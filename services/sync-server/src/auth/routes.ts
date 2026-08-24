import { Router } from "express";
import { z } from "zod";
import { db } from "../db";
import { config } from "../config";
import { generateDeviceToken, hashPassword, hashToken, verifyPassword } from "./crypto";
import { requireAuth } from "./middleware";

export const authRouter = Router();

const credentialsSchema = z.object({
  username: z.string().trim().min(3).max(64),
  password: z.string().min(8).max(256),
});

const tokenRequestSchema = credentialsSchema.extend({
  deviceName: z.string().trim().min(1).max(128).default("unknown-device"),
});

interface UserRow {
  id: number;
  username: string;
  password_hash: string;
}

const findUser = db.prepare<[string], UserRow>("SELECT id, username, password_hash FROM users WHERE username = ?");
const insertUser = db.prepare("INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?)");
const insertToken = db.prepare(`
  INSERT INTO device_tokens (user_id, device_name, token_hash, created_at, last_seen_at)
  VALUES (?, ?, ?, ?, ?)
`);

// Registration is meant for the operator to create their own account(s) on
// first run. Disable it (ALLOW_REGISTRATION=false) once your users exist.
authRouter.post("/register", async (req, res) => {
  if (!config.allowRegistration) {
    res.status(403).json({ error: "Registration is disabled on this server" });
    return;
  }

  const parsed = credentialsSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid username or password", details: parsed.error.flatten() });
    return;
  }

  const { username, password } = parsed.data;
  if (findUser.get(username)) {
    res.status(409).json({ error: "Username already taken" });
    return;
  }

  const passwordHash = await hashPassword(password);
  insertUser.run(username, passwordHash, Date.now());
  res.status(201).json({ ok: true });
});

// Exchanges username/password for a per-device bearer token. Each call
// creates a *new* device token, so the same account can be logged in from
// several devices/apps simultaneously, each revocable independently.
authRouter.post("/token", async (req, res) => {
  const parsed = tokenRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid request", details: parsed.error.flatten() });
    return;
  }

  const { username, password, deviceName } = parsed.data;
  const user = findUser.get(username);
  if (!user || !(await verifyPassword(password, user.password_hash))) {
    res.status(401).json({ error: "Invalid username or password" });
    return;
  }

  const token = generateDeviceToken();
  const now = Date.now();
  const result = insertToken.run(user.id, deviceName, hashToken(token), now, now);

  res.status(201).json({
    token,
    deviceId: result.lastInsertRowid,
    deviceName,
  });
});

interface DeviceRow {
  id: number;
  device_name: string;
  created_at: number;
  last_seen_at: number;
  revoked_at: number | null;
}

const listDevices = db.prepare<[number], DeviceRow>(`
  SELECT id, device_name, created_at, last_seen_at, revoked_at
  FROM device_tokens WHERE user_id = ? ORDER BY last_seen_at DESC
`);

authRouter.get("/devices", requireAuth, (req, res) => {
  const devices = listDevices.all(req.auth!.userId).map((d) => ({
    id: d.id,
    deviceName: d.device_name,
    createdAt: d.created_at,
    lastSeenAt: d.last_seen_at,
    revoked: d.revoked_at !== null,
    current: d.id === req.auth!.deviceTokenId,
  }));
  res.json({ devices });
});

const revokeDevice = db.prepare(`
  UPDATE device_tokens SET revoked_at = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL
`);

authRouter.delete("/devices/:id", requireAuth, (req, res) => {
  const deviceId = Number(req.params.id);
  if (!Number.isInteger(deviceId)) {
    res.status(400).json({ error: "Invalid device id" });
    return;
  }
  const result = revokeDevice.run(Date.now(), deviceId, req.auth!.userId);
  if (result.changes === 0) {
    res.status(404).json({ error: "Device not found" });
    return;
  }
  res.status(204).end();
});
