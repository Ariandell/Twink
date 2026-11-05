import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twink_android/domain.dart';

void main() {
  final f = asMap(
    jsonDecode(File('../contracts/parity.json').readAsStringSync()),
  );
  final now = f['now'] as int;
  group('Shared Android / React contract', () {
    for (final entry in (f['reviews'] as List).asMap().entries) {
      final c = asMap(entry.value);
      test('rating ${entry.key}', () {
        final p = review(
          asMap(c['previous']),
          c['rating'],
          mode: c['mode'],
          now: now,
        );
        expect(p['excellentStreak'], c['score']);
        expect(p['interval'], closeTo(c['days'], 1e-12));
        expect(p['nextDate'], now + (number(c['days']) * dayMs).round());
        expect(p['is_ideal'], c['ideal']);
        expect(p['isActive'], false);
      });
    }
    for (final entry in (f['answers'] as List).asMap().entries) {
      final c = asMap(entry.value);
      test('answer ${entry.key}: ${c['answer']}', () {
        final r = checkAnswer(asMap(c['word']), c['answer']);
        expect(r['correct'], c['correct']);
        for (final key in ['articleError', 'sequenceError', 'partial']) {
          if (c.containsKey(key)) expect(r[key], c[key]);
        }
      });
    }
    for (final entry in (f['eligibility'] as List).asMap().entries) {
      final c = asMap(entry.value);
      test(
        'queue ${entry.key}',
        () => expect(
          eligible(asMap(c['word']), exam: c['exam'], now: now),
          c['eligible'],
        ),
      );
    }
    test('exam activates at 10 and article error deducts 1.5', () {
      expect(review({'excellentStreak': 9}, 6)['excellentStreak'], 9);
      expect(
        examProgress({'excellentStreak': 9}, {'correct': true})['isActive'],
        true,
      );
      expect(
        examProgress(
          {'excellentStreak': 9},
          {'correct': false, 'articleError': true},
        )['excellentStreak'],
        7.5,
      );
    });
    test('imports preserve unknown fields and schedules', () {
      final old = {
        'id': '1',
        'word': 'alt',
        'translation': 'x',
        'extra': 'keep',
        'progress_global': {
          'excellentStreak': 9,
          'nextDate': 123,
          'interval': 7,
          'lastReviewed': 42,
        },
        'progress_groups': {'nextDate': 5},
      };
      final result = importRows(
        toRows([
          {...old, 'word': 'neu'},
        ], 'words'),
        'words',
        {'1': old},
        now: now,
      );
      final w = asMap(asMap(result['updates'])['1']);
      expect(w['progress_global'], old['progress_global']);
      expect(w['extra'], 'keep');
      expect(w['word'], 'neu');
      expect(w['progress_groups'], old['progress_groups']);
    });
    test('new imports start fresh and do not delete omitted rows', () {
      final r = importRows(
        [
          ['ID'],
          ['2', 10, 'neu', 'новий'],
        ],
        'words',
        {
          '1': {'word': 'old'},
        },
        now: now,
      );
      expect(
        asMap(
          asMap(asMap(r['updates'])['2'])['progress_global'],
        )['excellentStreak'],
        0,
      );
      expect(asMap(r['updates']).keys, ['2']);
    });
    test('rejects malformed imports', () {
      expect(
        () => importRows(
          [
            ['a/b', 0, 'x', 'y'],
          ],
          'words',
          {},
        ),
        throwsFormatException,
      );
      expect(
        () => importRows(
          [
            ['100000', 0, 'x', 'y'],
          ],
          'words',
          {},
        ),
        throwsFormatException,
      );
    });
    test('six-hour UTC date boundary', () {
      expect(
        logicalDay(
          DateTime.parse('2026-11-01T05:59:59Z').millisecondsSinceEpoch,
        ),
        '2026-10-31',
      );
      expect(
        logicalDay(
          DateTime.parse('2026-11-01T06:00:00Z').millisecondsSinceEpoch,
        ),
        '2026-11-01',
      );
    });
    test(
      'nouns differ from adverbs',
      () => expect(duplicateKey('der Morgen'), isNot(duplicateKey('morgen'))),
    );
    test(
      'sparse arrays are supported',
      () => expect(
        records([
          null,
          {'word': 'A'},
          null,
          {'word': 'B'},
        ]).map((w) => w['id']),
        ['1', '3'],
      ),
    );
  });
}
