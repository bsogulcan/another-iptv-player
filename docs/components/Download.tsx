import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { DOWNLOADS, LINKS } from "@/lib/data";
import {
  AppleIcon,
  ArrowUpRight,
  CoffeeIcon,
  LinuxIcon,
  PlayStoreIcon,
  WindowsIcon,
} from "./icons";
import { Reveal, SectionLabel } from "./Reveal";

function iconFor(name: string) {
  if (name === "App Store" || name === "macOS")
    return <AppleIcon className="h-5 w-5" />;
  if (name === "Google Play") return <PlayStoreIcon className="h-5 w-5" />;
  if (name === "Windows") return <WindowsIcon className="h-5 w-5" />;
  if (name === "Linux") return <LinuxIcon className="h-5 w-5" />;
  return <ArrowUpRight className="h-5 w-5" />;
}

export function Download({ d }: { d: Dictionary }) {
  return (
    <section id="download" className="relative overflow-hidden py-24 sm:py-32">
      <div className="pointer-events-none absolute left-1/2 top-1/2 h-[400px] w-[700px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-acid/[0.07] blur-[150px]" />
      <div className="relative mx-auto max-w-6xl px-5">
        <div className="overflow-hidden rounded-3xl border border-line bg-ink-2/50">
          <div className="grid lg:grid-cols-5">
            <div className="border-line p-8 sm:p-12 lg:col-span-2 lg:border-r">
              <Reveal>
                <SectionLabel>{d.download.label}</SectionLabel>
              </Reveal>
              <Reveal delay={0.05}>
                <h2 className="mt-5 font-display text-[clamp(2rem,4vw,3rem)] font-semibold leading-[1.02] tracking-[-0.02em] text-snow">
                  {d.download.heading}
                </h2>
              </Reveal>
              <Reveal delay={0.1}>
                <p className="mt-5 text-fog">{d.download.intro}</p>
              </Reveal>
              <Reveal delay={0.15}>
                <a
                  href={LINKS.coffee}
                  target="_blank"
                  rel="noreferrer noopener external"
                  className="group mt-6 inline-flex items-center gap-2 text-sm font-semibold text-acid transition-colors hover:text-acid-soft"
                >
                  <CoffeeIcon className="h-4 w-4" />
                  {d.openSource.coffee}
                  <ArrowUpRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
                </a>
              </Reveal>
            </div>

            <div className="grid grid-cols-1 gap-px bg-line sm:grid-cols-2 lg:col-span-3">
              {DOWNLOADS.map((item, i) => (
                <Reveal key={item.name} delay={(i % 2) * 0.05}>
                  <a
                    href={item.href}
                    target="_blank"
                    rel="noreferrer noopener external"
                    className={`group flex h-full items-center justify-between gap-4 p-6 transition-colors sm:p-7 ${
                      item.featured
                        ? "bg-ink-2 hover:bg-ink-3"
                        : "bg-ink-2/60 hover:bg-ink-3"
                    }`}
                  >
                    <div className="flex items-center gap-4">
                      <span
                        className={`grid h-11 w-11 shrink-0 place-items-center rounded-xl transition-colors ${
                          item.featured
                            ? "bg-acid text-ink"
                            : "border border-line bg-ink-3 text-mist group-hover:text-snow"
                        }`}
                      >
                        {iconFor(item.name)}
                      </span>
                      <div>
                        <div className="font-display font-medium tracking-tight text-snow">
                          {item.name}
                        </div>
                        <div className="text-xs text-fog">
                          {d.download.subs[item.name]}
                        </div>
                      </div>
                    </div>
                    <ArrowUpRight className="h-5 w-5 shrink-0 text-fog transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-acid" />
                  </a>
                </Reveal>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
