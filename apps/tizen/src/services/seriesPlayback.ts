import { AppDB } from "../data/db";
import {
  PlaylistRecord,
  SeriesInfoEpisode,
  SeriesInfoRecord,
} from "../data/records";
import { getSeriesInfo, saveSeriesInfo } from "../data/seriesInfoRepo";
import { XtreamClient } from "../api/xtreamClient";
import { PlaybackUrlBuilder } from "../api/playbackUrlBuilder";
import {
  episodesBySeasonNumber,
  resolvedSeasons,
  XtreamSeriesInfo,
} from "../models/xtream";
import { PlayableItem } from "../models/playable";

// Shared by the series detail screen and the continue-watching shelf (which
// jumps straight into playback, iOS HistorySeriesPlayerShell equivalent).

export function seriesInfoToRecord(
  playlistId: string,
  seriesId: number,
  remote: XtreamSeriesInfo,
): SeriesInfoRecord {
  const seasonsResolved = resolvedSeasons(remote);
  const buckets = episodesBySeasonNumber(remote);

  const seasons = seasonsResolved.map((season) => ({
    seasonNumber: season.number,
    name: season.metadata?.name,
    cover: season.metadata?.cover,
    overview: season.metadata?.overview,
    airDate: season.metadata?.airDate,
    episodeCount: season.metadata?.episodeCount,
  }));

  const flat: SeriesInfoEpisode[] = [];
  for (const season of seasonsResolved) {
    const bucket = buckets.get(season.number) ?? [];
    bucket.forEach((episode, position) => {
      if (episode.id === undefined) return;
      flat.push({
        id: episode.id,
        seasonNumber: season.number,
        episodeNum: episode.episodeNum ?? position + 1,
        title: episode.title,
        containerExtension: episode.containerExtension,
        plot: episode.info?.plot,
        cover: episode.info?.cover,
      });
    });
  }

  return {
    id: `${playlistId}_${seriesId}`,
    playlistId,
    seriesId,
    seasons,
    episodes: flat,
    fetchedAt: Date.now(),
  };
}

/**
 * Cached seasons/episodes, fetching (and persisting) from the panel when the
 * cache is empty — e.g. history entries for series whose detail screen was
 * never opened on this device. Returns null when the fetch fails too.
 */
export async function ensureSeriesInfo(
  db: AppDB,
  playlist: PlaylistRecord,
  seriesId: number,
): Promise<SeriesInfoRecord | null> {
  const cached = await getSeriesInfo(db, playlist.id, seriesId);
  if (cached) return cached;
  try {
    const client = new XtreamClient(playlist);
    const remote = await client.getSeriesInfo(seriesId);
    const record = seriesInfoToRecord(playlist.id, seriesId, remote);
    await saveSeriesInfo(db, record);
    return record;
  } catch {
    return null;
  }
}

/** Full episode queue in playback order (player resolves per-episode resume). */
export function buildSeriesQueue(
  playlist: PlaylistRecord,
  seriesId: number,
  seriesName: string,
  seriesCover: string | undefined,
  info: SeriesInfoRecord,
): PlayableItem[] {
  const urls = new PlaybackUrlBuilder(playlist);
  return info.episodes.map((entry) => ({
    url: urls.seriesUrl(entry.id, entry.containerExtension),
    title: seriesName,
    secondaryTitle: `S${entry.seasonNumber}E${entry.episodeNum}${entry.title ? ` · ${entry.title}` : ""}`,
    imageURL: entry.cover ?? seriesCover,
    isLive: false,
    historyType: "series" as const,
    historyStreamId: entry.id,
    seriesId,
    containerExtension: entry.containerExtension,
  }));
}
