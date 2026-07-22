import { settings } from "../data/settings";
import { PlayerPort, TrackInfo } from "./PlayerPort";

// Persisted audio/subtitle language preference (iOS PlaybackTrackPreferences):
// after prepare, auto-select the track whose language matches; when the user
// picks a track manually, remember its language for future playback. An
// explicit "subtitles off" choice is remembered too (iOS __off__ sentinel).

export const SUBTITLE_OFF = "__off__";

function normalize(language: string | undefined): string | undefined {
  if (!language) return undefined;
  const lower = language.trim().toLowerCase();
  if (lower === "") return undefined;
  // Collapse ISO 639-2/B vs T duplicates commonly seen in streams.
  const aliases: { [key: string]: string } = {
    tur: "tr",
    tr: "tr",
    eng: "en",
    en: "en",
    ger: "de",
    deu: "de",
    de: "de",
    fre: "fr",
    fra: "fr",
    fr: "fr",
    spa: "es",
    es: "es",
    ara: "ar",
    ar: "ar",
    rus: "ru",
    ru: "ru",
    por: "pt",
    pt: "pt",
    hin: "hi",
    hi: "hi",
    chi: "zh",
    zho: "zh",
    zh: "zh",
  };
  return aliases[lower] ?? lower;
}

function findByLanguage(
  tracks: TrackInfo[],
  preferred: string | null,
): TrackInfo | undefined {
  const wanted = normalize(preferred ?? undefined);
  if (!wanted) return undefined;
  return tracks.find((track) => normalize(track.language) === wanted);
}

/**
 * Applies persisted language preferences right after `prepared`.
 * Returns whether app-drawn subtitles should render: an explicit "off"
 * preference — or no preference at all — keeps them hidden even when AVPlay
 * auto-selects a text track.
 */
export function applyTrackPreferences(player: PlayerPort): {
  textEnabled: boolean;
} {
  const tracks = player.getTracks();

  const audio = findByLanguage(
    tracks.filter((track) => track.type === "AUDIO"),
    settings.preferredAudioLanguage,
  );
  if (audio) player.selectTrack("AUDIO", audio.index);

  const subtitlePref = settings.preferredSubtitleLanguage;
  if (subtitlePref === null || subtitlePref === SUBTITLE_OFF) {
    return { textEnabled: false };
  }
  const text = findByLanguage(
    tracks.filter((track) => track.type === "TEXT"),
    subtitlePref,
  );
  if (text) {
    player.selectTrack("TEXT", text.index);
    return { textEnabled: true };
  }
  return { textEnabled: false };
}

/** Records a manual selection as the new preference. */
export function rememberTrackSelection(track: TrackInfo): void {
  const language = normalize(track.language);
  if (track.type === "AUDIO") {
    if (language) settings.preferredAudioLanguage = language;
  } else if (track.type === "TEXT") {
    // Selecting any text track re-enables subtitles even without a language
    // tag; a missing tag stores nothing but still clears an "off" state.
    settings.preferredSubtitleLanguage = language ?? null;
  }
}

/** Records an explicit "subtitles off" choice (iOS __off__ sentinel). */
export function rememberSubtitlesOff(): void {
  settings.preferredSubtitleLanguage = SUBTITLE_OFF;
}
