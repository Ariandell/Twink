import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Official API: https://www.dwds.de/d/api#frequency. Never substitutes another
/// dictionary's frequency field or merges unrelated senses/lemmas.
class DwdsFrequencyRepository {
  static String query(String title) {
    final head = title
        .split(',')
        .first
        .trim()
        .replaceFirst(RegExp(r'^(der|die|das|sich)\s+'), '');
    return RegExp(r'^[\p{L}\p{M}ß-]+$', unicode: true).hasMatch(head)
        ? head
        : '';
  }

  static Future<Map<String, dynamic>>? _seed;
  static Future<Map<String, dynamic>> preload() => _seed ??= rootBundle
      .loadString('assets/data/dwds-frequency.json')
      .then((s) => Map<String, dynamic>.from(jsonDecode(s)))
      .catchError((_) => <String, dynamic>{});
  static final _pending = <String, Future<Map<String, dynamic>?>>{};
  static Future<Map<String, dynamic>?> load(
    String lemma, {
    required Map<String, dynamic> cache,
    bool allowNetwork = true,
    http.Client? client,
  }) async {
    if (lemma.isEmpty) return null;
    final cached = cache[lemma];
    if (cached is Map && valid(cached)) {
      return Map<String, dynamic>.from(cached);
    }
    final seed = await preload();
    if (seed[lemma] is Map && valid(seed[lemma])) {
      return Map<String, dynamic>.from(seed[lemma]);
    }
    if (!allowNetwork) return null;
    return _pending.putIfAbsent(lemma, () async {
      final api = client ?? http.Client();
      try {
        final uri = Uri.https('www.dwds.de', '/api/frequency/', {'q': lemma});
        final response = await api.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) return null;
        final record = <String, dynamic>{
          'data': jsonDecode(response.body),
          'source': uri.toString(),
          'fetchedAt': DateTime.now().millisecondsSinceEpoch,
        };
        return valid(record) ? record : null;
      } catch (_) {
        return null;
      } finally {
        if (client == null) api.close();
        _pending.remove(lemma);
      }
    });
  }

  static bool valid(dynamic record) {
    if (record is! Map || record['data'] is! Map) return false;
    final d = record['data'] as Map, frequency = d['frequency'];
    return frequency is int &&
        frequency >= 0 &&
        frequency <= 6 &&
        (num.tryParse('${d['hits']}') ?? 0) >= 5 &&
        (num.tryParse('${d['total']}') ?? 0) > 0;
  }
}
