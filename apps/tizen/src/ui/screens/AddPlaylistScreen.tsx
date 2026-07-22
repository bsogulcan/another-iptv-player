import { useCallback, useEffect, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { getDb } from "../../data/db";
import { PlaylistRecord } from "../../data/records";
import { settings } from "../../data/settings";
import { syncXtreamCatalog, ImportProgress } from "../../data/xtreamImporter";
import { importM3UPlaylist } from "../../data/m3uImporter";
import { XtreamClient } from "../../api/xtreamClient";
import { detectXtreamLink } from "../../api/xtreamLinkDetector";
import { downloadM3U } from "../../api/m3uService";
import { parseM3U } from "../../api/m3uParser";
import { useNavigation } from "../../navigation/NavigationStack";
import { t } from "../../i18n";
import { Button, TextField, ToggleField } from "../components/TextField";
import { Modal } from "../components/Modal";

type PlaylistType = "xtream" | "m3u";

function uuid(): string {
  // Chromium 56 has no crypto.randomUUID; getRandomValues exists everywhere.
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function TypeSwitch({
  value,
  onChange,
}: {
  value: PlaylistType;
  onChange: (type: PlaylistType) => void;
}) {
  const Xtream = useFocusable({ onEnterPress: () => onChange("xtream") });
  const M3U = useFocusable({ onEnterPress: () => onChange("m3u") });
  return (
    <div className="type-switch">
      <div
        ref={Xtream.ref}
        className={`type-option${value === "xtream" ? " active" : ""}${Xtream.focused ? " focused" : ""}`}
      >
        Xtream Codes
      </div>
      <div
        ref={M3U.ref}
        className={`type-option${value === "m3u" ? " active" : ""}${M3U.focused ? " focused" : ""}`}
      >
        M3U URL
      </div>
    </div>
  );
}

export function AddPlaylistScreen() {
  const { replace } = useNavigation();
  const [type, setType] = useState<PlaylistType>("xtream");
  const [name, setName] = useState("");
  const [serverURL, setServerURL] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [m3uURL, setM3uURL] = useState("");
  const [filterAdult, setFilterAdult] = useState(false);
  const [phase, setPhase] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });

  useEffect(() => {
    focusSelf();
  }, [focusSelf]);

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

  const finishWith = useCallback(
    (playlist: PlaylistRecord) => {
      settings.lastPlaylistId = playlist.id;
      setPhase(null);
      // Replace so Back from the dashboard returns to the playlist list.
      replace({ name: "dashboard", playlist });
    },
    [replace],
  );

  const saveXtream = useCallback(
    async (
      creds: { serverURL: string; username: string; password: string },
      displayName: string,
    ) => {
      const client = new XtreamClient(creds);
      setPhase(t("add_playlist.verifying"));
      await client.verify();

      const playlist: PlaylistRecord = {
        id: uuid(),
        name: displayName,
        type: "xtream",
        serverURL: creds.serverURL,
        username: creds.username,
        password: creds.password,
        filterAdultContent: filterAdult,
        createdAt: Date.now(),
      };
      const db = await getDb();
      await syncXtreamCatalog(db, client, playlist, onImportProgress);
      finishWith(playlist);
    },
    [filterAdult, onImportProgress, finishWith],
  );

  const saveM3U = useCallback(async () => {
    const displayName = name.trim() || "M3U Playlist";
    const url = m3uURL.trim();

    // get.php links are auto-upgraded to the Xtream API when the panel's
    // player_api.php works (metadata unlock); otherwise plain M3U fallback.
    const detected = detectXtreamLink(url);
    if (detected) {
      try {
        await saveXtream(detected, displayName);
        return;
      } catch {
        setPhase(null); // fall back to plain M3U below
      }
    }

    setPhase(t("common.loading"));
    const text = await downloadM3U(url);
    const parsed = parseM3U(text);
    const playlist: PlaylistRecord = {
      id: uuid(),
      name: displayName,
      type: "m3u",
      serverURL: url,
      username: "",
      password: "",
      filterAdultContent: filterAdult,
      m3uEpgURL: parsed.epgURL,
      createdAt: Date.now(),
    };
    const db = await getDb();
    await importM3UPlaylist(db, playlist, parsed.channels, (written, total) =>
      setPhase(`${t("add_playlist.saving_db")} (${written}/${total})`),
    );
    finishWith(playlist);
  }, [name, m3uURL, filterAdult, saveXtream, finishWith]);

  const save = useCallback(async () => {
    setError(null);
    try {
      if (type === "xtream") {
        await saveXtream(
          {
            serverURL: serverURL.trim(),
            username: username.trim(),
            password: password.trim(),
          },
          name.trim() || "IPTV",
        );
      } else {
        await saveM3U();
      }
    } catch (err) {
      setPhase(null);
      setError(err instanceof Error ? err.message : t("common.unknown_error"));
    }
  }, [type, serverURL, username, password, name, saveXtream, saveM3U]);

  const canSave =
    type === "xtream"
      ? serverURL.trim() !== "" && username.trim() !== "" && password.trim() !== ""
      : m3uURL.trim() !== "";

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="screen add-screen">
        <h1 className="screen-title">{t("add_playlist.xtream.title_new")}</h1>

        <TypeSwitch value={type} onChange={setType} />

        <div className="form">
          <TextField
            label={t("add_playlist.name_placeholder")}
            value={name}
            onChange={setName}
          />
          {type === "xtream" ? (
            <>
              <TextField
                label={t("add_playlist.server_url")}
                value={serverURL}
                onChange={setServerURL}
                type="url"
                placeholder="http://example.com:8080"
              />
              <TextField
                label={t("add_playlist.username")}
                value={username}
                onChange={setUsername}
              />
              <TextField
                label={t("add_playlist.password")}
                value={password}
                onChange={setPassword}
                type="password"
              />
            </>
          ) : (
            <TextField
              label="M3U URL"
              value={m3uURL}
              onChange={setM3uURL}
              type="url"
              placeholder="http://example.com/get.php?username=...&password=...&type=m3u_plus"
            />
          )}
          <ToggleField
            label={t("add_playlist.filter_adult")}
            value={filterAdult}
            onChange={setFilterAdult}
          />
          {canSave && (
            <Button primary label={t("common.save")} onSelect={() => void save()} />
          )}
        </div>

        {error && <p className="form-error">{error}</p>}

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
