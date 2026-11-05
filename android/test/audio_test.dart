import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:twink_android/audio_api.dart';

http.Response mp3() => http.Response.bytes(
  [73, 68, 51, 1],
  200,
  headers: {'content-type': 'audio/mpeg'},
);
void main() {
  test('voice, language, model, duplicate requests and cache', () async {
    var calls = 0;
    final client = ElevenAudioClient(
      key: 'test-key',
      client: MockClient((r) async {
        calls++;
        expect(r.headers['xi-api-key'], 'test-key');
        expect(r.url.path, endsWith(defaultVoice));
        expect(jsonDecode(r.body), {
          'text': 'Hallo',
          'model_id': 'eleven_multilingual_v2',
          'language_code': 'de',
        });
        return mp3();
      }),
    );
    final clips = await Future.wait([
      client.synthesize('Hallo'),
      client.synthesize('Hallo'),
    ]);
    expect(clips.first.bytes.length, 4);
    expect(calls, 1);
    expect((await client.synthesize('Hallo')).cached, true);
    client.dispose();
  });
  test('persistent cache survives a new client', () async {
    final dir = await Directory.systemTemp.createTemp('twink-audio-test-');
    var calls = 0;
    ElevenAudioClient create() => ElevenAudioClient(
      key: 'test',
      directory: () async => dir,
      client: MockClient((_) async {
        calls++;
        return mp3();
      }),
    );
    final first = create();
    await first.synthesize('Hallo');
    first.dispose();
    final second = create();
    expect((await second.synthesize('Hallo')).cached, true);
    expect(calls, 1);
    second.dispose();
    await dir.delete(recursive: true);
  });
  test('library voice 402 falls back to the available voice', () async {
    final voices = <String>[];
    final client = ElevenAudioClient(
      key: 'test',
      client: MockClient((r) async {
        voices.add(r.url.path);
        return voices.length == 1
            ? http.Response('{"detail":{"status":"payment_required"}}', 402)
            : mp3();
      }),
    );
    expect(
      (await client.synthesize('Hallo', voice: 'old-library-voice')).voice,
      defaultVoice,
    );
    await client.synthesize('Guten Tag', voice: 'old-library-voice');
    expect(voices.length, 3);
    expect(voices.last, endsWith(defaultVoice));
    client.dispose();
  });
  test(
    'quota cooldown avoids retries and leaves cached audio usable',
    () async {
      var calls = 0;
      final client = ElevenAudioClient(
        key: 'test',
        client: MockClient(
          (_) async => ++calls == 1
              ? mp3()
              : http.Response('{"detail":{"status":"quota_exceeded"}}', 401),
        ),
      );
      await client.synthesize('cached');
      await expectLater(
        client.synthesize('new'),
        throwsA(
          isA<SpeechFailure>().having((e) => e.code, 'code', 'quota_exceeded'),
        ),
      );
      await expectLater(
        client.synthesize('other'),
        throwsA(
          isA<SpeechFailure>().having(
            (e) => e.code,
            'code',
            'temporarily_blocked',
          ),
        ),
      );
      expect((await client.synthesize('cached')).cached, true);
      expect(calls, 2);
      client.dispose();
    },
  );
  test('front and back preserve field toggles and languages', () {
    final w = {
      'word': 'entdecken',
      'translation': 'відкривати',
      'info1': 'entdeckte, hat entdeckt',
      'info2': 'Notiz',
      'ex1': 'Beispiel',
      'ex2': 'Інший приклад',
    };
    expect(speechPlan(w, {'audioInfo2': false}).map((p) => p['text']), [
      'entdecken',
      'entdeckte, hat entdeckt',
    ]);
    expect(
      speechPlan(w, {'audioEx1': true, 'audioEx2': true}).last['language'],
      'uk',
    );
    expect(speechPlan(w, {'audioTranslationLanguage': 'uk'}, 'back'), [
      {'text': 'відкривати', 'language': 'uk'},
    ]);
    expect(speechPlan(w, {'audioTranslation': false}, 'back'), isEmpty);
  });
}
