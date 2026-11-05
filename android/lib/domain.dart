import 'dart:math';

typedef Json = Map<String, dynamic>;
const dayMs = 86400000;
const intervals = <String, List<double>>{
  'long': [0, 1 / 24, 1, 4, 7, 12, 21],
  'intensive': [0, 1 / 24, 1, 2, 4, 9, 17],
};
const ratings = [
  '',
  'Забув',
  'Важко',
  'Невпевнено',
  'Добре',
  'Пам’ятаю',
  'Відмінно',
];
Json asMap(dynamic value) {
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  if (value is List) {
    return {
      for (var i = 0; i < value.length; i++)
        if (value[i] != null) '$i': value[i],
    };
  }
  return {};
}

List<Json> records(dynamic value) =>
    asMap(value).entries
        .where((e) => e.value is Map)
        .map((e) => {...asMap(e.value), 'id': e.key})
        .toList();
String wordTitle(Json w) => '${w['word'] ?? w['idiom'] ?? ''}';
num number(dynamic value) => value is num ? value : num.tryParse('$value') ?? 0;
Json freshProgress([int? now]) => {
  'interval': 0,
  'nextDate': now ?? DateTime.now().millisecondsSinceEpoch,
  'state': 'new',
  'excellentStreak': 0,
  'isActive': false,
  'is_ideal': false,
};
bool eligible(Json w, {bool exam = false, int? now}) {
  final p = asMap(w['progress_global']);
  final due =
      number(p['nextDate']) <= (now ?? DateTime.now().millisecondsSinceEpoch);
  return p['isActive'] != true &&
      due &&
      (exam
          ? w['idiom'] == null && number(p['excellentStreak']) >= 9
          : w['idiom'] != null || number(p['excellentStreak']) < 9);
}

Json review(Json previous, int rating, {String mode = 'long', int? now}) {
  if (rating < 1 || rating > 6) throw ArgumentError('Невідома оцінка');
  final time = now ?? DateTime.now().millisecondsSinceEpoch;
  final interval = (intervals[mode] ?? intervals['long']!)[rating];
  final score = rating == 1
      ? 0
      : min(
          9,
          max(
            0,
            ((number(previous['excellentStreak']) +
                            [0, 0, -3, -1.5, 0, 1.5, 3][rating]) *
                        10)
                    .round() /
                10,
          ),
        );
  return {
    ...previous,
    'interval': interval,
    'nextDate': time + (interval * dayMs).round(),
    'lastRating': rating,
    'lastReviewed': time,
    'excellentStreak': score,
    'isActive': previous['isActive'] == true,
    'is_ideal': previous['isActive'] == true || rating >= 5,
  };
}

Json examProgress(
  Json previous,
  Json result, {
  String mode = 'long',
  int? now,
}) {
  final time = now ?? DateTime.now().millisecondsSinceEpoch,
      correct = result['correct'] == true;
  final score = correct
      ? 10
      : max(
          0,
          number(previous['excellentStreak']) -
              (result['articleError'] == true || result['sequenceError'] == true
                  ? 1.5
                  : 3),
        );
  final rating = correct
          ? 6
          : score >= 9
          ? 4
          : 2,
      interval = (intervals[mode] ?? intervals['long']!)[rating];
  return {
    ...previous,
    'excellentStreak': score,
    'isActive': correct,
    'is_ideal': correct,
    'interval': interval,
    'nextDate': time + (interval * dayMs).round(),
    'lastRating': rating,
    'lastReviewed': time,
  };
}

