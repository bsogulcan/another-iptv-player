import type { MetadataRoute } from "next";

export const dynamic = "force-static";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Another IPTV Player",
    short_name: "IPTV Player",
    description:
      "A free, open-source, multi-platform IPTV player — Xtream Codes & M3U, offline downloads, PiP, HDR.",
    start_url: "/en/",
    display: "standalone",
    background_color: "#08090a",
    theme_color: "#08090a",
    icons: [
      { src: "/logo.png", sizes: "1024x1024", type: "image/png" },
      {
        src: "/logo.png",
        sizes: "1024x1024",
        type: "image/png",
        purpose: "any",
      },
    ],
  };
}
