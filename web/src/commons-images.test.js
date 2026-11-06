import { it, expect } from "vitest";
import { commonsSearchUrl, commonsPhoto, plainText, validCommonsResponse } from "../scripts/images/commons.mjs";
import { runBatch, emptyCatalog, imageKey, quotaDelay } from "../scripts/images/catalog.mjs";
import { reviewHtml } from "../scripts/images/review.mjs";

const page = {
  pageid: 42, title: "File:Red Apple.jpg", index: 1,
  imageinfo: [{ mime: "image/jpeg", width: 2000, height: 1000, size: 1_000_000,
    descriptionurl: "https://commons.wikimedia.org/wiki/File:Red_Apple.jpg",
    url: "https://upload.wikimedia.org/wikipedia/commons/a/a0/Red_Apple.jpg",
    thumburl: "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a0/Red_Apple.jpg/640px-Red_Apple.jpg",
    extmetadata: {
      Artist: { value: '<a href="https://example.org">Author &amp; partner</a>' },
      LicenseShortName: { value: "CC BY-SA 4.0" },
      LicenseUrl: { value: "https://creativecommons.org/licenses/by-sa/4.0/" },
      ImageDescription: { value: "<p>A red apple</p>" },
    },
  }],
};
const word = { word: "der Apfel", translation: "яблуко" };
const now = Date.UTC(2026, 10, 6);
function setup(data = { batchcomplete: true, query: { pages: [page] } }) {
  const calls = [], catalog = emptyCatalog("commons"), ledger = { attempts: [] };
  return { calls, catalog, ledger, args: {
    words: [word], catalog, ledger, now: () => now,
    saveCatalog: async () => {}, saveLedger: async () => {},
    fetchImpl: async (url, options) => { calls.push({ url, options }); return Response.json(data); },
  }};
}

it("requests at most three bitmap candidates with licensing and a small thumbnail", () => {
  const url = commonsSearchUrl("apple fruit");
  expect(url.hostname).toBe("commons.wikimedia.org");
  expect(url.searchParams.get("gsrsearch")).toBe("intitle:apple intitle:fruit filetype:bitmap");
  expect(commonsSearchUrl('end of road').searchParams.get('gsrsearch')).toBe('intitle:end intitle:road filetype:bitmap');
  expect(url.searchParams.get("gsrlimit")).toBe("3");
  expect(url.searchParams.get("iiurlwidth")).toBe("500");
  expect(url.searchParams.get("maxlag")).toBe("5");
});
it("keeps the author, license, source and thumbnail, stripping metadata HTML", () => {
  const result = commonsPhoto(page);
  expect(result.provider).toBe("commons");
  expect(result.photographer).toBe("Author & partner");
  expect(result.license).toBe("CC BY-SA 4.0");
  expect(result.imageUrl).toContain("640px");
  expect(result.alt).toBe("A red apple");
  expect(plainText('&#x41;&#66;&quot; <script>text</script>')).toBe('AB" text');
  const migrated = commonsPhoto({ ...page, imageinfo: [{ ...page.imageinfo[0], thumburl: page.imageinfo[0].thumburl.replace('upload.wikimedia.org','thumb.wikimedia.org') }] });
  expect(migrated.thumbnailUrl).toContain('thumb.wikimedia.org');
});
it("rejects unknown licensing, missing authors and foreign image hosts", () => {
  for (const patch of [
    { extmetadata: { ...page.imageinfo[0].extmetadata, LicenseUrl: { value: "https://example.org/license" } } },
    { extmetadata: { ...page.imageinfo[0].extmetadata, Artist: undefined } },
    { thumburl: "https://attacker.example/file.jpg" },
    { mime: "application/pdf" },
  ]) expect(commonsPhoto({ ...page, imageinfo: [{ ...page.imageinfo[0], ...patch }] })).toBeNull();
});
it("preserves explicit public-domain status and upgrades HTTP CC0 license links", () => {
  const base = page.imageinfo[0];
  const pd = commonsPhoto({ ...page, imageinfo: [{ ...base, extmetadata: { ...base.extmetadata, LicenseShortName: { value: "Public domain" }, LicenseUrl: undefined } }] });
  expect(pd.license).toBe("Public domain");
  const cc0 = commonsPhoto({ ...page, imageinfo: [{ ...base, extmetadata: { ...base.extmetadata, LicenseShortName: { value: "CC0" }, LicenseUrl: { value: "http://creativecommons.org/publicdomain/zero/1.0/deed.en" } } }] });
  expect(cc0.licenseUrl).toMatch(/^https:/u);
});
it("runs without an API key and sends an identifying User-Agent, never an auth key", async () => {
  const h = setup();
  const result = await runBatch(h.args);
  expect(result.matched).toBe(1);
  expect(h.calls[0].options.headers["User-Agent"]).toContain("github.com/Ariandell/Twink");
  expect(h.calls[0].options.headers.Authorization).toBeUndefined();
  expect(h.catalog.entries[imageKey(word)].selected.license).toBe("CC BY-SA 4.0");
});
it("distinguishes a valid empty search from malformed or server-error data", async () => {
  expect(validCommonsResponse({ batchcomplete: true })).toBe(true);
  expect(validCommonsResponse({ error: { code: "badrequest" } })).toBe(false);
  expect(validCommonsResponse({ query: { pages: "broken" } })).toBe(false);
  const empty = setup({ batchcomplete: true });
  expect((await runBatch(empty.args)).missing).toBe(1);
  const malformed = setup({ query: { pages: "broken" } });
  expect((await runBatch(malformed.args)).stop).toBe("invalid_response");
});
it("respects maxlag and Retry-After instead of marking server errors as missing words", async () => {
  const maxlag = setup({ error: { code: "maxlag" } });
  expect((await runBatch(maxlag.args)).stop).toBe("quota");
  expect(maxlag.catalog.entries).toEqual({});
  const busy = setup();
  busy.args.fetchImpl = async () => new Response("busy", { status: 503, headers: { "Retry-After": "120" } });
  expect((await runBatch(busy.args)).resumeAt).toBe(new Date(now + 120_000).toISOString());
});
it("uses a conservative minute limit independent of Pexels hourly quota", () => {
  const ledger = { attempts: Array.from({ length: 30 }, () => now - 1000) };
  expect(quotaDelay(structuredClone(ledger), now, "commons")).toBeGreaterThan(0);
  expect(quotaDelay(structuredClone(ledger), now, "pexels")).toBe(0);
});
it("includes Commons attribution and license links in the review page", () => {
  const catalog = emptyCatalog("commons");
  const photo = commonsPhoto(page);
  catalog.entries[imageKey(word)] = { ...word, candidates: [photo], selected: photo };
  const html = reviewHtml(catalog);
  expect(html).toContain("Images from Wikimedia Commons");
  expect(html).toContain("upload.wikimedia.org");
  expect(html).toContain("creativecommons.org");
  expect(html).not.toContain("Photos provided by Pexels");
});
it("retries deferred unreviewed bindings only when explicitly requested", async () => {
  const h = setup();
  h.catalog.entries[imageKey(word)] = { ...word, selected: null, status: "needs_review", reviewed: false };
  expect((await runBatch(h.args)).requests).toBe(0);
  h.args.retryMissing = true;
  expect((await runBatch(h.args)).requests).toBe(1);
  expect(h.catalog.entries[imageKey(word)].selected.id).toBe(42);
});
