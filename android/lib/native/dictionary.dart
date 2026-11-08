part of 'app.dart';

const entryFields = {
  'words': [
    ['word', 'Немецкое слово'],
    ['translation', 'Перевод'],
    ['info1', 'Формы глагола'],
    ['info2', 'Дополнительно'],
    ['ex1', 'Пример 1'],
    ['ex2', 'Пример 2'],
    ['folder', 'Папка'],
  ],
  'idioms': [
    ['idiom', 'Идиома'],
    ['translation', 'Перевод'],
    ['meaning', 'Смысловой перевод'],
    ['info', 'Дополнительно'],
    ['example', 'Пример'],
    ['folder', 'Папка'],
  ],
};

List<List<String>> dictionaryColumns(String kind) => [
  ['id', 'ID'],
  if (kind == 'words') ['active', 'Актив'],
  ['ideal', 'Идеально'],
  ...entryFields[kind]!,
  ['interval', 'Интервал'],
  ['nextDate', 'След. повтор'],
  if (kind == 'words') ['frequency', 'Употребительность'],
];
String dictionaryValue(Json w, String key) {
  final p = asMap(w['progress_global']);
  return switch (key) {
    'active' =>
      p['isActive'] == true
          ? 'Актив'
          : number(p['excellentStreak']) > 0
          ? '${p['excellentStreak']}'.replaceAll('.', ',')
          : '—',
    'ideal' => p['is_ideal'] == true ? 'Идеально' : '—',
    'interval' => _intervalText(number(p['interval'])),
    'nextDate' =>
      number(p['interval']) > 0 && number(p['nextDate']) > 0
          ? _nextDate(number(p['nextDate']).toInt())
          : '—',
    _ => '${w[key] ?? ''}',
  };
}

