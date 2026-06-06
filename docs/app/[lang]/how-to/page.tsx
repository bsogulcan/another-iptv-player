import type { Metadata } from "next";
import { isLocale, locales, type Locale } from "@/lib/i18n/config";
import { getDictionary } from "@/lib/i18n/dictionaries";
import { getHowTo } from "@/lib/i18n/howto";
import { buildOpenGraph, pageAlternates } from "@/lib/i18n/seo";
import { breadcrumbSchema, howToSchema } from "@/lib/structuredData";
import { JsonLd } from "@/components/JsonLd";
import { Page } from "@/components/Page";
import { HowToGallery } from "@/components/HowToGallery";

export function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ lang: string }>;
}): Promise<Metadata> {
  const { lang } = await params;
  const locale: Locale = isLocale(lang) ? lang : "en";
  const h = getHowTo(locale);
  return {
    title: h.metaTitle,
    description: h.metaDescription,
    alternates: pageAlternates(locale, "/how-to"),
    openGraph: buildOpenGraph(locale, {
      path: "/how-to",
      title: h.metaTitle,
      description: h.metaDescription,
    }),
  };
}

export default async function HowToPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const locale: Locale = isLocale(lang) ? lang : "en";
  const d = getDictionary(locale);
  const h = getHowTo(locale);

  return (
    <>
      <JsonLd data={howToSchema(h)} />
      <JsonLd
        data={breadcrumbSchema(locale, [
          { name: d.meta.siteName, path: "" },
          { name: d.nav.guide, path: "/how-to" },
        ])}
      />
      <Page
        d={d}
        lang={locale}
        eyebrow={h.eyebrow}
        title={h.title}
        intro={h.intro}
        contentClassName="max-w-5xl"
        showCoffee
      >
        <div className="space-y-14 sm:space-y-20">
          {h.steps.map((s, i) => (
            <div key={i}>
              <div className="flex max-w-2xl items-start gap-4">
                <span className="grid h-9 w-9 shrink-0 place-items-center rounded-lg border border-line bg-ink-3 font-display text-sm text-acid">
                  {String(i + 1).padStart(2, "0")}
                </span>
                <div>
                  <h2 className="font-display text-2xl font-semibold tracking-tight text-snow">
                    {s.title}
                  </h2>
                  <p className="mt-3 leading-relaxed text-fog">{s.body}</p>
                </div>
              </div>

              <HowToGallery images={s.images} alt={s.title} />
            </div>
          ))}
        </div>
      </Page>
    </>
  );
}
