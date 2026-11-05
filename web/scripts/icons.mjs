import sharp from "sharp";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
const source = await readFile(new URL("../public/classic/icon-512.png", import.meta.url));
const render = (size) =>
  sharp(source)
    .resize(size, size, { fit: "contain", background: "#080b10" })
    .png();
for (const size of [192, 512])
  await render(size).toFile(
    fileURLToPath(new URL(`../public/icon-${size}.png`, import.meta.url)),
  );
if (process.argv.includes("--android"))
  for (const [density, size] of Object.entries({
    mdpi: 48,
    hdpi: 72,
    xhdpi: 96,
    xxhdpi: 144,
    xxxhdpi: 192,
  }))
    await render(size).toFile(
      fileURLToPath(
        new URL(
          `../../android/android/app/src/main/res/mipmap-${density}/ic_launcher.png`,
          import.meta.url,
        ),
      ),
    );
