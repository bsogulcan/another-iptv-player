import type { ReactNode } from "react";
import type { Locale } from "@/lib/i18n/config";
import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { LINKS } from "@/lib/data";
import { Nav } from "./Nav";
import { Footer } from "./Footer";
import { CoffeeIcon } from "./icons";
import { SectionLabel } from "./Reveal";

export function Page({
  d,
  lang,
  eyebrow,
  title,
  intro,
  children,
  contentClassName = "max-w-3xl",
  showCoffee = false,
}: {
  d: Dictionary;
  lang: Locale;
  eyebrow: string;
  title: string;
  intro?: string;
  children: ReactNode;
  contentClassName?: string;
  showCoffee?: boolean;
}) {
  return (
    <>
      <Nav d={d} lang={lang} />
      <main className="relative">
        <section className="relative overflow-hidden pt-36 pb-12 sm:pt-44">
          <div className="dot-grid pointer-events-none absolute inset-0 opacity-50" />
          <div className="pointer-events-none absolute left-1/2 top-0 h-[360px] w-[680px] -translate-x-1/2 rounded-full bg-acid/[0.08] blur-[140px]" />
          <div className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-line to-transparent" />
          <div className="relative mx-auto max-w-3xl px-5">
            <SectionLabel>{eyebrow}</SectionLabel>
            <h1 className="mt-5 font-display text-[clamp(2.4rem,6vw,4rem)] font-semibold leading-[1.0] tracking-[-0.03em] text-snow">
              {title}
            </h1>
            {intro && (
              <p className="mt-6 max-w-2xl text-lg leading-relaxed text-fog">
                {intro}
              </p>
            )}
          </div>
        </section>

        <section className="relative pb-28">
          <div className={`relative mx-auto px-5 ${contentClassName}`}>
            {children}
            {showCoffee && (
              <div className="mt-16 flex flex-col items-start gap-5 rounded-2xl border border-line bg-ink-2/40 p-8 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <h2 className="font-display text-xl font-semibold tracking-tight text-snow">
                    {d.openSource.label}
                  </h2>
                  <p className="mt-2 max-w-md text-sm leading-relaxed text-fog">
                    {d.openSource.text}
                  </p>
                </div>
                <a
                  href={LINKS.coffee}
                  target="_blank"
                  rel="noreferrer noopener external"
                  className="inline-flex shrink-0 items-center gap-2 rounded-xl bg-acid px-5 py-3 text-sm font-semibold text-ink transition-transform hover:-translate-y-0.5"
                >
                  <CoffeeIcon className="h-4 w-4" />
                  {d.openSource.coffee}
                </a>
              </div>
            )}
          </div>
        </section>
      </main>
      <Footer d={d} lang={lang} />
    </>
  );
}
