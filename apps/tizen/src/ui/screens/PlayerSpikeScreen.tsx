import { useCallback, useEffect, useRef, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { createPlayer } from "../../player/playerFactory";
import {
  PlaybackSource,
  PlayerPort,
  PlayerState,
  TrackInfo,
} from "../../player/PlayerPort";
import { KEY, normalizeKeyCode } from "../../navigation/keys";

// Phase 1 AVPlay spike: play hardcoded sources on a real TV and observe raw
// TS behavior, VOD seek stalls, track switching, suspend/restore. Reads real
// Xtream URLs from spike-sources.json (gitignored); falls back to public
// test streams that exercise HLS + mp4 only.

interface SpikeSource {
  name: string;
  url: string;
  isLive: boolean;
  userAgent?: string;
}

const FALLBACK_SOURCES: SpikeSource[] = [
  {
    name: "Public HLS test (Mux)",
    url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
    isLive: false,
  },
  {
    name: "Public mp4 (Sintel trailer)",
    url: "https://media.w3.org/2010/05/sintel/trailer.mp4",
    isLive: false,
  },
];

interface SpikeStatus {
  state: PlayerState;
  positionMs: number;
  durationMs: number;
  buffering: string;
  error: string;
  tracks: TrackInfo[];
  audioIndex: number;
  textIndex: number;
}

const INITIAL_STATUS: SpikeStatus = {
  state: "idle",
  positionMs: 0,
  durationMs: 0,
  buffering: "-",
  error: "-",
  tracks: [],
  audioIndex: -1,
  textIndex: -1,
};

function fmt(ms: number): string {
  const total = Math.floor(ms / 1000);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => (n < 10 ? `0${n}` : String(n));
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

function SourceButton({
  source,
  onSelect,
}: {
  source: SpikeSource;
  onSelect: (source: SpikeSource) => void;
}) {
  const { ref, focused } = useFocusable({
    onEnterPress: () => onSelect(source),
  });
  return (
    <div ref={ref} className={focused ? "spike-source focused" : "spike-source"}>
      {source.name}
    </div>
  );
}

export function PlayerSpikeScreen({
  registerBackInterceptor,
}: {
  registerBackInterceptor: (interceptor: (() => boolean) | null) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<PlayerPort | null>(null);
  const [sources, setSources] = useState<SpikeSource[]>(FALLBACK_SOURCES);
  const [usingFallback, setUsingFallback] = useState(true);
  const [active, setActive] = useState<SpikeSource | null>(null);
  const activeRef = useRef<SpikeSource | null>(null);
  const [status, setStatus] = useState<SpikeStatus>(INITIAL_STATUS);

  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });

  useEffect(() => {
    focusSelf();
  }, [focusSelf]);

  useEffect(() => {
    fetch("./spike-sources.json")
      .then((res) => (res.ok ? res.json() : Promise.reject(res.status)))
      .then((json: { sources?: SpikeSource[] }) => {
        if (json.sources?.length) {
          setSources(json.sources);
          setUsingFallback(false);
        }
      })
      .catch(() => {
        // Keep public fallback sources.
      });
  }, []);

  useEffect(() => {
    const player = createPlayer();
    playerRef.current = player;
    if (containerRef.current) player.mount(containerRef.current);

    const offs = [
      player.on("statechange", ({ state }) =>
        setStatus((prev) => ({ ...prev, state })),
      ),
      player.on("prepared", ({ durationMs }) =>
        setStatus((prev) => ({
          ...prev,
          durationMs,
          tracks: player.getTracks(),
          error: "-",
        })),
      ),
      player.on("timeupdate", ({ positionMs }) =>
        setStatus((prev) => ({ ...prev, positionMs })),
      ),
      player.on("buffering", ({ done, percent }) =>
        setStatus((prev) => ({
          ...prev,
          buffering: done ? "done" : `buffering ${percent ?? "?"}%`,
        })),
      ),
      player.on("ended", () =>
        setStatus((prev) => ({ ...prev, buffering: "stream completed" })),
      ),
      player.on("error", ({ message }) =>
        setStatus((prev) => ({ ...prev, error: message })),
      ),
    ];

    const onVisibility = () => {
      if (document.hidden) player.suspend();
      else player.restore();
    };
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      offs.forEach((off) => off());
      document.removeEventListener("visibilitychange", onVisibility);
      player.destroy();
      playerRef.current = null;
    };
  }, []);

  const openSource = useCallback((source: SpikeSource) => {
    const player = playerRef.current;
    if (!player) return;
    setActive(source);
    activeRef.current = source;
    setStatus({ ...INITIAL_STATUS, state: "preparing" });
    const playback: PlaybackSource = {
      url: source.url,
      isLive: source.isLive,
      headers: source.userAgent ? { "User-Agent": source.userAgent } : undefined,
    };
    player.open(playback).catch(() => {
      // Error already surfaced via the error event.
    });
  }, []);

  const stopPlayback = useCallback(() => {
    playerRef.current?.stop();
    setActive(null);
    activeRef.current = null;
    setStatus(INITIAL_STATUS);
  }, []);

  useEffect(() => {
    registerBackInterceptor(() => {
      if (activeRef.current) {
        stopPlayback();
        return true;
      }
      return false;
    });
    return () => registerBackInterceptor(null);
  }, [registerBackInterceptor, stopPlayback]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const player = playerRef.current;
      if (!player || !activeRef.current) return;
      const code = normalizeKeyCode(event);
      const src = activeRef.current;

      if (code === KEY.MediaPlayPause) {
        player.getState() === "playing" ? player.pause() : player.play();
      } else if (code === KEY.MediaPlay) {
        player.play();
      } else if (code === KEY.MediaPause) {
        player.pause();
      } else if (code === KEY.MediaStop) {
        stopPlayback();
      } else if (!src.isLive && (code === KEY.Left || code === KEY.MediaRewind)) {
        void player.seekTo(player.getPositionMs() - 10_000);
      } else if (
        !src.isLive &&
        (code === KEY.Right || code === KEY.MediaFastForward)
      ) {
        void player.seekTo(player.getPositionMs() + 10_000);
      } else if (code === KEY.Red) {
        cycleTrack(player, "AUDIO");
      } else if (code === KEY.Green) {
        cycleTrack(player, "TEXT");
      }
    };

    const cycleTrack = (player: PlayerPort, type: "AUDIO" | "TEXT") => {
      const all = player.getTracks().filter((t) => t.type === type);
      if (all.length === 0) return;
      setStatus((prev) => {
        const current = type === "AUDIO" ? prev.audioIndex : prev.textIndex;
        const pos = all.findIndex((t) => t.index === current);
        const next = all[(pos + 1) % all.length];
        player.selectTrack(type, next.index);
        return type === "AUDIO"
          ? { ...prev, audioIndex: next.index }
          : { ...prev, textIndex: next.index };
      });
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [stopPlayback]);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="spike-shell">
        <div ref={containerRef} className="spike-video" />

        <div className="spike-panel">
          <h2>Player spike {usingFallback ? "(public fallback sources)" : ""}</h2>
          {usingFallback && (
            <p className="spike-hint">
              Xtream URL testi için spike-sources.example.json dosyasını
              spike-sources.json olarak kopyalayıp doldur.
            </p>
          )}
          <div className="spike-sources">
            {sources.map((source) => (
              <SourceButton
                key={source.name}
                source={source}
                onSelect={openSource}
              />
            ))}
          </div>

          <div className="spike-status">
            <div>state: {status.state}</div>
            <div>
              time: {fmt(status.positionMs)} /{" "}
              {status.durationMs > 0 ? fmt(status.durationMs) : "live/–"}
            </div>
            <div>buffer: {status.buffering}</div>
            <div className="spike-error">error: {status.error}</div>
            <div>
              tracks:{" "}
              {status.tracks.length === 0
                ? "–"
                : status.tracks
                    .map((t) => `${t.type}#${t.index}${t.language ? `(${t.language})` : ""}`)
                    .join(" ")}
            </div>
            {active && (
              <div className="spike-active">playing: {active.name}</div>
            )}
          </div>

          <p className="spike-help">
            Enter: aç · Play/Pause: duraklat · ←/→: ±10 sn (VOD) · Kırmızı: ses
            parçası · Yeşil: altyazı · Back: durdur
          </p>
        </div>
      </div>
    </FocusContext.Provider>
  );
}
