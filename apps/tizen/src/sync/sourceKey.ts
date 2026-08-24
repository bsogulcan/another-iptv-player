import { sha256 } from "js-sha256";
import { AppDB } from "../data/db";
import { PlaylistRecord } from "../data/records";
import { getAllPlaylists } from "../data/playlistRepo";

/**
 * Stable, non-secret identifier for a playlist, used to scope sync items
 * (`sync/key = "<sourceKey>:<contentType>:<contentId>"`). Derived from the
 * server + account identity rather than the local playlist row id, which is
 * generated per install and would differ across a user's devices for what
 * is otherwise "the same playlist". The password is deliberately excluded
 * so it never reaches the sync server.
 */
export function playlistSourceKey(playlist: PlaylistRecord): string {
  return sha256(`${playlist.type}:${playlist.serverURL}:${playlist.username}`);
}

/** Reverse lookup: which local playlist (if any) a pulled item's sourceKey belongs to. */
export async function findPlaylistBySourceKey(
  db: AppDB,
  sourceKey: string,
): Promise<PlaylistRecord | undefined> {
  const playlists = await getAllPlaylists(db);
  return playlists.find((p) => playlistSourceKey(p) === sourceKey);
}
