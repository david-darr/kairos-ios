// Kairos push relay: a Cloudflare Worker. No dependencies, no build step.
//
// Routes (all JSON):
//   GET    /v1/health
//   POST   /v1/installs              register a device         (open, rate limited per IP)
//   PUT    /v1/installs/{id}         replace its tokens        (signed)
//   DELETE /v1/installs/{id}         remove the registration   (signed)
//   POST   /v1/installs/{id}/push    send alert, ring or live activity push (signed)

import { checkSignature, verifierFromSecret } from "./auth.js";
import { buildMessage, sendToApns } from "./apns.js";
import { fail, json, log, randomB64url, sha256Hex } from "./util.js";

export const LIMITS = {
  registerPerIpPerHour: 10,
  pushPerInstallPerMinute: 30,
  ringPerInstallPerMinute: 6,
  maxBodyBytes: 8192,
};

const TOKEN_RE = /^[0-9a-fA-F]{64,200}$/;
const INSTALL_PATH_RE = /^\/v1\/installs\/([A-Za-z0-9_-]{16,64})(\/push)?$/;

// Fixed-window counter in KV. KV is eventually consistent, so this is a
// brake against runaway loops and abuse, not an exact meter.
async function hit(kv, key, limit, windowSeconds, nowSeconds) {
  const bucket = Math.floor(nowSeconds / windowSeconds);
  const k = `rl:${key}:${bucket}`;
  const count = Number((await kv.get(k)) ?? 0);
  if (count >= limit) return { ok: false, retryAfter: (bucket + 1) * windowSeconds - nowSeconds };
  await kv.put(k, String(count + 1), { expirationTtl: Math.max(60, windowSeconds * 2) });
  return { ok: true };
}

function tooMany(retryAfter) {
  return fail(429, "rate_limited", "Too many requests. Try again shortly.", { "retry-after": String(Math.max(1, retryAfter)) });
}

