// Apple push: provider token (ES256 JWT), message builders, and the send call.

import { b64url, utf8 } from "./util.js";

export const HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

// Apple: refresh the provider token no more than once every 20 minutes and
// before it is 60 minutes old. We refresh at 40 minutes.
export const TOKEN_MIN_AGE_SECONDS = 20 * 60;
export const TOKEN_REFRESH_SECONDS = 40 * 60;

let cache = null; // { id, jwt, iat }
let pending = null; // { id, promise }

export function resetTokenCache() {
  cache = null;
  pending = null;
}

function pemToDer(pem) {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function makeJwt(env, iat) {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(env.APNS_KEY_P8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = b64url(utf8(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID })));
  const claims = b64url(utf8(JSON.stringify({ iss: env.APNS_TEAM_ID, iat })));
  const input = `${header}.${claims}`;
  // WebCrypto ECDSA returns raw r||s, which is exactly the JWS ES256 format.
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(input));
  return `${input}.${b64url(sig)}`;
}

// Returns a valid provider token, reusing the cached one until it is old
// enough to refresh. `force` is only for an ExpiredProviderToken answer and is
// still held to Apple's 20 minute minimum.
export async function providerToken(env, nowSeconds, force = false) {
  const id = `${env.APNS_TEAM_ID}:${env.APNS_KEY_ID}:${env.APNS_KEY_P8.length}`;
  const sameKey = cache && cache.id === id;
  const age = sameKey ? nowSeconds - cache.iat : Infinity;
  const needsRefresh = age >= TOKEN_REFRESH_SECONDS || age < 0 || (force && age >= TOKEN_MIN_AGE_SECONDS);
  if (sameKey && !needsRefresh) return cache.jwt;
  if (pending && pending.id === id) return pending.promise;
  const promise = makeJwt(env, nowSeconds).then((jwt) => {
    cache = { id, jwt, iat: nowSeconds };
    return jwt;
  });
  pending = { id, promise };
  try {
    return await promise;
  } finally {
    if (pending && pending.promise === promise) pending = null;
  }
}

// ---- message builders (pure) ----

const ALERT_TEXT = {
  message: (who) => `${who} sent you a message`,
  needs_you: (who) => `${who} needs you`,
  approval: (who) => `${who} is waiting for your approval`,
  done: (who) => `${who} finished a task`,
};
export const ALERT_KINDS = Object.keys(ALERT_TEXT);

// The phone's notification kinds the desktop sends (kairos-ios KairosAgents/Native/Notifications.swift,
// NoticeKind). Each line is exactly the phone's own `headline` (test/wording.test.js checks it);
// the title of the notification is who it is from, so the line never repeats the name.
const NOTICE_TEXT = {
  approval: () => "Wants your approval",
  question: () => "Is waiting for your answer",
  replyReady: () => "Your reply is ready",
  workDone: () => "Finished a task",
  workFailed: () => "Couldn't finish",
};
export const NOTICE_KINDS = Object.keys(NOTICE_TEXT);
export function noticeLine(notice, who) {
  return NOTICE_TEXT[notice](who);
}
const TIME_SENSITIVE = new Set(["approval", "question"]);

export const LIMITS = { who: 40, title: 80, link: 256, id: 128, thread: 64 };
const LINK_RE = /^kairos-agents:\/\/(chat|bot|approval|ring|call|ask|area|tab|home|desktop|new-chat)(\/[A-Za-z0-9_.-]{1,128})?(\?bot=[A-Za-z0-9_-]{1,64})?$/;
const ID_RE = /^[A-Za-z0-9_.:-]{1,128}$/;
const THREAD_RE = /^[A-Za-z0-9_.:-]{1,64}$/;
const COLLAPSE_RE = /^[A-Za-z0-9_.:-]{1,64}$/;

