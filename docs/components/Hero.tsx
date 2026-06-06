"use client";

import { motion } from "motion/react";
import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { LINKS, PLATFORMS, RATINGS } from "@/lib/data";
import {
  AppleIcon,
  ArrowUpRight,
  CoffeeIcon,
  GithubIcon,
  PlayStoreIcon,
} from "./icons";

const container = {
  hidden: {},
  show: { transition: { staggerChildren: 0.09, delayChildren: 0.1 } },
};
const item = {
  hidden: { opacity: 0, y: 22 },
  show: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.85, ease: [0.16, 1, 0.3, 1] as const },
  },
};

function Phone({
  src,
  className,
  rotate,
  delay,
}: {
  src: string;
  className?: string;
  rotate: number;
  delay: number;
}) {
  return (
    <motion.div
      className={`absolute overflow-hidden rounded-[2rem] border border-line bg-ink-3 ${className}`}
      initial={{ opacity: 0, y: 60, rotate: rotate * 1.6 }}
      animate={{ opacity: 1, y: 0, rotate }}
      transition={{ duration: 1.1, delay, ease: [0.16, 1, 0.3, 1] }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={src} alt="" className="h-full w-full object-cover" />
      <div className="pointer-events-none absolute inset-0 rounded-[2rem] ring-1 ring-inset ring-white/5" />
    </motion.div>
  );
}

export function Hero({ d }: { d: Dictionary }) {
  const h = d.hero;
  return (
    <section
      id="top"
      className="relative overflow-hidden pt-36 pb-20 sm:pt-40 lg:pt-44"
    >
      <div className="dot-grid absolute inset-0 opacity-60" />
      <div className="pointer-events-none absolute left-1/2 top-0 h-[520px] w-[820px] -translate-x-1/2 rounded-full bg-acid/10 blur-[140px]" />
      <div className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-line to-transparent" />

      <div className="relative mx-auto max-w-6xl px-5">
        <motion.div
          variants={container}
          initial="hidden"
          animate="show"
          className="mx-auto max-w-3xl text-center"
        >
          <motion.div variants={item} className="flex justify-center">
            <span className="inline-flex items-center gap-2 rounded-full border border-line bg-ink-2/90 px-4 py-1.5 text-[13px] font-medium text-snow shadow-sm ring-1 ring-line backdrop-blur">
              <span className="h-1.5 w-1.5 rounded-full bg-acid ring-2 ring-acid/25" />
              {h.badge}
            </span>
          </motion.div>

          <motion.h1
            variants={item}
            className="mt-7 font-display text-[clamp(2.6rem,7vw,5.25rem)] font-semibold leading-[0.98] tracking-[-0.03em] text-snow"
          >
            {h.titleLine1}
            <br />
            <span className="text-fog">{h.titlePre}</span>
            <span className="relative whitespace-nowrap text-acid">
              {h.titleHighlight}
              <svg
                className="absolute -bottom-2 left-0 w-full text-acid/60"
                viewBox="0 0 300 12"
                fill="none"
                preserveAspectRatio="none"
              >
                <path
                  d="M2 9C60 3 240 3 298 7"
                  stroke="currentColor"
                  strokeWidth="3"
                  strokeLinecap="round"
                />
              </svg>
            </span>
            <span className="text-snow">{h.titlePost}</span>
          </motion.h1>

          <motion.p
            variants={item}
            className="mx-auto mt-7 max-w-xl text-balance text-lg leading-relaxed text-fog"
          >
            {h.subtitle}
          </motion.p>

          <motion.div
            variants={item}
            className="mt-9 flex flex-wrap items-center justify-center gap-3"
          >
            <a
              href={LINKS.appStore}
              target="_blank"
              rel="noreferrer noopener external"
              className="group inline-flex items-center gap-2.5 rounded-xl bg-snow px-5 py-3 text-sm font-semibold text-ink transition-transform hover:-translate-y-0.5"
            >
              <AppleIcon className="h-4.5 w-4.5" />
              {h.ctaAppStore}
            </a>
            <a
              href={LINKS.googlePlay}
              target="_blank"
              rel="noreferrer noopener external"
              className="group inline-flex items-center gap-2.5 rounded-xl bg-snow px-5 py-3 text-sm font-semibold text-ink transition-transform hover:-translate-y-0.5"
            >
              <PlayStoreIcon className="h-4.5 w-4.5" />
              {h.ctaGooglePlay}
            </a>
            <a
              href={LINKS.github}
              target="_blank"
              rel="noreferrer noopener external"
              className="group inline-flex items-center gap-2 rounded-xl border border-line bg-ink-2/50 px-5 py-3 text-sm font-semibold text-snow backdrop-blur transition-colors hover:border-fog"
            >
              <GithubIcon className="h-4.5 w-4.5" />
              {h.ctaGithub}
              <ArrowUpRight className="h-4 w-4 text-fog transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
            </a>
            <a
              href={LINKS.coffee}
              target="_blank"
              rel="noreferrer noopener external"
              className="group inline-flex items-center gap-2 rounded-xl border border-line bg-ink-2/50 px-5 py-3 text-sm font-semibold text-snow backdrop-blur transition-colors hover:border-fog"
            >
              <CoffeeIcon className="h-4.5 w-4.5 text-acid" />
              {d.openSource.coffee}
            </a>
          </motion.div>

          <motion.div
            variants={item}
            className="mt-7 flex flex-wrap items-center justify-center gap-x-5 gap-y-2 text-sm text-fog"
          >
            <span className="inline-flex items-center gap-1.5">
              <span className="text-acid" aria-hidden>
                ★★★★★
              </span>
              <strong className="font-semibold text-snow">
                {RATINGS.appStore.value.toFixed(1)}
              </strong>
              <span>App Store · {RATINGS.appStore.count}</span>
            </span>
            <span className="hidden h-3.5 w-px bg-line sm:block" />
            <span className="inline-flex items-center gap-1.5">
              <span className="text-acid" aria-hidden>
                ★★★★★
              </span>
              <strong className="font-semibold text-snow">
                {RATINGS.macStore.value.toFixed(1)}
              </strong>
              <span>macOS · {RATINGS.macStore.count}</span>
            </span>
          </motion.div>

          <motion.div
            variants={item}
            className="mt-8 flex flex-wrap items-center justify-center gap-x-5 gap-y-2 text-xs font-medium uppercase tracking-[0.2em] text-fog"
          >
            {PLATFORMS.map((p) => (
              <span key={p}>{p}</span>
            ))}
          </motion.div>
        </motion.div>

        <div className="relative mx-auto mt-16 h-[440px] w-full max-w-3xl sm:h-[500px]">
          <Phone
            src="/screenshots/iphone/home-movies.png"
            rotate={-9}
            delay={0.5}
            className="left-1/2 top-6 hidden h-[400px] aspect-[1320/2868] -translate-x-[150%] sm:block"
          />
          <Phone
            src="/screenshots/iphone/home-live-tv.png"
            rotate={9}
            delay={0.6}
            className="left-1/2 top-6 hidden h-[400px] aspect-[1320/2868] translate-x-[50%] sm:block"
          />
          <Phone
            src="/screenshots/iphone/home-series.png"
            rotate={0}
            delay={0.4}
            className="left-1/2 top-0 h-[440px] aspect-[1320/2868] -translate-x-1/2 sm:h-[460px]"
          />
        </div>
      </div>
    </section>
  );
}
