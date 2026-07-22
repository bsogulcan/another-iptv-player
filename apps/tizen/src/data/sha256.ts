import { sha256 } from "js-sha256";

// js-sha256 instead of crypto.subtle: the packaged wgt origin is not a secure
// context on all firmwares, where crypto.subtle is undefined.

/** Stable M3U channel id so favorites/history survive playlist re-imports. */
export function stableM3UChannelId(playlistId: string, url: string): string {
  return sha256(`${playlistId}:${url}`);
}
