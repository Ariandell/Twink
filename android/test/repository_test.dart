import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:twink_android/repository.dart';
import 'package:twink_android/domain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('progress applies acknowledged fields without GET; errors and stale reloads preserve data', () async {
    var gets = 0, reject = false;
    Completer<http.Response>? heldGet;
    const original =
        '{"nickname":"Test","words":{"1":{"word":"eins","translation":"one"},"2":{"word":"zwei"}}}';
    final store = TwinkStore(
      client: MockClient((r) async {
        if (r.url.host == 'identitytoolkit.googleapis.com') {
          return http.Response(
            '{"localId":"u","idToken":"token","refreshToken":"refresh","expiresIn":"3600"}',
            200,
          );
        }
        if (r.method == 'GET') {
          gets++;
          return heldGet == null
              ? http.Response(original, 200)
              : await heldGet.future;
        }
        expect(r.method, 'PATCH');
        return reject
            ? http.Response('{"error":"Permission denied"}', 403)
            : http.Response('{}', 200);
      }),
    );
    await store.login('test@example.com', 'password');
    final initialGets = gets, oldData = jsonEncode(store.data);
    final p = {'interval': 7, 'nextDate': 123};
    reject = true;
    await expectLater(store.progress('words', '1', p), throwsException);
    expect(jsonEncode(store.data), oldData);
    reject = false;
    await store.progress('words', '1', p);
    expect(
      gets,
      initialGets,
      reason: 'A rating must not download the full dictionary again.',
    );
    expect(store.words.first['progress_global'], p);
    expect(store.words.first['word'], 'eins');
    expect(store.words.first['translation'], 'one');
    expect(store.words.last['word'], 'zwei');
    heldGet = Completer<http.Response>();
    final loading = store.reload();
    await Future<void>.delayed(Duration.zero);
    var notifications = 0, readCompleted = false;
    store.addListener(() => notifications++);
    final release = store.holdVisualUpdates();
    final updated = {'interval': 12, 'nextDate': 456};
    await store.progress('words', '1', updated);
    expect(notifications, 0);
    loading.then((_) => readCompleted = true);
    heldGet.complete(http.Response(original, 200));
    await Future<void>.delayed(Duration.zero);
    expect(
      readCompleted,
      false,
      reason: 'A full dictionary response waits until motion has finished.',
    );
    release();
    await loading;
    expect(notifications, 1);
    expect(
      store.words.first['progress_global'],
      updated,
      reason: 'An older read must not erase an acknowledged rating.',
    );
    await store.progress('words', '1', null);
    expect(store.words.first['progress_global'], isNull);
    expect(store.words.first['interval'], 0);
    expect(store.words.first['word'], 'eins');
    store.dispose();
  });
  test(
    'time preserves both original daily statistics representations',
    () async {
      for (final value in <dynamic>[
        100,
        {'seconds': 100, 'source': 'legacy'},
      ]) {
        final store = TwinkStore()..startDemo();
        store.data!['stats'] = {
          'daily': {logicalDay(): value},
        };
        await store.addTime(12);
        final result = asMap(
          asMap(store.data!['stats'])['daily'],
        )[logicalDay()];
        if (value is Map) {
          expect(result, {'seconds': 112, 'source': 'legacy'});
        } else {
          expect(result, 112);
        }
        store.dispose();
      }
    },
  );
  test(
    'refreshes saved session, scopes writes and uses atomic time increments',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'twink-session': jsonEncode({
          'uid': 'test-user',
          'email': 'test@example.com',
          'refreshToken': 'saved-token',
        }),
      });
      final patches = <Json>[], requests = <String>[];
      final store = TwinkStore(
        client: MockClient((r) async {
          requests.add(r.url.host);
          if (r.url.host == 'securetoken.googleapis.com') {
            expect(r.body, contains('refresh_token=saved-token'));
            return http.Response(
              jsonEncode({
                'id_token': 'test-id-token',
                'refresh_token': 'new-refresh',
                'expires_in': '3600',
              }),
              200,
            );
          }
          expect(r.url.path, startsWith('/users/test-user'));
          expect(r.url.queryParameters['auth'], 'test-id-token');
          if (r.method == 'PATCH') {
            patches.add(asMap(jsonDecode(r.body)));
            return http.Response('{}', 200);
          }
          return http.Response(
            '{"nickname":"Test","words":{"1":{"word":"alt"}}}',
            200,
          );
        }),
      );
      await store.initialize();
      expect(store.signedIn, true);
      expect(store.words.single['word'], 'alt');
      await store.progress('words', '1', {
        'interval': 7,
        'nextDate': 123,
        'excellentStreak': 3,
      });
      expect(patches.last['words/1/nextDate'], 123);
      expect(patches.last['words/1/interval'], 7);
      await store.addTime(10);
      expect(patches.last['stats/daily/${logicalDay()}'], {
        '.sv': {'increment': 10},
      });
      expect(
        requests.where((s) => s == 'securetoken.googleapis.com').length,
        1,
      );
      await store.logout();
      expect(store.signedIn, false);
      store.dispose();
    },
  );
  test(
    'new numeric IDs retry conditional write without losing a concurrent edit',
    () async {
      var gets = 0, puts = 0;
      Json? sent;
      final store = TwinkStore(
        client: MockClient((r) async {
          if (r.url.host == 'identitytoolkit.googleapis.com') {
            return http.Response(
              '{"localId":"u","idToken":"token","refreshToken":"refresh","expiresIn":"3600"}',
              200,
            );
          }
          if (r.method == 'GET' && r.url.path.endsWith('/words.json')) {
            gets++;
            return http.Response(
              gets == 1 ? '{"1":{"word":"one"}}' : '{"1":{"word":"one","translation":"concurrent"},"2":{"word":"two"}}',
              200,
              headers: {'etag': 'v$gets'},
            );
          }
          if (r.method == 'PUT') {
            puts++;
            if (puts == 1) return http.Response('{"error":"conflict"}', 412);
            expect(r.headers['if-match'], 'v2');
            sent = asMap(jsonDecode(r.body));
            return http.Response.bytes(
              utf8.encode(r.body),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{}', 200);
        }),
      );
      await store.login('test@example.com', 'password');
      final id = await store.save('words', {
        'word': 'neu',
        'translation': 'новий',
      });
      expect(id, '3');
      expect(puts, 2);
      expect(asMap(sent!['1'])['translation'], 'concurrent');
      expect(asMap(asMap(sent!['3'])['progress_global'])['excellentStreak'], 0);
      store.dispose();
    },
  );
}
