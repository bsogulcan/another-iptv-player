/**
 * Builds direct playback URLs for Xtream Codes streams.
 *
 * Port of the iOS `PlaybackURLBuilder` (Networking/PlaybackURLBuilder.swift).
 * The iOS MockFixture/demo-URL short-circuit is intentionally not ported.
 */

/** Minimal structural playlist shape needed to build playback URLs. */
export interface PlaybackPlaylist {
  serverURL: string;
  username: string;
  password: string;
}

function cleanBaseURL(serverURL: string): string {
  let baseString = serverURL.trim();

  const lower = baseString.toLowerCase();
  if (lower.indexOf("http://") !== 0 && lower.indexOf("https://") !== 0) {
    baseString = "http://" + baseString;
  }

  // Remove trailing slash
  if (baseString.charAt(baseString.length - 1) === "/") {
    baseString = baseString.slice(0, -1);
  }

  // Remove player_api.php if user entered it
  const lowered = baseString.toLowerCase();
  if (lowered.slice(-15) === "/player_api.php") {
    baseString = baseString.slice(0, -15);
  } else if (lowered.slice(-14) === "player_api.php") {
    baseString = baseString.slice(0, -14);
  }

  return baseString.split(" ").join("");
}

function authPath(playlist: PlaybackPlaylist): string {
  const u = playlist.username.trim();
  const p = playlist.password.trim();
  return u + "/" + p;
}

export class PlaybackUrlBuilder {
  private readonly playlist: PlaybackPlaylist;

  constructor(playlist: PlaybackPlaylist) {
    this.playlist = playlist;
  }

  /** Builds URL for a live stream. Xtream API direct playback format uses server/u/p/id. */
  liveUrl(streamId: number, extension?: string | null): string {
    let urlString =
      cleanBaseURL(this.playlist.serverURL) +
      "/" +
      authPath(this.playlist) +
      "/" +
      String(streamId);
    if (extension !== undefined && extension !== null && extension !== "") {
      urlString += "." + extension;
    }
    return urlString;
  }

  /** Builds URL for a VOD (Movie). */
  movieUrl(streamId: number, containerExtension?: string | null): string {
    const ext =
      containerExtension !== undefined && containerExtension !== null
        ? containerExtension
        : "mp4";
    return (
      cleanBaseURL(this.playlist.serverURL) +
      "/movie/" +
      authPath(this.playlist) +
      "/" +
      String(streamId) +
      "." +
      ext
    );
  }

  /** Builds URL for a series episode. */
  seriesUrl(streamId: string, containerExtension?: string | null): string {
    const ext =
      containerExtension !== undefined && containerExtension !== null
        ? containerExtension
        : "mp4";
    return (
      cleanBaseURL(this.playlist.serverURL) +
      "/series/" +
      authPath(this.playlist) +
      "/" +
      streamId +
      "." +
      ext
    );
  }
}
