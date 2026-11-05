import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twink_android/domain.dart';
import 'package:twink_android/spreadsheet.dart';

void main() {
  test('imports real ExcelJS workbooks with Unicode from the React app', () {
    for (final kind in ['words', 'idioms']) {
      final rows = decodeSpreadsheet(
        File('../templates/Twink_$kind.xlsx').readAsBytesSync(),
      );
      final imported = importRows(rows, kind, {}),
          expected = records(sampleData()[kind]);
      expect(imported['created'], expected.length);
      expect(
        wordTitle(records(imported['updates']).first),
        wordTitle(expected.first),
      );
      expect(
        records(imported['updates']).first['translation'],
        expected.first['translation'],
      );
    }
  });
  test('Android Excel export retains text, IDs and score columns', () {
    final words = records(sampleData()['words']),
        rows = decodeSpreadsheet(encodeSpreadsheet(words, 'words'));
    expect(rows[0], wordHeaders);
    expect(rows[1][0], '1');
    expect(rows[1][3], 'мить');
    expect(rows[3][1], 9);
  });
  test('wrong collection header is rejected before writing', () {
    expect(
      () => importRows(
        [
          idiomHeaders,
          ['100000', 'ABC', 'x'],
        ],
        'words',
        {},
      ),
      throwsFormatException,
    );
  });
}
