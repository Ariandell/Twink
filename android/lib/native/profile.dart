part of 'app.dart';

String formatSeconds(num seconds) {
  final n = seconds.floor().clamp(0, 1 << 40),
      h = n ~/ 3600,
      m = (n % 3600) ~/ 60,
      s = n % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
}

String levelFor(int mastered) => mastered >= 16000
    ? 'C2'
    : mastered >= 8000
    ? 'C1'
    : mastered >= 4000
    ? 'B2'
    : mastered >= 2000
    ? 'B1'
    : mastered >= 1000
    ? 'A2'
    : mastered >= 500
    ? 'A1'
    : 'A0';
num secondsOf(dynamic value) =>
    value is Map ? number(value['seconds']) : number(value);
Map<String, num> dailyStats(Json? data) =>
    asMap(asMap(data?['stats'])['daily'])
        .map((key, value) => MapEntry(key, secondsOf(value)));
(int, int) streakFor(Map<String, num> days) {
  final dates =
      days.entries
          .where((e) => e.value >= 900)
          .map((e) => DateTime.tryParse(e.key))
          .whereType<DateTime>()
          .toList()
        ..sort();
  var best = 0, run = 0;
  DateTime? previous;
  for (final date in dates) {
    run = previous != null && date.difference(previous).inDays == 1
        ? run + 1
        : 1;
    best = math.max(best, run);
    previous = date;
  }
  final today = DateTime.parse(logicalDay());
  if (dates.isEmpty || today.difference(dates.last).inDays > 1) {
    return (0, best);
  }
  var current = 1;
  for (var i = dates.length - 1; i > 0; i--) {
    if (dates[i].difference(dates[i - 1]).inDays != 1) break;
    current++;
  }
  return (current, best);
}

String? _decodedAvatar;
Uint8List? _avatarBytes;
ImageProvider? avatarImage(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  if (value.startsWith('https://')) return NetworkImage(value);
  if (_decodedAvatar != value) {
    _decodedAvatar = value;
    try {
      _avatarBytes = base64Decode(value.split(',').last);
    } catch (_) {
      _avatarBytes = null;
    }
  }
  return _avatarBytes == null ? null : MemoryImage(_avatarBytes!);
}

