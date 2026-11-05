import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android bundles the exact original styles and application logic', () {
    final baseline = jsonDecode(
      File('../contracts/original-manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final entry in (baseline['files'] as Map<String, dynamic>).entries) {
      final file = File('assets/classic/${entry.key}');
      expect(file.existsSync(), true, reason: entry.key);
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        entry.value,
        reason: entry.key,
      );
    }
  });
  test(
    'Android entry keeps the original card, dictionary, profile and settings',
    () {
      final html = File('assets/classic/index.html').readAsStringSync();
      for (final id in [
        'flashcard',
        'view-words',
        'view-profile',
        'view-settings',
        'rating-buttons',
        'card-translation',
      ]) {
        expect(html, contains('id="$id"'));
      }
      expect(html, contains('vendor/twink-bridge.js'));
    },
  );
}
