import Link from "next/link";
import type { Locale } from "@/lib/i18n/config";
import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { LINKS } from "@/lib/data";
import { GithubIcon, PlayMark } from "./icons";

export function Footer({ d, lang }: { d: Dictionary; lang: Locale }) {
  const base = `/${lang}`;
  const f = d.footer;

  const cols = [
    {
      title: f.product,
      links: [
        { label: d.nav.features, href: `${base}/#features` },
        { label: d.nav.screenshots, href: `${base}/#screenshots` },
        { label: d.nav.how, href: `${base}/#how` },
        { label: f.download, href: `${base}/#download` },
      ],
    },
    {
      title: f.help,
      links: [
        { label: d.nav.faq, href: `${base}/faq` },
        { label: d.nav.support, href: `${base}/support` },
        { label: f.privacy, href: `${base}/privacy` },
        { label: "bsogulcan@gmail.com", href: LINKS.email, ext: true },
      ],
    },
    {
      title: f.project,
      links: [
        { label: f.github, href: LINKS.github, ext: true },
        { label: f.releases, href: LINKS.releases, ext: true },
        { label: f.contribute, href: LINKS.github, ext: true },
        { label: f.coffee, href: LINKS.coffee, ext: true },
      ],
    },
  ];

  return (
    <footer className="relative border-t border-line">
      <div className="mx-auto max-w-6xl px-5 py-16">
        <div className="grid gap-10 md:grid-cols-[1.3fr_1fr_1fr_1fr]">
          <div>
            <div className="flex items-center gap-2.5">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/logo.png"
                alt="Another IPTV Player"
                width={32}
                height={32}
                className="h-8 w-8 rounded-[9px] shadow-sm ring-1 ring-line"
              />
              <span className="font-display text-[15px] font-semibold tracking-tight text-snow">
                Another IPTV Player
              </span>
            </div>
            <p className="mt-4 max-w-xs text-sm leading-relaxed text-fog">
              {f.tagline}
            </p>
            <a
              href={LINKS.github}
              target="_blank"
              rel="noreferrer noopener external"
              aria-label={f.github}
              className="mt-5 inline-grid h-9 w-9 place-items-center rounded-lg border border-line text-mist transition-colors hover:border-fog hover:text-snow"
            >
              <GithubIcon className="h-4 w-4" />
            </a>
          </div>

          {cols.map((col) => (
            <div key={col.title}>
              <h4 className="text-xs font-medium uppercase tracking-[0.2em] text-fog/70">
                {col.title}
              </h4>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((l) => (
                  <li key={l.label}>
                    {"ext" in l && l.ext ? (
                      <a
                        href={l.href}
                        target="_blank"
                        rel="noreferrer noopener external"
                        className="text-sm text-mist transition-colors hover:text-acid"
                      >
                        {l.label}
                      </a>
                    ) : (
                      <Link
                        href={l.href}
                        className="text-sm text-mist transition-colors hover:text-acid"
                      >
                        {l.label}
                      </Link>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-14 flex flex-col gap-4 border-t border-line pt-8 text-xs text-fog sm:flex-row sm:items-center sm:justify-between">
          <p>
            © {new Date().getFullYear()} Another IPTV Player. {f.rights}
          </p>
          <p className="max-w-xl text-fog/70">{f.disclaimer}</p>
        </div>
      </div>
    </footer>
  );
}
