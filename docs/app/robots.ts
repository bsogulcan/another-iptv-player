import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/i18n/config";

export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  // Note: no `host` directive — Googlebot ignores it (only Yandex supports it).
  // Canonical host is enforced via the www→apex redirect + canonical tags.
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
