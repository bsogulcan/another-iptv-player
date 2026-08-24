import crypto from "node:crypto";
import bcrypt from "bcryptjs";
import { config } from "../config";

const BCRYPT_ROUNDS = 12;

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, BCRYPT_ROUNDS);
}

export async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}

// Device tokens are opaque, high-entropy secrets handed to the client.
// Only a keyed hash of the token is ever persisted, so a database leak alone
// does not let an attacker impersonate a device.
export function generateDeviceToken(): string {
  return crypto.randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return crypto.createHmac("sha256", config.tokenPepper).update(token).digest("hex");
}
