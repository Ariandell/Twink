import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../domain.dart';
import '../repository.dart';
import '../speech.dart' as audio;
import '../audio_api.dart' show speechPlan;
import '../spreadsheet.dart';

part 'profile.dart';
part 'dictionary.dart';
part 'study.dart';
part 'settings.dart';
part 'trail.dart';
part 'exam_help.dart';

Uint8List _encodeExport((List<Json>, String) input) =>
    encodeSpreadsheet(input.$1, input.$2);

const originalSettings = <String, dynamic>{
  'audio': true,
  'audioWord': true,
  'audioInfo1': true,
  'audioInfo2': true,
  'audioEx1': false,
  'audioEx2': false,
  'audioTranslation': true,
  'showWord': true,
  'showInfo1': true,
  'showInfo2': true,
  'showEx1': true,
  'showEx2': true,
  'showProgress': true,
  'showStatTotal': true,
  'showStatDue': true,
  'showStatToday': true,
  'masterCard': false,
  'masterInterface': false,
  'masterAudio': true,
  'includeActive': false,
  'genderColors': false,
  'genderCardBackground': false,
  'studyMode': 'long',
  'selectAudioDe': 'elevenlabs_Qy4b2JlSGxY7I9M9Bqxb',
  'selectAudioRu': 'elevenlabs_3EuKHIEZbSzrHGNmdYsx',
};
const ratingNames = [
  '',
  'Не помню',
  'С трудом',
  'Частично',
  'Почти',
  'Помню',
  'Отлично',
];
const schemes = {
  'default': [Color(0xff3b82f6), Color(0xff10b981)],
  'pink-yellow': [Color(0xffec4899), Color(0xfff59e0b)],
  'purple-orange': [Color(0xff8b5cf6), Color(0xfff97316)],
  'red-cyan': [Color(0xffef4444), Color(0xff06b6d4)],
  'midnight-gold': [Color(0xff1e1b4b), Color(0xfffacc15)],
  'pure-black': [Colors.white, Colors.white],
};

class NativePreferences extends ChangeNotifier {
  NativePreferences({this.persistent = true});
  final bool persistent;
  final Json values = {};
  Timer? _save;
  bool get light => values['theme'] == 'light';
  String get scheme => '${values['scheme'] ?? 'pure-black'}';
  Future<void> load() async {
    if (!persistent) return;
    try {
      values.addAll(
        asMap(
          jsonDecode(
            await const FlutterSecureStorage().read(key: 'twink-native-ui') ??
                '{}',
          ),
        ),
      );
    } catch (_) {}
    notifyListeners();
  }

  void set(String key, dynamic value) {
    values[key] = value;
    notifyListeners();
    _save?.cancel();
    if (persistent) {
      _save = Timer(
        const Duration(milliseconds: 150),
        () => const FlutterSecureStorage().write(
          key: 'twink-native-ui',
          value: jsonEncode(values),
        ),
      );
    }
  }

  @override
  void dispose() {
    _save?.cancel();
    super.dispose();
  }
}

class NativeTwinkApp extends StatefulWidget {
  const NativeTwinkApp({super.key, this.store, this.preferences});
  final TwinkStore? store;
  final NativePreferences? preferences;
  @override
  State<NativeTwinkApp> createState() => _NativeTwinkAppState();
}

class _NativeTwinkAppState extends State<NativeTwinkApp> {
  late final store = widget.store ?? TwinkStore();
  late final prefs = widget.preferences ?? NativePreferences();
  @override
  void initState() {
    super.initState();
    if (widget.preferences == null) prefs.load();
    if (widget.store == null) {
      if (const bool.fromEnvironment('TWINK_DEMO')) {
        store.startDemo();
      } else {
        store.initialize();
      }
    }
  }

