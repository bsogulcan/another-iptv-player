import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  FocusContext,
  getCurrentFocusKey,
  setFocus,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { getDb } from "../../data/db";
import {
  CatalogKind,
  FavoriteKind,
  LiveStreamRecord,
  M3UChannelRecord,
  PlaylistRecord,
  SeriesRecord,
  VodStreamRecord,
  WatchHistoryRecord,
} from "../../data/records";
import { getFavorites, toggleFavorite } from "../../data/favoritesRepo";
import { groupChannels } from "../../data/m3uRepo";
import {
  CatalogSection,
  getCatalogSection,
  getM3UCatalog,
} from "../../data/catalogCache";
import { makeMatcher, sortLiveByRelevance } from "../../models/catalogTextSearch";
import {
  continueWatchingItems,
  progressRatio,
} from "../../services/continueWatching";
import {
  buildSeriesQueue,
  ensureSeriesInfo,
} from "../../services/seriesPlayback";
import { PlaybackUrlBuilder } from "../../api/playbackUrlBuilder";
import { PlayableItem } from "../../models/playable";
import { useNavigation } from "../../navigation/NavigationStack";
import { useScreenActive } from "../../navigation/ScreenLayer";
import { registerBackInterceptor } from "../../navigation/backHandler";
import { KEY, normalizeKeyCode } from "../../navigation/keys";
import { settings } from "../../data/settings";
import { t } from "../../i18n";
import { CardShape, FocusableCard } from "../components/FocusableCard";
import {
  CategoryEntry,
  CategoryPickerPanel,
} from "../components/CategoryPickerPanel";
import { SearchPill } from "../components/SearchPill";
import { Shelf } from "../components/Shelf";
import { TabBar, TabDescriptor } from "../components/TabBar";
import { TabLayer, useTabActive } from "../components/TabLayer";
import { getTabQuery, setTabQuery } from "../state/tabSearchMemory";
import { SettingsTab } from "./SettingsTab";

// Shelves reveal cards incrementally as focus scrolls right (see Shelf), but
// CardModel construction is still capped: building closures for a 50k-stream
// category up front would stall tab load. Beyond the cap → category grid.
const SHELF_ITEM_CAP = 250;
const ROW_WINDOW = 4;
const TABS_FOCUS_KEY = "dashboard-tabs";
const SEARCH_RESULT_CAP = 60;
const SEARCH_DEBOUNCE_MS = 300;

/** Color-key handlers must ignore keys typed into the search input. */
function isTypingTarget(event: KeyboardEvent): boolean {
  return (event.target as HTMLElement | null)?.tagName === "INPUT";
}

/** Search hits as a windowed grid: chunked rows, count on the first title. */
function chunkIntoRows(
  cards: CardModel[],
  shape: CardShape,
  totalMatches: number,
): RowModel[] {
  // Sized so a full row fits inside 1920 minus both safe-x insets.
  const perRow = 5;
  const rows: RowModel[] = [];
  for (let i = 0; i < cards.length; i += perRow) {
    rows.push({
      id: `search-${i}`,
      title: i === 0 ? t("tv.results_format", totalMatches) : "",
      shape,
      cards: cards.slice(i, i + perRow),
    });
  }
  return rows;
}

// Stable empty fallbacks: fresh [] per render would invalidate every memo
// keyed on the catalog arrays while the catalog is still loading.
const NO_RECORDS: never[] = [];

/** Tab re-activations refresh history from IDB but the data is usually
 *  identical — keeping the previous array identity then stops the refresh
 *  from cascading into full row/card-model rebuilds. */
function sameHistory(
  a: WatchHistoryRecord[],
  b: WatchHistoryRecord[],
): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (
      a[i].id !== b[i].id ||
      a[i].lastTimeMs !== b[i].lastTimeMs ||
      a[i].lastWatchedAt !== b[i].lastWatchedAt
    ) {
      return false;
    }
  }
  return true;
}

/** Debounced copy of the header search query. */
function useDebouncedQuery(query: string): string {
  const [debounced, setDebounced] = useState(query);
  useEffect(() => {
    const timer = window.setTimeout(
      () => setDebounced(query),
      SEARCH_DEBOUNCE_MS,
    );
    return () => window.clearTimeout(timer);
  }, [query]);
  return debounced;
}

export interface CardModel {
  id: string;
  title: string;
  subtitle?: string;
  imageURL?: string;
  shape: CardShape;
  rating?: string;
  progress?: number;
  favoriteKey?: { kind: FavoriteKind; itemId: string };
  onSelect: () => void;
}

export interface RowModel {
  id: string;
  title: string;
  shape: CardShape;
  cards: CardModel[];
  /** Real item count when cards are capped (category picker count chip). */
  totalCount?: number;
  /** Enter on the (focusable) shelf title → full category grid. */
  onOpenCategory?: () => void;
}

function rowHeight(row: RowModel): number {
  // Must track the card CSS sizes (tvOS pass): poster 320×480 + title,
  // landscape 320×180 + title, plus shelf title and focus-scale headroom.
  return row.shape === "poster" ? 640 : 350;
}

// Row-aligned vertical navigation: Norigin only considers same-container
// siblings, so entering a fresh row would land on its first card. Cards route
// ↑/↓ here instead and we focus the target row's horizontally-closest card.
const RowIndexContext = createContext(0);
const RowNavContext = createContext<
  (rowIndex: number, direction: string, fromEl: HTMLElement) => boolean
>(() => false);
// ← past a row's left edge → open the category picker (see WindowedRows).
const EdgeLeftContext = createContext<(() => void) | null>(null);

