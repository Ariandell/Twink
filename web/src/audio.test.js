import { describe, it, expect, vi } from "vitest";
import { ElevenClient, SpeechEngine } from "./audio";
import { DEFAULT_VOICE, speechPlan } from "./speech-plan";
const audio = () =>
  new Response(new Uint8Array([73, 68, 51, 1]), {
    status: 200,
    headers: { "Content-Type": "audio/mpeg" },
  });
describe("ElevenLabs", () => {
  it('binds the browser fetch receiver correctly',async()=>{vi.stubGlobal('fetch',function(){expect(this).toBe(globalThis);return Promise.resolve(audio());});try{await new ElevenClient({key:'test'}).synthesize('Hallo');}finally{vi.unstubAllGlobals();}});
  it("sends voice, language and model; identical requests reuse audio", async () => {
    let calls = 0;
    const client = new ElevenClient({
      key: "test-key",
      fetcher: async (url, options) => {
        calls++;
        expect(url).toContain(DEFAULT_VOICE);
        expect(options.headers["xi-api-key"]).toBe("test-key");
        expect(JSON.parse(options.body)).toEqual({
          text: "Hallo",
          model_id: "eleven_multilingual_v2",
          language_code: "de",
        });
        return audio();
      },
    });
    const [a, b] = await Promise.all([
      client.synthesize("Hallo"),
      client.synthesize("Hallo"),
    ]);
    expect(a.blob.size).toBe(4);
    expect(b.blob.size).toBe(4);
    expect(calls).toBe(1);
    expect((await client.synthesize("Hallo")).cached).toBe(true);
  });
  it("uses a persistent cache without another request", async () => {
    let requests = 0;
    const cache = new Map(),
      options = {
        key: "test",
        fetcher: async () => {
          requests++;
          return audio();
        },
        cache: {
          get: async (k) => cache.get(k),
          put: async (k, v) => cache.set(k, v),
        },
      };
    await new ElevenClient(options).synthesize("Hallo");
    expect((await new ElevenClient(options).synthesize("Hallo")).cached).toBe(
      true,
    );
    expect(requests).toBe(1);
  });
  it("replaces library voices requiring payment with George", async () => {
    const voices = [];
    const client = new ElevenClient({
      key: "test",
      fetcher: async (url) => {
        voices.push(url);
        return voices.length === 1
          ? new Response(
              JSON.stringify({ detail: { status: "payment_required" } }),
              { status: 402 },
            )
          : audio();
      },
    });
    expect(
      (await client.synthesize("Hallo", "de", "old-library-voice")).voice,
    ).toBe(DEFAULT_VOICE);
    await client.synthesize("Guten Tag", "de", "old-library-voice");
    expect(voices).toHaveLength(3);
    expect(voices[2]).toContain(DEFAULT_VOICE);
  });
  it("quota failure triggers a cooldown, but cached phrases still work", async () => {
    let calls = 0;
    const c = new ElevenClient({
      key: "test",
      now: () => 100,
      fetcher: async () =>
        ++calls === 1
          ? audio()
          : new Response(
              JSON.stringify({ detail: { status: "quota_exceeded" } }),
              { status: 401 },
            ),
    });
    await c.synthesize("cached");
    await expect(c.synthesize("new")).rejects.toMatchObject({
      code: "quota_exceeded",
    });
    await expect(c.synthesize("other")).rejects.toMatchObject({
      code: "temporarily_blocked",
    });
    expect((await c.synthesize("cached")).cached).toBe(true);
    expect(calls).toBe(2);
  });
  it("falls back to the system voice after a service error", async () => {
    const spoken = [];
    const engine = new SpeechEngine(
      {
        synthesize: async () => {
          throw Error("Unavailable");
        },
      },
      {
        stop() {},
        audio: async () => true,
        system: async (t, l) => {
          spoken.push([t, l]);
          return true;
        },
      },
    );
    await engine.speak([{ text: "Hallo", language: "de" }]);
    expect(spoken).toEqual([["Hallo", "de"]]);
  });
  it("never plays an old request after a new card or stop", async () => {
    let complete;
    const played = [];
    const engine = new SpeechEngine(
      { synthesize: () => new Promise((resolve) => (complete = resolve)) },
      {
        stop() {},
        audio: async (b) => {
          played.push(b);
          return true;
        },
        system: async () => true,
      },
    );
    const work = engine.speak([{ text: "old", language: "de" }]);
    engine.stop();
    complete({ blob: "old-audio" });
    await work;
    expect(played).toEqual([]);
  });
  it("a system-only choice never calls ElevenLabs", async () => {
    let calls = 0;
    const engine = new SpeechEngine(
      {
        synthesize: () => {
          calls++;
        },
      },
      { stop() {}, system: async () => true },
    );
    await engine.speak([{ text: "Hallo", language: "de" }], {
      audioProvider: "system",
    });
    expect(calls).toBe(0);
  });
  it("honors per-field controls and never reveals an answer on the front", () => {
    const w = {
      word: "entdecken",
      translation: "відкривати",
      info1: "entdeckte, hat entdeckt",
      info2: "Notiz",
      ex1: "Beispiel",
      ex2: "Інший приклад",
    };
    expect(speechPlan(w, { audioInfo2: false }).map((p) => p.text)).toEqual([
      "entdecken",
      "entdeckte, hat entdeckt",
    ]);
    expect(
      speechPlan(w, { audioEx1: true, audioEx2: true }).at(-1).language,
    ).toBe("uk");
    expect(speechPlan(w, { audioTranslationLanguage: "uk" }, "back")).toEqual([
      { text: "відкривати", language: "uk" },
    ]);
    expect(speechPlan(w, { audioTranslation: false }, "back")).toEqual([]);
  });
});
