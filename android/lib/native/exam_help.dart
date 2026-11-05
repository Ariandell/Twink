part of 'app.dart';

class _ExamHelpPage extends StatelessWidget {
  const _ExamHelpPage();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 40, 12, 40),
              children: [
                Surface(
                  radius: 24,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label(
                        'Правила Экзамена',
                        size: 17.6,
                        weight: FontWeight.w700,
                      ),
                      gap(12),
                      label(
                        'На экзамене проверяется знание основной формы слова и всех его форм (для глаголов).',
                        size: 13.6,
                        color: muted(context),
                      ),
                      gap(20),
                      label(
                        'Основные правила:',
                        size: 14.4,
                        weight: FontWeight.w700,
                      ),
                      gap(8),
                      for (final rule in [
                        ('Одна строка', 'Все слова пишутся подряд'),
                        ('Артикли', 'Первый артикль обязателен'),
                        ('Порядок', 'Внутри форм порядок важен'),
                      ])
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: ink(context).withValues(alpha: .05),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: label(rule.$1, size: 13.12)),
                              Expanded(
                                child: label(
                                  rule.$2,
                                  size: 13.12,
                                  color: muted(context),
                                  align: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        ),
                      gap(20),
                      label('Подсказки:', size: 14.4, weight: FontWeight.w700),
                      gap(8),
                      for (final hint in [
                        (
                          '________',
                          'Введите основное немецкое слово (инфинитив).',
                        ),
                        (
                          'Präsens, Präteritum, Partizip II',
                          'Введите все три формы глагола. Порядок форм не критичен.',
                        ),
                        (
                          '(plural)',
                          'Обязательно записать множественное число слова (через запятую или пробел).',
                        ),
                        (
                          '(жен. р.)',
                          'Укажите женскую форму слова, если она есть в задании.',
                        ),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Surface(
                            radius: 12,
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                label(hint.$1, size: 12.8),
                                gap(4),
                                label(hint.$2, size: 12, color: muted(context)),
                              ],
                            ),
                          ),
                        ),
                      gap(20),
                      label(
                        'Цвета проверки:',
                        size: 14.4,
                        weight: FontWeight.w700,
                      ),
                      gap(8),
                      for (final state in <(Color, String)>[
                        (
                          const Color(0xff10b981),
                          'Зеленый — полный верный ответ. +1б',
                        ),
                        (
                          const Color(0xff3b82f6),
                          'Синий — верно, но в форме глагола ist/hat указан только один из вариантов. +1б',
                        ),
                        (
                          const Color(0xff8b5cf6),
                          'Фиолетовый — ошибка в артикле или в порядке слов. -1.5б',
                        ),
                        (
                          const Color(0xffef4444),
                          'Красный — орфографическая ошибка или неполный ответ. -3б',
                        ),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Surface(
                            radius: 12,
                            padding: const EdgeInsets.all(10),
                            background: state.$1.withValues(alpha: .03),
                            borderColor: state.$1.withValues(alpha: .05),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: state.$1,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: label(state.$2, size: 12)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