/** Category-picker jump target; the nonce re-fires jumps to the same row. */
export interface RowJumpRequest {
  rowId: string;
  nonce: number;
}

/** Vertically-windowed shelf list: only rows near focus render their cards. */
export function WindowedRows({
  rows,
  favoriteIds,
  onCardFocused,
  resetKey = 0,
  jumpRequest = null,
  onFocusedRowChange,
  onEdgeLeft,
}: {
  rows: RowModel[];
  favoriteIds: Set<string>;
  onCardFocused: (card: CardModel) => void;
  /** Bumped when Back refocuses the tab bar: scrolls the rows back to top. */
  resetKey?: number;
  /** Scroll to this row and focus its first card (category picker). */
  jumpRequest?: RowJumpRequest | null;
  /** Reports which row holds focus (the picker's active highlight). */
  onFocusedRowChange?: (rowId: string | null) => void;
  /** ← past any row's left edge (opens the category picker). */
  onEdgeLeft?: () => void;
}) {
  const [focusedRow, setFocusedRow] = useState(0);
  const contentRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    onFocusedRowChange?.(rows[focusedRow]?.id ?? null);
  }, [rows, focusedRow, onFocusedRowChange]);

  // Jump from the category picker in two committed steps: setFocusedRow first
  // so the windowing mounts the target row's cards, then focus its first card.
  // Kept pending across renders because the target row may only exist after a
  // cleared search re-materializes the shelf rows (debounced).
  const pendingJumpRef = useRef<RowJumpRequest | null>(null);
  // Channel-key hops set the pending ref directly and kick the executor.
  const [jumpKick, setJumpKick] = useState(0);
  const requestRowJump = useCallback((rowId: string) => {
    pendingJumpRef.current = { rowId, nonce: -1 };
    setJumpKick((n) => n + 1);
  }, []);
  useEffect(() => {
    pendingJumpRef.current = jumpRequest ?? null;
  }, [jumpRequest]);
  useEffect(() => {
    const pending = pendingJumpRef.current;
    if (!pending) return;
    const index = rows.findIndex((row) => row.id === pending.rowId);
    if (index < 0) return;
    if (index !== focusedRow) {
      setFocusedRow(index);
      return; // re-runs once the row window includes the target
    }
    const first = contentRef.current?.querySelector<HTMLElement>(
      `[data-row-index="${index}"] [data-fk]`,
    );
    if (first?.dataset.fk) {
      pendingJumpRef.current = null;
      setFocus(first.dataset.fk);
    }
  }, [rows, focusedRow, jumpRequest, jumpKick]);

  // Only the visible tab rewinds on Back: hidden sibling tabs keep their
  // position and must not retro-reset when they become visible again (the
  // ref keeps stale bumps from re-running the effect on re-activation).
  const tabActive = useTabActive();
  const tabActiveRef = useRef(tabActive);
  tabActiveRef.current = tabActive;
  useEffect(() => {
    if (tabActiveRef.current) setFocusedRow(0);
  }, [resetKey]);

  const navigateRows = useCallback(
    (rowIndex: number, direction: string, fromEl: HTMLElement): boolean => {
      const target = rowIndex + (direction === "down" ? 1 : -1);
      const rowEl = contentRef.current?.querySelector(
        `[data-row-index="${target}"]`,
      );
      if (!rowEl) return false; // out of rows → default nav (e.g. up to tabs)
      const candidates = rowEl.querySelectorAll<HTMLElement>("[data-fk]");
      if (candidates.length === 0) return false;
      const from = fromEl.getBoundingClientRect();
      const fromCenter = from.left + from.width / 2;
      let best: HTMLElement | null = null;
      let bestDistance = Infinity;
      candidates.forEach((candidate) => {
        const rect = candidate.getBoundingClientRect();
        const distance = Math.abs(rect.left + rect.width / 2 - fromCenter);
        if (distance < bestDistance) {
          bestDistance = distance;
          best = candidate;
        }
      });
      const focusKey = best ? (best as HTMLElement).dataset.fk : undefined;
      if (!focusKey) return false;
      setFocus(focusKey);
      return true;
    },
    [],
  );

  // Green color key: open the focused row's category from anywhere in the row.
  const screenActive = useScreenActive();
  useEffect(() => {
    if (!screenActive || !tabActive) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (isTypingTarget(event)) return;
      if (normalizeKeyCode(event) !== KEY.Green) return;
      rows[focusedRow]?.onOpenCategory?.();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [rows, focusedRow, screenActive, tabActive]);

  // Clamp: the instance survives the shelves ↔ search-grid swap (same child
  // position), so a deep focusedRow from the longer list must not window-out
  // every row of the shorter one (blank screen with zero focusables).
  const effectiveRow = Math.max(0, Math.min(focusedRow, rows.length - 1));

  // Channel ▲/▼ hops straight to the previous/next shelf (its first card) —
  // fast category surfing without opening the picker.
  useEffect(() => {
    if (!screenActive || !tabActive) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (isTypingTarget(event)) return;
      const code = normalizeKeyCode(event);
      if (code !== KEY.ChannelUp && code !== KEY.ChannelDown) return;
      event.preventDefault();
      const target = effectiveRow + (code === KEY.ChannelDown ? 1 : -1);
      const row = rows[target];
      if (row) requestRowJump(row.id);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [rows, effectiveRow, screenActive, tabActive, requestRowJump]);

  const offsetY = useMemo(() => {
    let sum = 0;
    for (let i = 0; i < effectiveRow && i < rows.length; i++) {
      sum += rowHeight(rows[i]);
    }
    return sum;
  }, [rows, effectiveRow]);

  return (
    <div className="rows-viewport">
      <div
        ref={contentRef}
        className="rows-content"
        style={{ transform: `translateY(-${offsetY}px)` }}
      >
        <RowNavContext.Provider value={navigateRows}>
          <EdgeLeftContext.Provider value={onEdgeLeft ?? null}>
          {rows.map((row, index) => {
            const visible = Math.abs(index - effectiveRow) <= ROW_WINDOW;
            if (!visible) {
              return (
                <div
                  key={row.id}
                  style={{ height: `${rowHeight(row)}px` }}
                  className="row-placeholder"
                />
              );
            }
            return (
              <div
                key={row.id}
                data-row-index={index}
                style={{ height: `${rowHeight(row)}px` }}
              >
                <RowIndexContext.Provider value={index}>
                  <Shelf
                    title={row.title}
                    onRowFocused={() => setFocusedRow(index)}
                    onHeaderSelect={row.onOpenCategory}
                    onEdgeLeft={onEdgeLeft}
                  >
                    {row.cards.map((card) => (
                      <ShelfCard
                        key={card.id}
                        card={card}
                        favorite={
                          card.favoriteKey
                            ? favoriteIds.has(
                                `${card.favoriteKey.kind}_${card.favoriteKey.itemId}`,
                              )
                            : false
                        }
                        onCardFocused={onCardFocused}
                      />
                    ))}
                  </Shelf>
                </RowIndexContext.Provider>
              </div>
            );
          })}
          </EdgeLeftContext.Provider>
        </RowNavContext.Provider>
      </div>
    </div>
  );
}

import { memo } from "react";
import { useShelfHeaderKey, useShelfScroll } from "../components/Shelf";

// Memoized: dashboards re-render on row focus changes, and hundreds of cards
// re-rendering per keypress is what makes TV navigation feel sluggish.
const ShelfCard = memo(function ShelfCard({
  card,
  favorite,
  onCardFocused,
}: {
  card: CardModel;
  favorite: boolean;
  onCardFocused: (card: CardModel) => void;
}) {
  const scrollToCard = useShelfScroll();
  const headerKey = useShelfHeaderKey();
  const rowIndex = useContext(RowIndexContext);
  const navigateRows = useContext(RowNavContext);
  const onEdgeLeft = useContext(EdgeLeftContext);

  const onFocusedElement = useCallback(
    (el: HTMLElement) => {
      scrollToCard(el);
      onCardFocused(card);
    },
    [scrollToCard, onCardFocused, card],
  );

  // Returning false consumes the key (row-aligned vertical hop performed).
  const onArrowPress = useCallback(
    (direction: string, el: HTMLElement | null) => {
      if ((direction === "up" || direction === "down") && el) {
        return !navigateRows(rowIndex, direction, el);
      }
      // ← on the first card: shelf title when focusable (category entry
      // point), otherwise the category picker (left-edge gesture).
      if (direction === "left" && el && el.previousElementSibling === null) {
        if (headerKey) {
          setFocus(headerKey);
          return false;
        }
        if (onEdgeLeft) {
          onEdgeLeft();
          return false;
        }
      }
      return true;
    },
    [navigateRows, rowIndex, headerKey, onEdgeLeft],
  );

  return (
    <FocusableCard
      title={card.title}
      subtitle={card.subtitle}
      imageURL={card.imageURL}
      shape={card.shape}
      rating={card.rating}
      progress={card.progress}
      favorite={favorite}
      onSelect={card.onSelect}
      onFocusedElement={onFocusedElement}
      onArrowPress={onArrowPress}
    />
  );
});

// MARK: - Category picker (shared by Xtream tabs and M3U browse)

/** Header pill next to search; the yellow dot mirrors the color-key shortcut. */
function CategoryPill({ onOpen }: { onOpen: () => void }) {
  const { ref, focused } = useFocusable({ onEnterPress: onOpen });
  return (
    <div ref={ref} className={`category-pill${focused ? " focused" : ""}`}>
      <span className="category-pill-dot" />
      {t("category_picker.title")}
    </div>
  );
}

/**
 * Open/close state, Yellow-key shortcut and the jump handshake for the
 * category picker. `clearSearch` runs on select so the shelf rows (the jump
 * targets) are visible again when a search grid was showing.
 */
function useCategoryPicker(active: boolean, clearSearch: () => void) {
  const [pickerOpen, setPickerOpen] = useState(false);
  const [jumpRequest, setJumpRequest] = useState<RowJumpRequest | null>(null);
  const activeRowIdRef = useRef<string | null>(null);
  // Where focus was when the picker opened: restored on plain Back dismiss
  // (the rows stay mounted under the overlay, so the key remains valid).
  const restoreKeyRef = useRef<string | null>(null);

  const onFocusedRowChange = useCallback((rowId: string | null) => {
    activeRowIdRef.current = rowId;
  }, []);

  const openPicker = useCallback(() => {
    restoreKeyRef.current = getCurrentFocusKey() ?? null;
    setPickerOpen(true);
  }, []);

  const dismissPicker = useCallback(() => {
    setPickerOpen(false);
    if (restoreKeyRef.current) setFocus(restoreKeyRef.current);
  }, []);

  const selectCategory = useCallback(
    (rowId: string) => {
      setPickerOpen(false);
      clearSearch();
      setJumpRequest((prev) => ({ rowId, nonce: (prev?.nonce ?? 0) + 1 }));
    },
    [clearSearch],
  );

  // Yellow color key opens the picker from anywhere in the tab.
  useEffect(() => {
    if (!active || pickerOpen) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (isTypingTarget(event)) return;
      if (normalizeKeyCode(event) !== KEY.Yellow) return;
      openPicker();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [active, pickerOpen, openPicker]);

  return {
    pickerOpen,
    openPicker,
    dismissPicker,
    selectCategory,
    jumpRequest,
    onFocusedRowChange,
    activeRowIdRef,
  };
}

// MARK: - Xtream content tab

function useFavoriteIds(playlistId: string, reloadKey: number): Set<string> {
  const [ids, setIds] = useState<Set<string>>(new Set());
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      const favorites = await getFavorites(db, playlistId);
      if (!cancelled) {
        const next = new Set(favorites.map((f) => `${f.kind}_${f.itemId}`));
        // Same contents → keep the previous Set identity so unchanged
        // refreshes (every tab re-activation) don't re-render the rows.
        setIds((prev) =>
          prev.size === next.size && Array.from(next).every((id) => prev.has(id))
            ? prev
            : next,
        );
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [playlistId, reloadKey]);
  return ids;
}

export function ContentTab({
  playlist,
  kind,
  resetKey,
}: {
  playlist: PlaylistRecord;
  kind: CatalogKind;
  resetKey?: number;
}) {
  const { push } = useNavigation();
  const [section, setSection] = useState<CatalogSection | null>(null);
  const [history, setHistory] = useState<WatchHistoryRecord[]>([]);
  const [refreshKey, setRefreshKey] = useState(0);
  // Query state lives in the tab (kept alive by TabLayer); the module-level
  // memory only bridges the dashboard unmounting (exit to playlist list).
  const [searchQuery, setSearchQuery] = useState(() =>
    getTabQuery(playlist.id, kind),
  );
  const onSearchChange = useCallback(
    (value: string) => {
      setTabQuery(playlist.id, kind, value);
      setSearchQuery(value);
    },
    [playlist.id, kind],
  );
  // Ref, not state: focus tracking must not re-render the whole tab per keypress.
  const screenActive = useScreenActive();
  const tabActive = useTabActive();
  const active = screenActive && tabActive;
  const focusedCardRef = useRef<CardModel | null>(null);
  const onCardFocused = useCallback((card: CardModel) => {
    focusedCardRef.current = card;
  }, []);
  const favoriteIds = useFavoriteIds(playlist.id, refreshKey);

  // Hidden layers (covering screens, sibling tabs) can change favorites and
  // watch history while this tab stays mounted — refresh on becoming the
  // visible tab again.
  useEffect(() => {
    if (active) setRefreshKey((n) => n + 1);
  }, [active]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      // Cached per section after the first load: tab switches and pop-backs
      // are instant, and this tab only ever materializes its own kind.
      const [loaded, hist] = await Promise.all([
        getCatalogSection(db, playlist, kind),
        continueWatchingItems(db, playlist.id, kind),
      ]);
      if (cancelled) return;
      // The catalog cache returns the same object identity for unchanged
      // data, and sameHistory keeps the array identity — so a no-op refresh
      // re-renders nothing at all.
      setSection(loaded);
      setHistory((prev) => (sameHistory(prev, hist) ? prev : hist));
    })();
    return () => {
      cancelled = true;
    };
  }, [playlist, kind, refreshKey]);

  const categories = section?.categories ?? NO_RECORDS;
  const items = section?.items ?? NO_RECORDS;

  const urls = useMemo(() => new PlaybackUrlBuilder(playlist), [playlist]);

  const liveItem = useCallback(
    (stream: LiveStreamRecord): PlayableItem => ({
      url: urls.liveUrl(stream.streamId),
      title: stream.name,
      imageURL: stream.icon,
      isLive: true,
      historyType: "live",
      historyStreamId: String(stream.streamId),
    }),
    [urls],
  );

  // Live playback carries the whole category as the queue so Up/Down and the
  // Blue-key panel zap within it (iOS live side-panel equivalent).
  const playLive = useCallback(
    (stream: LiveStreamRecord) => {
      // Only reachable from the live tab, where items are LiveStreamRecords.
      const siblings = (items as LiveStreamRecord[]).filter(
        (s) => s.categoryId === stream.categoryId,
      );
      const queue = (siblings.length > 0 ? siblings : [stream]).map(liveItem);
      const startIndex = Math.max(
        queue.findIndex((q) => q.historyStreamId === String(stream.streamId)),
        0,
      );
      push({ name: "player", playlist, items: queue, startIndex });
    },
    [items, liveItem, push, playlist],
  );

  const openMovie = useCallback(
    (stream: VodStreamRecord) => {
      push({ name: "movieDetail", playlist, vodId: stream.streamId });
    },
    [push, playlist],
  );

  const cardFor = useCallback(
    (record: LiveStreamRecord | VodStreamRecord | SeriesRecord): CardModel => {
      if (kind === "live") {
        const stream = record as LiveStreamRecord;
        return {
          id: `live-${stream.streamId}`,
          title: stream.name,
          imageURL: stream.icon,
          shape: "landscape",
          favoriteKey: { kind: "live", itemId: String(stream.streamId) },
          onSelect: () => playLive(stream),
        };
      }
      if (kind === "vod") {
        const stream = record as VodStreamRecord;
        return {
          id: `vod-${stream.streamId}`,
          title: stream.name,
          rating: stream.rating,
          imageURL: stream.icon,
          shape: "poster",
          favoriteKey: { kind: "vod", itemId: String(stream.streamId) },
          onSelect: () => openMovie(stream),
        };
      }
      const item = record as SeriesRecord;
      return {
        id: `series-${item.seriesId}`,
        title: item.name,
        rating: item.rating,
        imageURL: item.cover,
        shape: "poster",
        favoriteKey: { kind: "series", itemId: String(item.seriesId) },
        onSelect: () =>
          push({ name: "seriesDetail", playlist, seriesId: item.seriesId }),
      };
    },
    [kind, playLive, openMovie, push, playlist],
  );

  // Row building is deliberately split into independent memos: history and
  // favorites refresh on EVERY tab re-activation, and as a single memo that
  // cascaded into rebuilding card-model closures for every category (tens of
  // thousands of objects on big playlists — the tab-switch hitch). Category
  // shelves now only rebuild when the catalog itself changes.
  const byId = useMemo(() => {
    const map = new Map<
      string,
      LiveStreamRecord | VodStreamRecord | SeriesRecord
    >();
    for (const record of items) {
      const key =
        kind === "series"
          ? String((record as SeriesRecord).seriesId)
          : String((record as LiveStreamRecord | VodStreamRecord).streamId);
      map.set(key, record);
    }
    return map;
  }, [kind, items]);

  const continueRow = useMemo((): RowModel | null => {
    if (history.length === 0) return null;
    // Movie/series artwork is portrait: continue-watching renders as posters
    // there (landscape squeezed them); live channel logos stay landscape.
    const continueShape: CardShape = kind === "live" ? "landscape" : "poster";
    return {
      id: "continue",
      title: t("continue_watching.title"),
      shape: continueShape,
      cards: history.map((entry) => ({
        id: `history-${entry.id}`,
        title: entry.title,
        subtitle: entry.secondaryTitle,
        imageURL: entry.imageURL,
        shape: continueShape,
        progress: progressRatio(entry),
        onSelect: () => {
          if (entry.type === "series" && entry.seriesId !== undefined) {
            // Straight into the episode with resume (iOS
            // HistorySeriesPlayerShell); detail screen only as fallback.
            const seriesId = entry.seriesId;
            void (async () => {
              const db = await getDb();
              // Series-type history only appears in the series tab, where
              // this section's items are SeriesRecords.
              const seriesRecord = (
                (section?.items ?? []) as SeriesRecord[]
              ).find((item) => item.seriesId === seriesId);
              const info = await ensureSeriesInfo(db, playlist, seriesId);
              if (!info || !seriesRecord || info.episodes.length === 0) {
                push({ name: "seriesDetail", playlist, seriesId });
                return;
              }
              const queue = buildSeriesQueue(
                playlist,
                seriesId,
                seriesRecord.name,
                seriesRecord.cover,
                info,
              );
              const startIndex = Math.max(
                queue.findIndex(
                  (item) => item.historyStreamId === entry.streamId,
                ),
                0,
              );
              push({ name: "player", playlist, items: queue, startIndex });
            })();
            return;
          }
          const record = byId.get(entry.streamId);
          if (!record) return;
          if (entry.type === "live") playLive(record as LiveStreamRecord);
          else openMovie(record as VodStreamRecord);
        },
      })),
    };
  }, [history, byId, kind, section, playLive, openMovie, push, playlist]);

  // iOS parity (VODView/SeriesView): "Recently Added" right after continue
  // watching — vod sorts by `added`, series by `lastModified` (unix-seconds
  // strings), limited to visible categories, newest 20.
  const recentRow = useMemo((): RowModel | null => {
    if (kind !== "vod" && kind !== "series") return null;
    const visibleCategoryIds = new Set(
      categories.map((category) => category.categoryId),
    );
    const stamped: { record: VodStreamRecord | SeriesRecord; ts: number }[] =
      [];
    for (const record of items as (VodStreamRecord | SeriesRecord)[]) {
      if (!record.categoryId || !visibleCategoryIds.has(record.categoryId)) {
        continue;
      }
      const raw =
        kind === "vod"
          ? (record as VodStreamRecord).added
          : (record as SeriesRecord).lastModified;
      const ts = raw !== undefined ? parseInt(raw, 10) : NaN;
      if (isFinite(ts)) stamped.push({ record, ts });
    }
    if (stamped.length === 0) return null;
    stamped.sort((a, b) => b.ts - a.ts);
    return {
      id: "recent",
      title: t("recently_added.title"),
      shape: "poster",
      cards: stamped.slice(0, 20).map((entry) => cardFor(entry.record)),
    };
  }, [kind, items, categories, cardFor]);

  const favoritesRow = useMemo((): RowModel | null => {
    const shape: CardShape = kind === "live" ? "landscape" : "poster";
    const favoriteCards: CardModel[] = [];
    for (const id of favoriteIds) {
      if (id.indexOf(`${kind}_`) !== 0) continue;
      const itemId = id.slice(kind.length + 1);
      const record = byId.get(itemId);
      if (record) favoriteCards.push(cardFor(record));
    }
    if (favoriteCards.length === 0) return null;
    return {
      id: "favorites",
      title: t("favorites.title"),
      shape,
      totalCount: favoriteCards.length,
      cards: favoriteCards.slice(0, SHELF_ITEM_CAP),
    };
  }, [favoriteIds, kind, byId, cardFor]);

  const categoryRows = useMemo((): RowModel[] => {
    const shape: CardShape = kind === "live" ? "landscape" : "poster";
    const byCategory = section?.byCategory;
    const result: RowModel[] = [];
    for (const category of categories) {
      const items = byCategory?.get(category.categoryId) ?? [];
      if (items.length === 0) continue;
      result.push({
        id: `cat-${category.categoryId}`,
        title: category.name,
        shape,
        totalCount: items.length,
        cards: items.slice(0, SHELF_ITEM_CAP).map(cardFor),
        onOpenCategory: () =>
          push({
            name: "categoryGrid",
            playlist,
            kind,
            categoryId: category.categoryId,
            title: category.name,
          }),
      });
    }
    return result;
  }, [kind, section, categories, cardFor, push, playlist]);

  const rows = useMemo((): RowModel[] => {
    const result: RowModel[] = [];
    if (continueRow) result.push(continueRow);
    if (recentRow) result.push(recentRow);
    if (favoritesRow) result.push(favoritesRow);
    result.push(...categoryRows);
    return result;
  }, [continueRow, recentRow, favoritesRow, categoryRows]);

  // Red key toggles favorite on the focused card. Gated on the tab being the
  // visible one: every mounted tab hears window keydowns.
  useEffect(() => {
    if (!active) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (isTypingTarget(event)) return;
      if (normalizeKeyCode(event) !== KEY.Red) return;
      const key = focusedCardRef.current?.favoriteKey;
      if (!key) return;
      void (async () => {
        const db = await getDb();
        await toggleFavorite(db, playlist.id, key.kind, key.itemId);
        setRefreshKey((n) => n + 1);
      })();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [playlist.id, active]);

  // Header search scoped to this tab's kind: ≥2 chars replaces the shelves
  // with a result grid; favoriting keeps working via cardFor's favoriteKey.
  const debouncedQuery = useDebouncedQuery(searchQuery);
  const searchRows = useMemo((): RowModel[] | null => {
    const trimmed = debouncedQuery.trim();
    if (trimmed.length < 2) return null;
    const shape: CardShape = kind === "live" ? "landscape" : "poster";
    const match = makeMatcher(trimmed);
    if (kind === "series") {
      const hits = items.filter((item) => match(item.name));
      return chunkIntoRows(
        hits.slice(0, SEARCH_RESULT_CAP).map(cardFor),
        shape,
        hits.length,
      );
    }
    const hits = sortLiveByRelevance(
      items
        .filter((stream) => match(stream.name))
        .map((stream) => ({ stream })),
      trimmed,
    );
    return chunkIntoRows(
      hits.slice(0, SEARCH_RESULT_CAP).map(({ stream }) => cardFor(stream)),
      shape,
      hits.length,
    );
  }, [debouncedQuery, kind, items, cardFor]);

  const clearSearch = useCallback(() => onSearchChange(""), [onSearchChange]);
  const picker = useCategoryPicker(active, clearSearch);
  const pickerEntries = useMemo(
    (): CategoryEntry[] =>
      rows.map((row) => ({
        id: row.id,
        title: row.title,
        count: row.totalCount ?? row.cards.length,
      })),
    [rows],
  );
  const onEdgeLeft = pickerEntries.length > 0 ? picker.openPicker : undefined;

  const body =
    searchRows !== null ? (
      searchRows.length === 0 ? (
        <p className="screen-hint">{t("favorites.empty.no_result.title")}</p>
      ) : (
        <WindowedRows
          rows={searchRows}
          favoriteIds={favoriteIds}
          onCardFocused={onCardFocused}
          resetKey={resetKey}
          jumpRequest={picker.jumpRequest}
          onFocusedRowChange={picker.onFocusedRowChange}
          onEdgeLeft={onEdgeLeft}
        />
      )
    ) : rows.length === 0 ? (
      <p className="screen-hint">{t("common.loading")}</p>
    ) : (
      <WindowedRows
        rows={rows}
        favoriteIds={favoriteIds}
        onCardFocused={onCardFocused}
        resetKey={resetKey}
        jumpRequest={picker.jumpRequest}
        onFocusedRowChange={picker.onFocusedRowChange}
        onEdgeLeft={onEdgeLeft}
      />
    );

  return (
    <div className="tab-content">
      <div className="tab-search-row">
        <SearchPill
          value={searchQuery}
          placeholder={t("search.placeholder")}
          onChange={onSearchChange}
        />
        {pickerEntries.length > 0 && (
          <CategoryPill onOpen={picker.openPicker} />
        )}
      </div>
      {body}
      {picker.pickerOpen && (
        <CategoryPickerPanel
          entries={pickerEntries}
          activeId={picker.activeRowIdRef.current}
          onSelect={picker.selectCategory}
          onDismiss={picker.dismissPicker}
        />
      )}
    </div>
  );
}

