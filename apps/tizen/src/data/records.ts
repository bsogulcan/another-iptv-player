// Persistence record shapes (IndexedDB). Deliberately separate from the wire
// models in models/xtream.ts, mirroring the iOS DBModels/XtreamModels split.

export type PlaylistKind = "xtream" | "m3u";
export type CatalogKind = "live" | "vod" | "series";
export type FavoriteKind = CatalogKind | "m3u";
export type HistoryKind = CatalogKind;

export interface PlaylistRecord {
  id: string;
  name: string;
  type: PlaylistKind;
  serverURL: string;
  username: string;
  password: string;
  filterAdultContent: boolean;
  m3uEpgURL?: string;
  createdAt: number;
}

export interface CategoryRecord {
  id: string; // `${playlistId}_${kind}_${categoryId}`
  playlistId: string;
  kind: CatalogKind;
  categoryId: string;
  name: string;
  sortIndex: number;
}

export interface LiveStreamRecord {
  id: string; // `${playlistId}_${streamId}`
  playlistId: string;
  streamId: number;
  name: string;
  icon?: string;
  categoryId?: string;
  epgChannelId?: string;
  isAdult: boolean;
  sortIndex: number;
}

export interface VodStreamRecord {
  id: string; // `${playlistId}_${streamId}`
  playlistId: string;
  streamId: number;
  name: string;
  icon?: string;
  categoryId?: string;
  rating?: string;
  containerExtension?: string;
  added?: string; // unix-timestamp string, used for "recently added"
  isAdult: boolean;
  sortIndex: number;
}

export interface SeriesRecord {
  id: string; // `${playlistId}_${seriesId}`
  playlistId: string;
  seriesId: number;
  name: string;
  cover?: string;
  plot?: string;
  cast?: string;
  director?: string;
  genre?: string;
  releaseDate?: string;
  rating?: string;
  categoryId?: string;
  youtubeTrailer?: string;
  lastModified?: string;
  seasonsLoaded: boolean;
  sortIndex: number;
}

export interface SeriesInfoSeason {
  seasonNumber: number;
  name?: string;
  cover?: string;
  overview?: string;
  airDate?: string;
  episodeCount?: number;
}

export interface SeriesInfoEpisode {
  id: string; // Xtream episode id, used to build the playback URL
  seasonNumber: number;
  episodeNum: number;
  title?: string;
  containerExtension?: string;
  plot?: string;
  durationSecs?: number;
  cover?: string;
}

/**
 * Lazily-fetched get_series_info result, stored as one document per series so
 * seasons and episodes are read atomically (replaces iOS season/episode tables).
 */
export interface SeriesInfoRecord {
  id: string; // `${playlistId}_${seriesId}`
  playlistId: string;
  seriesId: number;
  seasons: SeriesInfoSeason[];
  episodes: SeriesInfoEpisode[];
  fetchedAt: number;
}

export interface VodInfoRecord {
  id: string; // `${playlistId}_${vodId}`
  playlistId: string;
  vodId: number;
  plot?: string;
  cast?: string;
  director?: string;
  genre?: string;
  releaseDate?: string;
  rating?: string;
  backdropPath?: string[];
  youtubeTrailer?: string;
  /** Raw runtime string from the panel ("01:29:00"); iOS displays this as-is. */
  duration?: string;
  durationSecs?: number;
  tmdbId?: string;
  containerExtension?: string;
  fetchedAt: number;
}

export interface M3UChannelRecord {
  id: string; // sha256(`${playlistId}:${url}`) — stable across re-imports
  playlistId: string;
  name: string;
  url: string;
  tvgId?: string;
  tvgName?: string;
  tvgLogo?: string;
  tvgCountry?: string;
  groupTitle?: string;
  userAgent?: string;
  sortIndex: number;
}

export interface FavoriteRecord {
  id: string; // `${playlistId}_${kind}_${itemId}`
  playlistId: string;
  kind: FavoriteKind;
  itemId: string; // Xtream streamId/seriesId as string, or M3U channel id
  addedAt: number;
}

export interface WatchHistoryRecord {
  id: string; // `${playlistId}_${type}_${streamId}` — identical to iOS
  playlistId: string;
  type: HistoryKind;
  streamId: string;
  lastTimeMs: number;
  durationMs: number;
  lastWatchedAt: number;
  title: string;
  secondaryTitle?: string;
  imageURL?: string;
  seriesId?: number;
  containerExtension?: string;
}
