/**
 * Xtream Codes API models, ported from
 * apps/ios/another-iptv-player/Models/XtreamModels.swift.
 *
 * Every parser takes `unknown` (raw JSON.parse output). Per-element parsers
 * are failable: a malformed element yields `null` and list parsers drop it,
 * so one corrupt entry never sinks a whole list (the Swift side uses
 * `FailableDecodable` + `compactMap` for the same effect).
 */

import { asFloat, asInt, asString } from "./coerce";

// MARK: - Interfaces

export interface XtreamUserInfo {
  username?: string;
  password?: string;
  message?: string;
  auth?: number;
  status?: string;
  expDate?: string;
  isTrial?: string;
  activeCons?: string;
  createdAt?: string;
  maxConnections?: string;
}

export interface XtreamServerInfo {
  url?: string;
  port?: string;
  httpsPort?: string;
  serverProtocol?: string;
  rtmpPort?: string;
  timezone?: string;
  timeNow?: string;
}

export interface XtreamAuthResponse {
  userInfo?: XtreamUserInfo;
  serverInfo?: XtreamServerInfo;
}

export interface XtreamCategory {
  categoryId?: string;
  categoryName?: string;
  parentId?: number;
}

export interface XtreamLiveStream {
  streamId?: number;
  streamIcon?: string;
  epgChannelId?: string;
  name?: string;
  categoryId?: string;
  isAdult?: number;
}

export interface XtreamVodStream {
  streamId?: number;
  name?: string;
  streamIcon?: string;
  categoryId?: string;
  rating?: string;
  containerExtension?: string;
  isAdult?: number;
  added?: string;
}

/** One row of the `get_series` list. NOTE: the list uses camelCase `releaseDate`. */
export interface XtreamSeriesListItem {
  seriesId?: number;
  name?: string;
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
}

export interface XtreamSeriesDetails {
  name?: string;
  cover?: string;
  plot?: string;
  cast?: string;
  director?: string;
  genre?: string;
  releaseDate?: string;
  rating?: string;
  lastModified?: string;
  rating5Based?: number;
  backdropPath?: string[];
  youtubeTrailer?: string;
  episodeRunTime?: string;
}

export interface XtreamSeason {
  name?: string;
  seasonNumber?: number;
  cover?: string;
  overview?: string;
  airDate?: string;
  episodeCount?: number;
  voteAverage?: number;
}

export interface XtreamEpisodeInfo {
  plot?: string;
  duration?: string;
  rating?: string;
  cover?: string;
  movieImage?: string;
}

export interface XtreamEpisode {
  /** Stream id as a string, e.g. "1234". */
  id?: string;
  episodeNum?: number;
  title?: string;
  containerExtension?: string;
  info?: XtreamEpisodeInfo;
}

/** `get_series_info` response. The episodes dict is keyed by season STRING. */
export interface XtreamSeriesInfo {
  seasons?: XtreamSeason[];
  info?: XtreamSeriesDetails;
  episodes?: { [seasonKey: string]: XtreamEpisode[] };
}

/** `get_vod_info` -> `info` object. NOTE: uses lowercase `releasedate`. */
export interface XtreamVodInfoDetails {
  name?: string;
  movieImage?: string;
  coverBig?: string;
  plot?: string;
  cast?: string;
  director?: string;
  genre?: string;
  releaseDate?: string;
  rating?: string;
  backdropPath?: string[];
  youtubeTrailer?: string;
  duration?: string;
  durationSecs?: number;
  tmdbId?: string;
  kinopoiskUrl?: string;
}

export interface XtreamVodMovieData {
  streamId?: number;
  name?: string;
  added?: string;
  categoryId?: string;
  containerExtension?: string;
  customSid?: string;
  directSource?: string;
}

/** `get_vod_info` response. */
export interface XtreamVodInfo {
  info?: XtreamVodInfoDetails;
  movieData?: XtreamVodMovieData;
}

