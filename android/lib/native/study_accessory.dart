part of 'app.dart';

class _StudyAccessoryBar extends StatelessWidget {
  const _StudyAccessoryBar({
    required this.mode,
    required this.frequency,
    required this.progress,
    required this.total,
    required this.remaining,
    required this.onMode,
    required this.minimal,
    required this.showProgress,
  });
  final String mode;
  final Json? frequency;
  final Json progress;
  final int total, remaining;
  final ValueChanged<String> onMode;
  final bool minimal, showProgress;
  static Color ratingColor(int r) => r <= 2
      ? const Color(0xffdba374)
      : r <= 4
      ? const Color(0xffb5adcf)
      : const Color(0xffa5c6b3);
  static const accent = Color(0xffb8c7dc);
  double get completed => total == 0 ? 0 : (total - remaining) / total;

  Widget _meter(BuildContext context) => Row(
    children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            key: const ValueKey('session-integrated-progress'),
            value: completed,
            minHeight: 3,
            color: accent,
            backgroundColor: ink(context).withValues(alpha: .09),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Semantics(
        label: 'Осталось $remaining из $total',
        child: label(
          '$remaining / $total',
          size: 11,
          weight: FontWeight.w600,
          color: muted(context),
        ),
      ),
    ],
  );

  Widget _details(
    BuildContext context,
    String name,
    String explanation,
    Widget child,
  ) => Tooltip(
    message: name,
    child: Tap(
      label: name,
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(name),
          content: Text(explanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Понятно'),
            ),
          ],
        ),
      ),
      child: SizedBox(height: 44, child: Center(child: child)),
    ),
  );

  List<Widget> _metrics(BuildContext context) {
    final data = asMap(frequency?['data']);
    final level = frequency == null ? null : number(data['frequency']).toInt();
    final score = progress['isActive'] == true
        ? 9.0
        : number(progress['excellentStreak']).clamp(0, 9).toDouble();
    final ratings =
        (progress['recentRatings'] is List
                ? progress['recentRatings'] as List
                : [
                    if (number(progress['lastRating']) >= 1)
                      progress['lastRating'],
                  ])
            .where((r) => number(r) >= 1 && number(r) <= 6)
            .toList();
    final tail = ratings.reversed.take(8).toList().reversed.toList();
    return [
      _details(
        context,
        'Частотность DWDS',
        level == null
            ? 'Данные DWDS для этого слова пока недоступны. Пустой индикатор не означает редкое слово.'
            : 'Ступень ${level + 1} из 7 по текстовым корпусам DWDS. Это частотность леммы со всеми её формами, а не оценка ваших знаний.\n\n${data['hits']} вхождений.\nИсточник: ${frequency!['source']}',
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++)
              Container(
                width: 5,
                height: 7.0 + i * 2.5,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: level != null && i <= level
                      ? accent
                      : ink(context).withValues(alpha: .1),
                ),
              ),
            if (level == null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: label('—', size: 11, color: muted(context)),
              ),
          ],
        ),
      ),
      _details(
        context,
        'Этап освоения слова',
        'Прогресс к экзамену: $score из 9 баллов по правилам Twink. Это этап обучения, а не вероятность запоминания.',
        SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  value: score / 9,
                  strokeWidth: 2.5,
                  color: const Color(0xffc6b9df),
                  backgroundColor: ink(context).withValues(alpha: .09),
                ),
              ),
              Glyph('star', size: 14, color: const Color(0xffc6b9df)),
            ],
          ),
        ),
      ),
      _details(
        context,
        'Последние оценки этого слова',
        tail.isEmpty
            ? 'Пока нет сохранённых оценок этого слова. Новые оценки будут накапливаться между сессиями.'
            : 'От старой к новой: ${tail.map((r) => ratingNames[number(r).toInt()]).join(' → ')}',
        SizedBox(
          width: 50,
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (var i = 0; i < 8; i++)
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < tail.length
                        ? ratingColor(number(tail[i]).toInt())
                        : Colors.transparent,
                    border: i < tail.length
                        ? null
                        : Border.all(
                            color: ink(context).withValues(alpha: .16),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _menu(BuildContext context) => SizedBox(
    width: 36,
    height: 44,
    child: PopupMenuButton<String>(
      tooltip: 'Вариант нижней панели',
      initialValue: mode,
      padding: EdgeInsets.zero,
      icon: Glyph('more-horizontal', size: 18, color: muted(context)),
      onSelected: onMode,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'ribbon', child: Text('Капсула над навигацией')),
        PopupMenuItem(value: 'tiles', child: Text('Три плитки')),
        PopupMenuItem(value: 'underCard', child: Text('Под карточкой')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (minimal) {
      return SizedBox(
        key: const ValueKey('study-accessory'),
        height: 12,
        child: _meter(context),
      );
    }
    final metrics = _metrics(context);
    final row = Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0 && mode != 'tiles')
            Container(
              width: 1,
              height: 22,
              color: ink(context).withValues(alpha: .07),
            ),
          Expanded(
            child: mode == 'tiles'
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Surface(
                      radius: 14,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: metrics[i],
                    ),
                  )
                : metrics[i],
          ),
        ],
        _menu(context),
      ],
    );
    final footer = showProgress
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _meter(context),
          )
        : const SizedBox(height: 8);
    return SizedBox(
      key: const ValueKey('study-accessory'),
      height: mode == 'tiles' ? 88 : 76,
      child: mode == 'tiles'
          ? Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [row, footer],
            )
          : Surface(
              radius: 20,
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [row, footer],
              ),
            ),
    );
  }
}
