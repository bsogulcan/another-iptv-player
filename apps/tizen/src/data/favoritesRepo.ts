import { AppDB, playlistKeyRange } from "./db";
import { FavoriteKind, FavoriteRecord } from "./records";

export function favoriteId(
  playlistId: string,
  kind: FavoriteKind,
  itemId: string,
): string {
  return `${playlistId}_${kind}_${itemId}`;
}

export async function getFavorites(
  db: AppDB,
  playlistId: string,
  kind?: FavoriteKind,
): Promise<FavoriteRecord[]> {
  const all = await db.getAllFromIndex(
    "favorites",
    "byPlaylist",
    playlistKeyRange("favorites", playlistId),
  );
  const rows = kind ? all.filter((f) => f.kind === kind) : all;
  return rows.sort((a, b) => b.addedAt - a.addedAt);
}

export async function isFavorite(
  db: AppDB,
  playlistId: string,
  kind: FavoriteKind,
  itemId: string,
): Promise<boolean> {
  return (
    (await db.get("favorites", favoriteId(playlistId, kind, itemId))) !==
    undefined
  );
}

/** Returns the new favorite state (true = now favorited). */
export async function toggleFavorite(
  db: AppDB,
  playlistId: string,
  kind: FavoriteKind,
  itemId: string,
): Promise<boolean> {
  const id = favoriteId(playlistId, kind, itemId);
  const existing = await db.get("favorites", id);
  if (existing) {
    await db.delete("favorites", id);
    return false;
  }
  await db.put("favorites", {
    id,
    playlistId,
    kind,
    itemId,
    addedAt: Date.now(),
  });
  return true;
}
