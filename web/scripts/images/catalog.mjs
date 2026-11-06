import { createHash } from "node:crypto";

export const normalize = (value) => String(value ?? "").trim().replace(/\s+/gu, " ").toLowerCase();
export const imageKey = (word) => createHash("sha256")
  .update(`${normalize(word.word ?? word.idiom)}\u001f${normalize(word.translation)}`)
  .digest("hex");

const common = new Set("Ich Du Er Sie Es Wir Ihr Ein Eine Einen Einer Eines Der Die Das Den Dem Des Am Im Zum Zur Auf An In Mit Ohne Und Oder Aber Mein Meine Unser Unsere Dieser Diese Dieses Heute Morgen Gestern".toLowerCase().split(" "));

export function searchFor(word, override) {
  if (override) {
    const query = String(override.query ?? override).trim().slice(0, 160), locale = override.locale ?? "en-US";
    if (!query || !/^[a-z]{2}-[A-Z]{2}$/u.test(locale)) throw new Error("Порожній запит або некоректна мова в плані пошуку.");
    return { query, locale };
  }
  const title = String(word.word ?? word.idiom ?? "").split(",")[0]
    .replace(/\([^)]*\)/gu, "").replace(/^(der|die|das|ein|eine)\s+/iu, "").trim();
  // Capitalized context nouns help distinguish e.g. Bank + Park. This is a
  // heuristic, not semantic verification; all automatic matches remain unreviewed.
  const core = new Set(normalize(title).split(/[^\p{L}\p{N}_]+/u));
  const context = [word.ex1, word.ex2, word.example].filter(Boolean).join(" ");
  const nouns = [...context.matchAll(/(?<![\p{L}\p{N}_])[A-ZÄÖÜ][a-zäöüß]{2,}(?![\p{L}\p{N}_])/gu)]
    .filter((match) => !/(?:^|[.!?])\s*$/u.test(context.slice(0, match.index)))
    .map((m) => m[0]).filter((w) => !common.has(normalize(w)) && !core.has(normalize(w)));
  return { query: [title, ...[...new Set(nouns)].slice(0, 2)].join(" ").slice(0, 160), locale: "de-DE" };
}

function safeUrl(value, host) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname === host && !url.username && !url.password ? url.href : null;
  } catch { return null; }
}

export function photoRecord(photo) {
  const url = safeUrl(photo?.url, "www.pexels.com");
  const imageUrl = safeUrl(photo?.src?.medium, "images.pexels.com");
  const thumbnailUrl = safeUrl(photo?.src?.tiny, "images.pexels.com");
  if (!Number.isSafeInteger(photo?.id) || !url || !imageUrl || !thumbnailUrl) return null;
  return {
    provider: "pexels", id: photo.id, url, imageUrl, thumbnailUrl,
    photographer: String(photo.photographer ?? "Pexels"),
    photographerUrl: safeUrl(photo.photographer_url, "www.pexels.com") ?? url,
    alt: String(photo.alt ?? ""), width: Number(photo.width) || 0, height: Number(photo.height) || 0,
  };
}

export function emptyCatalog() {
  return { schemaVersion: 1, provider: "pexels", entries: {} };
}

export function validateCatalog(catalog) {
  if (catalog?.schemaVersion !== 1 || catalog?.provider !== "pexels" || !catalog.entries || typeof catalog.entries !== "object" || Array.isArray(catalog.entries)) {
    throw new Error("Непідтримуваний формат каталогу зображень. Наявний файл не змінено.");
  }
  return catalog;
}

export function planWords(words, catalog = emptyCatalog(), overrides = {}) {
  const seen = new Set();
  return words.filter((word) => String(word.word ?? word.idiom ?? "").trim()).flatMap((word) => {
    const key = imageKey(word);
    if (seen.has(key)) return [];
    seen.add(key);
    return [{ key, word, ...searchFor(word, overrides[key] ?? overrides[String(word.id)]), existing: catalog.entries[key]?.status ?? null }];
  });
}

const HOUR = 3_600_000;
export function quotaDelay(ledger, now) {
  ledger.attempts = (ledger.attempts ?? []).filter((time) => time > now - HOUR);
  const hourDelay = ledger.attempts.length >= 200 ? ledger.attempts[0] + HOUR - now + 1000 : 0;
  return Math.max(hourDelay, (ledger.pauseUntil ?? 0) - now, 0);
}

