import { LINKS } from "./data";
import { SITE_URL, type Locale } from "./i18n/config";
import { localizedUrl } from "./i18n/seo";
import type { Dictionary } from "./i18n/dictionaries/en";

const ORG_ID = `${SITE_URL}/#org`;
const SITE_ID = `${SITE_URL}/#website`;
const APP_ID = `${SITE_URL}/#app`;

export function organizationSchema() {
  return {
    "@type": "Organization",
    "@id": ORG_ID,
    name: "Another IPTV Player",
    url: SITE_URL,
    logo: `${SITE_URL}/logo.png`,
    sameAs: [LINKS.github],
  };
}

export function websiteSchema(locale: Locale) {
  return {
    "@type": "WebSite",
    "@id": SITE_ID,
    name: "Another IPTV Player",
    url: SITE_URL,
    inLanguage: locale,
    publisher: { "@id": ORG_ID },
  };
}

export function softwareAppSchema(d: Dictionary) {
  return {
    "@type": "SoftwareApplication",
    "@id": APP_ID,
    name: "Another IPTV Player",
    operatingSystem: "iOS, iPadOS, Android, macOS, Windows, Linux",
    applicationCategory: "MultimediaApplication",
    description: d.meta.home.description,
    url: SITE_URL,
    image: `${SITE_URL}/logo.png`,
    downloadUrl: LINKS.releases,
    softwareVersion: "latest",
    license: "https://opensource.org/licenses/MIT",
    isAccessibleForFree: true,
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD",
    },
    publisher: { "@id": ORG_ID },
  };
}

export function homeGraph(locale: Locale, d: Dictionary) {
  return {
    "@context": "https://schema.org",
    "@graph": [
      organizationSchema(),
      websiteSchema(locale),
      softwareAppSchema(d),
    ],
  };
}

export function faqSchema(d: Dictionary) {
  return {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: d.faqPage.items.map((it) => ({
      "@type": "Question",
      name: it.q,
      acceptedAnswer: { "@type": "Answer", text: it.a },
    })),
  };
}

export function breadcrumbSchema(
  locale: Locale,
  trail: { name: string; path: string }[]
) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: trail.map((t, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: t.name,
      item: localizedUrl(locale, t.path),
    })),
  };
}
