part of 'app.dart';

class TwinkPalette extends ThemeExtension<TwinkPalette> {
  const TwinkPalette(this.scheme, this.light);
  final String scheme;
  final bool light;
  List<Color> get accents => schemes[scheme] ?? schemes['default']!;
  Color get secondary => scheme == 'pure-black'
      ? (light ? Colors.black : Colors.white)
      : ['pink-yellow', 'purple-orange', 'red-cyan'].contains(scheme)
      ? accents.first
      : accents.last;
  @override
  TwinkPalette copyWith({String? scheme, bool? light}) =>
      TwinkPalette(scheme ?? this.scheme, light ?? this.light);
  @override
  TwinkPalette lerp(covariant TwinkPalette? other, double t) =>
      t < .5 ? this : other ?? this;
}

Color originalSecondary(BuildContext context) =>
    Theme.of(context).extension<TwinkPalette>()?.secondary ?? ink(context);

String intervalCaption(num days) {
  if (days < 1) return '1 час';
  final n = days.round(),
      one = n % 10 == 1 && n % 100 != 11,
      twoToFour = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
  return '$n ${one
      ? 'день'
      : twoToFour
      ? 'дня'
      : 'дней'}';
}

class _ModeComparison extends StatelessWidget {
  const _ModeComparison({required this.mode});
  final String mode;
  @override
  Widget build(BuildContext context) => Surface(
    radius: 20,
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1.2),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
          },
          children: [
            TableRow(
              children: [
                for (final title in ['Оценка', 'Долгое', 'Интенсив'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: label(
                      title,
                      size: 12.8,
                      color: muted(context),
                      align: title == 'Оценка'
                          ? TextAlign.left
                          : TextAlign.center,
                    ),
                  ),
              ],
            ),
            for (var r = 1; r <= 6; r++)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: label(
                      ratingNames[r],
                      size: 12.8,
                      color: muted(context),
                    ),
                  ),
                  for (final m in ['long', 'intensive'])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: label(
                        intervalCaption(intervals[m]![r]),
                        size: 12.8,
                        weight: mode == m ? FontWeight.w600 : FontWeight.w400,
                        color: mode == m
                            ? ink(context)
                            : muted(context).withValues(alpha: .5),
                        align: TextAlign.center,
                      ),
                    ),
                ],
              ),
          ],
        ),
        gap(16),
        Container(height: 1, color: ink(context).withValues(alpha: .05)),
        gap(12),
        label(
          mode == 'intensive'
              ? 'Интенсив: Идеально для быстрого погружения. Интервалы короче, повторения чаще.'
              : 'Стандарт: Сбалансированный путь для долгосрочной памяти. Оптимально для спокойного темпа.',
          size: 12,
          color: muted(context),
        ),
      ],
    ),
  );
}

int naturalCompare(String a, String b) {
  final split = RegExp(r'\d+|\D+');
  final aa = split.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList(),
      bb = split.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < math.min(aa.length, bb.length); i++) {
    final an = int.tryParse(aa[i]), bn = int.tryParse(bb[i]);
    final comparison = an != null && bn != null
        ? an.compareTo(bn)
        : aa[i].compareTo(bb[i]);
    if (comparison != 0) return comparison;
  }
  return aa.length.compareTo(bb.length);
}

int compareFolders(String a, String b, List<Json> records, String order) {
  if (order == 'alphabet') return naturalCompare(a, b);
  num first(String folder) {
    final ids = records
        .where((w) => w['folder'] == folder)
        .map(
          (w) =>
              num.tryParse(
                RegExp(r'^\d+').firstMatch('${w['id']}')?.group(0) ?? '',
              ) ??
              0,
        );
    return ids.isEmpty ? 0 : ids.reduce(math.min);
  }

  final comparison = first(a).compareTo(first(b));
  return (comparison == 0 ? naturalCompare(a, b) : comparison) *
      (order == 'newest' ? -1 : 1);
}

String examHint(Json word) {
  final title = wordTitle(word),
      parts = title.split(',').map((p) => p.trim()).toList();
  final hasArticle = RegExp(
    r'\b(der|die|das)\b',
    caseSensitive: false,
  ).hasMatch(title);
  bool feminine(String text) => text
      .toLowerCase()
      .replaceFirst(RegExp(r'^(der|die|das)\s+'), '')
      .trim()
      .endsWith('in');
  var hints = <String>[];
  if (parts.length == 2 && parts[1].startsWith('-')) {
    hints = ['________', if (feminine(parts[0])) '(жен. р.)', '(plural)'];
  } else {
    for (var i = 0; i < parts.length; i++) {
      hints.add(
        feminine(parts[i])
            ? '(жен. р.)'
            : hasArticle && i > 0
            ? '(plural)'
            : '________',
      );
    }
    if ('${word['info1'] ?? ''}'.isNotEmpty) {
      hints.addAll(['Präsens', 'Präteritum', 'Partizip II']);
    }
  }
  if (hints.every((h) => h == '________')) {
    final count = title
        .replaceAll(RegExp(r'\s*\(.*?\)'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .length;
    if (count > 1) hints = ['Введите $count слова/слов'];
  }
  return hints.join(', ');
}

List<(int, int)> originalExampleHighlights(
  String text,
  String word,
  String forms,
) {
  final clean = '$word $forms'
      .replaceAll(RegExp(r'[()\[\]]'), ' ')
      .replaceAll(
        RegExp(
          r'\b(der|die|das|den|dem|des|ein|eine|einer|einem|einen)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'\b(ist|sind|war|waren|hat|haben|hatte|hatten|bin|bist|wird|werden|wurde)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[,.;:!?]'), ' ')
      .trim();
  final stems = <String>{};
  for (final token in clean.split(RegExp(r'\s+')).where((t) => t.length > 1)) {
    stems.add(token);
    if (token.length >= 5) stems.add(token.substring(0, token.length - 2));
  }
  if (stems.isEmpty) return [];
  final sorted = stems.toList()..sort((a, b) => b.length.compareTo(a.length));
  final pattern = sorted
      .map(
        (stem) => stem.length >= 4
            ? '[\\w]*${RegExp.escape(stem)}[\\w]*'
            : '\\b${RegExp.escape(stem)}[\\w]*',
      )
      .join('|');
  return RegExp(
    pattern,
    caseSensitive: false,
  ).allMatches(text).map((m) => (m.start, m.end)).toList();
}

class OriginalProgress extends StatelessWidget {
  const OriginalProgress({
    super.key,
    required this.value,
    this.height = 6,
    this.glow = false,
    this.color,
  });
  final double value, height;
  final bool glow;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final accent = color ?? originalSecondary(context);
    final fill = FractionallySizedBox(
      widthFactor: value.clamp(0, 1),
      heightFactor: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          gradient: LinearGradient(colors: [ink(context), accent]),
          boxShadow: [
            if (glow)
              BoxShadow(color: accent.withValues(alpha: .35), blurRadius: 12),
          ],
        ),
      ),
    );
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ink(context).withValues(alpha: .07),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          if (value > 0)
            Positioned.fill(
              child: Align(alignment: Alignment.centerLeft, child: fill),
            ),
        ],
      ),
    );
  }
}
