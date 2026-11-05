export const DAY = 86400000;
export const INTERVALS = {
  long: [0, 1 / 24, 1, 4, 7, 12, 21],
  intensive: [0, 1 / 24, 1, 2, 4, 9, 17],
};
export const RATINGS = [
  "",
  "Забув",
  "Важко",
  "Невпевнено",
  "Добре",
  "Пам’ятаю",
  "Відмінно",
];
export function entries(raw) {
  return Object.entries(raw || {})
    .filter(([, v]) => v && typeof v === "object")
    .map(([id, v]) => ({ ...v, id }));
}
export function freshProgress(now = Date.now()) {
  return {
    interval: 0,
    nextDate: now,
    state: "new",
    excellentStreak: 0,
    isActive: false,
    is_ideal: false,
  };
}
export function title(w) {
  return w.word || w.idiom || "";
}
export function eligible(w, exam = false, now = Date.now()) {
  const p = w.progress_global || {};
  return (
    !p.isActive &&
    (!p.nextDate || p.nextDate <= now) &&
    (exam
      ? !w.idiom && (p.excellentStreak || 0) >= 9
      : !!w.idiom || (p.excellentStreak || 0) < 9)
  );
}
export function review(previous, rating, mode = "long", now = Date.now()) {
  const p = previous || {},
    interval = (INTERVALS[mode] || INTERVALS.long)[rating];
  if (!interval) throw new Error("Невідома оцінка");
  const score =
    rating === 1
      ? 0
      : Math.min(
          9,
          Math.max(
            0,
            Math.round(
              ((p.excellentStreak || 0) + [0, 0, -3, -1.5, 0, 1.5, 3][rating]) *
                10,
            ) / 10,
          ),
        );
  return {
    ...p,
    interval,
    nextDate: now + interval * DAY,
    lastRating: rating,
    lastReviewed: now,
    excellentStreak: score,
    isActive: !!p.isActive,
    is_ideal: !!p.isActive || rating >= 5,
  };
}
export function examProgress(
  previous,
  result,
  mode = "long",
  now = Date.now(),
) {
  const p = previous || {};
  const score = result.correct
    ? 10
    : Math.max(
        0,
        (p.excellentStreak || 0) -
          (result.articleError || result.sequenceError ? 1.5 : 3),
      );
  const rating = result.correct ? 6 : score >= 9 ? 4 : 2,
    interval = (INTERVALS[mode] || INTERVALS.long)[rating];
  return {
    ...p,
    excellentStreak: score,
    isActive: result.correct,
    is_ideal: result.correct,
    interval,
    nextDate: now + interval * DAY,
    lastRating: rating,
    lastReviewed: now,
  };
}
const ARTICLES = /\b(der|die|das|den|dem|des|ein|eine|einer|einem|einen)\b/gi;
const noParens = (s) => String(s || "").replace(/\([^)]*\)/g, "");
const clean = (s) =>
  noParens(s)
    .toLowerCase()
    .replace(ARTICLES, "")
    .replace(/[^a-z0-9äöüß\s]/gi, " ")
    .trim()
    .replace(/\s+/g, " ");
const compact = (s) => clean(s).replace(/\s/g, "");
const article = (s) =>
  noParens(s)
    .trim()
    .match(/^(der|die|das|den|dem|des|ein|eine|einer|einem|einen)\b/i)?.[1]
    ?.toLowerCase() || null;
