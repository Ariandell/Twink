import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'domain.dart';

List<List<String>> _decodeDwdsIndex(Uint8List bytes) =>
    (jsonDecode(utf8.decode(gzip.decode(bytes))) as List)
        .map((r) => (r as List).cast<String>())
        .toList();

Json parseDwdsArticle((String, String, String) input) {
  final document = html.parse(input.$1);
  String clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  final block = document.querySelector('.dwdswb-ft-block');
  final grammar = clean(
    block?.querySelector('.dwdswb-ft-blocktext')?.text ?? '',
  );
  var word = input.$2;
  final article = grammar.contains('Substantiv')
      ? grammar.contains('Neutrum')
            ? 'das'
            : grammar.contains('Femininum')
            ? 'die'
            : grammar.contains('Maskulinum')
            ? 'der'
            : null
      : null;
  if (article != null) {
    word = '$article $word';
    final plural = RegExp(r'Nominativ Plural:\s*([^·]+)')
        .firstMatch(grammar)
        ?.group(1)
        ?.trim();
    if (plural != null && plural.isNotEmpty) word += ', die $plural';
  }
  final definitions = document
      .querySelectorAll('.dwdswb-definition')
      .where((e) => clean(e.text).isNotEmpty)
      .take(12)
      .toList();
  final senses = definitions.map((e) => clean(e.text)).toList();
  final senseExamples = definitions.map((definition) {
    var parent = definition.parent;
    while (parent != null && !parent.classes.contains('dwdswb-lesart')) {
      parent = parent.parent;
    }
    return parent
            ?.querySelectorAll('.dwdswb-kompetenzbeispiel .dwdswb-belegtext')
            .map((e) => clean(e.text))
            .where((s) => s.isNotEmpty)
            .toSet()
            .take(2)
            .toList() ??
        <String>[];
  }).toList();
  final examples = document
      .querySelectorAll('.dwdswb-kompetenzbeispiel .dwdswb-belegtext')
      .map((e) => clean(e.text))
      .where((s) => s.isNotEmpty)
      .toSet()
      .take(2)
      .toList();
  return {
    'word': word,
    'grammar': grammar,
    'info1': clean(block?.querySelector('.dwdswb-flexionen')?.text ?? ''),
    'senses': senses,
    'senseExamples': senseExamples,
    'examples': examples,
    'source': input.$3,
  };
}

class DwdsDictionary {
  DwdsDictionary({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static final shared = DwdsDictionary();
  static Future<List<List<String>>>? _catalog;
  static List<List<String>>? _rows;
  static Map<String, Json>? cachedKnown;
  static bool get ready => _rows != null;
  static Future<Map<String, Json>>? _known;
  final _details = <String, Json>{};
  static String fold(String text) => text
      .toLowerCase()
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll('ß', 'ss')
      .replaceAll('ae', 'a')
      .replaceAll('oe', 'o')
      .replaceAll('ue', 'u');
  static String lemma(String text) => text
      .split(',')
      .first
      .trim()
      .replaceFirst(RegExp(r'^(der|die|das|sich)\s+'), '');
  static Future<List<List<String>>> preload() => _catalog ??= () async {
    final data = await rootBundle.load('assets/data/dwds-headwords.json.gz');
    final rows = await compute(
      _decodeDwdsIndex,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    _rows = rows;
    return rows;
  }();
  static Future<Map<String, Json>> known() => _known ??= () async {
    try {
      final list = jsonDecode(
        await rootBundle.loadString('assets/word-images/lexicon.json'),
      ) as List;
      return cachedKnown = {
        for (final row in list) lemma('${row['word']}'): asMap(row),
      };
    } catch (_) {
      return cachedKnown = <String, Json>{};
    }
  }();
  Future<List<Json>> suggest(String text, {int limit = 12}) async {
    await preload();
    return suggestCached(text, limit: limit);
  }

  List<Json> suggestCached(String text, {int limit = 12}) {
    final q = fold(lemma(text.trim()));
    if (q.length < 2) return [];
    final rows = _rows ?? const <List<String>>[];
    var low = 0, high = rows.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (rows[mid][0].compareTo(q) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final result = <Json>[];
    for (
      var i = low;
      i < rows.length && rows[i][0].startsWith(q) && result.length < limit;
      i++
    ) {
      result.add({
        'lemma': rows[i][1],
        'url': 'https://www.dwds.de${rows[i][2]}',
      });
    }
    return result;
  }

  Future<Json> detail(Json hit) async {
    final uri = Uri.parse('${hit['url']}');
    if (uri.scheme != 'https' ||
        uri.host != 'www.dwds.de' ||
        !uri.path.startsWith('/wb/')) {
      throw const FormatException('Некорректная ссылка DWDS');
    }
    final key = uri.toString();
    if (_details.containsKey(key)) return _details[key]!;
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const HttpException('DWDS недоступен. Попробуйте ещё раз.');
    }
    final parsed = await compute(parseDwdsArticle, (
      utf8.decode(response.bodyBytes),
      '${hit['lemma']}',
      key,
    ));
    if ((parsed['senses'] as List).isEmpty && '${parsed['grammar']}'.isEmpty) {
      throw const FormatException(
        'Статья DWDS не распознана. Можно открыть её на сайте.',
      );
    }
    if (_details.length >= 60) _details.remove(_details.keys.first);
    _details[key] = parsed;
    return parsed;
  }
}
