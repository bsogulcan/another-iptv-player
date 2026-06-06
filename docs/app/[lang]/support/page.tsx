import type { Metadata } from "next";
import { isLocale, locales, type Locale } from "@/lib/i18n/config";
import { getDictionary } from "@/lib/i18n/dictionaries";
import { buildOpenGraph, pageAlternates } from "@/lib/i18n/seo";
import { breadcrumbSchema } from "@/lib/structuredData";
import { JsonLd } from "@/components/JsonLd";
import { Page } from "@/components/Page";
import { LINKS } from "@/lib/data";
import { ArrowUpRight, GithubIcon } from "@/components/icons";

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
    title: d.meta.support.title,
    description: d.meta.support.description,
    alternates: pageAlternates(locale, "/support"),
    openGraph: buildOpenGraph(locale, {
      path: "/support",
      title: d.meta.support.title,
      description: d.meta.support.description,
    }),
  };
}

export default async function SupportPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const locale: Locale = isLocale(lang) ? lang : "en";
  const d = getDictionary(locale);
  const sp = d.supportPage;

  return (
    <>
      <JsonLd
        data={breadcrumbSchema(locale, [
          { name: d.meta.siteName, path: "" },
          { name: d.nav.support, path: "/support" },
        ])}
      />
      <Page d={d} lang={locale} eyebrow={sp.eyebrow} title={sp.title} intro={sp.intro}>
        <div className="grid gap-3 sm:grid-cols-3">
          {sp.notes.map((n) => (
            <div
              key={n.title}
              className="rounded-2xl border border-line bg-ink-2/40 p-6"
            >
              <h3 className="font-display text-base font-medium tracking-tight text-snow">
                {n.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-fog">{n.body}</p>
            </div>
          ))}
        </div>

        <h2 className="mt-16 font-display text-2xl font-semibold tracking-tight text-snow">
          {sp.howToTitle}
        </h2>
        <ol className="mt-6 space-y-4">
          {sp.howTo.map((step, i) => (
            <li key={i} className="flex gap-4">
              <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg border border-line bg-ink-3 font-display text-sm text-acid">
                {i + 1}
              </span>
              <p className="pt-1 leading-relaxed text-mist">{step}</p>
            </li>
          ))}
        </ol>

        <h2 className="mt-16 font-display text-2xl font-semibold tracking-tight text-snow">
          {sp.whyTitle}
        </h2>
        <ul className="mt-6 grid gap-3 sm:grid-cols-2">
          {sp.why.map((w) => (
            <li
              key={w}
              className="flex items-center gap-3 rounded-xl border border-line bg-ink-2/40 px-4 py-3.5 text-sm text-mist"
            >
              <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-acid" />
              {w}
            </li>
          ))}
        </ul>

        <div className="mt-16 rounded-2xl border border-line bg-ink-2/40 p-8 sm:p-10">
          <h2 className="font-display text-2xl font-semibold tracking-tight text-snow">
            {sp.needHelpTitle}
          </h2>
          <p className="mt-3 max-w-xl leading-relaxed text-fog">
            {sp.needHelpText}
          </p>
          <div className="mt-6 flex flex-wrap gap-3">
            <a
              href={LINKS.github}
              target="_blank"
              rel="noreferrer noopener external"
              className="inline-flex items-center gap-2 rounded-xl border border-line px-5 py-3 text-sm font-semibold text-snow transition-colors hover:border-fog"
            >
              <GithubIcon className="h-4 w-4" />
              {sp.githubBtn}
            </a>
            <a
              href={LINKS.email}
              className="inline-flex items-center gap-2 rounded-xl bg-acid px-5 py-3 text-sm font-semibold text-ink transition-transform hover:-translate-y-0.5"
            >
              bsogulcan@gmail.com
              <ArrowUpRight className="h-4 w-4" />
            </a>
          </div>
        </div>

        <p className="mt-10 text-sm leading-relaxed text-fog/70">{sp.disclaimer}</p>
      </Page>
    </>
  );
}
