import 'package:flutter_test/flutter_test.dart';
import 'package:chainway_c72_scanner/scan_record.dart';
import 'fake_scanner_port.dart';

void main() {
  test('CSV escapes quotes, commas, line breaks, and formula input', () {
    final csv = recordsToCsv([
      ScanRecord.fromMap(read('a,"b"\nc')),
      ScanRecord.fromMap(read('=HYPERLINK("x")')),
      ScanRecord.fromMap(read('0000123')),
      ScanRecord.fromMap(read('3008AB', kind: 'rfid', rssi: '-55.7')),
    ]);
    expect(csv, contains('"a,""b""\nc"'));
    expect(
      csv,
      contains(
        '"'
        "'=HYPERLINK"
        '(""x"")"',
      ),
    );
    expect(csv, contains('"0000123"'));
    expect(csv, contains('"-55.7"'));
    expect(csv, contains('1970-01-01T00:00:01.000Z'));
    expect(csv.endsWith('\r\n'), isTrue);
  });
  test('out-of-order batches preserve earliest and latest timestamps', () {
    final latest = ScanRecord.fromMap(
      read('EPC', kind: 'rfid', first: 4000, last: 8000, rssi: '-50'),
    );
    final older = ScanRecord.fromMap(
      read('EPC', kind: 'rfid', first: 1000, last: 3000, rssi: '-70'),
    );
    final result = latest.merge(older);
    expect(result.count, 2);
    expect(result.firstSeen.millisecondsSinceEpoch, 1000);
    expect(result.lastSeen.millisecondsSinceEpoch, 8000);
    expect(result.rssi, '-50');
  });
  test(
    'empty identifiers, negative counts and reversed timestamps are rejected',
    () {
      expect(() => ScanRecord.fromMap(read('')), throwsFormatException);
      expect(
        () => ScanRecord.fromMap(read('A', count: -1)),
        throwsFormatException,
      );
      expect(
        () => ScanRecord.fromMap(read('A', first: 20, last: 10)),
        throwsFormatException,
      );
    },
  );
}