// One line of plain text: control, line and paragraph separators and bidi overrides become spaces,
// runs of space collapse, and the result is cut to `max` characters (never inside a surrogate pair).
export function cleanText(value, max) {
  if (typeof value !== "string") return "";
  const s = value.replace(/[\p{Cc}\p{Zl}\p{Zp}‪-‮⁦-⁩]/gu, " ").replace(/\s+/g, " ").trim();
  return Array.from(s).slice(0, max).join("").trim();
}

export function cleanLabel(value, fallback = "Kairos") {
  return cleanText(value, LIMITS.who) || fallback;
}

const pick = (value, re, max) => (typeof value === "string" && value.length <= max && re.test(value) ? value : null);

export function buildAlert(body, bundleId, nowSeconds) {
  const message = {
    tokenField: "apns_token",
    topic: bundleId,
    pushType: "alert",
    priority: 10,
    expiration: nowSeconds + 3600,
  };
  const collapse = pick(body.collapse_id, COLLAPSE_RE, 64);
  if (collapse) message.collapseId = collapse;

  // Without `notice` this is the original generic alert, unchanged.
  if (body.notice === undefined) {
    if (!ALERT_KINDS.includes(body.what)) return { error: "bad_what", message: `what must be one of ${ALERT_KINDS.join(", ")}.` };
    const text = ALERT_TEXT[body.what](cleanLabel(body.who));
    message.payload = { aps: { alert: { title: "Kairos", body: text }, sound: "default" }, kind: body.what };
    return { message };
  }

  if (!NOTICE_KINDS.includes(body.notice)) return { error: "bad_notice", message: `notice must be one of ${NOTICE_KINDS.join(", ")}.` };
  const who = cleanLabel(body.who);
  const alert = { title: who, body: NOTICE_TEXT[body.notice](who) };
  const title = cleanText(body.title, LIMITS.title);
  if (title) alert.subtitle = title;
  const link = pick(body.link, LINK_RE, LIMITS.link);
  const requestId = pick(body.request_id, ID_RE, LIMITS.id);
  const chat = link && /^kairos-agents:\/\/chat\/([A-Za-z0-9_.-]+)$/.exec(link);
  const thread = pick(body.thread_id, THREAD_RE, LIMITS.thread) ?? (chat ? `chat-${chat[1]}`.slice(0, LIMITS.thread) : body.notice);
  const aps = {
    alert,
    sound: "default",
    category: `kairos.${body.notice}`,
    "thread-id": thread,
    "interruption-level": TIME_SENSITIVE.has(body.notice) ? "time-sensitive" : "active",
  };
  // Custom keys exactly as the phone reads them (NativeNotifications.handle): strings only.
  const payload = { aps, kind: body.notice };
  if (link) payload.link = link;
  if (requestId) payload.request_id = requestId;
  const activityId = pick(body.activity_id, ID_RE, LIMITS.id);
  const activityKind = pick(body.activity_kind, /^[A-Za-z_]{1,32}$/, 32);
  if (activityId && activityKind) {
    payload.activity_id = activityId;
    payload.activity_kind = activityKind;
  }
  message.payload = payload;
  return { message };
}

export const RING_MIN_SECONDS_LEFT = 3;
export const RING_MAX_SECONDS_AHEAD = 300;

export function buildRing(body, bundleId, nowSeconds) {
  if (typeof body.ring_id !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(body.ring_id)) return { error: "bad_ring_id", message: "ring_id must be 1 to 64 letters, digits, dashes or underscores." };
  if (!Number.isInteger(body.expires_at)) return { error: "bad_expires_at", message: "expires_at must be unix seconds." };
  if (body.expires_at - nowSeconds < RING_MIN_SECONDS_LEFT) return { error: "ring_expired", status: 409, message: "That ring has already run out. No call was sent." };
  if (body.expires_at - nowSeconds > RING_MAX_SECONDS_AHEAD) return { error: "bad_expires_at", message: "expires_at is too far ahead for a ring." };
  const message = {
    tokenField: "voip_token",
    topic: `${bundleId}.voip`,
    pushType: "voip",
    priority: 10,
    expiration: body.expires_at,
    payload: { kind: "ring", ring_id: body.ring_id, expires_at: body.expires_at, caller: cleanLabel(body.who, "Kairos") },
  };
  return { message };
}

