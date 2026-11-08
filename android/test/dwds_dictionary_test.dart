import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:twink_android/dwds_dictionary.dart';

import 'fixtures/dwds_article.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('complete DWDS index suggests real headwords offline and normalizes umlauts', () async {
    final index = await DwdsDictionary.preload();
    expect(index.length, greaterThan(280000));
    final service = DwdsDictionary();
    expect(
      (await service.suggest('Haus')).any((r) => r['lemma'] == 'Haus'),
      true,
    );
    expect(
      (await service.suggest('Hauser'))
          .any((r) => '${r['lemma']}'.startsWith('Häuser')),
      true,
    );
    expect(await service.suggest(''), isEmpty);
    expect((await service.suggest('Haus', limit: 3)).length, 3);
  });
  test('article parser preserves article, plural and examples per meaning', () {
    final result = parseDwdsArticle((
      article,
      'Haus',
      'https://www.dwds.de/wb/Haus',
    ));
    expect(result['word'], 'das Haus, die Häuser');
    expect(result['senses'], ['Gebäude zum Wohnen', 'Familie oder Haushalt']);
    expect(result['senseExamples'], [
      ['Das Haus steht am Fluss.'],
      ['Das ganze Haus feiert.'],
    ]);
  });
  test('details use DWDS only, cache successful results and allow retry after failure', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      if (requests == 1) return http.Response('temporarily unavailable', 503);
      return http.Response(
        article,
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
    final service = DwdsDictionary(client: client);
    final hit = {'lemma': 'Haus', 'url': 'https://www.dwds.de/wb/Haus'};
    await expectLater(service.detail(hit), throwsException);
    expect((await service.detail(hit))['word'], 'das Haus, die Häuser');
    await service.detail(hit);
    expect(requests, 2);
    await expectLater(
      service.detail({'lemma': 'Haus', 'url': 'https://example.org/wb/Haus'}),
      throwsFormatException,
    );
  });
}
