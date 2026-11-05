import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twink_android/native/app.dart';

class _Stripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0; x < size.width; x += 4) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), 0, 4, size.height),
        Paint()..color = x % 8 == 0 ? Colors.white : Colors.black,
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes old) => false;
}

void main() {
  testWidgets(
    'glass actually blurs the backdrop while keeping controls usable',
    (tester) async {
      tester.view.physicalSize = const Size(300, 140);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      const capture = Key('glass-proof');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: capture,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _Stripes()),
                Positioned(
                  left: 10,
                  top: 10,
                  width: 120,
                  height: 120,
                  child: NativeGlass(
                    kind: GlassKind.navigation,
                    blur: 16,
                    child: Tap(
                      onTap: () => taps++,
                      label: 'Glass button',
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Positioned(
                  left: 166,
                  top: 10,
                  width: 120,
                  height: 120,
                  child: NativeGlass(
                    kind: GlassKind.navigation,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final bytes = await tester.runAsync(() async {
        final picture = await boundary.toImage();
        final data = await picture.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      double contrast(Uint8List pixels, int x) {
        var sum = 0.0;
        for (var i = 0; i < 60; i++) {
          sum +=
              (pixels[(70 * 300 + x + i) * 4] -
                      pixels[(70 * 300 + x + i + 1) * 4])
                  .abs();
        }
        return sum / 60;
      }

      expect(
        contrast(bytes!, 35),
        lessThan(contrast(bytes, 191) * .25),
        reason: 'A painted gradient alone cannot soften background stripes.',
      );
      await tester.tap(find.bySemanticsLabel('Glass button'));
      await tester.pump();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, false);
    },
  );
}