// MARK: - Errors

/** Thrown when a response body has a shape the models cannot decode at all. */
export class XtreamDecodeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "XtreamDecodeError";
  }
}

// MARK: - Internal helpers

function isRecord(value: unknown): value is { [key: string]: unknown } {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Strict `[String]` decode: the whole array is dropped if any element is not a string. */
function asStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }
  for (const element of value) {
    if (typeof element !== "string") {
      return undefined;
    }
  }
  return value as string[];
}

function compact<T>(items: Array<T | null>): T[] {
  const result: T[] = [];
  for (const item of items) {
    if (item !== null) {
      result.push(item);
    }
  }
  return result;
}

function requireArray(raw: unknown, what: string): unknown[] {
  if (!Array.isArray(raw)) {
    throw new XtreamDecodeError(`Expected a JSON array for ${what}`);
  }
  return raw;
}

// MARK: - Auth

export function parseXtreamUserInfo(raw: unknown): XtreamUserInfo | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    username: asString(raw["username"]),
    password: asString(raw["password"]),
    message: asString(raw["message"]),
    auth: asInt(raw["auth"]),
    status: asString(raw["status"]),
    expDate: asString(raw["exp_date"]),
    isTrial: asString(raw["is_trial"]),
    activeCons: asString(raw["active_cons"]),
    createdAt: asString(raw["created_at"]),
    maxConnections: asString(raw["max_connections"]),
  };
}

export function parseXtreamServerInfo(raw: unknown): XtreamServerInfo | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    url: asString(raw["url"]),
    port: asString(raw["port"]),
    httpsPort: asString(raw["https_port"]),
    serverProtocol: asString(raw["server_protocol"]),
    rtmpPort: asString(raw["rtmp_port"]),
    timezone: asString(raw["timezone"]),
    timeNow: asString(raw["time_now"]),
  };
}

/** Never throws: an unrecognizable body yields an empty response (Swift parity). */
export function parseXtreamAuthResponse(raw: unknown): XtreamAuthResponse {
  if (!isRecord(raw)) {
    return {};
  }
  return {
    userInfo: parseXtreamUserInfo(raw["user_info"]) ?? undefined,
    serverInfo: parseXtreamServerInfo(raw["server_info"]) ?? undefined,
  };
}

// MARK: - Category

export function parseXtreamCategory(raw: unknown): XtreamCategory | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    categoryId: asString(raw["category_id"]),
    categoryName: asString(raw["category_name"]),
    parentId: asInt(raw["parent_id"]),
  };
}

export function parseXtreamCategoryList(raw: unknown): XtreamCategory[] {
  return compact(requireArray(raw, "categories").map(parseXtreamCategory));
}

// MARK: - Streams

export function parseXtreamLiveStream(raw: unknown): XtreamLiveStream | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    streamId: asInt(raw["stream_id"]),
    streamIcon: asString(raw["stream_icon"]),
    epgChannelId: asString(raw["epg_channel_id"]),
    name: asString(raw["name"]),
    categoryId: asString(raw["category_id"]),
    isAdult: asInt(raw["is_adult"]),
  };
}

export function parseXtreamLiveStreamList(raw: unknown): XtreamLiveStream[] {
  return compact(requireArray(raw, "live streams").map(parseXtreamLiveStream));
}

export function parseXtreamVodStream(raw: unknown): XtreamVodStream | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    streamId: asInt(raw["stream_id"]),
    name: asString(raw["name"]),
    streamIcon: asString(raw["stream_icon"]),
    categoryId: asString(raw["category_id"]),
    rating: asString(raw["rating"]),
    containerExtension: asString(raw["container_extension"]),
    isAdult: asInt(raw["is_adult"]),
    added: asString(raw["added"]),
  };
}

export function parseXtreamVodStreamList(raw: unknown): XtreamVodStream[] {
  return compact(requireArray(raw, "VOD streams").map(parseXtreamVodStream));
}

