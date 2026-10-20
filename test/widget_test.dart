import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chainway_c72_scanner/main.dart';
import 'package:chainway_c72_scanner/scan_controller.dart';
import 'fake_scanner_port.dart';

void main() {
  testWidgets('barcode, RFID, history and settings fit a compact C72 screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FakeScannerPort();
    await tester.pumpWidget(FieldScanApp(controller: ScanController(port)));
    await tester.pumpAndSettle();
    expect(find.text('Scan barcode'), findsOneWidget);
    await tester.tap(find.text('UHF RFID'));
    await tester.pumpAndSettle();
    expect(find.text('Start inventory'), findsOneWidget);
    await tester.tap(find.text('Start inventory'));
    await tester.pumpAndSettle();
    expect(find.text('Stop inventory'), findsOneWidget);
    port.send({
      'type': 'reads',
      'items': [
        read(
          '300833B2DDD9014000000001',
          kind: 'rfid',
          count: 28,
          rssi: '-52.1',
        ),
      ],
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 unique records'), findsOneWidget);
    expect(find.text('300833B2DDD9014000000001'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Read feedback'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await port.close();
  });

  testWidgets('large text and scanner errors remain usable at 320 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FakeScannerPort();
    await tester.pumpWidget(FieldScanApp(controller: ScanController(port)));
    await tester.pumpAndSettle();
    port.send({
      'type': 'error',
      'message': 'Close other scanner apps and reconnect.',
    });
    await tester.pumpAndSettle();
    expect(find.text('Scan barcode'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await port.close();
  });
}
