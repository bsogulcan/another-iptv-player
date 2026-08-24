import path from "node:path";

function requireEnvInProduction(name: string, fallback: string): string {
  const value = process.env[name];
  if (value && value.trim().length > 0) return value;
  if (process.env.NODE_ENV === "production") {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return fallback;
}

export const config = {
  port: Number(process.env.PORT ?? 8787),
  dataDir: process.env.DATA_DIR ?? path.resolve(process.cwd(), "data"),
  get dbPath() {
    return path.join(this.dataDir, "sync.sqlite3");
  },
  // Self-hosted: registration is open by default so the first run can create
  // an account. Operators exposing this beyond their own network should set
  // ALLOW_REGISTRATION=false after creating their account(s).
  allowRegistration: (process.env.ALLOW_REGISTRATION ?? "true").toLowerCase() !== "false",
  corsOrigin: process.env.CORS_ORIGIN ?? "*",
  // Only matters in production; in dev a fallback is used so `npm run dev` works out of the box.
  tokenPepper: requireEnvInProduction("TOKEN_PEPPER", "dev-only-insecure-pepper"),
  maxSyncItemsPerPush: Number(process.env.MAX_SYNC_ITEMS_PER_PUSH ?? 500),
};