final _articles = RegExp(
  r'\b(der|die|das|den|dem|des|ein|eine|einer|einem|einen)\b',
  caseSensitive: false,
);
String _noParens(String s) => s.replaceAll(RegExp(r'\([^)]*\)'), '');
String _clean(String s) =>
    _noParens(s)
        .toLowerCase()
        .replaceAll(_articles, '')
        .replaceAll(RegExp(r'[^a-z0-9äöüß\s]', caseSensitive: false), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
String _compact(String s) => _clean(s).replaceAll(' ', '');
String? _article(String s) => RegExp(
  r'^(der|die|das|den|dem|des|ein|eine|einer|einem|einen)\b',
  caseSensitive: false,
).firstMatch(_noParens(s).trim())?.group(1)?.toLowerCase();
String duplicateKey(String s) =>
    '${_compact(s.split(',').first.replaceAll(RegExp(r'\bsich\b', caseSensitive: false), ''))}${_article(s) != null ? '::noun' : ''}';

String autoFolder(List<Json> list) {
  final counts = <int, int>{};
  for (final w in list) {
    final m = RegExp(r'^Папка (\d+)$').firstMatch('${w['folder'] ?? ''}');
    if (m != null) {
      final n = int.parse(m[1]!);
      counts[n] = (counts[n] ?? 0) + 1;
    }
  }
  var n = counts.keys.fold<int>(1, max);
  if ((counts[n] ?? 0) >= 100) n++;
  return 'Папка $n';
}

Json checkAnswer(Json w, String answer) {
  final expected = wordTitle(w), info = '${w['info1'] ?? ''}';
  var content = false, partial = false, sequence = false;
  if (info.isNotEmpty) {
    final units = '$expected,$info'
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    List<Json> variants(String unit) {
      if (!unit.contains('/')) {
        return [
          {'text': _clean(unit), 'partial': false},
        ];
      }
      final tokens = unit
          .replaceAll(RegExp(r'\s*/\s*'), '/')
          .split(RegExp(r'\s+'));
      final i = tokens.indexWhere((s) => s.contains('/')),
          opts = tokens[i].split('/');
      if (opts.length < 2) {
        return [
          {'text': _clean(unit), 'partial': false},
        ];
      }
      final values = [
        opts[0],
        opts[1],
        '${opts[0]} ${opts[1]}',
        '${opts[1]} ${opts[0]}',
      ];
      return [
        for (var j = 0; j < values.length; j++)
          {
            'text': _clean(
              [
                for (var k = 0; k < tokens.length; k++)
                  k == i ? values[j] : tokens[k],
              ].join(' '),
            ),
            'partial': j < 2,
          },
      ];
    }

    Json permute(String rest, List<String> left) {
      if (left.isEmpty) return {'ok': rest.trim().isEmpty, 'partial': false};
      for (var i = 0; i < left.length; i++) {
        for (final v in variants(left[i])) {
          if (v['text'] == '') continue;
          final pattern = RegExp(
            '(^|\\s)${RegExp.escape(v['text'])}(?=\\s|\$)',
          );
          if (pattern.hasMatch(rest)) {
            final next = List<String>.of(left)..removeAt(i);
            final result = permute(
              rest
                  .replaceFirst(pattern, ' ')
                  .trim()
                  .replaceAll(RegExp(r'\s+'), ' '),
              next,
            );
            if (result['ok'] == true) {
              return {
                'ok': true,
                'partial': v['partial'] == true || result['partial'] == true,
              };
            }
          }
        }
      }
      return {'ok': false, 'partial': false};
    }

    final result = permute(_clean(answer), units);
    content = result['ok'] == true;
    partial = result['partial'] == true;
    String sorted(String s) => (_clean(
      s,
    ).split(' ').where((t) => t.isNotEmpty).toList()..sort()).join(' ');
    sequence = !content && sorted(answer) == sorted('$expected $info');
  } else {
    final parts = expected.split(',').map((s) => s.trim()).toList();
    if (parts.length == 2 && parts[1].startsWith('-')) {
      final singular = parts[0],
          suffix = parts[1].substring(1),
          base = singular.replaceFirst(
            RegExp(r'^(der|die|das)\s+', caseSensitive: false),
            '',
          );
      content = [
        singular,
        '$singular $suffix',
        expected,
        '$singular $base$suffix',
      ].any((v) => _compact(v) == _compact(answer));
    } else {
      content = _compact(expected) == _compact(answer);
    }
  }
  final expectedParts = expected.split(','), userParts = answer.split(',');
  var articleError = false;
  if (content) {
    for (var i = 0; i < expectedParts.length && i < userParts.length; i++) {
      final c = _article(expectedParts[i]), u = _article(userParts[i]);
      if (c != null && (i == 0 ? c != u : u != null && c != u)) {
        articleError = true;
      }
    }
  }
  return {
    'correct': content && !articleError,
    'articleError': articleError,
    'sequenceError': sequence,
    'partial': partial,
  };
}

String logicalDay([int? now]) => DateTime.fromMillisecondsSinceEpoch(
  (now ?? DateTime.now().millisecondsSinceEpoch) - 6 * 3600000,
  isUtc: true,
).toIso8601String().substring(0, 10);
const wordHeaders = [
  'ID',
  'Активные слова',
  'Немецкое слово',
  'Перевод',
  'Формы глагола',
  'Дополнительно',
  'Пример 1',
  'Пример 2',
  'Папка',
];
const idiomHeaders = [
  'ID',
  'Идиома',
  'Перевод',
  'Смысловой перевод',
  'Дополнительно',
  'Пример',
  'Папка',
];
List<List<dynamic>> toRows(List<Json> list, String kind) => [
  kind == 'idioms' ? idiomHeaders : wordHeaders,
  ...list.map(
    (w) => kind == 'idioms'
        ? [
            w['id'],
            w['idiom'] ?? '',
            w['translation'] ?? '',
            w['meaning'] ?? '',
            w['info'] ?? '',
            w['example'] ?? '',
            w['folder'] ?? '',
          ]
        : [
            w['id'],
            asMap(w['progress_global'])['isActive'] == true
                ? 10
                : asMap(w['progress_global'])['excellentStreak'] ?? 0,
            w['word'] ?? '',
            w['translation'] ?? '',
            w['info1'] ?? '',
            w['info2'] ?? '',
            w['ex1'] ?? '',
            w['ex2'] ?? '',
            w['folder'] ?? '',
          ],
  ),
];
Json importRows(
  List<List<dynamic>> rows,
  String kind,
  Json existing, {
  int? now,
}) {
  final header = rows.isEmpty
      ? ''
      : rows.first.map((v) => '$v'.toLowerCase()).join(' ');
  if (rows.isNotEmpty &&
      rows.first.isNotEmpty &&
      '${rows.first.first}'.toLowerCase() == 'id' &&
      ((RegExp('идиом|idiom|ідіом').hasMatch(header) && kind == 'words') ||
          (RegExp('активн|немецк|score').hasMatch(header) &&
              kind == 'idioms'))) {
    throw const FormatException(
      'Формат файлу не відповідає вкладці. Оберіть «Слова» або «Ідіоми».',
    );
  }
  final updates = <String, dynamic>{};
  var created = 0, updated = 0;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i].map((v) => '${v ?? ''}'.trim()).toList();
    if (row.every((s) => s.isEmpty)) continue;
    if (i == 0 && row[0].toLowerCase() == 'id') continue;
    String cell(int n) => row.length > n ? row[n] : '';
    final id = cell(0);
    if (id.isEmpty || RegExp(r'[.#$\[\]/\x00-\x1f]').hasMatch(id)) {
      throw FormatException('Рядок ${i + 1}: некоректний ID');
    }
    if (kind == 'words' &&
        (!RegExp(r'^\d+$').hasMatch(id) || number(id) >= 100000)) {
      throw FormatException('Рядок ${i + 1}: ID слова має бути від 0 до 99999');
    }
    final old = asMap(existing[id]);
    final data = kind == 'idioms'
        ? {
            'idiom': cell(1),
            'translation': cell(2),
            'meaning': cell(3),
            'info': cell(4),
            'example': cell(5),
            'folder': cell(6).isNotEmpty
                ? cell(6)
                : old['folder'] ??
                      autoFolder(records({...existing, ...updates})),
          }
        : {
            'word': cell(2),
            'translation': cell(3),
            'info1': cell(4),
            'info2': cell(5),
            'ex1': cell(6),
            'ex2': cell(7),
            'folder': cell(8).isNotEmpty
                ? cell(8)
                : old['folder'] ??
                      autoFolder(records({...existing, ...updates})),
          };
    if ('${data['word'] ?? data['idiom'] ?? ''}'.isEmpty ||
        '${data['translation']}'.isEmpty) {
      throw FormatException('Рядок ${i + 1}: потрібні текст і переклад');
    }
    final p = asMap(old['progress_global']);
    if (existing.containsKey(id) && kind == 'words') {
      final score = cell(1).toLowerCase() == 'yes'
          ? 10
          : number(cell(1)).clamp(0, 10);
      if (score != number(p['excellentStreak'])) {
        data['progress_global'] = {
          ...p,
          'excellentStreak': score,
          'isActive': score >= 10,
        };
      }
    }
    if (!existing.containsKey(id)) {
      data.addAll({
        'progress_global': freshProgress(now),
        if (kind == 'words') ...{
          'progress_groups': freshProgress(now),
          'interval': 0,
          'nextDate': now ?? DateTime.now().millisecondsSinceEpoch,
        },
      });
    }
    updates[id] = {...old, ...data, 'id': id};
    existing.containsKey(id) ? updated++ : created++;
  }
  return {'updates': updates, 'created': created, 'updated': updated};
}

