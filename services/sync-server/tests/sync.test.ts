import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-server-test-"));
process.env.DATA_DIR = dataDir;
process.env.TOKEN_PEPPER = "test-pepper";
process.env.NODE_ENV = "test";

// Imported after env vars are set, since config/db read them at module load.
import { createApp } from "../src/app";

const app = createApp();
let baseUrl: string;
let server: import("node:http").Server;

before(async () => {
  await new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      const address = server.address();
      if (address && typeof address === "object") {
        baseUrl = `http://127.0.0.1:${address.port}`;
      }
      resolve();
    });
  });
});

after(async () => {
  await new Promise<void>((resolve) => server.close(() => resolve()));
  fs.rmSync(dataDir, { recursive: true, force: true });
});

async function json(res: Response) {
  return res.json();
}

test("register, issue device token, push and pull sync items", async () => {
  const register = await fetch(`${baseUrl}/api/auth/register`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "alice", password: "correcthorsebattery" }),
  });
  assert.equal(register.status, 201);

  const tokenRes = await fetch(`${baseUrl}/api/auth/token`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "alice", password: "correcthorsebattery", deviceName: "test-device" }),
  });
  assert.equal(tokenRes.status, 201);
  const { token } = (await json(tokenRes)) as { token: string };
  assert.ok(token.length > 20);

  const pushRes = await fetch(`${baseUrl}/api/sync/push`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({
      items: [{ kind: "favorite", key: "src1:movie:1", payload: {}, updatedAt: 1000, deleted: false }],
    }),
  });
  assert.equal(pushRes.status, 200);
  const pushBody = (await json(pushRes)) as { results: { status: string }[] };
  assert.equal(pushBody.results[0].status, "applied");

  const pullRes = await fetch(`${baseUrl}/api/sync/pull?since=0`, {
    headers: { authorization: `Bearer ${token}` },
  });
  const pullBody = (await json(pullRes)) as { items: { kind: string; key: string }[]; cursor: number };
  assert.equal(pullBody.items.length, 1);
  assert.equal(pullBody.items[0].kind, "favorite");
  assert.equal(pullBody.items[0].key, "src1:movie:1");

  // Stale write (older updatedAt) must not overwrite the current value.
  const stalePush = await fetch(`${baseUrl}/api/sync/push`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({
      items: [{ kind: "favorite", key: "src1:movie:1", payload: {}, updatedAt: 500, deleted: true }],
    }),
  });
  const staleBody = (await json(stalePush)) as { results: { status: string }[] };
  assert.equal(staleBody.results[0].status, "stale");
});

test("sync routes reject requests without a valid bearer token", async () => {
  const res = await fetch(`${baseUrl}/api/sync/pull`);
  assert.equal(res.status, 401);
});

test("wrong password is rejected", async () => {
  const res = await fetch(`${baseUrl}/api/auth/token`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "alice", password: "wrong-password", deviceName: "x" }),
  });
  assert.equal(res.status, 401);
});

test("revoked device token stops working", async () => {
  const tokenRes = await fetch(`${baseUrl}/api/auth/token`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "alice", password: "correcthorsebattery", deviceName: "revoke-me" }),
  });
  const { token, deviceId } = (await json(tokenRes)) as { token: string; deviceId: number };

  const revoke = await fetch(`${baseUrl}/api/auth/devices/${deviceId}`, {
    method: "DELETE",
    headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(revoke.status, 204);

  const afterRevoke = await fetch(`${baseUrl}/api/sync/pull?since=0`, {
    headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(afterRevoke.status, 401);
});

test("a second update to an already-synced item is still visible to a delta pull", async () => {
  await fetch(`${baseUrl}/api/auth/register`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "bob", password: "correcthorsebattery" }),
  });
  const tokenRes = await fetch(`${baseUrl}/api/auth/token`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "bob", password: "correcthorsebattery", deviceName: "d1" }),
  });
  const { token } = (await json(tokenRes)) as { token: string };

  // First write, then pull to establish a cursor past it (as a second
  // device would after its initial sync).
  await fetch(`${baseUrl}/api/sync/push`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({
      items: [{ kind: "progress", key: "src:vod:1", payload: { positionSeconds: 10 }, updatedAt: 1000, deleted: false }],
    }),
  });
  const firstPull = await fetch(`${baseUrl}/api/sync/pull?since=0`, {
    headers: { authorization: `Bearer ${token}` },
  });
  const { cursor } = (await json(firstPull)) as { cursor: number };

  // Update the SAME key again (e.g. more playback progress). Naively
  // reusing the row's own rowid as the ordering column would leave this
  // update invisible to anyone who already pulled past `cursor`.
  await fetch(`${baseUrl}/api/sync/push`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({
      items: [{ kind: "progress", key: "src:vod:1", payload: { positionSeconds: 500 }, updatedAt: 2000, deleted: false }],
    }),
  });

  const deltaPull = await fetch(`${baseUrl}/api/sync/pull?since=${cursor}`, {
    headers: { authorization: `Bearer ${token}` },
  });
  const deltaBody = (await json(deltaPull)) as {
    items: { key: string; payload: { positionSeconds: number } }[];
  };
  assert.equal(deltaBody.items.length, 1);
  assert.equal(deltaBody.items[0].key, "src:vod:1");
  assert.equal(deltaBody.items[0].payload.positionSeconds, 500);
});
