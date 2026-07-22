import {
  PlaybackSource,
  PlayerEventEmitter,
  PlayerEventMap,
  PlayerEventListener,
  PlayerPort,
  PlayerState,
  TrackInfo,
  TrackType,
} from "./PlayerPort";
import { t } from "../i18n";

// Samsung AVPlay is a device-global singleton: only one instance can exist,
// so every open() must be preceded by a close() of whatever was playing.
// The video plane renders behind the web view through a transparent
// <object type="application/avplayer"> element.

function avplay() {
  return window.webapis!.avplay;
}

/** Trims a possibly-string value; empty results become undefined. */
function cleanText(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed === "" ? undefined : trimmed;
}

export class AVPlayAdapter implements PlayerPort {
  private events = new PlayerEventEmitter();
  private objectEl: HTMLObjectElement | null = null;
  private state: PlayerState = "idle";
  private durationMs = 0;
  private positionMs = 0;
  private source: PlaybackSource | null = null;

  mount(container: HTMLElement): void {
    if (this.objectEl) this.objectEl.remove();
    const el = document.createElement("object");
    el.setAttribute("type", "application/avplayer");
    el.style.width = "100%";
    el.style.height = "100%";
    container.appendChild(el);
    this.objectEl = el;
  }

  private applyDisplayMethod(): void {
    try {
      avplay().setDisplayMethod("PLAYER_DISPLAY_MODE_LETTER_BOX");
    } catch (err) {
      console.warn("[avplay] setDisplayMethod not accepted", err);
    }
  }

  async open(source: PlaybackSource): Promise<void> {
    this.closeQuietly();
    this.source = source;
    this.durationMs = 0;
    this.positionMs = 0;
    this.setState("preparing");

    const player = avplay();
    player.open(source.url);

    // UHD/HDR10 pipeline must be requested explicitly on 4K panels; without
    // it some models decode 4K/HDR content through the SDR path (washed-out
    // colors). Requested unconditionally: gating on productinfo silently
    // skipped it on firmwares lacking that API, and non-UHD panels just
    // reject the property. Note: Dolby Vision profile-5 files stay washed
    // out regardless — Samsung panels have no DV support at all (profile
    // 8.1 falls back to its HDR10 base layer instead).
    try {
      player.setStreamingProperty("SET_MODE_4K", "TRUE");
    } catch (err) {
      console.warn("[avplay] SET_MODE_4K not accepted", err);
    }

    const userAgent = source.headers?.["User-Agent"];
    if (userAgent) {
      try {
        player.setStreamingProperty("USER_AGENT", userAgent);
      } catch (err) {
        console.warn("[avplay] USER_AGENT not accepted", err);
      }
    }
    const cookie = source.headers?.["Cookie"];
    if (cookie) {
      try {
        player.setStreamingProperty("COOKIE", cookie);
      } catch (err) {
        console.warn("[avplay] COOKIE not accepted", err);
      }
    }

    player.setDisplayRect(0, 0, window.innerWidth, window.innerHeight);
    this.applyDisplayMethod();

    player.setListener({
      onbufferingstart: () => this.events.emit("buffering", { done: false }),
      onbufferingprogress: (percent) =>
        this.events.emit("buffering", { done: false, percent }),
      onbufferingcomplete: () => this.events.emit("buffering", { done: true }),
      oncurrentplaytime: (ms) => {
        this.positionMs = ms;
        this.events.emit("timeupdate", { positionMs: ms });
      },
      onstreamcompleted: () => {
        this.events.emit("ended", {});
      },
      onerror: (eventType) => {
        this.setState("idle");
        this.events.emit("error", { message: String(eventType) });
      },
      onsubtitlechange: (duration, text) => {
        const durationMs = Number(duration);
        this.events.emit("subtitle", {
          text,
          durationMs: isFinite(durationMs) ? durationMs : undefined,
        });
      },
    });

    await new Promise<void>((resolve, reject) => {
      player.prepareAsync(
        () => resolve(),
        (err) => reject(new Error(`AVPlay prepare failed: ${String(err)}`)),
      );
    }).catch((err: Error) => {
      this.setState("idle");
      this.events.emit("error", { message: err.message });
      throw err;
    });

    // Re-assert in READY: firmwares that reject setDisplayMethod in IDLE
    // would otherwise stay on the firmware default, which stretches video
    // to full screen on some models.
    this.applyDisplayMethod();

    this.durationMs = source.isLive ? 0 : player.getDuration();
    this.events.emit("prepared", { durationMs: this.durationMs });

    const start = source.startPositionMs ?? 0;
    if (!source.isLive && start > 5000) {
      await this.seekTo(start).catch(() => {
        // A failed resume seek should not abort playback from zero.
      });
    }

    player.play();
    this.setState("playing");
  }

