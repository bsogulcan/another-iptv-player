"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { SCREENSHOTS, type Shot } from "@/lib/data";
import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { Reveal, SectionLabel } from "./Reveal";

const TABS = Object.keys(SCREENSHOTS);

/** A carousel card that auto-sizes to its image orientation (portrait vs landscape). */
function GalleryShot({
  shot,
  onClick,
  viewLabel,
}: {
  shot: Shot;
  onClick: () => void;
  viewLabel: string;
}) {
  const [wide, setWide] = useState(false);
  return (
    <button
      type="button"
      onClick={onClick}
      className={`group relative shrink-0 snap-start overflow-hidden rounded-2xl border border-line bg-ink-3 transition-all duration-300 hover:-translate-y-1 hover:border-acid/40 ${
        wide
          ? "h-[218px] w-[474px] sm:h-[250px] sm:w-[543px]"
          : "h-[400px] w-[184px] sm:h-[460px] sm:w-[212px]"
      }`}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={shot.src}
        alt={shot.alt}
        loading="lazy"
        onLoad={(e) => {
          const img = e.currentTarget;
          setWide(img.naturalWidth > img.naturalHeight);
        }}
        className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-105"
      />
      <span className="pointer-events-none absolute inset-0 ring-1 ring-inset ring-white/5" />
      <span className="pointer-events-none absolute inset-x-0 bottom-0 flex items-end justify-center bg-gradient-to-t from-ink/80 to-transparent p-3 opacity-0 transition-opacity duration-300 group-hover:opacity-100">
        <span className="rounded-full bg-acid px-3 py-1 text-xs font-semibold text-ink">
          {viewLabel}
        </span>
      </span>
    </button>
  );
}

function Arrow({
  dir,
  onClick,
  disabled,
  className = "",
}: {
  dir: "prev" | "next";
  onClick: () => void;
  disabled?: boolean;
  className?: string;
}) {
  return (
    <button
      type="button"
      aria-label={dir === "prev" ? "Previous" : "Next"}
      onClick={onClick}
      disabled={disabled}
      className={`grid h-11 w-11 place-items-center rounded-full border border-line bg-ink-2/80 text-mist backdrop-blur transition-all hover:border-acid hover:text-acid disabled:pointer-events-none disabled:opacity-30 ${className}`}
    >
      <svg
        viewBox="0 0 24 24"
        className={`h-5 w-5 ${dir === "next" ? "rotate-180" : ""}`}
        fill="none"
        stroke="currentColor"
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M15 18l-6-6 6-6" />
      </svg>
    </button>
  );
}

