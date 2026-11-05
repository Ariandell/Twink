import { readFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";
import { describe, it, expect, vi } from "vitest";

function nativeSession({ synthesis = undefined, audio = true } = {}) {
  const nodes = new Map(), messages = [], timers = [], listeners = new Map();
  function element(id) {
    if (!nodes.has(id)) {
      const classes = new Set();
      nodes.set(id, {
        style: {}, textContent: "", innerHTML: "", dataset: {},
        classList: {
          add: (c) => classes.add(c), remove: (c) => classes.delete(c),
          contains: (c) => classes.has(c),
          toggle(c, force = !classes.has(c)) {
            if (force) classes.add(c); else classes.delete(c);
            return force;
          },
        },
        querySelectorAll: () => [],
      });
    }
    return nodes.get(id);
  }
  const rates = [1, 2, 3, 4, 5, 6].map((rating) => {
    const button = element(`rating-${rating}`);
    button.dataset.rating = String(rating);
    button.classList.add("btn-rate");
    return button;
  });
  element("rating-buttons").classList.add("hidden");
  const storage = new Map();
  const services = {
    speech: { stop: vi.fn(), speak: vi.fn(async () => {}) },
    elevenClient: { quota: vi.fn() },
  };
  const context = createContext({
    console,
    document: {
      getElementById: element,
      querySelector: element,
      querySelectorAll: (selector) => selector === ".btn-rate" ? rates : [],
    },
    localStorage: {
      getItem: (key) => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: (key) => storage.delete(key),
    },
    setTimeout: (fn) => timers.push(fn),
    speechSynthesis: synthesis,
    TwinkNative: { postMessage: (value) => messages.push(JSON.parse(value)) },
    HTMLAnchorElement: class { click() {} },
    addEventListener: (type, fn) => {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(fn);
    },
    removeEventListener: (type, fn) => listeners.get(type)?.delete(fn),
    __services: services,
  });
  context.window = context;
  runInContext(readFileSync(new URL("../../public/classic/study.js", import.meta.url), "utf8"), context);
  const bridge = readFileSync(new URL("./bridge-entry.js", import.meta.url), "utf8")
    .replace(/^import .*?;\r?\n/, "const { speech, elevenClient } = __services;\n");
  runInContext(bridge, context);
  const study = context.StudyModule;
  const words = [
    { id: 1, word: "der Hügel", translation: "холм", ex1: "Auf dem Hügel steht ein Haus." },
    { id: 2, word: "das Haus", translation: "дом" },
  ];
  study.settings.audio = audio;
  study.allWordsCache = words;
  study.db = { updateProgress: vi.fn(async () => {}) };
  study.currentSession = {
    mode: "global", groupIndex: null, key: "progress_global",
    currentIndex: 0, queue: words, history: [],
  };
  study.initSessionControls();
  return { study, messages, rates, services, timers, nodes };
}

describe("Original study controls in Android WebView without browser speech synthesis", () => {
  it("reveals all six ratings and fills both card faces with audio enabled", () => {
    const { study, rates, messages, timers } = nativeSession();
    study.showNextCard();
    timers.forEach((fn) => fn());
    expect(study.ratingButtons.classList.contains("hidden")).toBe(false);
    expect(study.ratingButtons.style.pointerEvents).toBe("auto");
    expect(rates).toHaveLength(6);
    expect(study.cardTranslation.textContent).toBe("холм");
    expect(messages.some((m) => m.type === "speak" && m.language === "de")).toBe(true);
  });

  it.each([true, false])("flips front and back when audio is %s", (audio) => {
    const { study, messages } = nativeSession({ audio });
    study.currentSession.currentWord = study.currentSession.queue[0];
    study.flashcard.onclick();
    expect(study.flashcard.classList.contains("is-flipped")).toBe(true);
    study.flashcard.onclick();
    expect(study.flashcard.classList.contains("is-flipped")).toBe(false);
    expect(messages.filter((m) => m.type === "stopAudio").length).toBeGreaterThanOrEqual(2);
  });

  it("advances on rating, keeps controls active, and supports undo with audio enabled", async () => {
    const { study, rates } = nativeSession();
    study.showNextCard();
    await rates[4].onclick({ stopPropagation() {}, target: rates[4] });
    expect(study.currentSession.currentWord.id).toBe(2);
    expect(study.ratingButtons.style.pointerEvents).toBe("auto");
    study.btnExitSession.onclick();
    expect(study.currentSession.currentWord.id).toBe(1);
    expect(study.currentSession.history).toHaveLength(0);
    expect(study.ratingButtons.classList.contains("hidden")).toBe(false);
  });

  it("still cancels browser speech and legacy audio when those APIs exist", () => {
    const synthesis = { cancel: vi.fn() };
    const { study, services } = nativeSession({ synthesis });
    const legacy = { pause: vi.fn(), currentTime: 5 };
    study.currentAudio = legacy;
    study.stopAudio();
    expect(synthesis.cancel).toHaveBeenCalled();
    expect(legacy.pause).toHaveBeenCalled();
    expect(legacy.currentTime).toBe(0);
    expect(study.currentAudio).toBeNull();
    expect(services.speech.stop).toHaveBeenCalled();
  });
});
