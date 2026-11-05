if (window.TwinkNative) {
  let active = null;
  class NativeRecognition {
    constructor() {
      this.lang = "ru-RU";
      this.continuous = true;
      this.interimResults = false;
    }
    start() {
      active = this;
      TwinkNative.postMessage(
        JSON.stringify({ type: "startRecognition", language: this.lang }),
      );
    }
    stop() {
      TwinkNative.postMessage(JSON.stringify({ type: "stopRecognition" }));
    }
    abort() {
      this.stop();
    }
  }
  window.SpeechRecognition = NativeRecognition;
  window.addEventListener("twink-native-event", (event) => {
    if (!active) return;
    if (event.detail?.type === "recognition") {
      const result = [{ transcript: event.detail.text, confidence: 1 }];
      result.isFinal = true;
      active.onresult?.({ results: [result], resultIndex: 0 });
    }
    if (event.detail?.type === "recognitionEnd") active.onend?.();
    if (event.detail?.type === "recognitionError")
      active.onerror?.({ error: event.detail.error });
  });
}
