import {
  defaultLocale,
  htmlLang,
  locales,
  SITE_URL,
  type Locale,
} from "./config";

/** Absolute, trailing-slashed URL for a locale + path ("" = home, "/faq", ...). */
export function localizedUrl(locale: Locale, path = ""): string {
  return `${SITE_URL}/${locale}${path}/`.replace(/\/{2,}$/, "/");
}

/** Locale-prefixed relative href for in-app links. */
export function localizedHref(locale: Locale, path = ""): string {
  return `/${locale}${path}`;
}

/** hreflang alternates + canonical for a given page path. */
export function pageAlternates(locale: Locale, path = "") {
  const languages: Record<string, string> = {};
  for (const l of locales) languages[htmlLang[l]] = localizedUrl(l, path);
  languages["x-default"] = localizedUrl(defaultLocale, path);
  return {
    canonical: localizedUrl(locale, path),
    languages,
  };
}
