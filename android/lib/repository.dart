import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'domain.dart';

// Official Firebase Auth / Realtime Database REST APIs; no privileged credentials.
// This uses the existing web project without requiring a new Android Firebase app registration.
const firebaseKey = String.fromEnvironment(
  'FIREBASE_API_KEY',
  defaultValue: 'AIzaSyC5L2JlRmCrlq0Zyj1CIwbtd18eHHwkL3g',
);
const databaseUrl = String.fromEnvironment(
  'FIREBASE_DATABASE_URL',
  defaultValue: 'https://german-df0f0-default-rtdb.firebaseio.com',
);
String errorText(Object e) {
  final s = e
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('FormatException: ', '');
  for (final entry in {
    'INVALID_LOGIN_CREDENTIALS': 'Перевірте email і пароль.',
    'EMAIL_EXISTS': 'Цей email уже зареєстровано.',
    'WEAK_PASSWORD': 'Пароль має містити щонайменше 6 символів.',
    'INVALID_EMAIL': 'Перевірте адресу email.',
    'Permission denied': 'Немає дозволу на доступ до даних.',
    'SocketException': 'Немає зв’язку. Спробуйте ще раз.',
    'TimeoutException': 'Сервер не відповідає. Спробуйте ще раз.',
  }.entries) {
    if (s.contains(entry.key)) return entry.value;
  }
  return s;
}

