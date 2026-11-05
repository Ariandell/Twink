import { it, expect } from "vitest";
import ExcelJS from "exceljs";
import { entries, sampleData, toRows, importRows } from "./domain";
it("writes and reopens a real XLSX with IDs, Unicode and verb forms", async () => {
  const original = entries(sampleData().words),
    book = new ExcelJS.Workbook(),
    sheet = book.addWorksheet("Dictionary");
  toRows(original, "words").forEach((r) => sheet.addRow(r));
  const read = new ExcelJS.Workbook();
  await read.xlsx.load(await book.xlsx.writeBuffer());
  const rows = [];
  read.worksheets[0].eachRow((r) => rows.push(r.values.slice(1)));
  const result = importRows(rows, "words");
  expect(result.created).toBe(4);
  expect(result.updates["1"].translation).toBe("мить");
  expect(result.updates["2"].info1).toBe("entdeckte, hat entdeckt");
});
