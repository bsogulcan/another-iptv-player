import { useCallback, useEffect, useMemo, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { getDb } from "../../data/db";
import {
  PlaylistRecord,
  VodInfoRecord,
  VodStreamRecord,
} from "../../data/records";
import { getVodById } from "../../data/catalogRepo";
import { getVodInfo, saveVodInfo } from "../../data/seriesInfoRepo";
import { isFavorite, toggleFavorite } from "../../data/favoritesRepo";
import { getResumePositionMs } from "../../data/watchHistoryRepo";
import { XtreamClient } from "../../api/xtreamClient";
import { PlaybackUrlBuilder } from "../../api/playbackUrlBuilder";
import { PlayableItem } from "../../models/playable";
import { useNavigation } from "../../navigation/NavigationStack";
import { useScreenActive } from "../../navigation/ScreenLayer";
import { KEY, normalizeKeyCode } from "../../navigation/keys";
import { t } from "../../i18n";
import { useCachedImage } from "../../services/imageCache";
import { Button } from "../components/TextField";

/** "2019-05-14" → "2019"; anything that doesn't start with a year is dropped. */
function releaseYear(date: string | undefined): string | undefined {
  const year = date?.slice(0, 4);
  return year && /^\d{4}$/.test(year) ? year : undefined;
}

export function MovieDetailScreen({
  playlist,
  vodId,
}: {
  playlist: PlaylistRecord;
  vodId: number;
}) {
  const { push } = useNavigation();
  const [movie, setMovie] = useState<VodStreamRecord | null>(null);
  const [details, setDetails] = useState<VodInfoRecord | null>(null);
  // Backdrop waits for the get_vod_info attempt to settle: showing the
  // blurred poster first and swapping to the real art looks inconsistent.
  const [detailsSettled, setDetailsSettled] = useState(false);
  const [resumeMs, setResumeMs] = useState<number | undefined>(undefined);
  const [favorite, setFavorite] = useState(false);

  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      const record = await getVodById(db, playlist.id, vodId);
      if (!cancelled && record) setMovie(record);

      setResumeMs(
        await getResumePositionMs(db, playlist.id, "vod", String(vodId)),
      );
      const fav = await isFavorite(db, playlist.id, "vod", String(vodId));
      if (!cancelled) setFavorite(fav);

      // Lazy get_vod_info enrichment (iOS metadataLoaded pattern); the base
      // catalog fields keep the screen usable when the fetch fails.
      // `duration === undefined` also marks records cached before the field
      // existed — refresh those once.
      let cached = await getVodInfo(db, playlist.id, vodId);
      if (cached && cached.duration === undefined) cached = undefined;
      if (!cached) {
        try {
          const client = new XtreamClient(playlist);
          const remote = await client.getVodInfo(vodId);
          cached = {
            id: `${playlist.id}_${vodId}`,
            playlistId: playlist.id,
            vodId,
            plot: remote.info?.plot,
            cast: remote.info?.cast,
            director: remote.info?.director,
            genre: remote.info?.genre,
            releaseDate: remote.info?.releaseDate,
            rating: remote.info?.rating,
            backdropPath: remote.info?.backdropPath,
            youtubeTrailer: remote.info?.youtubeTrailer,
            duration: remote.info?.duration ?? "",
            durationSecs: remote.info?.durationSecs,
            tmdbId: remote.info?.tmdbId,
            containerExtension: remote.movieData?.containerExtension,
            fetchedAt: Date.now(),
          };
          await saveVodInfo(db, cached);
        } catch {
          if (!cancelled) setDetailsSettled(true);
          return; // catalog fields already shown
        }
      }
      if (!cancelled) {
        if (cached) setDetails(cached);
        setDetailsSettled(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [playlist, vodId]);

  useEffect(() => {
    if (movie) focusSelf();
  }, [movie, focusSelf]);

  const toggleFav = useCallback(() => {
    void (async () => {
      const db = await getDb();
      setFavorite(await toggleFavorite(db, playlist.id, "vod", String(vodId)));
    })();
  }, [playlist.id, vodId]);

  const screenActive = useScreenActive();
  useEffect(() => {
    if (!screenActive) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (normalizeKeyCode(event) !== KEY.Red) return;
      toggleFav();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [toggleFav, screenActive]);

  // Stays mounted under the player layer; re-read the state on return there
  // (the player's heart button can toggle this movie meanwhile).
  useEffect(() => {
    if (!screenActive) return;
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      const fav = await isFavorite(db, playlist.id, "vod", String(vodId));
      if (!cancelled) setFavorite(fav);
    })();
    return () => {
      cancelled = true;
    };
  }, [screenActive, playlist.id, vodId]);

  const urls = useMemo(() => new PlaybackUrlBuilder(playlist), [playlist]);

  // Real backdrop art renders sharp; a portrait poster only works as an
  // ambient color field, so the fallback stays blurred — and only once the
  // details attempt settled (no poster→backdrop photo swap).
  const heroArt = details?.backdropPath?.[0];
  const backdrop = useCachedImage(
    heroArt ?? (detailsSettled ? movie?.icon : undefined),
  );

  const play = useCallback(
    (fromMs?: number) => {
      if (!movie) return;
      const item: PlayableItem = {
        url: urls.movieUrl(
          movie.streamId,
          details?.containerExtension ?? movie.containerExtension,
        ),
        title: movie.name,
        imageURL: movie.icon,
        isLive: false,
        historyType: "vod",
        historyStreamId: String(movie.streamId),
        containerExtension:
          details?.containerExtension ?? movie.containerExtension,
        resumeTimeMs: fromMs ?? 0,
      };
      push({ name: "player", playlist, items: [item], startIndex: 0 });
    },
    [movie, details, urls, push, playlist],
  );

  if (!movie) {
    // ref stays attached even while loading: a registered focusable without
    // a DOM node breaks Norigin's layout math.
    return (
      <p ref={ref} className="screen-hint">
        {t("common.loading")}
      </p>
    );
  }

  const rating = details?.rating ?? movie.rating;
  // iOS parity: the panel's raw runtime string ("01:29:00") wins — many
  // panels put junk in duration_secs; minutes math is only the fallback.
  const durationLabel = details?.duration?.trim()
    ? details.duration.trim()
    : details?.durationSecs !== undefined && details.durationSecs > 0
      ? t("tv.minutes_format", Math.round(details.durationSecs / 60))
      : undefined;
  const metaChips = [
    releaseYear(details?.releaseDate),
    details?.genre,
    durationLabel,
    rating ? `★ ${rating}` : undefined,
  ].filter((chip): chip is string => !!chip);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="screen detail-screen movie-detail">
        {backdrop && (
          <div className={`detail-backdrop${heroArt ? " sharp" : ""}`}>
            <img src={backdrop} alt="" />
            <div className="detail-backdrop-scrim" />
          </div>
        )}
        <div className="detail-body">
          <h1 className="detail-title">{movie.name}</h1>
          <p className="detail-meta-line">
            {metaChips.length > 0 && <span>{metaChips.join("\u2002·\u2002")}</span>}
            <span className={`detail-fav${favorite ? " active" : ""}`}>♥</span>
          </p>
          {details?.plot && (
            <p className="detail-plot clamp-3">{details.plot}</p>
          )}
          {details?.director && (
            <p className="detail-credit clamp-1">
              {t("movie.director")}: {details.director}
            </p>
          )}
          {details?.cast && (
            <p className="detail-credit clamp-1">
              {t("movie.cast")}: {details.cast}
            </p>
          )}
          <div className="detail-actions">
            {resumeMs !== undefined && (
              <Button
                primary
                label={`${t("detail.resume")} (${Math.floor(resumeMs / 60000)}:${String(Math.floor((resumeMs % 60000) / 1000)).padStart(2, "0")})`}
                onSelect={() => play(resumeMs)}
              />
            )}
            <Button
              primary={resumeMs === undefined}
              label={
                resumeMs !== undefined ? t("detail.restart") : t("movie.play")
              }
              onSelect={() => play(0)}
            />
            <Button
              label={`♥ ${t(favorite ? "favorites.remove" : "favorites.add")}`}
              onSelect={toggleFav}
            />
          </div>
          <p className="detail-key-hint">{t("tv.favorite_hint")}</p>
        </div>
      </div>
    </FocusContext.Provider>
  );
}
