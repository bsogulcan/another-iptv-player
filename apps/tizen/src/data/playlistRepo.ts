import { AppDB, deletePlaylistRows } from "./db";
import { PlaylistRecord } from "./records";
import { invalidateCatalog } from "./catalogCache";
import { resetSyncCursor } from "../sync/config";

export async function getAllPlaylists(db: AppDB): Promise<PlaylistRecord[]> {
  const all = await db.getAll("playlists");
  return all.sort((a, b) => a.createdAt - b.createdAt);
}

export function getPlaylist(
  db: AppDB,
  id: string,
): Promise<PlaylistRecord | undefined> {
  return db.get("playlists", id);
}

export async function savePlaylist(
  db: AppDB,
  playlist: PlaylistRecord,
): Promise<void> {
  const isNew = (await db.get("playlists", playlist.id)) === undefined;
  await db.put("playlists", playlist);
  // A newly added playlist might match one another device already pushed
  // favorites/progress for before this device ever synced; those pushes are
  // behind the current cursor, so replay from the start to pick them up.
  if (isNew) resetSyncCursor();
}

/** Removes the playlist and every row that belongs to it. */
export async function deletePlaylist(db: AppDB, id: string): Promise<void> {
  await deletePlaylistRows(db, id, [
    "categories",
    "liveStreams",
    "vodStreams",
    "series",
    "seriesInfo",
    "vodInfo",
    "m3uChannels",
    "favorites",
    "watchHistory",
  ]);
  await db.delete("playlists", id);
  invalidateCatalog(id);
}
