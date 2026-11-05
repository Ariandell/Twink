import { speech, elevenClient } from "../audio";
const module = window.StudyModule;
if (module) {
  const originalSpeak = module.speakText.bind(module);
  module.stopAudio = function () {
    speech.stop();
    // Android WebView has native TTS, but may not expose Web Speech synthesis.
    // Keep the original cleanup without letting an absent browser API interrupt
    // showNextCard() or the flashcard's flip handler.
    this.currentSpeakId = (this.currentSpeakId || 0) + 1;
    if (this.currentAudio) {
      this.currentAudio.pause();
      this.currentAudio.currentTime = 0;
      this.currentAudio = null;
    }
    window.responsiveVoice?.cancel?.();
    window.speechSynthesis?.cancel?.();
    if (window.TwinkNative)
      TwinkNative.postMessage(JSON.stringify({ type: "stopAudio" }));
  };
  module.speakText = function (text, language = "de", complete) {
    if (!text || !this.settings.audio) {
      complete?.();
      return;
    }
    const selection =
      this.settings[language === "de" ? "selectAudioDe" : "selectAudioRu"] ||
      "";
    if (window.TwinkNative) {
      const requestId = `speech-${Date.now()}-${Math.random()}`;
      this.currentSpeakId = requestId;
      const finished = (e) => {
        if (e.detail?.id !== requestId) return;
        window.removeEventListener("twink-native-event", finished);
        if (this.currentSpeakId === requestId && this.settings.audio)
          complete?.();
      };
      window.addEventListener("twink-native-event", finished);
      TwinkNative.postMessage(
        JSON.stringify({
          type: "speak",
          id: requestId,
          text,
          language,
          settings: {
            ...this.settings,
            audioProvider:
              selection && !selection.startsWith("elevenlabs_")
                ? "system"
                : "elevenlabs",
          },
        }),
      );
      return;
    }
    if (selection && !selection.startsWith("elevenlabs_")) {
      originalSpeak(text, language, complete);
      return;
    }
    const id = (this.currentSpeakId || 0) + 1;
    this.currentSpeakId = id;
    speech
      .speak([{ text, language }], {
        ...this.settings,
        audioProvider: "elevenlabs",
      })
      .then(() => {
        if (this.currentSpeakId === id && this.settings.audio) complete?.();
      });
  };
  module.fetchElevenLabsQuota = async function () {
    const error = document.getElementById("elevenlabs-sync-error");
    try {
      const quota = await elevenClient.quota();
      localStorage.setItem("elevenlabs_chars", String(quota.used));
      const counter = document.getElementById("elevenlabs-char-count");
      if (counter) counter.textContent = Number(quota.used).toLocaleString();
      if (error) error.textContent = "";
    } catch {
      if (error) error.textContent = "Не удалось проверить лимит";
    }
  };
}
if (window.TwinkNative) {
  const click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (this.download && /^(blob:|data:)/.test(this.href)) {
      fetch(this.href)
        .then((r) => r.arrayBuffer())
        .then((bytes) => {
          let encoded = "";
          const data = new Uint8Array(bytes);
          for (let i = 0; i < data.length; i += 8192)
            encoded += String.fromCharCode(...data.subarray(i, i + 8192));
          TwinkNative.postMessage(
            JSON.stringify({
              type: "download",
              name: this.download,
              data: btoa(encoded),
            }),
          );
        });
      return;
    }
    return click.call(this);
  };
}
