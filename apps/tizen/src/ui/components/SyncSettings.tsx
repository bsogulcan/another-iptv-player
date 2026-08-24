import { useCallback, useEffect, useState } from "react";
import { useFocusable } from "@noriginmedia/norigin-spatial-navigation";
import { getDb } from "../../data/db";
import { t } from "../../i18n";
import * as syncApi from "../../sync/api";
import { SyncApiError } from "../../sync/api";
import {
  clearSyncConfig,
  isSyncConfigured,
  SyncIntervalMinutes,
  syncConfig,
} from "../../sync/config";
import {
  bootSync,
  outboxSize,
  runSync,
  startPeriodicSync,
  subscribeSyncStatus,
  SyncStatus,
} from "../../sync/syncEngine";
import { Button, TextField, ToggleField } from "./TextField";

const INTERVAL_OPTIONS: SyncIntervalMinutes[] = [0, 15, 30, 60];

function intervalLabel(minutes: SyncIntervalMinutes): string {
  if (minutes === 0) return t("settings.sync.interval.manual");
  return t("settings.sync.interval.minutes", minutes);
}

function OptionButton({
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

export function SyncSettings() {
  const [connected, setConnected] = useState(isSyncConfigured());
  const [serverUrl, setServerUrl] = useState(syncConfig.serverUrl ?? "");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [deviceName, setDeviceName] = useState("Tizen TV");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [status, setStatus] = useState<SyncStatus>("idle");
  const [pending, setPending] = useState(0);
  const [autoSync, setAutoSync] = useState(syncConfig.autoSyncEnabled);
  const [interval, setIntervalMinutes] = useState(syncConfig.intervalMinutes);
  const [devices, setDevices] = useState<syncApi.DeviceInfo[] | null>(null);

  useEffect(() => subscribeSyncStatus(setStatus), []);

  const refreshPending = useCallback(() => {
    void (async () => setPending(await outboxSize(await getDb())))();
  }, []);

  useEffect(() => {
    if (connected) refreshPending();
  }, [connected, status, refreshPending]);

  const loadDevices = useCallback(() => {
    if (!connected) return;
    void syncApi
      .listDevices()
      .then(setDevices)
      .catch(() => setDevices(null));
  }, [connected]);

  useEffect(() => loadDevices(), [loadDevices]);

  const connect = useCallback(
    async (mode: "login" | "register") => {
      setError(null);
      if (!serverUrl.trim() || !username.trim() || !password) {
        setError(t("settings.sync.error.missing_fields"));
        return;
      }
      setBusy(true);
      try {
        if (mode === "register") {
          await syncApi.register(serverUrl, username.trim(), password);
        }
        const res = await syncApi.requestDeviceToken(
          serverUrl,
          username.trim(),
          password,
          deviceName.trim() || "Tizen TV",
        );
        syncConfig.serverUrl = serverUrl.trim();
        syncConfig.deviceToken = res.token;
        syncConfig.deviceId = res.deviceId;
        syncConfig.accountUsername = username.trim();
        syncConfig.cursor = 0;
        setPassword("");
        setConnected(true);
        const db = await getDb();
        bootSync(db);
      } catch (err) {
        setError(
          err instanceof SyncApiError
            ? err.message
            : t("common.unknown_error"),
        );
      } finally {
        setBusy(false);
      }
    },
    [serverUrl, username, password, deviceName],
  );

  const disconnect = useCallback(async () => {
    const id = syncConfig.deviceId;
    try {
      if (id !== null) await syncApi.revokeDevice(id);
    } catch {
      // best-effort: still forget local credentials even if the revoke call fails
    }
    clearSyncConfig();
    startPeriodicSync(await getDb());
    setConnected(false);
    setDevices(null);
  }, []);

  const syncNow = useCallback(() => {
    void (async () => {
      await runSync(await getDb());
      loadDevices();
    })();
  }, [loadDevices]);

  const onToggleAutoSync = useCallback((value: boolean) => {
    setAutoSync(value);
    syncConfig.autoSyncEnabled = value;
    void getDb().then(startPeriodicSync);
  }, []);

  const onSelectInterval = useCallback((value: SyncIntervalMinutes) => {
    setIntervalMinutes(value);
    syncConfig.intervalMinutes = value;
    void getDb().then(startPeriodicSync);
  }, []);

  const revoke = useCallback(
    (deviceId: number, isSelf: boolean) => {
      void (async () => {
        await syncApi.revokeDevice(deviceId);
        if (isSelf) {
          clearSyncConfig();
          startPeriodicSync(await getDb());
          setConnected(false);
          setDevices(null);
        } else {
          loadDevices();
        }
      })();
    },
    [loadDevices],
  );

  if (!connected) {
    return (
      <section className="settings-section">
        <h3>{t("settings.sync.title")}</h3>
        <div className="settings-info">
          <p>{t("settings.sync.intro")}</p>
        </div>
        <TextField
          label={t("settings.sync.server_url")}
          value={serverUrl}
          onChange={setServerUrl}
          type="url"
          placeholder="http://192.168.1.10:8787"
        />
        <TextField
          label={t("settings.sync.username")}
          value={username}
          onChange={setUsername}
        />
        <TextField
          label={t("settings.sync.password")}
          value={password}
          onChange={setPassword}
          type="password"
        />
        <TextField
          label={t("settings.sync.device_name")}
          value={deviceName}
          onChange={setDeviceName}
        />
        <div className="playlist-actions">
          <Button
            primary
            label={busy ? t("common.loading") : t("settings.sync.login")}
            onSelect={() => void connect("login")}
          />
          <Button
            label={busy ? t("common.loading") : t("settings.sync.register")}
            onSelect={() => void connect("register")}
          />
        </div>
        {error && <p className="form-error">{error}</p>}
      </section>
    );
  }

  return (
    <section className="settings-section">
      <h3>{t("settings.sync.title")}</h3>
      <div className="settings-info">
        <p>
          {t("settings.sync.server_url")}: {syncConfig.serverUrl}
        </p>
        <p>
          {t("settings.sync.account")}: {syncConfig.accountUsername}
        </p>
        <p>
          {t("settings.sync.status")}:{" "}
          {status === "syncing"
            ? t("settings.sync.status_syncing")
            : status === "error"
              ? t("settings.sync.status_error", syncConfig.lastSyncError ?? "")
              : syncConfig.lastSyncedAt
                ? t(
                    "settings.sync.status_last_synced",
                    new Date(syncConfig.lastSyncedAt).toLocaleString(),
                  )
                : t("settings.sync.status_never")}
        </p>
        {pending > 0 && (
          <p>{t("settings.sync.pending_items", pending)}</p>
        )}
      </div>

      <ToggleField
        label={t("settings.sync.auto_sync")}
        value={autoSync}
        onChange={onToggleAutoSync}
      />

      <div className="settings-info">
        <p>{t("settings.sync.interval.title")}</p>
      </div>
      <div className="season-bar">
        {INTERVAL_OPTIONS.map((minutes) => (
          <OptionButton
            key={minutes}
            label={intervalLabel(minutes)}
            active={interval === minutes}
            onSelect={() => onSelectInterval(minutes)}
          />
        ))}
      </div>

      {devices && devices.length > 0 && (
        <div className="settings-info">
          <p>{t("settings.sync.devices_title")}</p>
          {devices.map((device) => (
            <div key={device.id} className="toggle-field">
              <span>
                {device.deviceName}
                {device.current ? ` (${t("settings.sync.this_device")})` : ""}{" "}
                · {new Date(device.lastSeenAt).toLocaleDateString()}
              </span>
              {!device.current && (
                <Button
                  label={t("settings.sync.revoke")}
                  onSelect={() => revoke(device.id, false)}
                />
              )}
            </div>
          ))}
        </div>
      )}

      <div className="playlist-actions">
        <Button
          primary
          label={
            status === "syncing" ? t("settings.sync.status_syncing") : t("settings.sync.sync_now")
          }
          onSelect={syncNow}
        />
        <Button label={t("settings.sync.sign_out")} onSelect={() => void disconnect()} />
      </div>
    </section>
  );
}
