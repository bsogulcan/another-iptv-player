// M3U playlist model types.
// Ported from apps/ios/another-iptv-player/Networking/M3UParser.swift (public types).

/** A single channel produced by the M3U parser. */
export interface ParsedM3UChannel {
  name: string;
  url: string;
  tvgId?: string;
  tvgName?: string;
  tvgLogo?: string;
  tvgCountry?: string;
  groupTitle?: string;
  userAgent?: string;
}

export interface ParsedM3UPlaylist {
  /** `x-tvg-url` (or `url-tvg`) from the `#EXTM3U` header line, if present. Stored only; not used for EPG yet. */
  epgURL?: string;
  channels: ParsedM3UChannel[];
}

/** Raw EXTINF line + parsed summary for a channel that ended up without a group (debug aid). */
export interface M3UNoGroupSample {
  rawExtinf: string;
  name: string;
  url: string;
}

/** Counters collected during a parse run (mirrors Swift `M3UParser.ParseDiagnostics`). */
export interface M3UParseDiagnostics {
  totalLines: number;
  extm3uLines: number;
  extinfLines: number;
  uriLines: number;
  commentLines: number;
  vlcOptLines: number;
  kodiPropLines: number;
  extgrpLines: number;
  orphanURIs: number;
  lostPendingChannels: number;
  channelCount: number;
  noGroupCount: number;
  noNameFallbackCount: number;
  /** First 20 channels that fell into the "no group" bucket (raw EXTINF + parsed summary, for debugging). */
  sampleNoGroup: M3UNoGroupSample[];
}