export function duplicateKey(s) {
  return (
    compact(
      String(s)
        .split(",")[0]
        .replace(/\bsich\b/gi, ""),
    ) + (article(s) ? "::noun" : "")
  );
}
export function autoFolder(list) {
  const counts = {};
  for (const w of list) {
    const m = String(w.folder || "").match(/^Папка (\d+)$/);
    if (m) counts[m[1]] = (counts[m[1]] || 0) + 1;
  }
  let n = Math.max(1, ...Object.keys(counts).map(Number));
  if ((counts[n] || 0) >= 100) n++;
  return `Папка ${n}`;
}
export function checkAnswer(w, answer) {
  const expected = title(w),
    info = w.info1 || "";
  let content = false,
    partial = false,
    sequenceError = false;
  if (info) {
    const units = (expected + "," + info)
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    const variants = (unit) => {
      if (!unit.includes("/")) return [{ text: clean(unit), partial: false }];
      const tokens = unit.replace(/\s*\/\s*/g, "/").split(/\s+/),
        i = tokens.findIndex((t) => t.includes("/"));
      const [a, b] = tokens[i].split("/");
      return [a, b, a + " " + b, b + " " + a].map((v, j) => ({
        text: clean(tokens.map((t, k) => (k === i ? v : t)).join(" ")),
        partial: j < 2,
      }));
    };
    const permute = (rest, left) => {
      if (!left.length) return { ok: !rest.trim(), partial: false };
      for (let i = 0; i < left.length; i++)
        for (const v of variants(left[i])) {
          if (!v.text) continue;
          const re = new RegExp(
            "(^|\\s)" +
              v.text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") +
              "(?=\\s|$)",
          );
          if (re.test(rest)) {
            const r = permute(
              rest.replace(re, " ").trim().replace(/\s+/g, " "),
              left.filter((_, j) => i !== j),
            );
            if (r.ok) return { ok: true, partial: v.partial || r.partial };
          }
        }
      return { ok: false, partial: false };
    };
    const r = permute(clean(answer), units);
    content = r.ok;
    partial = r.partial;
    const sorted = (s) => clean(s).split(" ").filter(Boolean).sort().join(" ");
    sequenceError =
      !content && sorted(answer) === sorted(expected + " " + info);
  } else {
    const parts = expected.split(",").map((s) => s.trim());
    if (parts.length === 2 && parts[1].startsWith("-")) {
      const singular = parts[0],
        suffix = parts[1].slice(1),
        base = singular.replace(/^(der|die|das)\s+/i, "");
      content = [
        singular,
        singular + " " + suffix,
        expected,
        singular + " " + base + suffix,
      ].some((s) => compact(s) === compact(answer));
    } else content = compact(expected) === compact(answer);
  }
  const expectedParts = expected.split(","),
    userParts = answer.split(",");
  const articleError =
    content &&
    expectedParts.some(
      (p, i) =>
        i < userParts.length &&
        article(p) &&
        (i === 0
          ? article(p) !== article(userParts[i])
          : article(userParts[i]) && article(p) !== article(userParts[i])),
    );
  return {
    correct: content && !articleError,
    articleError,
    sequenceError,
    partial,
  };
}
// Match the original web app exactly: shift six hours, then use a UTC date key.
export function logicalDay(now = Date.now()) {
  return new Date(now - 6 * 3600000).toISOString().slice(0, 10);
}
export const WORD_HEADERS = [
  "ID",
  "Активные слова",
  "Немецкое слово",
  "Перевод",
  "Формы глагола",
  "Дополнительно",
  "Пример 1",
  "Пример 2",
  "Папка",
];
export const IDIOM_HEADERS = [
  "ID",
  "Идиома",
  "Перевод",
  "Смысловой перевод",
  "Дополнительно",
  "Пример",
  "Папка",
];
export function toRows(list, kind) {
  return [
    kind === "idioms" ? IDIOM_HEADERS : WORD_HEADERS,
    ...list.map((w) =>
      kind === "idioms"
        ? [
            w.id,
            w.idiom || "",
            w.translation || "",
            w.meaning || "",
            w.info || "",
            w.example || "",
            w.folder || "",
          ]
        : [
            w.id,
            w.progress_global?.isActive
              ? 10
              : w.progress_global?.excellentStreak || 0,
            w.word || "",
            w.translation || "",
            w.info1 || "",
            w.info2 || "",
            w.ex1 || "",
            w.ex2 || "",
            w.folder || "",
          ],
    ),
  ];
}
export function importRows(rows, kind, existing = {}, now = Date.now()) {
  const header = (rows[0] || [])
    .map((v) => String(v || "").toLowerCase())
    .join(" ");
  if (
    String(rows[0]?.[0]).toLowerCase() === "id" &&
    ((/идиом|idiom|ідіом/.test(header) && kind === "words") ||
      (/активн|немецк|score/.test(header) && kind === "idioms"))
  )
    throw new Error(
      "Формат файлу не відповідає вкладці. Оберіть «Слова» або «Ідіоми».",
    );
  const updates = {};
  let created = 0,
    updated = 0;
  rows.forEach((row, i) => {
    if (!row?.some((v) => v !== null && v !== "" && v !== undefined)) return;
    if (i === 0 && String(row[0]).trim().toLowerCase() === "id") return;
    const values = row.map((v) => String(v ?? "").trim()),
      id = values[0];
    if (!id || /[.#$\[\]\/\x00-\x1f]/.test(id))
      throw new Error(`Рядок ${i + 1}: некоректний ID`);
    if (kind === "words" && (!/^\d+$/.test(id) || Number(id) >= 100000))
      throw new Error(
        `Рядок ${i + 1}: ID слова має бути числом від 0 до 99999`,
      );
    const old = existing[id] || {};
    const data =
      kind === "idioms"
        ? {
            idiom: values[1] || "",
            translation: values[2] || "",
            meaning: values[3] || "",
            info: values[4] || "",
            example: values[5] || "",
            folder:
              values[6] ||
              old.folder ||
              autoFolder(Object.values({ ...existing, ...updates })),
          }
        : {
            word: values[2] || "",
            translation: values[3] || "",
            info1: values[4] || "",
            info2: values[5] || "",
            ex1: values[6] || "",
            ex2: values[7] || "",
            folder:
              values[8] ||
              old.folder ||
              autoFolder(Object.values({ ...existing, ...updates })),
          };
    if (!(data.word || data.idiom) || !data.translation)
      throw new Error(`Рядок ${i + 1}: потрібні текст і переклад`);
    const p = old.progress_global || freshProgress(now);
    // Only an explicit score column updates an existing score. New words start new, as in the source.
    if (existing[id] && kind === "words") {
      let score =
        values[1]?.toLowerCase() === "yes" ? 10 : Number(values[1]) || 0;
      score = Math.min(10, Math.max(0, score));
      if (score !== (p.excellentStreak || 0))
        data.progress_global = {
          ...p,
          excellentStreak: score,
          isActive: score >= 10,
        };
    }
    if (!existing[id])
      Object.assign(data, {
        progress_global: p,
        ...(kind === "words"
          ? { progress_groups: freshProgress(now), interval: 0, nextDate: now }
          : {}),
      });
    updates[id] = { ...old, ...data, id };
    existing[id] ? updated++ : created++;
  });
  return { updates, created, updated };
}
export function sampleData() {
  const words = {};
  [
    ["1", "der Augenblick", "мить", "Momente", ""],
    [
      "2",
      "entdecken",
      "відкривати",
      "entdeckte, hat entdeckt",
      "Ich entdecke jeden Tag etwas Neues.",
    ],
    ["3", "die Möglichkeit", "можливість", "", ""],
    [
      "4",
      "sich erinnern",
      "пам’ятати",
      "erinnerte sich, hat sich erinnert",
      "Ich erinnere mich an diesen Tag.",
    ],
  ].forEach(
    ([id, word, translation, info1, ex1]) =>
      (words[id] = {
        id,
        word,
        translation,
        info1,
        ex1,
        folder: "Щодня",
        progress_global: {
          ...freshProgress(),
          excellentStreak: id === "3" ? 9 : 0,
        },
      }),
  );
  return {
    nickname: "Демо",
    words,
    idioms: {
      100000: {
        id: "100000",
        idiom: "Daumen drücken",
        translation: "тримати кулаки",
        meaning: "Бажати успіху",
        example: "Ich drücke dir die Daumen!",
        folder: "Вислови",
        progress_global: freshProgress(),
      },
    },
    settings: { study: { studyMode: "long", examples: true, audio: false } },
    stats: { daily: {} },
  };
}