export function readQuota(response, ledger, now) {
  const remaining = response.headers.get("x-ratelimit-remaining");
  const reset = Number(response.headers.get("x-ratelimit-reset")) * 1000;
  if (remaining !== null && Number.isFinite(Number(remaining))) ledger.remaining = Number(remaining);
  if (reset > now) ledger.resetAt = reset;
  if (ledger.remaining === 0) ledger.pauseUntil = reset > now ? reset : now + HOUR;
  if (response.status === 429) {
    const retry = response.headers.get("retry-after");
    const retryAt = retry && /^\d+$/u.test(retry) ? now + Number(retry) * 1000 : Date.parse(retry);
    ledger.pauseUntil = Math.max(ledger.pauseUntil ?? 0, retryAt > now ? retryAt : now + HOUR);
  }
}

// All I/O is injected so tests never spend the live API quota. The CLI supplies
// durable, atomic writes and a per-key process lock before calling this function.
export async function runBatch({ words, catalog, ledger, apiKey, limit = 200, overrides = {},
  fetchImpl = fetch, now = Date.now, saveCatalog, saveLedger,
  cacheGet = async () => null, cachePut = async () => {}, retryMissing = false, retryErrors = false,
  progress = () => {}, signal,
}) {
  validateCatalog(catalog);
  if (!apiKey || !String(apiKey).trim()) throw new Error("Не задано ключ PEXELS_API_KEY.");
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) throw new Error("Порція має містити від 1 до 200 запитів.");
  const plan = planWords(words, catalog, overrides);
  const result = { requests: 0, matched: 0, missing: 0, skipped: 0, cached: 0, errors: 0, pending: 0, stop: "complete", httpStatus: null, resumeAt: null };
  for (const item of plan) {
    const old = catalog.entries[item.key];
    if (old && !(old.status === "not_found" && retryMissing) && !(old.status === "error" && retryErrors)) { result.skipped++; continue; }
    if (signal?.aborted) { result.stop = "interrupted"; break; }
    const cacheKey = createHash("sha256").update(JSON.stringify([item.query, item.locale, 3])).digest("hex");
    let data = await cacheGet(cacheKey);
    if (data) result.cached++;
    else {
      if (result.requests >= limit) { result.stop = "batch_limit"; break; }
      const delay = quotaDelay(ledger, now());
      if (delay > 0) { result.stop = "quota"; result.resumeAt = new Date(now() + delay).toISOString(); break; }
      // Persist BEFORE sending: interruption/timeout still consumes the budget.
      ledger.attempts.push(now());
      await saveLedger(ledger);
      result.requests++;
      const url = new URL("https://api.pexels.com/v1/search");
      url.search = new URLSearchParams({ query: item.query, locale: item.locale, orientation: "landscape", per_page: "3" });
      let response;
      try {
        response = await fetchImpl(url, { headers: { Authorization: apiKey }, signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(30_000)]) : AbortSignal.timeout(30_000) });
      } catch {
        result.errors++;
        result.stop = signal?.aborted ? "interrupted" : "network_error";
        // No automatic retry: the request may have reached Pexels.
        break;
      }
      readQuota(response, ledger, now());
      await saveLedger(ledger);
      if (!response.ok) {
        result.errors++;
        result.httpStatus = response.status;
        result.stop = response.status === 429 ? "quota" : response.status === 401 || response.status === 403 ? "auth_error" : "api_error";
        if (ledger.pauseUntil > now()) result.resumeAt = new Date(ledger.pauseUntil).toISOString();
        break;
      }
      try { data = await response.json(); } catch { result.errors++; result.stop = "invalid_response"; break; }
      if (!Array.isArray(data?.photos)) { result.errors++; result.stop = "invalid_response"; break; }
      await cachePut(cacheKey, data);
    }
    const candidates = data.photos.map(photoRecord).filter(Boolean);
    catalog.entries[item.key] = {
      word: String(item.word.word ?? item.word.idiom), translation: String(item.word.translation ?? ""),
      sourceId: String(item.word.id ?? ""), context: [item.word.ex1, item.word.ex2, item.word.example].filter(Boolean).join("\n"),
      query: item.query, locale: item.locale, status: candidates.length ? "matched" : "not_found",
      reviewed: false, selected: candidates[0] ?? null, candidates, searchedAt: new Date(now()).toISOString(),
    };
    catalog.updatedAt = new Date(now()).toISOString();
    await saveCatalog(catalog);
    if (candidates.length) result.matched++; else result.missing++;
    progress({ ...result });
  }
  result.pending = plan.filter((item) => !catalog.entries[item.key]).length;
  return result;
}
