import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chainway_c72_scanner/main.dart';
import 'package:chainway_c72_scanner/scan_controller.dart';
import 'fake_scanner_port.dart';

// Optional visual check. Uses fonts bundled with the Flutter SDK.
void main() {
  const capture = bool.fromEnvironment('CAPTURE_PREVIEWS');
  testWidgets('render barcode, RFID, and history previews', (tester) async {
    await tester.runAsync(() async {
      final root = Platform.environment['FLUTTER_ROOT']!;
      final fonts = '$root/bin/cache/artifacts/material_fonts';
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '$fonts/materialicons-regular.otf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await icons.load();
      for (final family in [
        'sans-serif',
        'sans-serif-condensed',
        'monospace',
        'Roboto',
      ]) {
        final name = family == 'sans-serif-condensed'
            ? 'robotocondensed'
            : 'roboto';
        final loader = FontLoader(family)
          ..addFont(
            File(
              '$fonts/$name-regular.ttf',
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
      }
    });
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FakeScannerPort();
    await tester.pumpWidget(FieldScanApp(controller: ScanController(port)));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../docs/previews/barcode.png'),
    );
    await tester.tap(find.text('UHF RFID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start inventory'));
    await tester.pumpAndSettle();
    port.send({
      'type': 'reads',
      'items': [
        read(
          '300833B2DDD9014000000001',
          kind: 'rfid',
          count: 28,
          rssi: '-52.1',
        ),
        read(
          '300833B2DDD9014000000002',
          kind: 'rfid',
          count: 14,
          first: 2000,
          rssi: '-58.4',
        ),
        read(
          '300833B2DDD9014000000003',
          kind: 'rfid',
          count: 9,
          first: 3000,
          rssi: '-61.2',
        ),
      ],
    });
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../docs/previews/rfid.png'),
    );
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../docs/previews/history.png'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await port.close();
  }, skip: !capture);
}
