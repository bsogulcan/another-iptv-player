import { useCallback, useEffect, useMemo, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { getDb } from "../../data/db";
import {
  CatalogKind,
  LiveStreamRecord,
  M3UChannelRecord,
  PlaylistRecord,
  SeriesRecord,
  VodStreamRecord,
} from "../../data/records";
import { getCatalogSection, getM3UCatalog } from "../../data/catalogCache";
import { PlaybackUrlBuilder } from "../../api/playbackUrlBuilder";
import { PlayableItem } from "../../models/playable";
import { useNavigation } from "../../navigation/NavigationStack";
import { useScreenActive } from "../../navigation/ScreenLayer";
import { t } from "../../i18n";
import { CardShape, FocusableCard } from "../components/FocusableCard";
import { centerInContainer } from "../utils/scroll";

const PAGE_SIZE = 60;
// Fixed 1920 canvas: 5 × 320px cards per grid row (see app.css row math).
const GRID_COLS = 5;
// Rows above/below the focused one whose cards stay focusable. Cards outside
// go dormant: identical static markup (so the layout and scroll offsets never
// shift) but no useFocusable registration, no IntersectionObserver entry and
// no <img>. Without this, deep scrolls accumulated thousands of focusables
// and Norigin's per-keypress candidate measurement grew without bound.
const ACTIVE_ROWS = 30;

/** Layout twin of FocusableCard for cards far outside the focus window. */
function DormantCard({ title, shape }: { title: string; shape: CardShape }) {
  return (
    <div className={`card card-${shape}`}>
      <div className="card-image-wrap">
        <div className={`poster-image image-${shape}`}>
          <div className="poster-fallback">
            {title.slice(0, 2).toUpperCase()}
          </div>
        </div>
      </div>
      <div className="card-title">{title}</div>
    </div>
  );
}

interface GridItem {
  id: string;
  title: string;
  imageURL?: string;
  onSelect: () => void;
}

export function CategoryGridScreen({
  playlist,
  kind,
  categoryId,
  title,
}: {
  playlist: PlaylistRecord;
  kind: CatalogKind | "m3uGroup";
  categoryId: string;
  title: string;
}) {
  const { push } = useNavigation();
  const [items, setItems] = useState<GridItem[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [visibleCount, setVisibleCount] = useState(PAGE_SIZE);

  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });

  const urls = useMemo(() => new PlaybackUrlBuilder(playlist), [playlist]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      let loaded: GridItem[] = [];
      if (kind === "live") {
        const section = await getCatalogSection(db, playlist, "live");
        const streams = (section.byCategory.get(categoryId) ??
          []) as LiveStreamRecord[];
        const queue: PlayableItem[] = streams.map((stream) => ({
          url: urls.liveUrl(stream.streamId),
          title: stream.name,
          imageURL: stream.icon,
          isLive: true,
          historyType: "live" as const,
          historyStreamId: String(stream.streamId),
        }));
        loaded = streams.map((stream: LiveStreamRecord, index) => ({
          id: String(stream.streamId),
          title: stream.name,
          imageURL: stream.icon,
          onSelect: () =>
            push({ name: "player", playlist, items: queue, startIndex: index }),
        }));
      } else if (kind === "vod") {
        const section = await getCatalogSection(db, playlist, "vod");
        const streams = (section.byCategory.get(categoryId) ??
          []) as VodStreamRecord[];
        loaded = streams.map((stream: VodStreamRecord) => ({
          id: String(stream.streamId),
          title: stream.name,
          imageURL: stream.icon,
          onSelect: () =>
            push({ name: "movieDetail", playlist, vodId: stream.streamId }),
        }));
      } else if (kind === "series") {
        const section = await getCatalogSection(db, playlist, "series");
        const list = (section.byCategory.get(categoryId) ??
          []) as SeriesRecord[];
        loaded = list.map((series: SeriesRecord) => ({
          id: String(series.seriesId),
          title: series.name,
          imageURL: series.cover,
          onSelect: () =>
            push({ name: "seriesDetail", playlist, seriesId: series.seriesId }),
        }));
      } else {
        const channels = await getM3UCatalog(db, playlist);
        const groupChannels = channels.filter(
          (channel: M3UChannelRecord) =>
            (channel.groupTitle?.trim() || t("m3u.ungrouped_label")) ===
            categoryId,
        );
        const queue: PlayableItem[] = groupChannels.map((channel) => ({
          url: channel.url,
          title: channel.name,
          imageURL: channel.tvgLogo,
          isLive: true,
          historyType: "live" as const,
          historyStreamId: channel.id,
          userAgent: channel.userAgent,
        }));
        loaded = groupChannels.map((channel, index) => ({
          id: channel.id,
          title: channel.name,
          imageURL: channel.tvgLogo,
          onSelect: () =>
            push({ name: "player", playlist, items: queue, startIndex: index }),
        }));
      }
      if (!cancelled) {
        setItems(loaded);
        setLoaded(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [playlist, kind, categoryId, urls, push]);

  const screenActive = useScreenActive();
  useEffect(() => {
    // Never while covered: focusSelf would steal focus from the top screen.
    if (screenActive && items.length > 0) focusSelf();
  }, [items.length, focusSelf, screenActive]);

  const shape = kind === "vod" || kind === "series" ? "poster" : "landscape";
  const visible = items.slice(0, visibleCount);
  const [focusedRow, setFocusedRow] = useState(0);

  // Incremental reveal (extend near the loaded end) + focus-window tracking.
  // Stable callback: FocusableCard is memoized, an inline handler would
  // re-render every mounted card on each grid re-render.
  const onCardFocused = useCallback((el: HTMLElement) => {
    centerInContainer(el, ".grid-scroller");
    const wrap = el.parentElement;
    if (!wrap) return;
    const index = Array.prototype.indexOf.call(wrap.children, el);
    if (index < 0) return;
    setVisibleCount((current) =>
      index >= current - 14 ? current + PAGE_SIZE : current,
    );
    const row = Math.floor(index / GRID_COLS);
    // Bail on same row: the window only re-renders on actual row crossings.
    setFocusedRow((prev) => (prev === row ? prev : row));
  }, []);

  const activeFrom = Math.max(0, (focusedRow - ACTIVE_ROWS) * GRID_COLS);
  const activeTo = (focusedRow + ACTIVE_ROWS + 1) * GRID_COLS;

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="screen grid-screen">
        <h1 className="screen-title">
          {title}
          <span className="grid-count"> · {items.length}</span>
        </h1>
        {loaded && items.length === 0 && (
          <p className="screen-hint">
            {kind === "vod"
              ? t("vod.empty.no_movie")
              : kind === "series"
                ? t("series.empty.no_in_category")
                : t("live.empty.no_channel_in_category")}
          </p>
        )}
        <div className="grid-scroller">
          <div className="grid-wrap">
            {visible.map((item, index) =>
              index >= activeFrom && index < activeTo ? (
                <FocusableCard
                  key={item.id}
                  title={item.title}
                  imageURL={item.imageURL}
                  shape={shape}
                  onSelect={item.onSelect}
                  onFocusedElement={onCardFocused}
                />
              ) : (
                <DormantCard key={item.id} title={item.title} shape={shape} />
              ),
            )}
          </div>
        </div>
      </div>
    </FocusContext.Provider>
  );
}
