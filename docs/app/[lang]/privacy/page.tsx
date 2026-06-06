import type { Metadata } from "next";
import { isLocale, locales, type Locale } from "@/lib/i18n/config";
import { getDictionary } from "@/lib/i18n/dictionaries";
import { buildOpenGraph, pageAlternates } from "@/lib/i18n/seo";
import { breadcrumbSchema } from "@/lib/structuredData";
import { JsonLd } from "@/components/JsonLd";
import { Page } from "@/components/Page";
import { LINKS } from "@/lib/data";

const LAST_UPDATED = "2026-06-06";

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
    title: d.meta.privacy.title,
    description: d.meta.privacy.description,
    alternates: pageAlternates(locale, "/privacy"),
    openGraph: buildOpenGraph(locale, {
      path: "/privacy",
      title: d.meta.privacy.title,
      description: d.meta.privacy.description,
    }),
  };
}

function Block({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="border-t border-line py-8 first:border-t-0 first:pt-0">
      <h2 className="font-display text-xl font-semibold tracking-tight text-snow">
        {title}
      </h2>
      <div className="mt-3 space-y-3 leading-relaxed text-fog">{children}</div>
    </section>
  );
}

export default async function PrivacyPage({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const locale: Locale = isLocale(lang) ? lang : "en";
  const d = getDictionary(locale);
  const pp = d.privacyPage;
  const b = pp.blocks;
  const dateStr = new Intl.DateTimeFormat(locale, {
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(new Date(LAST_UPDATED));

  const ghLink = (
    <a
      href={LINKS.github}
      target="_blank"
      rel="noreferrer noopener external"
      className="text-snow underline underline-offset-4 hover:text-acid"
    >
      {b.openSource.link}
    </a>
  );

  return (
    <>
      <JsonLd
        data={breadcrumbSchema(locale, [
          { name: d.meta.siteName, path: "" },
          { name: pp.eyebrow, path: "/privacy" },
        ])}
      />
      <Page
        d={d}
        lang={locale}
        eyebrow={pp.eyebrow}
        title={pp.title}
        intro={`${pp.lastUpdated}: ${dateStr}`}
      >
        <Block title={b.app.title}>
          <p>{b.app.intro}</p>
          <ul className="space-y-2">
            {b.app.points.map((t) => (
              <li key={t} className="flex gap-3">
                <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-acid" />
                <span>{t}</span>
              </li>
            ))}
          </ul>
        </Block>

        <Block title={b.website.title}>
          <p>{b.website.p1}</p>
          <p>{b.website.p2}</p>
        </Block>

        <Block title={b.thirdParty.title}>
          <p>{b.thirdParty.p1}</p>
        </Block>

        <Block title={b.openSource.title}>
          <p>
            {b.openSource.before}
            {ghLink}
            {b.openSource.after}
          </p>
        </Block>

        <Block title={b.changes.title}>
          <p>{b.changes.p1}</p>
        </Block>

        <Block title={b.contact.title}>
          <p>
            {b.contact.before}
            {ghLink}
            {b.contact.middle}
            <a
              href={LINKS.email}
              className="text-snow underline underline-offset-4 hover:text-acid"
            >
              bsogulcan@gmail.com
            </a>
            {b.contact.after}
          </p>
        </Block>
      </Page>
    </>
  );
}
