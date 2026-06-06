import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { Reveal, SectionLabel } from "./Reveal";

export function HowItWorks({ d }: { d: Dictionary }) {
  const h = d.how;
  return (
    <section id="how" className="relative py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-5">
        <div className="max-w-2xl">
          <Reveal>
            <SectionLabel>{h.label}</SectionLabel>
          </Reveal>
          <Reveal delay={0.05}>
            <h2 className="mt-5 font-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold leading-[1.02] tracking-[-0.02em] text-snow">
              {h.heading}
            </h2>
          </Reveal>
        </div>

        <div className="mt-14 grid gap-4 md:grid-cols-3">
          {h.steps.map((s, i) => (
            <Reveal key={s.title} delay={i * 0.08}>
              <div className="relative h-full rounded-2xl border border-line bg-ink-2/40 p-7">
                <span className="font-display text-5xl font-semibold tracking-tight text-ink-3 [-webkit-text-stroke:1px_var(--color-line)]">
                  {String(i + 1).padStart(2, "0")}
                </span>
                <h3 className="mt-5 font-display text-xl font-medium tracking-tight text-snow">
                  {s.title}
                </h3>
                <p className="mt-2.5 text-sm leading-relaxed text-fog">
                  {s.body}
                </p>
              </div>
            </Reveal>
          ))}
        </div>

        <Reveal delay={0.1}>
          <div className="mt-6 flex flex-col gap-2 rounded-2xl border border-acid/20 bg-acid/[0.04] p-6 sm:flex-row sm:items-center sm:gap-5">
            <span className="shrink-0 font-display text-sm font-semibold uppercase tracking-[0.18em] text-acid">
              {h.headsUp}
            </span>
            <p className="text-sm leading-relaxed text-mist">{h.headsUpText}</p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
