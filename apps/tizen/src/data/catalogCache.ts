import { AppDB } from "./db";
import {
  CatalogKind,
  CategoryRecord,
  LiveStreamRecord,
  M3UChannelRecord,
  PlaylistRecord,
  SeriesRecord,
  VodStreamRecord,
} from "./records";
import {
  getCategories,
  getLiveStreams,
  getSeriesList,
  getVodStreams,
} from "./catalogRepo";
import { getM3UChannels } from "./m3uRepo";

// Session-scoped catalog cache (iOS PlaylistContentStore equivalent). Tabs
// and screens remount constantly (only the top navigation screen renders),
// and re-reading tens of thousands of IndexedDB rows plus re-grouping them
// per category on every mount is what makes content feel slow on the TV.
// Cached PER SECTION (live/vod/series/m3u): the dashboard shows one kind at
// a time, and eagerly materializing all three arrays on open was a
// multi-hundred-ms startup spike (full-store deserialization + three sorts
// + three regroups) that also pinned the whole catalog in the JS heap.
// Load a section on first use, invalidate only when content changes.

export type CatalogItem = LiveStreamRecord | VodStreamRecord | SeriesRecord;

export interface CatalogSection {
  categories: CategoryRecord[];
  items: CatalogItem[];
  byCategory: Map<string, CatalogItem[]>;
}

const sections = new Map<string, Promise<CatalogSection>>();
const m3uChannels = new Map<string, Promise<M3UChannelRecord[]>>();

function groupByCategory<T extends { categoryId?: string }>(
  items: T[],
): Map<string, T[]> {
  const map = new Map<string, T[]>();
  for (const item of items) {
    if (item.categoryId === undefined) continue;
    let bucket = map.get(item.categoryId);
    if (!bucket) {
      bucket = [];
      map.set(item.categoryId, bucket);
    }
    bucket.push(item);
  }
  return map;
}

async function loadSection(
  db: AppDB,
  playlist: PlaylistRecord,
  kind: CatalogKind,
): Promise<CatalogSection> {
  const [categories, loaded] = await Promise.all([
    getCategories(db, playlist.id, kind),
    kind === "live"
      ? getLiveStreams(db, playlist.id)
      : kind === "vod"
        ? getVodStreams(db, playlist.id)
        : getSeriesList(db, playlist.id),
  ]);
  const items: CatalogItem[] = loaded;
  return { categories, items, byCategory: groupByCategory(items) };
}

export function getCatalogSection(
  db: AppDB,
  playlist: PlaylistRecord,
  kind: CatalogKind,
): Promise<CatalogSection> {
  const key = `${playlist.id}:${kind}`;
  let entry = sections.get(key);
  if (!entry) {
    entry = loadSection(db, playlist, kind).catch((err) => {
      sections.delete(key); // don't cache failures
      throw err;
    });
    sections.set(key, entry);
  }
  return entry;
}

export function getM3UCatalog(
  db: AppDB,
  playlist: PlaylistRecord,
): Promise<M3UChannelRecord[]> {
  let entry = m3uChannels.get(playlist.id);
  if (!entry) {
    entry = getM3UChannels(db, playlist.id).catch((err) => {
      m3uChannels.delete(playlist.id); // don't cache failures
      throw err;
    });
    m3uChannels.set(playlist.id, entry);
  }
  return entry;
}

/** Call after any import/refresh/delete that changes catalog content. */
export function invalidateCatalog(playlistId?: string): void {
  if (playlistId === undefined) {
    sections.clear();
    m3uChannels.clear();
    return;
  }
  for (const key of Array.from(sections.keys())) {
    if (key.indexOf(`${playlistId}:`) === 0) sections.delete(key);
  }
  m3uChannels.delete(playlistId);
}
