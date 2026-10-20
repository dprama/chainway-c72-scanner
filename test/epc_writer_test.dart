import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:chainway_c72_scanner/epc_writer_controller.dart';
import 'fake_scanner_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeScannerPort port;
  late EpcWriterController c;
  setUp(() {
    port = FakeScannerPort();
    c = EpcWriterController(port);
  });
  tearDown(() async {
    c.dispose();
    await port.close();
  });

  test(
    'pasted EPC normalizes spaces, case and 0x prefix without losing zeros',
    () {
      expect(normalizeEpcHex(' 0x0000 abcd\n1234 '), '0000ABCD1234');
      expect(validateEpc('0000 abcd 1234'), isNull);
      expect(validateEpc(''), isNotNull);
      expect(validateEpc('ABC'), isNotNull);
      expect(validateEpc('XYZ0'), isNotNull);
      expect(validateEpc('A' * 128), isNotNull);
      expect(validateAccessPassword('00000000'), isNull);
      expect(validateAccessPassword('0000'), isNotNull);
    },
  );

  test('inspection is read-only and canonicalizes target/password', () async {
    await c.inspect('0x0000 abcd 1234', '00000000');
    expect(c.inspection!.epc, '0000ABCD1234');
    expect(port.calls.single.$1, 'inspectEpc');
    expect(port.calls.single.$2!['epc'], '0000ABCD1234');
    expect(port.calls.where((call) => call.$1 == 'writeEpc'), isEmpty);
  });

  test(
    'write requires inspection, complete words, and a different EPC',
    () async {
      await c.write('000011112222');
      expect(c.error, contains('Read'));
      expect(port.calls, isEmpty);
      await c.inspect('0000ABCD1234', '00000000');
      await c.write('0000ABCD1234');
      expect(c.error, contains('differ'));
      await c.write('123');
      expect(port.calls.where((call) => call.$1 == 'writeEpc'), isEmpty);
    },
  );

  test(
    'one inspection permits one write request with its native token',
    () async {
      await c.inspect('0000ABCD1234', '00000000');
      await c.write('0x0000 aaaa bbbb');
      final call = port.calls.last;
      expect(call.$1, 'writeEpc');
      expect(call.$2, {'token': 'test-inspection', 'newEpc': '0000AAAABBBB'});
      expect(c.result!.verified, isTrue);
      expect(c.inspection, isNull);
      await c.write('0000CCCCDDDD');
      expect(port.calls.where((call) => call.$1 == 'writeEpc').length, 1);
    },
  );

  test('unverified result never becomes success or triggers a retry', () async {
    port.writeVerified = false;
    await c.inspect('0000ABCD1234', '00000000');
    await c.write('0000AAAABBBB');
    expect(c.result!.verified, isFalse);
    expect(c.error, contains('not verified'));
    expect(c.inspection, isNull);
    expect(port.calls.where((call) => call.$1 == 'writeEpc').length, 1);
  });

  test('backgrounding invalidates inspection before a write', () async {
    await c.inspect('0000ABCD1234', '00000000');
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    await c.write('0000AAAABBBB');
    expect(port.calls.where((call) => call.$1 == 'writeEpc'), isEmpty);
  });

  test(
    'reader errors clear busy state and invalidate the attempted inspection',
    () async {
      await c.inspect('0000ABCD1234', '00000000');
      port.failMethod = 'writeEpc';
      await c.write('0000AAAABBBB');
      expect(c.error, contains('Test failure'));
      expect(c.busy, isFalse);
      expect(c.inspection, isNull);
    },
  );
  test(
    'transient read failures retry at most three times without writing',
    () async {
      port.inspectionFailures = 2;
      await c.inspect('0000ABCD1234', '00000000');
      expect(c.inspection?.epc, '0000ABCD1234');
      expect(c.error, isNull);
      expect(port.calls.where((call) => call.$1 == 'inspectEpc').length, 3);
      expect(port.calls.where((call) => call.$1 == 'writeEpc'), isEmpty);
    },
  );

  test(
    'persistent read failure stops after three attempts with no inspection',
    () async {
      port.inspectionFailures = 9;
      await c.inspect('0000ABCD1234', '00000000');
      expect(c.inspection, isNull);
      expect(c.busy, isFalse);
      expect(c.error, contains('65535'));
      expect(port.calls.where((call) => call.$1 == 'inspectEpc').length, 3);
      expect(port.calls.where((call) => call.$1 == 'writeEpc'), isEmpty);
    },
  );

  test('connection errors are not retried as tag response failures', () async {
    port.inspectionFailures = 9;
    port.inspectionErrorCode = 'EPC';
    await c.inspect('0000ABCD1234', '00000000');
    expect(c.inspection, isNull);
    expect(port.calls.length, 1);
  });

  test('backgrounding cancels pending read retries', () async {
    port.inspectionFailures = 9;
    final pending = c.inspect('0000ABCD1234', '00000000');
    await Future<void>.delayed(Duration.zero);
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    await pending;
    expect(c.inspection, isNull);
    expect(c.busy, isFalse);
    expect(port.calls.length, 1);
  });

  test('changing target cancels pending read retries', () async {
    port.inspectionFailures = 9;
    final pending = c.inspect('0000ABCD1234', '00000000');
    await Future<void>.delayed(Duration.zero);
    c.invalidate();
    await pending;
    expect(c.inspection, isNull);
    expect(port.calls.length, 1);
  });
}
