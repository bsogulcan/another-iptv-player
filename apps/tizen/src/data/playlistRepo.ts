import { AppDB, deletePlaylistRows } from "./db";
import { PlaylistRecord } from "./records";
import { invalidateCatalog } from "./catalogCache";

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
  await db.put("playlists", playlist);
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