function parseJson(text) {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && !Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

// Validates a registration body; returns { fields } or { response }.
function readTokens(body) {
  if (!body) return { response: fail(400, "bad_json", "Send a JSON object.") };
  if (typeof body.apns_token !== "string" || !TOKEN_RE.test(body.apns_token)) return { response: fail(400, "bad_apns_token", "apns_token must be a hex device token.") };
  const voip = body.voip_token ?? null;
  if (voip !== null && (typeof voip !== "string" || !TOKEN_RE.test(voip))) return { response: fail(400, "bad_voip_token", "voip_token must be a hex token or null.") };
  if (body.environment !== "sandbox" && body.environment !== "production") return { response: fail(400, "bad_environment", "environment must be sandbox or production.") };
  return { fields: { apns_token: body.apns_token.toLowerCase(), voip_token: voip === null ? null : voip.toLowerCase(), environment: body.environment } };
}

export async function handle(request, env, deps = {}) {
  const fetchFn = deps.fetch ?? globalThis.fetch;
  const now = deps.now ?? Date.now;
  const nowSeconds = Math.floor(now() / 1000);
  const url = new URL(request.url);
  const path = url.pathname;
  const kv = env.INSTALLS;

  if (path === "/v1/health" && request.method === "GET") return json(200, { ok: true });

  const isRegister = path === "/v1/installs" && request.method === "POST";
  const m = INSTALL_PATH_RE.exec(path);
  if (!isRegister && !m) return fail(404, "not_found", "No such route.");

  const bodyText = await request.text();
  if (bodyText.length > LIMITS.maxBodyBytes) return fail(413, "too_large", "Request body is too big.");

  // ---- register ----
  if (isRegister) {
    const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
    const ipKey = (await sha256Hex(ip)).slice(0, 16);
    const rl = await hit(kv, `reg:${ipKey}`, LIMITS.registerPerIpPerHour, 3600, nowSeconds);
    if (!rl.ok) return tooMany(rl.retryAfter);
    const { fields, response } = readTokens(parseJson(bodyText));
    if (response) return response;
    const installId = randomB64url(16);
    const secret = randomB64url(32);
    await kv.put(`install:${installId}`, JSON.stringify({ v: 1, verifier: await verifierFromSecret(secret), ...fields }));
    log("register", { status: 201 });
    return json(201, { install_id: installId, secret });
  }

  // ---- everything below is per install and signed ----
  if (!["PUT", "DELETE", "POST"].includes(request.method) || (m[2] && request.method !== "POST") || (!m[2] && request.method === "POST")) {
    return fail(405, "method_not_allowed", "That method does not work on this route.");
  }
  const installId = m[1];
  const key = `install:${installId}`;
  const record = parseJson((await kv.get(key)) ?? "null");
  // Unknown install and bad signature look the same on purpose.
  const denied = () => { log("denied", { status: 401 }); return fail(401, "unauthorized", "Missing or invalid signature."); };
  if (!record) return denied();
  const sigProblem = await checkSignature({ request, path, body: bodyText, verifier: record.verifier, nowSeconds });
  if (sigProblem) return denied();

  if (request.method === "DELETE") {
    await kv.delete(key);
    log("delete", { status: 204 });
    return new Response(null, { status: 204 });
  }

  if (request.method === "PUT") {
    const { fields, response } = readTokens(parseJson(bodyText));
    if (response) return response;
    await kv.put(key, JSON.stringify({ ...record, ...fields }));
    return new Response(null, { status: 204 });
  }

  // ---- push ----
  const rl = await hit(kv, `push:${installId}`, LIMITS.pushPerInstallPerMinute, 60, nowSeconds);
  if (!rl.ok) return tooMany(rl.retryAfter);
  const body = parseJson(bodyText);
  if (!body) return fail(400, "bad_json", "Send a JSON object.");
  const built = buildMessage(body, env.BUNDLE_ID, nowSeconds);
  if (built.error) return fail(built.status ?? 400, built.error, built.message);
  const { message } = built;
  if (body.kind === "ring") {
    const ringRl = await hit(kv, `ring:${installId}`, LIMITS.ringPerInstallPerMinute, 60, nowSeconds);
    if (!ringRl.ok) return tooMany(ringRl.retryAfter);
  }
  const token = message.token ?? record[message.tokenField];
  if (!token) return fail(409, "no_token", `This install has no ${message.tokenField === "voip_token" ? "call (VoIP)" : "device"} token.`);

  let result;
  try {
    result = await sendToApns({ env, fetchFn, nowSeconds, environment: record.environment, token, message });
  } catch {
    log("apns_error", { kind: body.kind, status: 502 });
    return fail(502, "apns_unreachable", "Could not reach Apple. Try again.");
  }
  log("push", { kind: body.kind, status: result.status, reason: result.reason });

  if (result.status === 200) return json(200, { ok: true, apns_id: result.apnsId ?? null });
  if (result.status === 410) {
    // Apple says the token is gone: remove it. Activity tokens are not stored.
    if (message.tokenField) {
      const fresh = parseJson((await kv.get(key)) ?? "null") ?? record;
      fresh[message.tokenField] = null;
      if (!fresh.apns_token && !fresh.voip_token) await kv.delete(key);
      else await kv.put(key, JSON.stringify(fresh));
    }
    return fail(410, "token_gone", "That device token is no longer valid and was removed.");
  }
  if (result.status === 429 || result.status >= 500) return fail(503, "apns_unavailable", "Apple is busy. Try again shortly.");
  if (result.status === 413) return fail(413, "payload_too_large", "The push payload is too big.");
  if (result.status === 403) return fail(502, "relay_misconfigured", "Apple rejected the relay's key. The relay owner needs to check it.");
  return fail(422, "apns_rejected", `Apple rejected the push${result.reason ? `: ${result.reason}` : ""}.`);
}

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch {
      log("internal_error", { status: 500 });
      return fail(500, "internal", "Something went wrong in the relay.");
    }
  },
};
