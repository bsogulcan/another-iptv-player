"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import type { Locale } from "@/lib/i18n/config";
import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { LINKS } from "@/lib/data";
import { GithubIcon } from "./icons";
import { ThemeToggle } from "./ThemeToggle";
import { LanguageSwitcher } from "./LanguageSwitcher";

export function Nav({ d, lang }: { d: Dictionary; lang: Locale }) {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const base = `/${lang}`;

  const navItems = [
    { label: d.nav.features, href: `${base}/#features` },
    { label: d.nav.screenshots, href: `${base}/#screenshots` },
    { label: d.nav.how, href: `${base}/#how` },
    { label: d.nav.guide, href: `${base}/how-to` },
    { label: d.nav.faq, href: `${base}/faq` },
    { label: d.nav.support, href: `${base}/support` },
  ];

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 16);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header className="fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-4">
      <nav
        className={`flex w-full max-w-6xl items-center justify-between rounded-2xl border px-4 py-3 transition-all duration-500 ${
          scrolled
            ? "border-line bg-ink-2/80 backdrop-blur-xl"
            : "border-transparent bg-transparent"
        }`}
      >
        <Link href={base} className="flex items-center gap-2.5">
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
        </Link>

        <div className="hidden items-center gap-7 md:flex">
          {navItems.map((it) => (
            <Link
              key={it.href}
              href={it.href}
              className="text-sm text-fog transition-colors hover:text-snow"
            >
              {it.label}
            </Link>
          ))}
        </div>

        <div className="flex items-center gap-2">
          <LanguageSwitcher current={lang} label={d.nav.language} />
          <ThemeToggle />
          <a
            href={LINKS.github}
            target="_blank"
            rel="noreferrer noopener external"
            aria-label={d.nav.github}
            className="hidden h-9 w-9 place-items-center rounded-lg border border-line text-mist transition-colors hover:border-fog hover:text-snow sm:grid"
          >
            <GithubIcon className="h-4 w-4" />
          </a>
          <a
            href={`${base}/#download`}
            className="hidden rounded-lg bg-acid px-4 py-2 text-sm font-semibold text-ink transition-transform hover:-translate-y-0.5 sm:block"
          >
            {d.nav.getApp}
          </a>
          <button
            type="button"
            aria-label={d.nav.menu}
            onClick={() => setOpen((v) => !v)}
            className="grid h-9 w-9 place-items-center rounded-lg border border-line text-mist md:hidden"
          >
            <span className="relative block h-3 w-4">
              <span
                className={`absolute left-0 block h-0.5 w-4 bg-current transition-all ${
                  open ? "top-1.5 rotate-45" : "top-0"
                }`}
              />
              <span
                className={`absolute left-0 top-1.5 block h-0.5 w-4 bg-current transition-opacity ${
                  open ? "opacity-0" : "opacity-100"
                }`}
              />
              <span
                className={`absolute left-0 block h-0.5 w-4 bg-current transition-all ${
                  open ? "top-1.5 -rotate-45" : "top-3"
                }`}
              />
            </span>
          </button>
        </div>
      </nav>

      {open && (
        <div className="absolute left-4 right-4 top-20 rounded-2xl border border-line bg-ink-2/95 p-2 backdrop-blur-xl md:hidden">
          {navItems.map((it) => (
            <Link
              key={it.href}
              href={it.href}
              onClick={() => setOpen(false)}
              className="block rounded-xl px-4 py-3 text-sm text-mist hover:bg-ink-3"
            >
              {it.label}
            </Link>
          ))}
          <a
            href={`${base}/#download`}
            onClick={() => setOpen(false)}
            className="mt-1 block rounded-xl bg-acid px-4 py-3 text-center text-sm font-semibold text-ink"
          >
            {d.nav.getApp}
          </a>
        </div>
      )}
    </header>
  );
}
