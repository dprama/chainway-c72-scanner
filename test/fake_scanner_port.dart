import 'dart:async';
import 'package:flutter/services.dart';
import 'package:chainway_c72_scanner/scanner_port.dart';

class FakeScannerPort implements ScannerPort {
  final stream = StreamController<Object?>.broadcast(sync: true);
  final calls = <(String, Map<String, Object?>?)>[];
  String? saved;
  String? failMethod;
  String mode = 'barcode';
  bool enabled = true;
  bool writeVerified = true;
  int inspectionFailures = 0;
  String inspectionErrorCode = 'EPC_READ';
  @override
  Stream<Object?> get events => stream.stream;
  void send(Map<String, Object?> data) => stream.add(data);
  void status({bool ready = true, bool scanning = false}) => send({
    'type': 'status',
    'mode': mode,
    'state': scanning
        ? 'scanning'
        : ready
        ? 'ready'
        : 'paused',
    'ready': ready,
    'scanning': scanning,
    'power': mode == 'rfid' && ready ? 20 : null,
    'region': mode == 'rfid' ? 8 : null,
  });
  @override
  Future<T?> invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    calls.add((method, arguments));
    if (method == failMethod) throw StateError('Test failure for $method');
    Object? result;
    switch (method) {
      case 'loadState':
        result = saved;
      case 'saveState':
        saved = arguments!['json'] as String;
      case 'deviceInfo':
        result = {'manufacturer': 'Chainway', 'model': 'C72', 'android': '13'};
      case 'open':
        mode = arguments!['mode'] as String;
        status(ready: enabled);
      case 'start':
        status(scanning: true);
      case 'stop':
        status(ready: enabled);
      case 'setEnabled':
        enabled = arguments!['enabled'] == true;
        status(ready: enabled);
      case 'inspectEpc':
        if (inspectionFailures > 0) {
          inspectionFailures--;
          throw PlatformException(
            code: inspectionErrorCode,
            message: 'No matching tag response (SDK code 65535).',
          );
        }
        result = {
          'token': 'test-inspection',
          'epc': arguments!['epc'],
          'tid': 'E28012340000000000000001',
        };
      case 'writeEpc':
        result = {
          'oldEpc': '0000ABCD1234',
          'newEpc': arguments!['newEpc'],
          'verified': writeVerified,
          'sdkConfirmed': true,
          'observedEpc': writeVerified ? arguments['newEpc'] : null,
          'message': writeVerified
              ? 'EPC written and read-back verified.'
              : 'Read-back was not verified.',
        };
      case 'exportCsv':
        result = true;
    }
    return result as T?;
  }

  Future<void> close() => stream.close();
}

Map<String, Object?> read(
  String value, {
  String kind = 'barcode',
  int count = 1,
  int first = 1000,
  int? last,
  String? rssi,
}) => {
  'kind': kind,
  'value': value,
  'format': kind == 'barcode' ? 'CODE128' : 'EPC',
  'count': count,
  'firstSeen': first,
  'lastSeen': last ?? first,
  'rssi': rssi,
};