  @override
  void dispose() {
    if (widget.store == null) store.dispose();
    if (widget.preferences == null) prefs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: prefs,
    builder: (context, _) {
      final light = prefs.light, fg = light ? Colors.black : Colors.white;
      return MaterialApp(
        title: 'German Vocabulary',
        debugShowCheckedModeBanner: false,
        builder: (context, child) => NativeTrail(prefs: prefs, child: child!),
        theme: ThemeData(
          useMaterial3: true,
          brightness: light ? Brightness.light : Brightness.dark,
          fontFamily: 'Roboto',
          textTheme: (light ? ThemeData.light() : ThemeData.dark()).textTheme
              .apply(fontFamily: 'Roboto', bodyColor: fg, displayColor: fg),
          scaffoldBackgroundColor: light ? Colors.white : Colors.black,
          colorScheme:
              ColorScheme.fromSeed(
                seedColor: fg,
                brightness: light ? Brightness.light : Brightness.dark,
              ).copyWith(
                primary: fg,
                onPrimary: light ? Colors.white : Colors.black,
                secondary: fg,
                onSecondary: light ? Colors.white : Colors.black,
                secondaryContainer: fg.withValues(alpha: .12),
                onSecondaryContainer: fg,
                outline: fg.withValues(alpha: .2),
                error: const Color(0xffef4444),
                surface: light ? Colors.white : const Color(0xff101010),
              ),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: fg,
            selectionColor: fg.withValues(alpha: .18),
            selectionHandleColor: fg,
          ),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            },
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: false,
            labelStyle: TextStyle(color: fg.withValues(alpha: .6)),
            hintStyle: TextStyle(color: fg.withValues(alpha: .4)),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: fg.withValues(alpha: .15)),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: fg.withValues(alpha: .15)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: fg.withValues(alpha: .7)),
            ),
          ),
        ),
        home: ListenableBuilder(
          listenable: store,
          builder: (context, _) => store.loading
              ? const Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : store.signedIn
              ? NativeHome(store: store, prefs: prefs)
              : _AuthPage(store: store),
        ),
      );
    },
  );
}

Color ink(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark ? Colors.white : Colors.black;
Color muted(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xff9ca3af)
    : const Color(0xff4b5563);
Widget gap([double h = 12]) => SizedBox(height: h);
Text label(
  String value, {
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color? color,
  TextAlign? align,
  int? lines,
  double? spacing,
}) => Text(
  value,
  style: TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: spacing,
    height: 1.25,
  ),
  textAlign: align,
  maxLines: lines,
  overflow: lines == null ? null : TextOverflow.ellipsis,
);

class Glyph extends StatelessWidget {
  const Glyph(this.name, {super.key, this.size = 22, this.color});
  final String name;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color ?? ink(context), BlendMode.srcIn),
  );
}

class Tap extends StatelessWidget {
  const Tap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.label,
  });
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final String? label;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    enabled: onTap != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.strong = false,
    this.tint,
    this.background,
    this.borderColor,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool strong;
  final Color? tint;
  final Color? background, borderColor;
  @override
  Widget build(BuildContext context) {
    final c = ink(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? c.withValues(alpha: strong ? .2 : .12),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            background ??
                tint?.withValues(alpha: .15) ??
                c.withValues(alpha: strong ? .05 : .03),
            background ?? c.withValues(alpha: .01),
          ],
        ),
      ),
      child: child,
    );
  }
}

class Square extends StatelessWidget {
  const Square(
    this.icon, {
    super.key,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.border = true,
    this.size = 40,
  });
  final String icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool active, border;
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: Tap(
      label: tooltip,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: !border
              ? null
              : Border.all(
                  color: ink(context).withValues(alpha: active ? .7 : .15),
                ),
          borderRadius: BorderRadius.circular(10),
          color: active ? ink(context).withValues(alpha: .035) : null,
        ),
        child: Glyph(
          icon,
          size: 20,
          color: active ? ink(context) : muted(context),
        ),
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    required this.onTap,
    this.primary = false,
    this.icon,
    this.busy = false,
  });
  final String text;
  final VoidCallback? onTap;
  final bool primary, busy;
  final String? icon;
  @override
  Widget build(BuildContext context) {
    final fg = primary
        ? Theme.of(context).scaffoldBackgroundColor
        : ink(context);
    return Tap(
      onTap: busy ? null : onTap,
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: primary ? ink(context) : ink(context).withValues(alpha: .035),
          border: Border.all(color: ink(context).withValues(alpha: .15)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Glyph(icon!, size: 19, color: fg),
              const SizedBox(width: 9),
            ],
            if (busy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            else
              Flexible(
                child: label(
                  text,
                  size: 14,
                  weight: FontWeight.w700,
                  color: fg,
                  align: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<bool> nativeConfirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('OK'),
          ),
        ],
      ),
    ) ??
    false;
void notify(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error is String ? error : errorText(error))),
    );
  }
}

