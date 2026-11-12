// Per-device secret and request signing.
//
// At registration the relay makes a random secret and returns it once. The
// relay keeps only SHA-256(secret) as lowercase hex (the "verifier"). The
// desktop computes the same verifier from its secret and uses it, as UTF-8
// text, as the HMAC-SHA256 key. Signing string:
//
//   <timestamp>\n<METHOD>\n<path>\n<sha256 hex of the raw body>
//
// sent as X-Kairos-Timestamp (unix seconds) and X-Kairos-Signature (hex).

import { sha256Hex, toHex, fromHex, utf8 } from "./util.js";

export const SIGNATURE_WINDOW_SECONDS = 120;

export async function verifierFromSecret(secret) {
  return sha256Hex(secret);
}

export async function signingString(timestamp, method, path, body) {
  return `${timestamp}\n${method.toUpperCase()}\n${path}\n${await sha256Hex(body)}`;
}

async function hmacKey(verifier, usages) {
  return crypto.subtle.importKey("raw", utf8(verifier), { name: "HMAC", hash: "SHA-256" }, false, usages);
}

// Used by the desktop side and by the tests.
export async function signRequest(verifier, { timestamp, method, path, body }) {
  const key = await hmacKey(verifier, ["sign"]);
  const data = utf8(await signingString(timestamp, method, path, body));
  return toHex(await crypto.subtle.sign("HMAC", key, data));
}

// Returns null when the request is signed correctly and fresh, otherwise a
// short reason code. Comparison is done by WebCrypto verify (constant time).
export async function checkSignature({ request, path, body, verifier, nowSeconds }) {
  const ts = request.headers.get("x-kairos-timestamp");
  const sig = request.headers.get("x-kairos-signature");
  if (!ts || !sig) return "missing_headers";
  if (!/^\d{1,12}$/.test(ts)) return "bad_timestamp";
  if (Math.abs(nowSeconds - Number(ts)) > SIGNATURE_WINDOW_SECONDS) return "stale_timestamp";
  const sigBytes = fromHex(sig);
  if (!sigBytes || sigBytes.length !== 32) return "bad_signature";
  const key = await hmacKey(verifier, ["verify"]);
  const data = utf8(await signingString(ts, request.method, path, body));
  const ok = await crypto.subtle.verify("HMAC", key, sigBytes, data);
  return ok ? null : "bad_signature";
}
