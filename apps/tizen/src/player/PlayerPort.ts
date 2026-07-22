export type TrackType = "AUDIO" | "TEXT" | "VIDEO";

export interface TrackInfo {
  type: TrackType;
  index: number;
  language?: string;
  label?: string;
  /** Secondary caption (iOS parity): codec · resolution · channels · LANG. */
  detail?: string;
}

export interface PlaybackSource {
  url: string;
  isLive: boolean;
  startPositionMs?: number;
  /** Extra HTTP headers; "User-Agent" comes from M3U per-channel settings. */
  headers?: Record<string, string>;
}

export type PlayerState = "idle" | "preparing" | "playing" | "paused";

export interface PlayerEventMap {
  prepared: { durationMs: number };
  timeupdate: { positionMs: number };
  buffering: { done: boolean; percent?: number };
  ended: Record<string, never>;
  error: { message: string };
  statechange: { state: PlayerState };
  /** AVPlay does not render subtitles itself; the app draws this text. */
  subtitle: { text: string; durationMs?: number };
}

export type PlayerEventListener<K extends keyof PlayerEventMap> = (
  payload: PlayerEventMap[K],
) => void;

export interface PlayerPort {
  /** Inserts the platform's video surface into the given container. */
  mount(container: HTMLElement): void;
  open(source: PlaybackSource): Promise<void>;
  play(): void;
  pause(): void;
  stop(): void;
  seekTo(positionMs: number): Promise<void>;
  getPositionMs(): number;
  getDurationMs(): number;
  getState(): PlayerState;
  getTracks(): TrackInfo[];
  selectTrack(type: TrackType, index: number): void;
  /** App went to background / came back (Tizen multitasking). */
  suspend(): void;
  restore(): void;
  on<K extends keyof PlayerEventMap>(
    event: K,
    listener: PlayerEventListener<K>,
  ): () => void;
  destroy(): void;
}

export class PlayerEventEmitter {
  private listeners = new Map<string, Set<(payload: never) => void>>();

  on<K extends keyof PlayerEventMap>(
    event: K,
    listener: PlayerEventListener<K>,
  ): () => void {
    let set = this.listeners.get(event);
    if (!set) {
      set = new Set();
      this.listeners.set(event, set);
    }
    set.add(listener as (payload: never) => void);
    return () => set!.delete(listener as (payload: never) => void);
  }

  emit<K extends keyof PlayerEventMap>(
    event: K,
    payload: PlayerEventMap[K],
  ): void {
    const set = this.listeners.get(event);
    if (!set) return;
    for (const listener of Array.from(set)) {
      try {
        (listener as PlayerEventListener<K>)(payload);
      } catch (err) {
        console.error(`[player] listener for "${event}" threw`, err);
      }
    }
  }

  removeAll(): void {
    this.listeners.clear();
  }
}