export const ACTIVITY_EVENTS = ["start", "update", "end"];

export function buildActivity(body, bundleId, nowSeconds) {
  if (!ACTIVITY_EVENTS.includes(body.event)) return { error: "bad_event", message: "event must be start, update or end." };
  if (typeof body.push_token !== "string" || !/^[0-9a-fA-F]{32,512}$/.test(body.push_token)) return { error: "bad_push_token", message: "push_token must be the activity's hex token." };
  const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
  if (body.content_state !== undefined && !isObj(body.content_state)) return { error: "bad_content_state", message: "content_state must be an object." };
  const aps = { timestamp: nowSeconds, event: body.event };
  aps["content-state"] = body.content_state ?? {};
  if (body.event === "start") {
    if (typeof body.activity_type !== "string" || !/^[A-Za-z0-9_]{1,80}$/.test(body.activity_type)) return { error: "bad_activity_type", message: "start needs activity_type, the Swift attributes type name." };
    if (!isObj(body.attributes)) return { error: "bad_attributes", message: "start needs an attributes object." };
    aps["attributes-type"] = body.activity_type;
    aps.attributes = body.attributes;
    aps.alert = { title: "Kairos", body: `${cleanLabel(body.who)} is working` };
  }
  if (Number.isInteger(body.stale_date)) aps["stale-date"] = body.stale_date;
  if (body.event === "end" && Number.isInteger(body.dismissal_date)) aps["dismissal-date"] = body.dismissal_date;
  const message = {
    tokenField: null,
    token: body.push_token,
    topic: `${bundleId}.push-type.liveactivity`,
    pushType: "liveactivity",
    priority: body.event === "update" && body.priority !== 10 ? 5 : 10,
    expiration: nowSeconds + (body.event === "update" ? 300 : 3600),
    payload: { aps },
  };
  return { message };
}

export function buildMessage(body, bundleId, nowSeconds) {
  switch (body.kind) {
    case "alert": return buildAlert(body, bundleId, nowSeconds);
    case "ring": return buildRing(body, bundleId, nowSeconds);
    case "activity": return buildActivity(body, bundleId, nowSeconds);
    default: return { error: "bad_kind", message: "kind must be alert, ring or activity." };
  }
}

// ---- send ----

// Sends one message. Returns { status, reason, apnsId }. Retries once with a
// fresh provider token if Apple says the cached one expired.
export async function sendToApns({ env, fetchFn, nowSeconds, environment, token, message }) {
  const body = JSON.stringify(message.payload);
  if (utf8(body).length > 4096) return { status: 413, reason: "PayloadTooLarge" };
  const url = `${HOSTS[environment] ?? HOSTS.production}/3/device/${token}`;
  const attempt = async (force) => {
    const jwt = await providerToken(env, nowSeconds, force);
    const headers = {
      authorization: `bearer ${jwt}`,
      "apns-topic": message.topic,
      "apns-push-type": message.pushType,
      "apns-priority": String(message.priority),
      "apns-expiration": String(message.expiration),
      "content-type": "application/json",
    };
    if (message.collapseId) headers["apns-collapse-id"] = message.collapseId;
    const res = await fetchFn(url, { method: "POST", headers, body });
    let reason;
    if (res.status !== 200) {
      try { reason = (await res.json()).reason; } catch { reason = undefined; }
    }
    return { status: res.status, reason, apnsId: res.headers.get("apns-id") ?? undefined };
  };
  let out = await attempt(false);
  if (out.status === 403 && out.reason === "ExpiredProviderToken") out = await attempt(true);
  return out;
}
