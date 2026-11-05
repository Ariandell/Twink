import { readdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
const dir = new URL("../dist/", import.meta.url);
const paths = await readdir(dir, { recursive: true });
const files = paths
  .filter(
    (p) =>
      p !== "sw.js" &&
      (p.endsWith(".js") ||
        p.endsWith(".css") ||
        p.endsWith(".html") ||
        p.endsWith(".svg") ||
        p.endsWith(".png") ||
        p.endsWith(".json") ||
        p.endsWith(".webmanifest")),
  )
  .map((p) => "/" + p.replaceAll("\\", "/"));
const revision = createHash("sha256")
  .update(
    (await Promise.all(files.map((p) => readFile(new URL("." + p, dir)))))
      .map((b) => createHash("sha256").update(b).digest("hex"))
      .join(""),
  )
  .digest("hex")
  .slice(0, 12);
await writeFile(
  new URL("sw.js", dir),
  `
const CACHE='twink-${revision}',FILES=${JSON.stringify(files)};
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(FILES)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('twink-')&&!k.startsWith('twink-tts-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{if(event.request.method!=='GET'||new URL(event.request.url).origin!==self.location.origin)return;if(event.request.mode==='navigate'){event.respondWith(fetch(event.request).catch(async()=>await caches.match(new URL(event.request.url).pathname)||await caches.match('/index.html')));return;}event.respondWith(caches.match(event.request,{ignoreSearch:true}).then(cached=>cached||fetch(event.request)));});
`,
);
