import type { MetadataRoute } from "next";
import { defaultLocale, htmlLang, locales } from "@/lib/i18n/config";
import { localizedUrl } from "@/lib/i18n/seo";

export const dynamic = "force-static";

const paths = ["", "/faq", "/support", "/privacy"];

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  return paths.flatMap((path) =>
    locales.map((locale) => ({
      url: localizedUrl(locale, path),
      lastModified: now,
      changeFrequency: "monthly" as const,
      priority: path === "" ? 1 : 0.7,
      alternates: {
        languages: {
          ...Object.fromEntries(
            locales.map((l) => [htmlLang[l], localizedUrl(l, path)])
          ),
          "x-default": localizedUrl(defaultLocale, path),
        },
      },
    }))
  );
}
