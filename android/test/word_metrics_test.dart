import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:twink_android/word_metrics.dart';
import 'package:twink_android/domain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('DWDS lookup retains noun case, removes forms and rejects phrases', () {
    expect(DwdsFrequencyRepository.query('die Bank, die Banken'), 'Bank');
    expect(DwdsFrequencyRepository.query('sich erinnern'), 'erinnern');
    expect(DwdsFrequencyRepository.query('in der Nähe'), '');
  });
  test(
    'zero frequency is a measured lowest class; missing data is unknown',
    () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'www.dwds.de');
        expect(request.url.queryParameters['q'], 'Testlemma');
        return http.Response(
          jsonEncode({'frequency': 0, 'hits': 5, 'total': '50000000000'}),
          200,
        );
      });
      final result = await DwdsFrequencyRepository.load(
        'Testlemma',
        cache: {},
        client: client,
      );
      expect(result!['data']['frequency'], 0);
      expect(
        DwdsFrequencyRepository.valid({
          'data': {'frequency': 0, 'hits': 0, 'total': 50},
        }),
        false,
      );
      expect(
        await DwdsFrequencyRepository.load(
          'Unbekannt',
          cache: {},
          allowNetwork: false,
        ),
        isNull,
      );
    },
  );
  test(
    'word rating history is bounded and previous progress can restore it',
    () {
      var p = <String, dynamic>{};
      for (final rating in [1, 2, 3, 4, 5, 6, 1, 2, 3, 4]) {
        p = review(p, rating);
      }
      expect(p['recentRatings'], [3, 4, 5, 6, 1, 2, 3, 4]);
      final previous = Map<String, dynamic>.from(p);
      final next = examProgress(p, {'correct': true});
      expect((next['recentRatings'] as List).last, 6);
      expect(previous['recentRatings'], [3, 4, 5, 6, 1, 2, 3, 4]);
    },
  );
}
