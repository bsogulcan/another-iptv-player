import type { Metadata } from "next";
import { isLocale, locales, type Locale } from "@/lib/i18n/config";
import { getDictionary } from "@/lib/i18n/dictionaries";
import { localizedUrl, pageAlternates } from "@/lib/i18n/seo";
import { homeGraph } from "@/lib/structuredData";
import { JsonLd } from "@/components/JsonLd";
import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { Marquee } from "@/components/Marquee";
import { Features } from "@/components/Features";
import { Screenshots } from "@/components/Screenshots";
import { HowItWorks } from "@/components/HowItWorks";
import { Download } from "@/components/Download";
import { Support } from "@/components/Support";
import { Footer } from "@/components/Footer";

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
    title: d.meta.home.title,
    description: d.meta.home.description,
    alternates: pageAlternates(locale, ""),
    openGraph: { url: localizedUrl(locale, "") },
  };
}

export default async function Home({
  params,
}: {
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const locale: Locale = isLocale(lang) ? lang : "en";
  const d = getDictionary(locale);

  return (
    <>
      <JsonLd data={homeGraph(locale, d)} />
      <Nav d={d} lang={locale} />
      <main>
        <Hero d={d} />
        <Marquee words={d.marquee} />
        <Features d={d} />
        <Screenshots d={d} />
        <HowItWorks d={d} />
        <Download d={d} />
        <Support d={d} />
      </main>
      <Footer d={d} lang={locale} />
    </>
  );
}
