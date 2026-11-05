import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'domain.dart';

Uint8List encodeSpreadsheet(List<Json> list, String kind) {
  final book = Excel.createExcel(),
      sheetName = kind == 'words' ? 'Dictionary' : 'Idioms';
  final sheet = book[sheetName];
  book.delete('Sheet1');
  for (final row in toRows(list, kind)) {
    sheet.appendRow(
      row
          .map(
            (v) =>
                v is num ? DoubleCellValue(v.toDouble()) : TextCellValue('$v'),
          )
          .toList(),
    );
  }
  final bytes = book.encode();
  if (bytes == null) throw const FormatException('Не вдалося створити файл');
  return Uint8List.fromList(bytes);
}

List<List<dynamic>> decodeSpreadsheet(Uint8List bytes) {
  final book = Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) throw const FormatException('У файлі немає аркушів');
  return book.tables.values.first.rows
      .map(
        (row) => row.map((c) {
          final value = c?.value;
          if (value is IntCellValue) return value.value;
          if (value is DoubleCellValue) {
            return value.value == value.value.roundToDouble()
                ? value.value.toInt()
                : value.value;
          }
          return value?.toString() ?? '';
        }).toList(),
      )
      .toList();
}
