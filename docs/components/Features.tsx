import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { PlayMark } from "./icons";
import { Reveal, SectionLabel } from "./Reveal";

export function Features({ d }: { d: Dictionary }) {
  const f = d.features;
  return (
    <section id="features" className="relative py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-5">
        <div className="flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
          <div>
            <Reveal>
              <SectionLabel>{f.label}</SectionLabel>
            </Reveal>
            <Reveal delay={0.05}>
              <h2 className="mt-5 max-w-xl font-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold leading-[1.02] tracking-[-0.02em] text-snow">
                {f.headingLine1}
                <br />
                {f.headingLine2}
              </h2>
            </Reveal>
          </div>
          <Reveal delay={0.1}>
            <p className="max-w-sm text-fog">{f.intro}</p>
          </Reveal>
        </div>

        <div className="mt-14 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {f.items.map((item, i) => (
            <Reveal key={item.title} delay={(i % 3) * 0.05} className="group">
              <article className="relative flex h-full min-h-[200px] flex-col justify-between overflow-hidden rounded-2xl border border-line bg-ink-2/50 p-6 transition-colors duration-300 hover:border-fog/50">
                <div className="pointer-events-none absolute -right-10 -top-10 h-28 w-28 rounded-full bg-acid/0 blur-2xl transition-all duration-500 group-hover:bg-acid/10" />
                <div className="flex items-center justify-between">
                  <span className="grid h-9 w-9 place-items-center rounded-lg border border-line bg-ink-3 text-acid transition-colors group-hover:border-acid/40">
                    <PlayMark className="h-3.5 w-3.5 translate-x-px" />
                  </span>
                  <span className="font-display text-xs tabular-nums text-fog/50">
                    {String(i + 1).padStart(2, "0")}
                  </span>
                </div>
                <div>
                  <h3 className="font-display text-xl font-medium tracking-tight text-snow">
                    {item.title}
                  </h3>
                  <p className="mt-2 text-sm leading-relaxed text-fog">
                    {item.body}
                  </p>
                </div>
              </article>
            </Reveal>
          ))}
        </div>

        <Reveal delay={0.05}>
          <div className="mt-14 rounded-2xl border border-line bg-ink-2/30 p-6 sm:p-8">
            <div className="flex items-baseline justify-between gap-4">
              <h3 className="font-display text-lg font-medium tracking-tight text-snow">
                {f.moreTitle}
              </h3>
              <span className="font-display text-xs tabular-nums text-fog/50">
                {String(f.more.length).padStart(2, "0")}+
              </span>
            </div>
            <ul className="mt-5 grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2 lg:grid-cols-3">
              {f.more.map((m) => (
                <li
                  key={m}
                  className="flex items-center gap-2.5 text-sm text-mist"
                >
                  <PlayMark className="h-2.5 w-2.5 shrink-0 text-acid" />
                  {m}
                </li>
              ))}
            </ul>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