export function Screenshots({ d }: { d: Dictionary }) {
  const [tab, setTab] = useState(TABS[0]);
  const [active, setActive] = useState<number | null>(null);
  const [canPrev, setCanPrev] = useState(false);
  const [canNext, setCanNext] = useState(true);
  const trackRef = useRef<HTMLDivElement>(null);

  const shots = SCREENSHOTS[tab];

  const updateArrows = useCallback(() => {
    const el = trackRef.current;
    if (!el) return;
    setCanPrev(el.scrollLeft > 8);
    setCanNext(el.scrollLeft < el.scrollWidth - el.clientWidth - 8);
  }, []);

  useEffect(() => {
    const el = trackRef.current;
    if (!el) return;
    el.scrollTo({ left: 0 });
    // wait for layout, then refresh arrow state
    const id = requestAnimationFrame(updateArrows);
    return () => cancelAnimationFrame(id);
  }, [tab, updateArrows]);

  const scrollByCards = (dir: 1 | -1) => {
    const el = trackRef.current;
    if (!el) return;
    el.scrollBy({ left: dir * el.clientWidth * 0.8, behavior: "smooth" });
  };

  // lightbox navigation
  const close = useCallback(() => setActive(null), []);
  const step = useCallback(
    (d: number) =>
      setActive((cur) =>
        cur === null ? cur : (cur + d + shots.length) % shots.length
      ),
    [shots.length]
  );

  useEffect(() => {
    if (active === null) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") close();
      if (e.key === "ArrowRight") step(1);
      if (e.key === "ArrowLeft") step(-1);
    };
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [active, close, step]);

  return (
    <section id="screenshots" className="relative py-24 sm:py-32">
      <div className="dot-grid pointer-events-none absolute inset-0 opacity-40" />
      <div className="relative mx-auto max-w-6xl px-5">
        <div className="flex flex-col items-start gap-6 md:flex-row md:items-end md:justify-between">
          <div>
            <Reveal>
              <SectionLabel>{d.screenshots.label}</SectionLabel>
            </Reveal>
            <Reveal delay={0.05}>
              <h2 className="mt-5 font-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold leading-[1.02] tracking-[-0.02em] text-snow">
                {d.screenshots.heading}
              </h2>
            </Reveal>
          </div>

          <Reveal delay={0.1}>
            <div className="flex items-center gap-4">
              <div className="flex rounded-xl border border-line bg-ink-2/60 p-1 backdrop-blur">
                {TABS.map((t) => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => setTab(t)}
                    className={`relative rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                      tab === t ? "text-ink" : "text-fog hover:text-snow"
                    }`}
                  >
                    {tab === t && (
                      <motion.span
                        layoutId="tab-pill"
                        className="absolute inset-0 rounded-lg bg-acid"
                        transition={{
                          type: "spring",
                          stiffness: 380,
                          damping: 32,
                        }}
                      />
                    )}
                    <span className="relative z-10">{t}</span>
                  </button>
                ))}
              </div>
              <div className="hidden items-center gap-2 sm:flex">
                <Arrow
                  dir="prev"
                  onClick={() => scrollByCards(-1)}
                  disabled={!canPrev}
                />
                <Arrow
                  dir="next"
                  onClick={() => scrollByCards(1)}
                  disabled={!canNext}
                />
              </div>
            </div>
          </Reveal>
        </div>

        {/* carousel */}
        <div className="relative mt-12">
          <div
            ref={trackRef}
            onScroll={updateArrows}
            className="no-scrollbar flex min-h-[400px] snap-x snap-mandatory items-center gap-4 overflow-x-auto scroll-smooth pb-2 sm:min-h-[460px]"
          >
            {shots.map((shot, i) => (
              <GalleryShot
                key={shot.src}
                shot={shot}
                onClick={() => setActive(i)}
                viewLabel={d.screenshots.view}
              />
            ))}
            {/* trailing spacer for snap padding */}
            <span className="shrink-0" aria-hidden style={{ width: 1 }} />
          </div>

          {/* edge fades */}
          <div className="pointer-events-none absolute inset-y-0 left-0 w-10 bg-gradient-to-r from-ink to-transparent" />
          <div className="pointer-events-none absolute inset-y-0 right-0 w-10 bg-gradient-to-l from-ink to-transparent" />
        </div>

        {/* mobile arrows */}
        <div className="mt-6 flex items-center justify-center gap-3 sm:hidden">
          <Arrow dir="prev" onClick={() => scrollByCards(-1)} disabled={!canPrev} />
          <Arrow dir="next" onClick={() => scrollByCards(1)} disabled={!canNext} />
        </div>
      </div>

      {/* lightbox gallery */}
      <AnimatePresence>
        {active !== null && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={close}
            className="fixed inset-0 z-[200] flex flex-col items-center justify-center bg-ink/92 p-4 backdrop-blur-md sm:p-8"
          >
            <button
              type="button"
              aria-label="Close"
              onClick={close}
              className="absolute right-5 top-5 z-10 grid h-10 w-10 place-items-center rounded-full border border-line bg-ink-2 text-mist transition-colors hover:text-snow"
            >
              ✕
            </button>

            <div
              className="flex w-full max-w-5xl flex-1 items-center justify-center gap-3 sm:gap-6"
              onClick={(e) => e.stopPropagation()}
            >
              <Arrow
                dir="prev"
                onClick={() => step(-1)}
                className="shrink-0"
              />
              <AnimatePresence mode="popLayout">
                <motion.img
                  key={shots[active].src}
                  initial={{ opacity: 0, scale: 0.96 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.96 }}
                  transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
                  src={shots[active].src}
                  alt={shots[active].alt}
                  className="max-h-[78vh] max-w-[80vw] rounded-2xl border border-line object-contain shadow-2xl"
                />
              </AnimatePresence>
              <Arrow dir="next" onClick={() => step(1)} className="shrink-0" />
            </div>

            <div
              className="mt-5 flex items-center gap-3"
              onClick={(e) => e.stopPropagation()}
            >
              <span className="font-display text-sm tabular-nums text-fog">
                {String(active + 1).padStart(2, "0")} /{" "}
                {String(shots.length).padStart(2, "0")}
              </span>
              <div className="flex gap-1.5">
                {shots.map((_, i) => (
                  <button
                    key={i}
                    type="button"
                    aria-label={`Go to image ${i + 1}`}
                    onClick={() => setActive(i)}
                    className={`h-1.5 rounded-full transition-all ${
                      i === active ? "w-6 bg-acid" : "w-1.5 bg-line hover:bg-fog"
                    }`}
                  />
                ))}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </section>
  );
}