  play(): void {
    if (this.state === "paused") {
      avplay().play();
      this.setState("playing");
    }
  }

  pause(): void {
    if (this.state === "playing") {
      avplay().pause();
      this.setState("paused");
    }
  }

  stop(): void {
    this.closeQuietly();
  }

  seekTo(positionMs: number): Promise<void> {
    return new Promise((resolve, reject) => {
      const bounded =
        this.durationMs > 0
          ? Math.min(Math.max(positionMs, 0), this.durationMs - 1000)
          : Math.max(positionMs, 0);
      avplay().seekTo(
        bounded,
        () => resolve(),
        () => reject(new Error("seek failed")),
      );
    });
  }

  getPositionMs(): number {
    return this.positionMs;
  }

  getDurationMs(): number {
    return this.durationMs;
  }

  getState(): PlayerState {
    return this.state;
  }

  getTracks(): TrackInfo[] {
    try {
      return avplay()
        .getTotalTrackInfo()
        .map((raw) => {
          let language: string | undefined;
          let label: string | undefined;
          let detail: string | undefined;
          try {
            const extra = JSON.parse(raw.extra_info) as Record<string, unknown>;
            language = cleanText(extra.language) ?? cleanText(extra.track_lang);
            label = cleanText(extra.track_name);

            // iOS buildTrackMenuOption parity: the row's caption carries
            // codec · resolution · channels · LANG. Codec also serves HDR/DV
            // diagnosis ("dvhe"/"dvh1" = Dolby Vision, unsupported panels).
            const parts: string[] = [];
            const fourCC = cleanText(extra.fourCC);
            if (fourCC) {
              parts.push(
                fourCC.replace(/^(video|audio|text|application)\/(x-)?/i, ""),
              );
            }
            if (raw.type === "VIDEO") {
              const width = Number(extra.Width ?? extra.width);
              const height = Number(extra.Height ?? extra.height);
              if (isFinite(width) && isFinite(height) && width > 0) {
                parts.push(`${width}×${height}`);
              }
            }
            if (raw.type === "AUDIO") {
              const channels = Number(extra.channels ?? extra.channel);
              if (isFinite(channels) && channels > 0) {
                parts.push(t("tv.channels_format", channels));
              }
              const sampleRate = Number(extra.sample_rate);
              if (isFinite(sampleRate) && sampleRate > 0) {
                parts.push(`${Math.round(sampleRate / 1000)} kHz`);
              }
            }
            if (
              language &&
              label &&
              label.toLowerCase() !== language.toLowerCase()
            ) {
              parts.push(language.toUpperCase());
            }
            if (parts.length > 0) detail = parts.join(" · ");
          } catch {
            // extra_info is firmware-dependent; language stays unknown.
          }
          return { type: raw.type, index: raw.index, language, label, detail };
        });
    } catch (err) {
      console.warn("[avplay] getTotalTrackInfo failed", err);
      return [];
    }
  }

  selectTrack(type: TrackType, index: number): void {
    try {
      avplay().setSelectTrack(type, index);
    } catch (err) {
      // Non-fatal: AVPlay rejects track switches outside PLAYING/PAUSED
      // (INVALID_STATE). Never surface as a sticky playback error.
      console.warn(`[avplay] setSelectTrack(${type}, ${index}) failed`, err);
    }
  }

  suspend(): void {
    try {
      avplay().suspend();
    } catch (err) {
      console.warn("[avplay] suspend failed", err);
    }
  }

  restore(): void {
    try {
      avplay().restore();
    } catch (err) {
      // Some firmwares reject the parameterless form after a long suspend and
      // need a full re-prepare with the original URL and position.
      if (this.source) {
        try {
          avplay().restore(this.source.url, this.positionMs, true);
          return;
        } catch (err2) {
          console.warn("[avplay] parameterized restore failed", err2);
        }
      }
      console.warn("[avplay] restore failed", err);
    }
  }

  on<K extends keyof PlayerEventMap>(
    event: K,
    listener: PlayerEventListener<K>,
  ): () => void {
    return this.events.on(event, listener);
  }

  destroy(): void {
    this.closeQuietly();
    this.events.removeAll();
    if (this.objectEl) {
      this.objectEl.remove();
      this.objectEl = null;
    }
  }

  private closeQuietly(): void {
    try {
      const state = avplay().getState();
      if (state !== "NONE") avplay().close();
    } catch {
      // close() on an already-closed player throws; ignore.
    }
    this.setState("idle");
  }

  private setState(state: PlayerState): void {
    if (this.state === state) return;
    this.state = state;
    this.events.emit("statechange", { state });
  }
}
