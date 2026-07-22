import { memo, useCallback, useEffect, useRef, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { registerBackInterceptor } from "../../navigation/backHandler";
import { useScreenActive } from "../../navigation/ScreenLayer";
import { useTabActive } from "./TabLayer";
import { KEY, normalizeKeyCode } from "../../navigation/keys";
import { t } from "../../i18n";

// Category jump panel (Yellow key / pill next to search): the active tab's
// shelves as a focusable vertical list; Enter scrolls the dashboard to that
// row and focuses its first card. TV counterpart of iOS CategoryPickerSheet.

export interface CategoryEntry {
  id: string;
  title: string;
  count: number;
}

// Must match .category-picker-row height (64) + margin (8) in app.css.
const ROW_STRIDE = 72;
// Rows mounted above/below the focused one. Real playlists carry hundreds of
// categories; keeping the rest unmounted caps Norigin's per-keypress rect
// measurements and the list repaint at ~2× a viewport's worth of rows.
const ROW_WINDOW = 15;

// Memoized so the per-keypress panel re-render (focused index changes every
// arrow press) only touches the window edges, not every mounted row.
const CategoryRow = memo(function CategoryRow({
  entry,
  index,
  active,
  autoFocus,
  onSelect,
  onFocused,
  onClose,
}: {
  entry: CategoryEntry;
  index: number;
  active: boolean;
  autoFocus: boolean;
  onSelect: (rowId: string) => void;
  onFocused: (index: number) => void;
  onClose: () => void;
}) {
  const { ref, focused, focusSelf } = useFocusable({
    onEnterPress: () => onSelect(entry.id),
    onFocus: () => onFocused(index),
    // → closes the panel: it slid in from the left, so right reads as
    // "back to the content" (mirrors the ←-edge gesture that opens it).
    onArrowPress: (direction: string) => {
      if (direction === "right") {
        onClose();
        return false;
      }
      return true;
    },
  });
  useEffect(() => {
    if (autoFocus) focusSelf();
  }, [autoFocus, focusSelf]);
  const classes = ["category-picker-row"];
  if (active) classes.push("active");
  if (focused) classes.push("focused");
  return (
    <div ref={ref} className={classes.join(" ")}>
      <span className="category-picker-name">{entry.title}</span>
      <span className="category-picker-count">{entry.count}</span>
    </div>
  );
});

export function CategoryPickerPanel({
  entries,
  activeId,
  onSelect,
  onDismiss,
}: {
  entries: CategoryEntry[];
  /** Row the dashboard currently sits on: highlighted and initially focused. */
  activeId: string | null;
  onSelect: (rowId: string) => void;
  onDismiss: () => void;
}) {
  const { ref, focusKey } = useFocusable({
    trackChildren: true,
    isFocusBoundary: true,
  });
  const viewportRef = useRef<HTMLDivElement>(null);

  // Windowed + transform-scrolled like the dashboard shelves: scrollTop jumps
  // instantly on Chromium 56 (no smooth scrolling), while a CSS-transitioned
  // translateY glides on the TV GPU.
  const [focusedIndex, setFocusedIndex] = useState(() => {
    const index = entries.findIndex((entry) => entry.id === activeId);
    return index >= 0 ? index : 0;
  });
  // Pre-position near the active row: starting at 0 would glide the whole
  // (transitioned) track from the top on open. Exact centering lands on
  // first focus, once the viewport height is measurable.
  const [scrollY, setScrollY] = useState(() =>
    Math.max(0, focusedIndex * ROW_STRIDE - 416),
  );
  // One-shot: -1 once any row took focus, so a window-shift remount of the
  // initial row can never steal focus back mid-navigation.
  const pendingFocusRef = useRef(focusedIndex);

  const onRowFocused = useCallback(
    (index: number) => {
      pendingFocusRef.current = -1;
      setFocusedIndex(index);
      const viewport = viewportRef.current?.clientHeight ?? 0;
      const centered = index * ROW_STRIDE - (viewport - ROW_STRIDE) / 2;
      const max = Math.max(entries.length * ROW_STRIDE - viewport, 0);
      setScrollY(Math.max(0, Math.min(centered, max)));
    },
    [entries.length],
  );

  const screenActive = useScreenActive();
  const tabActive = useTabActive();
  const active = screenActive && tabActive;
  useEffect(() => {
    if (!active) return;
    return registerBackInterceptor(() => {
      onDismiss();
      return true;
    });
  }, [active, onDismiss]);

  // The dashboard's global key handlers (Red favorite, Green open-category,
  // Yellow open-picker, Channel ▲/▼ shelf hop) listen on window bubble phase
  // and stay mounted under this overlay — swallow those keys in capture phase
  // while the panel is up.
  useEffect(() => {
    if (!active) return;
    const swallow = (event: KeyboardEvent) => {
      const code = normalizeKeyCode(event);
      if (
        code === KEY.Red ||
        code === KEY.Green ||
        code === KEY.Yellow ||
        code === KEY.ChannelUp ||
        code === KEY.ChannelDown
      ) {
        event.stopPropagation();
      }
    };
    window.addEventListener("keydown", swallow, true);
    return () => window.removeEventListener("keydown", swallow, true);
  }, [active]);

  const first = Math.max(0, focusedIndex - ROW_WINDOW);
  const last = Math.min(entries.length - 1, focusedIndex + ROW_WINDOW);
  const visible = entries.slice(first, last + 1);

  return (
    <FocusContext.Provider value={focusKey}>
      <div className="category-picker-backdrop">
        <div ref={ref} className="category-picker">
          <h3>{t("category_picker.title")}</h3>
          <div ref={viewportRef} className="category-picker-list">
            <div
              className="category-picker-track"
              style={{ transform: `translateY(-${scrollY}px)` }}
            >
              {first > 0 && <div style={{ height: `${first * ROW_STRIDE}px` }} />}
              {visible.map((entry, offset) => {
                const index = first + offset;
                return (
                  <CategoryRow
                    key={entry.id}
                    entry={entry}
                    index={index}
                    active={entry.id === activeId}
                    autoFocus={index === pendingFocusRef.current}
                    onSelect={onSelect}
                    onFocused={onRowFocused}
                    onClose={onDismiss}
                  />
                );
              })}
            </div>
          </div>
        </div>
      </div>
    </FocusContext.Provider>
  );
}