class TwinkStore extends ChangeNotifier {
  TwinkStore({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _storage = const FlutterSecureStorage();
  String? uid, email, _token, _refresh;
  DateTime _expiry = DateTime(2000);
  Future<void>? _refreshing;
  Timer? _poll;
  bool loading = true, demo = false, _fetching = false;
  String? syncError;
  Json? data;
  bool get signedIn => uid != null || demo;
  Json get settings => asMap(asMap(data?['settings'])['study']);
  List<Json> get words => records(data?['words']);
  List<Json> get idioms => records(data?['idioms']);
  Future<Json> _auth(String action, Json body) async {
    final response = await _client
        .post(
          Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:$action?key=$firebaseKey',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Json _decode(http.Response response) {
    final value = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(
        value is Map
            ? (value['error'] is Map
                  ? value['error']['message']
                  : value['error'])
            : 'Помилка ${response.statusCode}',
      );
    }
    return asMap(value);
  }

  Future<void> initialize() async {
    try {
      final saved = await _storage.read(key: 'twink-session');
      if (saved != null) {
        final s = asMap(jsonDecode(saved));
        uid = s['uid'];
        email = s['email'];
        _refresh = s['refreshToken'];
        try {
          await _ensureToken();
          await reload();
          _startPolling();
        } catch (e) {
          syncError = errorText(e);
        }
      }
    } catch (e) {
      syncError = errorText(e);
    } finally {
      if (uid != null) _startPolling();
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _persist() => _storage.write(
    key: 'twink-session',
    value: jsonEncode({'uid': uid, 'email': email, 'refreshToken': _refresh}),
  );
  Future<void> login(String mail, String password, {String? nickname}) async {
    final s = await _auth(nickname == null ? 'signInWithPassword' : 'signUp', {
      'email': mail,
      'password': password,
      'returnSecureToken': true,
    });
    uid = s['localId'];
    email = mail;
    _token = s['idToken'];
    _refresh = s['refreshToken'];
    _expiry = DateTime.now().add(
      Duration(seconds: int.tryParse('${s['expiresIn']}') ?? 3600),
    );
    demo = false;
    data = null;
    await _persist();
    if (nickname != null) await patch({'nickname': nickname});
    await reload();
    _startPolling();
    notifyListeners();
  }

  Future<void> _ensureToken() async {
    if (_token != null &&
        DateTime.now().isBefore(_expiry.subtract(const Duration(minutes: 2)))) {
      return;
    }
    if (_refreshing != null) return _refreshing!;
    final future = _refreshToken();
    _refreshing = future;
    try {
      await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _refreshToken() async {
    if (_refresh == null) throw Exception('Увійдіть у свій акаунт');
    final sessionUid = uid;
    final response = await _client
        .post(
          Uri.parse(
            'https://securetoken.googleapis.com/v1/token?key=$firebaseKey',
          ),
          body: {'grant_type': 'refresh_token', 'refresh_token': _refresh!},
        )
        .timeout(const Duration(seconds: 20));
    final s = _decode(response);
    if (uid != sessionUid) throw Exception('Сесію завершено');
    _token = s['id_token'];
    _refresh = s['refresh_token'];
    _expiry = DateTime.now().add(
      Duration(seconds: int.tryParse('${s['expires_in']}') ?? 3600),
    );
    await _persist();
  }

  Future<Uri> _uri([String path = '']) async {
    final id = uid;
    await _ensureToken();
    if (id == null || uid != id) throw Exception('Сесію завершено');
    return Uri.parse(
      '$databaseUrl/users/$id${path.isEmpty ? '' : '/$path'}.json',
    ).replace(queryParameters: {'auth': _token!});
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => reload());
  }

  Future<void> reload() async {
    if (demo || uid == null || _fetching) return;
    final id = uid;
    _fetching = true;
    try {
      final response = await _client
          .get(await _uri())
          .timeout(const Duration(seconds: 20));
      final next = _decode(response);
      if (uid == id && !demo) {
        data = next;
        syncError = null;
        notifyListeners();
      }
    } catch (e) {
      if (uid == id) {
        syncError = errorText(e);
        notifyListeners();
      }
    } finally {
      _fetching = false;
    }
  }

  void startDemo() {
    _poll?.cancel();
    demo = true;
    data = sampleData();
    syncError = null;
    loading = false;
    notifyListeners();
  }

  Future<void> logout() async {
    _poll?.cancel();
    uid = null;
    email = null;
    _token = null;
    _refresh = null;
    demo = false;
    data = null;
    syncError = null;
    await _storage.delete(key: 'twink-session');
    notifyListeners();
  }

  Future<void> resetPassword(String mail) => _auth('sendOobCode', {
    'requestType': 'PASSWORD_RESET',
    'email': mail,
  }).then((_) {});
  Future<void> patch(Json changes) async {
    if (changes.isEmpty) return;
    if (demo) {
      final next = asMap(jsonDecode(jsonEncode(data ?? sampleData())));
      for (final entry in changes.entries) {
        final parts = entry.key.split('/');
        var cursor = next;
        for (final part in parts.take(parts.length - 1)) {
          cursor[part] = asMap(cursor[part]);
          cursor = cursor[part];
        }
        if (entry.value == null) {
          cursor.remove(parts.last);
        } else {
          cursor[parts.last] = entry.value;
        }
      }
      data = next;
      notifyListeners();
      return;
    }
    final response = await _client
        .patch(
          await _uri(),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(changes),
        )
        .timeout(const Duration(seconds: 25));
    _decode(response);
    await reload();
  }

  Future<String> save(String kind, Json record) async {
    if (record['id'] != null) {
      final changes = <String, dynamic>{};
      record.forEach((k, v) {
        if (k != 'id') changes['$kind/${record['id']}/$k'] = v;
      });
      await patch(changes);
      return '${record['id']}';
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      final uri = demo ? null : await _uri(kind);
      final response = uri == null
          ? null
          : await _client
                .get(uri, headers: {'X-Firebase-ETag': 'true'})
                .timeout(const Duration(seconds: 20));
      final raw = demo ? asMap(data?[kind]) : _decode(response!);
      final next = asMap(raw);
      var maxId = kind == 'idioms' ? 99999 : 0;
      for (final k in next.keys) {
        final n = int.tryParse(k);
        if (n != null && n > maxId) maxId = n;
      }
      final id = '${maxId + 1}';
      if (kind == 'words' && maxId + 1 >= 100000) {
        throw Exception('Досягнуто ліміт ID слів старого формату');
      }
      next[id] = {
        ...record,
        'folder': '${record['folder'] ?? ''}'.isEmpty
            ? autoFolder(records(raw))
            : record['folder'],
        'id': id,
        'progress_global': freshProgress(),
        if (kind == 'words') ...{
          'progress_groups': freshProgress(),
          'interval': 0,
          'nextDate': DateTime.now().millisecondsSinceEpoch,
        },
      };
      if (demo) {
        await patch({kind: next});
        return id;
      }
      final saved = await _client
          .put(
            uri!,
            headers: {
              'Content-Type': 'application/json',
              'if-match': response!.headers['etag']!,
            },
            body: jsonEncode(next),
          )
          .timeout(const Duration(seconds: 25));
      if (saved.statusCode == 412) continue;
      _decode(saved);
      await reload();
      return id;
    }
    throw Exception('Словник одночасно змінюється. Спробуйте ще раз.');
  }

  Future<void> progress(String kind, String id, Json? p) => patch({
    '$kind/$id/progress_global': p,
    if (kind == 'words') ...{
      'words/$id/interval': p?['interval'] ?? 0,
      'words/$id/nextDate': p?['nextDate'] ?? 0,
    },
  });
  Future<void> importRecords(String kind, List<List<dynamic>> rows) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final uri = demo ? null : await _uri(kind);
      final response = uri == null
          ? null
          : await _client
                .get(uri, headers: {'X-Firebase-ETag': 'true'})
                .timeout(const Duration(seconds: 20));
      final existing = demo ? asMap(data?[kind]) : _decode(response!);
      final next = {
        ...existing,
        ...asMap(importRows(rows, kind, existing)['updates']),
      };
      if (demo) {
        await patch({kind: next});
        return;
      }
      final saved = await _client
          .put(
            uri!,
            headers: {
              'Content-Type': 'application/json',
              'if-match': response!.headers['etag']!,
            },
            body: jsonEncode(next),
          )
          .timeout(const Duration(seconds: 25));
      if (saved.statusCode == 412) continue;
      _decode(saved);
      await reload();
      return;
    }
    throw Exception('Словник одночасно змінюється. Спробуйте ще раз.');
  }

  Future<void> addTime(int seconds) async {
    final key = logicalDay();
    if (demo) {
      await patch({
        'stats/daily/$key':
            number(asMap(asMap(data?['stats'])['daily'])[key]) + seconds,
      });
      return;
    }
    await patch({
      'stats/daily/$key': {
        '.sv': {'increment': seconds},
      },
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _client.close();
    super.dispose();
  }
}
