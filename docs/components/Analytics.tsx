import Script from "next/script";
import { Analytics as VercelAnalytics } from "@vercel/analytics/next";

const GA_ID = "G-7TGBTLKK9R";

export function Analytics() {
  return (
    <>
      <VercelAnalytics />
      <Script
        src={`https://www.googletagmanager.com/gtag/js?id=${GA_ID}`}
        strategy="afterInteractive"
      />
      <Script id="ga-init" strategy="afterInteractive">
        {`
          window.dataLayer = window.dataLayer || [];
          function gtag(){dataLayer.push(arguments);}
          gtag('js', new Date());
          gtag('config', '${GA_ID}');
        `}
      </Script>
    </>
  );
}
