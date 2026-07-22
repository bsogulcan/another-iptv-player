import { memo, useCallback, useEffect, useRef, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { PlayableItem } from "../../models/playable";
import { registerBackInterceptor } from "../../navigation/backHandler";
import { t } from "../../i18n";

// Live-zapping side panel: the current queue (usually one category or M3U
// group) as a focusable vertical list over the playing video. Windowed like
// CategoryPickerPanel: live queues are routinely thousands of channels, and
// mounting a useFocusable row per channel froze the panel open and kept
// Norigin measuring thousands of candidates per keypress.

// Must match .channel-row height (60) + margin (8) in app.css.
const ROW_STRIDE = 68;
// Rows mounted above/below the focused one (~2 viewports' worth).
const ROW_WINDOW = 20;

// Memoized: the per-keypress panel re-render (focused index changes every
// arrow press) only touches the window edges, not every mounted row.
const ChannelRow = memo(function ChannelRow({
  item,
  index,
  active,
  autoFocus,
  onSelectIndex,
  onFocused,
}: {
  item: PlayableItem;
  index: number;
  active: boolean;
  autoFocus: boolean;
  onSelectIndex: (index: number) => void;
  onFocused: (index: number) => void;
}) {
  const { ref, focused, focusSelf } = useFocusable({
    onEnterPress: () => onSelectIndex(index),
    onFocus: () => onFocused(index),
  });
  useEffect(() => {
    if (autoFocus) focusSelf();
  }, [autoFocus, focusSelf]);
  const classes = ["channel-row"];
  if (active) classes.push("active");
  if (focused) classes.push("focused");
  return (
    <div ref={ref} className={classes.join(" ")}>
      {item.title}
    </div>
  );
});

export const LiveChannelPanel = memo(function LiveChannelPanel({
  items,
  currentIndex,
  onSelect,
  onDismiss,
}: {
  items: PlayableItem[];
  currentIndex: number;
  onSelect: (index: number) => void;
  onDismiss: () => void;
}) {
  const { ref, focusKey } = useFocusable({
    trackChildren: true,
    isFocusBoundary: true,
  });
  const viewportRef = useRef<HTMLDivElement>(null);

  // Windowed + transform-scrolled like the category picker: scrollTop jumps
  // instantly on old Chromium, while a CSS-transitioned translateY glides.
  const [focusedIndex, setFocusedIndex] = useState(currentIndex);
  // Pre-position near the current channel: starting at 0 would paint one
  // frame at the list top and then GLIDE thousands of px to the autofocused
  // row (the transitioned track animates every scrollY change). The exact
  // centering (needs the mounted viewport height) lands on first focus.
  const [scrollY, setScrollY] = useState(() =>
    Math.max(0, currentIndex * ROW_STRIDE - 416),
  );
  // One-shot: -1 once any row took focus, so a window-shift remount of the
  // initial row can never steal focus back mid-navigation.
  const pendingFocusRef = useRef(currentIndex);

  const onRowFocused = useCallback(
    (index: number) => {
      pendingFocusRef.current = -1;
      setFocusedIndex(index);
      const viewport = viewportRef.current?.clientHeight ?? 0;
      const centered = index * ROW_STRIDE - (viewport - ROW_STRIDE) / 2;
      const max = Math.max(items.length * ROW_STRIDE - viewport, 0);
      setScrollY(Math.max(0, Math.min(centered, max)));
    },
    [items.length],
  );

  useEffect(() => {
    return registerBackInterceptor(() => {
      onDismiss();
      return true;
    });
  }, [onDismiss]);

  const first = Math.max(0, focusedIndex - ROW_WINDOW);
  const last = Math.min(items.length - 1, focusedIndex + ROW_WINDOW);
  const visible = items.slice(first, last + 1);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="channel-panel">
        <h3>{t("player.all_channels")}</h3>
        <div ref={viewportRef} className="channel-panel-list">
          <div
            className="channel-panel-track"
            style={{ transform: `translateY(-${scrollY}px)` }}
          >
            {first > 0 && <div style={{ height: `${first * ROW_STRIDE}px` }} />}
            {visible.map((item, offset) => {
              const index = first + offset;
              return (
                <ChannelRow
                  key={`${item.historyStreamId}-${index}`}
                  item={item}
                  index={index}
                  active={index === currentIndex}
                  autoFocus={index === pendingFocusRef.current}
                  onSelectIndex={onSelect}
                  onFocused={onRowFocused}
                />
              );
            })}
          </div>
        </div>
      </div>
    </FocusContext.Provider>
  );
});