extension _ProfileView on _NativeHomeState {
  Widget _profile() {
    final words = store.words,
        mastered = words
            .where((w) => asMap(w['progress_global'])['is_ideal'] == true)
            .length;
    final percent = words.isEmpty ? 0 : (mastered * 100 / words.length).round(),
        active = words
            .where((w) => asMap(w['progress_global'])['isActive'] == true)
            .length;
    final days = dailyStats(store.data),
        streak = streakFor(days),
        today = DateTime.parse(logicalDay());
    num totalSince(DateTime date) => days.entries
        .where(
          (e) => !(DateTime.tryParse(e.key) ?? DateTime(1900)).isBefore(date),
        )
        .fold<num>(0, (a, e) => a + e.value);
    final name = '${store.data?['nickname'] ?? 'Пользователь'}',
        avatar = avatarImage(store.data?['avatar']);
    final fg = ink(context), secondary = originalSecondary(context);
    final badges = Wrap(
      spacing: 6,
      children: [
        _badge('trophy', '${levelFor(mastered)} ⓘ'),
        _badge('globe', 'German'),
      ],
    );
    return scrolling([
      Tap(
        label: 'Уровни владения',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const _LevelsPage()),
        ),
        child: Surface(
          glass: GlassKind.profile,
          blur: 25,
          strong: true,
          radius: 16,
          padding: const EdgeInsets.fromLTRB(10, 15, 16, 15),
          child: Row(
            children: [
              SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _Ring(percent / 100, secondary),
                      ),
                    ),
                    Container(
                      width: 70,
                      height: 70,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: fg.withValues(alpha: .025),
                        image: avatar == null
                            ? null
                            : DecorationImage(image: avatar, fit: BoxFit.cover),
                      ),
                      child: avatar == null
                          ? Center(
                              child: label(
                                name.isEmpty
                                    ? 'U'
                                    : name.characters.first.toUpperCase(),
                                size: 26,
                                weight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, c) =>
                          name.length * 10 + 145 < c.maxWidth
                          ? Row(
                              children: [
                                Expanded(
                                  child: label(
                                    name,
                                    size: 20,
                                    weight: FontWeight.w700,
                                    lines: 1,
                                  ),
                                ),
                                badges,
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                label(
                                  name,
                                  size: 18,
                                  weight: FontWeight.w700,
                                  lines: 1,
                                ),
                                gap(6),
                                badges,
                              ],
                            ),
                    ),
                    gap(10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        label(
                          'MASTERY LEVEL',
                          size: 10,
                          weight: FontWeight.w700,
                          color: muted(context),
                          spacing: 1.1,
                        ),
                        label('$percent%', size: 16, weight: FontWeight.w700),
                      ],
                    ),
                    gap(8),
                    OriginalProgress(
                      value: percent / 100,
                      color: secondary,
                      glow: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      gap(12),
      Surface(
        blur: 10,
        grouped: true,
        child: Column(
          children: [
            _groupTitle('link', 'Streak'),
            gap(16),
            Row(
              children: [
                Expanded(child: _streakNumber(streak.$1, 'CURRENT')),
                Expanded(child: _streakNumber(streak.$2, 'BEST')),
              ],
            ),
            gap(1),
          ],
        ),
      ),
      gap(16),
      Surface(
        blur: 10,
        grouped: true,
        child: Column(
          children: [
            _groupTitle('calendar', 'Total time'),
            gap(14),
            for (final row in <(String, num)>[
              (
                'This week',
                totalSince(today.subtract(Duration(days: today.weekday - 1))),
              ),
              ('This month', totalSince(DateTime(today.year, today.month))),
              ('This year', totalSince(DateTime(today.year))),
              ('All', days.values.fold<num>(0, (a, b) => a + b)),
            ])
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9.25),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: fg.withValues(alpha: .03)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    label(row.$1, color: muted(context), size: 14),
                    label(
                      formatSeconds(row.$2),
                      size: 14,
                      weight: FontWeight.w700,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      gap(16),
      _monthChart(days),
      gap(20),
      Row(
        children: [
          Expanded(
            child: Surface(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
              child: Row(
                children: [
                  Expanded(child: _count(words.length, 'Слов')),
                  Container(
                    width: 1,
                    height: 38,
                    color: fg.withValues(alpha: .08),
                  ),
                  Expanded(child: _count(store.idioms.length, 'Идиом')),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Surface(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
              child: _count(active, 'Активные слова', icon: 'zap'),
            ),
          ),
        ],
      ),
      gap(12),
      Surface(
        child: Row(
          children: [
            Expanded(child: _count(mastered, 'Слова', icon: 'star')),
            Expanded(
              child: _count(
                store.idioms
                    .where(
                      (w) => asMap(w['progress_global'])['is_ideal'] == true,
                    )
                    .length,
                'Идиомы',
                icon: 'star',
              ),
            ),
          ],
        ),
      ),
    ], top: 24);
  }

  Widget _badge(String icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: ink(context).withValues(alpha: .045),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: ink(context).withValues(alpha: .1)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Glyph(icon, size: 12),
        const SizedBox(width: 4),
        label(text, size: 10, weight: FontWeight.w700),
      ],
    ),
  );
  Widget _groupTitle(String icon, String text) => Row(
    children: [
      Glyph(icon, size: 20, color: muted(context).withValues(alpha: .7)),
      const SizedBox(width: 12),
      label(text, color: muted(context), weight: FontWeight.w500),
    ],
  );
  Widget _streakNumber(int n, String title) => Column(
    children: [
      label('$n DAYS', size: 24, weight: FontWeight.w900, spacing: -.8),
      gap(5),
      label(title, size: 10, color: muted(context), spacing: 1),
    ],
  );
  Widget _count(int n, String title, {String? icon}) => Column(
    children: [
      label('$n', size: 24, weight: FontWeight.w900),
      gap(5),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Glyph(icon, size: 11, color: muted(context)),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: label(
              title,
              size: 11,
              color: muted(context),
              align: TextAlign.center,
            ),
          ),
        ],
      ),
    ],
  );
  Widget _monthChart(Map<String, num> days) {
    const months = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];
    final count = DateTime(chartMonth.year, chartMonth.month + 1, 0).day;
    final values = List<num>.generate(
      count,
      (i) =>
          days['${chartMonth.year}-${chartMonth.month.toString().padLeft(2, '0')}-${(i + 1).toString().padLeft(2, '0')}'] ??
          0,
    );
    final maxValue = values.fold<num>(1, math.max),
        fg = ink(context),
        now = DateTime.parse(logicalDay());
    return Surface(
      blur: 15,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Square(
                'left',
                onTap: () => update(
                  () => chartMonth = DateTime(
                    chartMonth.year,
                    chartMonth.month - 1,
                  ),
                ),
                border: false,
                tooltip: 'Предыдущий месяц',
              ),
              Column(
                children: [
                  label(
                    months[chartMonth.month - 1],
                    size: 18,
                    weight: FontWeight.w700,
                  ),
                  label('${chartMonth.year}', size: 12, color: muted(context)),
                ],
              ),
              Square(
                'right',
                onTap: () => update(
                  () => chartMonth = DateTime(
                    chartMonth.year,
                    chartMonth.month + 1,
                  ),
                ),
                border: false,
                tooltip: 'Следующий месяц',
              ),
            ],
          ),
          gap(20),
          SizedBox(
            height: 166,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: count,
              itemExtent: 28,
              itemBuilder: (context, i) {
                final n = values[i],
                    barHeight = n == 0
                        ? 2.0
                        : math.max(4, n / maxValue * 116).toDouble(),
                    current =
                        now.year == chartMonth.year &&
                        now.month == chartMonth.month &&
                        now.day == i + 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (n > 0)
                        FittedBox(child: label(formatSeconds(n), size: 9)),
                      gap(5),
                      Container(
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: n > 0 ? fg : fg.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: n > 0
                              ? [
                                  BoxShadow(
                                    color: fg.withValues(alpha: .15),
                                    blurRadius: 10,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      gap(10),
                      label(
                        '${i + 1}',
                        size: 10,
                        color: current ? fg : muted(context),
                        weight: current ? FontWeight.w900 : FontWeight.w400,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends CustomPainter {
  const _Ring(this.progress, this.color);
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: .06);
    canvas.drawOval(rect, p);
    p.color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, p);
  }

  @override
  bool shouldRepaint(_Ring old) =>
      old.progress != progress || old.color != color;
}

class _LevelsPage extends StatelessWidget {
  const _LevelsPage();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Square(
                      'back',
                      onTap: () => Navigator.pop(context),
                      border: false,
                    ),
                    Expanded(
                      child: label(
                        'ИНСТРУКТАЖ',
                        weight: FontWeight.w700,
                        align: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              const Expanded(child: _LearningGuide()),
            ],
          ),
        ),
      ),
    ),
  );
}
