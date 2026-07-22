import { useCallback, useEffect, useRef, useState } from "react";
import {
  doesFocusableExist,
  setFocus,
} from "@noriginmedia/norigin-spatial-navigation";
import { exitApp } from "./env/platform";
import { getDb } from "./data/db";
import { getPlaylist } from "./data/playlistRepo";
import { settings } from "./data/settings";
import { dispatchBack } from "./navigation/backHandler";
import { KEY, normalizeKeyCode } from "./navigation/keys";
import {
  ScreenDescriptor,
  topScreen,
  useNavigation,
} from "./navigation/NavigationStack";
import { ScreenLayer } from "./navigation/ScreenLayer";
import { PlaylistListScreen } from "./ui/screens/PlaylistListScreen";
import { AddPlaylistScreen } from "./ui/screens/AddPlaylistScreen";
import { DashboardScreen } from "./ui/screens/DashboardScreen";
import { CategoryGridScreen } from "./ui/screens/CategoryGridScreen";
import { MovieDetailScreen } from "./ui/screens/MovieDetailScreen";
import { SeriesDetailScreen } from "./ui/screens/SeriesDetailScreen";
import { PlayerScreen } from "./ui/screens/PlayerScreen";
import { ToolchainScreen } from "./ui/screens/ToolchainScreen";
import { PlayerSpikeScreen } from "./ui/screens/PlayerSpikeScreen";
import { registerBackInterceptor } from "./navigation/backHandler";
import { useLanguageVersion } from "./i18n/react";
import { t } from "./i18n";
import "./ui/styles/app.css";

function renderScreen(screen: ScreenDescriptor) {
  switch (screen.name) {
    case "playlists":
      return <PlaylistListScreen />;
    case "addPlaylist":
      return <AddPlaylistScreen />;
    case "dashboard":
      return <DashboardScreen playlist={screen.playlist} />;
    case "categoryGrid":
      return (
        <CategoryGridScreen
          playlist={screen.playlist}
          kind={screen.kind}
          categoryId={screen.categoryId}
          title={screen.title}
        />
      );
    case "movieDetail":
      return (
        <MovieDetailScreen playlist={screen.playlist} vodId={screen.vodId} />
      );
    case "seriesDetail":
      return (
        <SeriesDetailScreen
          playlist={screen.playlist}
          seriesId={screen.seriesId}
        />
      );
    case "player":
      return (
        <PlayerScreen
          playlist={screen.playlist}
          items={screen.items}
          startIndex={screen.startIndex}
        />
      );
    case "toolchain":
      return <ToolchainScreen />;
    case "spike":
      return <SpikeWithBack />;
  }
}

export function App() {
  const { stack, pop, reset, pendingFocusRestore, consumeFocusRestore } =
    useNavigation();
  const languageVersion = useLanguageVersion();
  const [booted, setBooted] = useState(false);
  const [exitArmed, setExitArmed] = useState(false);
  const exitTimer = useRef<number | undefined>(undefined);

  // Cold start: auto-open the last used playlist (iOS attemptAutoLoad).
  useEffect(() => {
    void (async () => {
      const lastId = settings.lastPlaylistId;
      if (lastId) {
        const db = await getDb();
        const playlist = await getPlaylist(db, lastId);
        if (playlist) {
          // Seed the playlist list below the dashboard so Back pops to a
          // live, state-retaining list instead of rebuilding it.
          reset({ name: "playlists" }, { name: "dashboard", playlist });
        }
      }
      setBooted(true);
    })();
  }, [reset]);

  // After a pop the covered screen is still mounted: return focus to the
  // exact control the user left (captured at push time).
  useEffect(() => {
    if (!pendingFocusRestore) return;
    const target = pendingFocusRestore;
    requestAnimationFrame(() => {
      if (doesFocusableExist(target)) setFocus(target);
      consumeFocusRestore();
    });
  }, [pendingFocusRestore, consumeFocusRestore]);

  const onKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (normalizeKeyCode(event) !== KEY.Back) return;
      event.preventDefault();
      if (dispatchBack()) {
        setExitArmed(false);
        return;
      }
      if (stack.length > 1) {
        // Dismissing a dashboard clears the auto-open id (iOS parity),
        // whether it was pushed from the list or seeded at cold start.
        if (topScreen(stack).name === "dashboard") {
          settings.lastPlaylistId = null;
        }
        pop();
        return;
      }
      if (exitArmed) {
        exitApp();
      } else {
        setExitArmed(true);
        window.clearTimeout(exitTimer.current);
        exitTimer.current = window.setTimeout(() => setExitArmed(false), 2000);
      }
    },
    [stack, pop, exitArmed],
  );

  useEffect(() => {
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onKeyDown]);

  if (!booted) {
    return <div className="boot-screen" />;
  }

  return (
    // Keyed by language so a language switch re-renders every t() call site.
    <div className="app-shell" key={`lang-${languageVersion}`}>
      {stack.map((entry, index) => (
        <ScreenLayer
          key={`${index}:${entry.screen.name}`}
          active={index === stack.length - 1}
        >
          {renderScreen(entry.screen)}
        </ScreenLayer>
      ))}

      {exitArmed && <div className="exit-toast">{t("tv.exit_hint")}</div>}
    </div>
  );
}

/** Adapter keeping the phase-1 spike screen's stop-on-back behavior. */
function SpikeWithBack() {
  const interceptor = useRef<(() => boolean) | null>(null);
  const register = useCallback((fn: (() => boolean) | null) => {
    interceptor.current = fn;
  }, []);
  useEffect(() => {
    return registerBackInterceptor(() => interceptor.current?.() ?? false);
  }, []);
  return <PlayerSpikeScreen registerBackInterceptor={register} />;
}
