import {
  ReactNode,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  getCurrentFocusKey,
  setFocus,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { getDb } from "../../data/db";
import { FavoriteKind, PlaylistRecord } from "../../data/records";
import { isFavorite, toggleFavorite } from "../../data/favoritesRepo";
import { getResumePositionMs, saveProgress } from "../../data/watchHistoryRepo";
import { settings } from "../../data/settings";
import { createPlayer } from "../../player/playerFactory";
import { PlayerPort, PlayerState, TrackInfo } from "../../player/PlayerPort";
import {
  applyTrackPreferences,
  rememberSubtitlesOff,
  rememberTrackSelection,
} from "../../player/trackPreferences";
import { sanitizeSubtitleText } from "../../player/subtitleText";
import {
  IDLE_SEEK_STREAK,
  nextSeekStep,
  SeekStreak,
} from "../../player/seekAcceleration";
import { PlayableItem } from "../../models/playable";
import { useNavigation } from "../../navigation/NavigationStack";
import { registerBackInterceptor } from "../../navigation/backHandler";
import { KEY, normalizeKeyCode } from "../../navigation/keys";
import { t } from "../../i18n";
import { Modal } from "../components/Modal";
import { TrackSettingsPanel } from "../player/TrackSettingsPanel";
import { LiveChannelPanel } from "../player/LiveChannelPanel";

// Full player (phase 4): queue prev/next (episode nav & live zapping), track
// settings with persisted language preference, app-drawn subtitles, next-
// episode auto-advance, watch-history recording.

const CONTROLS_HIDE_MS = 5000;
const HISTORY_TICK_MS = 5000;
const AUTO_ADVANCE_SECONDS = 10;
const SEEK_COMMIT_DELAY_MS = 450;

// Player focus model: the visible play/pause button (bottom center) is the
// focus home. ↑ from it reaches the seek bar (VOD only) — ←/→ scrub ONLY
// there. → reaches the bottom-right button row (favorite / channels /
// tracks). All arrows are routed explicitly and dead ends are consumed:
// Norigin's geometric adjacency is unreliable across the sparse overlay.
const PLAYER_PLAY_KEY = "player-play-button";
const PLAYER_SEEK_KEY = "player-seek-bar";
const PLAYER_TRACKS_KEY = "player-tracks-button";
const PLAYER_FAV_KEY = "player-fav-button";
const PLAYER_CHANNELS_KEY = "player-channels-button";

function ChromeButton({
  focusKey,
  onPress,
  leftKey,
  rightKey,
  upKey,
  children,
}: {
  focusKey: string;
  onPress: () => void;
  leftKey?: string;
  rightKey?: string;
  upKey?: string;
  children: ReactNode;
}) {
  const { ref, focused } = useFocusable({
    focusKey,
    onEnterPress: onPress,
    onArrowPress: (direction: string): boolean => {
      const target =
        direction === "left"
          ? leftKey
          : direction === "right"
            ? rightKey
            : direction === "up"
              ? upKey
              : undefined;
      if (target) setFocus(target);
      return false;
    },
  });
  return (
    <div
      ref={ref}
      className={`player-chrome-button${focused ? " focused" : ""}`}
    >
      {children}
    </div>
  );
}

function PlayPauseButton({
  paused,
  buffering,
  onToggle,
  upKey,
  rightKey,
}: {
  paused: boolean;
  buffering: boolean;
  onToggle: () => void;
  upKey?: string;
  rightKey?: string;
}) {
  const { ref, focused } = useFocusable({
    focusKey: PLAYER_PLAY_KEY,
    onEnterPress: onToggle,
    onArrowPress: (direction: string): boolean => {
      if (direction === "up" && upKey) setFocus(upKey);
      else if (direction === "right" && rightKey) setFocus(rightKey);
      return false;
    },
  });
  return (
    <div
      ref={ref}
      className={`player-play-button${focused ? " focused" : ""}`}
    >
      {buffering ? <span className="play-spinner" /> : paused ? "▶" : "❚❚"}
    </div>
  );
}

function SeekBar({
  positionMs,
  durationMs,
  onStep,
  onToggle,
}: {
  positionMs: number;
  durationMs: number;
  onStep: (dir: -1 | 1) => void;
  onToggle: () => void;
}) {
  const { ref, focused } = useFocusable({
    focusKey: PLAYER_SEEK_KEY,
    onEnterPress: onToggle,
    // Scrubbing lives HERE and only here: ←/→ accumulate a seek while focus
    // stays put; ↓ returns to play/pause; ↑ is a dead end (consumed).
    onArrowPress: (direction: string): boolean => {
      if (direction === "left") onStep(-1);
      else if (direction === "right") onStep(1);
      else if (direction === "down") setFocus(PLAYER_PLAY_KEY);
      return false;
    },
  });
  const ratio =
    durationMs > 0 ? Math.min(Math.max(positionMs / durationMs, 0), 1) : 0;
  return (
    <div ref={ref} className={`player-seek${focused ? " focused" : ""}`}>
      <span className="player-time">{fmt(positionMs)}</span>
      <div className="seek-track">
        <div className="seek-fill" style={{ width: `${ratio * 100}%` }} />
        <div className="seek-thumb" style={{ left: `${ratio * 100}%` }} />
      </div>
      <span className="player-time">
        {durationMs > 0 ? fmt(durationMs) : "–"}
      </span>
    </div>
  );
}

/**
 * What the red key / heart button favorites for the current item: the live
 * channel (Xtream or M3U), the movie, or — from an episode — the series.
 */
function favoriteKeyFor(
  playlist: PlaylistRecord,
  item: PlayableItem,
): { kind: FavoriteKind; itemId: string } | null {
  if (item.historyType === "series") {
    return item.seriesId !== undefined
      ? { kind: "series", itemId: String(item.seriesId) }
      : null;
  }
  if (item.historyType === "vod") {
    return { kind: "vod", itemId: item.historyStreamId };
  }
  return {
    kind: playlist.type === "m3u" ? "m3u" : "live",
    itemId: item.historyStreamId,
  };
}

function fmt(ms: number): string {
  const total = Math.max(Math.floor(ms / 1000), 0);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => (n < 10 ? `0${n}` : String(n));
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

export function PlayerScreen({
  playlist,
  items,
  startIndex,
}: {
  playlist: PlaylistRecord;
  items: PlayableItem[];
  startIndex: number;
}) {
  const { pop } = useNavigation();
  const containerRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<PlayerPort | null>(null);
  const [index, setIndex] = useState(startIndex);
  const indexRef = useRef(startIndex);
  const item = items[index];

  const [state, setState] = useState<PlayerState>("idle");
  const [positionMs, setPositionMs] = useState(0);
  const [durationMs, setDurationMs] = useState(0);
  const [buffering, setBuffering] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [subtitleText, setSubtitleText] = useState("");
  const [textDisabled, setTextDisabled] = useState(false);
  const textDisabledRef = useRef(false);
  const [tracks, setTracks] = useState<TrackInfo[]>([]);
  const [selectedTracks, setSelectedTracks] = useState<{
    AUDIO?: number;
    TEXT?: number;
    VIDEO?: number;
  }>({});
  const [panel, setPanel] = useState<"none" | "tracks" | "channels">("none");
  const [countdown, setCountdown] = useState<number | null>(null);
  const countdownTimer = useRef<number | undefined>(undefined);
  // Ref mirrors so the global keydown/back handlers can read panel/countdown
  // without listing them as effect deps — re-registering window listeners
  // once per countdown second / panel toggle is avoidable churn.
  const panelRef = useRef(panel);
  panelRef.current = panel;
  const countdownRef = useRef(countdown);
  countdownRef.current = countdown;

  const [controlsVisible, setControlsVisible] = useState(true);
  const controlsRef = useRef(true);
  const hideTimer = useRef<number | undefined>(undefined);

  // Rapid ←/→ presses accumulate into one seek committed after a short pause;
  // issuing an AVPlay seek per keypress queues slow pipeline flushes (laggy).
  // Sustained same-direction presses accelerate the step (seekAcceleration).
  const pendingSeekRef = useRef<number | null>(null);
  const seekCommitTimer = useRef<number | undefined>(undefined);
  const seekStreakRef = useRef<SeekStreak>(IDLE_SEEK_STREAK);
  const lastShownSecond = useRef(-1);
  const prefsAppliedRef = useRef(false);

  const stepSeek = useCallback((dir: -1 | 1) => {
    const player = playerRef.current;
    if (!player) return;
    const step = nextSeekStep(seekStreakRef.current, dir, Date.now());
    seekStreakRef.current = step.streak;
    const duration = player.getDurationMs();
    const base = pendingSeekRef.current ?? player.getPositionMs();
    let target = Math.max(base + step.deltaMs, 0);
    if (duration > 0) target = Math.min(target, duration - 1000);
    pendingSeekRef.current = target;
    setPositionMs(target); // optimistic timeline feedback
    window.clearTimeout(seekCommitTimer.current);
    seekCommitTimer.current = window.setTimeout(() => {
      const commit = pendingSeekRef.current;
      pendingSeekRef.current = null;
      if (commit !== null) void player.seekTo(commit);
    }, SEEK_COMMIT_DELAY_MS);
  }, []);

  const hideControls = useCallback(() => {
    setControlsVisible(false);
    controlsRef.current = false;
  }, []);

  const showControls = useCallback(() => {
    // Clock ticks are suppressed while the OSD is hidden (nothing consumes
    // them) — re-sync on reveal so the seek bar never flashes a stale time.
    const player = playerRef.current;
    if (player && pendingSeekRef.current === null) {
      const p = player.getPositionMs();
      lastShownSecond.current = Math.floor(p / 1000);
      setPositionMs(p);
    }
    setControlsVisible(true);
    controlsRef.current = true;
    window.clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(hideControls, CONTROLS_HIDE_MS);
  }, [hideControls]);

  const togglePlay = useCallback(() => {
    const player = playerRef.current;
    if (!player) return;
    player.getState() === "playing" ? player.pause() : player.play();
  }, []);

  // Focus home when the overlay (re)appears: play/pause by default, or the
  // seek bar when the reveal came from a seek-intent key (←/→ while hidden).
  const revealFocusRef = useRef<string | null>(null);
  useEffect(() => {
    if (!controlsVisible) return;
    const target = revealFocusRef.current ?? PLAYER_PLAY_KEY;
    revealFocusRef.current = null;
    setFocus(target);
  }, [controlsVisible]);

  // Favorite state for the current item (series episodes favorite the series).
  const favKey = useMemo(() => favoriteKeyFor(playlist, item), [playlist, item]);
  const [favorite, setFavorite] = useState(false);
  useEffect(() => {
    if (!favKey) return;
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      const state = await isFavorite(db, playlist.id, favKey.kind, favKey.itemId);
      if (!cancelled) setFavorite(state);
    })();
    return () => {
      cancelled = true;
    };
  }, [playlist.id, favKey]);

  const toggleFav = useCallback(() => {
    if (!favKey) return;
    void (async () => {
      const db = await getDb();
      setFavorite(
        await toggleFavorite(db, playlist.id, favKey.kind, favKey.itemId),
      );
    })();
  }, [playlist.id, favKey]);

  const closePanel = useCallback(() => {
    setPanel("none");
    setFocus(PLAYER_PLAY_KEY);
  }, []);

  // Stable identity: LiveChannelPanel is memoized, an inline closure would
  // re-render every mounted channel row whenever the player re-renders.
  const zapFromPanel = useCallback(
    (target: number) => {
      closePanel();
      void openIndexRef.current(target);
    },
    [closePanel],
  );

  const flushHistory = useCallback(async () => {
    const player = playerRef.current;
    const current = items[indexRef.current];
    if (!player || !current) return;
    const db = await getDb();
    await saveProgress(db, {
      playlistId: playlist.id,
      type: current.historyType,
      streamId: current.historyStreamId,
      lastTimeMs: player.getPositionMs(),
      durationMs: player.getDurationMs(),
      lastWatchedAt: Date.now(),
      title: current.title,
      secondaryTitle: current.secondaryTitle,
      imageURL: current.imageURL,
      seriesId: current.seriesId,
      containerExtension: current.containerExtension,
    });
  }, [items, playlist.id]);

  const cancelCountdown = useCallback(() => {
    window.clearInterval(countdownTimer.current);
    setCountdown(null);
  }, []);

  const openIndex = useCallback(
    async (nextIndex: number, resumeOverrideMs?: number) => {
      const player = playerRef.current;
      const next = items[nextIndex];
      if (!player || !next) return;
      cancelCountdown();
      // BEFORE the timeline resets below: showControls re-syncs positionMs
      // from the still-loaded OLD stream — called later it would overwrite
      // the fresh zeros and the seek bar would show the previous episode's
      // time until the new stream's first tick.
      showControls();
      await flushHistory();
      indexRef.current = nextIndex;
      setIndex(nextIndex);
      setError(null);
      setSubtitleText("");
      setTracks([]);
      setSelectedTracks({});
      setPositionMs(0);
      setDurationMs(0);
      pendingSeekRef.current = null;
      lastShownSecond.current = -1;
      prefsAppliedRef.current = false;
      window.clearTimeout(seekCommitTimer.current);

      const db = await getDb();
      const resume =
        resumeOverrideMs ??
        next.resumeTimeMs ??
        (await getResumePositionMs(
          db,
          playlist.id,
          next.historyType,
          next.historyStreamId,
        ));

      await player
        .open({
          url: next.url,
          isLive: next.isLive,
          startPositionMs: resume,
          headers: next.userAgent
            ? { "User-Agent": next.userAgent }
            : undefined,
        })
        .catch(() => {
          // surfaced via the error event
        });
    },
    [items, playlist.id, flushHistory, cancelCountdown, showControls],
  );
  const openIndexRef = useRef(openIndex);
  openIndexRef.current = openIndex;

  // Player lifecycle (mounted once; queue switches reuse the same player).
  useEffect(() => {
    const player = createPlayer();
    playerRef.current = player;
    if (containerRef.current) player.mount(containerRef.current);

    const offs = [
      player.on("statechange", ({ state: s }) => {
        setState(s);
        // Track preferences only once playback runs: AVPlay rejects
        // setSelectTrack outside PLAYING/PAUSED (INVALID_STATE).
        if (s === "playing" && !prefsAppliedRef.current) {
          prefsAppliedRef.current = true;
          const { textEnabled } = applyTrackPreferences(player);
          textDisabledRef.current = !textEnabled;
          setTextDisabled(!textEnabled);
          setTracks(player.getTracks());
        }
      }),
      player.on("prepared", ({ durationMs: d }) => setDurationMs(d)),
      player.on("timeupdate", ({ positionMs: p }) => {
        // Only the seek bar consumes the clock: skip entirely while the OSD
        // is hidden, a panel covers it, or the item is live (no seek bar) —
        // otherwise the whole player tree re-rendered once per second for
        // zero visual change. showControls re-syncs the position on reveal.
        if (!controlsRef.current || panelRef.current !== "none") return;
        if (items[indexRef.current]?.isLive) return;
        // Skip while an accumulated seek is pending (optimistic position wins)
        // and only re-render when the visible second actually changes.
        if (pendingSeekRef.current !== null) return;
        const second = Math.floor(p / 1000);
        if (second === lastShownSecond.current) return;
        lastShownSecond.current = second;
        setPositionMs(p);
      }),
      player.on("buffering", ({ done }) => setBuffering(!done)),
      player.on("error", ({ message }) => setError(message)),
      player.on("subtitle", ({ text }) => {
        if (!textDisabledRef.current) {
          setSubtitleText(sanitizeSubtitleText(text));
        }
      }),
      player.on("ended", () => {
        const current = items[indexRef.current];
        const hasNext = indexRef.current + 1 < items.length;
        void flushHistory().then(() => {
          if (
            hasNext &&
            !current.isLive &&
            settings.autoPlayNextEpisode
          ) {
            startAutoAdvance();
          } else if (!hasNext) {
            pop();
          }
        });
      }),
    ];

    void openIndexRef.current(startIndex);

    const onVisibility = () => {
      if (document.hidden) player.suspend();
      else player.restore();
    };
    document.addEventListener("visibilitychange", onVisibility);

    const historyTimer = window.setInterval(() => {
      if (playerRef.current?.getState() === "playing") void flushHistory();
    }, HISTORY_TICK_MS);

    return () => {
      window.clearInterval(historyTimer);
      document.removeEventListener("visibilitychange", onVisibility);
      offs.forEach((off) => off());
      player.destroy();
      playerRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const startAutoAdvance = useCallback(() => {
    setCountdown(AUTO_ADVANCE_SECONDS);
    window.clearInterval(countdownTimer.current);
    countdownTimer.current = window.setInterval(() => {
      setCountdown((current) => {
        if (current === null) return null;
        if (current <= 1) {
          window.clearInterval(countdownTimer.current);
          void openIndexRef.current(indexRef.current + 1);
          return null;
        }
        return current - 1;
      });
    }, 1000);
  }, []);

  // Back priority: panel → countdown → controls → exit. Reads state via refs
  // so the interceptor registers once instead of re-stacking every countdown
  // tick / panel toggle.
  useEffect(() => {
    return registerBackInterceptor(() => {
      if (panelRef.current !== "none") {
        closePanel();
        return true;
      }
      if (countdownRef.current !== null) {
        cancelCountdown();
        pop();
        return true;
      }
      if (controlsRef.current) {
        window.clearTimeout(hideTimer.current);
        hideControls();
        return true;
      }
      void flushHistory().then(() => pop());
      return true;
    });
  }, [cancelCountdown, flushHistory, pop, hideControls, closePanel]);

  // Transport + panel keys. Panel/countdown/current-item are read through
  // refs: the listener would otherwise unbind+rebind once per countdown
  // second and on every panel toggle.
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const player = playerRef.current;
      if (!player || panelRef.current !== "none") return;
      const item = items[indexRef.current];
      if (!item) return;
      const code = normalizeKeyCode(event);
      if (code === KEY.Back) return;

      // Next-episode countdown: OK starts the next episode immediately; the
      // other transport keys stay quiet (Back cancels via the interceptor).
      if (countdownRef.current !== null) {
        if (
          code === KEY.Enter ||
          code === KEY.MediaPlay ||
          code === KEY.MediaPlayPause
        ) {
          cancelCountdown();
          void openIndexRef.current(indexRef.current + 1);
        }
        return;
      }

      // Dedicated CH+/CH− keys zap through the live queue regardless of
      // overlay/focus state (CH+ = next channel in the list).
      if (
        (code === KEY.ChannelUp || code === KEY.ChannelDown) &&
        item.isLive &&
        items.length > 1
      ) {
        const delta = code === KEY.ChannelUp ? 1 : -1;
        void openIndexRef.current(
          (indexRef.current + delta + items.length) % items.length,
        );
        return;
      }

      const controlsWereHidden = !controlsRef.current;
      // ←/→ while the controls were hidden reveal them WITH the seek bar
      // focused (seek intent) — but never seek blind: scrubbing only happens
      // with focus on the bar (SeekBar.onArrowPress).
      if (
        controlsWereHidden &&
        !item.isLive &&
        (code === KEY.Left || code === KEY.Right)
      ) {
        revealFocusRef.current = PLAYER_SEEK_KEY;
      }
      showControls();

      // With the overlay visible, OK belongs to the focused control (Norigin
      // onEnterPress); only with no player control focused does OK mean
      // play/pause (controls hidden → the overlay is unmounted).
      const focusKey = getCurrentFocusKey();
      const onPlayerControl =
        focusKey === PLAYER_PLAY_KEY ||
        focusKey === PLAYER_SEEK_KEY ||
        focusKey === PLAYER_TRACKS_KEY ||
        focusKey === PLAYER_FAV_KEY ||
        focusKey === PLAYER_CHANNELS_KEY;
      if (code === KEY.MediaPlayPause) {
        togglePlay();
      } else if (code === KEY.Enter) {
        if (!onPlayerControl) togglePlay();
      } else if (code === KEY.MediaPlay) {
        player.play();
      } else if (code === KEY.MediaPause) {
        player.pause();
      } else if (code === KEY.MediaStop) {
        void flushHistory().then(() => pop());
      } else if (!item.isLive && code === KEY.MediaRewind) {
        // Dedicated media keys scrub regardless of focus.
        stepSeek(-1);
      } else if (!item.isLive && code === KEY.MediaFastForward) {
        stepSeek(1);
      } else if (code === KEY.Up && items.length > 1 && controlsWereHidden) {
        // Queue nav only with hidden controls; the visible overlay routes
        // ↑/↓ between the seek bar, play button and side buttons.
        void openIndexRef.current(
          (indexRef.current - 1 + items.length) % items.length,
        );
      } else if (
        code === KEY.Down &&
        items.length > 1 &&
        controlsWereHidden
      ) {
        void openIndexRef.current((indexRef.current + 1) % items.length);
      } else if (code === KEY.Yellow) {
        setTracks(player.getTracks());
        setPanel("tracks");
      } else if (code === KEY.Blue && item.isLive && items.length > 1) {
        setPanel("channels");
      } else if (code === KEY.Red) {
        toggleFav();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [items, cancelCountdown, showControls, flushHistory, pop, stepSeek, toggleFav, togglePlay]);

  const selectTrack = useCallback((track: TrackInfo) => {
    const player = playerRef.current;
    if (!player) return;
    if (track.type === "TEXT") {
      textDisabledRef.current = false;
      setTextDisabled(false);
    }
    player.selectTrack(track.type, track.index);
    rememberTrackSelection(track);
    setSelectedTracks((prev) => ({ ...prev, [track.type]: track.index }));
  }, []);

  const disableText = useCallback(() => {
    textDisabledRef.current = true;
    setTextDisabled(true);
    setSubtitleText("");
    rememberSubtitlesOff();
  }, []);


  const showChannelsButton = item.isLive && items.length > 1;
  const seekKey = !item.isLive ? PLAYER_SEEK_KEY : undefined;
  const firstSideKey = favKey
    ? PLAYER_FAV_KEY
    : showChannelsButton
      ? PLAYER_CHANNELS_KEY
      : PLAYER_TRACKS_KEY;
  const afterFavKey = showChannelsButton
    ? PLAYER_CHANNELS_KEY
    : PLAYER_TRACKS_KEY;
  const tracksLeftKey = showChannelsButton
    ? PLAYER_CHANNELS_KEY
    : favKey
      ? PLAYER_FAV_KEY
      : PLAYER_PLAY_KEY;

  const overlayShown =
    (controlsVisible || state !== "playing" || error !== null) &&
    panel === "none" &&
    countdown === null;

  return (
    <div className="player-screen">
      <div ref={containerRef} className="player-surface" />

      {subtitleText !== "" && !textDisabled && (
        <div
          className={`subtitle-overlay${overlayShown ? " raised" : ""}`}
        >
          {subtitleText}
        </div>
      )}

      {overlayShown && (
          <div className="player-overlay">
            <div className="player-title-block">
              <h2>{item.title}</h2>
              {(item.isLive ||
                item.secondaryTitle ||
                items.length > 1) && (
                <p className="player-subtitle">
                  {item.isLive && (
                    <span className="live-badge">{t("stream.live")}</span>
                  )}
                  {item.secondaryTitle && <span>{item.secondaryTitle}</span>}
                  {items.length > 1 && (
                    <span className="queue-position">
                      {index + 1} / {items.length}
                    </span>
                  )}
                </p>
              )}
            </div>

            <div className="player-bottom-stack">
              {error ? (
                <p className="player-error">{error}</p>
              ) : (
                <>
                  {!item.isLive && (
                    <SeekBar
                      positionMs={positionMs}
                      durationMs={durationMs}
                      onStep={stepSeek}
                      onToggle={togglePlay}
                    />
                  )}
                  <div className="player-controls-row">
                    <PlayPauseButton
                      paused={state === "paused"}
                      buffering={buffering}
                      onToggle={togglePlay}
                      upKey={seekKey}
                      rightKey={firstSideKey}
                    />
                    <div className="player-side-buttons">
                      {favKey && (
                        <ChromeButton
                          focusKey={PLAYER_FAV_KEY}
                          onPress={toggleFav}
                          leftKey={PLAYER_PLAY_KEY}
                          rightKey={afterFavKey}
                          upKey={seekKey}
                        >
                          <span
                            className={`chrome-fav-heart${favorite ? " active" : ""}`}
                          >
                            ♥
                          </span>
                        </ChromeButton>
                      )}
                      {showChannelsButton && (
                        <ChromeButton
                          focusKey={PLAYER_CHANNELS_KEY}
                          onPress={() => setPanel("channels")}
                          leftKey={favKey ? PLAYER_FAV_KEY : PLAYER_PLAY_KEY}
                          rightKey={PLAYER_TRACKS_KEY}
                          upKey={seekKey}
                        >
                          ☰
                        </ChromeButton>
                      )}
                      <ChromeButton
                        focusKey={PLAYER_TRACKS_KEY}
                        onPress={() => {
                          setTracks(playerRef.current?.getTracks() ?? []);
                          setPanel("tracks");
                        }}
                        leftKey={tracksLeftKey}
                        upKey={seekKey}
                      >
                        ⚙
                      </ChromeButton>
                    </div>
                  </div>
                </>
              )}
              <p className="player-hints">
                {items.length > 1
                  ? "↑/↓ " +
                    (item.isLive
                      ? t("list.channel_list")
                      : t("stream.series")) +
                    " · "
                  : ""}
                {t("player.tracks.title")}: {t("tv.key.yellow")}
                {item.isLive && items.length > 1
                  ? ` · ${t("player.all_channels")}: ${t("tv.key.blue")}`
                  : ""}
              </p>
            </div>
          </div>
        )}

      {panel === "tracks" && (
        <Modal onDismiss={() => closePanel()}>
          <TrackSettingsPanel
            tracks={tracks}
            selected={selectedTracks}
            onSelectTrack={(track) => {
              selectTrack(track);
              closePanel();
            }}
            onDisableText={() => {
              disableText();
              closePanel();
            }}
            textDisabled={textDisabled}
          />
        </Modal>
      )}

      {panel === "channels" && (
        <LiveChannelPanel
          items={items}
          currentIndex={index}
          onSelect={zapFromPanel}
          onDismiss={closePanel}
        />
      )}

      {countdown !== null && (
        <div className="autonext-overlay">
          <p>{t("player.autonext.countdown", countdown)}</p>
          <p className="autonext-target">
            {items[index + 1]?.secondaryTitle ?? items[index + 1]?.title}
          </p>
          <p className="autonext-hint">{t("tv.autonext_now")}</p>
        </div>
      )}
    </div>
  );
}
