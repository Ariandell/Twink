part of 'app.dart';

extension _StudyView on _NativeHomeState {
  Widget _studyDashboard() {
    final words = store.words,
        idioms = store.idioms,
        last = asMap(prefs.values['last_session']);
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
      gap(12),
      _modeCard(
        'Все идиомы',
        'chat',
        idioms.length,
        idioms.where((w) => eligible(w)).length,
        () => _startStudy('idioms'),
      ),
      gap(12),
      _modeCard(
        'Экзамен',
        'check-circle',
        null,
        words.where((w) => eligible(w, exam: true)).length,
        () => _startStudy('words', exam: true),
      ),
      if (last.isNotEmpty && last['folder'] != null) ...[
        gap(16),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: label(
                      '${last['folder']}',
                      size: 18,
                      weight: FontWeight.w700,
                    ),
                  ),
                  Square(
                    'edit',
                    border: false,
                    onTap: () => _folderEditor(
                      '${last['kind']}',
                      folder: '${last['folder']}',
                    ),
                  ),
                ],
              ),
              gap(),
              label(
                'Последняя открытая папка',
                size: 12,
                color: muted(context),
              ),
              gap(),
              Pill(
                'Продолжить',
                primary: true,
                icon: 'play',
                onTap: () =>
                    _startStudy('${last['kind']}', folder: '${last['folder']}'),
              ),
            ],
          ),
        ),
      ],
      gap(28),
      Row(
        children: [
          Expanded(child: label('Папки', size: 16, weight: FontWeight.w700)),
          Square(
            'sort',
            onTap: () => update(() => foldersNewest = !foldersNewest),
            border: false,
            tooltip: 'Сортировка',
          ),
          Square(
            folderGrid ? 'list' : 'grid',
            onTap: () => update(() => folderGrid = !folderGrid),
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
          padding: const EdgeInsets.all(28),
          background: due == 0 ? ink(context).withValues(alpha: .08) : null,
          borderColor: due == 0 ? ink(context).withValues(alpha: .25) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: label(
                      folder,
                      size: 14.72,
                      weight: FontWeight.w700,
                      lines: 1,
                    ),
                  ),
                  Square(
                    'list',
                    border: false,
                    size: 28,
                    onTap: () => _folderEditor(k, folder: folder),
                    tooltip: 'Редактировать папку',
                  ),
                ],
              ),
              gap(4),
              label(
                k == 'idioms'
                    ? 'Папка идиом'
                    : RegExp(r'^Папка \d+$').hasMatch(folder)
                    ? 'Создано автоматически'
                    : asMap(asMap(store.data?['folderMeta'])[folder])['type'] ==
                          'manual'
                    ? 'Создано вручную'
                    : 'Создано через импорт',
                size: 10,
                color: muted(context),
              ),
              gap(36),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final value in [
                    (items.length, 'ВСЕГО'),
                    (due, 'К ПОВТОРУ'),
                    (ideal, 'ИДЕАЛЬНО'),
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
                          child: _folderCount(value.$1, value.$2),
                        ),
                      ),
                    ),
                ],
              ),
              gap(20),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: p,
                  color: ink(context),
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
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final f in list)
            SizedBox(width: (c.maxWidth - 10) / 2, child: tile(f)),
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
  Future<void> _createFolder() async {
    final k = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Pill(
                'Папка слов',
                icon: 'book',
                onTap: () => Navigator.pop(c, 'words'),
              ),
              gap(),
              Pill(
                'Папка идиом',
                icon: 'book',
                onTap: () => Navigator.pop(c, 'idioms'),
              ),
            ],
          ),
        ),
      ),
    );
    if (k != null && mounted) await _folderEditor(k);
  }

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
    prefs.set('last_session', {'kind': k, 'folder': folder});
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
  bool missing = false;
  Json? result, incorrectState;
  final history = <Json>[];
  final answer = TextEditingController(), recognition = SpeechToText();
  final elapsed = ValueNotifier<int>(0);
  final cardsScroll = ScrollController();
  Timer? clock, restart;
  DateTime activity = DateTime.now();
  Future<void>? flushing;
  Json get settings => {...originalSettings, ...widget.store.settings};
  Json get word => queue[index];
  List<Json> get all =>
      widget.kind == 'words' ? widget.store.words : widget.store.idioms;
  String get sessionKey => 'session-${widget.kind}-${widget.folder ?? 'all'}';
  @override
  void initState() {
    super.initState();
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
      if (ids is List && number(saved['index']) < ids.length) {
        final restored = ids
            .map((id) => all.where((w) => '${w['id']}' == '$id').firstOrNull)
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
        if (!widget.exam) speakFront();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(syncCurrent);
    clock?.cancel();
    restart?.cancel();
    audio.speech.stop();
    recognition.stop();
    flush();
    answer.dispose();
    elapsed.dispose();
    cardsScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    if (!resumed) {
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
    });
  }

  void syncCurrent() {
    if (!mounted || busy || leaving || index >= queue.length) return;
    final fresh = all.where((w) => '${w['id']}' == '${word['id']}').firstOrNull;
    setState(() {
      missing = fresh == null;
      if (fresh != null) queue[index] = Map<String, dynamic>.from(fresh);
    });
    if (missing) audio.speech.stop();
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
    back = false;
    result = null;
    answer.clear();
    saveSession();
    if (index >= queue.length) {
      await finish();
      return;
    }
    setState(() {});
    speakFront();
  }

  Future<void> flush() async {
    if (flushing != null) return flushing!;
    if (pending == 0) return;
    final n = pending;
    final work = widget.store.addTime(n);
    flushing = work;
    try {
      await work;
      pending -= n;
    } catch (_) {
    } finally {
      flushing = null;
    }
  }

  Future<void> finish() async {
    if (leaving || !mounted) return;
    leaving = true;
    audio.speech.stop();
    recognition.stop();
    await flush();
    if (!mounted) return;
    widget.prefs.set(sessionKey, null);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(widget.exam ? 'Экзамен завершен!' : 'Сессия завершена!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
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
        index = last['index'] as int;
        queue[index]['progress_global'] = last['progress'];
        back = false;
        saveSession();
        if (mounted) setState(() => busy = false);
        if (cardsScroll.hasClients) cardsScroll.jumpTo(0);
        speakFront();
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
    if (busy || missing) return;
    activity = DateTime.now();
    setState(() => back = !back);
    audio.speech.stop();
    if (settings['audio'] == true) {
      if (back && settings['audioTranslation'] == true) {
        audio.speech.say(
          '${word['translation'] ?? ''}${widget.kind == 'idioms' && settings['audioInfo1'] == true ? '. ${word['meaning'] ?? ''}' : ''}',
          language: 'ru',
          settings: _audioSettings('ru'),
        );
      } else if (!back) {
        speakFront();
      }
    }
  }

  Future<void> rate(int rating) async {
    if (busy || missing || widget.exam) return;
    activity = DateTime.now();
    setState(() => busy = true);
    await audio.speech.stop();
    final previous = word['progress_global'] == null
        ? null
        : Map<String, dynamic>.from(asMap(word['progress_global']));
    final next = review(
      asMap(word['progress_global']),
      rating,
      mode: '${settings['studyMode']}',
    );
    try {
      await widget.store.progress(widget.kind, '${word['id']}', next);
      history.add({'id': word['id'], 'index': index, 'progress': previous});
      if (history.length > 10) history.removeAt(0);
      word['progress_global'] = next;
      index++;
      back = false;
      saveSession();
      if (!mounted) return;
      if (index >= queue.length) {
        await finish();
      } else {
        setState(() => busy = false);
        if (cardsScroll.hasClients) cardsScroll.jumpTo(0);
        speakFront();
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        notify(context, e);
      }
    }
  }

  Future<void> edit() async {
    await audio.speech.stop();
    if (!mounted) return;
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
        back = false;
      });
      speakFront();
    }
  }

  Future<void> openSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _SessionSettings(
          store: widget.store,
          voiceOn: listening,
          onVoice: toggleVoice,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
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
        if (['переверни', 'открой', 'покажи'].any(text.contains)) {
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
    if (queue.isEmpty || index >= queue.length) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) exit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Listener(
            onPointerDown: (_) => activity = DateTime.now(),
            onPointerMove: (_) => activity = DateTime.now(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _Background(light: widget.prefs.light),
                    ),
                  ),
                ),
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
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: cardsScroll,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 110),
            children: [
              Row(
                children: [
                  Square('back', onTap: exit, tooltip: 'Выйти'),
                  const SizedBox(width: 8),
                  Square(
                    settings['audio'] == true ? 'volume' : 'muted',
                    active: settings['audio'] == true,
                    onTap: () async {
                      await widget.store.patch({
                        'settings/study': {
                          ...settings,
                          'audio': settings['audio'] != true,
                        },
                      });
                      if (mounted) setState(() {});
                      if (settings['audio'] != true) audio.speech.stop();
                    },
                    tooltip: 'Озвучка',
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
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
                  label('$ideal', size: 12, weight: FontWeight.w700),
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
                  Square('settings', onTap: openSettings, tooltip: 'Настройки'),
                ],
              ),
              gap(24),
              Row(
                spacing: 12,
                children: [
                  for (final v in <(String, String, bool)>[
                    (
                      '${scope.length}',
                      'Всего слов',
                      settings['showStatTotal'] == true,
                    ),
                    ('$due', 'К повторению', settings['showStatDue'] == true),
                    (
                      '$learned',
                      'Пройдено сегодня',
                      settings['showStatToday'] == true,
                    ),
                  ])
                    if (v.$3)
                      Expanded(
                        child: SizedBox(
                          height: 76,
                          child: Surface(
                            radius: 12,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 9,
                            ),
                            strong: true,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                label(v.$1, size: 18, weight: FontWeight.w700),
                                gap(4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 90,
                                  ),
                                  child: label(
                                    v.$2,
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
              gap(24),
              _NativeFlashcard(
                key: ValueKey('${word['id']}'),
                back: back,
                onFlip: flip,
                front: _front(),
                reverse: _back(),
              ),
              gap(32),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var r = 1; r <= 6; r++)
                      SizedBox(
                        width: (c.maxWidth - 12) / 2,
                        child: Tap(
                          label: ratingNames[r],
                          onTap: busy ? null : () => rate(r),
                          child: Container(
                            height: 60,
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
                                        size: 14,
                                        weight: FontWeight.w700,
                                      ),
                                      gap(2),
                                      label(_intervalLabel(r), size: 12),
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
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (settings['showProgress'] == true) ...[
                gap(16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: queue.isEmpty ? 0 : index / queue.length,
                    minHeight: 5,
                    color: fg,
                    backgroundColor: fg.withValues(alpha: .12),
                  ),
                ),
              ],
            ],
          ),
        ),
        SessionNavigation(
          store: widget.store,
          prefs: widget.prefs,
          onExit: () async {
            await flush();
            if (mounted) Navigator.pop(context);
          },
          listening: listening,
        ),
      ],
    );
  }

  Color prefsSchemeColor(int r) {
    if (widget.prefs.scheme == 'pure-black') {
      return ink(context).withValues(alpha: .08);
    }
    final colors = schemes[widget.prefs.scheme] ?? schemes['default']!;
    return Color.lerp(colors[0], colors[1], (r - 1) / 5)!.withValues(alpha: .1);
  }

  String _intervalLabel(int r) {
    final d = (intervals['${settings['studyMode']}'] ?? intervals['long']!)[r];
    return d < 1
        ? '1 час'
        : switch (d.toInt()) {
            1 => '1 день',
            2 => '2 дня',
            4 => '4 дня',
            _ => '${d.toInt()} дней',
          };
  }

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
      fontFamily: 'Roboto',
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
          strong: true,
          tint: settings['genderCardBackground'] == true ? gender : null,
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 216),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (settings['showWord'] == true)
                    Text.rich(
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
                    for (final ex in examples)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
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
                            ex,
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
    strong: true,
    tint: settings['genderCardBackground'] == true ? gender : null,
    padding: const EdgeInsets.all(32),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 216),
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
        label(
          '${word['info1'] ?? ''}'.isNotEmpty
              ? '________, Präsens, Präteritum, Partizip II'
              : wordTitle(word).contains(',')
              ? '________, (plural)'
              : 'Введите ${wordTitle(word).split(RegExp(r'\s+')).length} слова/слов',
          size: 14,
          color: muted(context),
        ),
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

