part of 'app.dart';

class _UnifiedSearchResults extends StatefulWidget {
  const _UnifiedSearchResults({
    super.key,
    required this.query,
    required this.own,
    required this.allOwn,
    required this.ownBuilder,
    required this.kind,
    required this.store,
    required this.dictionary,
  });
  final String query, kind;
  final List<Json> own, allOwn;
  final Widget Function(Json) ownBuilder;
  final TwinkStore store;
  final DwdsDictionary dictionary;
  @override
  State<_UnifiedSearchResults> createState() => _UnifiedSearchResultsState();
}

class _UnifiedSearchResultsState extends State<_UnifiedSearchResults> {
  String scope = 'all';
  List<Json> hits = [];
  bool loading = false;
  String? error;
  int request = 0, limit = 12, ownLimit = 30;
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(_UnifiedSearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      limit = 12;
      ownLimit = 30;
      _search();
    }
  }

  Future<void> _search() async {
    final token = ++request;
    if (DwdsDictionary.ready) {
      setState(() {
        loading = false;
        error = null;
        hits = widget.dictionary.suggestCached(widget.query, limit: limit);
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
      hits = [];
    });
    try {
      final results = await widget.dictionary.suggest(
        widget.query,
        limit: limit,
      );
      if (mounted && token == request) {
        setState(() {
          hits = results;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && token == request) {
        setState(() {
          error = 'Не удалось загрузить подсказки DWDS';
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          for (final option in [
            ('all', 'Все'),
            ('own', 'Мои карточки'),
            ('dwds', 'DWDS'),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tap(
                  label: option.$2,
                  onTap: () => setState(() => scope = option.$1),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scope == option.$1
                          ? ink(context)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: ink(context).withValues(alpha: .18),
                      ),
                    ),
                    child: label(
                      option.$2,
                      size: 12,
                      lines: 1,
                      weight: FontWeight.w600,
                      color: scope == option.$1
                          ? Theme.of(context).scaffoldBackgroundColor
                          : ink(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      if (scope != 'dwds') ...[
        gap(20),
        label(
          'МОИ КАРТОЧКИ · ${widget.own.length}',
          size: 11,
          color: muted(context),
          weight: FontWeight.w700,
        ),
        gap(10),
        if (widget.own.isEmpty)
          label(
            'В ваших карточках совпадений нет',
            size: 13,
            color: muted(context),
          ),
        for (final word in widget.own.take(scope == 'all' ? 3 : ownLimit))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: widget.ownBuilder(word),
          ),
        if (widget.own.length > (scope == 'all' ? 3 : ownLimit))
          Pill(
            'Показать ещё карточки',
            onTap: () => setState(() {
              if (scope == 'all') {
                scope = 'own';
              } else {
                ownLimit += 30;
              }
            }),
          ),
      ],
      if (scope != 'own') ...[
        gap(20),
        Row(
          children: [
            const Glyph('book', size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: label(
                'СЛОВАРЬ DWDS',
                size: 11,
                color: muted(context),
                weight: FontWeight.w700,
              ),
            ),
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
          ],
        ),
        gap(10),
        if (error != null) Pill(error!, onTap: _search),
        if (!loading && error == null && hits.isEmpty)
          label(
            widget.query.trim().length < 2
                ? 'Введите хотя бы два символа для подсказок DWDS'
                : 'Нет совпадений в DWDS. Попробуйте начало немецкого слова.',
            size: 13,
            color: muted(context),
          ),
        for (final hit in hits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Surface(
              radius: 12,
              padding: EdgeInsets.zero,
              child: Tap(
                label: 'DWDS: ${hit['lemma']}',
                onTap: () {
                  FocusScope.of(context).unfocus();
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _DwdsWordPage(
                        hit: hit,
                        kind: widget.kind,
                        store: widget.store,
                        dictionary: widget.dictionary,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label(
                              '${hit['lemma']}',
                              size: 16,
                              weight: FontWeight.w700,
                            ),
                            gap(4),
                            label(
                              widget.allOwn.any(
                                    (w) =>
                                        DwdsDictionary.lemma(wordTitle(w)) ==
                                        hit['lemma'],
                                  )
                                  ? 'DWDS · Уже есть в карточках'
                                  : 'DWDS · Новое слово',
                              size: 11,
                              color:
                                  widget.allOwn.any(
                                    (w) =>
                                        DwdsDictionary.lemma(wordTitle(w)) ==
                                        hit['lemma'],
                                  )
                                  ? const Color(0xffa5c6b3)
                                  : muted(context),
                            ),
                          ],
                        ),
                      ),
                      const Glyph('right', size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (hits.length == limit)
          Pill(
            'Больше подсказок',
            onTap: () {
              limit += 20;
              _search();
            },
          ),
      ],
    ],
  );
}

class _DwdsWordPage extends StatefulWidget {
  const _DwdsWordPage({
    required this.hit,
    required this.kind,
    required this.store,
    required this.dictionary,
  });
  final Json hit;
  final String kind;
  final TwinkStore store;
  final DwdsDictionary dictionary;
  @override
  State<_DwdsWordPage> createState() => _DwdsWordPageState();
}

class _DwdsWordPageState extends State<_DwdsWordPage> {
  final translation = TextEditingController();
  Json? detail, known;
  String? error;
  bool loading = true, saving = false;
  int sense = 0;
  String folder = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    translation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final vocabulary =
        DwdsDictionary.cachedKnown ?? await DwdsDictionary.known();
    if (!mounted) return;
    known = vocabulary['${widget.hit['lemma']}'];
    if (translation.text.isEmpty) {
      translation.text = '${known?['translation'] ?? ''}';
    }
    try {
      final value = await widget.dictionary.detail(widget.hit);
      if (mounted) {
        setState(() {
          detail = value;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Не удалось открыть статью DWDS. Повторите запрос или откройте сайт.';
        });
      }
    }
  }

  Future<void> _save() async {
    if (saving) return;
    if (translation.text.trim().isEmpty) {
      notify(context, 'Добавьте перевод для своей карточки');
      return;
    }
    final title = '${known?['word'] ?? detail?['word'] ?? widget.hit['lemma']}';
    final own = widget.kind == 'words'
        ? widget.store.words
        : widget.store.idioms;
    if (own.any(
      (w) =>
          DwdsDictionary.lemma(wordTitle(w)) == DwdsDictionary.lemma(title) &&
          '${w['translation']}'.trim().toLowerCase() ==
              translation.text.trim().toLowerCase(),
    )) {
      notify(context, 'Такая карточка уже есть в словаре');
      return;
    }
    setState(() => saving = true);
    final senses = (detail?['senses'] as List?) ?? [];
    final perSense = (detail?['senseExamples'] as List?) ?? [];
    final examples = perSense.length > sense ? perSense[sense] as List : [];
    final definition = senses.isEmpty ? '' : '${senses[sense]}';
    final record = <String, dynamic>{
      widget.kind == 'words' ? 'word' : 'idiom': title,
      'translation': translation.text.trim(),
      'folder': folder,
      'dictionarySource': 'DWDS',
      'dictionaryUrl': widget.hit['url'],
      'dwdsDefinition': definition,
      if (widget.kind == 'words') ...{
        'info1': known?['info1'] ?? detail?['info1'] ?? '',
        'info2': definition,
        'ex1': examples.isNotEmpty ? examples[0] : '',
        'ex2': examples.length > 1 ? examples[1] : '',
      } else ...{
        'meaning': definition,
        'example': examples.isNotEmpty ? examples[0] : '',
        'info': detail?['grammar'] ?? '',
      },
    };
    try {
      await widget.store.save(widget.kind, record);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        notify(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final senses = (detail?['senses'] as List?) ?? [];
    final entries = widget.kind == 'words'
        ? widget.store.words
        : widget.store.idioms;
    final folders =
        entries
            .map((w) => '${w['folder'] ?? ''}')
            .where((f) => f.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Square(
                    'back',
                    tooltip: 'Назад',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: label(
                      'Словарь DWDS',
                      size: 18,
                      weight: FontWeight.w700,
                    ),
                  ),
                  Square(
                    'upload',
                    tooltip: 'Открыть DWDS',
                    onTap: () async {
                      try {
                        if (!await launchUrl(
                              Uri.parse('${widget.hit['url']}'),
                              mode: LaunchMode.externalApplication,
                            ) &&
                            context.mounted) {
                          notify(context, 'Не удалось открыть браузер');
                        }
                      } catch (_) {
                        if (context.mounted) {
                          notify(context, 'Не удалось открыть браузер');
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  label(
                    '${detail?['word'] ?? widget.hit['lemma']}',
                    size: 28,
                    weight: FontWeight.w700,
                  ),
                  gap(8),
                  label(
                    '${detail?['grammar'] ?? 'Статья немецкого словаря'}',
                    size: 13,
                    color: muted(context),
                  ),
                  gap(20),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (error != null) ...[
                    label(error!, size: 14, color: muted(context)),
                    gap(8),
                    Pill('Повторить загрузку', onTap: _load),
                  ],
                  if (senses.isNotEmpty) ...[
                    label(
                      'ЗНАЧЕНИЕ · НА НЕМЕЦКОМ',
                      size: 11,
                      color: muted(context),
                    ),
                    gap(8),
                    for (var i = 0; i < senses.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Tap(
                          label: 'Значение ${i + 1}',
                          onTap: () => setState(() => sense = i),
                          child: Surface(
                            radius: 12,
                            strong: sense == i,
                            borderColor: ink(context)
                                .withValues(alpha: sense == i ? .6 : .12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                label('${i + 1}', color: muted(context)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: label('${senses[i]}', size: 14),
                                ),
                                if (sense == i) const Glyph('check', size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    gap(12),
                  ],
                  label(
                    'ПЕРЕВОД ДЛЯ ВАШЕЙ КАРТОЧКИ',
                    size: 11,
                    color: muted(context),
                  ),
                  gap(8),
                  TextField(
                    key: const ValueKey('dwds-translation'),
                    controller: translation,
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'Введите перевод',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (known != null) ...[
                    gap(6),
                    label(
                      'Перевод подставлен из вашего каталога WordLab',
                      size: 11,
                      color: muted(context),
                    ),
                  ],
                  gap(16),
                  DropdownButtonFormField<String>(
                    icon: const Glyph('down', size: 16),
                    initialValue: folder,
                    decoration: const InputDecoration(labelText: 'Папка'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Автоматически'),
                      ),
                      for (final f in folders)
                        DropdownMenuItem(value: f, child: Text(f)),
                    ],
                    onChanged: (value) => folder = value ?? '',
                  ),
                  gap(16),
                  label(
                    'Источник: DWDS · dwds.de',
                    size: 11,
                    color: muted(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Pill(
                widget.kind == 'words'
                    ? 'Добавить в мои карточки'
                    : 'Добавить в мои идиомы',
                onTap: saving ? null : _save,
                primary: true,
                busy: saving,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
