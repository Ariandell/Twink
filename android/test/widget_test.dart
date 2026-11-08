import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twink_android/domain.dart';
import 'package:twink_android/dwds_dictionary.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures/dwds_article.dart';

import 'package:twink_android/word_metrics.dart';
import 'package:twink_android/native/app.dart';
import 'package:twink_android/repository.dart';

class _DelayedProgressStore extends TwinkStore {
  Completer<void>? pending;
  @override
  Future<void> progress(String kind, String id, Json? p) async {
    await pending?.future;
    await super.progress(kind, id, p);
  }
}

class _DelayedTimeStore extends TwinkStore {
  Completer<void>? pendingTime;
  final savedTimes = <int>[];
  @override
  Future<void> addTime(int seconds) async {
    await pendingTime?.future;
    savedTimes.add(seconds);
    await super.addTime(seconds);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = Key('capture');
  Future<(TwinkStore, NativePreferences)> launch(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    int tab = 0,
    bool signedIn = true,
    TwinkStore? suppliedStore,
    DwdsDictionary? dictionary,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final weight in ['Regular']) {
      await (FontLoader('Roboto')..addFont(
            rootBundle.load('assets/fonts/roboto-${weight.toLowerCase()}.ttf'),
          ))
          .load();
    }
    await (FontLoader(
      'Outfit',
    )..addFont(rootBundle.load('assets/fonts/outfit-variable.ttf'))).load();
    await tester.runAsync(StickerDeck.preloadPictures);
    await tester.runAsync(DwdsFrequencyRepository.preload);
    await tester.runAsync(DwdsDictionary.preload);
    await tester.runAsync(DwdsDictionary.known);
    final store = (suppliedStore ?? TwinkStore())..startDemo();
    store.demo = signedIn;
    store.data = asMap(
      jsonDecode(File('test/fixtures/web-demo.json').readAsStringSync()),
    );
    store.data!['settings'] = {
      'study': {...originalSettings, 'audio': false},
    };
    for (final kind in ['words', 'idioms']) {
      for (final w in asMap(store.data![kind]).values) {
        asMap(w)['progress_global']['nextDate'] = 0;
        w['nextDate'] = 0;
      }
    }
    final prefs = NativePreferences(persistent: false)
      ..values['dwdsFrequency'] = asMap(
        jsonDecode(File('assets/data/dwds-frequency.json').readAsStringSync()),
      )
      ..values['tab'] = tab
      ..values['session-words-all'] = {
        'ids': ['1', '2', '4'],
        'index': 0,
      };
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NativeTwinkApp(
          store: store,
          preferences: prefs,
          dictionary: dictionary,
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      store.dispose();
      prefs.dispose();
    });
    return (store, prefs);
  }

  Future<void> screenshot(
    WidgetTester tester,
    String name, {
    bool settle = true,
  }) async {
    if (!const bool.fromEnvironment('CAPTURE_NATIVE')) return;
    if (settle) await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(capture),
    );
    // Record the full scene at the same animation time, including retained tabs.
    boundary.markNeedsPaint();
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../../native-qa/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> tapNav(WidgetTester tester, String name) async {
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == name).last,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'native navigation, dictionary search and editor persist changes',
    (tester) async {
      final (store, _) = await launch(tester);
      expect(find.text('MASTERY LEVEL'), findsOneWidget);
      await screenshot(tester, 'profile');
      await tapNav(tester, 'Словарь');
      await screenshot(tester, 'dictionary');
      await tester.enterText(find.byType(TextField).first, 'Augenblick');
      await tester.pumpAndSettle();
      expect(find.text('der Augenblick'), findsOneWidget);
      expect(find.text('entdecken'), findsNothing);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Square && w.icon == 'edit').first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(1),
        'Измененный перевод',
      );
      await tester.tap(
        find.byWidgetPredicate((w) => w is Square && w.icon == 'check'),
      );
      await tester.pumpAndSettle();
      expect(
        store.words.firstWhere(
          (w) => w['word'] == 'der Augenblick',
        )['translation'],
        'Измененный перевод',
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final fail in [false, true]) {
    testWidgets('next card appears before network save; failure=$fail', (
      tester,
    ) async {
      final delayed = _DelayedProgressStore();
      final (store, prefs) = await launch(
        tester,
        tab: 1,
        suppliedStore: delayed,
      );
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      final before = jsonEncode(store.words);
      final firstIds = List.of(
        (prefs.values['session-words-all'] as Map)['ids'] as List,
      );
      delayed.pending = Completer<void>();
      final rate = find.byWidgetPredicate(
        (w) => w is Tap && w.label == ratingNames[2],
      );
      await tester.tap(rate);
      await tester.pump();
      expect(find.text('entdecken').hitTestable(), findsOneWidget);
      expect(jsonEncode(store.words), before);
      await tester.tap(rate);
      await tester.pump();
      expect(find.text('entdecken').hitTestable(), findsOneWidget);
      expect((prefs.values['session-words-all'] as Map)['ids'], firstIds);
      expect(
        identical(tester.widget<MaterialApp>(find.byType(MaterialApp)), app),
        true,
      );
      // Reading/flipping the next word is allowed while its predecessor saves.
      await tester.tap(card);
      await tester.pumpAndSettle();
      final nextTranslation = store.words
          .firstWhere((w) => w['id'] == '2')['translation']
          .toString();
      expect(find.text(nextTranslation).hitTestable(), findsOneWidget);
      if (fail) {
        delayed.pending!.completeError(Exception('offline'));
      } else {
        delayed.pending!.complete();
      }
      await tester.pumpAndSettle();
      if (fail) {
        expect(find.text('der Augenblick').hitTestable(), findsOneWidget);
        expect(jsonEncode(store.words), before);
        expect(
          find.text('Не удалось сохранить оценку. Повторите попытку.'),
          findsOneWidget,
        );
      } else {
        expect(jsonEncode(store.words), isNot(before));
        expect((prefs.values['session-words-all'] as Map)['ids'], ['2', '4']);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'rating ACK during return flip does not rebuild faces or notify background screens',
    (tester) async {
      final delayed = _DelayedProgressStore();
      final (store, _) = await launch(tester, tab: 1, suppliedStore: delayed);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      await tester.tap(card);
      await tester.pumpAndSettle();
      var notifications = 0;
      store.addListener(() => notifications++);
      delayed.pending = Completer<void>();
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == ratingNames[2]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final nextWord = tester.widget<Text>(
        find.text('entdecken', skipOffstage: false),
      );
      final previousTranslation = tester.widget<Text>(
        find.text('мгновение, момент'),
      );
      delayed.pending!.complete();
      await tester.pump();
      expect(notifications, 0);
      expect(
        identical(
          tester.widget<Text>(find.text('entdecken', skipOffstage: false)),
          nextWord,
        ),
        true,
      );
      expect(
        identical(
          tester.widget<Text>(find.text('мгновение, момент')),
          previousTranslation,
        ),
        true,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(notifications, 0);
      expect(
        identical(
          tester.widget<Text>(find.text('entdecken', skipOffstage: false)),
          nextWord,
        ),
        true,
      );
      await tester.pumpAndSettle();
      expect(notifications, 1);
      expect(
        find.text('entdecken', skipOffstage: false).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'bundled pictures peel inside the study card and return to its word',
    (tester) async {
      final (store, _) = await launch(tester, tab: 1);
      await store.patch({
        'words/1/word': 'das Wochenende, die Wochenenden',
        'words/1/translation': 'выходные',
      });
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      final deck = find.byType(StickerDeck);
      expect(tester.widget<StickerDeck>(deck).images, isNotEmpty);
      await tester.runAsync(
        () => precacheImage(
          ResizeImage(
            AssetImage(tester.widget<StickerDeck>(deck).images.first),
            width: 800,
          ),
          tester.element(deck),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(deck);
      final drag = await tester.startGesture(
        rect.topLeft + const Offset(12, 12),
      );
      await drag.moveBy(const Offset(140, 120));
      await tester.pump();
      await screenshot(tester, 'sticker-study-peel', settle: false);
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.byType(NativeStudyPage), findsOneWidget);
      await tester.dragFrom(
        rect.bottomRight - const Offset(12, 12),
        const Offset(-180, -160),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('das Wochenende, die Wochenenden').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    skip: !File('assets/word-images/images/60911.webp').existsSync(),
  );
  for (final screen in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets(
      'study page has no outer scroll and retains 0.3.1 card size at $screen',
      (tester) async {
        await launch(tester, tab: 1, size: screen);
        await tester.tap(
          find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
        );
        await tester.pumpAndSettle();
        final card = find.byWidgetPredicate(
          (w) => w is Tap && w.label == 'Перевернуть карточку',
        );
        expect(tester.getSize(card).height, 280);
        expect(tester.getRect(card).height, closeTo(280, .01));
        expect(
          find.ancestor(of: card, matching: find.byType(Scrollable)),
          findsNothing,
        );
        for (final rating in ratingNames.skip(1)) {
          final button = find.byWidgetPredicate(
            (w) => w is Tap && w.label == rating,
          );
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.getBottomLeft(button).dy, lessThan(screen.height - 68));
        }
        final rect = tester.getRect(card);
        await tester.dragFrom(const Offset(160, 65), const Offset(0, -70));
        await tester.pumpAndSettle();
        expect(tester.getRect(card), rect);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'legacy and current font selection saves, cancels and updates card text',
    (tester) async {
      final (store, prefs) = await launch(tester, tab: 1);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      Future<void> choose(String title, bool save) async {
        await tester.tap(
          find.byWidgetPredicate((w) => w is Square && w.icon == 'settings'),
        );
        await tester.pumpAndSettle();
        final selector = find.byKey(const ValueKey('session-font-choice'));
        await tester.ensureVisible(selector);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: selector,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(title).last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is Square && w.icon == (save ? 'check' : 'close'),
          ),
        );
        await tester.pumpAndSettle();
      }

      await choose('Roboto · версия 0.3.1', false);
      expect(prefs.fontFamily, 'Outfit');
      await choose('Roboto · версия 0.3.1', true);
      expect(prefs.fontFamily, 'Roboto');
      expect(
        tester
            .widget<Text>(find.text('der Augenblick'))
            .textSpan!
            .style!
            .fontFamily,
        'Roboto',
      );
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .textTheme
            .bodyMedium!
            .fontFamily,
        'Roboto',
      );
      await screenshot(tester, 'legacy-font-card');
      await choose('Outfit · текущая версия', true);
      expect(prefs.fontFamily, 'Outfit');
      expect(
        tester
            .widget<Text>(find.text('der Augenblick'))
            .textSpan!
            .style!
            .fontFamily,
        'Outfit',
      );
      expect(store.settings['firstSide'], 'word');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'experimental metrics layouts combine progress and keep fixed cards',
    (tester) async {
      final (store, prefs) = await launch(tester, tab: 1);
      await store.patch({
        'words/4/progress_global/recentRatings': [2, 3, 4, 5],
        'words/4/progress_global/excellentStreak': 4.5,
      });
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      for (final rating in [2, 5]) {
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is Tap && w.label == ratingNames[rating],
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('sich erinnern'), findsOneWidget);
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      final cardSize = tester.getSize(card);
      for (final variant in [
        ('Капсула над навигацией', 'ribbon'),
        ('Три плитки', 'tiles'),
        ('Под карточкой', 'underCard'),
      ]) {
        await tester.tap(find.byTooltip('Вариант нижней панели'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(variant.$1));
        await tester.pumpAndSettle();
        expect(tester.getSize(card), cardSize);
        expect(tester.getRect(card).height, 280);
        expect(
          find.byKey(const ValueKey('session-integrated-progress')),
          findsOneWidget,
        );
        expect(
          find.ancestor(of: card, matching: find.byType(Scrollable)),
          findsNothing,
        );
        expect(
          find.byTooltip('Частотность DWDS').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await screenshot(tester, 'metrics-${variant.$2}');
      }
      expect(prefs.values['studyMetricsLayout'], 'underCard');
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Tap && w.label == 'Частотность DWDS',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Ступень 5 из 7'), findsOneWidget);
      Navigator.of(tester.element(find.text('Понятно'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Выйти'));
      await tester.pumpAndSettle();
      expect(find.text('entdecken'), findsOneWidget);
      expect(tester.getRect(card).height, 280);
    },
  );

  testWidgets(
    'metrics layouts respect phone safe areas and keep all ratings usable',
    (tester) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPadding);
      await launch(tester, tab: 1);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      for (final variant in [
        'Капсула над навигацией',
        'Три плитки',
        'Под карточкой',
      ]) {
        await tester.tap(find.byTooltip('Вариант нижней панели'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(variant));
        await tester.pumpAndSettle();
        expect(tester.getRect(card).height, closeTo(280, .01));
        final bar = tester.getRect(
          find.byKey(const ValueKey('study-accessory')),
        );
        expect(
          bar.bottom,
          lessThan(tester.getTopLeft(find.byType(SessionNavigation)).dy),
        );
        for (final rating in ratingNames.skip(1)) {
          expect(
            find
                .byWidgetPredicate((w) => w is Tap && w.label == rating)
                .hitTestable(),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await screenshot(tester, 'metrics-safe-area');
    },
  );

  testWidgets(
    'widget settings save, cancel and fit every style and position on a phone',
    (tester) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPadding);
      final (_, prefs) = await launch(tester, tab: 1);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      await screenshot(tester, 'final-0.3.14-card');
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      Future<void> open() async {
        await tester.tap(
          find.byWidgetPredicate((w) => w is Square && w.icon == 'settings'),
        );
        await tester.pumpAndSettle();
      }

      Future<void> choose(String key, String value) async {
        final selector = find.byKey(ValueKey(key));
        await tester.ensureVisible(selector);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: selector,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(value).last);
        await tester.pumpAndSettle();
      }

      await open();
      await choose('session-widget-style', 'Отдельные плитки');
      await choose('session-widget-position', 'Под кнопками оценок');
      await tester.tap(
        find.byWidgetPredicate((w) => w is Square && w.icon == 'close'),
      );
      await tester.pumpAndSettle();
      expect(prefs.studyWidgetStyle, 'ribbon');
      expect(prefs.studyWidgetPosition, 'aboveNavigation');
      for (final style in [
        ('ribbon', 'Единая капсула'),
        ('tiles', 'Отдельные плитки'),
      ]) {
        for (final position in [
          ('aboveNavigation', 'Над нижней навигацией'),
          ('belowRatings', 'Под кнопками оценок'),
          ('belowCard', 'Под карточкой'),
        ]) {
          await open();
          await choose('session-widget-style', style.$2);
          await choose('session-widget-position', position.$2);
          if (style.$1 == 'ribbon' && position.$1 == 'aboveNavigation') {
            await screenshot(tester, 'final-0.3.14-widget-settings');
          }
          await tester.tap(
            find.byWidgetPredicate((w) => w is Square && w.icon == 'check'),
          );
          await tester.pumpAndSettle();
          expect(prefs.studyWidgetStyle, style.$1);
          expect(prefs.studyWidgetPosition, position.$1);
          expect(tester.getRect(card).height, closeTo(280, .01));
          final bar = tester.getRect(
            find.byKey(const ValueKey('study-accessory')),
          );
          expect(
            bar.bottom,
            lessThan(tester.getTopLeft(find.byType(SessionNavigation)).dy),
          );
          for (final rating in ratingNames.skip(1)) {
            final button = find.byWidgetPredicate(
              (w) => w is Tap && w.label == rating,
            );
            expect(button.hitTestable(), findsOneWidget);
            expect(tester.getRect(button).overlaps(bar), false);
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('session bottom navigation opens each home destination', (
    tester,
  ) async {
    final (_, prefs) = await launch(tester, tab: 1);
    for (final destination in [
      (0, 'Профиль'),
      (2, 'Словарь'),
      (3, 'Импорт'),
      (4, 'Настройки'),
    ]) {
      await tapNav(tester, 'Учить');
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NativeStudyPage), findsOneWidget);
      await tapNav(tester, destination.$2);
      expect(find.byType(NativeStudyPage), findsNothing);
      expect(find.byType(NativeHome), findsOneWidget);
      expect(prefs.values['tab'], destination.$1);
      final visible = tester.widget<Offstage>(
        find.byKey(ValueKey('home-tab-${destination.$1}')),
      );
      expect(visible.offstage, false);
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).selected,
        destination.$1,
      );
    }
    await screenshot(tester, 'navigation-hotfix-settings');
  });

  testWidgets(
    'rapid session navigation cannot pop home while time save is delayed',
    (tester) async {
      final store = _DelayedTimeStore();
      final (_, prefs) = await launch(tester, tab: 1, suppliedStore: store);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      store.pendingTime = Completer<void>();
      final select = tester
          .widget<SessionNavigation>(find.byType(SessionNavigation))
          .onSelect;
      // Exercise callbacks already queued before the pop transition removes input.
      for (final tab in [0, 2, 4]) {
        select(tab);
      }
      await tester.pumpAndSettle();
      // A network save must not trap the user on the session route.
      expect(find.byType(NativeStudyPage), findsNothing);
      expect(find.byType(NativeHome), findsOneWidget);
      expect(prefs.values['tab'], 0);
      store.pendingTime!.complete();
      await tester.pumpAndSettle();
      expect(store.savedTimes, hasLength(1));
      expect(store.savedTimes.single, greaterThan(0));
      expect(find.byType(NativeHome), findsOneWidget);
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).selected,
        0,
      );
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'navigation-hotfix-profile');
    },
  );

  testWidgets(
    'time-save failure after navigation does not throw from dispose',
    (tester) async {
      final store = _DelayedTimeStore();
      await launch(tester, tab: 1, suppliedStore: store);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      store.pendingTime = Completer<void>();
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Профиль').last,
      );
      await tester.pumpAndSettle();
      expect(find.byType(NativeStudyPage), findsNothing);
      store.pendingTime!.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.byType(NativeHome), findsOneWidget);
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).selected,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'leaving during a flip and pending rating keeps the selected home tab',
    (tester) async {
      final store = _DelayedProgressStore();
      await launch(tester, tab: 1, suppliedStore: store);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      await tester.tap(card);
      await tester.pumpAndSettle();
      store.pending = Completer<void>();
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == ratingNames[5]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Словарь').last,
      );
      await tester.pumpAndSettle();
      expect(find.byType(NativeStudyPage), findsNothing);
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).selected,
        2,
      );
      store.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(NativeHome), findsOneWidget);
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).selected,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final phone in [
    const Size(411.43, 914.29),
    const Size(411.43, 891.43),
    const Size(390, 844),
  ]) {
    testWidgets('rating grid fills the space above widgets at $phone', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
      addTearDown(tester.view.resetPadding);
      final (store, _) = await launch(tester, tab: 1, size: phone);
      await store.patch({
        'words/1/word': 'qualmen',
        'words/1/info1': 'qualmt, qualmte, hat gequalmt',
        'words/1/info2': '',
        'words/1/ex1': 'Tag für Tag kriechen Myriaden qualmender Wagen über die Autobahn, und sie haben die gleiche Wirkung wie Wasser auf eine Gebetsmühle, mahlen einen endlosen Nebel aus hochgradig Bösem, der die metaphysische Atmosphäre im Umkreis von vielen Meilen verseucht.',
        'words/1/ex2': '',
      });
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      final last = find.byWidgetPredicate(
        (w) => w is Tap && w.label == ratingNames[6],
      );
      final first = find.byWidgetPredicate(
        (w) => w is Tap && w.label == ratingNames[1],
      );
      final bar = tester.getRect(find.byKey(const ValueKey('study-accessory')));
      expect(tester.getRect(card).height, closeTo(280, .01));
      expect(bar.top - tester.getRect(last).bottom, closeTo(12, .01));
      expect(tester.getRect(first).height, greaterThanOrEqualTo(52));
      for (final rating in ratingNames.skip(1)) {
        final button = find.byWidgetPredicate(
          (w) => w is Tap && w.label == rating,
        );
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getRect(button).overlaps(bar), false);
      }
      expect(
        find.ancestor(of: card, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'pixel-layout-${phone.height.toInt()}');
    });
  }

  testWidgets(
    'unified search suggests DWDS, adds a sense and marks owned cards',
    (tester) async {
      final client = MockClient(
        (request) async => http.Response(
          article,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      );
      final dictionary = DwdsDictionary(client: client);
      final (store, _) = await launch(tester, tab: 2, dictionary: dictionary);
      final hit = (await tester.runAsync(() => dictionary.suggest('Haus')))!
          .firstWhere((h) => h['lemma'] == 'Haus');
      await tester.runAsync(() => dictionary.detail(hit));
      await tester.enterText(find.byType(TextField).first, 'Haus');
      await tester.pumpAndSettle();
      expect(find.text('МОИ КАРТОЧКИ · 0'), findsOneWidget);
      expect(find.text('СЛОВАРЬ DWDS'), findsOneWidget);
      await screenshot(tester, 'unified-search-dwds');
      final result = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'DWDS: Haus',
      );
      await tester.ensureVisible(result);
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(find.text('das Haus, die Häuser'), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Значение 2'),
      );
      await tester.enterText(
        find.byKey(const ValueKey('dwds-translation')),
        'семья для теста',
      );
      await screenshot(tester, 'dwds-quick-add');
      await tester.tap(find.widgetWithText(Pill, 'Добавить в мои карточки'));
      await tester.pumpAndSettle();
      final saved = store.words
          .where((w) => w['translation'] == 'семья для теста')
          .single;
      expect(saved['dictionarySource'], 'DWDS');
      expect(saved['dwdsDefinition'], 'Familie oder Haushalt');
      expect(saved['ex1'], 'Das ganze Haus feiert.');
      expect(saved['dictionaryUrl'], 'https://www.dwds.de/wb/Haus');
      expect(find.text('DWDS · Уже есть в карточках'), findsWidgets);
      await screenshot(tester, 'unified-search-owned');
      await tester.ensureVisible(result);
      await tester.tap(result);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dwds-translation')),
        'семья для теста',
      );
      await tester.tap(find.widgetWithText(Pill, 'Добавить в мои карточки'));
      await tester.pumpAndSettle();
      expect(
        store.words.where((w) => w['translation'] == 'семья для теста'),
        hasLength(1),
      );
      expect(find.text('Такая карточка уже есть в словаре'), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Очистить поиск'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'семья для теста');
      await tester.pumpAndSettle();
      expect(find.text('МОИ КАРТОЧКИ · 1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('unified-search-words')),
          matching: find.text('семья для теста'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      client.close();
    },
  );

  testWidgets(
    'completion screen counts committed reviews, respects undo and exits to dictionary',
    (tester) async {
      final (_, prefs) = await launch(tester, tab: 1);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == ratingNames[5]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Выйти'));
      await tester.pumpAndSettle();
      for (final rating in [1, 4, 6]) {
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is Tap && w.label == ratingNames[rating],
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('Сессия завершена'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('summary-Карточек')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('summary-Уверенно')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(find.text('Стоит закрепить'), findsOneWidget);
      expect(find.text('der Augenblick'), findsOneWidget);
      expect(prefs.values['session-words-all'], isNull);
      await screenshot(tester, 'session-completed');
      await tester.tap(find.widgetWithText(Pill, 'Открыть словарь'));
      await tester.pumpAndSettle();
      expect(find.byType(NativeStudyPage), findsNothing);
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).selected,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('exam completion reports actual checked results', (tester) async {
    final (store, _) = await launch(tester, tab: 1);
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == 'Экзамен'),
    );
    await tester.pumpAndSettle();
    final expected = wordTitle(store.words.firstWhere((w) => w['id'] == '3'));
    await tester.enterText(find.byType(TextField), expected);
    await tester.tap(find.widgetWithText(Pill, 'Проверить'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Pill, 'Следующее слово'));
    await tester.pumpAndSettle();
    expect(find.text('Экзамен завершён'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('summary-Верно')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await screenshot(tester, 'exam-completed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('last card does not finish before its save succeeds', (
    tester,
  ) async {
    final store = _DelayedProgressStore();
    final (_, prefs) = await launch(tester, tab: 1, suppliedStore: store);
    prefs.values['session-words-all'] = {
      'ids': ['1'],
      'index': 0,
    };
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
    );
    await tester.pumpAndSettle();
    store.pending = Completer<void>();
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == ratingNames[5]),
    );
    await tester.pump();
    expect(find.text('Сессия завершена'), findsNothing);
    store.pending!.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Сессия завершена'), findsNothing);
    expect(find.text('der Augenblick').hitTestable(), findsOneWidget);
    store.pending = null;
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == ratingNames[5]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сессия завершена'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('summary-Карточек')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('card flip, six ratings, undo and native settings work', (
    tester,
  ) async {
    final (store, _) = await launch(tester, tab: 1);
    await screenshot(tester, 'study-home');
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NativeStudyPage), findsOneWidget);
    await screenshot(tester, 'card-front');
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('мгновение, момент').hitTestable(), findsOneWidget);
    await screenshot(tester, 'card-back');
    for (final rating in ratingNames.skip(1)) {
      expect(find.text(rating), findsOneWidget);
    }
    final before = jsonEncode(store.words);
    final rating = find.byWidgetPredicate(
      (w) => w is Tap && w.label == ratingNames[2],
    );
    await tester.ensureVisible(rating);
    await tester.tap(rating);
    await tester.pumpAndSettle();
    expect(jsonEncode(store.words), isNot(before));
    final exit = find.byWidgetPredicate((w) => w is Square && w.icon == 'back');
    await tester.ensureVisible(exit);
    await tester.pumpAndSettle();
    await tester.tap(exit);
    await tester.pumpAndSettle();
    expect(jsonEncode(store.words), before);
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.icon == 'settings'),
    );
    await tester.pumpAndSettle();
    await screenshot(tester, 'session-settings');
    expect(find.text('Настройки сессии'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'rating a translation flips back to the next word without replacing the card',
    (tester) async {
      await launch(tester, tab: 1);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      final element = tester.element(card);
      final bounds = tester.getRect(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('мгновение, момент').hitTestable(), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == ratingNames[2]),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(identical(tester.element(card), element), true);
      final rotation = tester
          .widget<Transform>(
            find.descendant(of: card, matching: find.byType(Transform)).first,
          )
          .transform;
      expect(
        rotation.entry(0, 0),
        isNot(closeTo(1, .001)),
        reason: 'The next word must arrive through a rotation, not an instant replacement.',
      );
      expect(find.text('мгновение, момент').hitTestable(), findsOneWidget);
      expect(tester.getRect(card), bounds);
      await screenshot(tester, 'rating-return-100', settle: false);
      await tester.pumpAndSettle();
      expect(find.text('entdecken').hitTestable(), findsOneWidget);
      expect(tester.getRect(card), bounds);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'card keeps its layout while flipping and handles interrupted taps',
    (tester) async {
      await launch(tester, tab: 1);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      final bounds = tester.getRect(card);
      await screenshot(tester, 'flip-000', settle: false);
      await tester.tap(card);
      await tester.pump();
      var previous = 0;
      for (final ms in [100, 200, 300, 450, 600]) {
        await tester.pump(Duration(milliseconds: ms - previous));
        expect(tester.getRect(card), bounds);
        expect(tester.takeException(), isNull);
        await screenshot(tester, 'flip-$ms', settle: false);
        previous = ms;
      }
      expect(find.text('мгновение, момент').hitTestable(), findsOneWidget);
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('мгновение, момент').hitTestable(), findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('der Augenblick').hitTestable(), findsOneWidget);
      expect(tester.getRect(card), bounds);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'tab navigation retains screens and scroll without rebuilding app theme; data stays fresh',
    (tester) async {
      final (store, prefs) = await launch(tester);
      final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final scroll = find.byKey(const ValueKey('home-scroll-0'));
      final originalElement = tester.element(scroll);
      await tester.drag(scroll, const Offset(0, -220));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          )
          .position
          .pixels;
      expect(position, greaterThan(0));
      await tapNav(tester, 'Словарь');
      await tapNav(tester, 'Учить');
      await tapNav(tester, 'Профиль');
      expect(
        identical(
          tester.widget<MaterialApp>(find.byType(MaterialApp)),
          material,
        ),
        true,
      );
      expect(identical(tester.element(scroll), originalElement), true);
      expect(
        tester
            .state<ScrollableState>(
              find
                  .descendant(of: scroll, matching: find.byType(Scrollable))
                  .first,
            )
            .position
            .pixels,
        position,
      );
      await tapNav(tester, 'Словарь');
      await tapNav(tester, 'Импорт');
      await store.patch({'words/1/translation': 'Обновленный перевод'});
      await tester.pumpAndSettle();
      await tapNav(tester, 'Словарь');
      expect(find.text('Обновленный перевод'), findsOneWidget);
      prefs.set('theme', 'light');
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(NativeHome))).brightness,
        Brightness.light,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('filters update the native dictionary without recursion', (
    tester,
  ) async {
    await launch(tester, tab: 2);
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.icon == 'filter'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Баллы'));
    await tester.pumpAndSettle();
    final score = find.widgetWithText(CheckboxListTile, '9');
    await tester.ensureVisible(score);
    await tester.pumpAndSettle();
    await tester.tap(score);
    await tester.pumpAndSettle();
    expect(find.text('Найдено: 1'), findsWidgets);
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'filters');
  });
  testWidgets('native login validates locally and shows registration', (
    tester,
  ) async {
    await launch(tester, signedIn: false, size: const Size(320, 568));
    await screenshot(tester, 'login');
    await tester.tap(find.widgetWithText(Pill, 'Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Введите email и пароль'), findsOneWidget);
    await tester.tap(find.text('Нет аккаунта? Регистрация'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('Зарегистрироваться'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('native folder creation saves a real word and metadata', (
    tester,
  ) async {
    final (store, _) = await launch(tester, tab: 1);
    await tester.tap(find.text('Создать папку'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Новая папка');
    await tester.enterText(find.byType(TextFormField).at(0), 'das Haus');
    await tester.enterText(find.byType(TextFormField).at(1), 'дом');
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.icon == 'check'),
    );
    await tester.pumpAndSettle();
    expect(
      store.words.any(
        (w) => w['word'] == 'das Haus' && w['folder'] == 'Новая папка',
      ),
      true,
    );
    expect(asMap(store.data!['folderMeta']).containsKey('Новая папка'), true);
    expect(tester.takeException(), isNull);
  });
  testWidgets('exam mistakes, override, undo and a correct answer persist', (
    tester,
  ) async {
    final (store, _) = await launch(tester, tab: 1);
    await store.patch({'settings/study/firstSide': 'translation'});
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == 'Экзамен'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'falsch');
    await tester.tap(find.widgetWithText(Pill, 'Проверить'));
    await tester.pumpAndSettle();
    expect(find.text('✗ Неправильно'), findsOneWidget);
    final wrong = jsonEncode(
      store.words.firstWhere((w) => w['id'] == '3')['progress_global'],
    );
    await tester.tap(find.widgetWithText(Pill, 'Засчитать как верно'));
    await tester.pumpAndSettle();
    expect(
      asMap(
        store.words.firstWhere((w) => w['id'] == '3')['progress_global'],
      )['isActive'],
      true,
    );
    await tester.tap(find.widgetWithText(Pill, 'Отменить исправление'));
    await tester.pumpAndSettle();
    expect(
      jsonEncode(
        store.words.firstWhere((w) => w['id'] == '3')['progress_global'],
      ),
      wrong,
    );
    await screenshot(tester, 'exam');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'remote deletion can be restored and long cards fit a small phone',
    (tester) async {
      final (store, _) = await launch(
        tester,
        tab: 1,
        size: const Size(320, 568),
      );
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      final backup = Map<String, dynamic>.from(
        store.words.firstWhere((w) => w['id'] == '1'),
      );
      await store.patch({'words/1': null});
      await tester.pumpAndSettle();
      expect(find.text('Вы удалили это слово из словаря.'), findsOneWidget);
      await tester.tap(find.widgetWithText(Pill, 'Восстановить слово'));
      await tester.pumpAndSettle();
      expect(store.words.any((w) => w['id'] == '1'), true);
      await store.patch({
        'words/1': {
          ...backup,
          'ex1': List.filled(20, 'Ein langer Beispielsatz.').join(' '),
        },
      });
      await tester.pumpAndSettle();
      final rate = find.byWidgetPredicate(
        (w) => w is Tap && w.label == ratingNames[6],
      );
      await tester.scrollUntilVisible(
        rate,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(rate.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'small-phone-ratings');
    },
  );
  for (final screen in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets('fixed card keeps ratings steady at $screen', (tester) async {
      final (store, _) = await launch(tester, tab: 1, size: screen);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
      );
      await tester.pumpAndSettle();
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      final initialSize = tester.getSize(card);
      final rating = find.byWidgetPredicate(
        (w) => w is Tap && w.label == ratingNames[1],
      );
      final ratingY = tester.getTopLeft(rating).dy;
      await store.patch({
        'words/1/ex1': List.filled(40, 'Ein langer Beispielsatz.').join(' '),
        'words/1/translation': List.filled(30, 'Довгий переклад').join(' '),
      });
      await tester.pumpAndSettle();
      expect(tester.getSize(card), initialSize);
      expect(tester.getTopLeft(rating).dy, ratingY);
      final inner = find
          .descendant(of: card, matching: find.byType(Scrollable))
          .hitTestable();
      expect(inner, findsOneWidget);
      final position = tester.state<ScrollableState>(inner).position;
      expect(position.maxScrollExtent, greaterThan(0));
      await tester.drag(card, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      await screenshot(tester, 'fixed-long-front-${screen.width.toInt()}');
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(tester.getSize(card), initialSize);
      expect(tester.getTopLeft(rating).dy, ratingY);
      await screenshot(tester, 'fixed-long-back-${screen.width.toInt()}');
      final distance =
          tester.getTopLeft(rating).dy - tester.getTopLeft(card).dy;
      await Scrollable.ensureVisible(tester.element(rating), alignment: .2);
      await tester.pumpAndSettle();
      await tester.tap(rating);
      await tester.pumpAndSettle();
      expect(tester.getSize(card), initialSize);
      expect(
        tester.getTopLeft(rating).dy - tester.getTopLeft(card).dy,
        distance,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('light mode and folder grid render without overflow', (
    tester,
  ) async {
    final (_, prefs) = await launch(tester, tab: 1, size: const Size(320, 568));
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.icon == 'grid'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    prefs.set('theme', 'light');
    await tester.pumpAndSettle();
    await screenshot(tester, 'light-grid');
    await tapNav(tester, 'Профиль');
    expect(tester.takeException(), isNull);
  });
  testWidgets('folder sort menu and view survive rebuilding the app', (
    tester,
  ) async {
    final (store, prefs) = await launch(tester, tab: 1);
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.tooltip == 'Сортировка'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('По алфавиту'));
    await tester.pumpAndSettle();
    expect(prefs.values['folderOrder'], 'alphabet');
    Finder folder(String name) =>
        find.byWidgetPredicate((w) => w is Tap && w.label == name);
    expect(
      tester.getTopLeft(folder('Папка 1')).dy,
      lessThan(tester.getTopLeft(folder('Папка 2')).dy),
    );
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.tooltip == 'Вид папок'),
    );
    await tester.pumpAndSettle();
    expect(prefs.values['folderGrid'], true);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NativeTwinkApp(store: store, preferences: prefs),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = tester.widget<Square>(
      find.byWidgetPredicate((w) => w is Square && w.tooltip == 'Вид папок'),
    );
    expect(toggle.icon, 'list');
    expect(tester.takeException(), isNull);
  });
  testWidgets('dictionary columns persist independently for words and idioms', (
    tester,
  ) async {
    final (store, prefs) = await launch(tester, tab: 2);
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.icon == 'filter'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Столбцы'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Перевод'));
    await tester.pumpAndSettle();
    expect(prefs.values['columns-words'], isNot(contains('translation')));
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.icon == 'close'),
    );
    await tester.pumpAndSettle();
    expect(find.text('мгновение, момент'), findsNothing);
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == 'Идиомы'),
    );
    await tester.pumpAndSettle();
    expect(find.text('${store.idioms.first['translation']}'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NativeTwinkApp(store: store, preferences: prefs),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('der Augenblick'), findsOneWidget);
    expect(find.text('мгновение, момент'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'first side saves, cancels, survives reopening and returns to translation after rating',
    (tester) async {
      final (store, prefs) = await launch(tester, tab: 1);
      final study = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Весь словарь',
      );
      final card = find.byWidgetPredicate(
        (w) => w is Tap && w.label == 'Перевернуть карточку',
      );
      Future<void> chooseTranslation() async {
        await tester.tap(
          find.byWidgetPredicate((w) => w is Square && w.icon == 'settings'),
        );
        await tester.pumpAndSettle();
        final selector = find.byKey(const ValueKey('first-side-selector'));
        await tester.scrollUntilVisible(
          selector,
          180,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: selector,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Перевод').last);
        await tester.pumpAndSettle();
      }

      await tester.tap(study);
      await tester.pumpAndSettle();
      await chooseTranslation();
      await tester.tap(
        find.byWidgetPredicate((w) => w is Square && w.icon == 'close'),
      );
      await tester.pumpAndSettle();
      expect(store.settings['firstSide'], 'word');
      expect(find.text('der Augenblick').hitTestable(), findsOneWidget);
      await chooseTranslation();
      await tester.tap(
        find.byWidgetPredicate((w) => w is Square && w.icon == 'check'),
      );
      await tester.pumpAndSettle();
      expect(store.settings['firstSide'], 'translation');
      expect(find.text('мгновение, момент').hitTestable(), findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('der Augenblick').hitTestable(), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tap && w.label == ratingNames[2]),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('der Augenblick').hitTestable(), findsOneWidget);
      final rotation = tester
          .widget<Transform>(
            find.descendant(of: card, matching: find.byType(Transform)).first,
          )
          .transform;
      expect(rotation.entry(0, 0), isNot(closeTo(-1, .001)));
      await tester.pumpAndSettle();
      final nextTranslation = store.words
          .firstWhere((w) => w['id'] == '2')['translation']
          .toString();
      expect(find.text(nextTranslation).hitTestable(), findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('entdecken').hitTestable(), findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text(nextTranslation).hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: NativeTwinkApp(store: store, preferences: prefs),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(study);
      await tester.pumpAndSettle();
      expect(find.text(nextTranslation).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('idioms can start with translation', (tester) async {
    final (store, _) = await launch(tester, tab: 1);
    await store.patch({'settings/study/firstSide': 'translation'});
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == 'Все идиомы'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(store.idioms.first['translation'].toString()).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('closing session settings cancels and checkmark saves', (
    tester,
  ) async {
    final (store, _) = await launch(tester, tab: 1);
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == 'Весь словарь'),
    );
    await tester.pumpAndSettle();
    Future<void> open() async {
      await tester.tap(
        find.byWidgetPredicate((w) => w is Square && w.icon == 'settings'),
      );
      await tester.pumpAndSettle();
    }

    Future<void> toggleGender() async {
      final row = find
          .ancestor(
            of: find.text('Подсветка слова по роду'),
            matching: find.byType(Row),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Подсветка слова по роду'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Tap)).last,
      );
      await tester.pumpAndSettle();
    }

    await open();
    await toggleGender();
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.icon == 'close'),
    );
    await tester.pumpAndSettle();
    expect(store.settings['genderColors'], false);
    await open();
    await toggleGender();
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.icon == 'check'),
    );
    await tester.pumpAndSettle();
    expect(store.settings['genderColors'], true);
    expect(tester.takeException(), isNull);
  });
  testWidgets('folder editor starts with one card and can create idioms', (
    tester,
  ) async {
    final (store, _) = await launch(tester, tab: 1);
    await tester.tap(find.text('Создать папку'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(6));
    await tester.enterText(find.byType(TextField).first, 'Новые идиомы');
    await tester.enterText(find.byType(TextField).at(1), 'Описание папки');
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tap && w.label == 'Идиомы'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(5));
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'den Nagel auf den Kopf treffen',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'попасть в точку');
    await screenshot(tester, 'folder-editor');
    await tester.tap(
      find.byWidgetPredicate((w) => w is Square && w.icon == 'check'),
    );
    await tester.pumpAndSettle();
    final saved = store.idioms.firstWhere((w) => w['folder'] == 'Новые идиомы');
    expect(saved['idiom'], 'den Nagel auf den Kopf treffen');
    expect(saved.containsKey('word'), false);
    expect(
      asMap(asMap(store.data!['idiomFolders'])['Новые идиомы'])['description'],
      'Описание папки',
    );
    expect(store.words.length, 5);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty study dashboard provides original add actions', (
    tester,
  ) async {
    final (store, _) = await launch(tester, tab: 1);
    await store.patch({
      'words': null,
      'idioms': null,
      'folderMeta': null,
      'idiomFolders': null,
    });
    await tester.pumpAndSettle();
    expect(find.text('Здесь пока ничего нет'), findsOneWidget);
    expect(find.widgetWithText(Pill, 'Добавить слово'), findsOneWidget);
    expect(find.widgetWithText(Pill, 'Добавить идиому'), findsOneWidget);
    await screenshot(tester, 'empty-study');
    await tester.tap(find.widgetWithText(Pill, 'Добавить слово'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });
  testWidgets('original interval comparison and palettes fit a small phone', (
    tester,
  ) async {
    final (_, prefs) = await launch(tester, size: const Size(320, 568), tab: 4);
    await tester.tap(find.text('Прогресс'));
    await tester.pumpAndSettle();
    expect(find.text('Долгое'), findsOneWidget);
    expect(find.text('Интенсив'), findsOneWidget);
    expect(find.text('21 день'), findsOneWidget);
    await screenshot(tester, 'progress-settings');
    final appearance = find.text('Персонализация');
    await tester.ensureVisible(appearance);
    await tester.pumpAndSettle();
    await tester.tap(appearance);
    await tester.pumpAndSettle();
    prefs.set('scheme', 'pink-yellow');
    await tester.pumpAndSettle();
    await tapNav(tester, 'Профиль');
    await screenshot(tester, 'pink-glass-profile');
    prefs.set('theme', 'light');
    await tester.pumpAndSettle();
    await screenshot(tester, 'light-glass-profile');
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(568, 320),
    const Size(1024, 768),
  ]) {
    testWidgets('all tabs fit ${size.width}', (tester) async {
      await launch(tester, size: size);
      for (final name in [
        'Словарь',
        'Импорт',
        'Настройки',
        'Учить',
        'Профиль',
      ]) {
        await tapNav(tester, name);
      }
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester.binding.hasScheduledFrame,
        false,
        reason: 'The idle UI must not continuously animate or repaint.',
      );
    });
  }
}
