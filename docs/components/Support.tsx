import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { LINKS } from "@/lib/data";
import { ArrowUpRight, GithubIcon } from "./icons";
import { Reveal, SectionLabel } from "./Reveal";

export function Support({ d }: { d: Dictionary }) {
  const o = d.openSource;
  return (
    <section className="relative py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-5">
        <div className="grid gap-3 sm:grid-cols-3">
          {o.pillars.map((p, i) => (
            <Reveal key={p.title} delay={i * 0.06}>
              <div className="h-full rounded-2xl border border-line bg-ink-2/40 p-7">
                <h3 className="font-display text-lg font-medium tracking-tight text-snow">
                  {p.title}
                </h3>
                <p className="mt-2 text-sm leading-relaxed text-fog">
                  {p.body}
                </p>
              </div>
            </Reveal>
          ))}
        </div>

        <Reveal delay={0.1}>
          <div className="mt-3 flex flex-col items-start justify-between gap-6 rounded-2xl border border-line bg-ink-2/40 p-8 sm:p-10 md:flex-row md:items-center">
            <div>
              <SectionLabel>{o.label}</SectionLabel>
              <p className="mt-4 max-w-lg font-display text-2xl font-medium leading-tight tracking-tight text-snow">
                {o.text}
              </p>
            </div>
            <div className="flex shrink-0 flex-wrap gap-3">
              <a
                href={LINKS.coffee}
                target="_blank"
                rel="noreferrer noopener external"
                className="inline-flex items-center gap-2 rounded-xl bg-acid px-5 py-3 text-sm font-semibold text-ink transition-transform hover:-translate-y-0.5"
              >
                {o.coffee}
                <ArrowUpRight className="h-4 w-4" />
              </a>
              <a
                href={LINKS.github}
                target="_blank"
                rel="noreferrer noopener external"
                className="inline-flex items-center gap-2 rounded-xl border border-line px-5 py-3 text-sm font-semibold text-snow transition-colors hover:border-fog"
              >
                <GithubIcon className="h-4 w-4" />
                {o.contribute}
              </a>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
