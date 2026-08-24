import type { NextFunction, Request, Response } from "express";
import { db } from "../db";
import { hashToken } from "./crypto";

interface DeviceTokenRow {
  id: number;
  user_id: number;
  username: string;
  device_name: string;
  revoked_at: number | null;
}

const findByHash = db.prepare<[string], DeviceTokenRow>(`
  SELECT dt.id, dt.user_id, u.username, dt.device_name, dt.revoked_at
  FROM device_tokens dt
  JOIN users u ON u.id = dt.user_id
  WHERE dt.token_hash = ?
`);

const touchLastSeen = db.prepare(`UPDATE device_tokens SET last_seen_at = ? WHERE id = ?`);

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const header = req.header("authorization") ?? "";
  const [scheme, token] = header.split(" ");
  if (scheme !== "Bearer" || !token) {
    res.status(401).json({ error: "Missing bearer token" });
    return;
  }

  const row = findByHash.get(hashToken(token));
  if (!row || row.revoked_at !== null) {
    res.status(401).json({ error: "Invalid or revoked token" });
    return;
  }

  touchLastSeen.run(Date.now(), row.id);

  req.auth = {
    userId: row.user_id,
    username: row.username,
    deviceTokenId: row.id,
    deviceName: row.device_name,
  };
  next();
}
