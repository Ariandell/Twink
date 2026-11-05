part of 'app.dart';

class _LearningGuide extends StatelessWidget {
  const _LearningGuide();
  Widget section(
    BuildContext context,
    String icon,
    String title,
    List<Widget> children,
  ) => Surface(
    radius: 24,
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Glyph(icon, size: 20, color: originalSecondary(context)),
            const SizedBox(width: 10),
            Expanded(
              child: label(
                title,
                size: 17.6,
                weight: FontWeight.w700,
                color: originalSecondary(context),
              ),
            ),
          ],
        ),
        gap(12),
        ...children,
      ],
    ),
  );
  Widget line(
    BuildContext context,
    String left,
    String right, {
    Color? color,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: ink(context).withValues(alpha: .05)),
      ),
    ),
    child: Row(
      children: [
        Expanded(child: label(left, size: 13.12)),
        label(
          right,
          size: 13.12,
          weight: FontWeight.w700,
          color: color ?? ink(context),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
    children: [
      section(context, 'trophy', 'Уровни владения', [
        label(
          'Ваш уровень рассчитывается на основе общего количества слов, достигнувших статуса Mastered (10 баллов):',
          size: 13.6,
          color: muted(context),
        ),
        gap(14),
        for (final level in <(String, String)>[
          ('A0 (Начальный)', '0+ слов'),
          ('A1 (Элементарный)', '500+ слов'),
          ('A2 (Предсредний)', '1000+ слов'),
          ('B1 (Средний)', '2000+ слов'),
          ('B2 (Выше среднего)', '4000+ слов'),
          ('C1 (Продвинутый)', '8000+ слов'),
          ('C2 (В совершенстве)', '16000+ слов'),
        ])
          line(context, level.$1, level.$2),
      ]),
      gap(20),
      section(context, 'star', 'Баллы в обучении', [
        for (final score in <(String, String, Color?)>[
          ('Отлично', '+3.0', const Color(0xff10b981)),
          ('Помню', '+1.5', const Color(0xff10b981)),
          ('Почти', '0.0', null),
          ('Частично', '-1.5', const Color(0xffef4444)),
          ('С трудом', '-3.0', const Color(0xffef4444)),
          ('Не помню', 'Сброс до 0', const Color(0xffef4444)),
        ])
          line(context, score.$1, score.$2, color: score.$3),
      ]),
      gap(20),
      section(context, 'clock', 'Как выучить слово?', [
        label(
          'Процесс освоения слова разделен на два этапа для лучшего запоминания:',
          size: 13.6,
          color: muted(context),
        ),
        gap(14),
        for (final step in <(String, String)>[
          (
            '1. Обучение (Flashcards)',
            'Наберите 9.0 баллов. После этого слово перестанет попадаться в обычных сессиях и будет ждать экзамена.',
          ),
          (
            '2. Экзамен (Final Test)',
            'Успешный ответ на экзамене дает финальный +1.0 балл. Слово становится Активным.',
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Surface(
              radius: 16,
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label(step.$1, size: 13.6, weight: FontWeight.w700),
                  gap(5),
                  label(step.$2, size: 12.8, color: muted(context)),
                ],
              ),
            ),
          ),
        label(
          'Ошибка на экзамене отнимает 3 балла, возвращая слово на этап обучения.',
          size: 13,
          color: muted(context),
        ),
      ]),
      gap(20),
      const _ExamRules(),
    ],
  );
}
