import { HistoryKind } from "../data/records";

/**
 * One playable entry handed to the player screen. Series detail builds a full
 * episode queue of these (tvOS pattern); live/vod pass a single-item queue or
 * a channel list for zapping.
 */
export interface PlayableItem {
  url: string;
  title: string;
  secondaryTitle?: string;
  imageURL?: string;
  isLive: boolean;
  /** Watch-history identity. */
  historyType: HistoryKind;
  historyStreamId: string;
  seriesId?: number;
  containerExtension?: string;
  resumeTimeMs?: number;
  /** Per-channel override from M3U (#EXTVLCOPT etc.). */
  userAgent?: string;
}
