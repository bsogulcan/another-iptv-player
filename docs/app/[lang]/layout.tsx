import type { Metadata, Viewport } from "next";
import { Analytics } from "@/components/Analytics";
import {
  dir,
  htmlLang,
  isLocale,
  locales,
  ogLocale,
  SITE_URL,
  type Locale,
} from "@/lib/i18n/config";
import { getDictionary } from "@/lib/i18n/dictionaries";
import "../globals.css";

export const dynamicParams = false;

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
    metadataBase: new URL(SITE_URL),
    title: {
      default: d.meta.home.title,
      template: `%s`,
    },
    description: d.meta.home.description,
    applicationName: d.meta.siteName,
    keywords: [
      "IPTV player",
      "open source IPTV",
      "Xtream Codes",
      "M3U player",
      "free IPTV",
      "offline IPTV downloads",
      "iOS Android Windows macOS Linux IPTV",
    ],
    authors: [{ name: "ogulcan ozcan" }],
    openGraph: {
      type: "website",
      siteName: d.meta.siteName,
      locale: ogLocale[locale],
      alternateLocale: locales
        .filter((l) => l !== locale)
        .map((l) => ogLocale[l]),
      title: d.meta.home.title,
      description: d.meta.home.description,
      images: [{ url: "/og.png", width: 1200, height: 630 }],
    },
    twitter: {
      card: "summary_large_image",
      title: d.meta.home.title,
      description: d.meta.home.description,
      images: ["/og.png"],
    },
    robots: {
      index: true,
      follow: true,
      googleBot: { index: true, follow: true, "max-image-preview": "large" },
    },
  };
}

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#fbfbf9" },
    { media: "(prefers-color-scheme: dark)", color: "#08090a" },
  ],
};

const THEME_INIT = `(function(){try{var t=localStorage.getItem('theme');if(t==='light'||t==='dark'){document.documentElement.setAttribute('data-theme',t);}}catch(e){}})();`;

export default async function LangLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;
  const locale: Locale = isLocale(lang) ? lang : "en";

  return (
    <html lang={htmlLang[locale]} dir={dir(locale)} suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://api.fontshare.com" />
        <link
          rel="preconnect"
          href="https://cdn.fontshare.com"
          crossOrigin="anonymous"
        />
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT }} />
      </head>
      <body className="grain antialiased">
        {children}
        <Analytics />
      </body>
    </html>
  );
}