export function parseXtreamSeriesListItem(
  raw: unknown,
): XtreamSeriesListItem | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    seriesId: asInt(raw["series_id"]),
    name: asString(raw["name"]),
    cover: asString(raw["cover"]),
    plot: asString(raw["plot"]),
    cast: asString(raw["cast"]),
    director: asString(raw["director"]),
    genre: asString(raw["genre"]),
    // The series LIST uses camelCase "releaseDate" (unlike VOD info's "releasedate").
    releaseDate: asString(raw["releaseDate"]),
    rating: asString(raw["rating"]),
    categoryId: asString(raw["category_id"]),
    youtubeTrailer: asString(raw["youtube_trailer"]),
    lastModified: asString(raw["last_modified"]),
  };
}

export function parseXtreamSeriesList(raw: unknown): XtreamSeriesListItem[] {
  return compact(requireArray(raw, "series list").map(parseXtreamSeriesListItem));
}

// MARK: - Series info

export function parseXtreamSeriesDetails(
  raw: unknown,
): XtreamSeriesDetails | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    name: asString(raw["name"]),
    cover: asString(raw["cover"]),
    plot: asString(raw["plot"]),
    cast: asString(raw["cast"]),
    director: asString(raw["director"]),
    genre: asString(raw["genre"]),
    releaseDate: asString(raw["releaseDate"]),
    rating: asString(raw["rating"]),
    lastModified: asString(raw["last_modified"]),
    rating5Based: asFloat(raw["rating_5based"]),
    backdropPath: asStringArray(raw["backdrop_path"]),
    youtubeTrailer: asString(raw["youtube_trailer"]),
    episodeRunTime: asString(raw["episode_run_time"]),
  };
}

export function parseXtreamSeason(raw: unknown): XtreamSeason | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    name: asString(raw["name"]),
    seasonNumber: asInt(raw["season_number"]),
    cover: asString(raw["cover"]),
    overview: asString(raw["overview"]),
    airDate: asString(raw["air_date"]),
    episodeCount: asInt(raw["episode_count"]),
    voteAverage: asFloat(raw["vote_average"]),
  };
}

export function parseXtreamEpisodeInfo(raw: unknown): XtreamEpisodeInfo | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    plot: asString(raw["plot"]),
    duration: asString(raw["duration"]),
    rating: asString(raw["rating"]),
    cover: asString(raw["cover"]),
    movieImage: asString(raw["movie_image"]),
  };
}

export function parseXtreamEpisode(raw: unknown): XtreamEpisode | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    id: asString(raw["id"]),
    episodeNum: asInt(raw["episode_num"]),
    title: asString(raw["title"]),
    containerExtension: asString(raw["container_extension"]),
    info: parseXtreamEpisodeInfo(raw["info"]) ?? undefined,
  };
}

export function parseXtreamSeriesInfo(raw: unknown): XtreamSeriesInfo {
  if (!isRecord(raw)) {
    throw new XtreamDecodeError("Expected a JSON object for series info");
  }
  const result: XtreamSeriesInfo = {};

  const seasonsRaw = raw["seasons"];
  if (Array.isArray(seasonsRaw)) {
    result.seasons = compact(seasonsRaw.map(parseXtreamSeason));
  }

  const details = parseXtreamSeriesDetails(raw["info"]);
  if (details !== null) {
    result.info = details;
  }

  const episodesRaw = raw["episodes"];
  if (isRecord(episodesRaw)) {
    const episodes: { [seasonKey: string]: XtreamEpisode[] } = {};
    for (const key of Object.keys(episodesRaw)) {
      const bucket = episodesRaw[key];
      if (!Array.isArray(bucket)) {
        continue;
      }
      episodes[key] = compact(bucket.map(parseXtreamEpisode));
    }
    result.episodes = episodes;
  }

  return result;
}

