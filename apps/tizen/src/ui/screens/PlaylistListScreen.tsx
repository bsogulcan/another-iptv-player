import { useCallback, useEffect, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { getDb } from "../../data/db";
import { PlaylistRecord } from "../../data/records";
import { deletePlaylist, getAllPlaylists } from "../../data/playlistRepo";
import { settings } from "../../data/settings";
import { useNavigation } from "../../navigation/NavigationStack";
import { useScreenActive } from "../../navigation/ScreenLayer";
import { KEY, normalizeKeyCode } from "../../navigation/keys";
import { t } from "../../i18n";
import { Button } from "../components/TextField";
import { Modal } from "../components/Modal";
import { seedDemoPlaylist } from "../../dev/demoSeed";

function PlaylistRow({
  playlist,
  onSelect,
  onFocus,
}: {
  playlist: PlaylistRecord;
  onSelect: () => void;
  onFocus: () => void;
}) {
  const { ref, focused } = useFocusable({ onEnterPress: onSelect, onFocus });
  return (
    <div ref={ref} className={`playlist-row${focused ? " focused" : ""}`}>
      <span className="playlist-name">{playlist.name}</span>
      <span className="playlist-kind">
        {playlist.type === "m3u" ? "M3U" : "Xtream"}
      </span>
    </div>
  );
}

export function PlaylistListScreen() {
  const { push } = useNavigation();
  const [playlists, setPlaylists] = useState<PlaylistRecord[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [focusedId, setFocusedId] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<PlaylistRecord | null>(
    null,
  );

  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });

  const reload = useCallback(async () => {
    const db = await getDb();
    setPlaylists(await getAllPlaylists(db));
    setLoaded(true);
  }, []);

  // Reload on every activation, not just mount: a playlist added while this
  // screen sat lower in the stack (AddPlaylist replaces itself with the new
  // dashboard) must appear when the user pops back. Row keys are stable ids,
  // so a reload does not disturb focus.
  const screenActive = useScreenActive();
  useEffect(() => {
    if (screenActive) void reload();
  }, [screenActive, reload]);

  // Also gated on screenActive: at cold start this screen sits hidden under
  // the seeded dashboard and must not steal focus when its list loads
  // (setFocus ignores focusable:false). Re-firing on activation focuses the
  // list after popping back to the cold-seeded entry, which has no savedFocus.
  useEffect(() => {
    if (loaded && screenActive) focusSelf();
  }, [loaded, screenActive, focusSelf]);

  const openPlaylist = useCallback(
    (playlist: PlaylistRecord) => {
      settings.lastPlaylistId = playlist.id;
      push({ name: "dashboard", playlist });
    },
    [push],
  );

  // Red color key opens the delete confirmation for the focused playlist.
  useEffect(() => {
    if (!screenActive) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (normalizeKeyCode(event) !== KEY.Red || !focusedId) return;
      const target = playlists.find((p) => p.id === focusedId);
      if (target) setConfirmDelete(target);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [focusedId, playlists, screenActive]);

  const doDelete = useCallback(async () => {
    if (!confirmDelete) return;
    const db = await getDb();
    await deletePlaylist(db, confirmDelete.id);
    if (settings.lastPlaylistId === confirmDelete.id) {
      settings.lastPlaylistId = null;
    }
    setConfirmDelete(null);
    await reload();
  }, [confirmDelete, reload]);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="screen playlist-screen">
        <h1 className="screen-title">{t("playlists.title")}</h1>

        {loaded && playlists.length === 0 && (
          <p className="screen-hint">{t("playlists.empty.message")}</p>
        )}

        <div className="playlist-list">
          {playlists.map((playlist) => (
            <PlaylistRow
              key={playlist.id}
              playlist={playlist}
              onSelect={() => openPlaylist(playlist)}
              onFocus={() => setFocusedId(playlist.id)}
            />
          ))}
        </div>

        <div className="playlist-actions">
          <Button
            primary
            label={t("playlists.empty.add_button")}
            onSelect={() => push({ name: "addPlaylist" })}
          />
          {import.meta.env.DEV && (
            <Button
              label="Seed demo playlist (dev)"
              onSelect={async () => {
                const db = await getDb();
                await seedDemoPlaylist(db);
                await reload();
              }}
            />
          )}
          {/* Diagnostics stay available in dev builds only. */}
          {import.meta.env.DEV && (
            <>
              <Button
                label="Diagnostics: key test"
                onSelect={() => push({ name: "toolchain" })}
              />
              <Button
                label="Diagnostics: player spike"
                onSelect={() => push({ name: "spike" })}
              />
            </>
          )}
        </div>

        {playlists.length > 0 && (
          <p className="screen-footnote">{t("tv.delete_hint")}</p>
        )}

        {confirmDelete && (
          <Modal onDismiss={() => setConfirmDelete(null)}>
            <h2>{t("playlists.delete.title")}</h2>
            <p>{t("playlists.delete.message")}</p>
            <p className="modal-target">{confirmDelete.name}</p>
            <div className="modal-actions">
              <Button
                primary
                label={t("common.confirm_delete_yes")}
                onSelect={() => void doDelete()}
              />
              <Button
                label={t("common.cancel")}
                onSelect={() => setConfirmDelete(null)}
              />
            </div>
          </Modal>
        )}
      </div>
    </FocusContext.Provider>
  );
}