Future<String?> nativePrompt(
  BuildContext context,
  String title, {
  String value = '',
  bool secret = false,
}) async {
  final input = TextEditingController(text: value);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: input,
        autofocus: true,
        obscureText: secret,
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, input.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 350), input.dispose);
  return result;
}

class NativeHome extends StatefulWidget {
  const NativeHome({super.key, required this.store, required this.prefs});
  final TwinkStore store;
  final NativePreferences prefs;
  @override
  State<NativeHome> createState() => _NativeHomeState();
}

class _NativeHomeState extends State<NativeHome> with WidgetsBindingObserver {
  void update(VoidCallback change) {
    if (mounted) setState(change);
  }

  int tab = 0, settingsTab = 0;
  String kind = 'words', query = '', sort = 'oldest';
  bool folderGrid = false,
      foldersNewest = true,
      duplicates = false,
      exporting = false;
  final scoreFilters = <num>{}, intervalFilters = <num>{};
  final visibleColumns = <String>{
    'word',
    'translation',
    'info1',
    'info2',
    'ex1',
    'ex2',
    'folder',
    'progress',
  };
  final searches = TextEditingController();
  late DateTime chartMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  TwinkStore get store => widget.store;
  NativePreferences get prefs => widget.prefs;
  Json get settings => {...originalSettings, ...store.settings};
  List<Json> get entries => kind == 'words' ? store.words : store.idioms;
  List<String> folders(String k) {
    final list = k == 'words' ? store.words : store.idioms;
    final meta = asMap(
      store.data?[k == 'words' ? 'folderMeta' : 'idiomFolders'],
    );
    final names = <String>{
      ...list.map((w) => '${w['folder'] ?? ''}').where((f) => f.isNotEmpty),
      ...meta.entries.map((e) => '${asMap(e.value)['name'] ?? e.key}'),
    }.toList();
    names.sort();
    if (foldersNewest) return names.reversed.toList();
    return names;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tab = number(prefs.values['tab']).toInt().clamp(0, 4);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      store.reload();
    } else {
      audio.speech.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    searches.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      if (mounted) notify(context, e);
    }
  }

  void selectTab(int value) {
    audio.speech.stop();
    setState(() => tab = value);
    prefs.set('tab', value);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 768;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _Background(light: prefs.light)),
              ),
            ),
            Column(
              children: [
                if (wide) _navigation(wide: true),
                Expanded(
                  child: ListenableBuilder(
                    listenable: store,
                    builder: (context, _) => Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: tab == 0
                              ? 1200
                              : tab == 1
                              ? 900
                              : 1100,
                        ),
                        child: switch (tab) {
                          0 => _profile(),
                          1 => _studyDashboard(),
                          2 => _dictionary(),
                          3 => _importPage(),
                          _ => _settingsPage(),
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (!wide)
              Positioned(
                left: 28,
                right: 28,
                bottom: 12,
                child: RepaintBoundary(child: _navigation()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _navigation({bool wide = false}) {
    final fg = ink(context),
        names = ['Профиль', 'Учить', 'Словарь', 'Импорт', 'Настройки'],
        icons = ['user', 'play', 'book', 'upload', 'settings'];
    final order = [0, 2, 1, 3, 4];
    final ordered = wide ? [0, 1, 2, 3, 4] : order;
    return Center(
      child: Container(
        height: wide ? 70 : 60,
        constraints: BoxConstraints(maxWidth: wide ? 700 : 450),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xf016161b)
              : const Color(0xf0e5e5e8),
          border: Border.all(color: fg.withValues(alpha: .3)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth / 5;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: ordered.indexOf(tab) * width,
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: fg,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Row(
                  children: ordered
                      .map(
                        (i) => Expanded(
                          child: Tap(
                            label: names[i],
                            onTap: () => selectTab(i),
                            child: Center(
                              child: wide
                                  ? label(
                                      names[i],
                                      size: 14,
                                      weight: tab == i
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: tab == i
                                          ? Theme.of(context)
                                                .scaffoldBackgroundColor
                                          : fg,
                                    )
                                  : Glyph(
                                      icons[i],
                                      size: 22,
                                      color: tab == i
                                          ? Theme.of(context)
                                                .scaffoldBackgroundColor
                                          : fg.withValues(alpha: .8),
                                    ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget scrolling(
    List<Widget> children, {
    double top = 16,
    double bottom = 112,
  }) => ListView(
    padding: EdgeInsets.fromLTRB(12, top, 12, bottom),
    children: children,
  );
}

class _Background extends CustomPainter {
  const _Background({this.light = false});
  final bool light;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.2, 1),
          radius: 1,
          colors: [
            light ? const Color(0xfff6f6f8) : const Color(0xff0f0e18),
            light ? const Color(0x00f6f6f8) : const Color(0x000f0e18),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Background old) => old.light != light;
}

class _AuthPage extends StatefulWidget {
  const _AuthPage({required this.store});
  final TwinkStore store;
  @override
  State<_AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<_AuthPage> {
  bool register = false, show = false, busy = false;
  String? error;
  final email = TextEditingController(),
      password = TextEditingController(),
      repeat = TextEditingController(),
      nickname = TextEditingController();
  InputDecoration field(String hint, {Widget? suffix}) => InputDecoration(
    hintText: hint,
    suffixIcon: suffix,
    filled: true,
    fillColor: ink(context).withValues(alpha: .05),
    contentPadding: const EdgeInsets.symmetric(horizontal: 19, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(99),
      borderSide: BorderSide(color: ink(context).withValues(alpha: .1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(99),
      borderSide: BorderSide(color: ink(context).withValues(alpha: .1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(99),
      borderSide: BorderSide(color: ink(context).withValues(alpha: .4)),
    ),
  );
  @override
  void dispose() {
    for (final c in [email, password, repeat, nickname]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (register && password.text != repeat.text) {
      setState(() => error = 'Пароли не совпадают');
      return;
    }
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Введите email и пароль');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.login(
        email.text.trim(),
        password.text,
        nickname: register ? nickname.text.trim() : null,
      );
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label(
                  register ? 'Регистрация' : 'Вход',
                  size: 32,
                  weight: FontWeight.w700,
                  align: TextAlign.center,
                ),
                gap(32),
                if (register) ...[
                  TextField(controller: nickname, decoration: field('Никнейм')),
                  gap(18),
                ],
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: field('Email'),
                ),
                gap(18),
                TextField(
                  controller: password,
                  obscureText: !show,
                  autofillHints: const [AutofillHints.password],
                  decoration: field(
                    'Пароль',
                    suffix: Square(
                      'eye',
                      onTap: () => setState(() => show = !show),
                      border: false,
                    ),
                  ),
                  onSubmitted: (_) => submit(),
                ),
                if (register) ...[
                  gap(18),
                  TextField(
                    controller: repeat,
                    obscureText: !show,
                    decoration: field('Повторите пароль'),
                  ),
                ],
                gap(24),
                Pill(
                  register ? 'Зарегистрироваться' : 'Войти',
                  onTap: submit,
                  primary: true,
                  busy: busy,
                ),
                if (error != null) ...[
                  gap(),
                  label(
                    error!,
                    color: const Color(0xffef4444),
                    align: TextAlign.center,
                  ),
                ],
                gap(24),
                Tap(
                  onTap: () => setState(() {
                    register = !register;
                    error = null;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: label(
                      register
                          ? 'Уже есть аккаунт? Войти'
                          : 'Нет аккаунта? Регистрация',
                      color: muted(context),
                      align: TextAlign.center,
                    ),
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