/**
 * Episodes regrouped by numeric season, since panels key the dictionary
 * inconsistently ("1", "01", " 1" all mean season 1). Non-numeric keys
 * ("specials") are dropped.
 */
export function episodesBySeasonNumber(
  info: XtreamSeriesInfo,
): Map<number, XtreamEpisode[]> {
  const grouped = new Map<number, XtreamEpisode[]>();
  const episodes = info.episodes;
  if (!episodes) {
    return grouped;
  }
  for (const key of Object.keys(episodes)) {
    const seasonNumber = asInt(key.trim());
    if (seasonNumber === undefined) {
      continue;
    }
    const existing = grouped.get(seasonNumber);
    if (existing) {
      existing.push(...episodes[key]);
    } else {
      grouped.set(seasonNumber, episodes[key].slice());
    }
  }
  return grouped;
}

export interface ResolvedSeason {
  number: number;
  metadata?: XtreamSeason;
}

/**
 * Every season worth persisting: the ones the panel declares, plus one for
 * each episode bucket the `seasons` array fails to cover. The two are
 * routinely out of sync (a panel may list season 1 while keying its episodes
 * under "2"), and an uncovered bucket would otherwise be dropped.
 */
export function resolvedSeasons(info: XtreamSeriesInfo): ResolvedSeason[] {
  const order: number[] = [];
  const metadata = new Map<number, XtreamSeason>();

  for (const season of info.seasons ?? []) {
    const number = season.seasonNumber;
    if (number === undefined) {
      continue;
    }
    if (!metadata.has(number)) {
      order.push(number);
    }
    metadata.set(number, season);
  }

  const bucketNumbers = Array.from(episodesBySeasonNumber(info).keys()).sort(
    (a, b) => a - b,
  );
  for (const number of bucketNumbers) {
    if (!metadata.has(number)) {
      order.push(number);
    }
  }

  return order.map((number) => ({ number, metadata: metadata.get(number) }));
}

// MARK: - VOD info

export function parseXtreamVodInfoDetails(
  raw: unknown,
): XtreamVodInfoDetails | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    name: asString(raw["name"]),
    movieImage: asString(raw["movie_image"]),
    coverBig: asString(raw["cover_big"]),
    plot: asString(raw["plot"]),
    cast: asString(raw["cast"]),
    director: asString(raw["director"]),
    genre: asString(raw["genre"]),
    // VOD info uses lowercase "releasedate" (unlike the series list's "releaseDate").
    releaseDate: asString(raw["releasedate"]),
    rating: asString(raw["rating"]),
    backdropPath: asStringArray(raw["backdrop_path"]),
    youtubeTrailer: asString(raw["youtube_trailer"]),
    duration: asString(raw["duration"]),
    durationSecs: asInt(raw["duration_secs"]),
    tmdbId: asString(raw["tmdb_id"]),
    kinopoiskUrl: asString(raw["kinopoisk_url"]),
  };
}

export function parseXtreamVodMovieData(
  raw: unknown,
): XtreamVodMovieData | null {
  if (!isRecord(raw)) {
    return null;
  }
  return {
    streamId: asInt(raw["stream_id"]),
    name: asString(raw["name"]),
    added: asString(raw["added"]),
    categoryId: asString(raw["category_id"]),
    containerExtension: asString(raw["container_extension"]),
    customSid: asString(raw["custom_sid"]),
    directSource: asString(raw["direct_source"]),
  };
}

export function parseXtreamVodInfo(raw: unknown): XtreamVodInfo {
  if (!isRecord(raw)) {
    throw new XtreamDecodeError("Expected a JSON object for VOD info");
  }
  const result: XtreamVodInfo = {};
  const details = parseXtreamVodInfoDetails(raw["info"]);
  if (details !== null) {
    result.info = details;
  }
  const movieData = parseXtreamVodMovieData(raw["movie_data"]);
  if (movieData !== null) {
    result.movieData = movieData;
  }
  return result;
}
