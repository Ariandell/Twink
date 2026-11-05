import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'domain.dart';
import 'elevenlabs_config.dart';

const defaultVoice = 'JBFqnCBsd6RMkjVDRZzb';
String speechLanguage(String text, [String preferred = 'ru']) =>
    RegExp(r'[а-яіїєґё]', caseSensitive: false).hasMatch(text)
    ? (RegExp(r'[іїєґ]', caseSensitive: false).hasMatch(text)
          ? 'uk'
          : preferred)
    : 'de';
String voiceFor(Json settings, String language) {
  final value =
      '${settings[language == 'de' ? 'selectAudioDe' : 'selectAudioRu'] ?? ''}';
  return value.startsWith('elevenlabs_') ? value.substring(11) : defaultVoice;
}

List<Json> speechPlan(Json w, Json settings, [String side = 'front']) {
  final plan = <Json>[],
      preferred = '${settings['audioTranslationLanguage'] ?? 'ru'}';
  void add(dynamic text, bool enabled, [String? language]) {
    if (text != null && '$text'.trim().isNotEmpty && enabled) {
      plan.add({
        'text': '$text',
        'language': language ?? speechLanguage('$text', preferred),
      });
    }
  }

  if (side == 'back') {
    add(w['translation'], settings['audioTranslation'] != false, preferred);
    add(w['meaning'], settings['audioInfo1'] != false);
  } else {
    add(w['word'] ?? w['idiom'], settings['audioWord'] != false, 'de');
    add(w['info1'], settings['audioInfo1'] != false);
    add(w['info2'] ?? w['info'], settings['audioInfo2'] != false);
    add(w['ex1'] ?? w['example'], settings['audioEx1'] == true);
    add(w['ex2'], settings['audioEx2'] == true);
  }
  return plan;
}

class SpeechFailure implements Exception {
  final String code, message;
  const SpeechFailure(this.code, this.message);
  @override
  String toString() => message;
}

class AudioClip {
  final Uint8List bytes;
  final bool cached;
  final String voice;
  const AudioClip(this.bytes, {this.cached = false, this.voice = defaultVoice});
}

class ElevenAudioClient {
  ElevenAudioClient({
    String? key,
    http.Client? client,
    this.directory,
    DateTime Function()? now,
  }) : _key = key ?? elevenLabsKey,
       _http = client ?? http.Client(),
       now = now ?? DateTime.now;
  final String _key;
  final http.Client _http;
  final Future<Directory> Function()? directory;
  final DateTime Function() now;
  final _memory = <String, Uint8List>{},
      _pending = <String, Future<AudioClip>>{},
      _unavailableVoices = <String>{};
  DateTime blockedUntil = DateTime(2000);
  Future<AudioClip> synthesize(
    String text, {
    String language = 'de',
    String voice = defaultVoice,
  }) async {
    text = text.trim();
    if (text.isEmpty || text.length > 2000) {
      throw const SpeechFailure(
        'invalid_text',
        'Цей фрагмент завеликий або порожній.',
      );
    }
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode(['eleven_multilingual_v2', voice, language, text]),
          ),
        )
        .toString();
    if (_memory.containsKey(key)) {
      return AudioClip(_memory[key]!, cached: true, voice: voice);
    }
    if (_pending.containsKey(key)) return _pending[key]!;
    final work = _generate(text, language, voice, key);
    _pending[key] = work;
    try {
      return await work;
    } finally {
      _pending.remove(key);
    }
  }

  void _remember(String key, Uint8List bytes) {
    _memory[key] = bytes;
    if (_memory.length > 64) _memory.remove(_memory.keys.first);
  }

  Future<AudioClip> _generate(
    String text,
    String language,
    String voice,
    String key,
  ) async {
    File? file;
    if (directory != null) {
      try {
        final dir = await directory!();
        await dir.create(recursive: true);
        file = File('${dir.path}/$key.mp3');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            _remember(key, bytes);
            return AudioClip(bytes, cached: true, voice: voice);
          }
        }
      } catch (_) {
        file = null;
      }
    }
    if (blockedUntil.isAfter(now())) {
      throw const SpeechFailure(
        'temporarily_blocked',
        'ElevenLabs тимчасово недоступний. Працює системний голос.',
      );
    }
    var actual = _unavailableVoices.contains(voice) ? defaultVoice : voice;
    var response = await _request(text, language, actual);
    if (response.statusCode == 402 && actual != defaultVoice) {
      _unavailableVoices.add(actual);
      actual = defaultVoice;
      response = await _request(text, language, actual);
    }
    if (response.statusCode >= 400) {
      Json body = {};
      try {
        body = asMap(jsonDecode(response.body));
      } catch (_) {}
      final code =
          '${asMap(body['detail'])['status'] ?? 'http_${response.statusCode}'}';
      final quota = code.contains('quota') || code.contains('limit');
      if (quota) {
        blockedUntil = now().add(const Duration(minutes: 10));
      } else if (response.statusCode == 429) {
        blockedUntil = now().add(const Duration(seconds: 30));
      } else if ([401, 402, 403].contains(response.statusCode)) {
        blockedUntil = now().add(const Duration(minutes: 1));
      }
      throw SpeechFailure(
        code,
        quota
            ? 'Ліміт ElevenLabs вичерпано. Працює системний голос.'
            : 'ElevenLabs недоступний. Працює системний голос.',
      );
    }
    if (response.bodyBytes.isEmpty ||
        !(response.headers['content-type'] ?? '').startsWith('audio/')) {
      throw const SpeechFailure(
        'invalid_audio',
        'ElevenLabs повернув некоректне аудіо.',
      );
    }
    final bytes = response.bodyBytes;
    _remember(key, bytes);
    if (file != null) {
      try {
        await file.writeAsBytes(bytes, flush: true);
        final files = await file.parent
            .list()
            .where((f) => f is File && f.path.endsWith('.mp3'))
            .cast<File>()
            .toList();
        if (files.length > 128) {
          final dated = await Future.wait(
            files.map((f) async => MapEntry(f, (await f.stat()).modified)),
          );
          dated.sort((a, b) => a.value.compareTo(b.value));
          for (final entry in dated.take(dated.length - 128)) {
            await entry.key.delete();
          }
        }
      } catch (_) {}
    }
    return AudioClip(bytes, voice: actual);
  }

  Future<http.Response> _request(
    String text,
    String language,
    String voice,
  ) => _http
      .post(
        Uri.parse(
          'https://api.elevenlabs.io/v1/text-to-speech/${Uri.encodeComponent(voice)}?output_format=mp3_44100_128',
        ),
        headers: {
          'xi-api-key': _key,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: jsonEncode({
          'text': text,
          'model_id': 'eleven_multilingual_v2',
          'language_code': language,
        }),
      )
      .timeout(const Duration(seconds: 25));
  Future<Json> quota() async {
    if (_key.isEmpty) {
      throw const SpeechFailure('missing_key', 'Ключ ElevenLabs не настроен.');
    }
    final response = await _http
        .get(
          Uri.parse('https://api.elevenlabs.io/v1/user/subscription'),
          headers: {'xi-api-key': _key},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const SpeechFailure(
        'quota_unavailable',
        'Ліміт недоступний для перегляду цим ключем.',
      );
    }
    final data = asMap(jsonDecode(response.body));
    blockedUntil = DateTime(2000);
    return {'used': data['character_count'], 'limit': data['character_limit']};
  }

  void dispose() => _http.close();
}
