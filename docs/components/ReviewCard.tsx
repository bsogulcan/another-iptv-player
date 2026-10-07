"use client";

import { useState } from "react";

export function ReviewCard({
  original,
  originalLang,
  translation,
  caption,
  labels,
}: {
  original: string;
  originalLang: string;
  /** Absent when the review is already in the page language. */
  translation?: string;
  caption: string;
  labels: {
    translated: string;
    showOriginal: string;
    showTranslation: string;
    languageName: string;
  };
}) {
  const [showOriginal, setShowOriginal] = useState(false);
  const isOriginal = !translation || showOriginal;

  return (
    <figure className="rounded-2xl border border-line bg-ink-2/40 p-7">
      <blockquote
        lang={isOriginal ? originalLang : undefined}
        dir="auto"
        className="text-[15px] leading-relaxed text-snow"
      >
        “{isOriginal ? original : translation}”
      </blockquote>
      <figcaption className="mt-4 flex flex-wrap items-center justify-between gap-x-4 gap-y-2 text-[13px] font-medium text-fog">
        <span>{caption}</span>
        {translation && (
          <button
            type="button"
            onClick={() => setShowOriginal((v) => !v)}
            aria-pressed={showOriginal}
            className="text-fog underline decoration-line underline-offset-4 transition-colors hover:text-snow"
          >
            {showOriginal
              ? labels.showTranslation
              : `${labels.translated} · ${labels.showOriginal} (${labels.languageName})`}
          </button>
        )}
      </figcaption>
    </figure>
  );
}
