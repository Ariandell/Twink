import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twink_android/domain.dart';
import 'package:twink_android/native/app.dart';

void main() {
  test('all original word and idiom column controls are available', () {
    final html = File('../web/public/classic/index.html').readAsStringSync();
    for (final kind in ['words', 'idioms']) {
      final id = kind == 'words'
          ? 'dict-filter-columns-menu'
          : 'dict-filter-idioms-columns-menu';
      final start = html.indexOf('id="$id"'),
          end = html.indexOf('</div>', start);
      final keys = RegExp('value="([^"]+)"')
          .allMatches(html.substring(start, end))
          .map((m) => m[1] == 'is_ideal' ? 'ideal' : m[1]!)
          .toSet();
      expect(
        dictionaryColumns(kind).map((f) => f.first).toSet(),
        keys,
        reason: kind,
      );
    }
  });
  test('folders use numeric creation order and natural alphabet order', () {
    final records = <Json>[
      {'id': '1', 'folder': 'Zebra'},
      {'id': '200', 'folder': 'Apfel'},
      {'id': '40', 'folder': 'Apfel'},
      {'id': '90', 'folder': 'Папка 2'},
      {'id': '8', 'folder': 'Папка 10'},
    ];
    const names = ['Zebra', 'Apfel', 'Папка 2', 'Папка 10'];
    List<String> sorted(String order) =>
        [...names]..sort((a, b) => compareFolders(a, b, records, order));
    expect(sorted('newest'), ['Папка 2', 'Apfel', 'Папка 10', 'Zebra']);
    expect(sorted('oldest'), ['Zebra', 'Папка 10', 'Apfel', 'Папка 2']);
    expect(sorted('alphabet'), ['Apfel', 'Zebra', 'Папка 2', 'Папка 10']);
  });
  test('exam hints preserve noun, feminine, phrase and verb cues', () {
    for (final pair in <(Json, String)>[
      ({'word': 'schön'}, '________'),
      ({'word': 'ein paar'}, 'Введите 2 слова/слов'),
      ({'word': 'der Hügel, die Hügel'}, '________, (plural)'),
      ({'word': 'die Restaurierung, -en'}, '________, (plural)'),
      ({'word': 'die Lehrerin'}, '(жен. р.)'),
      (
        {'word': 'fahren', 'info1': 'fuhr, ist/hat gefahren'},
        '________, Präsens, Präteritum, Partizip II',
      ),
    ]) {
      expect(examHint(pair.$1), pair.$2, reason: pair.$1.toString());
    }
  });
  test(
    'example emphasis preserves original forms and excludes auxiliaries',
    () {
      const text = 'Er ist gekreist. Wir kreisen heute.';
      final parts = originalExampleHighlights(
        text,
        'kreisen',
        'kreist, kreiste, ist gekreist',
      ).map((r) => text.substring(r.$1, r.$2)).toList();
      expect(parts, ['gekreist', 'kreisen']);
      const nouns = 'Auf dem Hügel steht ein Haus.';
      expect(
        originalExampleHighlights(
          nouns,
          'der Hügel',
          '',
        ).map((r) => nouns.substring(r.$1, r.$2)),
        ['Hügel'],
      );
    },
  );
  test('rating intervals retain original Russian labels', () {
    expect(intervals['long']!.skip(1).map(intervalCaption), [
      '1 час',
      '1 день',
      '4 дня',
      '7 дней',
      '12 дней',
      '21 день',
    ]);
    expect(intervals['intensive']!.skip(1).map(intervalCaption), [
      '1 час',
      '1 день',
      '2 дня',
      '4 дня',
      '7 дней',
      '17 дней',
    ]);
  });
}
