import { readFile, writeFile, mkdir, rename, open, unlink } from "node:fs/promises";
import { dirname, extname } from "node:path";
import ExcelJS from "exceljs";

export async function readJson(path, fallback) {
  try { return JSON.parse(await readFile(path, "utf8")); }
  catch (error) { if (error.code === "ENOENT" && fallback !== undefined) return fallback; throw error; }
}

export async function atomicJson(path, value) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.${process.pid}.tmp`;
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  await rename(temporary, path);
}

const columns = {
  id: "id", "немецкое слово": "word", "німецьке слово": "word", word: "word", german: "word",
  "перевод": "translation", "переклад": "translation", translation: "translation",
  "пример 1": "ex1", "приклад 1": "ex1", ex1: "ex1", "пример 2": "ex2", "приклад 2": "ex2", ex2: "ex2",
  "формы глагола": "info1", info1: "info1", "идиома": "idiom", "ідіома": "idiom", idiom: "idiom",
  "пример": "example", example: "example", "смысловой перевод": "meaning", meaning: "meaning",
};
function text(value) {
  if (value && typeof value === "object") return value.text ?? value.result ?? value.richText?.map((part) => part.text).join("") ?? "";
  return value ?? "";
}
export async function readWords(path) {
  if (extname(path).toLowerCase() === ".xlsx") {
    const book = new ExcelJS.Workbook();
    await book.xlsx.readFile(path);
    const rows = [];
    for (const sheet of book.worksheets) {
      const headers = sheet.getRow(1).values.map((v) => columns[String(text(v)).trim().toLowerCase()]);
      if (!headers.includes("word") && !headers.includes("idiom")) continue;
      sheet.eachRow((row, index) => {
        if (index === 1) return;
        const word = {};
        row.eachCell((cell, col) => { if (headers[col]) word[headers[col]] = text(cell.value); });
        if (word.word || word.idiom) rows.push(word);
      });
    }
    if (!rows.length) throw new Error("XLSX не містить слів. Очікується експорт словника Twink із заголовками.");
    return rows;
  }
  const source = await readJson(path);
  const collection = source.words ?? source;
  const rows = Array.isArray(collection) ? collection : Object.entries(collection).map(([id, word]) => ({ ...word, id }));
  const words = rows.filter((word) => word && typeof word === "object" && (word.word || word.idiom));
  if (!words.length) throw new Error("JSON не містить словника. Потрібен масив слів або об’єкт words з експорту Twink.");
  return words;
}

export async function acquireLock(path) {
  await mkdir(dirname(path), { recursive: true });
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const file = await open(path, "wx", 0o600);
      await file.writeFile(JSON.stringify({ pid: process.pid }));
      return async () => { await file.close(); await unlink(path); };
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      const existing = await readJson(path);
      let alive = true;
      try { process.kill(existing.pid, 0); } catch (e) { if (e.code === "ESRCH") alive = false; }
      if (alive) throw new Error("Інший пошук уже працює з цим ключем. Дочекайтеся завершення.");
      await unlink(path);
    }
  }
  throw new Error("Не вдалося заблокувати стан пошуку.");
}
