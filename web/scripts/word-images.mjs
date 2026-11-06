import { parseArgs } from "node:util";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { resolve, dirname, join } from "node:path";
import { homedir } from "node:os";
import { createHash } from "node:crypto";
import { atomicJson, readJson, readWords, acquireLock } from "./images/files.mjs";
import { emptyCatalog, validateCatalog, planWords, runBatch } from "./images/catalog.mjs";
import { reviewHtml } from "./images/review.mjs";

async function main() {
  const { values: args } = parseArgs({ options: {
    input: { type: "string" }, output: { type: "string" }, limit: { type: "string", default: "200" },
    "key-file": { type: "string" }, queries: { type: "string" }, "state-dir": { type: "string" },
    "dry-run": { type: "boolean" }, "retry-missing": { type: "boolean" }, "retry-errors": { type: "boolean" },
    help: { type: "boolean" },
  }});
  if (args.help || !args.input || !args.output) {
    console.log("Пошук картинок до слів Twink (Node.js 24)\n\nnode scripts/word-images.mjs --input words.xlsx --output PATH/catalog.json [--limit 200] [--key-file PATH/pexels.json]\n\n--dry-run        Підготувати план без API-запитів.\n--queries PATH  План/перевизначення запитів за ключами слів.\n--retry-missing Повторити слова без результатів (решту пропустити).\n\nКлюч: PEXELS_API_KEY у середовищі або приватний файл. Каталог і HTML-звіт не публікуються автоматично.");
    if (!args.help) process.exitCode = 2;
    return;
  }
  const output = resolve(args.output), input = resolve(args.input), limit = Number(args.limit);
  if (input === output) throw new Error("Вхідний словник і вихідний каталог мають бути різними файлами.");
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) throw new Error("--limit має бути цілим числом від 1 до 200.");
  const words = await readWords(input);
  const overridesFile = args.queries ? await readJson(resolve(args.queries)) : {};
  const overrides = overridesFile.queries ?? overridesFile;
  if (typeof overrides !== "object" || Array.isArray(overrides) || overrides === null) throw new Error("Некоректний файл пошукових запитів.");
  if (args["dry-run"]) {
    const catalog = validateCatalog(await readJson(output, emptyCatalog()));
    const plan = planWords(words, catalog, overrides);
    const path = `${output}.plan.json`;
    await atomicJson(path, {
      schemaVersion: 1,
      note: "Запити підібрано евристично. Для неоднозначних слів та ідіом уточніть значення. Це план, не результати API.",
      queries: Object.fromEntries(plan.map((item) => [item.key, { query: item.query, locale: item.locale }])),
      words: plan.map((item) => ({ key: item.key, word: item.word.word ?? item.word.idiom, translation: item.word.translation ?? "", context: [item.word.ex1, item.word.ex2, item.word.example].filter(Boolean).join("\n"), existing: item.existing })),
    });
    console.log(JSON.stringify({ mode: "plan_only", words: words.length, unique: plan.length, apiRequests: 0, path }, null, 2));
    return;
  }
  let apiKey = process.env.PEXELS_API_KEY?.trim();
  if (args["key-file"]) {
    const raw = (await readFile(resolve(args["key-file"]), "utf8")).trim();
    try { apiKey = raw.startsWith("{") ? JSON.parse(raw).PEXELS_API_KEY : raw; }
    catch { throw new Error("Некоректний приватний файл ключа Pexels. Його вміст не виводиться."); }
  }
  if (!apiKey || typeof apiKey !== "string" || /[\r\n]/u.test(apiKey)) throw new Error("Потрібен ключ PEXELS_API_KEY або --key-file з {\"PEXELS_API_KEY\":\"…\"}. Ключ не виводиться у звіти.");
  apiKey = apiKey.trim();
  // Global per-key state prevents a second output file/process from resetting
  // the same account's hourly budget. Other API users can still exhaust it;
  // HTTP 429 and provider headers always take precedence.
  const state = join(args["state-dir"] ? resolve(args["state-dir"]) : join(homedir(), ".twink", "pexels"), createHash("sha256").update(apiKey).digest("hex").slice(0, 24));
  const keyUnlock = await acquireLock(join(state, "search.lock"));
  let outputUnlock;
  const controller = new AbortController();
  const stop = () => controller.abort();
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
  try {
    // Also serialize different keys writing the same catalog.
    outputUnlock = await acquireLock(`${output}.lock`);
    const catalog = validateCatalog(await readJson(output, emptyCatalog()));
    const ledger = await readJson(join(state, "quota.json"), { attempts: [] });
    const result = await runBatch({ words, catalog, ledger, apiKey, limit, overrides,
      retryMissing: args["retry-missing"], retryErrors: args["retry-errors"], signal: controller.signal,
      saveCatalog: (data) => atomicJson(output, data),
      saveLedger: (data) => atomicJson(join(state, "quota.json"), data),
      cacheGet: async (key) => {
        const cache = await readJson(join(state, "cache", `${key}.json`), null);
        return cache && Date.now() - cache.time < 86_400_000 ? cache.data : null;
      },
      cachePut: (key, data) => atomicJson(join(state, "cache", `${key}.json`), { time: Date.now(), data }),
      progress: (result) => { if ((result.matched + result.missing) % 20 === 0) console.log(`Запитів: ${result.requests}; знайдено: ${result.matched}; без результатів: ${result.missing}`); },
    });
    await mkdir(dirname(output), { recursive: true });
    await writeFile(`${output}.review.html`, reviewHtml(catalog), { mode: 0o600 });
    await atomicJson(`${output}.last-run.json`, { ...result, finishedAt: new Date().toISOString() });
    console.log(JSON.stringify({ ...result, catalog: output, review: `${output}.review.html` }, null, 2));
    if (["auth_error", "api_error", "network_error", "invalid_response"].includes(result.stop)) process.exitCode = 2;
    if (result.stop === "interrupted") process.exitCode = 130;
  } finally {
    process.off("SIGINT", stop);
    process.off("SIGTERM", stop);
    if (outputUnlock) await outputUnlock();
    await keyUnlock();
  }
}

main().catch((error) => {
  // Never print raw responses, request headers or the secret key.
  console.error(`Пошук не виконано: ${error.message}`);
  process.exitCode = 2;
});
