import { PlayMark } from "./icons";

export function Marquee({ words }: { words: string[] }) {
  const row = [...words, ...words];
  return (
    <div className="relative flex overflow-hidden border-y border-line bg-ink-2/40 py-5">
      {[0, 1].map((dup) => (
        <div
          key={dup}
          className="animate-marquee flex shrink-0 items-center gap-8 pr-8"
          aria-hidden={dup === 1}
        >
          {row.map((w, i) => (
            <span key={i} className="flex items-center gap-8">
              <span className="font-display text-lg font-medium tracking-tight text-mist">
                {w}
              </span>
              <PlayMark className="h-2.5 w-2.5 text-acid" />
            </span>
          ))}
        </div>
      ))}
    </div>
  );
}
