import { useCallback, useEffect, useRef, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { useTabActive } from "../components/TabLayer";
import { getDb, playlistKeyRange } from "../../data/db";
import { PlaylistRecord } from "../../data/records";
import { savePlaylist } from "../../data/playlistRepo";
import { clearHistory } from "../../data/watchHistoryRepo";
import { settings } from "../../data/settings";
import {
  refreshXtreamCatalog,
  ImportProgress,
} from "../../data/xtreamImporter";
import { importM3UPlaylist } from "../../data/m3uImporter";
import { XtreamClient } from "../../api/xtreamClient";
import { XtreamUserInfo } from "../../models/xtream";
import { downloadM3U } from "../../api/m3uService";
import { parseM3U } from "../../api/m3uParser";
import {
  getLanguage,
  Language,
  setLanguage,
  SUPPORTED_LANGUAGES,
  t,
} from "../../i18n";
import { Button, ToggleField } from "../components/TextField";
import { Modal } from "../components/Modal";

const LANGUAGE_NAMES: { [K in Language]: string } = {
  ar: "العربية",
  de: "Deutsch",
  en: "English",
  es: "Español",
  fr: "Français",
  hi: "हिन्दी",
  pt: "Português",
  ru: "Русский",
  tr: "Türkçe",
  zh: "中文",
};

interface Stats {
  live: number;
  vod: number;
  series: number;
  channels: number;
  history: number;
}

/** iOS calculateRemainingDays port: unix-seconds string → localized label. */
function remainingDaysLabel(expDate: string | undefined): string {
  if (!expDate) return t("settings.playlist.unlimited_or_unknown");
  const timestamp = Number(expDate);
  if (!isFinite(timestamp)) return t("settings.playlist.unlimited_or_unknown");
  if (timestamp === 0) return t("settings.playlist.unlimited");
  const days = Math.floor((timestamp * 1000 - Date.now()) / 86_400_000);
  if (days < 0) return t("settings.playlist.expired");
  return t("common.days_format", days);
}

function LanguageButton({
  label,
  active,
  onSelect,
}: {
  label: string;
  active: boolean;
  onSelect: () => void;
}) {
  const { ref, focused } = useFocusable({ onEnterPress: onSelect });
  const classes = ["season-button"];
  if (active) classes.push("active");
  if (focused) classes.push("focused");
  return (
    <div ref={ref} className={classes.join(" ")}>
      {label}
    </div>
  );
}

export function SettingsTab({
  playlist,
  onPlaylistChanged,
}: {
  playlist: PlaylistRecord;
  onPlaylistChanged: (playlist: PlaylistRecord) => void;
}) {
  const [stats, setStats] = useState<Stats | null>(null);
  const [autoNext, setAutoNext] = useState(settings.autoPlayNextEpisode);
  const [adultFilter, setAdultFilter] = useState(playlist.filterAdultContent);
  const [phase, setPhase] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [statsReload, setStatsReload] = useState(0);
  const [userInfo, setUserInfo] = useState<XtreamUserInfo | null>(null);
  const [authState, setAuthState] = useState<"idle" | "loading" | "error">(
    "idle",
  );
  const [authError, setAuthError] = useState("");

  // The tab stays mounted while hidden (see TabLayer); bump on each return
  // to the tab so "fetched on settings open" behaviors still re-run. Skips
  // the mount (the initial fetches below cover it).
  const tabActive = useTabActive();
  const [visitKey, setVisitKey] = useState(0);
  const wasActiveRef = useRef(tabActive);
  useEffect(() => {
    if (tabActive && !wasActiveRef.current) setVisitKey((n) => n + 1);
    wasActiveRef.current = tabActive;
  }, [tabActive]);

  // iOS parity: subscription/account info is live-fetched on settings open.
  useEffect(() => {
    if (playlist.type !== "xtream") return;
    let cancelled = false;
    setAuthState("loading");
    void (async () => {
      try {
        const client = new XtreamClient(playlist);
        const response = await client.verify();
        if (!cancelled) {
          setUserInfo(response.userInfo ?? null);
          setAuthState("idle");
        }
      } catch (err) {
        if (!cancelled) {
          setAuthState("error");
          setAuthError(
            err instanceof Error ? err.message : t("common.unknown_error"),
          );
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [playlist, visitKey]);

  // No focusSelf: tab content must not steal focus from the tab bar.
  const { ref, focusKey } = useFocusable({ trackChildren: true });

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      const [live, vod, series, channels, history] = await Promise.all([
        db.countFromIndex(
          "liveStreams",
          "byPlaylist",
          playlistKeyRange("liveStreams", playlist.id),
        ),
        db.countFromIndex(
          "vodStreams",
          "byPlaylist",
          playlistKeyRange("vodStreams", playlist.id),
        ),
        db.countFromIndex(
          "series",
          "byPlaylist",
          playlistKeyRange("series", playlist.id),
        ),
        db.countFromIndex(
          "m3uChannels",
          "byPlaylist",
          playlistKeyRange("m3uChannels", playlist.id),
        ),
        db.countFromIndex(
          "watchHistory",
          "byPlaylistRecency",
          playlistKeyRange("watchHistory", playlist.id),
        ),
      ]);
      if (!cancelled) setStats({ live, vod, series, channels, history });
    })();
    return () => {
      cancelled = true;
    };
  }, [playlist.id, statsReload, visitKey]);

  const onImportProgress = useCallback((progress: ImportProgress) => {
    const label =
      progress.phase === "categories"
        ? t("add_playlist.fetching_categories")
        : progress.phase === "live"
          ? t("add_playlist.fetching_live")
          : progress.phase === "vod"
            ? t("add_playlist.fetching_movies")
            : t("add_playlist.fetching_series");
    setPhase(`${label} (${progress.written}/${progress.total})`);
  }, []);

  const refreshAll = useCallback(async () => {
    setError(null);
    setPhase(t("common.loading"));
    try {
      const db = await getDb();
      const updated = { ...playlist, filterAdultContent: adultFilter };
      if (playlist.type === "xtream") {
        const client = new XtreamClient(updated);
        await refreshXtreamCatalog(db, client, updated, onImportProgress);
      } else {
        const text = await downloadM3U(playlist.serverURL);
        const parsed = parseM3U(text);
        await importM3UPlaylist(db, updated, parsed.channels, (written, total) =>
          setPhase(`${t("add_playlist.saving_db")} (${written}/${total})`),
        );
      }
      onPlaylistChanged(updated);
      setStatsReload((n) => n + 1);
    } catch (err) {
      setError(err instanceof Error ? err.message : t("common.unknown_error"));
    } finally {
      setPhase(null);
    }
  }, [playlist, adultFilter, onImportProgress, onPlaylistChanged]);

  const toggleAdultFilter = useCallback(
    async (value: boolean) => {
      setAdultFilter(value);
      const db = await getDb();
      const updated = { ...playlist, filterAdultContent: value };
      await savePlaylist(db, updated);
      onPlaylistChanged(updated);
    },
    [playlist, onPlaylistChanged],
  );

  const doClearHistory = useCallback(async () => {
    const db = await getDb();
    await clearHistory(db, playlist.id);
    setStatsReload((n) => n + 1);
  }, [playlist.id]);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="settings-tab">
        <section className="settings-section">
          <h3>{t("settings.language.title")}</h3>
          <div className="season-bar">
            <LanguageButton
              label={t("settings.language.system")}
              active={settings.language === null}
              onSelect={() => setLanguage(null)}
            />
            {SUPPORTED_LANGUAGES.map((code) => (
              <LanguageButton
                key={code}
                label={LANGUAGE_NAMES[code]}
                active={settings.language === code && getLanguage() === code}
                onSelect={() => setLanguage(code)}
              />
            ))}
          </div>
        </section>

        <section className="settings-section">
          <h3>{t("settings.player.title")}</h3>
          <ToggleField
            label={t("settings.player.autonext.title")}
            value={autoNext}
            onChange={(value) => {
              setAutoNext(value);
              settings.autoPlayNextEpisode = value;
            }}
          />
          {playlist.type === "xtream" && (
            <ToggleField
              label={t("add_playlist.filter_adult")}
              value={adultFilter}
              onChange={(value) => void toggleAdultFilter(value)}
            />
          )}
        </section>

        <section className="settings-section">
          <h3>{t("settings.playlist.info.title")}</h3>
          <div className="settings-info">
            <p>
              {t("settings.playlist.name")}: {playlist.name}
            </p>
            <p>
              {t("settings.playlist.server_url")}: {playlist.serverURL}
            </p>
            {playlist.type === "xtream" && (
              <p>
                {t("settings.playlist.username")}: {playlist.username}
              </p>
            )}
          </div>
          {playlist.type === "xtream" && (
            <div className="settings-info">
              {authState === "loading" && (
                <p>{t("settings.playlist.fetching_info")}</p>
              )}
              {authState === "error" && (
                <p className="form-error">
                  {t("settings.playlist.info_error", authError)}
                </p>
              )}
              {userInfo && (
                <>
                  <p>
                    {t("settings.playlist.subscription")}:{" "}
                    {remainingDaysLabel(userInfo.expDate)}
                  </p>
                  <p>
                    {t("settings.playlist.active_connection")}:{" "}
                    {userInfo.activeCons ?? t("settings.playlist.unknown")} ·{" "}
                    {t("settings.playlist.max_connection")}:{" "}
                    {userInfo.maxConnections ??
                      t("settings.playlist.unlimited")}
                  </p>
                </>
              )}
            </div>
          )}
          {stats && (
            <div className="settings-info">
              {playlist.type === "xtream" ? (
                <p>
                  {t("settings.stats.live_count")}: {stats.live} ·{" "}
                  {t("settings.stats.movie_count")}: {stats.vod} ·{" "}
                  {t("settings.stats.series_count")}: {stats.series}
                </p>
              ) : (
                <p>
                  {t("settings.stats.channel_count")}: {stats.channels}
                </p>
              )}
              <p>
                {t("settings.stats.history_count")}:{" "}
                {t("settings.stats.history_items_format", stats.history)}
              </p>
            </div>
          )}
        </section>

        <section className="settings-section">
          <div className="playlist-actions">
            <Button
              primary
              label={t("settings.refresh_all")}
              onSelect={() => void refreshAll()}
            />
            <Button
              label={t("history.clear.button_entry")}
              onSelect={() => void doClearHistory()}
            />
          </div>
          {error && <p className="form-error">{error}</p>}
        </section>

        {phase && (
          <Modal blocking>
            <div className="progress-modal">
              <div className="spinner" />
              <p>{phase}</p>
            </div>
          </Modal>
        )}
      </div>
    </FocusContext.Provider>
  );
}
