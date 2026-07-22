/**
 * Orders series episodes by season / episode number for previous-next episode
 * navigation.
 *
 * Port of the iOS `SeriesPlaybackOrdering` (Models/SeriesPlaybackOrdering.swift).
 * The Swift version queries GRDB; this port expresses the same ordering and
 * neighbor logic as pure functions over in-memory season/episode arrays.
 * (`navigationContext`, which resolves the series id via DB lookups, is left
 * to the data layer.)
 */

/** Minimal identity of an episode row: stable row id plus optional Xtream episode id. */
export interface EpisodeIdentity {
  id: string;
  episodeId?: string | null;
}

/** Minimal season shape needed for ordering. */
export interface OrderableSeason {
  id: string;
  seasonNumber: number;
}

/** Minimal episode shape needed for ordering. */
export interface OrderableEpisode extends EpisodeIdentity {
  seasonId: string;
  episodeNum: number;
}

export interface NavigationContext<T extends EpisodeIdentity = EpisodeIdentity> {
  previous: T | null;
  next: T | null;
}

export const emptyNavigationContext: NavigationContext<never> = {
  previous: null,
  next: null,
};

/**
 * Flattens seasons/episodes into playback order: seasons ascending by
 * `seasonNumber`, episodes within each season ascending by `episodeNum`.
 */
export function orderedEpisodes<E extends OrderableEpisode>(
  seasons: readonly OrderableSeason[],
  episodes: readonly E[],
): E[] {
  const sortedSeasons = seasons
    .slice()
    .sort((a, b) => a.seasonNumber - b.seasonNumber);
  const out: E[] = [];
  for (const season of sortedSeasons) {
    const eps = episodes
      .filter((ep) => ep.seasonId === season.id)
      .sort((a, b) => a.episodeNum - b.episodeNum);
    for (const ep of eps) out.push(ep);
  }
  return out;
}

/**
 * Finds the position of the currently playing stream in an ordered episode
 * list, matching by Xtream episode id first and falling back to the row id.
 * Returns `null` when absent (mirrors Swift's `Int?`).
 */
export function episodeIndex(
  playbackStreamId: string,
  episodes: readonly EpisodeIdentity[],
): number | null {
  for (let i = 0; i < episodes.length; i++) {
    const ep = episodes[i];
    if (ep === undefined) continue;
    const primaryId = ep.episodeId ?? ep.id;
    if (primaryId === playbackStreamId || ep.id === playbackStreamId) {
      return i;
    }
  }
  return null;
}

/**
 * Returns the previous/next episodes around the currently playing stream
 * within an already ordered episode list (see `orderedEpisodes`).
 */
export function neighbors<T extends OrderableEpisode>(
  playbackStreamId: string,
  episodes: readonly T[],
): NavigationContext<T> {
  const i = episodeIndex(playbackStreamId, episodes);
  if (i === null) return emptyNavigationContext;
  const previous = i > 0 ? (episodes[i - 1] ?? null) : null;
  const next = i < episodes.length - 1 ? (episodes[i + 1] ?? null) : null;
  return { previous, next };
}
