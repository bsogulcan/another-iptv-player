import {
  Children,
  createContext,
  ReactNode,
  useCallback,
  useContext,
  useRef,
  useState,
} from "react";
import {
  FocusContext,
  setFocus,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";

const INITIAL_VISIBLE = 30;
const EXTEND_BY = 30;
const EXTEND_THRESHOLD = 8;

const ShelfScrollContext = createContext<(el: HTMLElement) => void>(() => {});
/** Focus key of the shelf's header button (null → header not focusable). */
const ShelfHeaderContext = createContext<string | null>(null);

export function useShelfScroll(): (el: HTMLElement) => void {
  return useContext(ShelfScrollContext);
}

export function useShelfHeaderKey(): string | null {
  return useContext(ShelfHeaderContext);
}

/**
 * Horizontal focusable row with incremental reveal: more cards mount as focus
 * approaches the end (no "load more" card). The title becomes focusable when
 * `onHeaderSelect` is given (Enter → category detail); reach it with ← from
 * the first card or ↓ from the tab bar.
 */
export function Shelf({
  title,
  children,
  onRowFocused,
  onHeaderSelect,
  onEdgeLeft,
}: {
  title: string;
  children: ReactNode;
  onRowFocused?: () => void;
  onHeaderSelect?: () => void;
  /** ← past the row's left edge (header, or first card when no header). */
  onEdgeLeft?: () => void;
}) {
  const scrollerRef = useRef<HTMLDivElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  const [visibleCount, setVisibleCount] = useState(INITIAL_VISIBLE);
  // Transform-based scrolling (not scrollLeft): CSS-transitioned translateX
  // glides on the TV GPU, while scrollLeft jumps instantly on Chromium 56
  // (no smooth-scroll support there).
  const [scrollX, setScrollX] = useState(0);
  const scrollXRef = useRef(0);

  const onFocus = useCallback(() => {
    onRowFocused?.();
  }, [onRowFocused]);

  const { ref, focusKey } = useFocusable({
    trackChildren: true,
    onFocus,
    saveLastFocusedChild: true,
  });

  // The header registers under the screen container (not the shelf), so it
  // must drive the row-windowing callback itself, and ↓ must be routed to the
  // shelf's own cards explicitly — default spatial nav would jump to the next
  // shelf while the viewport stays put (focus vanishes off-window).
  const headerArrow = useCallback(
    (direction: string): boolean => {
      if (direction === "down") {
        const first = trackRef.current?.querySelector<HTMLElement>("[data-fk]");
        if (first?.dataset.fk) {
          setFocus(first.dataset.fk);
          return false;
        }
      }
      // ← at the left edge opens the category picker (panel slides in from
      // the left, so the gesture reads as "pull it in").
      if (direction === "left" && onEdgeLeft) {
        onEdgeLeft();
        return false;
      }
      return true;
    },
    [onEdgeLeft],
  );

  const header = useFocusable({
    focusable: Boolean(onHeaderSelect),
    onEnterPress: onHeaderSelect,
    onFocus,
    onArrowPress: headerArrow,
  });

  // Keep-in-view scroll + incremental reveal as focus nears the loaded end.
  const scrollToCard = useCallback((el: HTMLElement) => {
    const scroller = scrollerRef.current;
    const track = trackRef.current;
    if (!scroller || !track) return;

    const index = Array.prototype.indexOf.call(track.children, el);
    if (index >= 0) {
      setVisibleCount((current) =>
        index >= current - EXTEND_THRESHOLD ? current + EXTEND_BY : current,
      );
    }

    const margin = 90; // matches --safe-x so cards settle on the inset line
    const left = el.offsetLeft; // track is positioned → offsets are track-local
    const right = left + el.offsetWidth;
    const viewLeft = scrollXRef.current;
    const viewWidth = scroller.clientWidth;
    let next = viewLeft;
    if (left - margin < viewLeft) {
      next = Math.max(left - margin, 0);
    } else if (right + margin > viewLeft + viewWidth) {
      next = right + margin - viewWidth;
    }
    next = Math.min(next, Math.max(track.scrollWidth - viewWidth, 0));
    if (next !== viewLeft) {
      scrollXRef.current = next;
      setScrollX(next);
    }
  }, []);

  const kids = Children.toArray(children);
  const shown = kids.slice(0, visibleCount);

  return (
    <FocusContext.Provider value={focusKey}>
      <section ref={ref} className="shelf">
        {/* ref is attached in both branches: a registered focusable without a
            DOM node makes Norigin warn and can corrupt layout math. */}
        {onHeaderSelect ? (
          <h3
            ref={header.ref}
            className={`shelf-title focusable${header.focused ? " focused" : ""}`}
          >
            {title} <span className="shelf-title-chevron">›</span>
          </h3>
        ) : (
          <h3 ref={header.ref} className="shelf-title">
            {title}
          </h3>
        )}
        <div ref={scrollerRef} className="shelf-scroller">
          <div
            ref={trackRef}
            className="shelf-track"
            style={{ transform: `translateX(-${scrollX}px)` }}
          >
            <ShelfScrollContext.Provider value={scrollToCard}>
              <ShelfHeaderContext.Provider
                value={onHeaderSelect ? header.focusKey : null}
              >
                {shown}
              </ShelfHeaderContext.Provider>
            </ShelfScrollContext.Provider>
          </div>
        </div>
      </section>
    </FocusContext.Provider>
  );
}
