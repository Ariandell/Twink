export const commonsUserAgent = "TwinkImages/0.1 (https://github.com/Ariandell/Twink) Node.js/24";

export function commonsSearchUrl(query) {
  const terms = String(query).match(/[\p{L}\p{N}][\p{L}\p{N}-]*/gu) ?? [];
  const keywords = terms.filter(term => !["the", "of", "and", "a", "an"].includes(term.toLowerCase())).slice(0, 4);
  if (!keywords.length) throw new Error("Порожній запит до Commons.");
  const titleQuery = keywords.map(term => `intitle:${term}`).join(" ");
  const url = new URL("https://commons.wikimedia.org/w/api.php");
  url.search = new URLSearchParams({
    action: "query", format: "json", formatversion: "2", generator: "search",
    gsrnamespace: "6", gsrsearch: `${titleQuery} filetype:bitmap`, gsrlimit: "3",
    prop: "imageinfo", iiprop: "url|extmetadata|mime|size", iiurlwidth: "500",
    iiextmetadatafilter: "Artist|Credit|LicenseShortName|LicenseUrl|ImageDescription|AttributionRequired|Restrictions",
    maxlag: "5",
  });
  return url;
}

export function plainText(value) {
  return String(value ?? "").replace(/<[^>]*>/gu, " ")
    .replace(/&#(x[\da-f]+|\d+);/giu, (all, code) => {
      const point = code[0].toLowerCase() === "x" ? parseInt(code.slice(1), 16) : Number(code);
      return point > 0 && point <= 0x10ffff ? String.fromCodePoint(point) : " ";
    })
    .replace(/&(amp|lt|gt|quot|apos|nbsp);/gu, (_, code) => ({ amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " })[code])
    .replace(/\s+/gu, " ").trim();
}

function safeUrl(value, host) {
  try { const url = new URL(value); return url.protocol === "https:" && url.hostname === host && !url.username && !url.password ? url.href : null; }
  catch { return null; }
}

function imageUrl(value) {
  return safeUrl(value, "upload.wikimedia.org") ?? safeUrl(value, "thumb.wikimedia.org");
}

function licenseRecord(metadata) {
  const name = plainText(metadata.LicenseShortName?.value);
  let url;
  try { url = new URL(metadata.LicenseUrl?.value); if (url.protocol === "http:") url.protocol = "https:"; } catch {}
  const freeCC = url?.hostname === "creativecommons.org" && !url.username && !url.password && url.protocol === "https:" &&
    /^\/(?:licenses\/(?:by|by-sa)\/[1-4]\.\d(?:\/[a-z-]+)?|publicdomain\/(?:zero|mark)\/1\.0)(?:\/deed\.[a-z-]+)?\/?$/u.test(url.pathname);
  if (name && freeCC) return { name, url: url.href };
  if (/^public domain$/iu.test(name)) return { name, url: null };
  return null;
}

export function commonsPhoto(page) {
  const info = page?.imageinfo?.[0], metadata = info?.extmetadata ?? {};
  if (!Number.isSafeInteger(page?.pageid) || !["image/jpeg", "image/png", "image/webp"].includes(info?.mime)) return null;
  const url = safeUrl(info.descriptionurl, "commons.wikimedia.org");
  const image = imageUrl(info.thumburl) ??
    (info.width <= 1280 && info.size <= 3_000_000 ? safeUrl(info.url, "upload.wikimedia.org") : null);
  const license = licenseRecord(metadata), artist = plainText(metadata.Artist?.value);
  // Reject unknown/restricted licensing or missing attribution rather than
  // silently treating every Commons file as having identical reuse terms.
  if (!url || !image || !license || !artist) return null;
  return {
    provider: "commons", id: page.pageid, url, imageUrl: image, thumbnailUrl: image,
    photographer: artist, photographerUrl: url,
    alt: plainText(metadata.ImageDescription?.value || page.title).slice(0, 600),
    title: String(page.title ?? ""), width: Number(info.width) || 0, height: Number(info.height) || 0,
    license: license.name, licenseUrl: license.url ?? url,
    credit: plainText(metadata.Credit?.value), restrictions: plainText(metadata.Restrictions?.value),
    attributionRequired: metadata.AttributionRequired?.value !== "false",
  };
}

export function commonsCandidates(data) {
  return [...(data.query?.pages ?? [])].sort((a, b) => (a.index ?? 0) - (b.index ?? 0)).map(commonsPhoto).filter(Boolean);
}

export function validCommonsResponse(data) {
  return data && !data.error && (Array.isArray(data.query?.pages) || "batchcomplete" in data && !data.query);
}
