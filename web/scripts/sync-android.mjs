import { cp, mkdir } from "node:fs/promises";
const from = new URL("../public/classic/", import.meta.url),
  to = new URL("../../android/assets/classic/", import.meta.url);
await mkdir(to, { recursive: true });
await cp(from, to, { recursive: true });
