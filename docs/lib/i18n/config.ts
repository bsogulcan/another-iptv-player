export const locales = [
  "en",
  "tr",
  "de",
  "es",
  "fr",
  "pt",
  "ru",
  "ar",
  "hi",
  "zh",
] as const;

export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = "en";

/** Right-to-left locales. */
export const rtlLocales: Locale[] = ["ar"];

export function dir(locale: Locale): "rtl" | "ltr" {
  return rtlLocales.includes(locale) ? "rtl" : "ltr";
}

/** BCP-47 tags used for <html lang>, hreflang and OpenGraph locale. */
export const htmlLang: Record<Locale, string> = {
  en: "en",
  tr: "tr",
  de: "de",
  es: "es",
  fr: "fr",
  pt: "pt",
  ru: "ru",
  ar: "ar",
  hi: "hi",
  zh: "zh",
};

export const ogLocale: Record<Locale, string> = {
  en: "en_US",
  tr: "tr_TR",
  de: "de_DE",
  es: "es_ES",
  fr: "fr_FR",
  pt: "pt_BR",
  ru: "ru_RU",
  ar: "ar_AR",
  hi: "hi_IN",
  zh: "zh_CN",
};

/** Native names shown in the language switcher. */
export const localeName: Record<Locale, string> = {
  en: "English",
  tr: "Türkçe",
  de: "Deutsch",
  es: "Español",
  fr: "Français",
  pt: "Português",
  ru: "Русский",
  ar: "العربية",
  hi: "हिन्दी",
  zh: "中文",
};

export function isLocale(value: string): value is Locale {
  return (locales as readonly string[]).includes(value);
}

export const SITE_URL = "https://another-iptv-player.com";
