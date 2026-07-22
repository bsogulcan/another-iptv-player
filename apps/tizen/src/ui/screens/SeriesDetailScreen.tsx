import { memo, useCallback, useEffect, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { getDb } from "../../data/db";
import {
  PlaylistRecord,
  SeriesInfoEpisode,
  SeriesInfoRecord,
  SeriesRecord,
} from "../../data/records";
import { getSeriesById } from "../../data/catalogRepo";
import { isFavorite, toggleFavorite } from "../../data/favoritesRepo";
import { getHistoryEntry } from "../../data/watchHistoryRepo";
import {
  buildSeriesQueue,
  ensureSeriesInfo,
} from "../../services/seriesPlayback";
import { useNavigation } from "../../navigation/NavigationStack";
import { useScreenActive } from "../../navigation/ScreenLayer";
import { KEY, normalizeKeyCode } from "../../navigation/keys";
import { t } from "../../i18n";
import { useCachedImage } from "../../services/imageCache";
import { PosterImage } from "../components/PosterImage";
import { Button } from "../components/TextField";
import { centerInContainer } from "../utils/scroll";

/** "2019-05-14" → "2019"; anything that doesn't start with a year is dropped. */
function releaseYear(date: string | undefined): string | undefined {
  const year = date?.slice(0, 4);
  return year && /^\d{4}$/.test(year) ? year : undefined;
}

// Memoized: the screen re-renders on every focus move (trackChildren), and
// re-rendering every row per keypress is what makes episode nav feel janky.
const EpisodeRow = memo(function EpisodeRow({
  episode,
  fallbackCover,
  progress,
  onPlay,
}: {
  episode: SeriesInfoEpisode;
  fallbackCover?: string;
  progress?: number;
  onPlay: (episode: SeriesInfoEpisode) => void;
}) {
  const { ref, focused } = useFocusable({
    onEnterPress: () => onPlay(episode),
  });
  useEffect(() => {
    if (focused && ref.current) {
      centerInContainer(ref.current, ".episode-list");
    }
  }, [focused, ref]);
  const heading = episode.title
    ? `${episode.episodeNum}. ${episode.title}`
    : t("series.episode_format", episode.episodeNum);
  return (
    <div ref={ref} className={`episode-row rich${focused ? " focused" : ""}`}>
      <div className="episode-thumb">
        <PosterImage src={episode.cover ?? fallbackCover} alt={heading} />
        {progress !== undefined && (
          <span className="episode-thumb-progress">
            <span
              className="episode-thumb-progress-fill"
              style={{ width: `${Math.min(progress * 100, 100)}%` }}
            />
          </span>
        )}
      </div>
      <div className="episode-body">
        <p className="episode-heading">{heading}</p>
        {episode.plot && <p className="episode-plot clamp-2">{episode.plot}</p>}
      </div>
      {episode.durationSecs !== undefined && episode.durationSecs > 0 && (
        <span className="episode-duration">
          {t("tv.minutes_format", Math.round(episode.durationSecs / 60))}
        </span>
      )}
    </div>
  );
});

function SeasonButton({
  label,
  active,
  onSelect,
}: {
  label: string;
  active: boolean;
  onSelect: () => void;
}) {
  const { ref, focused } = useFocusable({
    onEnterPress: onSelect,
    onFocus: onSelect,
  });
  const classes = ["season-button"];
  if (active) classes.push("active");
  if (focused) classes.push("focused");
  return (
    <div ref={ref} className={classes.join(" ")}>
      {label}
    </div>
  );
}

export function SeriesDetailScreen({
  playlist,
  seriesId,
}: {
  playlist: PlaylistRecord;
  seriesId: number;
}) {
  const { push } = useNavigation();
  const [series, setSeries] = useState<SeriesRecord | null>(null);
  const [info, setInfo] = useState<SeriesInfoRecord | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [selectedSeason, setSelectedSeason] = useState<number | null>(null);
  const [favorite, setFavorite] = useState(false);
  const [progressById, setProgressById] = useState<Map<string, number>>(
    new Map(),
  );

  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });
  const screenActive = useScreenActive();

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      const record = await getSeriesById(db, playlist.id, seriesId);
      if (!cancelled && record) setSeries(record);

      const fav = await isFavorite(db, playlist.id, "series", String(seriesId));
      if (!cancelled) setFavorite(fav);

      // Lazy enrichment with a fetch-once cache (iOS seasonsLoaded pattern).
      const cached = await ensureSeriesInfo(db, playlist, seriesId);
      if (!cached) {
        if (!cancelled) setLoadError(t("common.unknown_error"));
        return;
      }
      if (cancelled) return;
      setInfo(cached);
      if (cached.seasons.length > 0) {
        setSelectedSeason(cached.seasons[0].seasonNumber);
      }

      // Resume markers for episode rows.
      const progress = new Map<string, number>();
      for (const episode of cached.episodes) {
        const entry = await getHistoryEntry(db, playlist.id, "series", episode.id);
        if (entry && entry.durationMs > 0) {
          progress.set(episode.id, entry.lastTimeMs / entry.durationMs);
        }
      }
      if (!cancelled) setProgressById(progress);
    })();
    return () => {
      cancelled = true;
    };
  }, [playlist, seriesId]);

  useEffect(() => {
    // Re-run when the lazily-fetched info lands: the first pass has no
    // focusable children yet (season bar/episodes render from `info`).
    // Never while covered: focusSelf would steal focus from the top screen.
    if (screenActive && series) focusSelf();
  }, [series, info, focusSelf, screenActive]);

  const toggleFav = useCallback(() => {
    void (async () => {
      const db = await getDb();
      setFavorite(
        await toggleFavorite(db, playlist.id, "series", String(seriesId)),
      );
    })();
  }, [playlist.id, seriesId]);

  // Stays mounted under the player layer; re-read the state on return there
  // (the episode player can favorite/unfavorite this series meanwhile).
  useEffect(() => {
    if (!screenActive) return;
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      const fav = await isFavorite(db, playlist.id, "series", String(seriesId));
      if (!cancelled) setFavorite(fav);
    })();
    return () => {
      cancelled = true;
    };
  }, [screenActive, playlist.id, seriesId]);

  // Red key: favorite toggle for the series.
  useEffect(() => {
    if (!screenActive) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (normalizeKeyCode(event) !== KEY.Red) return;
      toggleFav();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [toggleFav, screenActive]);

  const backdrop = useCachedImage(series?.cover);

  const playFrom = useCallback(
    (episode: SeriesInfoEpisode) => {
      if (!info || !series) return;
      // Full queue in playback order; the player looks up per-episode resume.
      const queue = buildSeriesQueue(
        playlist,
        seriesId,
        series.name,
        series.cover,
        info,
      );
      const startIndex = info.episodes.findIndex(
        (entry) => entry.id === episode.id,
      );
      push({
        name: "player",
        playlist,
        items: queue,
        startIndex: Math.max(startIndex, 0),
      });
    },
    [info, series, seriesId, push, playlist],
  );

  if (!series) {
    // ref stays attached even while loading: a registered focusable without
    // a DOM node breaks Norigin's layout math.
    return (
      <p ref={ref} className="screen-hint">
        {t("common.loading")}
      </p>
    );
  }

  const seasonEpisodes =
    info?.episodes.filter((e) => e.seasonNumber === selectedSeason) ?? [];

  const metaChips = [
    releaseYear(series.releaseDate),
    series.genre,
    series.rating ? `★ ${series.rating}` : undefined,
    info && info.seasons.length > 0
      ? t("tv.seasons_format", info.seasons.length)
      : undefined,
  ].filter((chip): chip is string => !!chip);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="screen detail-screen series-detail">
        {backdrop && (
          <div className="detail-backdrop">
            <img src={backdrop} alt="" />
            <div className="detail-backdrop-scrim" />
          </div>
        )}
        <div className="detail-body">
          <h1 className="detail-title">{series.name}</h1>
          <p className="detail-meta-line">
            {metaChips.length > 0 && <span>{metaChips.join("\u2002·\u2002")}</span>}
            <span className={`detail-fav${favorite ? " active" : ""}`}>♥</span>
          </p>
          {series.plot && <p className="detail-plot clamp-2">{series.plot}</p>}
          <div className="detail-actions">
            <Button
              label={`♥ ${t(favorite ? "favorites.remove" : "favorites.add")}`}
              onSelect={toggleFav}
            />
          </div>
          <p className="detail-key-hint">{t("tv.favorite_hint")}</p>
        </div>

        {!info && !loadError && (
          <p className="screen-hint">{t("series.loading_seasons")}</p>
        )}
        {loadError && (
          <p className="form-error">
            {t("settings.playlist.info_error", loadError)}
          </p>
        )}

        {info && info.seasons.length === 0 && (
          <p className="screen-hint">{t("series.no_seasons_info")}</p>
        )}

        {info && info.seasons.length > 0 && (
          <>
            <div className="season-bar">
              {info.seasons.map((season) => (
                <SeasonButton
                  key={season.seasonNumber}
                  label={
                    season.name ??
                    t("series.season_format", season.seasonNumber)
                  }
                  active={selectedSeason === season.seasonNumber}
                  onSelect={() => setSelectedSeason(season.seasonNumber)}
                />
              ))}
            </div>
            <div className="episode-list">
              {seasonEpisodes.length === 0 && (
                <p className="screen-hint">
                  {t("series.no_episodes_in_season")}
                </p>
              )}
              {seasonEpisodes.map((episode) => (
                <EpisodeRow
                  key={episode.id}
                  episode={episode}
                  fallbackCover={series.cover}
                  progress={progressById.get(episode.id)}
                  onPlay={playFrom}
                />
              ))}
            </div>
          </>
        )}
      </div>
    </FocusContext.Provider>
  );
}
