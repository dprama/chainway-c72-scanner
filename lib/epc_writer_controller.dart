import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'scanner_port.dart';

String normalizeEpcHex(String value) {
  var result = value.replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (result.startsWith('0X')) result = result.substring(2);
  return result;
}

String? validateEpc(String value) {
  final epc = normalizeEpcHex(value);
  if (epc.isEmpty) return 'Enter an EPC in hexadecimal.';
  if (!RegExp(r'^[0-9A-F]+$').hasMatch(epc)) {
    return 'Use hexadecimal characters 0–9 and A–F.';
  }
  if (epc.length % 4 != 0) {
    return 'Use complete 16-bit words: 4, 8, 12… hex characters.';
  }
  if (epc.length > 124) return 'Use at most 124 hex characters (31 words).';
  return null;
}

String? validateAccessPassword(String value) =>
    RegExp(r'^[0-9A-F]{8}$').hasMatch(normalizeEpcHex(value))
    ? null
    : 'Use exactly 8 hexadecimal characters.';

class EpcInspection {
  const EpcInspection({required this.token, required this.epc, this.tid});
  factory EpcInspection.fromMap(Map<Object?, Object?> map) => EpcInspection(
    token: map['token'] as String,
    epc: map['epc'] as String,
    tid: map['tid'] as String?,
  );
  final String token;
  final String epc;
  final String? tid;
}

class EpcWriteResult {
  const EpcWriteResult({
    required this.oldEpc,
    required this.newEpc,
    required this.verified,
    required this.sdkConfirmed,
    required this.message,
    this.observedEpc,
  });
  factory EpcWriteResult.fromMap(Map<Object?, Object?> map) => EpcWriteResult(
    oldEpc: map['oldEpc'] as String,
    newEpc: map['newEpc'] as String,
    verified: map['verified'] == true,
    sdkConfirmed: map['sdkConfirmed'] == true,
    message: map['message'] as String,
    observedEpc: map['observedEpc'] as String?,
  );
  final String oldEpc;
  final String newEpc;
  final bool verified;
  final bool sdkConfirmed;
  final String message;
  final String? observedEpc;
}

class EpcWriterController extends ChangeNotifier with WidgetsBindingObserver {
  EpcWriterController(this.port) {
    WidgetsBinding.instance.addObserver(this);
  }
  final ScannerPort port;
  bool busy = false;
  bool writing = false;
  bool _disposed = false;
  int _inspectionEpoch = 0;
  String? error;
  EpcInspection? inspection;
  EpcWriteResult? result;

  void invalidate() {
    _inspectionEpoch++;
    inspection = null;
    result = null;
    error = null;
    _notify();
  }

  Future<void> inspect(String currentEpc, String password) async {
    if (busy || _disposed) return;
    final epoch = ++_inspectionEpoch;
    error = validateEpc(currentEpc) ?? validateAccessPassword(password);
    inspection = null;
    result = null;
    if (error != null) {
      _notify();
      return;
    }
    busy = true;
    _notify();
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (_disposed || epoch != _inspectionEpoch) return;
        try {
          final map = await port.invoke<Map<Object?, Object?>>('inspectEpc', {
            'epc': normalizeEpcHex(currentEpc),
            'password': normalizeEpcHex(password),
          });
          if (_disposed || epoch != _inspectionEpoch) return;
          if (map == null) {
            throw StateError('The reader returned no tag information.');
          }
          inspection = EpcInspection.fromMap(map);
          break;
        } on PlatformException catch (e) {
          // Only retry read-only tag-response failures. Writes are never retried.
          if (e.code != 'EPC_READ' || attempt == 2) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    } catch (e) {
      if (!_disposed && epoch == _inspectionEpoch) error = _message(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> write(String newEpc) async {
    if (busy) return;
    final target = inspection;
    error = validateEpc(newEpc);
    final epc = normalizeEpcHex(newEpc);
    if (target == null) error = 'Read the selected tag before writing.';
    if (target?.epc == epc) {
      error = 'The new EPC must differ from the current EPC.';
    }
    if (error != null) {
      _notify();
      return;
    }
    busy = true;
    writing = true;
    result = null;
    inspection = null; // One reviewed inspection authorizes one write attempt.
    _notify();
    try {
      final map = await port.invoke<Map<Object?, Object?>>('writeEpc', {
        'token': target!.token,
        'newEpc': epc,
      });
      if (map == null) {
        throw StateError(
          'Write outcome is unknown. Inspect the tag before retrying.',
        );
      }
      result = EpcWriteResult.fromMap(map);
      if (!result!.verified) error = result!.message;
    } catch (e) {
      error = _message(e);
    } finally {
      busy = false;
      writing = false;
      _notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _inspectionEpoch++;
      inspection = null;
      _notify();
    }
  }

  String _message(Object e) =>
      e is PlatformException ? e.message ?? e.code : e.toString();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _inspectionEpoch++;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
