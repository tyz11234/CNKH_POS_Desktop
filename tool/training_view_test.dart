import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/screens/training_page.dart';

void main() {
  testWidgets('packaged training screenshot loads and renders its measured arrow', (tester) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: SizedBox(width: 960,
        child: TrainingScreenshot(name: 'einvoice_credentials')))),
    )));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.renderObject<RenderImage>(find.byType(RawImage)).image, isNotNull);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter.runtimeType.toString() == '_Arrow'), findsOneWidget);
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/training-preview');
      await dir.create(recursive: true);
      await File('${dir.path}/training-arrow-check.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
