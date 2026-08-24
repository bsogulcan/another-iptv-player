import { DEFAULT_TIMEOUT_MS } from "../api/http";
import { syncConfig } from "./config";
import { PullResponse, PushResponse, SyncPushItem } from "./types";

export class SyncApiError extends Error {
  readonly status?: number;
  constructor(message: string, status?: number) {
    super(message);
    this.name = "SyncApiError";
    this.status = status;
  }
}

function normalizeServerUrl(url: string): string {
  let base = url.trim();
  const lower = base.toLowerCase();
  if (lower.indexOf("http://") !== 0 && lower.indexOf("https://") !== 0) {
    base = "http://" + base;
  }
  if (base.charAt(base.length - 1) === "/") {
    base = base.slice(0, -1);
  }
  return base;
}

async function request<T>(
  path: string,
  init: { method: "GET" | "POST" | "DELETE"; body?: unknown; auth?: boolean },
  baseUrlOverride?: string,
): Promise<T> {
  const baseUrl = baseUrlOverride ?? syncConfig.serverUrl;
  if (!baseUrl) throw new SyncApiError("Sync server URL is not configured");
  const url = normalizeServerUrl(baseUrl) + path;

  const headers: Record<string, string> = {};
  if (init.body !== undefined) headers["content-type"] = "application/json";
  if (init.auth) {
    const token = syncConfig.deviceToken;
    if (!token) throw new SyncApiError("Not signed in to a sync server");
    headers["authorization"] = `Bearer ${token}`;
  }

  // No AbortController on Tizen 4.0 (Chromium 56); fetchWithTimeout races a
  // timer instead, same trick the Xtream client uses.
  let response: Response;
  try {
    response = await Promise.race([
      fetch(url, {
        method: init.method,
        headers,
        body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
      }),
      new Promise<never>((_, reject) => {
        setTimeout(
          () => reject(new SyncApiError("Sync request timed out")),
          DEFAULT_TIMEOUT_MS,
        );
      }),
    ]);
  } catch (err) {
    if (err instanceof SyncApiError) throw err;
    throw new SyncApiError(
      err instanceof Error ? err.message : "Network error contacting sync server",
    );
  }

  if (!response.ok) {
    let message = `Sync server returned ${response.status}`;
    try {
      const body = (await response.json()) as { error?: string };
      if (body.error) message = body.error;
    } catch {
      // ignore non-JSON error bodies
    }
    throw new SyncApiError(message, response.status);
  }

  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

export async function register(
  serverUrl: string,
  username: string,
  password: string,
): Promise<void> {
  await request<{ ok: true }>(
    "/api/auth/register",
    { method: "POST", body: { username, password } },
    serverUrl,
  );
}

export interface TokenResponse {
  token: string;
  deviceId: number;
  deviceName: string;
}

export async function requestDeviceToken(
  serverUrl: string,
  username: string,
  password: string,
  deviceName: string,
): Promise<TokenResponse> {
  return request<TokenResponse>(
    "/api/auth/token",
    { method: "POST", body: { username, password, deviceName } },
    serverUrl,
  );
}

export interface DeviceInfo {
  id: number;
  deviceName: string;
  createdAt: number;
  lastSeenAt: number;
  revoked: boolean;
  current: boolean;
}

export async function listDevices(): Promise<DeviceInfo[]> {
  const res = await request<{ devices: DeviceInfo[] }>("/api/auth/devices", {
    method: "GET",
    auth: true,
  });
  return res.devices;
}

export async function revokeDevice(deviceId: number): Promise<void> {
  await request<void>(`/api/auth/devices/${deviceId}`, {
    method: "DELETE",
    auth: true,
  });
}

export async function push(items: SyncPushItem[]): Promise<PushResponse> {
  return request<PushResponse>("/api/sync/push", {
    method: "POST",
    body: { items },
    auth: true,
  });
}

export async function pull(since: number): Promise<PullResponse> {
  return request<PullResponse>(`/api/sync/pull?since=${since}&limit=1000`, {
    method: "GET",
    auth: true,
  });
}