Json sampleData() {
  final words = <String, dynamic>{};
  for (final row in [
    ['1', 'der Augenblick', 'мить', '', ''],
    [
      '2',
      'entdecken',
      'відкривати',
      'entdeckte, hat entdeckt',
      'Ich entdecke jeden Tag etwas Neues.',
    ],
    ['3', 'die Möglichkeit', 'можливість', '', ''],
    [
      '4',
      'sich erinnern',
      'пам’ятати',
      'erinnerte sich, hat sich erinnert',
      'Ich erinnere mich an diesen Tag.',
    ],
  ]) {
    words[row[0]] = {
      'id': row[0],
      'word': row[1],
      'translation': row[2],
      'info1': row[3],
      'ex1': row[4],
      'folder': 'Щодня',
      'progress_global': {
        ...freshProgress(),
        'excellentStreak': row[0] == '3' ? 9 : 0,
      },
    };
  }
  return {
    'nickname': 'Демо',
    'words': words,
    'idioms': {
      '100000': {
        'id': '100000',
        'idiom': 'Daumen drücken',
        'translation': 'тримати кулаки',
        'meaning': 'Бажати успіху',
        'example': 'Ich drücke dir die Daumen!',
        'folder': 'Вислови',
        'progress_global': freshProgress(),
      },
    },
    'settings': {
      'study': {'studyMode': 'long', 'examples': true, 'audio': false},
    },
    'stats': {'daily': <String, dynamic>{}},
  };
}
