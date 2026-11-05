import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twink_android/domain.dart';
import 'package:twink_android/native/app.dart';
import 'package:twink_android/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = Key('capture');
  Future<(TwinkStore, NativePreferences)> launch(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    int tab = 0,
    bool signedIn = true,
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
    final store = TwinkStore()..startDemo();
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
      ..values['tab'] = tab
      ..values['session-words-all'] = {
        'ids': ['1', '2', '4'],
        'index': 0,
      };
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: NativeTwinkApp(store: store, preferences: prefs),
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

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_NATIVE')) return;
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(capture),
    );
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
      await tester.ensureVisible(row);
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
