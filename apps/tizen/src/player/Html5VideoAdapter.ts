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

// Desktop-browser development fallback. Not shipped on the TV path: raw MPEG-TS
// is not playable here, .m3u8 goes through hls.js (dev dependency, dynamically
// imported), mp4 plays natively. Track selection is a no-op in this adapter.

type HlsInstance = {
  loadSource(url: string): void;
  attachMedia(el: HTMLVideoElement): void;
  destroy(): void;
};

export class Html5VideoAdapter implements PlayerPort {
  private events = new PlayerEventEmitter();
  private video: HTMLVideoElement | null = null;
  private hls: HlsInstance | null = null;
  private state: PlayerState = "idle";

  mount(container: HTMLElement): void {
    if (this.video) this.video.remove();
    const el = document.createElement("video");
    el.style.width = "100%";
    el.style.height = "100%";
    el.style.background = "#000";
    container.appendChild(el);
    this.video = el;

    el.addEventListener("loadedmetadata", () => {
      this.events.emit("prepared", { durationMs: this.getDurationMs() });
    });
    el.addEventListener("timeupdate", () => {
      this.events.emit("timeupdate", { positionMs: this.getPositionMs() });
    });
    el.addEventListener("waiting", () =>
      this.events.emit("buffering", { done: false }),
    );
    el.addEventListener("playing", () => {
      this.events.emit("buffering", { done: true });
      this.setState("playing");
    });
    el.addEventListener("pause", () => {
      if (this.state === "playing") this.setState("paused");
    });
    el.addEventListener("ended", () => this.events.emit("ended", {}));
    el.addEventListener("error", () => {
      this.setState("idle");
      this.events.emit("error", {
        message: el.error ? `video error code ${el.error.code}` : "video error",
      });
    });
  }

  async open(source: PlaybackSource): Promise<void> {
    if (!this.video) throw new Error("mount() must be called before open()");
    this.stop();
    this.setState("preparing");

    // hls.js only exists on the dev-server path; the production wgt always
    // plays through AVPlay, so the import is dead code there and tree-shaken.
    if (source.url.includes(".m3u8") && import.meta.env.DEV) {
      const { default: Hls } = await import("hls.js");
      if (Hls.isSupported()) {
        this.hls = new Hls() as unknown as HlsInstance;
        this.hls.loadSource(source.url);
        this.hls.attachMedia(this.video);
      } else {
        this.video.src = source.url;
      }
    } else {
      this.video.src = source.url;
    }

    const start = source.startPositionMs ?? 0;
    if (!source.isLive && start > 5000) {
      this.video.currentTime = start / 1000;
    }
    await this.video.play().catch((err: Error) => {
      this.setState("idle");
      this.events.emit("error", { message: err.message });
      throw err;
    });
    this.setState("playing");
  }

  play(): void {
    void this.video?.play();
  }

  pause(): void {
    this.video?.pause();
  }

  stop(): void {
    if (this.hls) {
      this.hls.destroy();
      this.hls = null;
    }
    if (this.video) {
      this.video.pause();
      this.video.removeAttribute("src");
      this.video.load();
    }
    this.setState("idle");
  }

  async seekTo(positionMs: number): Promise<void> {
    if (!this.video) return;
    this.video.currentTime = Math.max(positionMs, 0) / 1000;
  }

  getPositionMs(): number {
    return this.video ? Math.floor(this.video.currentTime * 1000) : 0;
  }

  getDurationMs(): number {
    if (!this.video || !isFinite(this.video.duration)) return 0;
    return Math.floor(this.video.duration * 1000);
  }

  getState(): PlayerState {
    return this.state;
  }

  getTracks(): TrackInfo[] {
    return [];
  }

  selectTrack(_type: TrackType, _index: number): void {
    console.info("[html5] track selection unavailable in browser dev");
  }

  suspend(): void {
    this.pause();
  }

  restore(): void {
    this.play();
  }

  on<K extends keyof PlayerEventMap>(
    event: K,
    listener: PlayerEventListener<K>,
  ): () => void {
    return this.events.on(event, listener);
  }

  destroy(): void {
    this.stop();
    this.events.removeAll();
    if (this.video) {
      this.video.remove();
      this.video = null;
    }
  }

  private setState(state: PlayerState): void {
    if (this.state === state) return;
    this.state = state;
    this.events.emit("statechange", { state });
  }
}