// MARK: - M3U browse tab

export function M3UBrowseTab({
  playlist,
  resetKey,
}: {
  playlist: PlaylistRecord;
  resetKey?: number;
}) {
  const { push } = useNavigation();
  const [channels, setChannels] = useState<M3UChannelRecord[]>([]);
  const [history, setHistory] = useState<WatchHistoryRecord[]>([]);
  const [refreshKey, setRefreshKey] = useState(0);
  const [searchQuery, setSearchQuery] = useState(() =>
    getTabQuery(playlist.id, "browse"),
  );
  const onSearchChange = useCallback(
    (value: string) => {
      setTabQuery(playlist.id, "browse", value);
      setSearchQuery(value);
    },
    [playlist.id],
  );
  const screenActive = useScreenActive();
  const tabActive = useTabActive();
  const active = screenActive && tabActive;
  const focusedCardRef = useRef<CardModel | null>(null);
  const onCardFocused = useCallback((card: CardModel) => {
    focusedCardRef.current = card;
  }, []);
  const favoriteIds = useFavoriteIds(playlist.id, refreshKey);

  // Same staleness guard as ContentTab: refresh on becoming visible again.
  useEffect(() => {
    if (active) setRefreshKey((n) => n + 1);
  }, [active]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      const [loaded, hist] = await Promise.all([
        getM3UCatalog(db, playlist),
        continueWatchingItems(db, playlist.id, "live"),
      ]);
      if (!cancelled) {
        setChannels(loaded);
        setHistory((prev) => (sameHistory(prev, hist) ? prev : hist));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [playlist, refreshKey]);

  const playChannel = useCallback(
    (channel: M3UChannelRecord) => {
      // Queue = the channel's group, enabling Up/Down zapping in the player.
      const group = channel.groupTitle?.trim() || t("m3u.ungrouped_label");
      const siblings = channels.filter(
        (c) => (c.groupTitle?.trim() || t("m3u.ungrouped_label")) === group,
      );
      const queue: PlayableItem[] = (siblings.length > 0 ? siblings : [channel]).map(
        (c) => ({
          url: c.url,
          title: c.name,
          imageURL: c.tvgLogo,
          isLive: true,
          historyType: "live" as const,
          historyStreamId: c.id,
          userAgent: c.userAgent,
        }),
      );
      const startIndex = Math.max(
        queue.findIndex((q) => q.historyStreamId === channel.id),
        0,
      );
      push({ name: "player", playlist, items: queue, startIndex });
    },
    [channels, push, playlist],
  );

  // Split like ContentTab: the group shelves (the expensive part on 50k+
  // channel lists) only rebuild when the channel list itself changes, not on
  // every history refresh from a tab re-activation.
  const continueRow = useMemo((): RowModel | null => {
    if (history.length === 0) return null;
    const byId = new Map(channels.map((c) => [c.id, c]));
    return {
      id: "continue",
      title: t("continue_watching.title"),
      shape: "landscape",
      cards: history.map((entry) => ({
        id: `history-${entry.id}`,
        title: entry.title,
        imageURL: entry.imageURL,
        shape: "landscape",
        onSelect: () => {
          const channel = byId.get(entry.streamId);
          if (channel) playChannel(channel);
        },
      })),
    };
  }, [history, channels, playChannel]);

  const groupRows = useMemo((): RowModel[] => {
    const grouped = groupChannels(channels, t("m3u.ungrouped_label"));
    const result: RowModel[] = [];
    for (const groupName of grouped.groupNames) {
      const items = grouped.channelsByGroup.get(groupName) ?? [];
      result.push({
        id: `group-${groupName}`,
        title: groupName,
        shape: "landscape",
        totalCount: items.length,
        cards: items.slice(0, SHELF_ITEM_CAP).map((channel) => ({
          id: channel.id,
          title: channel.name,
          imageURL: channel.tvgLogo,
          shape: "landscape",
          favoriteKey: { kind: "m3u", itemId: channel.id },
          onSelect: () => playChannel(channel),
        })),
        onOpenCategory: () =>
          push({
            name: "categoryGrid",
            playlist,
            kind: "m3uGroup",
            categoryId: groupName,
            title: groupName,
          }),
      });
    }
    return result;
  }, [channels, playChannel, push, playlist]);

  const rows = useMemo(
    (): RowModel[] => (continueRow ? [continueRow, ...groupRows] : groupRows),
    [continueRow, groupRows],
  );

  useEffect(() => {
    if (!active) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (isTypingTarget(event)) return;
      if (normalizeKeyCode(event) !== KEY.Red) return;
      const key = focusedCardRef.current?.favoriteKey;
      if (!key) return;
      void (async () => {
        const db = await getDb();
        await toggleFavorite(db, playlist.id, key.kind, key.itemId);
        setRefreshKey((n) => n + 1);
      })();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [playlist.id, active]);

  const debouncedQuery = useDebouncedQuery(searchQuery);
  const searchRows = useMemo((): RowModel[] | null => {
    const trimmed = debouncedQuery.trim();
    if (trimmed.length < 2) return null;
    const match = makeMatcher(trimmed);
    const hits = sortLiveByRelevance(
      channels
        .filter((channel) => match(channel.name))
        .map((channel) => ({ stream: channel, channel })),
      trimmed,
    );
    const cards = hits
      .slice(0, SEARCH_RESULT_CAP)
      .map(({ channel }): CardModel => ({
        id: channel.id,
        title: channel.name,
        imageURL: channel.tvgLogo,
        shape: "landscape",
        favoriteKey: { kind: "m3u", itemId: channel.id },
        onSelect: () => playChannel(channel),
      }));
    return chunkIntoRows(cards, "landscape", hits.length);
  }, [debouncedQuery, channels, playChannel]);

  const clearSearch = useCallback(() => onSearchChange(""), [onSearchChange]);
  const picker = useCategoryPicker(active, clearSearch);
  const pickerEntries = useMemo(
    (): CategoryEntry[] =>
      rows.map((row) => ({
        id: row.id,
        title: row.title,
        count: row.totalCount ?? row.cards.length,
      })),
    [rows],
  );
  const onEdgeLeft = pickerEntries.length > 0 ? picker.openPicker : undefined;

  const body =
    searchRows !== null ? (
      searchRows.length === 0 ? (
        <p className="screen-hint">{t("favorites.empty.no_result.title")}</p>
      ) : (
        <WindowedRows
          rows={searchRows}
          favoriteIds={favoriteIds}
          onCardFocused={onCardFocused}
          resetKey={resetKey}
          jumpRequest={picker.jumpRequest}
          onFocusedRowChange={picker.onFocusedRowChange}
          onEdgeLeft={onEdgeLeft}
        />
      )
    ) : rows.length === 0 ? (
      <p className="screen-hint">{t("common.loading")}</p>
    ) : (
      <WindowedRows
        rows={rows}
        favoriteIds={favoriteIds}
        onCardFocused={onCardFocused}
        resetKey={resetKey}
        jumpRequest={picker.jumpRequest}
        onFocusedRowChange={picker.onFocusedRowChange}
        onEdgeLeft={onEdgeLeft}
      />
    );

  return (
    <div className="tab-content">
      <div className="tab-search-row">
        <SearchPill
          value={searchQuery}
          placeholder={t("search.placeholder")}
          onChange={onSearchChange}
        />
        {pickerEntries.length > 0 && (
          <CategoryPill onOpen={picker.openPicker} />
        )}
      </div>
      {body}
      {picker.pickerOpen && (
        <CategoryPickerPanel
          entries={pickerEntries}
          activeId={picker.activeRowIdRef.current}
          onSelect={picker.selectCategory}
          onDismiss={picker.dismissPicker}
        />
      )}
    </div>
  );
}

// MARK: - Dashboard shell

export function DashboardScreen({ playlist: initial }: { playlist: PlaylistRecord }) {
  // Settings can update the playlist (adult filter); keep a live copy.
  const [playlist, setPlaylist] = useState(initial);
  const isM3U = playlist.type === "m3u";
  // Search is scoped per content tab (header pill), not a tab of its own.
  const tabs: TabDescriptor[] = isM3U
    ? [
        { id: "browse", label: t("dashboard.channels") },
        { id: "settings", label: t("dashboard.settings") },
      ]
    : [
        { id: "live", label: t("dashboard.live") },
        { id: "vod", label: t("dashboard.movies") },
        { id: "series", label: t("dashboard.series") },
        { id: "settings", label: t("dashboard.settings") },
      ];

  const initialTab =
    tabs[settings.dashboardTab]?.id ?? tabs[0].id;
  const [activeTab, setActiveTab] = useState(initialTab);
  // Visited tabs stay mounted (see TabLayer) so their state survives tab
  // switches; unvisited ones are not built at all (TV memory).
  const [visited, setVisited] = useState<ReadonlySet<string>>(
    () => new Set([initialTab]),
  );

  // Back inside content refocuses the tab bar; only a second Back (while the
  // tabs are focused) leaves the dashboard.
  const tabsFocused = useRef(false);
  const onTabsFocusedChange = useCallback((hasFocus: boolean) => {
    tabsFocused.current = hasFocus;
  }, []);
  // Back from inside the content also rewinds the rows to the top so the
  // tab bar isn't focused over a half-scrolled page.
  const [contentResetKey, setContentResetKey] = useState(0);
  const screenActive = useScreenActive();
  useEffect(() => {
    if (!screenActive) return;
    return registerBackInterceptor(() => {
      if (!tabsFocused.current) {
        setFocus(TABS_FOCUS_KEY);
        setContentResetKey((n) => n + 1);
        return true;
      }
      return false;
    });
  }, [screenActive]);

  // Focus passing over an unvisited tab must not mount it: a fresh tab build
  // materializes the catalog rows (expensive), and select-on-focus fires for
  // every tab crossed on the way to the target. A short dwell (or Enter)
  // commits the mount; already-visited tabs just toggle display instantly.
  const mountTimer = useRef<number | undefined>(undefined);
  useEffect(() => () => window.clearTimeout(mountTimer.current), []);
  const onSelectTab = useCallback(
    (id: string, source: "focus" | "enter") => {
      setActiveTab(id);
      settings.dashboardTab = tabs.findIndex((tab) => tab.id === id);
      window.clearTimeout(mountTimer.current);
      // Copy: mutating the Set in place would not re-render, so a newly
      // visited tab would never mount.
      const mount = () =>
        setVisited((prev) => (prev.has(id) ? prev : new Set(prev).add(id)));
      if (source === "enter") mount();
      else mountTimer.current = window.setTimeout(mount, 250);
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });

  useEffect(() => {
    focusSelf();
  }, [focusSelf]);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="screen dashboard-screen">
        <header className="dashboard-header">
          <span className="dashboard-playlist-name">{playlist.name}</span>
          <TabBar
            tabs={tabs}
            activeId={activeTab}
            onSelect={onSelectTab}
            focusKey={TABS_FOCUS_KEY}
            onFocusedChange={onTabsFocusedChange}
          />
        </header>

        {isM3U && visited.has("browse") && (
          <TabLayer active={activeTab === "browse"}>
            <M3UBrowseTab playlist={playlist} resetKey={contentResetKey} />
          </TabLayer>
        )}
        {!isM3U &&
          (["live", "vod", "series"] as const).map((kind) =>
            visited.has(kind) ? (
              // Stable key: three persistent instances, never remounted by
              // switching between them.
              <TabLayer key={kind} active={activeTab === kind}>
                <ContentTab
                  playlist={playlist}
                  kind={kind}
                  resetKey={contentResetKey}
                />
              </TabLayer>
            ) : null,
          )}
        {visited.has("settings") && (
          <TabLayer active={activeTab === "settings"}>
            <SettingsTab playlist={playlist} onPlaylistChanged={setPlaylist} />
          </TabLayer>
        )}
      </div>
    </FocusContext.Provider>
  );
}
