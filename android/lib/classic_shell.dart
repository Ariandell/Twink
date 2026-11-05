import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'classic_asset_server.dart';
import 'domain.dart';
import 'speech.dart' as audio;

class ClassicShell extends StatefulWidget {
  const ClassicShell({super.key});
  @override
  State<ClassicShell> createState() => _ClassicShellState();
}

class _ClassicShellState extends State<ClassicShell>
    with WidgetsBindingObserver {
  final _server = ClassicAssetServer(), _recognizer = SpeechToText();
  WebViewController? _web;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _server.start();
      if (!mounted) {
        await _server.close();
        return;
      }
      final web = WebViewController();
      _web = web;
      await web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await web.setBackgroundColor(Colors.black);
      await web.addJavaScriptChannel(
        'TwinkNative',
        onMessageReceived: (m) => _message(m.message),
      );
      await web.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _error = null);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _error = 'Не удалось открыть приложение.');
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri?.host == '127.0.0.1' && uri?.port == _server.origin.port
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
      await web.setOnJavaScriptAlertDialog((request) async {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            content: Text(request.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
      await web.setOnJavaScriptConfirmDialog((request) async {
        if (!mounted) return false;
        return await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                content: Text(request.message),
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
      });
      await web.setOnJavaScriptTextInputDialog((request) async {
        if (!mounted) return '';
        final input = TextEditingController(text: request.defaultText ?? '');
        final result = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(request.message),
                const SizedBox(height: 14),
                TextField(controller: input, autofocus: true),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, ''),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, input.text),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
        return result ?? '';
      });
      final platform = web.platform;
      if (platform is AndroidWebViewController) {
        await platform.setMediaPlaybackRequiresUserGesture(false);
        await platform.setTextZoom(100);
        await platform.setOnShowFileSelector(_pickFiles);
      }
      await web.loadRequest(
        _server.origin.resolve(
          'index.html?demo=${const bool.fromEnvironment('TWINK_DEMO') ? '1' : '0'}',
        ),
      );
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось запустить приложение. Закройте его и откройте снова.',
        );
      }
    }
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    final image = params.acceptTypes.any((type) => type.startsWith('image/'));
    final extensions = params.acceptTypes
        .expand((type) => type.split(','))
        .where((type) => type.startsWith('.'))
        .map((type) => type.substring(1))
        .toList();
    final kind = image
        ? FileType.image
        : extensions.isNotEmpty
        ? FileType.custom
        : FileType.any;
    final selected = params.mode == FileSelectorMode.openMultiple
        ? await FilePicker.pickFiles(
            type: kind,
            allowedExtensions: extensions.isEmpty ? null : extensions,
          )
        : [
            ?await FilePicker.pickFile(
              type: kind,
              allowedExtensions: extensions.isEmpty ? null : extensions,
            ),
          ];
    final directory = await getTemporaryDirectory(), uris = <String>[];
    for (final file in selected) {
      final name = file.name.replaceAll(RegExp(r'[/\\\x00]'), '_');
      final target = File(
        '${directory.path}/twink-import-${DateTime.now().microsecondsSinceEpoch}-$name',
      );
      await target.writeAsBytes(await file.readAsBytes());
      uris.add(target.uri.toString());
    }
    return uris;
  }

  Future<void> _event(Json data) async {
    if (!mounted || _web == null) return;
    await _web!.runJavaScript(
      'window.dispatchEvent(new CustomEvent("twink-native-event",{detail:${jsonEncode(data)}}));',
    );
  }

  Future<void> _message(String raw) async {
    try {
      final message = asMap(jsonDecode(raw));
      switch (message['type']) {
        case 'speak':
          await audio.speech.say(
            '${message['text'] ?? ''}',
            language: '${message['language'] ?? 'de'}',
            settings: asMap(message['settings']),
          );
          await _event({'id': message['id'], 'type': 'speechComplete'});
        case 'stopAudio':
          await audio.speech.stop();
        case 'download':
          final data = base64Decode('${message['data'] ?? ''}');
          if (data.length > 30 * 1024 * 1024) return;
          await FilePicker.saveFile(
            fileName: '${message['name'] ?? 'WordLab.xlsx'}'
                .split(RegExp(r'[/\\]'))
                .last,
            bytes: data,
          );
        case 'startRecognition':
          final ready = await _recognizer.initialize(
            onStatus: (status) {
              if (status == 'done' || status == 'notListening') {
                _event({'type': 'recognitionEnd'});
              }
            },
            onError: (error) => _event({
              'type': 'recognitionError',
              'error': error.errorMsg.contains('permission')
                  ? 'not-allowed'
                  : 'no-speech',
            }),
          );
          if (!ready) {
            await _event({'type': 'recognitionError', 'error': 'not-allowed'});
            return;
          }
          await _recognizer.listen(
            onResult: (result) {
              if (result.finalResult) {
                _event({'type': 'recognition', 'text': result.recognizedWords});
              }
            },
            listenOptions: SpeechListenOptions(
              localeId: '${message['language'] ?? 'ru-RU'}',
              partialResults: false,
              cancelOnError: true,
            ),
          );
        case 'stopRecognition':
          await _recognizer.stop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось выполнить действие. Попробуйте ещё раз.'),
          ),
        );
      }
    }
  }

  Future<void> _back() async {
    final web = _web;
    if (web == null) {
      SystemNavigator.pop();
      return;
    }
    final handled = await web.runJavaScriptReturningResult(
      '''(()=>{const visible=id=>{const e=document.getElementById(id);return e&&!e.classList.contains('hidden')};if(visible('view-study-session')){document.getElementById('btn-exit-session')?.click();return true}if(visible('view-exam')){document.getElementById('btn-exit-exam')?.click();return true}if(visible('view-group-edit')){document.getElementById('btn-back-to-study')?.click();return true}return false})()''',
    );
    if (handled == true || handled == 'true') return;
    if (await web.canGoBack()) {
      await web.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      audio.speech.stop();
      _recognizer.stop();
      _web?.runJavaScript(
        'window.VoiceControl?.stop();window.StudyModule?.stopAudio();',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    audio.speech.stop();
    _recognizer.stop();
    _server.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : Stack(
                children: [if (_web != null) WebViewWidget(controller: _web!)],
              ),
      ),
    ),
  );
}
