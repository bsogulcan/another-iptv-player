import type { Locale } from "@/lib/i18n/config";
import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { REVIEWS } from "@/lib/reviews";
import { ReviewCard } from "./ReviewCard";
import { Reveal, SectionLabel } from "./Reveal";

export function Reviews({ d, lang }: { d: Dictionary; lang: Locale }) {
  const r = d.reviews;
  const regions = new Intl.DisplayNames([lang], { type: "region" });
  const languages = new Intl.DisplayNames([lang], { type: "language" });
  return (
    <section id="reviews" className="relative py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-5">
        <div className="max-w-2xl">
          <Reveal>
            <SectionLabel>{r.label}</SectionLabel>
          </Reveal>
          <Reveal delay={0.05}>
            <h2 className="mt-5 font-display text-[clamp(2rem,4.5vw,3.25rem)] font-semibold leading-[1.02] tracking-[-0.02em] text-snow">
              {r.heading}
            </h2>
          </Reveal>
          <Reveal delay={0.1}>
            <p className="mt-5 text-sm leading-relaxed text-fog">{r.note}</p>
          </Reveal>
        </div>

        <div className="mt-14 gap-4 sm:columns-2 lg:columns-3">
          {REVIEWS.map((review, i) => (
            <Reveal
              key={review.text}
              delay={(i % 3) * 0.06}
              className="mb-4 break-inside-avoid"
            >
              <ReviewCard
                original={review.text}
                originalLang={review.lang}
                translation={
                  review.lang === lang ? undefined : review.translations[lang]
                }
                caption={`${regions.of(review.country)} · ${review.device}`}
                labels={{
                  translated: r.translated,
                  showOriginal: r.showOriginal,
                  showTranslation: r.showTranslation,
                  languageName: languages.of(review.lang) ?? review.lang,
                }}
              />
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
