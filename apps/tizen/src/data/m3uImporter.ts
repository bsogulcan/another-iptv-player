import { ParsedM3UChannel } from "../models/m3u";
import { AppDB } from "./db";
import { M3UChannelRecord, PlaylistRecord } from "./records";
import { replaceM3UChannels } from "./m3uRepo";
import { savePlaylist } from "./playlistRepo";
import { stableM3UChannelId } from "./sha256";
import { invalidateCatalog } from "./catalogCache";

// M3U import mirrors iOS M3UImporter: delete-then-insert with content-stable
// channel ids (sha256 of playlistId:url) so favorites and history survive.

// Pure-JS sha256 per channel (no crypto.subtle on some firmwares): a 100k
// channel list hashed in one synchronous .map() froze the UI right after the
// parser deliberately yielded — chunk the mapping with the same yields.
const RECORD_CHUNK = 2000;

function nextTick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

export async function toM3UChannelRecords(
  playlistId: string,
  channels: ParsedM3UChannel[],
): Promise<M3UChannelRecord[]> {
  const records: M3UChannelRecord[] = [];
  for (let index = 0; index < channels.length; index++) {
    if (index > 0 && index % RECORD_CHUNK === 0) await nextTick();
    const channel = channels[index];
    records.push({
      id: stableM3UChannelId(playlistId, channel.url),
      playlistId,
      name: channel.name,
      url: channel.url,
      tvgId: channel.tvgId,
      tvgName: channel.tvgName,
      tvgLogo: channel.tvgLogo,
      tvgCountry: channel.tvgCountry,
      groupTitle: channel.groupTitle,
      userAgent: channel.userAgent,
      sortIndex: index,
    });
  }
  return records;
}

export async function importM3UPlaylist(
  db: AppDB,
  playlist: PlaylistRecord,
  channels: ParsedM3UChannel[],
  onProgress?: (written: number, total: number) => void,
): Promise<void> {
  await savePlaylist(db, playlist);
  await replaceM3UChannels(
    db,
    playlist.id,
    await toM3UChannelRecords(playlist.id, channels),
    onProgress,
  );
  invalidateCatalog(playlist.id);
}
