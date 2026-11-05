import { readFileSync } from "node:fs";
import { describe, it, expect } from "vitest";
import {
  review,
  checkAnswer,
  eligible,
  examProgress,
  importRows,
  toRows,
  logicalDay,
  duplicateKey,
  entries,
  DAY,
} from "./domain";
const fixtures = JSON.parse(
  readFileSync(new URL("../../contracts/parity.json", import.meta.url), "utf8"),
);
describe("Shared Android / React contract", () => {
  fixtures.reviews.forEach((c, i) =>
    it(`rating ${i}`, () => {
      const p = review(c.previous, c.rating, c.mode, fixtures.now);
      expect(p.excellentStreak).toBe(c.score);
      expect(p.interval).toBeCloseTo(c.days, 12);
      expect(p.nextDate).toBe(fixtures.now + c.days * DAY);
      expect(p.is_ideal).toBe(c.ideal);
      expect(p.isActive).toBe(false);
    }),
  );
  fixtures.answers.forEach((c, i) =>
    it(`answer ${i}: ${c.answer}`, () => {
      const r = checkAnswer(c.word, c.answer);
      expect(r.correct).toBe(c.correct);
      for (const key of ["articleError", "sequenceError", "partial"])
        if (key in c) expect(r[key]).toBe(c[key]);
    }),
  );
  fixtures.eligibility.forEach((c, i) =>
    it(`queue ${i}`, () =>
      expect(eligible(c.word, c.exam, fixtures.now)).toBe(c.eligible)),
  );
  it("exam is the only way from 9 to active 10", () => {
    expect(review({ excellentStreak: 9 }, 6).excellentStreak).toBe(9);
    const p = examProgress({ excellentStreak: 9 }, { correct: true });
    expect(p.excellentStreak).toBe(10);
    expect(p.isActive).toBe(true);
    expect(
      examProgress(
        { excellentStreak: 9 },
        { correct: false, articleError: true },
      ).excellentStreak,
    ).toBe(7.5);
  });
  it("imports preserve unknown fields and schedules on existing words", () => {
    const old = {
      id: "1",
      word: "alt",
      translation: "x",
      extra: "keep",
      progress_global: {
        excellentStreak: 9,
        nextDate: 123,
        interval: 7,
        lastReviewed: 42,
      },
      progress_groups: { nextDate: 5 },
    };
    const rows = toRows([{ ...old, word: "neu" }], "words");
    const r = importRows(rows, "words", { 1: old }, fixtures.now);
    expect(r.updates["1"].progress_global).toEqual(old.progress_global);
    expect(r.updates["1"].extra).toBe("keep");
    expect(r.updates["1"].word).toBe("neu");
    expect(r.updates["1"].progress_groups).toEqual(old.progress_groups);
  });
  it("new imports start fresh and never delete omitted entries", () => {
    const r = importRows(
      [["ID"], ["2", 10, "neu", "новий"]],
      "words",
      { 1: { word: "old" } },
      fixtures.now,
    );
    expect(r.updates["2"].progress_global.excellentStreak).toBe(0);
    expect(Object.keys(r.updates)).toEqual(["2"]);
  });
  it("rejects malformed imports before any write", () => {
    expect(() => importRows([["a/b", 0, "x", "y"]], "words")).toThrow();
    expect(() => importRows([["100000", 0, "x", "y"]], "words")).toThrow();
  });
  it("keeps original six-hour UTC boundary", () => {
    expect(logicalDay(Date.parse("2026-11-01T05:59:59Z"))).toBe("2026-10-31");
    expect(logicalDay(Date.parse("2026-11-01T06:00:00Z"))).toBe("2026-11-01");
  });
  it("does not merge nouns and adverbs", () =>
    expect(duplicateKey("der Morgen")).not.toBe(duplicateKey("morgen")));
  it("reads sparse numeric-key Firebase arrays", () =>
    expect(
      entries([null, { word: "A" }, null, { word: "B" }]).map((w) => w.id),
    ).toEqual(["1", "3"]));
});
