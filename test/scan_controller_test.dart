import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chainway_c72_scanner/scan_controller.dart';
import 'package:chainway_c72_scanner/scan_record.dart';
import 'fake_scanner_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeScannerPort port;
  late ScanController c;
  setUp(() async {
    port = FakeScannerPort();
    c = ScanController(port);
    await c.initialize();
  });
  tearDown(() async {
    await c.save();
    c.dispose();
    await port.close();
  });

  test(
    'batch counts merge without losing leading zeros or read times',
    () async {
      port.send({
        'type': 'reads',
        'items': [read('000123', count: 3, first: 1000, last: 3000)],
      });
      port.send({
        'type': 'reads',
        'items': [read('000123', count: 2, first: 4000, last: 5000)],
      });
      expect(c.unique(ScanKind.barcode), 1);
      expect(c.total(ScanKind.barcode), 5);
      final r = c.history().single;
      expect(r.value, '000123');
      expect(r.firstSeen.millisecondsSinceEpoch, 1000);
      expect(r.lastSeen.millisecondsSinceEpoch, 5000);
      await c.save();
      expect((jsonDecode(port.saved!)['records'] as List).single['count'], 5);
    },
  );

  test('barcode and RFID with identical values remain separate', () async {
    port.send({
      'type': 'reads',
      'items': [
        read('123'),
        read('123', kind: 'rfid', count: 19, rssi: '-53.1'),
      ],
    });
    await c.changeMode(ScanKind.rfid);
    expect(c.recordCount, 2);
    expect(c.total(ScanKind.rfid), 19);
    expect(c.total(ScanKind.barcode), 1);
    expect(c.latest!.rssi, '-53.1');
    expect(c.history(filter: ScanKind.rfid).single.kind, ScanKind.rfid);
    // A delayed status from the previous engine cannot reset the selected engine.
    port.send({'type': 'status', 'mode': 'barcode', 'ready': false});
    expect(c.ready, isTrue);
  });

  test('saved history and feedback restore on a new controller', () async {
    port.send({
      'type': 'reads',
      'items': [read('A', kind: 'rfid', count: 7)],
    });
    await c.changeMode(ScanKind.rfid);
    await c.setSound(false);
    await c.save();
    final restoredPort = FakeScannerPort()..saved = port.saved;
    final restored = ScanController(restoredPort);
    await restored.initialize();
    expect(restored.kind, ScanKind.rfid);
    expect(restored.sound, isFalse);
    expect(restored.total(ScanKind.rfid), 7);
    expect(restored.latest!.value, 'A');
    restored.dispose();
    await restoredPort.close();
  });

  test('history filtering searches values and symbologies', () {
    port.send({
      'type': 'reads',
      'items': [read('ABC'), read('DEF', kind: 'rfid')],
    });
    expect(c.history(query: 'abc').single.value, 'ABC');
    expect(c.history(query: 'code128').single.value, 'ABC');
    expect(c.history(query: 'missing'), isEmpty);
  });

  test('export stops scanner and uses current filter', () async {
    port.send({
      'type': 'reads',
      'items': [read('ABC'), read('DEF', kind: 'rfid')],
    });
    expect(await c.export(filter: ScanKind.rfid), 'CSV saved');
    final export = port.calls.lastWhere((call) => call.$1 == 'exportCsv');
    final csv = export.$2!['csv'] as String;
    expect(csv, contains('"DEF"'));
    expect(csv, isNot(contains('"ABC"')));
    final exportIndex = port.calls.indexOf(export);
    expect(
      port.calls.take(exportIndex).any((call) => call.$1 == 'stop'),
      isTrue,
    );
  });

  test('scanner errors are visible and do not erase history', () async {
    port.send({
      'type': 'reads',
      'items': [read('ABC')],
    });
    port.failMethod = 'start';
    await c.toggleScan();
    expect(c.error, contains('Test failure'));
    expect(c.busy, isFalse);
    expect(c.recordCount, 1);
  });

  test('clear removes both kinds and persists the empty history', () async {
    port.send({
      'type': 'reads',
      'items': [read('A'), read('B', kind: 'rfid')],
    });
    await c.clearHistory();
    expect(c.recordCount, 0);
    expect(c.total(ScanKind.rfid), 0);
    expect(c.latest, isNull);
    expect(jsonDecode(port.saved!)['records'], isEmpty);
  });

  test('unreadable history is preserved until explicitly cleared', () async {
    final brokenPort = FakeScannerPort()..saved = '{broken';
    final broken = ScanController(brokenPort);
    await broken.initialize();
    expect(broken.storageBlocked, isTrue);
    expect(brokenPort.enabled, isFalse);
    await broken.save();
    expect(brokenPort.saved, '{broken');
    await broken.clearHistory();
    expect(broken.storageBlocked, isFalse);
    expect(jsonDecode(brokenPort.saved!)['records'], isEmpty);
    broken.dispose();
    await brokenPort.close();
  });
}
