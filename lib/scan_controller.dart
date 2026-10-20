import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'scan_record.dart';
import 'scanner_port.dart';

class ScanController extends ChangeNotifier with WidgetsBindingObserver {
  ScanController(this.port);
  final ScannerPort port;
  final Map<String, ScanRecord> _records = {};
  final Map<ScanKind, Map<String, ScanRecord>> _recent = {
    for (final kind in ScanKind.values) kind: {},
  };
  final Map<ScanKind, int> _totals = {
    for (final kind in ScanKind.values) kind: 0,
  };
  StreamSubscription<Object?>? _subscription;
  Timer? _saveTimer;
  Future<void> _saveTail = Future.value();
  bool _disposed = false;
  bool _storageBlocked = false;
  bool get storageBlocked => _storageBlocked;
  bool loading = true;
  bool busy = false;
  bool exporting = false;
  bool ready = false;
  bool scanning = false;
  bool sound = true;
  String state = 'idle';
  String? error;
  String? notice;
  ScanKind kind = ScanKind.barcode;
  int tab = 0;
  int? power;
  int? region;
  Map<Object?, Object?> device = {};
  ScanRecord? latest;

  int total(ScanKind kind) => _totals[kind]!;
  int unique(ScanKind kind) =>
      _records.values.where((r) => r.kind == kind).length;
  int get recordCount => _records.length;
  List<ScanRecord> recent() => _recent[kind]!.values.toList().reversed.toList();
  List<ScanRecord> history({String query = '', ScanKind? filter}) {
    final text = query.toLowerCase();
    return _records.values
        .where(
          (r) =>
              (filter == null || r.kind == filter) &&
              (r.value.toLowerCase().contains(text) ||
                  r.format.toLowerCase().contains(text)),
        )
        .toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  }

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _subscription = port.events.listen(
      _event,
      onError: (Object e) {
        error = 'Scanner connection lost: ${_message(e)}';
        ready = false;
        scanning = false;
        _notify();
      },
    );
    try {
      final raw = await port.invoke<String>('loadState');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['version'] != 1) {
          throw const FormatException('Unsupported history version');
        }
        // Parse everything before modifying state; never replace damaged history automatically.
        final records = (data['records'] as List)
            .map(
              (e) => ScanRecord.fromMap(Map<Object?, Object?>.from(e as Map)),
            )
            .toList();
        kind = ScanKind.values.byName(data['mode'] as String);
        sound = data['sound'] as bool;
        for (final record in records) {
          _add(record);
        }
        if (_records.isNotEmpty) {
          final ordered = history();
          for (final type in ScanKind.values) {
            _recent[type]!.clear();
            for (final r
                in ordered
                    .where((r) => r.kind == type)
                    .take(8)
                    .toList()
                    .reversed) {
              _recent[type]![r.key] = r;
            }
          }
          latest = ordered.where((r) => r.kind == kind).firstOrNull;
        }
      }
    } catch (e) {
      _storageBlocked = true;
      error =
          'Saved history could not be read. Clear history to reset local storage. ${_message(e)}';
    }
    try {
      device = await port.invoke<Map<Object?, Object?>>('deviceInfo') ?? {};
    } catch (_) {
      /* Device details are optional. */
    }
    loading = false;
    _notify();
    await _command('setSound', {'enabled': sound});
    if (!_storageBlocked) {
      await reconnect();
    } else {
      await _command('setEnabled', {'enabled': false});
    }
  }

  void _add(ScanRecord incoming) {
    final record = _records[incoming.key]?.merge(incoming) ?? incoming;
    _records[incoming.key] = record;
    _totals[record.kind] = _totals[record.kind]! + incoming.count;
    final recent = _recent[record.kind]!;
    recent.remove(record.key);
    recent[record.key] = record;
    if (recent.length > 8) recent.remove(recent.keys.first);
    if (record.kind == kind &&
        (latest == null || !record.lastSeen.isBefore(latest!.lastSeen))) {
      latest = record;
    }
  }

  void _event(Object? raw) {
    if (_disposed || raw is! Map) return;
    switch (raw['type']) {
      case 'reads':
        try {
          for (final item in raw['items'] as List) {
            _add(ScanRecord.fromMap(Map<Object?, Object?>.from(item as Map)));
          }
          notice = null;
          _scheduleSave();
        } catch (e) {
          error = 'A scanner result could not be read: ${_message(e)}';
        }
      case 'status':
        if (raw['mode'] != kind.name) return;
        state = raw['state'] as String? ?? 'idle';
        ready = raw['ready'] == true;
        scanning = raw['scanning'] == true;
        power = raw['power'] as int?;
        region = raw['region'] as int?;
        if (state == 'ready') notice = null;
        if (!scanning && !loading) unawaited(save());
      case 'error':
        error = raw['message'] as String?;
      case 'notice':
        notice = raw['message'] as String?;
    }
    _notify();
  }

  Future<bool> _command(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await port.invoke<void>(method, arguments);
      return true;
    } catch (e) {
      error = _message(e);
      _notify();
      return false;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || loading || _disposed) return;
    busy = true;
    notice = null;
    _notify();
    try {
      await action();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> beginEpcWriter() async {
    var opened = false;
    await _run(() async {
      if (_storageBlocked || kind != ScanKind.rfid || !ready) {
        error = 'Connect UHF before opening the EPC writer.';
        return;
      }
      opened = await _command('beginEpcWrite');
    });
    return opened;
  }

  Future<void> endEpcWriter() async {
    await _command('endEpcWrite');
  }

  Future<void> reconnect() => _run(() async {
    if (_storageBlocked) return;
    error = null;
    await _command('open', {'mode': kind.name});
  });

  Future<void> changeMode(ScanKind value) => _run(() async {
    if (_storageBlocked || value == kind) return;
    kind = value;
    latest = history(filter: value).firstOrNull;
    ready = false;
    scanning = false;
    error = null;
    await _command('open', {'mode': kind.name});
    await save();
  });

  Future<void> toggleScan() => _run(() async {
    if (_storageBlocked) return;
    error = null;
    await _command(scanning ? 'stop' : 'start');
  });

  Future<void> changeTab(int value) => _run(() async {
    tab = value;
    await _command('setEnabled', {'enabled': value == 0 && !_storageBlocked});
    await save();
  });

  Future<void> setPower(int value) => _run(() async {
    error = null;
    await _command('setPower', {'power': value});
  });

  Future<void> setSound(bool value) async {
    if (await _command('setSound', {'enabled': value})) {
      sound = value;
      await save();
      _notify();
    }
  }

  Future<void> clearHistory() => _run(() async {
    await _command('setEnabled', {'enabled': false});
    _records.clear();
    for (final type in ScanKind.values) {
      _recent[type]!.clear();
      _totals[type] = 0;
    }
    latest = null;
    error = null;
    _storageBlocked = false;
    await save();
    await _command('setEnabled', {'enabled': tab == 0});
    if (tab == 0) await _command('open', {'mode': kind.name});
  });

  void dismissError() {
    if (!_storageBlocked) error = null;
    _notify();
  }

  void _scheduleSave() {
    _saveTimer ??= Timer(const Duration(seconds: 1), () {
      _saveTimer = null;
      unawaited(save());
    });
  }

  Future<void> save() {
    if (loading || _storageBlocked || _disposed) return Future.value();
    _saveTimer?.cancel();
    _saveTimer = null;
    final json = jsonEncode({
      'version': 1,
      'mode': kind.name,
      'sound': sound,
      'records': _records.values.map((r) => r.toMap()).toList(),
    });
    _saveTail = _saveTail.then((_) async {
      try {
        await port.invoke<void>('saveState', {'json': json});
      } catch (e) {
        error = 'Could not save history: ${_message(e)}';
        _notify();
      }
    });
    return _saveTail;
  }

  Future<String?> export({ScanKind? filter, String query = ''}) async {
    if (exporting) return null;
    final records = history(filter: filter, query: query);
    if (records.isEmpty) return 'No matching records to export';
    exporting = true;
    _notify();
    try {
      // Stop before taking the export snapshot and opening Android's file picker.
      await port.invoke<void>('stop');
      await save();
      final stamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final saved = await port.invoke<bool>('exportCsv', {
        'name': 'c72-${filter?.name ?? 'all'}-$stamp.csv',
        'csv': recordsToCsv(history(filter: filter, query: query)),
      });
      return saved == true ? 'CSV saved' : 'Export cancelled';
    } catch (e) {
      error = 'Could not export CSV: ${_message(e)}';
      return null;
    } finally {
      exporting = false;
      _notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(save());
  }

  String _message(Object error) => error is PlatformException
      ? error.message ?? error.code
      : error.toString();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    unawaited(_subscription?.cancel());
    _disposed = true;
    super.dispose();
  }
}