class _NativeFlashcard extends StatefulWidget {
  const _NativeFlashcard({
    super.key,
    required this.back,
    required this.onFlip,
    required this.front,
    required this.reverse,
  });
  final bool back;
  final VoidCallback onFlip;
  final Widget front, reverse;
  @override
  State<_NativeFlashcard> createState() => _NativeFlashcardState();
}

class _NativeFlashcardState extends State<_NativeFlashcard>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    value: widget.back ? 1 : 0,
  );
  @override
  void didUpdateWidget(_NativeFlashcard old) {
    super.didUpdateWidget(old);
    if (widget.back != old.back) {
      animation.animateTo(widget.back ? 1 : 0, curve: Curves.easeInOutCubic);
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tap(
    label: 'Перевернуть карточку',
    onTap: widget.onFlip,
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value, isBack = t >= .5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0015)
              ..rotateY(t * math.pi),
            child: Stack(
              children: [
                Visibility(
                  visible: false,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: widget.front,
                ),
                Visibility(
                  visible: false,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: widget.reverse,
                ),
                Positioned.fill(
                  child: isBack
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(math.pi),
                          child: widget.reverse,
                        )
                      : widget.front,
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
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
    final roots = ('$title $forms')
        .toLowerCase()
        .split(RegExp(r'[^a-zäöüß]+'))
        .where(
          (w) =>
              w.length > 3 && !['haben', 'sich', 'wird', 'werden'].contains(w),
        )
        .map((w) => w.substring(0, math.min(w.length, 5)))
        .toSet();
    final parts = text.split(RegExp(r'(?<=\s)|(?=\s)'));
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14.4,
          height: 1.4,
          color: muted(context),
        ),
        children: [
          const TextSpan(text: '• '),
          for (final part in parts)
            TextSpan(
              text: part,
              style: roots.any((r) => part.toLowerCase().startsWith(r))
                  ? TextStyle(
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: ink(context),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class SessionNavigation extends StatelessWidget {
  const SessionNavigation({
    super.key,
    required this.store,
    required this.prefs,
    required this.onExit,
    required this.listening,
  });
  final TwinkStore store;
  final NativePreferences prefs;
  final Future<void> Function() onExit;
  final bool listening;
  @override
  Widget build(BuildContext context) {
    final fg = ink(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
      child: Container(
        height: 60,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xf016161b)
              : const Color(0xf0e5e5e8),
          border: Border.all(color: fg.withValues(alpha: .3)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          children: [
            for (var i = 0; i < 5; i++)
              Expanded(
                child: Tap(
                  label: const [
                    'Профиль',
                    'Словарь',
                    'Учить',
                    'Импорт',
                    'Настройки',
                  ][i],
                  onTap: () {
                    if (i != 2) {
                      prefs.set('tab', const [0, 2, 1, 3, 4][i]);
                      onExit();
                    }
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: i == 2
                        ? BoxDecoration(
                            color: fg,
                            borderRadius: BorderRadius.circular(99),
                          )
                        : null,
                    child: Glyph(
                      const ['user', 'book', 'play', 'upload', 'settings'][i],
                      color: i == 2
                          ? Theme.of(context).scaffoldBackgroundColor
                          : fg.withValues(alpha: .8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
