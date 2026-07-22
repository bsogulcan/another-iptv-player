import ar from "./locales/ar.json";
import de from "./locales/de.json";
import en from "./locales/en.json";
import es from "./locales/es.json";
import fr from "./locales/fr.json";
import hi from "./locales/hi.json";
import pt from "./locales/pt.json";
import ru from "./locales/ru.json";
import tr from "./locales/tr.json";
import zh from "./locales/zh.json";
import { settings } from "../data/settings";
import { TV_EXTRAS } from "./tvExtras";

// Runtime language switching with English fallback, mirroring the iOS L()
// helper. Framework-free core; React screens subscribe for re-render.

export const SUPPORTED_LANGUAGES = [
  "ar",
  "de",
  "en",
  "es",
  "fr",
  "hi",
  "pt",
  "ru",
  "tr",
  "zh",
] as const;

export type Language = (typeof SUPPORTED_LANGUAGES)[number];

const CATALOGS: Record<Language, Record<string, string>> = {
  ar,
  de,
  en,
  es,
  fr,
  hi,
  pt,
  ru,
  tr,
  zh,
};

const RTL_LANGUAGES: ReadonlySet<string> = new Set(["ar"]);

function systemLanguage(): Language {
  const raw =
    typeof navigator !== "undefined" ? navigator.language || "en" : "en";
  const prefix = raw.toLowerCase().split("-")[0];
  return (SUPPORTED_LANGUAGES as readonly string[]).includes(prefix)
    ? (prefix as Language)
    : "en";
}

let current: Language = (() => {
  const saved = settings.language;
  return saved && (SUPPORTED_LANGUAGES as readonly string[]).includes(saved)
    ? (saved as Language)
    : systemLanguage();
})();

const subscribers = new Set<() => void>();

function applyDirection(language: Language): void {
  if (typeof document !== "undefined") {
    document.documentElement.dir = RTL_LANGUAGES.has(language) ? "rtl" : "ltr";
    document.documentElement.lang = language;
  }
}

applyDirection(current);

export function getLanguage(): Language {
  return current;
}

/** Pass null to follow the system language again. */
export function setLanguage(language: Language | null): void {
  settings.language = language;
  current = language ?? systemLanguage();
  applyDirection(current);
  for (const notify of Array.from(subscribers)) notify();
}

export function subscribeLanguage(listener: () => void): () => void {
  subscribers.add(listener);
  return () => subscribers.delete(listener);
}

/** Looks up a key in the active catalog with en → key fallback. */
export function t(key: string, ...args: (string | number)[]): string {
  const template =
    CATALOGS[current][key] ??
    TV_EXTRAS[current]?.[key] ??
    CATALOGS.en[key] ??
    TV_EXTRAS.en[key] ??
    key;
  if (args.length === 0) return template;
  return template.replace(/\{(\d+)\}/g, (match, index) => {
    const value = args[Number(index)];
    return value === undefined ? match : String(value);
  });
}
