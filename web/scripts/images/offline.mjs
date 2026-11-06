import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile, rename } from "node:fs/promises";
import { join } from "node:path";
import sharp from "sharp";
import { setTimeout as sleep } from "node:timers/promises";
import { commonsUserAgent } from "./commons.mjs";

const hosts = new Set(["upload.wikimedia.org", "thumb.wikimedia.org", "images.pexels.com"]);
export function allowedImageUrl(value) {
  const url = new URL(value);
  if (url.protocol !== "https:" || !hosts.has(url.hostname) || url.username || url.password || url.port && url.port !== "443") throw new Error("Непідтримувана адреса прев’ю.");
  return url;
}

async function fetchBytes(value, fetchImpl) {
  let url = allowedImageUrl(value);
  for (let redirect = 0; redirect < 4; redirect++) {
    const response = await fetchImpl(url, {
      redirect: "manual", headers: { "User-Agent": commonsUserAgent }, signal: AbortSignal.timeout(25_000),
    });
    if ([301,302,303,307,308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location) throw new Error("Відсутня адреса перенаправлення.");
      url = allowedImageUrl(new URL(location, url).href);
      continue;
    }
    if (!response.ok) {
      const error = new Error(`HTTP ${response.status}`);
      error.status = response.status;
      const retry = response.headers.get("retry-after");
      error.retryMs = retry && /^\d+$/u.test(retry) ? Number(retry) * 1000 : Math.max(0, Date.parse(retry) - Date.now());
      throw error;
    }
    const type = response.headers.get("content-type")?.split(";")[0];
    if (!["image/jpeg","image/png","image/webp"].includes(type)) throw new Error("Відповідь не є зображенням.");
    if (Number(response.headers.get("content-length")) > 8_000_000) throw new Error("Прев’ю перевищує 8 MB.");
    const chunks = []; let size = 0;
    for await (const chunk of response.body) {
      size += chunk.byteLength;
      if (size > 8_000_000) throw new Error("Прев’ю перевищує 8 MB.");
      chunks.push(chunk);
    }
    return Buffer.concat(chunks);
  }
  throw new Error("Забагато перенаправлень.");
}

export async function packPreviews({ catalog, cacheDirectory, fetchImpl = fetch, intervalMs = 550,
  wait = sleep, progress = () => {},
}) {
  await mkdir(cacheDirectory, { recursive: true });
  const photos = [...new Map(Object.values(catalog.entries).flatMap(entry => entry.candidates ?? []).map(photo => [`${photo.provider}:${photo.id}`, photo])).values()];
  const previews = {}, failures = [];
  let cached = 0, downloaded = 0, next = 0, nextStart = 0, pauseUntil = 0;
  async function worker() {
    while (next < photos.length) {
      const photo = photos[next++], key = `${photo.provider}:${photo.id}`;
      const file = join(cacheDirectory, `${createHash("sha256").update(key).digest("hex")}.webp`);
      try {
        let bytes;
        try { bytes = await readFile(file); await sharp(bytes).metadata(); cached++; }
        catch (error) { if (error.code !== "ENOENT") throw error; }
        if (!bytes) {
          // Two workers, at most ~110 request starts/minute. Wikimedia's
          // response Retry-After takes precedence across both workers.
          const start = Math.max(Date.now(), nextStart, pauseUntil);
          nextStart = start + intervalMs;
          if (start > Date.now()) await wait(start - Date.now());
          if (pauseUntil > Date.now()) await wait(pauseUntil - Date.now());
          let input;
          for (let attempt = 0; attempt < 2; attempt++) {
            try { input = await fetchBytes(photo.thumbnailUrl, fetchImpl); break; }
            catch (error) {
              if (attempt || ![429,502,503,504].includes(error.status)) throw error;
              pauseUntil = Math.max(pauseUntil, Date.now() + (Number.isFinite(error.retryMs) && error.retryMs > 0 ? error.retryMs : 10_000));
              if (pauseUntil > Date.now()) await wait(pauseUntil - Date.now());
            }
          }
          bytes = await sharp(input, { limitInputPixels: 40_000_000 }).rotate()
            .resize({ width: 360, height: 240, fit: "inside", withoutEnlargement: true })
            .webp({ quality: 72 }).toBuffer();
          const temporary = `${file}.${process.pid}.tmp`;
          await writeFile(temporary, bytes); await rename(temporary, file);
          downloaded++;
        }
        previews[key] = `data:image/webp;base64,${bytes.toString("base64")}`;
      } catch (error) { failures.push({ key, message: error.message }); }
      const completed = Object.keys(previews).length + failures.length;
      if (completed % 25 === 0 || completed === photos.length) progress({ completed, total: photos.length, cached, downloaded, failed: failures.length });
    }
  }
  await Promise.all([worker(),worker()]);
  return { previews, failures, cached, downloaded, total: photos.length };
}
