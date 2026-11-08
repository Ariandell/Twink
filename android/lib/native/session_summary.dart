part of 'app.dart';

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({
    required this.exam,
    required this.title,
    required this.results,
    required this.seconds,
    required this.onStudy,
    required this.onDictionary,
  });
  final bool exam;
  final String title;
  final List<Json> results;
  final int seconds;
  final VoidCallback onStudy, onDictionary;
  @override
  Widget build(BuildContext context) {
    final remembered = results
        .where((r) => exam ? r['correct'] == true : number(r['rating']) >= 5)
        .length;
    final difficult = results
        .where((r) => exam ? r['correct'] != true : number(r['rating']) <= 3)
        .toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onStudy();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                      children: [
                        Center(
                          child: Surface(
                            radius: 30,
                            padding: const EdgeInsets.all(18),
                            child: const Glyph(
                              'check-circle',
                              size: 32,
                              color: Color(0xffa5c6b3),
                            ),
                          ),
                        ),
                        gap(24),
                        label(
                          results.isEmpty
                              ? 'Пока нечего повторять'
                              : exam
                              ? 'Экзамен завершён'
                              : 'Сессия завершена',
                          size: 28,
                          weight: FontWeight.w700,
                          align: TextAlign.center,
                        ),
                        gap(8),
                        label(
                          title,
                          size: 14,
                          color: muted(context),
                          align: TextAlign.center,
                        ),
                        gap(28),
                        Surface(
                          radius: 20,
                          padding: const EdgeInsets.symmetric(
                            vertical: 20,
                            horizontal: 12,
                          ),
                          child: Row(
                            children: [
                              for (final stat in [
                                (results.length.toString(), 'Карточек'),
                                (
                                  remembered.toString(),
                                  exam ? 'Верно' : 'Уверенно',
                                ),
                                (formatSeconds(seconds), 'Активное время'),
                              ])
                                Expanded(
                                  key: ValueKey('summary-${stat.$2}'),
                                  child: Column(
                                    children: [
                                      label(
                                        stat.$1,
                                        size: 24,
                                        weight: FontWeight.w700,
                                      ),
                                      gap(6),
                                      label(
                                        stat.$2,
                                        size: 11,
                                        color: muted(context),
                                        align: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (results.isNotEmpty) ...[
                          gap(28),
                          label(
                            exam ? 'Результат экзамена' : 'Ваши оценки',
                            size: 17,
                            weight: FontWeight.w700,
                          ),
                          gap(12),
                          if (exam) ...[
                            _resultRow(
                              context,
                              'Правильно',
                              remembered,
                              results.length,
                              const Color(0xffa5c6b3),
                            ),
                            _resultRow(
                              context,
                              'С ошибкой',
                              results.length - remembered,
                              results.length,
                              const Color(0xffdba374),
                            ),
                          ] else
                            for (var rating = 1; rating <= 6; rating++)
                              _resultRow(
                                context,
                                ratingNames[rating],
                                results
                                    .where((r) => r['rating'] == rating)
                                    .length,
                                results.length,
                                _StudyAccessoryBar.ratingColor(rating),
                              ),
                          if (difficult.isNotEmpty) ...[
                            gap(24),
                            label(
                              'Стоит закрепить',
                              size: 17,
                              weight: FontWeight.w700,
                            ),
                            gap(10),
                            for (final word in difficult.take(5))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Surface(
                                  radius: 12,
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      label(
                                        wordTitle(word),
                                        size: 15,
                                        weight: FontWeight.w700,
                                      ),
                                      gap(4),
                                      label(
                                        '${word['translation'] ?? ''}',
                                        size: 13,
                                        color: muted(context),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                          gap(16),
                          label(
                            'Прогресс карточек сохранён',
                            size: 12,
                            color: muted(context),
                            align: TextAlign.center,
                          ),
                        ] else ...[
                          gap(20),
                          label(
                            'Выберите другую папку или добавьте новые слова в словарь.',
                            size: 15,
                            color: muted(context),
                            align: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Pill(
                            'К обучению',
                            onTap: onStudy,
                            primary: true,
                          ),
                        ),
                        gap(10),
                        SizedBox(
                          width: double.infinity,
                          child: Pill('Открыть словарь', onTap: onDictionary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultRow(
    BuildContext context,
    String name,
    int count,
    int total,
    Color color,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 94,
          child: label(name, size: 13, color: muted(context)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : count / total,
              minHeight: 6,
              color: color,
              backgroundColor: ink(context).withValues(alpha: .06),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 22,
          child: label(
            '$count',
            size: 14,
            align: TextAlign.right,
            weight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
