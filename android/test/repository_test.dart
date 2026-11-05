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