String _nextDate(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

extension _DictionaryView on _NativeHomeState {
  List<Json> get filteredEntries {
    var list = entries.where((w) {
      final q = DwdsDictionary.fold(query).trim();
      return q.isEmpty ||
          DwdsDictionary.fold(
            '${wordTitle(w)} ${w['translation'] ?? ''} ${w['info1'] ?? w['meaning'] ?? ''} ${w['info2'] ?? w['info'] ?? ''}',
          ).contains(q);
    }).toList();
    if (duplicates) {
      final counts = <String, int>{};
      for (final w in entries) {
        final k = duplicateKey(wordTitle(w));
        counts[k] = (counts[k] ?? 0) + 1;
      }
      list = list
          .where((w) => (counts[duplicateKey(wordTitle(w))] ?? 0) > 1)
          .toList();
    }
    list = list.where((w) {
      final p = asMap(w['progress_global']);
      return (scoreFilters.isEmpty ||
              scoreFilters.contains(number(p['excellentStreak']))) &&
          (intervalFilters.isEmpty ||
              intervalFilters.contains(number(p['interval'])));
    }).toList();
    list.sort((a, b) {
      final pa = asMap(a['progress_global']), pb = asMap(b['progress_global']);
      return switch (sort) {
        'alphabet' => wordTitle(
          a,
        ).toLowerCase().compareTo(wordTitle(b).toLowerCase()),
        'interval' => number(pa['interval']).compareTo(number(pb['interval'])),
        'date_asc' => number(pa['nextDate']).compareTo(number(pb['nextDate'])),
        'date_desc' => number(pb['nextDate']).compareTo(number(pa['nextDate'])),
        'newest' => number(b['id']).compareTo(number(a['id'])),
        _ => number(a['id']).compareTo(number(b['id'])),
      };
    });
    return list;
  }

  Widget _dictionary() {
    final list = filteredEntries,
        fg = ink(context),
        wide = MediaQuery.sizeOf(context).width > 768;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                Row(
                  children: [
                    for (final k in ['words', 'idioms'])
                      Expanded(
                        child: Tap(
                          onTap: () => update(() => kind = k),
                          label: k == 'words' ? 'Слова' : 'Идиомы',
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: kind == k
                                      ? fg
                                      : fg.withValues(alpha: .08),
                                  width: kind == k ? 2 : 1,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                label(
                                  k == 'words' ? 'Слова' : 'Идиомы',
                                  weight: kind == k
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: kind == k ? fg : muted(context),
                                ),
                                const SizedBox(width: 5),
                                label(
                                  '${k == 'words' ? store.words.length : store.idioms.length}',
                                  size: 10,
                                  color: muted(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                gap(14),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: fg.withValues(alpha: .16)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Glyph('search', size: 18, color: muted(context)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: searches,
                                onChanged: (s) => update(() => query = s),
                                decoration: const InputDecoration(
                                  hintText: 'Мои карточки и DWDS',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            if (query.isNotEmpty)
                              Square(
                                'close',
                                size: 28,
                                border: false,
                                tooltip: 'Очистить поиск',
                                onTap: () {
                                  searches.clear();
                                  update(() => query = '');
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Square('filter', onTap: _filters, tooltip: 'Фильтры'),
                    const SizedBox(width: 8),
                    Tap(
                      label: kind == 'words'
                          ? 'Добавить слово'
                          : 'Добавить идиому',
                      onTap: () => _editEntry(kind),
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: fg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Glyph(
                          'plus',
                          color: Theme.of(context).scaffoldBackgroundColor,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Square(
                      'download',
                      onTap: () => _export(kind),
                      tooltip: 'Скачать таблицу (Excel)',
                    ),
                  ],
                ),
                if (scoreFilters.isNotEmpty ||
                    intervalFilters.isNotEmpty ||
                    duplicates)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        label(
                          'Найдено: ${list.length}',
                          size: 12,
                          color: muted(context),
                        ),
                        const Spacer(),
                        Tap(
                          onTap: () => update(() {
                            scoreFilters.clear();
                            intervalFilters.clear();
                            duplicates = false;
                          }),
                          child: label(
                            'Сбросить',
                            size: 12,
                            color: muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (query.trim().isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverToBoxAdapter(
              child: _UnifiedSearchResults(
                key: ValueKey('unified-search-$kind'),
                query: query,
                own: list,
                allOwn: entries,
                ownBuilder: _entryCard,
                kind: kind,
                store: store,
                dictionary: widget.dictionary ?? DwdsDictionary.shared,
              ),
            ),
          )
        else if (list.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: label(
                entries.isEmpty
                    ? 'Словарь пуст. Добавьте слово или загрузите Excel.'
                    : 'Ничего не найдено',
                align: TextAlign.center,
                color: muted(context),
              ),
            ),
          )
        else if (wide)
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              primary: false,
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final f in dictionaryColumns(kind))
                    if (visibleColumns.contains(f[0]))
                      DataColumn(label: Text(f[1])),
                  const DataColumn(label: Text('Действия')),
                ],
                rows: list
                    .map(
                      (w) => DataRow(
                        cells: [
                          for (final f in dictionaryColumns(kind))
                            if (visibleColumns.contains(f[0]))
                              DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 240,
                                  ),
                                  child: Text(dictionaryValue(w, f[0])),
                                ),
                              ),
                          DataCell(
                            Row(
                              children: [
                                Square(
                                  'edit',
                                  iconSize: 16,
                                  tooltip: 'Редактировать',
                                  onTap: () => _editEntry(kind, w),
                                  border: false,
                                ),
                                Square(
                                  'trash',
                                  iconSize: 16,
                                  color: const Color(0xffef4444)
                                      .withValues(alpha: .7),
                                  tooltip: 'Удалить',
                                  onTap: () => _deleteEntry(kind, w),
                                  border: false,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList.builder(
              itemCount: list.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _entryCard(list[index]),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 112)),
      ],
    );
  }

  Widget _entryCard(Json w) {
    final p = asMap(w['progress_global']),
        fg = ink(context),
        isIdiom = kind == 'idioms';
    return Surface(
      radius: 10,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: visibleColumns.contains(isIdiom ? 'idiom' : 'word')
                    ? label(wordTitle(w), size: 15, weight: FontWeight.w900)
                    : const SizedBox(),
              ),
              Square(
                'edit',
                color: muted(context),
                size: 32,
                iconSize: 16,
                border: false,
                tooltip: 'Редактировать',
                onTap: () => _editEntry(kind, w),
              ),
              Square(
                'trash',
                color: const Color(0xffef4444).withValues(alpha: .7),
                size: 32,
                iconSize: 16,
                border: false,
                tooltip: 'Удалить',
                onTap: () => _deleteEntry(kind, w),
              ),
            ],
          ),
          if (visibleColumns.contains('translation'))
            label(
              '${w['translation'] ?? ''}',
              size: 14,
              weight: FontWeight.w700,
            ),
          gap(8),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              for (final field
                  in isIdiom ? ['meaning', 'info'] : ['info1', 'info2'])
                if ('${w[field] ?? ''}'.isNotEmpty &&
                    visibleColumns.contains(field))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: .045),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: label(
                      '${w[field]}',
                      size: 11,
                      color: muted(context),
                    ),
                  ),
            ],
          ),
          for (final field in isIdiom ? ['example'] : ['ex1', 'ex2'])
            if ('${w[field] ?? ''}'.isNotEmpty &&
                visibleColumns.contains(field))
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Container(
                  padding: const EdgeInsets.only(left: 7),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: fg.withValues(alpha: .15)),
                    ),
                  ),
                  child: label('${w[field]}', size: 12, color: muted(context)),
                ),
              ),
          gap(12),
          Row(
            children: [
              if (visibleColumns.contains('interval')) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff6366f1).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: label(
                    _intervalText(number(p['interval'])),
                    size: 11,
                    color: muted(context),
                    weight: FontWeight.w700,
                  ),
                ),
              ],
              if (visibleColumns.contains('active')) ...[
                const SizedBox(width: 6),
                if (number(p['excellentStreak']) > 0)
                  label(
                    '${p['excellentStreak']}',
                    size: 11,
                    color: muted(context),
                  ),
                if (p['isActive'] == true) ...[
                  const SizedBox(width: 5),
                  Glyph('zap', size: 12, color: muted(context)),
                ],
              ],
              if (visibleColumns.contains('ideal') &&
                  p['is_ideal'] == true) ...[
                const SizedBox(width: 6),
                Glyph('star', size: 12, color: originalSecondary(context)),
              ],
              const SizedBox(width: 8),
              if (visibleColumns.contains('folder'))
                Expanded(
                  child: label(
                    '${w['folder'] ?? ''}',
                    size: 10,
                    color: muted(context),
                    lines: 1,
                  ),
                )
              else
                const Spacer(),
              if (visibleColumns.contains('id'))
                label(
                  '${w['id']}',
                  size: 10,
                  color: muted(context).withValues(alpha: .55),
                ),
            ],
          ),
          if (visibleColumns.contains('nextDate') &&
              number(p['interval']) > 0 &&
              number(p['nextDate']) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: label(
                  _nextDate(number(p['nextDate']).toInt()),
                  size: 10,
                  color: muted(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<Json?> _editEntry(String k, [Json? old, String? folder]) async {
    await audio.speech.stop();
    if (!mounted) return null;
    return Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _EntryEditor(store: store, kind: k, original: old, folder: folder),
      ),
    );
  }

  Future<void> _deleteEntry(String k, Json w) async {
    if (await nativeConfirm(context, 'Удалить «${wordTitle(w)}»?')) {
      await run(() => store.patch({'$k/${w['id']}': null}));
    }
  }

  Future<void> _export(String k) async {
    if (exporting) return;
    exporting = true;
    try {
      final list = List<Json>.from(k == 'words' ? store.words : store.idioms)
        ..sort((a, b) => number(a['id']).compareTo(number(b['id'])));
      final bytes = await compute(_encodeExport, (list, k));
      await FilePicker.saveFile(
        fileName: k == 'words'
            ? 'WordLab_dictionary.xlsx'
            : 'WordLab_idioms.xlsx',
        bytes: bytes,
      );
    } catch (e) {
      if (mounted) notify(context, e);
    } finally {
      exporting = false;
    }
  }

  Future<void> _filters() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть фильтры',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (c, a, b, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: a, curve: const Cubic(.16, 1, .3, 1)),
        ),
        child: child,
      ),
      pageBuilder: (c, a, b) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: math.min(MediaQuery.sizeOf(c).width * .8, 300),
          height: double.infinity,
          child: Material(
            type: MaterialType.transparency,
            child: NativeGlass(
              kind: GlassKind.overlay,
              blur: 25,
              radius: 0,
              gradient: LinearGradient(
                colors: [
                  Theme.of(c).scaffoldBackgroundColor.withValues(alpha: .95),
                  Theme.of(c).scaffoldBackgroundColor.withValues(alpha: .95),
                ],
              ),
              child: SafeArea(
                child: StatefulBuilder(
                  builder: (c, refresh) {
                    void change(VoidCallback action, {bool columns = false}) {
                      update(action);
                      if (columns) {
                        prefs.set('columns-$kind', visibleColumns.toList());
                      }
                      refresh(() {});
                    }

                    Widget check(
                      String text,
                      bool value,
                      ValueChanged<bool> action,
                    ) => CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                      title: label(text, size: 13),
                      value: value,
                      onChanged: (v) => action(v == true),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: ink(c),
                      checkColor: Theme.of(c).scaffoldBackgroundColor,
                    );
                    Widget menu(String text, List<Widget> choices) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _FilterMenu(text: text, choices: choices),
                    );
                    const sorts = {
                      'oldest': 'Старые',
                      'newest': 'Новые',
                      'alphabet': 'По алфавиту',
                      'interval': 'По интервалу',
                      'date_asc': 'Дата повторения ↑',
                      'date_desc': 'Дата повторения ↓',
                    };
                    return ListView(
                      primary: false,
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Square(
                            'close',
                            onTap: () => Navigator.pop(c),
                            border: false,
                          ),
                        ),
                        gap(18),
                        menu('Столбцы', [
                          for (final f in dictionaryColumns(kind))
                            check(
                              f[1],
                              visibleColumns.contains(f[0]),
                              (v) => change(
                                () => v
                                    ? visibleColumns.add(f[0])
                                    : visibleColumns.remove(f[0]),
                                columns: true,
                              ),
                            ),
                        ]),
                        menu(
                          intervalFilters.isEmpty
                              ? 'Интервалы: Все'
                              : 'Интервалы: ${intervalFilters.length}',
                          [
                            for (final n in [
                              0,
                              1 / 24,
                              1,
                              2,
                              4,
                              7,
                              9,
                              12,
                              17,
                              21,
                            ])
                              check(
                                _intervalText(n),
                                intervalFilters.contains(n),
                                (v) => change(
                                  () => v
                                      ? intervalFilters.add(n)
                                      : intervalFilters.remove(n),
                                ),
                              ),
                          ],
                        ),
                        menu(
                          scoreFilters.isEmpty
                              ? 'Баллы'
                              : 'Баллы: ${scoreFilters.length}',
                          [
                            for (final n in [0, 1.5, 3, 4.5, 6, 7.5, 9, 10])
                              check(
                                n.toString(),
                                scoreFilters.contains(n),
                                (v) => change(
                                  () => v
                                      ? scoreFilters.add(n)
                                      : scoreFilters.remove(n),
                                ),
                              ),
                          ],
                        ),
                        menu(sorts[sort] ?? 'Старые', [
                          for (final option in sorts.entries)
                            Tap(
                              label: option.value,
                              onTap: () => change(() => sort = option.key),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      child: sort == option.key
                                          ? const Glyph('check', size: 16)
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: label(option.value, size: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ]),
                        Surface(
                          radius: 12,
                          padding: EdgeInsets.zero,
                          child: check(
                            'Повторки',
                            duplicates,
                            (v) => change(() => duplicates = v),
                          ),
                        ),
                        gap(16),
                        label(
                          'Найдено: ${filteredEntries.length}',
                          size: 12,
                          color: muted(c),
                          align: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _importPage() => scrolling([
    label('Импорт слов', size: 18, weight: FontWeight.w700),
    gap(24),
    Tap(
      onTap: _chooseImport,
      child: Surface(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xff6366f1).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Glyph('upload', size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label('Выбрать файл', size: 18, weight: FontWeight.w700),
                  gap(5),
                  label(
                    'Нажмите, чтобы загрузить .xlsx',
                    color: muted(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    gap(28),
    _importGuide(
      'Структура Excel файла',
      'Данные должны располагаться в колонках A–J. Заголовки необязательны.',
      [
        'ID',
        'Активное слово (yes/no) или балл',
        'Немецкое слово',
        'Перевод',
        'Формы глагола',
        'Дополнительно',
        'Пример 1',
        'Пример 2',
        'Название папки',
        'Идеально (true/false)',
      ],
    ),
    gap(24),
    _importGuide(
      'Структура Excel для идиом',
      'Для идиом используйте колонки A–G. Система автоматически определит тип данных.',
      [
        'ID',
        'Идиома',
        'Перевод',
        'Смысловой перевод',
        'Дополнительно',
        'Пример',
        'Название папки',
      ],
    ),
  ]);
  Widget _importGuide(String title, String description, List<String> columns) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Glyph('book', size: 22),
              const SizedBox(width: 12),
              Expanded(child: label(title, size: 18, weight: FontWeight.w700)),
            ],
          ),
          gap(16),
          Surface(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label(description, color: muted(context)),
                gap(20),
                for (var i = 0; i < columns.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Surface(
                      radius: 10,
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: ink(context),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: label(
                              String.fromCharCode(65 + i),
                              weight: FontWeight.w700,
                              color: Theme.of(context).scaffoldBackgroundColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: label(columns[i], size: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
  Future<void> _chooseImport() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (file == null) return;
      final rows = await compute(decodeSpreadsheet, await file.readAsBytes());
      final header = rows.isEmpty
          ? ''
          : rows.first.map((e) => '$e'.toLowerCase()).join(' ');
      final k =
          RegExp('идиом|idiom|смыслов').hasMatch(header) ||
              (rows.isNotEmpty && rows.first.length <= 7)
          ? 'idioms'
          : 'words';
      final existing = asMap(store.data?[k]),
          preview = importRows(rows, k, existing);
      if (!mounted) return;
      if (!await nativeConfirm(
        context,
        'Импорт ${k == 'words' ? 'слов' : 'идиом'}: добавить ${preview['created']}, обновить ${preview['updated']}?',
      )) {
        return;
      }
      await store.importRecords(k, rows);
      if (mounted) {
        notify(
          context,
          'Импорт завершен: добавлено ${preview['created']}, обновлено ${preview['updated']}',
        );
      }
    } catch (e) {
      if (mounted) notify(context, e);
    }
  }
}

String _intervalText(num days) => days > 0 && days < 1
    ? '1 час'
    : '${days == days.roundToDouble() ? days.toInt() : days} дн.';

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({
    required this.store,
    required this.kind,
    this.original,
    this.folder,
  });
  final TwinkStore store;
  final String kind;
  final Json? original;
  final String? folder;
  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final inputs = {
    for (final f in entryFields[widget.kind]!)
      f[0]: TextEditingController(
        text:
            '${widget.original?[f[0]] ?? (f[0] == 'folder' ? widget.folder ?? '' : '')}',
      ),
  };
  bool busy = false;
  @override
  void dispose() {
    for (final c in inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    final record = <String, dynamic>{
      if (widget.original != null) 'id': widget.original!['id'],
      for (final e in inputs.entries) e.key: e.value.text.trim(),
    };
    if (wordTitle(record).isEmpty || '${record['translation']}'.isEmpty) {
      notify(context, 'Заполните слово и перевод');
      return;
    }
    setState(() => busy = true);
    try {
      final id = await widget.store.save(widget.kind, record);
      if (mounted) {
        Navigator.pop(context, {...widget.original ?? {}, ...record, 'id': id});
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        notify(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: ink(context).withValues(alpha: .1)),
              ),
            ),
            child: Row(
              children: [
                Square(
                  'back',
                  onTap: () => Navigator.pop(context),
                  border: false,
                  tooltip: 'Выйти',
                ),
                Expanded(
                  child: Column(
                    children: [
                      label(
                        widget.original == null ? 'ДОБАВИТЬ' : 'РЕДАКТИРОВАТЬ',
                        size: 14,
                        weight: FontWeight.w700,
                      ),
                      if (widget.original != null)
                        label(
                          '#${widget.original!['id']}',
                          size: 10,
                          color: muted(context),
                        ),
                    ],
                  ),
                ),
                busy
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Square(
                        'check',
                        onTap: save,
                        border: false,
                        tooltip: 'Сохранить',
                      ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                for (final f in entryFields[widget.kind]!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: TextField(
                      controller: inputs[f[0]],
                      maxLines: null,
                      style: const TextStyle(fontSize: 16, height: 1.4),
                      decoration: InputDecoration(
                        hintText: f[1],
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 18,
                        ),
                      ),
                      textCapitalization: TextCapitalization.none,
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

class _FolderEditor extends StatefulWidget {
  const _FolderEditor({required this.store, required this.kind, this.folder});
  final TwinkStore store;
  final String kind;
  final String? folder;
  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late String kind = widget.kind;
  late final name = TextEditingController(text: widget.folder ?? '');
  late final description = TextEditingController(
    text:
        asMap(
              asMap(
                widget.store.data?[kind == 'words'
                    ? 'folderMeta'
                    : 'idiomFolders'],
              )[widget.folder],
            )['description']
            as String? ??
        '',
  );
  late final List<Json> draft = widget.folder == null
      ? [{}]
      : (kind == 'words' ? widget.store.words : widget.store.idioms)
            .where((e) => e['folder'] == widget.folder && widget.folder != null)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
  final deleted = <String>[];
  bool busy = false;
  void toggleKind() {
    if (widget.folder != null) return;
    setState(() {
      final pairs = kind == 'words'
          ? {
              'word': 'idiom',
              'info1': 'meaning',
              'info2': 'info',
              'ex1': 'example',
            }
          : {
              'idiom': 'word',
              'meaning': 'info1',
              'info': 'info2',
              'example': 'ex1',
            };
      for (final record in draft) {
        for (final pair in pairs.entries) {
          record[pair.value] = record[pair.key] ?? '';
        }
      }
      kind = kind == 'words' ? 'idioms' : 'words';
    });
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    final folder = name.text.trim().isEmpty ? 'Новая папка' : name.text.trim();
    if (RegExp(r'[.#$\[\]/]').hasMatch(folder)) {
      notify(context, r'Введите название папки без . # $ [ ] /');
      return;
    }
    final valid = draft
        .where(
          (record) =>
              '${record[kind == 'words' ? 'word' : 'idiom'] ?? ''}'
                  .trim()
                  .isNotEmpty &&
              '${record['translation'] ?? ''}'.trim().isNotEmpty,
        )
        .toList();
    if (valid.isEmpty) {
      notify(context, 'Добавьте хотя бы одно слово.');
      return;
    }
    setState(() => busy = true);
    try {
      final meta = kind == 'words' ? 'folderMeta' : 'idiomFolders';
      final oldMeta = asMap(
        asMap(widget.store.data?[meta])[widget.folder ?? folder],
      );
      final changes = <String, dynamic>{
        '$meta/$folder': {
          ...oldMeta,
          'name': folder,
          'description': description.text.trim(),
          'type': oldMeta['type'] ?? 'manual',
          'createdAt':
              oldMeta['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
        },
        for (final id in deleted) '$kind/$id': null,
      };
      if (widget.folder != null && widget.folder != folder) {
        changes['$meta/${widget.folder}'] = null;
      }
      for (final record in valid.where((e) => e['id'] != null)) {
        for (final f in entryFields[kind]!) {
          changes['$kind/${record['id']}/${f[0]}'] = f[0] == 'folder'
              ? folder
              : record[f[0]] ?? '';
        }
      }
      await widget.store.patch(changes);
      for (final record in valid.where((e) => e['id'] == null)) {
        await widget.store.save(kind, {
          for (final field in entryFields[kind]!)
            field[0]: record[field[0]] ?? '',
          'folder': folder,
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        notify(context, e);
      }
    }
  }

  Future<void> delete() async {
    if (widget.folder == null) return;
    if (!await nativeConfirm(
      context,
      'Удалить папку «${widget.folder}» и все слова в ней?',
    )) {
      return;
    }
    try {
      await widget.store.patch({
        for (final w
            in (kind == 'words' ? widget.store.words : widget.store.idioms)
                .where((e) => e['folder'] == widget.folder))
          '$kind/${w['id']}': null,
        '${kind == 'words' ? 'folderMeta' : 'idiomFolders'}/${widget.folder}':
            null,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) notify(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                NativeGlass(
                  kind: GlassKind.navigation,
                  radius: 99,
                  blur: 20,
                  child: Square(
                    'back',
                    size: 48,
                    onTap: () => Navigator.pop(context),
                    border: false,
                    tooltip: 'Назад',
                  ),
                ),
                const Spacer(),
                if (widget.folder != null)
                  MenuAnchor(
                    menuChildren: [
                      MenuItemButton(
                        onPressed: delete,
                        child: Row(
                          children: [
                            const Glyph(
                              'trash',
                              size: 16,
                              color: Color(0xffff4b4b),
                            ),
                            const SizedBox(width: 8),
                            label(
                              'Удалить папку',
                              size: 14,
                              color: const Color(0xffff4b4b),
                            ),
                          ],
                        ),
                      ),
                    ],
                    builder: (context, menu, child) => Square(
                      'list',
                      size: 40,
                      border: false,
                      tooltip: 'Действия с папкой',
                      onTap: () => menu.isOpen ? menu.close() : menu.open(),
                    ),
                  ),
                const SizedBox(width: 8),
                Container(
                  decoration: activeNavigationDecoration(context),
                  child: Square(
                    'check',
                    size: 48,
                    color: Theme.of(context).scaffoldBackgroundColor,
                    onTap: busy ? null : save,
                    border: false,
                    tooltip: 'Сохранить',
                  ),
                ),
              ],
            ),
          ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
              itemCount: draft.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Surface(
                        radius: 16,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            TextField(
                              controller: name,
                              style: const TextStyle(
                                fontSize: 17.6,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Название папки',
                              ),
                            ),
                            gap(12),
                            TextField(
                              controller: description,
                              decoration: const InputDecoration(
                                hintText: 'Описание (необязательно)',
                              ),
                            ),
                          ],
                        ),
                      ),
                      gap(12),
                      if (widget.folder == null)
                        Tap(
                          label: 'Идиомы',
                          onTap: toggleKind,
                          child: Surface(
                            radius: 12,
                            background: kind == 'idioms'
                                ? originalSecondary(context)
                                      .withValues(alpha: .1)
                                : null,
                            borderColor: kind == 'idioms'
                                ? originalSecondary(context)
                                : null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Glyph('chat', size: 16),
                                const SizedBox(width: 8),
                                label(
                                  'Идиомы',
                                  size: 13,
                                  weight: FontWeight.w700,
                                ),
                              ],
                            ),
                          ),
                        ),
                      gap(16),
                    ],
                  );
                }
                if (index == draft.length + 1) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Pill(
                      kind == 'words' ? 'Добавить слово' : 'Добавить идиому',
                      icon: 'plus',
                      onTap: () => setState(() => draft.add({})),
                    ),
                  );
                }
                final w = draft[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Surface(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            label('$index', color: muted(context)),
                            Square(
                              'trash',
                              border: false,
                              onTap: () => setState(() {
                                if (w['id'] != null) deleted.add('${w['id']}');
                                draft.removeAt(index - 1);
                              }),
                            ),
                          ],
                        ),
                        for (final f in entryFields[kind]!.where(
                          (f) => f[0] != 'folder',
                        ))
                          TextFormField(
                            key: ValueKey(
                              '${identityHashCode(w)}-$kind-${f[0]}',
                            ),
                            initialValue: '${w[f[0]] ?? ''}',
                            onChanged: (v) => w[f[0]] = v,
                            maxLines: null,
                            decoration: InputDecoration(
                              hintText: f[1],
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _FilterMenu extends StatefulWidget {
  const _FilterMenu({required this.text, required this.choices});
  final String text;
  final List<Widget> choices;
  @override
  State<_FilterMenu> createState() => _FilterMenuState();
}

class _FilterMenuState extends State<_FilterMenu> {
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor
        .withValues(alpha: .94);
    final options = NativeGlass(
      kind: GlassKind.overlay,
      blur: 24,
      radius: 12,
      gradient: LinearGradient(colors: [background, background]),
      child: SizedBox(
        width: math.min(260, MediaQuery.sizeOf(context).width - 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(400, MediaQuery.sizeOf(context).height * .65),
          ),
          child: SingleChildScrollView(
            primary: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.choices,
            ),
          ),
        ),
      ),
    );
    return PrimaryScrollController(
      controller: scroll,
      child: MenuAnchor(
        style: const MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(0),
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        menuChildren: [options],
        builder: (context, controller, child) => Tap(
          label: widget.text,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Surface(
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(child: label(widget.text, size: 13)),
                const Glyph('down', size: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
