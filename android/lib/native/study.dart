part of 'app.dart';

extension _StudyView on _NativeHomeState {
  Widget _studyDashboard() {
    final words = store.words,
        idioms = store.idioms,
        last = asMap(prefs.values['last_session']),
        examDue = store.words.where((w) => eligible(w, exam: true)).length;
    if (words.isEmpty && idioms.isEmpty) {
      return scrolling([
        gap(80),
        Center(
          child: Column(
            children: [
              Surface(
                radius: 99,
                padding: const EdgeInsets.all(16),
                child: const Glyph('book', size: 32),
              ),
              gap(24),
              label(
                'Здесь пока ничего нет',
                size: 20,
                weight: FontWeight.w700,
                align: TextAlign.center,
              ),
              gap(8),
              label(
                'Добавьте свое первое слово или идиому, чтобы начать обучение',
                size: 16,
                color: muted(context),
                align: TextAlign.center,
              ),
              gap(24),
              Pill(
                'Добавить слово',
                primary: true,
                onTap: () => _editEntry('words'),
              ),
              gap(12),
              Pill('Добавить идиому', onTap: () => _editEntry('idioms')),
            ],
          ),
        ),
      ]);
    }
    return scrolling([
      label('Режимы обучения', size: 16, weight: FontWeight.w700),
      gap(20),
      _modeCard(
        'Весь словарь',
        'globe',
        words.length,
        words.where((w) => eligible(w)).length,
        () => _startStudy('words'),
      ),
      if (idioms.isNotEmpty) ...[
        gap(12),
        _modeCard(
          'Все идиомы',
          'chat',
          idioms.length,
          idioms.where((w) => eligible(w)).length,
          () => _startStudy('idioms'),
        ),
      ],
      if (examDue > 0) ...[
        gap(12),
        _modeCard(
          'Экзамен',
          'check-circle',
          null,
          examDue,
          () => _startStudy('words', exam: true),
        ),
      ],
      ..._lastOpened(last),
      gap(28),
      Row(
        children: [
          Expanded(child: label('Папки', size: 16, weight: FontWeight.w700)),
          Square(
            'sort',
            key: folderSortAnchor,
            onTap: _folderSort,
            border: false,
            tooltip: 'Сортировка',
          ),
          Square(
            folderGrid ? 'list' : 'grid',
            onTap: () {
              update(() => folderGrid = !folderGrid);
              prefs.set('folderGrid', folderGrid);
            },
            border: false,
            tooltip: 'Вид папок',
          ),
          const SizedBox(width: 8),
          Tap(
            onTap: _createFolder,
            child: Surface(
              radius: 99,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Glyph('plus', size: 16),
                  const SizedBox(width: 5),
                  label('Создать папку', size: 12),
                ],
              ),
            ),
          ),
        ],
      ),
      gap(16),
      if (folders('words').isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: label(
            'Нет папок. Добавьте слово или загрузите Excel.',
            color: muted(context),
            align: TextAlign.center,
          ),
        ),
      _folderList('words'),
      if (folders('idioms').isNotEmpty) ...[
        gap(24),
        Row(
          children: [
            const Glyph('book', size: 20),
            const SizedBox(width: 8),
            label('Папки идиом', size: 18, weight: FontWeight.w700),
          ],
        ),
        gap(16),
        _folderList('idioms'),
      ],
    ]);
  }

  List<Widget> _lastOpened(Json last) {
    if (last.isEmpty || last['folder'] == null && last['kind'] != 'idioms') {
      return [];
    }
    final k = last['kind'] == 'idioms' ? 'idioms' : 'words',
        folder = last['folder'] as String?;
    final items = (k == 'words' ? store.words : store.idioms)
        .where((w) => folder == null || w['folder'] == folder)
        .toList();
    if (items.isEmpty) return [];
    final counts = [
      items.length,
      items.where((w) => eligible(w)).length,
      items
          .where((w) => asMap(w['progress_global'])['is_ideal'] == true)
          .length,
    ];
    return [
      gap(16),
      Tap(
        label: 'Продолжить',
        onTap: () => _startStudy(k, folder: folder),
        onLongPress: folder == null
            ? null
            : () => _folderEditor(k, folder: folder),
        child: Surface(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ink(context).withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Glyph('play', size: 22),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: label(
                  folder ?? 'Все идиомы',
                  size: 14.72,
                  weight: FontWeight.w700,
                  lines: 1,
                ),
              ),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Surface(
                    radius: 10,
                    background: ink(context).withValues(alpha: .04),
                    borderColor: ink(context).withValues(alpha: .08),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        label(
                          counts[i].toString(),
                          size: 12,
                          weight: FontWeight.w700,
                        ),
                        if (i == 2) ...[
                          const SizedBox(width: 3),
                          const Glyph('star', size: 10),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _modeCard(
    String title,
    String icon,
    int? total,
    int due,
    VoidCallback start,
  ) => Tap(
    onTap: start,
    label: title,
    child: Surface(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ink(context).withValues(alpha: .08),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Glyph(icon, size: 22),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: label(title, size: 14.72, weight: FontWeight.w700, lines: 1),
          ),
          if (total != null) ...[
            Surface(
              radius: 10,
              background: ink(context).withValues(alpha: .04),
              borderColor: ink(context).withValues(alpha: .08),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              child: label(
                '$total',
                size: 13.6,
                weight: FontWeight.w700,
                color: muted(context),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Surface(
            radius: 10,
            background: ink(context).withValues(alpha: .04),
            borderColor: ink(context).withValues(alpha: .08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: label('$due', size: 13.6, weight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
  Widget _folderList(String k) {
    final list = folders(k), source = k == 'words' ? store.words : store.idioms;
    final compact = folderGrid && MediaQuery.sizeOf(context).width <= 768;
    Widget tile(String folder) {
      final items = source.where((w) => w['folder'] == folder).toList(),
          due = items.where((w) => eligible(w)).length,
          ideal = items
              .where((w) => asMap(w['progress_global'])['is_ideal'] == true)
              .length,
          p = items.isEmpty ? 0.0 : ideal / items.length;
      return Tap(
        label: folder,
        onTap: () => _startStudy(k, folder: folder),
        child: Surface(
          padding: EdgeInsets.all(compact ? 14.4 : 28),
          background: due == 0
              ? originalSecondary(context).withValues(alpha: .08)
              : null,
          borderColor: due == 0
              ? originalSecondary(context).withValues(alpha: .25)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: label(
                      folder,
                      size: compact ? 12 : 14.72,
                      weight: FontWeight.w700,
                      lines: 1,
                    ),
                  ),
                  Square(
                    'list',
                    border: false,
                    size: compact ? 22 : 28,
                    onTap: () => _folderEditor(k, folder: folder),
                    tooltip: 'Редактировать папку',
                  ),
                ],
              ),
              if (!compact) ...[
                gap(4),
                label(
                  k == 'idioms'
                      ? 'Папка идиом'
                      : RegExp(r'^Папка \d+$').hasMatch(folder)
                      ? 'Создано автоматически'
                      : asMap(
                              asMap(store.data?['folderMeta'])[folder],
                            )['type'] ==
                            'manual'
                      ? 'Создано вручную'
                      : 'Создано через импорт',
                  size: 10,
                  color: muted(context),
                ),
              ],
              gap(compact ? 6.4 : 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final value in [
                    (items.length, 'ВСЕГО'),
                    (due, 'К ПОВТОРУ'),
                    (ideal, k == 'words' ? 'ИДЕАЛЬНО' : 'ПРОЙДЕНО'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Surface(
                          radius: 10,
                          padding: const EdgeInsets.symmetric(
                            vertical: 9,
                            horizontal: 2,
                          ),
                          background: ink(context).withValues(alpha: .04),
                          borderColor: ink(context).withValues(alpha: .08),
                          child: compact
                              ? Center(
                                  child: label(
                                    '${value.$1}',
                                    size: 9.6,
                                    weight: FontWeight.w800,
                                  ),
                                )
                              : _folderCount(value.$1, value.$2),
                        ),
                      ),
                    ),
                ],
              ),
              gap(compact ? 10 : 20),
              if (!compact) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    label('Прогресс', size: 10, color: muted(context)),
                    label(
                      '${(p * 100).round()}%',
                      size: 10,
                      color: muted(context),
                    ),
                  ],
                ),
                gap(7),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: p,
                  color: originalSecondary(context),
                  backgroundColor: ink(context).withValues(alpha: .05),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!folderGrid) {
      return Column(
        children: [
          for (final f in list)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: tile(f)),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, c) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in list)
            SizedBox(width: (c.maxWidth - 8) / 2, child: tile(f)),
        ],
      ),
    );
  }

  Widget _folderCount(int n, String text) => Column(
    children: [
      label('$n', weight: FontWeight.w700),
      gap(3),
      label(text, size: 8, color: muted(context)),
    ],
  );
  Future<void> _folderSort() async {
    final box =
        folderSortAnchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final point = box.localToGlobal(Offset.zero),
        size = MediaQuery.sizeOf(context);
    final value = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть сортировку',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (c, a, b) => Stack(
        children: [
          Positioned(
            right: 12,
            top: math.min(point.dy + box.size.height + 8, size.height - 180),
            width: 200,
            child: Material(
              type: MaterialType.transparency,
              child: NativeGlass(
                kind: GlassKind.overlay,
                blur: 24,
                radius: 16,
                gradient: LinearGradient(
                  colors: [
                    Theme.of(c).scaffoldBackgroundColor.withValues(alpha: .9),
                    Theme.of(c).scaffoldBackgroundColor.withValues(alpha: .8),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in [
                        ('newest', 'Сначала новые'),
                        ('oldest', 'Сначала старые'),
                        ('alphabet', 'По алфавиту'),
                      ])
                        Tap(
                          label: entry.$2,
                          onTap: () => Navigator.pop(c, entry.$1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Glyph(
                                  folderOrder == entry.$1 ? 'check' : 'clock',
                                  size: 16,
                                ),
                                const SizedBox(width: 10),
                                label(entry.$2, size: 13),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (value != null && mounted) {
      update(() => folderOrder = value);
      prefs.set('folderOrder', value);
    }
  }

  Future<void> _createFolder() => _folderEditor('words');

  Future<void> _folderEditor(String k, {String? folder}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _FolderEditor(store: store, kind: k, folder: folder),
      ),
    );
    if (mounted) update(() {});
  }

  Future<void> _startStudy(
    String k, {
    String? folder,
    bool exam = false,
  }) async {
    final all = k == 'words' ? store.words : store.idioms,
        scope = all
            .where((w) => folder == null || w['folder'] == folder)
            .toList();
    final due = scope.where((w) => eligible(w, exam: exam)).toList();
    if (due.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(
            exam ? 'Нет слов для экзамена!' : 'Нет слов для повторения!',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    prefs.set('last_session', {'kind': k, 'folder': folder}, notify: false);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => NativeStudyPage(
          store: store,
          prefs: prefs,
          kind: k,
          folder: folder,
          exam: exam,
        ),
      ),
    );
    if (mounted) {
      update(() => tab = number(prefs.values['tab']).toInt().clamp(0, 4));
    }
  }
}

class NativeStudyPage extends StatefulWidget {
  const NativeStudyPage({
    super.key,
    required this.store,
    required this.prefs,
    required this.kind,
    this.folder,
    this.exam = false,
  });
  final TwinkStore store;
  final NativePreferences prefs;
  final String kind;
  final String? folder;
  final bool exam;
  @override
  State<NativeStudyPage> createState() => _NativeStudyPageState();
}

class _NativeStudyPageState extends State<NativeStudyPage>
    with WidgetsBindingObserver {
  late List<Json> queue;
  int index = 0, pending = 0;
  bool back = false,
      busy = false,
      listening = false,
      resumed = true,
      leaving = false;
  bool missing = false, savingRating = false;
  bool _peeling = false;
  Map<String, List<String>> _pictureIndex = {};
  List<String> get _pictures {
    final key = _StickerPictures.normalize(wordTitle(word));
    final direct = _pictureIndex[key];
    if (direct != null) return direct;
    final head = key.split(',').first;
    return _pictureIndex[head] ?? const [];
  }

  late List<Json> _records;
  Json? result, incorrectState;
  final history = <Json>[];
  final sessionResults = <String, Json>{};
  bool _finished = false, _navigatingAway = false;
  int sessionSeconds = 0;
  final answer = TextEditingController(), recognition = SpeechToText();
  final elapsed = ValueNotifier<int>(0);
  Timer? clock, restart;
  DateTime activity = DateTime.now();
  Future<void>? flushing;
  VoidCallback? _releaseVisualUpdates;
  Completer<void>? _motionIdle;
  int _speechRequest = 0;
  void _beginCardMotion() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _releaseVisualUpdates ??= widget.store.holdVisualUpdates();
    _motionIdle ??= Completer<void>();
  }

  void _endCardMotion({bool deferRelease = false}) {
    final release = _releaseVisualUpdates, idle = _motionIdle;
    _releaseVisualUpdates = null;
    _motionIdle = null;
    void complete() {
      release?.call();
      idle?.complete();
    }

    if (deferRelease) {
      scheduleMicrotask(complete);
    } else {
      complete();
    }
  }

  Json get settings => {...originalSettings, ...widget.store.settings};
  bool get firstBack => !widget.exam && settings['firstSide'] == 'translation';
  Json get word => queue[index];
  List<Json> get all => _records;
  String get sessionKey => 'session-${widget.kind}-${widget.folder ?? 'all'}';
  @override
  void initState() {
    super.initState();
    back = firstBack;
    _StickerPictures.load().then((pictures) {
      if (mounted) setState(() => _pictureIndex = pictures);
    });
    _records = widget.kind == 'words'
        ? widget.store.words
        : widget.store.idioms;
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(syncCurrent);
    final scope = all
        .where((w) => widget.folder == null || w['folder'] == widget.folder)
        .toList();
    queue =
        scope
            .where((w) => eligible(w, exam: widget.exam))
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
          ..shuffle();
    if (!widget.exam) {
      final saved = asMap(widget.prefs.values[sessionKey]), ids = saved['ids'];
      final byId = {for (final w in all) w['id'].toString(): w};
      if (ids is List && number(saved['index']) < ids.length) {
        final restored = ids
            .map((id) => byId[id.toString()])
            .whereType<Json>()
            .where((w) => eligible(w))
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (restored.isNotEmpty) {
          queue = restored;
          index = 0;
        }
      }
    }
    final totals = dailyStats(widget.store.data);
    elapsed.value = (totals[logicalDay()] ?? 0).toInt();
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (resumed &&
          !leaving &&
          DateTime.now().difference(activity).inSeconds < 30) {
        pending++;
        sessionSeconds++;
        elapsed.value++;
      }
      if (pending >= 15) flush();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (queue.isEmpty) {
        finish();
      } else {
        saveSession();
        if (!widget.exam) {
          speakVisibleSide();
          unawaited(_ensureFrequency());
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(syncCurrent);
    _endCardMotion(deferRelease: true);
    clock?.cancel();
    restart?.cancel();
    audio.speech.stop();
    recognition.stop();
    flush();
    answer.dispose();
    elapsed.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    if (!resumed) {
      _endCardMotion();
      audio.speech.stop();
      recognition.stop();
      flush();
    }
  }

  void saveSession() {
    if (widget.exam) return;
    widget.prefs.set(sessionKey, {
      'ids': queue.skip(index).map((e) => e['id']).toList(),
      'index': 0,
    }, notify: false);
  }

  void syncCurrent() {
    if (!mounted || busy || leaving || index >= queue.length) return;
    _records = widget.kind == 'words'
        ? widget.store.words
        : widget.store.idioms;
    final fresh = all.where((w) => '${w['id']}' == '${word['id']}').firstOrNull;
    setState(() {
      missing = fresh == null;
      if (fresh != null) queue[index] = Map<String, dynamic>.from(fresh);
    });
    if (missing) {
      audio.speech.stop();
    } else if (!widget.exam) {
      unawaited(_ensureFrequency());
    }
  }

  Future<void> restoreWord() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.store.patch({'${widget.kind}/${word['id']}': word});
      if (mounted) {
        setState(() {
          missing = false;
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        notify(context, e);
      }
    }
  }

  Future<void> skipDeleted() async {
    if (busy) return;
    index++;
    missing = false;
    back = firstBack;
    result = null;
    answer.clear();
    saveSession();
    if (index >= queue.length) {
      await finish();
      return;
    }
    setState(() {});
    speakVisibleSide();
  }

  Future<void> flush() async {
    if (flushing != null) {
      try {
        await flushing;
      } catch (_) {}
      return;
    }
    if (pending == 0) return;
    final n = pending;
    final store = widget.store;
    // dispose may run with the widget tree locked. Persist outside that phase,
    // including the synchronous demo/cache notifications before the HTTP call.
    final work = Future<void>.microtask(() => store.addTime(n));
    flushing = work;
    try {
      await work;
      pending -= n;
    } catch (_) {
    } finally {
      flushing = null;
    }
  }

  void leaveForTab(int tab) {
    if (!mounted || _navigatingAway || (leaving && !_finished)) return;
    _navigatingAway = true;
    leaving = true;
    clock?.cancel();
    restart?.cancel();
    if (!_finished) saveSession();
    widget.prefs.set('tab', tab, notify: false);
    _endCardMotion();
    unawaited(() async {
      try {
        await audio.speech.stop();
      } catch (_) {}
      try {
        await recognition.stop();
      } catch (_) {}
    }());
    unawaited(flush());
    Navigator.of(context).pop();
  }

  Future<void> finish() async {
    if (leaving || !mounted) return;
    leaving = true;
    clock?.cancel();
    restart?.cancel();
    _endCardMotion();
    unawaited(() async {
      try {
        await audio.speech.stop();
      } catch (_) {}
      try {
        await recognition.stop();
      } catch (_) {}
    }());
    unawaited(flush());
    widget.prefs.set(sessionKey, null, notify: false);
    setState(() => _finished = true);
  }

  Future<void> exit() async {
    if (busy) return;
    if (!widget.exam && history.isNotEmpty) {
      final last = history.last;
      setState(() => busy = true);
      try {
        await widget.store.progress(
          widget.kind,
          '${last['id']}',
          last['progress'] as Json?,
        );
        history.removeLast();
        sessionResults.remove('${last['id']}');
        index = last['index'] as int;
        queue[index]['progress_global'] = last['progress'];
        back = firstBack;
        saveSession();
        if (mounted) setState(() => busy = false);
        speakVisibleSide();
        unawaited(_ensureFrequency());
      } catch (e) {
        if (mounted) {
          setState(() => busy = false);
          notify(context, e);
        }
      }
      return;
    }
    if (widget.exam &&
        !await nativeConfirm(
          context,
          'Вы уверены, что хотите выйти из экзамена?',
        )) {
      return;
    }
    await audio.speech.stop();
    await recognition.stop();
    await flush();
    if (mounted) Navigator.pop(context);
  }

  Future<void> speakFront() async {
    if (!mounted || queue.isEmpty || settings['audio'] != true || widget.exam) {
      return;
    }
    await audio.speech.speak(speechPlan(word, settings), _audioSettings('de'));
  }

  Future<void> speakVisibleSide() async {
    if (!back) return speakFront();
    if (!mounted ||
        queue.isEmpty ||
        widget.exam ||
        settings['audio'] != true ||
        settings['audioTranslation'] != true) {
      return;
    }
    await audio.speech.say(
      "${word['translation'] ?? ''}${widget.kind == 'idioms' && settings['audioInfo1'] == true ? '. ${word['meaning'] ?? ''}' : ''}",
      language: 'ru',
      settings: _audioSettings('ru'),
    );
  }

  Json _audioSettings(String lang) {
    final selection =
        '${settings[lang == 'de' ? 'selectAudioDe' : 'selectAudioRu'] ?? ''}';
    return {
      ...settings,
      'audioProvider':
          selection.isNotEmpty && !selection.startsWith('elevenlabs_')
          ? 'system'
          : 'elevenlabs',
    };
  }

  void flip() {
    if ((busy && !savingRating) || missing) return;
    activity = DateTime.now();
    _beginCardMotion();
    setState(() => back = !back);
    audio.speech.stop();
    _speakAfterMotion();
  }

  Future<void> _speakAfterMotion() async {
    final request = ++_speechRequest;
    await _motionIdle?.future;
    if (mounted &&
        resumed &&
        !leaving &&
        request == _speechRequest &&
        ModalRoute.of(context)?.isCurrent == true) {
      speakVisibleSide();
    }
  }

  Future<void> rate(int rating) async {
    if (busy || missing || widget.exam || _peeling) return;
    activity = DateTime.now();
    final ratedIndex = index, rated = word, previousBack = back;
    final id = rated['id'].toString();
    final previous = rated['progress_global'] == null
        ? null
        : Map<String, dynamic>.from(asMap(rated['progress_global']));
    final next = review(
      asMap(rated['progress_global']),
      rating,
      mode: settings['studyMode'].toString(),
    );
    final hasNext = index + 1 < queue.length;
    if (hasNext && back != firstBack) _beginCardMotion();
    unawaited(audio.speech.stop().catchError((_) {}));
    setState(() {
      busy = savingRating = true;
      queue[ratedIndex] = {...rated, 'progress_global': next};
      _records = [
        for (final w in all)
          if (w['id'].toString() == id) {...w, 'progress_global': next} else w,
      ];
      if (hasNext) {
        index++;
        back = firstBack;
      }
    });
    if (hasNext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && index == ratedIndex + 1 && !leaving) {
          _speakAfterMotion();
          unawaited(_ensureFrequency());
        }
      });
    }
    try {
      await widget.store.progress(widget.kind, id, next);
      await _motionIdle?.future;
      if (!mounted) return;
      history.add({
        'id': id,
        'index': ratedIndex,
        'progress': previous,
        'title': wordTitle(rated),
        'rating': rating,
      });
      if (history.length > 10) history.removeAt(0);
      sessionResults[id] = {...rated, 'rating': rating};
      _records = widget.kind == 'words'
          ? widget.store.words
          : widget.store.idioms;
      if (!hasNext) index++;
      saveSession();
      setState(() {
        busy = savingRating = false;
      });
      if (hasNext) syncCurrent();
      if (!hasNext) await finish();
    } catch (e) {
      await _motionIdle?.future;
      if (!mounted) return;
      setState(() {
        queue[ratedIndex] = rated;
        index = ratedIndex;
        back = previousBack;
        busy = savingRating = false;
        _records = widget.kind == 'words'
            ? widget.store.words
            : widget.store.idioms;
      });
      unawaited(audio.speech.stop().catchError((_) {}));
      unawaited(_ensureFrequency());
      notify(context, 'Не удалось сохранить оценку. Повторите попытку.');
    }
  }

  Future<void> edit() async {
    await audio.speech.stop();
    if (!mounted) return;
    _endCardMotion();
    final updated = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) => _EntryEditor(
          store: widget.store,
          kind: widget.kind,
          original: word,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        queue[index] = {...word, ...updated};
        back = firstBack;
      });
      speakVisibleSide();
    }
  }

  Future<void> openSettings() async {
    _endCardMotion();
    final previousFirstBack = firstBack;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть настройки',
      transitionDuration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 500,
      ),
      transitionBuilder: (context, animation, secondary, child) {
        final t = const Cubic(.16, 1, .3, 1).transform(animation.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - t)),
            child: Transform.scale(scale: .9 + .1 * t, child: child),
          ),
        );
      },
      barrierColor: Colors.black.withValues(alpha: .4),
      pageBuilder: (dialogContext, animation, secondary) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SizedBox(
          width: 600,
          height: MediaQuery.sizeOf(dialogContext).height - 24,
          child: Surface(
            radius: 0,
            padding: EdgeInsets.zero,
            glass: GlassKind.overlay,
            blur: 20,
            background: ink(dialogContext).withValues(alpha: .09),
            child: _SessionSettings(
              store: widget.store,
              prefs: widget.prefs,
              voiceOn: listening,
              onVoice: toggleVoice,
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      final changedSide = firstBack != previousFirstBack;
      setState(() {
        if (changedSide) back = firstBack;
      });
      if (changedSide) {
        await audio.speech.stop();
        speakVisibleSide();
      }
      if (settings['audio'] != true) audio.speech.stop();
    }
  }

  Future<void> toggleVoice() async {
    if (listening) {
      setState(() => listening = false);
      restart?.cancel();
      await recognition.stop();
      return;
    }
    final ready = await recognition.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') &&
            listening &&
            mounted &&
            resumed) {
          restart?.cancel();
          restart = Timer(const Duration(milliseconds: 350), listen);
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() => listening = false);
          notify(
            context,
            'Не удалось запустить голосовое управление. Проверьте доступ к микрофону.',
          );
        }
      },
    );
    if (!mounted) return;
    if (!ready) {
      notify(
        context,
        'Разрешите доступ к микрофону для голосового управления.',
      );
      return;
    }
    setState(() => listening = true);
    await listen();
  }

  Future<void> listen() async {
    if (!listening || !mounted || !resumed) return;
    await recognition.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'ru-RU',
        partialResults: false,
        cancelOnError: true,
      ),
      onResult: (r) {
        if (!r.finalResult || !mounted) return;
        final text = r.recognizedWords.toLowerCase();
        if (['переверни', 'верни', 'открой', 'покажи'].any(text.contains)) {
          flip();
          return;
        }
        for (final pair in <(int, List<String>)>[
          (1, ['не помню', 'не знаю', 'забыл', 'ноль']),
          (2, ['с трудом', 'трудно', 'тяжело', 'один']),
          (3, ['частично', 'немного', 'средне', 'два']),
          (4, ['почти', 'близко', 'три']),
          (5, ['помню', 'знаю', 'четыре']),
          (6, ['отлично', 'супер', 'идеально', 'пять']),
        ]) {
          if (pair.$2.any(text.contains)) {
            rate(pair.$1);
            return;
          }
        }
      },
    );
  }

  Future<void> check() async {
    if (busy || missing || result != null) return;
    activity = DateTime.now();
    final checked = checkAnswer(word, answer.text);
    setState(() => busy = true);
    final progress = examProgress(
      asMap(word['progress_global']),
      checked,
      mode: '${settings['studyMode']}',
    );
    try {
      await widget.store.progress(widget.kind, '${word['id']}', progress);
      if (!mounted) return;
      setState(() {
        word['progress_global'] = progress;
        result = checked;
        sessionResults['${word['id']}'] = {
          ...word,
          'correct': checked['correct'],
          'rating': progress['lastRating'],
        };
        incorrectState = null;
        busy = false;
      });
      if (settings['audio'] == true) {
        audio.speech.say(
          '${wordTitle(word)}, ${word['info1'] ?? ''}',
          settings: _audioSettings('de'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        notify(context, e);
      }
    }
  }

  Future<void> overrideAnswer() async {
    if (busy) return;
    setState(() => busy = true);
    final restore = incorrectState;
    final next =
        restore ??
        examProgress(asMap(word['progress_global']), {
          'correct': true,
        }, mode: '${settings['studyMode']}');
    try {
      await widget.store.progress(widget.kind, '${word['id']}', next);
      if (mounted) {
        setState(() {
          if (restore == null) {
            incorrectState = Map<String, dynamic>.from(
              asMap(word['progress_global']),
            );
            result = {...result!, 'correct': true, 'override': true};
          } else {
            incorrectState = null;
            result = checkAnswer(word, answer.text);
          }
          word['progress_global'] = next;
          sessionResults['${word['id']}'] = {
            ...word,
            'correct': result?['correct'] == true,
            'rating': next['lastRating'],
          };
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        notify(context, e);
      }
    }
  }

  Future<void> nextExam() async {
    await audio.speech.stop();
    index++;
    if (index >= queue.length) {
      await finish();
      return;
    }
    setState(() {
      result = null;
      incorrectState = null;
      answer.clear();
    });
    activity = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return _SessionSummary(
        exam: widget.exam,
        title:
            widget.folder ??
            (widget.kind == 'words' ? 'Все слова' : 'Все идиомы'),
        results: sessionResults.values.toList(),
        seconds: sessionSeconds,
        onStudy: () => leaveForTab(1),
        onDictionary: () => leaveForTab(2),
      );
    }
    if (queue.isEmpty || index >= queue.length) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) exit();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Listener(
            onPointerDown: (_) => activity = DateTime.now(),
            onPointerMove: (_) => activity = DateTime.now(),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: widget.exam ? _exam() : _cards(),
                  ),
                ),
                if (missing)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor
                          .withValues(alpha: .97),
                      child: Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  label(
                                    'Вы удалили это слово из словаря.',
                                    size: 17.6,
                                    align: TextAlign.center,
                                  ),
                                  gap(32),
                                  Pill(
                                    'Восстановить слово',
                                    onTap: restoreWord,
                                    primary: true,
                                    busy: busy,
                                  ),
                                  gap(16),
                                  Pill(
                                    'Перейти к следующему',
                                    onTap: skipDeleted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cards() {
    final fg = ink(context),
        scope = all
            .where(
              (w) =>
                  (widget.folder == null || w['folder'] == widget.folder) &&
                  (widget.folder != null ||
                      widget.kind == 'idioms' ||
                      settings['includeActive'] == true ||
                      asMap(w['progress_global'])['isActive'] != true),
            )
            .toList(),
        due = scope.where((w) => eligible(w)).length,
        ideal = scope
            .where((w) => asMap(w['progress_global'])['is_ideal'] == true)
            .length,
        today = logicalDay();
    final learned = scope.where((w) {
      final last = number(asMap(w['progress_global'])['lastReviewed']).toInt();
      return last > 0 && logicalDay(last) == today;
    }).length;
    return LayoutBuilder(
      builder: (context, viewport) {
        final compact = viewport.maxHeight < 760 || viewport.maxWidth <= 360;
        final roomy = !compact && viewport.maxHeight >= 844;
        final showAccessory = viewport.maxHeight >= 610;
        final underCard =
            widget.prefs.studyWidgetPosition == 'belowCard' && showAccessory;
        final docked =
            widget.prefs.studyWidgetPosition == 'aboveNavigation' &&
            showAccessory;
        final topPadding = compact
            ? 8.0
            : roomy
            ? 12.0
            : 8.0;
        final bottomPadding = docked
            ? (widget.prefs.studyWidgetStyle == 'tiles' ? 180.0 : 168.0)
            : showAccessory
            ? 80.0
            : 72.0;
        final columns = compact ? 3 : 2;
        final rows = (6 / columns).ceil();
        final spacing = compact ? 8.0 : 12.0;
        return Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, topPadding, 12, bottomPadding),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: viewport.maxWidth - 24,
                    child: _SessionColumn(
                      viewportHeight:
                          viewport.maxHeight - topPadding - bottomPadding,
                      minimumRatingsHeight:
                          (compact
                                  ? 42.0
                                  : roomy
                                  ? 60.0
                                  : 48.0) *
                              rows +
                          spacing * (rows - 1),
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Square(
                                  'back',
                                  onTap: exit,
                                  tooltip: 'Выйти',
                                  size: compact ? 32 : 40,
                                ),
                                const SizedBox(width: 8),
                                Square(
                                  settings['audio'] == true
                                      ? 'volume'
                                      : 'muted',
                                  active: settings['audio'] == true,
                                  size: compact ? 32 : 40,
                                  onTap: () async {
                                    await widget.store.patch({
                                      'settings/study': {
                                        ...settings,
                                        'audio': settings['audio'] != true,
                                      },
                                    });
                                    if (mounted) setState(() {});
                                    if (settings['audio'] != true) {
                                      audio.speech.stop();
                                    }
                                  },
                                  tooltip: 'Озвучка',
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: label(
                                      widget.folder ??
                                          (widget.kind == 'words'
                                              ? 'Все слова'
                                              : 'Все идиомы'),
                                      size: 16,
                                      weight: FontWeight.w700,
                                      align: TextAlign.center,
                                      lines: 1,
                                    ),
                                  ),
                                ),
                                const Glyph('star', size: 15),
                                const SizedBox(width: 5),
                                label(
                                  '$ideal',
                                  size: 12,
                                  weight: FontWeight.w700,
                                ),
                                const SizedBox(width: 10),
                                ValueListenableBuilder<int>(
                                  valueListenable: elapsed,
                                  builder: (context, n, _) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: fg.withValues(alpha: .1),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: label(
                                      formatSeconds(n),
                                      size: 11,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Square(
                                  'settings',
                                  onTap: openSettings,
                                  tooltip: 'Настройки',
                                  size: compact ? 32 : 40,
                                ),
                              ],
                            ),
                            gap(
                              compact
                                  ? 4
                                  : roomy
                                  ? 16
                                  : 12,
                            ),
                            Row(
                              spacing: 12,
                              children: [
                                for (final v in <(String, String, bool)>[
                                  (
                                    '${scope.length}',
                                    'Всего слов',
                                    settings['showStatTotal'] == true,
                                  ),
                                  (
                                    '$due',
                                    'К повторению',
                                    settings['showStatDue'] == true,
                                  ),
                                  (
                                    '$learned',
                                    'Пройдено сегодня',
                                    settings['showStatToday'] == true,
                                  ),
                                ])
                                  if (v.$3)
                                    Expanded(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: compact
                                              ? 44
                                              : roomy
                                              ? 76
                                              : 64,
                                        ),
                                        child: Surface(
                                          radius: 12,
                                          padding: EdgeInsets.symmetric(
                                            horizontal: compact ? 4 : 8,
                                            vertical: compact ? 4 : 9,
                                          ),
                                          strong: true,
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              label(
                                                v.$1,
                                                size: 18,
                                                weight: FontWeight.w700,
                                              ),
                                              gap(compact ? 2 : 4),
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxWidth: 90,
                                                    ),
                                                child: label(
                                                  compact
                                                      ? (v.$2 == 'Всего слов'
                                                            ? 'Всего'
                                                            : v.$2 ==
                                                                  'К повторению'
                                                            ? 'Повторить'
                                                            : 'Сегодня')
                                                      : v.$2,
                                                  size: 11.2,
                                                  color: muted(context),
                                                  align: TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                            gap(
                              compact
                                  ? 4
                                  : roomy
                                  ? 16
                                  : 12,
                            ),
                            StickerDeck(
                              contentId: '${word['id']}',
                              images: _pictures,
                              height: _cardHeight,
                              onMotionStart: () {
                                _peeling = true;
                                _beginCardMotion();
                              },
                              onMotionEnd: () {
                                _peeling = false;
                                _endCardMotion();
                              },
                              child: _NativeFlashcard(
                                key: const ValueKey('study-flashcard'),
                                contentId: '${word['id']}',
                                height: _cardHeight,
                                onSettled: _endCardMotion,
                                back: back,
                                onFlip: flip,
                                front: KeyedSubtree(
                                  key: ValueKey('front-${word['id']}'),
                                  child: _front(),
                                ),
                                reverse: KeyedSubtree(
                                  key: ValueKey('back-${word['id']}'),
                                  child: _back(),
                                ),
                              ),
                            ),
                            gap(
                              compact
                                  ? 8
                                  : !docked && showAccessory
                                  ? 12
                                  : roomy
                                  ? 20
                                  : 16,
                            ),
                            if (underCard) ...[_sessionAccessory(), gap(12)],
                          ],
                        ),
                        LayoutBuilder(
                          builder: (context, c) => Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: [
                              for (var r = 1; r <= 6; r++)
                                SizedBox(
                                  width:
                                      (c.maxWidth - spacing * (columns - 1)) /
                                      columns,
                                  child: Tap(
                                    label: ratingNames[r],
                                    onTap: busy ? null : () => rate(r),
                                    child: Container(
                                      height:
                                          (c.maxHeight - spacing * (rows - 1)) /
                                          rows,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: fg.withValues(alpha: .85),
                                        ),
                                        color: prefsSchemeColor(r),
                                      ),
                                      child: Stack(
                                        children: [
                                          Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                label(
                                                  ratingNames[r],
                                                  size: compact ? 14 : 15.2,
                                                  weight: FontWeight.w600,
                                                ),
                                                gap(2),
                                                label(
                                                  _intervalLabel(r),
                                                  size: 12,
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (r >= 5)
                                            Positioned(
                                              right: 8,
                                              top: 7,
                                              child: Glyph(
                                                'star',
                                                size: 11,
                                                color: muted(context),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (busy && !savingRating)
                              const Padding(
                                padding: EdgeInsets.only(top: 10),
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                            if (showAccessory &&
                                widget.prefs.studyWidgetPosition ==
                                    'belowRatings') ...[
                              gap(16),
                              _sessionAccessory(),
                            ],
                            if (!showAccessory &&
                                settings['showProgress'] == true) ...[
                              gap(8),
                              _sessionAccessory(minimal: true),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (docked)
              Positioned(
                left: 12,
                right: 12,
                bottom: 80,
                child: _sessionAccessory(),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SessionNavigation(
                store: widget.store,
                prefs: widget.prefs,
                onSelect: leaveForTab,
                listening: listening,
              ),
            ),
          ],
        );
      },
    );
  }

  Json? _frequency;
  String? _frequencyWord;
  Future<void> _ensureFrequency() async {
    final query = DwdsFrequencyRepository.query(wordTitle(word));
    if (_frequencyWord == query) return;
    _frequencyWord = query;
    _frequency = null;
    final record = await DwdsFrequencyRepository.load(
      query,
      cache: asMap(widget.prefs.values['dwdsFrequency']),
      allowNetwork: !widget.store.demo,
    );
    if (!mounted || _frequencyWord != query) return;
    await _motionIdle?.future;
    if (!mounted || _frequencyWord != query) return;
    if (record != null) {
      widget.prefs.set('dwdsFrequency', {
        ...asMap(widget.prefs.values['dwdsFrequency']),
        query: record,
      }, notify: false);
    }
    setState(() => _frequency = record);
  }

  Widget _sessionAccessory({bool minimal = false}) => _StudyAccessoryBar(
    mode: widget.prefs.studyWidgetStyle,
    frequency: _frequencyWord == DwdsFrequencyRepository.query(wordTitle(word))
        ? _frequency
        : null,
    progress: asMap(word['progress_global']),
    total: queue.length,
    remaining: queue.length - index,
    minimal: minimal,
    showProgress: settings['showProgress'] == true,
    onMode: (mode) {
      widget.prefs.set('studyMetricsLayout', mode, notify: false);
      widget.prefs.set(
        'studyWidgetStyle',
        mode == 'tiles' ? 'tiles' : 'ribbon',
        notify: false,
      );
      widget.prefs.set(
        'studyWidgetPosition',
        mode == 'underCard' ? 'belowCard' : 'aboveNavigation',
        notify: false,
      );
      setState(() {});
    },
  );

  Color prefsSchemeColor(int r) {
    if (widget.prefs.scheme == 'pure-black') {
      return ink(context).withValues(alpha: .08);
    }
    final colors = schemes[widget.prefs.scheme] ?? schemes['default']!;
    return Color.lerp(colors[0], colors[1], (r - 1) / 5)!.withValues(alpha: .1);
  }

  String _intervalLabel(int r) => intervalCaption(
    (intervals['${settings['studyMode']}'] ?? intervals['long']!)[r],
  );

  Color? get gender {
    final title = wordTitle(word).toLowerCase();
    return title.startsWith('der ')
        ? const Color(0xff4a9eff)
        : title.startsWith('die ')
        ? const Color(0xffff69b4)
        : title.startsWith('das ')
        ? const Color(0xffffbf00)
        : null;
  }

  double get _cardHeight => 280;

  Color? get _cardPaper {
    if (_pictures.isEmpty) return null;
    final paper = _stickerPaperColor(context);
    return settings['genderCardBackground'] == true && gender != null
        ? Color.alphaBlend(gender!.withValues(alpha: .15), paper)
        : paper;
  }

  Widget _front() {
    final title = wordTitle(word),
        idiom = widget.kind == 'idioms',
        info1 = '${word['info1'] ?? ''}',
        info2 = '${word[idiom ? 'info' : 'info2'] ?? ''}',
        examples = [
          if (settings['showEx1'] == true)
            '${word[idiom ? 'example' : 'ex1'] ?? ''}',
          if (!idiom && settings['showEx2'] == true) '${word['ex2'] ?? ''}',
        ].where((e) => e.isNotEmpty).toList();
    final textStyle = TextStyle(
      fontFamily: nativeFont(context),
      fontFamilyFallback: const ['Roboto'],
      fontSize: title.length > 30
          ? 24
          : title.length > 22
          ? 25.6
          : 28.8,
      fontWeight: FontWeight.w700,
      height: 1.15,
      color: ink(context),
    );
    final comma = title.indexOf(',');
    return Stack(
      children: [
        Surface(
          radius: 24,
          glass: GlassKind.card,
          strong: true,
          background: _cardPaper,
          tint: settings['genderCardBackground'] == true ? gender : null,
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(height: _cardHeight - 64),
            child: _ReadableCardContent(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (settings['showWord'] == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text.rich(
                        TextSpan(
                          style: textStyle,
                          children:
                              settings['genderColors'] == true && gender != null
                              ? [
                                  TextSpan(
                                    text: comma < 0
                                        ? title
                                        : title.substring(0, comma),
                                    style: TextStyle(color: gender),
                                  ),
                                  if (comma >= 0)
                                    TextSpan(text: title.substring(comma)),
                                ]
                              : [TextSpan(text: title)],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (!idiom &&
                      settings['showInfo1'] == true &&
                      info1.isNotEmpty) ...[
                    gap(8),
                    Text(
                      info1,
                      style: TextStyle(
                        color: muted(context),
                        fontSize: 14.4,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (settings['showInfo2'] == true && info2.isNotEmpty) ...[
                    gap(8),
                    Text(
                      info2,
                      style: TextStyle(
                        color: muted(context),
                        fontSize: 14.4,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (examples.isNotEmpty) ...[
                    gap(20),
                    for (var i = 0; i < examples.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == examples.length - 1 ? 0 : 8,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ink(context).withValues(alpha: .025),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(color: ink(context), width: 3),
                            ),
                          ),
                          child: _HighlightedExample(
                            examples[i],
                            title: wordTitle(word),
                            forms: info1,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: Square(
            'edit',
            onTap: edit,
            border: false,
            tooltip: 'Редактировать',
          ),
        ),
      ],
    );
  }

  Widget _back() => Surface(
    radius: 24,
    glass: GlassKind.card,
    strong: true,
    background: _cardPaper,
    tint: settings['genderCardBackground'] == true ? gender : null,
    padding: const EdgeInsets.all(32),
    child: ConstrainedBox(
      constraints: BoxConstraints.tightFor(height: _cardHeight - 64),
      child: _ReadableCardContent(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            label(
              '${word['translation'] ?? ''}',
              size: '${word['translation'] ?? ''}'.length > 40 ? 21 : 25.6,
              weight: FontWeight.w700,
              align: TextAlign.center,
            ),
            if (widget.kind == 'idioms' &&
                '${word['meaning'] ?? ''}'.isNotEmpty) ...[
              gap(16),
              label(
                '${word['meaning']}',
                size: 17,
                color: muted(context),
                align: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    ),
  );
  Widget _exam() {
    final correct = result?['correct'] == true,
        minor =
            result?['articleError'] == true || result?['sequenceError'] == true,
        color = result == null
            ? ink(context)
            : correct
            ? (result?['partial'] == true
                  ? const Color(0xff3b82f6)
                  : const Color(0xff10b981))
            : minor
            ? const Color(0xff8b5cf6)
            : const Color(0xffef4444);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
      children: [
        Row(
          children: [
            Square('back', onTap: exit, border: false, tooltip: 'Выйти'),
            Expanded(
              child: Column(
                children: [
                  label('ЭКЗАМЕН', weight: FontWeight.w700),
                  gap(2),
                  label(
                    'Слово ${index + 1} из ${queue.length}',
                    size: 11,
                    color: muted(context),
                  ),
                ],
              ),
            ),
            Square(
              'help',
              border: false,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const _ExamHelpPage()),
              ),
              tooltip: 'Инструкции',
            ),
          ],
        ),
        gap(28),
        label(
          '${word['translation'] ?? ''}',
          size: 28,
          weight: FontWeight.w700,
        ),
        gap(10),
        label(examHint(word), size: 14, color: muted(context)),
        gap(24),
        TextField(
          controller: answer,
          enabled: result == null && !busy,
          maxLines: null,
          autofocus: true,
          onChanged: (_) => activity = DateTime.now(),
          onSubmitted: (_) => result == null ? check() : nextExam(),
          decoration: const InputDecoration(hintText: 'Введите перевод...'),
          style: const TextStyle(fontSize: 20),
        ),
        gap(24),
        if (result == null)
          Pill('Проверить', onTap: check, primary: true, busy: busy),
        if (result != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label(
                  correct
                      ? (result?['override'] == true
                            ? '✓ Исправлено: Засчитано как верно!'
                            : result?['partial'] == true
                            ? 'Верно! Принят вариант ответа.'
                            : '✓ Правильно!')
                      : minor
                      ? 'Ошибка в артикле или последовательности'
                      : '✗ Неправильно',
                  color: color,
                  weight: FontWeight.w700,
                ),
                gap(10),
                label('Правильный ответ:', color: muted(context)),
                gap(4),
                label(
                  '${wordTitle(word)}${'${word['info1'] ?? ''}'.isEmpty ? '' : ', ${word['info1']}'}',
                  weight: FontWeight.w700,
                ),
                if ('${word['info2'] ?? ''}'.isNotEmpty) ...[
                  gap(),
                  label('${word['info2']}', color: muted(context)),
                ],
              ],
            ),
          ),
          gap(16),
          if (!correct && answer.text.trim().isNotEmpty)
            Pill('Засчитать как верно', onTap: overrideAnswer),
          if (incorrectState != null)
            Pill('Отменить исправление', onTap: overrideAnswer),
          gap(),
          Pill('Следующее слово', onTap: busy ? null : nextExam, primary: true),
        ],
      ],
    );
  }
}

/// Shrink modestly, then scroll rather than making examples illegible.
class _ReadableCardContent extends StatefulWidget {
  const _ReadableCardContent({required this.child});
  final Widget child;
  @override
  State<_ReadableCardContent> createState() => _ReadableCardContentState();
}

class _ReadableCardContentState extends State<_ReadableCardContent> {
  final controller = ScrollController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Scrollbar(
      controller: controller,
      thumbVisibility: true,
      thickness: 3,
      child: SingleChildScrollView(
        controller: controller,
        primary: false,
        child: _CardContentFit(
          viewportHeight: constraints.maxHeight,
          child: widget.child,
        ),
      ),
    ),
  );
}

class _CardContentFit extends SingleChildRenderObjectWidget {
  const _CardContentFit({required this.viewportHeight, required super.child});
  final double viewportHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCardContentFit(viewportHeight);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCardContentFit renderObject,
  ) {
    renderObject.viewportHeight = viewportHeight;
  }
}

class _RenderCardContentFit extends RenderProxyBox {
  _RenderCardContentFit(this._viewportHeight);
  double _viewportHeight, _scale = 1, _dy = 0;
  set viewportHeight(double value) {
    if (_viewportHeight == value) return;
    _viewportHeight = value;
    markNeedsLayout();
  }

  Matrix4 get _transform =>
      Matrix4.diagonal3Values(_scale, _scale, 1)..setTranslationRaw(0, _dy, 0);
  @override
  void performLayout() {
    final width = constraints.maxWidth;
    void measure(double scale) => child!.layout(
      BoxConstraints.tightFor(width: width / scale),
      parentUsesSize: true,
    );
    measure(1);
    _scale = 1;
    if (child!.size.height > _viewportHeight) {
      // A 14.4 px example stays at least 13 px before the user's text scaling.
      const minimum = 13 / 14.4;
      var low = minimum, high = 1.0;
      measure(low);
      if (child!.size.height * low <= _viewportHeight) {
        for (var i = 0; i < 7; i++) {
          final mid = (low + high) / 2;
          measure(mid);
          if (child!.size.height * mid <= _viewportHeight) {
            low = mid;
          } else {
            high = mid;
          }
        }
      }
      _scale = low;
      measure(_scale);
    }
    size = constraints.constrain(
      Size(width, math.max(_viewportHeight, child!.size.height * _scale)),
    );
    _dy = math.max(0, (size.height - child!.size.height * _scale) / 2);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(child!, offset),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _transform,
        position: position,
        hitTest: (result, position) =>
            child!.hitTest(result, position: position),
      );
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_transform);
}

class _NativeFlashcard extends StatefulWidget {
  const _NativeFlashcard({
    super.key,
    required this.contentId,
    required this.height,
    required this.onSettled,
    required this.back,
    required this.onFlip,
    required this.front,
    required this.reverse,
  });
  final bool back;
  final String contentId;
  final double height;
  final VoidCallback onSettled;
  final VoidCallback onFlip;
  final Widget front, reverse;
  @override
  State<_NativeFlashcard> createState() => _NativeFlashcardState();
}

class _NativeFlashcardState extends State<_NativeFlashcard>
    with SingleTickerProviderStateMixin {
  Widget? outgoingReverse, outgoingFront;
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: widget.back ? 1 : 0,
  );
  @override
  void initState() {
    super.initState();
    animation.addStatusListener((status) {
      if (status != AnimationStatus.completed &&
          status != AnimationStatus.dismissed) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !animation.isAnimating) widget.onSettled();
      });
    });
  }

  @override
  void didUpdateWidget(_NativeFlashcard old) {
    super.didUpdateWidget(old);
    if (widget.contentId != old.contentId) {
      // Keep the rated translation visible until the rotating card reveals
      // the next word, rather than flashing the next translation first.
      outgoingReverse = animation.value >= .5 ? old.reverse : null;
      outgoingFront = animation.value < .5 ? old.front : null;
    } else if (widget.back != old.back) {
      outgoingReverse = null;
      outgoingFront = null;
    }
    if (widget.back != old.back) {
      if (MediaQuery.disableAnimationsOf(context)) {
        animation.value = widget.back ? 1 : 0;
        return;
      }
      animation.animateTo(
        widget.back ? 1 : 0,
        curve: const Cubic(.4, .2, .2, 1),
      );
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build/layout each face once; only the rotation changes on animation ticks.
    final faces = [
      RepaintBoundary(
        child: widget.back && outgoingFront != null
            ? outgoingFront!
            : widget.front,
      ),
      Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(math.pi),
        child: RepaintBoundary(
          child: !widget.back && outgoingReverse != null
              ? outgoingReverse!
              : widget.reverse,
        ),
      ),
    ];
    return Tap(
      label: 'Перевернуть карточку',
      onTap: widget.onFlip,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, -1 / 1500)
            ..rotateY(animation.value * math.pi),
          child: SizedBox(
            height: widget.height,
            child: IndexedStack(
              index: animation.value >= .5 ? 1 : 0,
              sizing: StackFit.expand,
              children: faces,
            ),
          ),
        ),
      ),
    );
  }
}

class _HighlightedExample extends StatelessWidget {
  const _HighlightedExample(
    this.text, {
    required this.title,
    required this.forms,
  });
  final String text, title, forms;
  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[const TextSpan(text: '• ')];
    var position = 0;
    for (final range in originalExampleHighlights(text, title, forms)) {
      if (range.$1 > position) {
        spans.add(TextSpan(text: text.substring(position, range.$1)));
      }
      spans.add(
        TextSpan(
          text: text.substring(range.$1, range.$2),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            color: ink(context),
          ),
        ),
      );
      position = range.$2;
    }
    if (position < text.length) {
      spans.add(TextSpan(text: text.substring(position)));
    }
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: nativeFont(context),
          fontFamilyFallback: const ['Roboto'],
          fontSize: 14.4,
          height: 1.4,
          color: muted(context),
        ),
        children: spans,
      ),
    );
  }
}

/// Measure header/card and footer first; give the rating grid the remaining
/// viewport height. FittedBox remains the fallback only below the natural minimum.
class _SessionColumn extends MultiChildRenderObjectWidget {
  const _SessionColumn({
    required this.viewportHeight,
    required this.minimumRatingsHeight,
    required super.children,
  });
  final double viewportHeight, minimumRatingsHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSessionColumn(viewportHeight, minimumRatingsHeight);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSessionColumn renderObject,
  ) => renderObject.update(viewportHeight, minimumRatingsHeight);
}

class _SessionParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSessionColumn extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderSessionColumn(this.viewportHeight, this.minimumRatingsHeight);
  double viewportHeight, minimumRatingsHeight;
  void update(double height, double minimum) {
    if (height == viewportHeight && minimum == minimumRatingsHeight) return;
    viewportHeight = height;
    minimumRatingsHeight = minimum;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _SessionParentData();
    }
  }

  @override
  void performLayout() {
    final before = firstChild!,
        ratings = childAfter(before)!,
        after = lastChild!;
    final width = constraints.maxWidth;
    final natural = BoxConstraints.tightFor(width: width);
    before.layout(natural, parentUsesSize: true);
    after.layout(natural, parentUsesSize: true);
    ratings.layout(
      BoxConstraints.tightFor(
        width: width,
        height: math.max(
          minimumRatingsHeight,
          viewportHeight - before.size.height - after.size.height,
        ),
      ),
      parentUsesSize: true,
    );
    var y = 0.0;
    for (final child in [before, ratings, after]) {
      (child.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
        0,
        y,
      );
      y += child.size.height;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class SessionNavigation extends StatelessWidget {
  const SessionNavigation({
    super.key,
    required this.store,
    required this.prefs,
    required this.onSelect,
    required this.listening,
  });
  final TwinkStore store;
  final NativePreferences prefs;
  final ValueChanged<int> onSelect;
  final bool listening;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
    child: GlassNavigation(
      selected: 1,
      onSelect: (i) {
        if (i == 1) return;
        onSelect(i);
      },
    ),
  );
}
