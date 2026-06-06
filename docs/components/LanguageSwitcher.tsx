"use client";

import { useEffect, useRef, useState } from "react";
import { usePathname } from "next/navigation";
import Link from "next/link";
import {
  isLocale,
  localeName,
  locales,
  type Locale,
} from "@/lib/i18n/config";

export function LanguageSwitcher({
  current,
  label,
}: {
  current: Locale;
  label: string;
}) {
  const [open, setOpen] = useState(false);
  const pathname = usePathname() || `/${current}`;
  const ref = useRef<HTMLDivElement>(null);

  // path within the current locale, e.g. "/faq" ("" for home)
  const segments = pathname.split("/").filter(Boolean);
  const rest =
    segments.length && isLocale(segments[0])
      ? "/" + segments.slice(1).join("/")
      : pathname;
  const subPath = rest === "/" ? "" : rest.replace(/\/$/, "");

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node))
        setOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-label={label}
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="flex h-9 items-center gap-1.5 rounded-lg border border-line px-2.5 text-mist transition-colors hover:border-fog hover:text-snow"
      >
        <svg
          viewBox="0 0 24 24"
          className="h-4 w-4"
          fill="none"
          stroke="currentColor"
          strokeWidth={1.8}
        >
          <circle cx="12" cy="12" r="9" />
          <path d="M3 12h18M12 3c2.5 2.6 2.5 15.4 0 18M12 3c-2.5 2.6-2.5 15.4 0 18" />
        </svg>
        <span className="text-xs font-semibold uppercase">{current}</span>
      </button>

      {open && (
        <div className="absolute right-0 top-11 z-50 max-h-[60vh] w-44 overflow-auto rounded-xl border border-line bg-ink-2/95 p-1.5 shadow-xl backdrop-blur-xl">
          {locales.map((l) => (
            <Link
              key={l}
              href={`/${l}${subPath}`}
              onClick={() => setOpen(false)}
              className={`flex items-center justify-between rounded-lg px-3 py-2 text-sm transition-colors ${
                l === current
                  ? "bg-acid/10 text-acid"
                  : "text-mist hover:bg-ink-3 hover:text-snow"
              }`}
            >
              {localeName[l]}
              <span className="text-[10px] font-semibold uppercase text-fog">
                {l}
              </span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
