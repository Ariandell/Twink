export const DEFAULT_VOICE = "JBFqnCBsd6RMkjVDRZzb";
export function speechLanguage(text, preferred = "ru") {
  return /[а-яіїєґё]/i.test(text)
    ? /[іїєґ]/i.test(text)
      ? "uk"
      : preferred
    : "de";
}
export function voiceFor(settings = {}, language = "de") {
  const value = settings[language === "de" ? "selectAudioDe" : "selectAudioRu"];
  return value?.startsWith("elevenlabs_") ? value.slice(11) : DEFAULT_VOICE;
}
export function speechPlan(word, settings = {}, side = "front") {
  const result = [],
    preferred = settings.audioTranslationLanguage || "ru";
  const add = (text, enabled = true, language) => {
    if (text && enabled)
      result.push({
        text: String(text),
        language: language || speechLanguage(String(text), preferred),
      });
  };
  if (side === "back") {
    add(word.translation, settings.audioTranslation !== false, preferred);
    add(word.meaning, settings.audioInfo1 !== false);
  } else {
    add(word.word || word.idiom, settings.audioWord !== false, "de");
    add(word.info1, settings.audioInfo1 !== false);
    add(word.info2 || word.info, settings.audioInfo2 !== false);
    add(word.ex1 || word.example, settings.audioEx1 === true);
    add(word.ex2, settings.audioEx2 === true);
  }
  return result;
}
