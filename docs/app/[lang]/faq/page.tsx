import type { Metadata } from "next";
import { isLocale, locales, type Locale } from "@/lib/i18n/config";
import { getDictionary } from "@/lib/i18n/dictionaries";
import { localizedUrl, pageAlternates } from "@/lib/i18n/seo";
import { breadcrumbSchema, faqSchema } from "@/lib/structuredData";
import { JsonLd } from "@/components/JsonLd";
import { Page } from "@/components/Page";
import { LINKS } from "@/lib/data";

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
  const d = getDictionary(locale);
  return {
    title: d.meta.faq.title,
    description: d.meta.faq.description,
    alternates: pageAlternates(locale, "/faq"),
    openGraph: {
      url: localizedUrl(locale, "/faq"),
      title: d.meta.faq.title,
      description: d.meta.faq.description,
    },
  };
}

export default async function FaqPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const locale: Locale = isLocale(lang) ? lang : "en";
  const d = getDictionary(locale);
  const fp = d.faqPage;

  return (
    <>
      <JsonLd data={faqSchema(d)} />
      <JsonLd
        data={breadcrumbSchema(locale, [
          { name: d.meta.siteName, path: "" },
          { name: d.nav.faq, path: "/faq" },
        ])}
      />
      <Page d={d} lang={locale} eyebrow={fp.eyebrow} title={fp.title} intro={fp.intro}>
        <div className="divide-y divide-line overflow-hidden rounded-2xl border border-line bg-ink-2/40">
          {fp.items.map((item, i) => (
            <details key={i} className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 px-6 py-5 transition-colors hover:bg-ink-3/50">
                <span className="font-display text-base font-medium tracking-tight text-snow">
                  {item.q}
                </span>
                <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full border border-line text-fog transition-all duration-300 group-open:rotate-45 group-open:border-acid group-open:text-acid">
                  <svg
                    viewBox="0 0 24 24"
                    className="h-3.5 w-3.5"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth={2.2}
                    strokeLinecap="round"
                  >
                    <path d="M12 5v14M5 12h14" />
                  </svg>
                </span>
              </summary>
              <div className="px-6 pb-5 text-sm leading-relaxed text-fog">
                {item.a}
              </div>
            </details>
          ))}
        </div>

        <div className="mt-8 flex flex-col items-start gap-3 rounded-2xl border border-acid/20 bg-acid/[0.04] p-6 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm text-mist">{fp.notFound}</p>
          <div className="flex gap-3">
            <a
              href={LINKS.github}
              target="_blank"
              rel="noreferrer noopener external"
              className="text-sm font-semibold text-snow underline-offset-4 hover:text-acid hover:underline"
            >
              {fp.askGithub}
            </a>
            <a
              href={LINKS.email}
              className="text-sm font-semibold text-snow underline-offset-4 hover:text-acid hover:underline"
            >
              {fp.emailUs}
            </a>
          </div>
        </div>
      </Page>
    </>
  );
}
