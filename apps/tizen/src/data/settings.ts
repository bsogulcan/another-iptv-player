// Typed localStorage wrapper for app-global settings (the iOS UserDefaults
// equivalents). Playlist-scoped data lives in IndexedDB instead.

const PREFIX = "aiptv.";

interface SettingsShape {
  lastPlaylistId: string | null;
  language: string | null; // null = follow system
  dashboardTab: number;
  autoPlayNextEpisode: boolean;
  preferredAudioLanguage: string | null;
  preferredSubtitleLanguage: string | null;
}

const DEFAULTS: SettingsShape = {
  lastPlaylistId: null,
  language: null,
  dashboardTab: 0,
  autoPlayNextEpisode: true,
  preferredAudioLanguage: null,
  preferredSubtitleLanguage: null,
};

function read<K extends keyof SettingsShape>(key: K): SettingsShape[K] {
  try {
    const raw = localStorage.getItem(PREFIX + key);
    if (raw === null) return DEFAULTS[key];
    return JSON.parse(raw) as SettingsShape[K];
  } catch {
    return DEFAULTS[key];
  }
}

function write<K extends keyof SettingsShape>(
  key: K,
  value: SettingsShape[K],
): void {
  try {
    if (value === null) {
      localStorage.removeItem(PREFIX + key);
    } else {
      localStorage.setItem(PREFIX + key, JSON.stringify(value));
    }
  } catch (err) {
    console.warn(`[settings] failed to persist ${key}`, err);
  }
}

export const settings = {
  get lastPlaylistId() {
    return read("lastPlaylistId");
  },
  set lastPlaylistId(value: string | null) {
    write("lastPlaylistId", value);
  },
  get language() {
    return read("language");
  },
  set language(value: string | null) {
    write("language", value);
  },
  get dashboardTab() {
    return read("dashboardTab");
  },
  set dashboardTab(value: number) {
    write("dashboardTab", value);
  },
  get autoPlayNextEpisode() {
    return read("autoPlayNextEpisode");
  },
  set autoPlayNextEpisode(value: boolean) {
    write("autoPlayNextEpisode", value);
  },
  get preferredAudioLanguage() {
    return read("preferredAudioLanguage");
  },
  set preferredAudioLanguage(value: string | null) {
    write("preferredAudioLanguage", value);
  },
  get preferredSubtitleLanguage() {
    return read("preferredSubtitleLanguage");
  },
  set preferredSubtitleLanguage(value: string | null) {
    write("preferredSubtitleLanguage", value);
  },
};
