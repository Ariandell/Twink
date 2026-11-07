import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twink_android/native/app.dart';

void main() {
  const picture = 'assets/word-images/images/60911.webp';
  if (!File(picture).existsSync()) {
    test(
      'private sticker image fixtures are not installed',
      () {},
      skip: 'Install the private image pack to run sticker rendering tests.',
    );
    return;
  }
  testWidgets(
    'peel hides the lower image under intact paper and rounds the image itself',
    (tester) async {
      tester.view.physicalSize = const Size(340, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const key = Key('pixels');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: StickerDeck(
                contentId: 'one',
                images: const [picture],
                height: 320,
                onMotionStart: () {},
                onMotionEnd: () {},
                child: const ColoredBox(color: Color(0x11000000)),
              ),
            ),
          ),
        ),
      );
      final deck = find.byType(StickerDeck);
      await tester.runAsync(
        () => precacheImage(
          const ResizeImage(AssetImage(picture), width: 800),
          tester.element(deck),
        ),
      );
      await tester.pumpAndSettle();
      Future<List<int>> pixels() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        boundary.markNeedsPaint();
        await tester.pump();
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List().toList();
        }))!;
      }

      int red(List<int> data, int x, int y) => data[(y * 340 + x) * 4];
      final drag = await tester.startGesture(const Offset(8, 8));
      await drag.moveBy(const Offset(40, 40));
      await tester.pump();
      final partial = await pixels();
      expect(
        red(partial, 280, 260),
        lessThan(40),
        reason: 'The unpeeled paper must hide the white image underneath.',
      );
      expect(
        red(partial, 40, 40),
        greaterThan(180),
        reason: 'Only the peeled region reveals the image.',
      );
      await drag.moveBy(const Offset(150, 140));
      await drag.up();
      await tester.pumpAndSettle();
      final revealed = await pixels();
      expect(
        red(revealed, 18, 39),
        lessThan(40),
        reason: 'The image corner itself is clipped, including its letterbox inset.',
      );
      expect(red(revealed, 60, 70), greaterThan(180));
      expect(tester.takeException(), isNull);
    },
  );
  for (final corner in [
    const Offset(0, 0),
    const Offset(1, 0),
    const Offset(0, 1),
    const Offset(1, 1),
  ]) {
    testWidgets('peel from $corner; undo, several images, cycle to word', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0, starts = 0, ends = 0;
      const key = Key('deck');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: RepaintBoundary(
                key: key,
                child: StickerDeck(
                  contentId: 'one',
                  images: const [picture, picture],
                  height: 320,
                  onMotionStart: () => starts++,
                  onMotionEnd: () => ends++,
                  child: GestureDetector(
                    onTap: () => taps++,
                    child: const ColoredBox(
                      color: Color(0xff11131a),
                      child: Center(child: Text('WORD')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(StickerDeck));
      Offset point(Offset c) => Offset(
        rect.left + (c.dx == 0 ? 8 : rect.width - 8),
        rect.top + (c.dy == 0 ? 8 : rect.height - 8),
      );
      final direction = Offset(
        corner.dx == 0 ? 180 : -180,
        corner.dy == 0 ? 160 : -160,
      );
      await tester.tapAt(rect.center);
      await tester.pump();
      expect(taps, 1);
      final gesture = await tester.startGesture(point(corner));
      await gesture.moveBy(direction * .6);
      await tester.pump();
      if (const bool.fromEnvironment('CAPTURE_NATIVE') &&
          corner == Offset.zero) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        await tester.runAsync(() async {
          final img = await boundary.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          final f = File('../../native-qa/sticker-peel.png');
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(starts, ends);
      final oppositeCorner = Offset(1 - corner.dx, 1 - corner.dy);
      await tester.dragFrom(point(oppositeCorner), -direction);
      await tester.pumpAndSettle();
      expect(find.text('WORD'), findsOneWidget);
      expect(find.text('1 / 2'), findsNothing);
      await tester.dragFrom(point(corner), direction);
      await tester.pumpAndSettle();
      await tester.dragFrom(point(corner), direction);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.dragFrom(point(corner), direction);
      await tester.pumpAndSettle();
      expect(find.text('WORD'), findsOneWidget);
      expect(starts, ends);
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'short or cancelled corner pull stays on word; no images keeps tap',
    (tester) async {
      var taps = 0;
      Widget app(List<String> images) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 320,
            child: StickerDeck(
              contentId: 'one',
              images: images,
              height: 320,
              onMotionStart: () {},
              onMotionEnd: () {},
              child: GestureDetector(
                onTap: () => taps++,
                child: const ColoredBox(
                  color: Colors.black,
                  child: Center(child: Text('WORD')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app([picture]));
      await tester.pumpAndSettle();
      final g = await tester.startGesture(const Offset(8, 8));
      await g.moveBy(const Offset(45, 45));
      await tester.pump();
      await g.cancel();
      await tester.pumpAndSettle();
      expect(find.text('WORD'), findsOneWidget);
      await tester.pumpWidget(app([]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WORD'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
