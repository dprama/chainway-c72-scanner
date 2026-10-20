enum ScanKind { barcode, rfid }

class ScanRecord {
  const ScanRecord({
    required this.kind,
    required this.value,
    required this.format,
    required this.count,
    required this.firstSeen,
    required this.lastSeen,
    this.rssi,
  });
  final ScanKind kind;
  final String value;
  final String format;
  final int count;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final String? rssi;
  String get key => '${kind.name}:$value';

  factory ScanRecord.fromMap(Map<Object?, Object?> data) {
    final value = data['value'];
    final count = data['count'];
    final first = data['firstSeen'];
    final last = data['lastSeen'];
    if (value is! String ||
        value.isEmpty ||
        count is! int ||
        count < 1 ||
        first is! int ||
        last is! int ||
        first > last) {
      throw const FormatException('Invalid scan record');
    }
    return ScanRecord(
      kind: ScanKind.values.byName(data['kind'] as String),
      value: value,
      format: data['format'] as String? ?? '',
      count: count,
      firstSeen: DateTime.fromMillisecondsSinceEpoch(first),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(last),
      rssi: data['rssi'] as String?,
    );
  }

  ScanRecord merge(ScanRecord other) {
    if (other.key != key) throw ArgumentError('Cannot merge different codes');
    final newer = other.lastSeen.isBefore(lastSeen) ? this : other;
    return ScanRecord(
      kind: kind,
      value: value,
      format: newer.format,
      count: count + other.count,
      firstSeen: firstSeen.isBefore(other.firstSeen)
          ? firstSeen
          : other.firstSeen,
      lastSeen: newer.lastSeen,
      rssi: newer.rssi ?? rssi,
    );
  }

  Map<String, Object?> toMap() => {
    'kind': kind.name,
    'value': value,
    'format': format,
    'count': count,
    'firstSeen': firstSeen.millisecondsSinceEpoch,
    'lastSeen': lastSeen.millisecondsSinceEpoch,
    'rssi': rssi,
  };
}

/// All cells are quoted. Prefix formula-looking text for spreadsheet-safe CSV.
String recordsToCsv(Iterable<ScanRecord> records) {
  String cell(Object? value) {
    var text = value?.toString() ?? '';
    if (RegExp(r'^[\s]*[=+\-@]').hasMatch(text) && value is! num) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  final rows = <List<Object?>>[
    [
      'type',
      'value',
      'format',
      'read_count',
      'first_seen_utc',
      'last_seen_utc',
      'rssi_dbm',
    ],
    for (final record in records)
      [
        record.kind.name,
        record.value,
        record.format,
        record.count,
        record.firstSeen.toUtc().toIso8601String(),
        record.lastSeen.toUtc().toIso8601String(),
        num.tryParse(record.rssi ?? '') ?? record.rssi,
      ],
  ];
  return '${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n';
}
