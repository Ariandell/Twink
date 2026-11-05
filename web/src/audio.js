import { elevenLabsKey } from "./elevenlabs-config";
import { DEFAULT_VOICE, voiceFor } from "./speech-plan";

const MODEL = "eleven_multilingual_v2";
export class SpeechError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}
export class ElevenClient {
  constructor({
    key = elevenLabsKey,
    fetcher = globalThis.fetch?.bind(globalThis),
    cache = null,
    now = Date.now,
  } = {}) {
    this.key = key;
    this.fetcher = fetcher;
    this.cache = cache;
    this.now = now;
    this.memory = new Map();
    this.pending = new Map();
    this.blockedUntil = 0;
    this.unavailableVoices = new Set();
  }
  async synthesize(text, language = "de", voice = DEFAULT_VOICE) {
    text = String(text || "").trim();
    if (!text) return null;
    if (text.length > 2000)
      throw new SpeechError(
        "text_too_long",
        "Цей фрагмент завеликий для хмарного озвучення.",
      );
    const cacheKey = JSON.stringify([MODEL, voice, language, text]);
    if (this.memory.has(cacheKey))
      return { blob: this.memory.get(cacheKey), cached: true };
    if (this.pending.has(cacheKey)) return this.pending.get(cacheKey);
    const work = this._get(text, language, voice, cacheKey);
    this.pending.set(cacheKey, work);
    try {
      return await work;
    } finally {
      this.pending.delete(cacheKey);
    }
  }
  async _get(text, language, voice, cacheKey) {
    const stored = await this.cache?.get(cacheKey).catch(() => null);
    if (stored) {
      this.remember(cacheKey, stored);
      return { blob: stored, cached: true };
    }
    if (this.blockedUntil > this.now())
      throw new SpeechError(
        "temporarily_blocked",
        "ElevenLabs тимчасово недоступний. Працює системний голос.",
      );
    if (!this.key)
      throw new SpeechError("missing_key", "Ключ ElevenLabs не налаштовано.");
    let actualVoice = this.unavailableVoices.has(voice) ? DEFAULT_VOICE : voice;
    let response = await this.request(text, language, actualVoice);
    if (response.status === 402 && actualVoice !== DEFAULT_VOICE) {
      this.unavailableVoices.add(actualVoice);
      actualVoice = DEFAULT_VOICE;
      response = await this.request(text, language, actualVoice);
    }
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      const code = detail.detail?.status || `http_${response.status}`;
      if (code === "quota_exceeded" || code === "character_limit_exceeded")
        this.blockedUntil = this.now() + 10 * 60000;
      else if (response.status === 429) this.blockedUntil = this.now() + 30000;
      else if (
        response.status === 401 ||
        response.status === 403 ||
        response.status === 402
      )
        this.blockedUntil = this.now() + 60000;
      throw new SpeechError(
        code,
        code.includes("quota") || code.includes("limit")
          ? "Ліміт ElevenLabs вичерпано. Працює системний голос."
          : response.status === 402
            ? "Цей тариф не дозволяє генерацію. Працює системний голос."
            : "ElevenLabs недоступний. Працює системний голос.",
      );
    }
    const blob = await response.blob();
    if (
      !blob.size ||
      !(response.headers.get("content-type") || "").startsWith("audio/")
    )
      throw new SpeechError(
        "invalid_audio",
        "ElevenLabs повернув некоректне аудіо.",
      );
    this.remember(cacheKey, blob);
    await this.cache?.put(cacheKey, blob).catch(() => {});
    return { blob, cached: false, voice: actualVoice };
  }
  request(text, language, voice) {
    return this.fetcher(
      `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voice)}?output_format=mp3_44100_128`,
      {
        method: "POST",
        headers: {
          "xi-api-key": this.key,
          "Content-Type": "application/json",
          Accept: "audio/mpeg",
        },
        body: JSON.stringify({
          text,
          model_id: MODEL,
          language_code: language,
        }),
        signal: AbortSignal.timeout(25000),
      },
    );
  }
  remember(key, blob) {
    this.memory.set(key, blob);
    if (this.memory.size > 64)
      this.memory.delete(this.memory.keys().next().value);
  }
  async quota() {
    const r = await this.fetcher(
      "https://api.elevenlabs.io/v1/user/subscription",
      {
        headers: { "xi-api-key": this.key },
        signal: AbortSignal.timeout(10000),
      },
    );
    if (!r.ok)
      throw new SpeechError(
        "quota_unavailable",
        "Ліміт недоступний для перегляду цим ключем.",
      );
    const q = await r.json();
    this.blockedUntil = 0;
    return { used: q.character_count, limit: q.character_limit };
  }
}
const diskCache = {
  async url(key) {
    const hash = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(key),
    );
    return new URL(
      "/__twink_audio/" +
        Array.from(new Uint8Array(hash), (b) =>
          b.toString(16).padStart(2, "0"),
        ).join(""),
      location.origin,
    ).href;
  },
  async get(key) {
    if (!globalThis.caches) return null;
    const response = await (
      await caches.open("twink-tts-v1")
    ).match(await this.url(key));
    return response ? response.blob() : null;
  },
  async put(key, blob) {
    if (!globalThis.caches) return;
    const cache = await caches.open("twink-tts-v1");
    await cache.put(
      await this.url(key),
      new Response(blob, { headers: { "Content-Type": "audio/mpeg" } }),
    );
    const keys = await cache.keys();
    for (const key of keys.slice(0, Math.max(0, keys.length - 128)))
      await cache.delete(key);
  },
};
export class SpeechEngine {
  constructor(client, player) {
    this.client = client;
    this.player = player;
    this.generation = 0;
    this.status = "ElevenLabs";
    this.listeners = new Set();
  }
  statusChanged(value) {
    this.status = value;
    for (const fn of this.listeners) fn(value);
  }
  stop() {
    this.generation++;
    this.player.stop();
  }
  async speak(plan, settings = {}) {
    const ticket = ++this.generation;
    this.player.stop();
    for (const item of plan) {
      if (ticket !== this.generation) return;
      const voice = voiceFor(settings, item.language);
      if (settings.audioProvider === "system") {
        this.statusChanged("Системний голос");
        if (!(await this.player.system(item.text, item.language))) return;
        continue;
      }
      try {
        this.statusChanged("Готуємо ElevenLabs…");
        const audio = await this.client.synthesize(
          item.text,
          item.language,
          voice,
        );
        if (ticket !== this.generation) return;
        if (!audio) continue;
        this.statusChanged(audio.cached ? "ElevenLabs · з кешу" : "ElevenLabs");
        if (!(await this.player.audio(audio.blob))) return;
      } catch (e) {
        if (ticket !== this.generation) return;
        this.statusChanged(
          e instanceof SpeechError?e.message:"ElevenLabs недоступний. Працює системний голос.",
        );
        if (!(await this.player.system(item.text, item.language))) return;
      }
    }
  }
}
let currentAudio, resolveCurrent, currentUrl;
const browserPlayer = {
  stop() {
    resolveCurrent?.(false);
    resolveCurrent = null;
    if (currentAudio) {
      currentAudio.pause();
      currentAudio.removeAttribute("src");
      currentAudio.load();
      currentAudio = null;
    }
    if (currentUrl) {
      URL.revokeObjectURL(currentUrl);
      currentUrl = null;
    }
    globalThis.speechSynthesis?.cancel();
  },
  async audio(blob) {
    return new Promise((resolve) => {
      resolveCurrent = resolve;
      currentUrl = URL.createObjectURL(blob);
      const audio = (currentAudio = new Audio(currentUrl));
      audio.onended = () => {
        resolveCurrent = null;
        resolve(true);
      };
      audio.onerror = () => {
        resolveCurrent = null;
        resolve(false);
      };
      audio.play().catch(() => {
        resolveCurrent = null;
        resolve(false);
      });
    });
  },
  async system(text, language) {
    if (!globalThis.speechSynthesis) return false;
    return new Promise((resolve) => {
      resolveCurrent = resolve;
      const u = new SpeechSynthesisUtterance(text);
      u.lang = { de: "de-DE", ru: "ru-RU", uk: "uk-UA" }[language] || language;
      u.rate = 0.9;
      u.onend = () => {
        resolveCurrent = null;
        resolve(true);
      };
      u.onerror = () => {
        resolveCurrent = null;
        resolve(false);
      };
      speechSynthesis.speak(u);
    });
  },
};
export const elevenClient = new ElevenClient({ cache: diskCache });
export const speech = new SpeechEngine(elevenClient, browserPlayer);
