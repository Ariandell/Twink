import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_api.dart';
import 'domain.dart';

final speech = TwinkSpeech();

class TwinkSpeech extends ChangeNotifier {
  TwinkSpeech({ElevenAudioClient? client})
    : client =
          client ??
          ElevenAudioClient(
            directory: () async => Directory(
              '${(await getTemporaryDirectory()).path}/twink-tts-v1',
            ),
          );
  final ElevenAudioClient client;
  AudioPlayer? _player;
  FlutterTts? _system;
  Completer<bool>? _completion;
  int _generation = 0;
  String status = 'ElevenLabs';
  void _status(String value) {
    status = value;
    notifyListeners();
  }

  Future<void> _stopPlayback() async {
    if (_completion != null && !_completion!.isCompleted) {
      _completion!.complete(false);
    }
    await _player?.stop();
    await _system?.stop();
  }

  Future<void> stop() async {
    _generation++;
    await _stopPlayback();
  }

  Future<void> say(
    String text, {
    String language = 'de',
    Json settings = const {},
  }) => speak([
    {'text': text, 'language': language},
  ], settings);
  Future<void> speak(List<Json> plan, Json settings) async {
    final ticket = ++_generation;
    await _stopPlayback();
    for (final item in plan) {
      if (ticket != _generation) return;
      final text = '${item['text'] ?? ''}',
          language = '${item['language'] ?? 'de'}';
      if (text.trim().isEmpty) continue;
      if (settings['audioProvider'] == 'system') {
        _status('Системний голос');
        if (!await _systemSpeak(text, language, ticket)) return;
        continue;
      }
      try {
        _status('Готуємо ElevenLabs…');
        final clip = await client.synthesize(
          text,
          language: language,
          voice: voiceFor(settings, language),
        );
        if (ticket != _generation) return;
        _status(clip.cached ? 'ElevenLabs · з кешу' : 'ElevenLabs');
        if (!await _play(clip.bytes)) return;
      } catch (e) {
        if (ticket != _generation) return;
        _status(
          e is SpeechFailure
              ? e.message
              : 'ElevenLabs недоступний. Працює системний голос.',
        );
        try {
          if (!await _systemSpeak(text, language, ticket)) return;
        } catch (_) {
          _status('Озвучення недоступне на цьому пристрої.');
          return;
        }
      }
    }
  }

  Future<bool> _play(Uint8List bytes) async {
    final player = _player ??= AudioPlayer(), done = Completer<bool>();
    _completion = done;
    final subscription = player.onPlayerComplete.listen(
      (_) {
        if (!done.isCompleted) done.complete(true);
      },
      onError: (_) {
        if (!done.isCompleted) done.complete(false);
      },
    );
    try {
      await player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
      return await done.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => false,
      );
    } finally {
      await subscription.cancel();
      if (identical(_completion, done)) _completion = null;
    }
  }

  Future<bool> _systemSpeak(String text, String language, int ticket) async {
    final tts = _system ??= FlutterTts(), done = Completer<bool>();
    _completion = done;
    tts.setCompletionHandler(() {
      if (!done.isCompleted) done.complete(true);
    });
    tts.setErrorHandler((_) {
      if (!done.isCompleted) done.complete(false);
    });
    await tts.setLanguage(
      {'de': 'de-DE', 'ru': 'ru-RU', 'uk': 'uk-UA'}[language] ?? language,
    );
    await tts.setSpeechRate(.45);
    if (ticket != _generation) return false;
    await tts.speak(text);
    try {
      return await done.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => false,
      );
    } finally {
      if (identical(_completion, done)) _completion = null;
    }
  }

  @override
  void dispose() {
    stop();
    _player?.dispose();
    client.dispose();
    super.dispose();
  }
}
