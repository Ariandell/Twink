import { describe, it, expect, afterEach } from "vitest";
import { mkdtemp, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import ExcelJS from "exceljs";
import { imageKey, searchFor, planWords, emptyCatalog, photoRecord, runBatch } from "../scripts/images/catalog.mjs";
import { readWords, atomicJson, readJson, acquireLock } from "../scripts/images/files.mjs";
import { reviewHtml } from "../scripts/images/review.mjs";

const time = Date.UTC(2026, 10, 6, 12);
const photo = {
  id: 42, url: "https://www.pexels.com/photo/apple-42/", photographer: "Example photographer",
  photographer_url: "https://www.pexels.com/@example/", alt: "An apple", width: 1200, height: 800,
  src: { medium: "https://images.pexels.com/photos/42/medium.jpeg", tiny: "https://images.pexels.com/photos/42/tiny.jpeg" },
};
const apple = { id: "1", word: "der Apfel", translation: "яблуко", ex1: "Ich esse einen Apfel." };
function harness(extra = {}) {
  const cache = new Map(), writes = [], calls = [];
  const args = {
    words: [apple], catalog: emptyCatalog(), ledger: { attempts: [] }, apiKey: "private-test-key", now: () => time,
    fetchImpl: async (url) => { calls.push(url); return Response.json({ photos: [photo] }); },
    saveCatalog: async (data) => { writes.push(structuredClone(data)); }, saveLedger: async () => {},
    cacheGet: async (key) => cache.get(key), cachePut: async (key, value) => { cache.set(key, value); },
    ...extra,
  };
  return { args, cache, writes, calls, run: () => runBatch(args) };
}

describe("word image bindings", () => {
  it("keeps stable keys across IDs while separating meanings", () => {
    expect(imageKey(apple)).toBe(imageKey({ ...apple, id: "999", word: " DER   APFEL ", translation: " ЯБЛУКО " }));
    expect(imageKey(apple)).not.toBe(imageKey({ ...apple, translation: "яблоня" }));
    expect(imageKey(apple)).toHaveLength(64);
  });
  it("deduplicates words and allows exact per-meaning query overrides", () => {
    const override = { [imageKey(apple)]: { query: "red apple fruit", locale: "en-US" } };
    const plan = planWords([apple, { ...apple, id: "2" }], emptyCatalog(), override);
    expect(plan).toHaveLength(1);
    expect(plan[0].query).toBe("red apple fruit");
    expect(plan[0].locale).toBe("en-US");
  });
  it("uses context nouns to distinguish a bench from a bank", () => {
    expect(searchFor({ word: "die Bank, die Bänke", ex1: "Ich sitze auf der Bank im Park." }).query).toBe("Bank Park");
    expect(searchFor({ word: "der Hügel", ex1: "Auf dem Hügel steht ein Haus." }).query).toBe("Hügel Haus");
    expect(searchFor({ word: "der Augenblick", ex1: "Genieße den Augenblick." }).query).toBe("Augenblick");
    expect(() => searchFor(apple, { query: "", locale: "en-US" })).toThrow("Порожній");
  });
  it("requires provider HTTPS URLs and retains attribution", () => {
    expect(photoRecord(photo).photographer).toBe(photo.photographer);
    expect(photoRecord({ ...photo, src: { ...photo.src, medium: "https://attacker.test/photo" } })).toBeNull();
    expect(photoRecord({ ...photo, url: "javascript:alert(1)" })).toBeNull();
  });
  it("binds candidates without claiming human review or downloading images", async () => {
    const h = harness();
    const result = await h.run();
    const entry = h.args.catalog.entries[imageKey(apple)];
    expect(result.matched).toBe(1);
    expect(entry.reviewed).toBe(false);
    expect(entry.selected.id).toBe(42);
    expect(h.calls).toHaveLength(1);
    expect(h.calls[0].hostname).toBe("api.pexels.com");
    expect(h.calls[0].searchParams.get("per_page")).toBe("3");
    expect(JSON.stringify(h.writes)).not.toContain("private-test-key");
  });
  it("caps all runs together at 200 actual requests in a rolling hour", async () => {
    const words = Array.from({ length: 201 }, (_, i) => ({ word: `Begriff${i}`, translation: `${i}` }));
    const h = harness({ words });
    expect((await h.run()).requests).toBe(200);
    expect(h.calls).toHaveLength(200);
    const blocked = await h.run();
    expect(blocked.requests).toBe(0);
    expect(blocked.stop).toBe("quota");
    expect(blocked.pending).toBe(1);
    h.args.now = () => time + 3_602_000;
    expect((await h.run()).requests).toBe(1);
    expect(Object.keys(h.args.catalog.entries)).toHaveLength(201);
  });
  it("reuses cached searches for different records without spending quota", async () => {
    const h = harness({ words: [apple, { ...apple, translation: "apple fruit" }] });
    const result = await h.run();
    expect(result.matched).toBe(2);
    expect(result.requests).toBe(1);
    expect(result.cached).toBe(1);
  });
  it("preserves reviewed selections across repeated runs", async () => {
    const h = harness();
    await h.run();
    const entry = h.args.catalog.entries[imageKey(apple)];
    entry.selected = null; entry.status = "no_image"; entry.reviewed = true;
    expect((await h.run()).requests).toBe(0);
    expect(h.args.catalog.entries[imageKey(apple)]).toBe(entry);
    expect(entry.selected).toBeNull();
  });
  it("remembers no-result searches and only retries them explicitly", async () => {
    let requests = 0;
    const h = harness({ fetchImpl: async () => { requests++; return Response.json({ photos: [] }); } });
    expect((await h.run()).missing).toBe(1);
    expect((await h.run()).skipped).toBe(1);
    h.args.retryMissing = true;
    expect((await h.run()).cached).toBe(1);
    expect(requests).toBe(1);
    h.cache.clear();
    expect((await h.run()).requests).toBe(1);
    expect(requests).toBe(2);
  });
  it("counts timed-out requests durably and stops without an automatic retry", async () => {
    const persisted = [];
    const h = harness({
      saveLedger: async (data) => persisted.push(structuredClone(data)),
      fetchImpl: async () => { expect(persisted[0].attempts).toHaveLength(1); throw new Error("network"); },
    });
    const result = await h.run();
    expect(result.requests).toBe(1);
    expect(result.stop).toBe("network_error");
    expect(h.writes).toHaveLength(0);
    expect(h.args.ledger.attempts).toHaveLength(1);
  });
  it("stops on a bad key without storing or exposing the provider body", async () => {
    const h = harness({ fetchImpl: async () => new Response("do not store this private-test-key", { status: 401 }) });
    expect((await h.run()).stop).toBe("auth_error");
    expect(h.writes).toHaveLength(0);
    expect(h.cache.size).toBe(0);
  });
  it("honors a provider 429 Retry-After without burning the rest of the batch", async () => {
    const h = harness({ fetchImpl: async () => new Response("limited", { status: 429, headers: { "Retry-After": "120" } }) });
    const result = await h.run();
    expect(result.requests).toBe(1);
    expect(result.stop).toBe("quota");
    expect(Date.parse(result.resumeAt)).toBe(time + 120_000);
    expect((await h.run()).requests).toBe(0);
  });
  it("honors the monthly quota reset even if local hourly budget remains", async () => {
    const resetAt = time + 86_400_000;
    const h = harness({
      words: [apple, { word: "das Haus", translation: "дім" }],
      fetchImpl: async () => Response.json({ photos: [photo] }, { headers: { "X-Ratelimit-Remaining": "0", "X-Ratelimit-Reset": String(resetAt / 1000) } }),
    });
    const result = await h.run();
    expect(result.requests).toBe(1);
    expect(result.matched).toBe(1);
    expect(Date.parse(result.resumeAt)).toBe(resetAt);
  });
  it("does not turn malformed API data into a successful binding", async () => {
    const h = harness({ fetchImpl: async () => Response.json({ photos: "broken" }) });
    expect((await h.run()).stop).toBe("invalid_response");
    expect(Object.keys(h.args.catalog.entries)).toHaveLength(0);
  });
  it("can recover a saved API response if the catalog write is interrupted", async () => {
    const h = harness({ saveCatalog: async () => { throw new Error("disk unavailable"); } });
    await expect(h.run()).rejects.toThrow("disk unavailable");
    h.args.catalog = emptyCatalog();
    h.args.saveCatalog = async () => {};
    const result = await h.run();
    expect(result.requests).toBe(0);
    expect(result.cached).toBe(1);
    expect(result.matched).toBe(1);
    expect(h.calls).toHaveLength(1);
  });
  it("rejects invalid batch limits and catalogs before the API call", async () => {
    const h = harness({ limit: 201 });
    await expect(h.run()).rejects.toThrow("200");
    h.args.limit = 200; h.args.catalog = { schemaVersion: 99 };
    await expect(h.run()).rejects.toThrow("формат");
    expect(h.calls).toHaveLength(0);
  });
  it("escapes untrusted words inside the review document", () => {
    const attack = "</script><img src=x onerror=alert(1)>";
    const catalog = emptyCatalog();
    catalog.entries.example = { word: attack, translation: "example", candidates: [] };
    const html = reviewHtml(catalog);
    expect(html).not.toContain(attack);
    expect(html).toContain("\\u003c/script>");
    expect(html).toContain("Photos provided by Pexels");
  });
});

describe("private catalog files", () => {
  const directories = [];
  afterEach(async () => { for (const dir of directories.splice(0)) await rm(dir, { recursive: true, force: true }); });
  async function temporary() { const dir = await mkdtemp(join(tmpdir(), "twink-images-")); directories.push(dir); return dir; }
  it("reads actual Twink JSON exports without importing progress into the image catalog", async () => {
    const words = await readWords("../android/test/fixtures/web-demo.json");
    expect(words.length).toBeGreaterThan(0);
    expect(words[0].word).toBeTruthy();
    const h = harness({ words });
    await h.run();
    expect(JSON.stringify(h.args.catalog)).not.toContain("progress_global");
  });
  it("reads an XLSX export with German, translation and context columns", async () => {
    const path = join(await temporary(), "words.xlsx");
    const book = new ExcelJS.Workbook(), sheet = book.addWorksheet("Dictionary");
    sheet.addRow(["ID", "Немецкое слово", "Перевод", "Пример 1"]);
    sheet.addRow([123, "die Bank", "лавка", "Ich sitze auf der Bank im Park."]);
    await book.xlsx.writeFile(path);
    expect(await readWords(path)).toEqual([{ id: 123, word: "die Bank", translation: "лавка", ex1: "Ich sitze auf der Bank im Park." }]);
  });
  it("atomically writes and reopens a catalog, refusing simultaneous writers", async () => {
    const path = join(await temporary(), "catalog.json");
    await atomicJson(path, emptyCatalog());
    await atomicJson(path, { ...emptyCatalog(), updatedAt: "test" });
    expect((await readJson(path)).updatedAt).toBe("test");
    expect((await readFile(path, "utf8")).endsWith("\n")).toBe(true);
    const unlock = await acquireLock(`${path}.lock`);
    await expect(acquireLock(`${path}.lock`)).rejects.toThrow("уже працює");
    await unlock();
    await (await acquireLock(`${path}.lock`))();
  });
});
