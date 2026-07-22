import { memo, ReactNode, useCallback } from "react";
import { useFocusable } from "@noriginmedia/norigin-spatial-navigation";
import { PosterImage } from "./PosterImage";

export type CardShape = "poster" | "landscape";

/** "7.50" → "7.5", "8.0" → "8"; empty/zero/unparseable → no badge. */
function formatRating(rating: string | undefined): string | undefined {
  if (!rating) return undefined;
  const value = parseFloat(rating);
  if (!isFinite(value) || value <= 0) return undefined;
  return String(Math.round(value * 10) / 10);
}

export const FocusableCard = memo(function FocusableCard({
  title,
  subtitle,
  imageURL,
  shape,
  rating,
  progress,
  favorite,
  onSelect,
  onFocusedElement,
  onArrowPress,
}: {
  title: string;
  subtitle?: string;
  imageURL?: string;
  shape: CardShape;
  /** Shown as a star badge on the poster's top-right corner (iOS RatingLabel). */
  rating?: string;
  /** 0..1 → progress bar at the card bottom (continue watching). */
  progress?: number;
  favorite?: boolean;
  onSelect: () => void;
  onFocusedElement?: (el: HTMLElement) => void;
  /** Return false to consume the key and suppress default spatial nav. */
  onArrowPress?: (direction: string, el: HTMLElement | null) => boolean;
}) {
  const ratingLabel = formatRating(rating);
  const onFocus = useCallback(() => {
    if (ref.current && onFocusedElement) onFocusedElement(ref.current);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onFocusedElement]);

  const handleArrow = useCallback(
    (direction: string): boolean =>
      onArrowPress
        ? onArrowPress(direction, ref.current as HTMLElement | null)
        : true,
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [onArrowPress],
  );

  const { ref, focused, focusKey } = useFocusable({
    onEnterPress: onSelect,
    onFocus,
    onArrowPress: handleArrow,
  });

  return (
    <div
      ref={ref}
      data-fk={focusKey}
      className={`card card-${shape}${focused ? " focused" : ""}`}
    >
      <div className="card-image-wrap">
        <PosterImage src={imageURL} alt={title} className={`image-${shape}`} />
        {ratingLabel && <span className="card-rating">★ {ratingLabel}</span>}
        {favorite && <span className="card-favorite">♥</span>}
        {progress !== undefined && progress > 0 && (
          <div className="card-progress">
            <div
              className="card-progress-fill"
              style={{ width: `${Math.min(progress * 100, 100)}%` }}
            />
          </div>
        )}
      </div>
      <div className="card-title">{title}</div>
      {subtitle && <div className="card-subtitle">{subtitle}</div>}
    </div>
  );
});

export function TextCard({
  label,
  onSelect,
  wide,
}: {
  label: ReactNode;
  onSelect: () => void;
  wide?: boolean;
}) {
  const { ref, focused } = useFocusable({ onEnterPress: onSelect });
  return (
    <div
      ref={ref}
      className={`text-card${wide ? " wide" : ""}${focused ? " focused" : ""}`}
    >
      {label}
    </div>
  );
}
