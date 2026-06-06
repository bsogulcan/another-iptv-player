import type { Metadata } from "next";
import {
  defaultLocale,
  htmlLang,
  locales,
  ogLocale,
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

/**
 * Full Open Graph object for a page. Next replaces (does not deep-merge)
 * `openGraph` when a page sets it, so each page must supply the complete object
 * — otherwise the layout's image/locale/type are dropped.
 */
export function buildOpenGraph(
  locale: Locale,
  opts: { path?: string; title: string; description: string }
): Metadata["openGraph"] {
  return {
    type: "website",
    siteName: "Another IPTV Player",
    locale: ogLocale[locale],
    alternateLocale: locales
      .filter((l) => l !== locale)
      .map((l) => ogLocale[l]),
    url: localizedUrl(locale, opts.path ?? ""),
    title: opts.title,
    description: opts.description,
    images: [{ url: "/og.png", width: 1200, height: 630 }],
  };
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
