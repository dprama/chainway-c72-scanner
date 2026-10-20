import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chainway_c72_scanner/epc_writer_page.dart';
import 'fake_scanner_port.dart';

void main() {
  testWidgets(
    'paste and inspection do not write; cancelling review leaves tag unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => call.method == 'Clipboard.getData'
                ? {'text': '0x0000 aaaa bbbb'}
                : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final port = FakeScannerPort();
      await tester.pumpWidget(
        MaterialApp(
          home: EpcWriterPage(port: port, initialEpc: '0000ABCD1234'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Read selected tag'));
      await tester.tap(find.text('Read selected tag'));
      await tester.pumpAndSettle();
      expect(find.text('Tag found'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Paste new EPC'));
      await tester.tap(find.byTooltip('Paste new EPC'));
      await tester.pumpAndSettle();
      expect(find.text('0000AAAABBBB'), findsOneWidget);
      await tester.ensureVisible(find.text('Review EPC write'));
      await tester.tap(find.text('Review EPC write'));
      await tester.pumpAndSettle();
      expect(find.text('Write this EPC?'), findsOneWidget);
      expect(port.calls.where((call) => call.$1 == 'writeEpc'), isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(port.calls.where((call) => call.$1 == 'writeEpc'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await port.close();
    },
  );
}
