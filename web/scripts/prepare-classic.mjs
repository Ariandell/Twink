import { build } from "esbuild";
import { readdir, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { loadEnv } from "vite";
const root = new URL("../", import.meta.url),
  classic = new URL("public/classic/", root);
const env = loadEnv(process.env.NODE_ENV || "production", fileURLToPath(root), "VITE_");
await build({
  entryPoints: [
    fileURLToPath(new URL("src/classic/firebase-compat-entry.js", root)),
  ],
  bundle: true,
  format: "iife",
  platform: "browser",
  target: "es2020",
  outfile: fileURLToPath(new URL("vendor/firebase-compat.js", classic)),
  minify: true,
  logLevel: "warning",
});
await build({
  entryPoints: [fileURLToPath(new URL("src/classic/bridge-entry.js", root))],
  bundle: true,
  format: "iife",
  platform: "browser",
  target: "es2020",
  outfile: fileURLToPath(new URL("vendor/twink-bridge.js", classic)),
  define: {
    "import.meta.env.VITE_ELEVENLABS_API_KEY": JSON.stringify(
      process.env.VITE_ELEVENLABS_API_KEY || env.VITE_ELEVENLABS_API_KEY || "",
    ),
  },
  minify: true,
  logLevel: "warning",
});
for (const name of await readdir(classic)) {
  if (!name.endsWith(".html")) continue;
  let html = await readFile(new URL(name, classic), "utf8");
  if (name === "index.html" && !html.includes('href="compat-layout.css"'))
    html = html.replace("</head>", '    <link rel="stylesheet" href="compat-layout.css">\n</head>');
  html = html.replace(
    /<script src="https:\/\/www\.gstatic\.com\/firebasejs\/9\.22\.0\/firebase-app-compat\.js"><\/script>/g,
    '<script src="vendor/firebase-compat.js"></script>',
  );
  html = html.replace(
    /\s*<script src="https:\/\/www\.gstatic\.com\/firebasejs\/9\.22\.0\/firebase-(?:auth|database)-compat\.js"><\/script>/g,
    "",
  );
  html = html.replace(
    "https://cdn.sheetjs.com/xlsx-0.20.0/package/dist/xlsx.full.min.js",
    "vendor/xlsx.full.min.js",
  );
  if (name === "index.html" && !html.includes("vendor/twink-bridge.js"))
    html = html.replace(
      '<script src="study.js"></script>',
      '<script src="study.js"></script>\n    <script src="vendor/twink-bridge.js"></script>',
    );
  html = html.replace(
    /(?<!\) )navigator\.serviceWorker\.register\('\/sw.js'\)/g,
    "(!window.TwinkNative) && navigator.serviceWorker.register('/sw.js')",
  );
  // Native containers have bundled files, and do not need a service worker.
  html = html.replace(
    "(!window.TwinkNative) && (!window.TwinkNative) && ",
    "(!window.TwinkNative) && ",
  );
  await writeFile(new URL(name, classic), html);
}
const hashes = {};
for (const name of await readdir(classic)) {
  if (name.endsWith(".css") || name.endsWith(".js"))
    hashes[name] = createHash("sha256")
      .update(await readFile(new URL(name, classic)))
      .digest("hex");
}
await writeFile(
  new URL("parity-manifest.json", classic),
  JSON.stringify({ interface: "original Twink-main", files: hashes }, null, 2),
);
