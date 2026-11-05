import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { describe, it, expect } from "vitest";
import { createDemoFirebase } from "./demo-store";
const root = new URL("../../public/classic/", import.meta.url);
const baseline = JSON.parse(
  readFileSync(
    new URL("../../../contracts/original-manifest.json", import.meta.url),
    "utf8",
  ),
);
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const body = (html) =>
  html
    .match(/<body[^>]*>([\s\S]*?)<\/body>/i)?.[1]
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/\s+/g, " ")
    .trim();
describe("Original Twink interface", () => {
  for (const [name, expected] of Object.entries(baseline.files))
    it(`preserves original ${name}`, () =>
      expect(hash(readFileSync(new URL(name, root)))).toBe(expected));
  for (const [name, expected] of Object.entries(baseline.bodies))
    it(`preserves all original UI markup and text in ${name}`, () =>
      expect(hash(body(readFileSync(new URL(name, root), "utf8")))).toBe(
        expected,
      ));
  it("ships the same original card and controls", () => {
    const html = readFileSync(new URL("index.html", root), "utf8");
    for (const id of [
      "flashcard",
      "card-info1",
      "card-info2",
      "card-examples",
      "card-translation",
      "btn-flashcard-edit",
      "btn-session-settings",
      "rating-buttons",
    ])
      expect(html).toContain(`id="${id}"`);
    expect(html).toContain("rating-grid-2");
  });
  it("demo updates words locally and deletes records without any live Firebase access", async () => {
    const map = new Map(),
      storage = {
        getItem: (k) => map.get(k) || null,
        setItem: (k, v) => map.set(k, v),
        removeItem: (k) => map.delete(k),
      };
    let accesses = 0;
    const fb = createDemoFirebase(
      new Proxy(
        {},
        {
          get() {
            accesses++;
            throw Error("No live access");
          },
        },
      ),
      storage,
    );
    const db = fb.database();
    await db.ref("users/demo/words/1").update({ translation: "проверка" });
    expect(
      (await db.ref("users/demo/words/1").once("value")).val().translation,
    ).toBe("проверка");
    await db.ref("users/demo/words/1").remove();
    expect((await db.ref("users/demo/words/1").once("value")).val()).toBeNull();
    expect(accesses).toBe(0);
  });
});
