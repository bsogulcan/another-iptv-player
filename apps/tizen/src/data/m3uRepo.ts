import { AppDB, bulkPut, deletePlaylistRows, playlistKeyRange } from "./db";
import { M3UChannelRecord } from "./records";

export async function getM3UChannels(
  db: AppDB,
  playlistId: string,
): Promise<M3UChannelRecord[]> {
  const rows = await db.getAllFromIndex(
    "m3uChannels",
    "byPlaylist",
    playlistKeyRange("m3uChannels", playlistId),
  );
  return rows.sort((a, b) => a.sortIndex - b.sortIndex);
}

/**
 * Groups channels by group-title preserving playlist order. Ungrouped channels
 * fall into the bucket named by `ungroupedLabel` (localized by the caller).
 */
export function groupChannels(
  channels: M3UChannelRecord[],
  ungroupedLabel: string,
): { groupNames: string[]; channelsByGroup: Map<string, M3UChannelRecord[]> } {
  const channelsByGroup = new Map<string, M3UChannelRecord[]>();
  for (const channel of channels) {
    const group = channel.groupTitle?.trim() || ungroupedLabel;
    let bucket = channelsByGroup.get(group);
    if (!bucket) {
      bucket = [];
      channelsByGroup.set(group, bucket);
    }
    bucket.push(channel);
  }
  return { groupNames: Array.from(channelsByGroup.keys()), channelsByGroup };
}

/**
 * Replaces a playlist's channels (delete-then-insert, like iOS M3UImporter).
 * Channel ids are content-stable hashes so favorites/history survive.
 */
export async function replaceM3UChannels(
  db: AppDB,
  playlistId: string,
  channels: M3UChannelRecord[],
  onProgress?: (written: number, total: number) => void,
): Promise<void> {
  await deletePlaylistRows(db, playlistId, ["m3uChannels"]);
  await bulkPut(db, "m3uChannels", channels, 500, onProgress);
}
