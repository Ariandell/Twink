import { parseArgs } from "node:util";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { resolve, dirname, join } from "node:path";
import { homedir } from "node:os";
import { validateCatalog } from "./images/catalog.mjs";
import { acquireLock, atomicJson } from "./images/files.mjs";
import { packPreviews } from "./images/offline.mjs";
import { reviewHtml } from "./images/review.mjs";

async function main() {
  const { values: args } = parseArgs({ options: { input: { type: "string" }, output: { type: "string" }, "cache-dir": { type: "string" } } });
  if (!args.input || !args.output) throw new Error("Вкажіть --input catalog.json --output review.html");
  const input = resolve(args.input), output = resolve(args.output);
  if (input === output) throw new Error("Каталог і сторінка мають бути різними файлами.");
  const catalog = validateCatalog(JSON.parse((await readFile(input,"utf8")).trim()));
  const cacheDirectory = args["cache-dir"] ? resolve(args["cache-dir"]) : join(homedir(), ".twink", "image-previews");
  const unlock = await acquireLock(join(cacheDirectory, "pack.lock"));
  try {
    const result = await packPreviews({ catalog, cacheDirectory, progress: result => console.log(JSON.stringify(result)) });
    await mkdir(dirname(output), { recursive: true });
    const html = reviewHtml(catalog, { previews: result.previews, offlineOnly: true });
    const temporary = `${output}.${process.pid}.tmp`;
    await writeFile(temporary, html);
    const { rename } = await import("node:fs/promises"); await rename(temporary, output);
    const summary = { total: result.total, embedded: Object.keys(result.previews).length, failed: result.failures.length, failures: result.failures, bytes: Buffer.byteLength(html), output };
    await atomicJson(`${output}.assets.json`,summary);
    console.log(JSON.stringify(summary,null,2));
    if (result.failures.length) process.exitCode = 2;
  } finally { await unlock(); }
}
main().catch(error => { console.error(error.message); process.exitCode = 2; });
