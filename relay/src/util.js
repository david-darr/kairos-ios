// Small helpers: encoding, hashing, JSON responses, safe logging.

const enc = new TextEncoder();

export function utf8(s) {
  return enc.encode(s);
}

export function toHex(buf) {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let out = "";
  for (const b of bytes) out += b.toString(16).padStart(2, "0");
  return out;
}

export function fromHex(hex) {
  if (typeof hex !== "string" || hex.length % 2 !== 0 || !/^[0-9a-f]*$/i.test(hex)) return null;
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

export function b64url(buf) {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256Hex(text) {
  return toHex(await crypto.subtle.digest("SHA-256", utf8(text)));
}

export function randomB64url(byteCount) {
  return b64url(crypto.getRandomValues(new Uint8Array(byteCount)));
}

export function json(status, body, extraHeaders = {}) {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...extraHeaders },
  });
}

export function fail(status, error, message, extraHeaders) {
  return json(status, { error, message }, extraHeaders);
}

// The only logging path in the relay. It takes a short event name and a few
// non-sensitive fields (status codes, kinds). Never pass tokens, secrets,
// signatures, request bodies or payloads here.
const ALLOWED_LOG_FIELDS = new Set(["route", "kind", "status", "reason", "event"]);
export function log(event, fields = {}) {
  const safe = { event };
  for (const [k, v] of Object.entries(fields)) {
    if (ALLOWED_LOG_FIELDS.has(k) && (typeof v === "string" ? v.length <= 40 : typeof v === "number")) safe[k] = v;
  }
  console.log(JSON.stringify(safe));
}
