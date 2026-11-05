part of 'app.dart';

extension _SettingsView on _NativeHomeState {
  Widget _settingsPage() => scrolling([
    label('Настройки', size: 22, weight: FontWeight.w700),
    gap(22),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tap(
                onTap: () => update(() => settingsTab = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: settingsTab == i
                        ? ink(context)
                        : ink(context).withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: ink(context).withValues(alpha: .12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Glyph(
                        ['user', 'trophy', 'settings'][i],
                        size: 16,
                        color: settingsTab == i
                            ? Theme.of(context).scaffoldBackgroundColor
                            : ink(context),
                      ),
                      const SizedBox(width: 6),
                      label(
                        ['Профиль', 'Прогресс', 'Персонализация'][i],
                        size: 13,
                        weight: FontWeight.w700,
                        color: settingsTab == i
                            ? Theme.of(context).scaffoldBackgroundColor
                            : ink(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    gap(26),
    ...switch (settingsTab) {
      0 => _profileSettings(),
      1 => _progressSettings(),
      _ => _appearanceSettings(),
    },
  ]);
  List<Widget> _profileSettings() => [
    label('Управление профилем', size: 20, weight: FontWeight.w700),
    gap(24),
    _accountField(
      'НИКНЕЙМ',
      '${store.data?['nickname'] ?? ''}',
      (v) => store.patch({'nickname': v}),
    ),
    gap(24),
    _accountField(
      'ЭЛЕКТРОННАЯ ПОЧТА',
      store.email ?? '',
      (v) => store.updateAccount(mail: v),
    ),
    gap(24),
    _accountField(
      'ПАРОЛЬ',
      '',
      (v) => store.updateAccount(password: v),
      secret: true,
    ),
    gap(32),
    Pill(
      'Выйти из учетной записи',
      icon: 'logout',
      onTap: () => run(store.logout),
    ),
    gap(16),
    Pill(
      'Удалить профиль',
      onTap: () async {
        if (!await nativeConfirm(
          context,
          'Удалить профиль и все данные? Это действие нельзя отменить.',
        )) {
          return;
        }
        if (!mounted) return;
        final password = store.demo
            ? ''
            : await nativePrompt(
                context,
                'Подтвердите текущий пароль',
                secret: true,
              );
        if (password != null) await run(() => store.deleteAccount(password));
      },
    ),
  ];
  Widget _accountField(
    String title,
    String value,
    Future<void> Function(String) save, {
    bool secret = false,
  }) => _AccountField(
    key: ValueKey(title),
    title: title,
    value: value,
    secret: secret,
    onSave: save,
  );
  List<Widget> _progressSettings() => [
    label('Слова и прогресс', size: 20, weight: FontWeight.w700),
    gap(24),
    label('Режим обучения', size: 18, weight: FontWeight.w700),
    gap(8),
    label('Выберите интервалы повторения для карточек.', color: muted(context)),
    gap(16),
    Row(
      children: [
        Expanded(
          child: Pill(
            'Долгое изучение',
            primary: settings['studyMode'] == 'long',
            onTap: () => _changeMode('long'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Pill(
            'Интенсивное',
            primary: settings['studyMode'] == 'intensive',
            onTap: () => _changeMode('intensive'),
          ),
        ),
      ],
    ),
    gap(16),
    _ModeComparison(mode: settings['studyMode'].toString()),
    gap(32),
    for (final item in [
      ('words', false, 'Сбросить прогресс слов'),
      ('words', true, 'Очистить словарь (удалить все слова)'),
      ('idioms', false, 'Сбросить прогресс идиом'),
      ('idioms', true, 'Очистить все идиомы'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Pill(item.$3, onTap: () => _resetData(item.$1, item.$2)),
      ),
  ];
  Future<void> _changeMode(String mode) async {
    if (mode == settings['studyMode']) return;
    if (!await nativeConfirm(
      context,
      mode == 'intensive'
          ? 'Вы уверены, что хотите переключиться на ИНТЕНСИВНЫЙ режим? Все интервалы будут сокращены для более частого повторения.'
          : 'Переключиться на стандартный режим? Все интервалы будут пересчитаны в сторону увеличения.',
    )) {
      return;
    }
    if (!mounted) return;
    final oldMode = '${settings['studyMode']}',
        oldIntervals = intervals[oldMode] ?? intervals['long']!,
        nextIntervals = intervals[mode]!,
        now = DateTime.now().millisecondsSinceEpoch;
    await run(() async {
      final updates = <String, dynamic>{
        'settings/study': {...settings, 'studyMode': mode},
      };
      for (final k in ['words', 'idioms']) {
        for (final w in k == 'words' ? store.words : store.idioms) {
          final p = asMap(w['progress_global']);
          if (p.isEmpty ||
              p['lastRating'] == null &&
                  number(p['interval']) == 0 &&
                  p['is_ideal'] != true &&
                  p['isActive'] != true) {
            continue;
          }
          var r = number(p['lastRating']).toInt();
          if (r < 1 || r > 6) {
            r = 1;
            for (var i = 2; i <= 6; i++) {
              if ((oldIntervals[i] - number(p['interval'])).abs() <
                  (oldIntervals[r] - number(p['interval'])).abs()) {
                r = i;
              }
            }
          }
          final reviewed = number(p['lastReviewed']) > 0
              ? number(p['lastReviewed']).toInt()
              : (number(p['nextDate']) > 0
                        ? number(p['nextDate']).toInt()
                        : now) -
                    (number(p['interval']) * dayMs).round();
          final nextDate =
              math.min(now, reviewed) + (nextIntervals[r] * dayMs).round();
          final next = {
            ...p,
            'interval': nextIntervals[r],
            'nextDate': nextDate,
            'is_ideal':
                p['isActive'] == true ||
                nextDate > now && (r >= 5 || p['is_ideal'] == true),
            'lastRating': r,
          };
          updates['$k/${w['id']}/progress_global'] = next;
          if (k == 'words') {
            updates['words/${w['id']}/interval'] = nextIntervals[r];
            updates['words/${w['id']}/nextDate'] = nextDate;
          }
        }
      }
      await store.patch(updates);
    });
    if (mounted) update(() {});
  }

  Future<void> _resetData(String k, bool clear) async {
    if (!await nativeConfirm(
      context,
      clear
          ? 'Удалить все ${k == 'words' ? 'слова' : 'идиомы'}? Это действие нельзя отменить.'
          : 'Сбросить весь прогресс ${k == 'words' ? 'слов' : 'идиом'}?',
    )) {
      return;
    }
    await run(
      () => store.patch(
        clear
            ? {k: null, k == 'words' ? 'folderMeta' : 'idiomFolders': null}
            : {
                for (final w in k == 'words' ? store.words : store.idioms)
                  '$k/${w['id']}/progress_global': freshProgress(),
                if (k == 'words')
                  for (final w in store.words) ...{
                    'words/${w['id']}/interval': 0,
                    'words/${w['id']}/nextDate':
                        DateTime.now().millisecondsSinceEpoch,
                  },
              },
      ),
    );
  }

  List<Widget> _appearanceSettings() {
    const names = {
      'default': 'Синий-Зеленый',
      'pink-yellow': 'Розовый-Желтый',
      'purple-orange': 'Фиолетовый-Оранжевый',
      'red-cyan': 'Красный-Голубой',
      'midnight-gold': 'Индиго-Золото',
      'pure-black': 'Чистый черный',
    };
    final fg = ink(context);
    return [
      label('Внешний вид', size: 20, weight: FontWeight.w700),
      gap(8),
      label('Выберите тему оформления приложения.', color: muted(context)),
      gap(16),
      Row(
        children: [
          Expanded(
            child: Pill(
              'Темная',
              primary: !prefs.light,
              onTap: () => prefs.set('theme', 'dark'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Pill(
              'Светлая',
              primary: prefs.light,
              onTap: () => prefs.set('theme', 'light'),
            ),
          ),
        ],
      ),
      gap(32),
      label('Цветовая схема', size: 20, weight: FontWeight.w700),
      gap(8),
      label(
        'Выберите акцентные цвета для выбранной темы.',
        color: muted(context),
      ),
      gap(16),
      LayoutBuilder(
        builder: (context, c) => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final e in schemes.entries)
              SizedBox(
                width: (c.maxWidth - 10) / 2,
                child: Tap(
                  onTap: () => prefs.set('scheme', e.key),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: .025),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: fg.withValues(
                          alpha: prefs.scheme == e.key ? .8 : .12,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: fg.withValues(alpha: .2)),
                            gradient: LinearGradient(
                              colors: e.key == 'pure-black'
                                  ? [
                                      Theme.of(context).scaffoldBackgroundColor,
                                      Theme.of(context).scaffoldBackgroundColor,
                                    ]
                                  : e.value,
                            ),
                          ),
                        ),
                        gap(10),
                        label(
                          e.key == 'pure-black' && prefs.light
                              ? 'Чистый белый'
                              : names[e.key]!,
                          size: 12,
                          weight: FontWeight.w500,
                          align: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      gap(32),
      label('Шлейф за мышкой', size: 20, weight: FontWeight.w700),
      gap(8),
      label(
        'Интерактивные частицы, следующие за курсором.',
        color: muted(context),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(child: label('Шлейф')),
            _NativeSwitch(
              value: prefs.values['trail'] != false,
              onChanged: (v) => prefs.set('trail', v),
            ),
          ],
        ),
      ),
      Row(
        children: [
          Expanded(
            child: Pill(
              'Искры',
              primary: prefs.values['trailType'] != 'fluid',
              onTap: () => prefs.set('trailType', 'sparks'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Pill(
              'Антигравитация',
              primary: prefs.values['trailType'] == 'fluid',
              onTap: () => prefs.set('trailType', 'fluid'),
            ),
          ),
        ],
      ),
      gap(32),
      label('Аватар', size: 20, weight: FontWeight.w700),
      gap(8),
      label(
        'Загрузите изображение профиля (PNG, JPG, макс. 2МБ).',
        color: muted(context),
      ),
      gap(16),
      Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg.withValues(alpha: .04),
              image: avatarImage(store.data?['avatar']) == null
                  ? null
                  : DecorationImage(
                      image: avatarImage(store.data?['avatar'])!,
                      fit: BoxFit.cover,
                    ),
            ),
            child: store.data?['avatar'] == null
                ? const Center(child: Glyph('image', size: 30))
                : null,
          ),
          const SizedBox(width: 18),
          Expanded(child: Pill('Загрузить фото', onTap: _chooseAvatar)),
        ],
      ),
      if (store.data?['avatar'] != null) ...[
        gap(12),
        Pill(
          'Удалить фото',
          onTap: () async {
            if (await nativeConfirm(context, 'Удалить фото профиля?')) {
              await run(() => store.patch({'avatar': null}));
            }
          },
        ),
      ],
    ];
  }

  Future<void> _chooseAvatar() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        if (mounted) {
          notify(context, 'Файл слишком большой. Максимальный размер 2МБ.');
        }
        return;
      }
      final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      await store.patch({
        'avatar': 'data:image/$ext;base64,${base64Encode(bytes)}',
      });
    } catch (e) {
      if (mounted) notify(context, e);
    }
  }
}

class _AccountField extends StatefulWidget {
  const _AccountField({
    super.key,
    required this.title,
    required this.value,
    required this.secret,
    required this.onSave,
  });
  final String title, value;
  final bool secret;
  final Future<void> Function(String) onSave;
  @override
  State<_AccountField> createState() => _AccountFieldState();
}

class _AccountFieldState extends State<_AccountField> {
  late final input = TextEditingController(text: widget.value);
  bool busy = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      label(widget.title, size: 12, color: muted(context)),
      gap(8),
      TextField(
        controller: input,
        obscureText: widget.secret,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: widget.secret ? 'Введите новый пароль' : '',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(99)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(99),
            borderSide: BorderSide(color: ink(context).withValues(alpha: .12)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
        ),
      ),
      gap(8),
      Pill(
        'Сохранить',
        busy: busy,
        onTap: input.text.trim().isEmpty
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  await widget.onSave(input.text.trim());
                  if (context.mounted) notify(context, 'Сохранено');
                } catch (e) {
                  if (context.mounted) notify(context, e);
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
      ),
    ],
  );
}

class _SessionSettings extends StatefulWidget {
  const _SessionSettings({
    required this.store,
    this.voiceOn = false,
    this.onVoice,
  });
  final TwinkStore store;
  final bool voiceOn;
  final Future<void> Function()? onVoice;
  @override
  State<_SessionSettings> createState() => _SessionSettingsState();
}

class _SessionSettingsState extends State<_SessionSettings> {
  late Json draft = {...originalSettings, ...widget.store.settings};
  late bool voice = widget.voiceOn;
  bool saving = false;
  late String providerDe = '${draft['selectAudioDe']}'.startsWith('elevenlabs_')
          ? 'elevenlabs'
          : 'system',
      providerRu = '${draft['selectAudioRu']}'.startsWith('elevenlabs_')
          ? 'elevenlabs'
          : 'system';
  int? quota;
  int quotaLimit = 10000;
  String? quotaError;
  @override
  void initState() {
    super.initState();
    _quota();
  }

  Future<void> _quota() async {
    try {
      final q = await audio.speech.client.quota();
      if (mounted) {
        setState(() {
          quota = number(q['used']).toInt();
          quotaLimit = number(q['limit']).toInt();
          quotaError = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => quotaError = 'Не удалось проверить лимит');
    }
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.store.patch({'settings/study': draft});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        notify(context, e);
      }
    }
  }

  Widget toggle(String key, String title, {bool expand = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: label(title, size: 14, weight: FontWeight.w500)),
        const SizedBox(width: 12),
        if (expand)
          Square(
            'down',
            onTap: () => setState(() => draft[key] = draft[key] != true),
            border: false,
            size: 32,
          )
        else
          _NativeSwitch(
            value: draft[key] == true,
            onChanged: (v) => setState(() => draft[key] = v),
          ),
      ],
    ),
  );
  Widget section(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: label(
      text,
      size: 10,
      weight: FontWeight.w900,
      color: originalSecondary(context).withValues(alpha: .6),
      spacing: 1.6,
    ),
  );
  Widget fields(List<(String, String)> rows) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth < 320 ? 1 : 2;
      return Wrap(
        spacing: 12,
        children: [
          for (final row in rows)
            SizedBox(
              width: cols == 1 ? c.maxWidth : (c.maxWidth - 12) / 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: ink(context).withValues(alpha: .05),
                    ),
                  ),
                ),
                child: toggle(row.$1, row.$2),
              ),
            ),
        ],
      );
    },
  );
  Widget voiceSelect(bool de) {
    final provider = de ? providerDe : providerRu,
        key = de ? 'selectAudioDe' : 'selectAudioRu';
    final voices = provider == 'elevenlabs'
        ? de
              ? {
                  'elevenlabs_Qy4b2JlSGxY7I9M9Bqxb': 'Deutsch Female',
                  'elevenlabs_JBFqnCBsd6RMkjVDRZzb': 'Deutsch Male',
                }
              : {
                  'elevenlabs_3EuKHIEZbSzrHGNmdYsx': 'Russ Male',
                  'elevenlabs_JBFqnCBsd6RMkjVDRZzb': 'Russ Female',
                }
        : de
        ? {'Deutsch Female': 'Deutsch Female', 'Deutsch Male': 'Deutsch Male'}
        : {'Russian Male': 'Russ Male', 'Russian Female': 'Russ Female'};
    final value = voices.containsKey('${draft[key]}')
        ? '${draft[key]}'
        : voices.keys.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        gap(10),
        label(
          de ? 'Немецкий голос' : 'Русский голос',
          size: 13,
          weight: FontWeight.w700,
        ),
        gap(6),
        Row(
          children: [
            Expanded(
              child: _select(
                provider,
                const {
                  'elevenlabs': 'ElevenLabs',
                  'responsivevoice': 'ResponsiveVoice',
                  'system': 'Браузерная',
                },
                (v) => setState(() {
                  if (de) {
                    providerDe = v;
                  } else {
                    providerRu = v;
                  }
                  draft[key] = v == 'elevenlabs'
                      ? (de
                            ? 'elevenlabs_Qy4b2JlSGxY7I9M9Bqxb'
                            : 'elevenlabs_3EuKHIEZbSzrHGNmdYsx')
                      : (de ? 'Deutsch Female' : 'Russian Male');
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _select(
                value,
                voices,
                (v) => setState(() => draft[key] = v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _select(
    String value,
    Map<String, String> options,
    ValueChanged<String> change,
  ) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: ink(context).withValues(alpha: .05),
      border: Border.all(color: ink(context).withValues(alpha: .15)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: options.containsKey(value) ? value : options.keys.first,
        isExpanded: true,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 13,
          color: ink(context),
        ),
        icon: const Glyph('down', size: 14),
        items: options.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) change(v);
        },
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: ink(context).withValues(alpha: .04),
                border: Border(
                  bottom: BorderSide(color: ink(context).withValues(alpha: .1)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: label(
                      'Настройки сессии',
                      size: 14,
                      color: muted(context),
                      weight: FontWeight.w700,
                    ),
                  ),
                  if (saving)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Square(
                      'check',
                      onTap: save,
                      border: false,
                      tooltip: 'Сохранить',
                    ),
                  const SizedBox(width: 6),
                  Square(
                    'close',
                    onTap: saving ? null : () => Navigator.pop(context),
                    border: false,
                    tooltip: 'Закрыть',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  section('ГОЛОС И ОБУЧЕНИЕ'),
                  Row(
                    children: [
                      Expanded(
                        child: label(
                          'Голосовое управление',
                          weight: FontWeight.w700,
                        ),
                      ),
                      _NativeSwitch(
                        value: voice,
                        onChanged: (v) async {
                          if (widget.onVoice != null) {
                            await widget.onVoice!();
                            if (mounted) setState(() => voice = v);
                          }
                        },
                      ),
                    ],
                  ),
                  voiceSelect(true),
                  voiceSelect(false),
                  gap(16),
                  Tap(
                    onTap: _quota,
                    child: label(
                      'ElevenLabs: ${quota ?? '—'} / $quotaLimit символов',
                      size: 11,
                      color: muted(context),
                    ),
                  ),
                  if (quotaError != null)
                    label(quotaError!, size: 10, color: muted(context)),
                  gap(20),
                  Row(
                    children: [
                      Expanded(
                        child: label(
                          'Элементы озвучки',
                          weight: FontWeight.w700,
                        ),
                      ),
                      _NativeSwitch(
                        value: draft['audio'] == true,
                        onChanged: (v) => setState(() => draft['audio'] = v),
                      ),
                      const SizedBox(width: 6),
                      Square(
                        'down',
                        onTap: () => setState(
                          () => draft['masterAudio'] =
                              draft['masterAudio'] != true,
                        ),
                        border: false,
                        size: 28,
                      ),
                    ],
                  ),
                  _LiquidExpansion(
                    open: draft['masterAudio'] == true,
                    child: fields(const [
                      ('audioWord', 'Слово'),
                      ('audioInfo1', 'Формы глагола'),
                      ('audioInfo2', 'Дополнительно'),
                      ('audioEx1', 'Пример 1'),
                      ('audioEx2', 'Пример 2'),
                      ('audioTranslation', 'Перевод'),
                    ]),
                  ),
                  section('ОФОРМЛЕНИЕ'),
                  toggle('genderColors', 'Подсветка слова по роду'),
                  toggle('genderCardBackground', 'Подсветка карточки по роду'),
                  toggle(
                    'masterCard',
                    'Редактировать элементы карточки',
                    expand: true,
                  ),
                  _LiquidExpansion(
                    open: draft['masterCard'] == true,
                    child: fields(const [
                      ('showWord', 'Слово'),
                      ('showInfo1', 'Формы глагола'),
                      ('showInfo2', 'Дополнительно'),
                      ('showEx1', 'Пример 1'),
                      ('showEx2', 'Пример 2'),
                    ]),
                  ),
                  toggle(
                    'masterInterface',
                    'Редактировать интерфейс сессии',
                    expand: true,
                  ),
                  _LiquidExpansion(
                    open: draft['masterInterface'] == true,
                    child: fields(const [
                      ('showProgress', 'Прогресс-бар'),
                      ('showStatTotal', 'Всего слов'),
                      ('showStatDue', 'К повторению'),
                      ('showStatToday', 'Пройдено сегодня'),
                    ]),
                  ),
                  section('ДРУГОЕ'),
                  toggle('includeActive', 'Изучать активные слова'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NativeSwitch extends StatelessWidget {
  const _NativeSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: value ? 'Включено' : 'Выключено',
    child: Tap(
      onTap: () => onChanged(!value),
      child: SizedBox(
        width: 40,
        height: 30,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 22,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? ink(context) : const Color(0xff333642),
              borderRadius: BorderRadius.circular(99),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: value
                      ? Theme.of(context).scaffoldBackgroundColor
                      : Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
