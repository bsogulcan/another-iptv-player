#!/usr/bin/env node
// Run from the repository root:
// APPLE_KEY_ID=... APPLE_ISSUER_ID=... APPLE_PRIVATE_KEY_PATH=/path/key.p8 \
//   node apps/ios/scripts/apple-jwt.mjs
// Capture stdout with APPLE_JWT="$(node apps/ios/scripts/apple-jwt.mjs)".
import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';

try {
  for (const name of ['APPLE_KEY_ID', 'APPLE_ISSUER_ID', 'APPLE_PRIVATE_KEY_PATH']) {
    if (!process.env[name]?.trim()) throw new Error(`Missing environment variable: ${name}`);
  }
  const key = createPrivateKey(readFileSync(process.env.APPLE_PRIVATE_KEY_PATH));
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('Expected an In-App Purchase P-256 private key (.p8).');
  }
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const header = encode({ alg: 'ES256', kid: process.env.APPLE_KEY_ID.trim(), typ: 'JWT' });
  const payload = encode({
    iss: process.env.APPLE_ISSUER_ID.trim(),
    iat: now,
    exp: now + 15 * 60,
    aud: 'appstoreconnect-v1',
    bid: process.env.APPLE_BUNDLE_ID?.trim() || 'dev.ogos.another-iptv-player',
  });
  const input = `${header}.${payload}`;
  const signature = sign('sha256', Buffer.from(input), {
    key,
    dsaEncoding: 'ieee-p1363',
  }).toString('base64url');
  process.stdout.write(`${input}.${signature}\n`);
} catch (error) {
  console.error(`Could not generate Apple JWT: ${error.message}`);
  process.exitCode = 1;
}
