import test from "node:test";
import assert from "node:assert/strict";
import { handle, LIMITS } from "../src/index.js";
import { signRequest, verifierFromSecret, SIGNATURE_WINDOW_SECONDS } from "../src/auth.js";
import { resetTokenCache, TOKEN_REFRESH_SECONDS } from "../src/apns.js";
import { b64url } from "../src/util.js";

// ---------- harness ----------

const APNS_TOKEN = "a1".repeat(32);
const VOIP_TOKEN = "b2".repeat(32);
const ACTIVITY_TOKEN = "c3".repeat(40);
const T0 = 1_800_000_000; // fixed clock, unix seconds

function makeKv() {
  const map = new Map();
  return {
    map,
    async get(k) { return map.has(k) ? map.get(k) : null; },
    async put(k, v) { map.set(k, v); },
    async delete(k) { map.delete(k); },
  };
}

async function makeEnv() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin).match(/.{1,64}/g).join("\n")}\n-----END PRIVATE KEY-----\n`;
  return {
    env: { INSTALLS: makeKv(), APNS_KEY_P8: pem, APNS_KEY_ID: "KEYID12345", APNS_TEAM_ID: "TEAMID1234", BUNDLE_ID: "com.example.kairos" },
    publicKey: pair.publicKey,
  };
}

function makeWorld(opts = {}) {
  const world = { clock: T0, calls: [], apnsStatus: 200, apnsReason: undefined, statuses: [] };
  world.deps = {
    now: () => world.clock * 1000,
    fetch: async (url, init) => {
      world.calls.push({ url, init });
      const status = world.statuses.length ? world.statuses.shift() : world.apnsStatus;
      const reason = status === 200 ? undefined : (opts.reason ?? world.apnsReason);
      return new Response(status === 200 ? "" : JSON.stringify({ reason }), { status, headers: { "apns-id": "apns-id-1" } });
    },
  };
  return world;
}

const call = (world, env, method, path, bodyObj, headers = {}) =>
  handle(new Request(`https://relay.test${path}`, { method, body: bodyObj === undefined ? undefined : typeof bodyObj === "string" ? bodyObj : JSON.stringify(bodyObj), headers }), env, world.deps);

async function register(world, env, extra = {}) {
  const res = await call(world, env, "POST", "/v1/installs", { apns_token: APNS_TOKEN, voip_token: VOIP_TOKEN, environment: "sandbox", ...extra }, { "cf-connecting-ip": "203.0.113.5" });
  assert.equal(res.status, 201);
  const { install_id, secret } = await res.json();
  return { id: install_id, secret, verifier: await verifierFromSecret(secret) };
}

async function signed(world, env, inst, method, bodyObj, { path, timestamp, sigOverride } = {}) {
  const p = path ?? `/v1/installs/${inst.id}${method === "POST" ? "/push" : ""}`;
  const body = bodyObj === undefined ? "" : JSON.stringify(bodyObj);
  const ts = String(timestamp ?? world.clock);
  const sig = sigOverride ?? await signRequest(inst.verifier, { timestamp: ts, method, path: p, body });
  return call(world, env, method, p, body === "" ? undefined : body, { "x-kairos-timestamp": ts, "x-kairos-signature": sig });
}

const push = (world, env, inst, body, opts) => signed(world, env, inst, "POST", body, opts);
const jwtParts = (auth) => auth.replace("bearer ", "").split(".");
const decode = (s) => JSON.parse(Buffer.from(s, "base64url").toString());

test.beforeEach(() => resetTokenCache());

// ---------- registration ----------

test("register returns an install id and secret; KV holds tokens and a hash, never the secret", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  assert.match(inst.id, /^[A-Za-z0-9_-]{22}$/);
  assert.match(inst.secret, /^[A-Za-z0-9_-]{43}$/);
  const stored = env.INSTALLS.map.get(`install:${inst.id}`);
  const rec = JSON.parse(stored);
  assert.deepEqual(Object.keys(rec).sort(), ["apns_token", "environment", "v", "verifier", "voip_token"]);
  assert.equal(rec.apns_token, APNS_TOKEN);
  assert.equal(rec.verifier, inst.verifier);
  assert.ok(!stored.includes(inst.secret), "plain secret must not be stored");
});

test("register rejects bad input", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  for (const bad of [
    { apns_token: "nothex", environment: "sandbox" },
    { apns_token: APNS_TOKEN, voip_token: "zz", environment: "sandbox" },
    { apns_token: APNS_TOKEN, environment: "staging" },
  ]) {
    const res = await call(world, env, "POST", "/v1/installs", bad);
    assert.equal(res.status, 400);
  }
  assert.equal((await call(world, env, "POST", "/v1/installs", "not json")).status, 400);
  assert.equal([...env.INSTALLS.map.keys()].filter((k) => k.startsWith("install:")).length, 0);
});

test("register is rate limited per IP, and the IP is not stored raw", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const body = { apns_token: APNS_TOKEN, environment: "sandbox" };
  for (let i = 0; i < LIMITS.registerPerIpPerHour; i++) {
    assert.equal((await call(world, env, "POST", "/v1/installs", body, { "cf-connecting-ip": "203.0.113.9" })).status, 201);
  }
  const res = await call(world, env, "POST", "/v1/installs", body, { "cf-connecting-ip": "203.0.113.9" });
  assert.equal(res.status, 429);
  assert.ok(Number(res.headers.get("retry-after")) >= 1);
  assert.equal((await call(world, env, "POST", "/v1/installs", body, { "cf-connecting-ip": "203.0.113.10" })).status, 201);
  assert.ok(![...env.INSTALLS.map.keys()].some((k) => k.includes("203.0.113")));
});

// ---------- HMAC and replay window ----------

test("a correctly signed push is accepted", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const res = await push(world, env, inst, { kind: "alert", what: "needs_you", who: "Kip" });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, apns_id: "apns-id-1" });
});

test("bad, missing, tampered and wrong-install signatures are all 401 and send nothing", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const other = await register(world, env);
  const body = { kind: "alert", what: "message", who: "Kip" };
  const results = [];
  results.push(await push(world, env, inst, body, { sigOverride: "00".repeat(32) }));
  results.push(await push(world, env, inst, body, { sigOverride: "xyz" }));
  results.push(await call(world, env, "POST", `/v1/installs/${inst.id}/push`, body)); // no headers
  results.push(await push(world, env, { ...inst, verifier: other.verifier }, body)); // someone else's key
  // signed for a different body
  const ts = String(world.clock);
  const sig = await signRequest(inst.verifier, { timestamp: ts, method: "POST", path: `/v1/installs/${inst.id}/push`, body: JSON.stringify({ ...body, who: "Other" }) });
  results.push(await call(world, env, "POST", `/v1/installs/${inst.id}/push`, body, { "x-kairos-timestamp": ts, "x-kairos-signature": sig }));
  // signature made for another install's path
  const sig2 = await signRequest(inst.verifier, { timestamp: ts, method: "POST", path: `/v1/installs/${other.id}/push`, body: JSON.stringify(body) });
  results.push(await call(world, env, "POST", `/v1/installs/${inst.id}/push`, body, { "x-kairos-timestamp": ts, "x-kairos-signature": sig2 }));
  // unknown install id
  results.push(await push(world, env, { id: "A".repeat(22), verifier: inst.verifier }, body));
  for (const r of results) assert.equal(r.status, 401);
  assert.equal(world.calls.length, 0);
});

test("replay window: old and far-future timestamps are refused, edge of the window is fine", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const body = { kind: "alert", what: "done" };
  assert.equal((await push(world, env, inst, body, { timestamp: T0 - SIGNATURE_WINDOW_SECONDS - 1 })).status, 401);
  assert.equal((await push(world, env, inst, body, { timestamp: T0 + SIGNATURE_WINDOW_SECONDS + 1 })).status, 401);
  assert.equal((await push(world, env, inst, body, { timestamp: T0 - SIGNATURE_WINDOW_SECONDS })).status, 200);
  // a captured request replayed after the window no longer works
  const ts = String(T0);
  const raw = JSON.stringify(body);
  const sig = await signRequest(inst.verifier, { timestamp: ts, method: "POST", path: `/v1/installs/${inst.id}/push`, body: raw });
  world.clock = T0 + SIGNATURE_WINDOW_SECONDS + 5;
  const replay = await call(world, env, "POST", `/v1/installs/${inst.id}/push`, raw, { "x-kairos-timestamp": ts, "x-kairos-signature": sig });
  assert.equal(replay.status, 401);
});

// ---------- delete and replace ----------

test("delete removes the registration; pushing after is 401", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  assert.equal((await signed(world, env, inst, "DELETE")).status, 204);
  assert.equal(env.INSTALLS.map.has(`install:${inst.id}`), false);
  assert.equal((await push(world, env, inst, { kind: "alert", what: "message" })).status, 401);
});

test("delete needs a valid signature", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  assert.equal((await signed(world, env, inst, "DELETE", undefined, { sigOverride: "11".repeat(32) })).status, 401);
  assert.ok(env.INSTALLS.map.has(`install:${inst.id}`));
});

test("PUT replaces the tokens", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const newTok = "d4".repeat(32);
  const res = await signed(world, env, inst, "PUT", { apns_token: newTok, voip_token: null, environment: "production" }, { path: `/v1/installs/${inst.id}` });
  assert.equal(res.status, 204);
  const rec = JSON.parse(env.INSTALLS.map.get(`install:${inst.id}`));
  assert.equal(rec.apns_token, newTok);
  assert.equal(rec.voip_token, null);
  assert.equal(rec.environment, "production");
  assert.equal(rec.verifier, inst.verifier);
});

// ---------- push kinds ----------

test("alert: topic, type, priority, expiry, generic text only", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const res = await push(world, env, inst, { kind: "alert", what: "message", who: "Kip", text: "SECRET MESSAGE BODY", body: "SECRET2", collapse_id: "chat-1" });
  assert.equal(res.status, 200);
  const { url, init } = world.calls[0];
  assert.equal(url, `https://api.sandbox.push.apple.com/3/device/${APNS_TOKEN}`);
  assert.equal(init.method, "POST");
  assert.equal(init.headers["apns-topic"], "com.example.kairos");
  assert.equal(init.headers["apns-push-type"], "alert");
  assert.equal(init.headers["apns-priority"], "10");
  assert.equal(init.headers["apns-expiration"], String(T0 + 3600));
  assert.equal(init.headers["apns-collapse-id"], "chat-1");
  const payload = JSON.parse(init.body);
  assert.deepEqual(payload, { aps: { alert: { title: "Kairos", body: "Kip sent you a message" }, sound: "default" }, kind: "message" });
  assert.ok(!init.body.includes("SECRET"));
});

test("alert: unknown 'what' is refused, label is cleaned", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  assert.equal((await push(world, env, inst, { kind: "alert", what: "custom text here" })).status, 400);
  assert.equal(world.calls.length, 0);
  await push(world, env, inst, { kind: "alert", what: "needs_you", who: "Kip\n\u0000" + "x".repeat(100) });
  const text = JSON.parse(world.calls[0].init.body).aps.alert.body;
  assert.ok(text.startsWith("Kip x") && !/[\n\u0000]/.test(text));
  assert.ok(text.length <= 40 + " needs you".length);
});

test("alert with notice: who, kind line, chat title, category, thread, custom keys, never message text", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const res = await push(world, env, inst, {
    kind: "alert", what: "approval", notice: "approval", who: "Kip", title: "Plan the launch",
    link: "kairos-agents://approval/perm_1?bot=kip", request_id: "perm_1", thread_id: "bot-kip",
    collapse_id: "kairos-run1", text: "SECRET MESSAGE BODY", preview: "SECRET2",
  });
  assert.equal(res.status, 200);
  const { init } = world.calls[0];
  assert.equal(init.headers["apns-collapse-id"], "kairos-run1");
  assert.deepEqual(JSON.parse(init.body), {
    aps: {
      alert: { title: "Kip", subtitle: "Plan the launch", body: "Kip wants your approval" },
      sound: "default", category: "kairos.approval", "thread-id": "bot-kip", "interruption-level": "time-sensitive",
    },
    kind: "approval", link: "kairos-agents://approval/perm_1?bot=kip", request_id: "perm_1",
  });
  assert.ok(!init.body.includes("SECRET"));
});

test("alert with notice: each kind's line, thread from the chat link, retry ids", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const lines = { approval: "Ada wants your approval", question: "Ada is waiting for your answer", replyReady: "Your reply is ready",
    workDone: "Ada finished a task", workFailed: "A task couldn't finish" };
  for (const [notice, line] of Object.entries(lines)) {
    assert.equal((await push(world, env, inst, { kind: "alert", notice, who: "Ada", link: "kairos-agents://chat/abc123" })).status, 200);
    const payload = JSON.parse(world.calls.at(-1).init.body);
    assert.equal(payload.aps.alert.body, line);
    assert.equal(payload.aps.alert.title, "Ada");
    assert.equal(payload.aps.alert.subtitle, undefined);
    assert.equal(payload.aps.category, `kairos.${notice}`);
    assert.equal(payload.aps["thread-id"], "chat-abc123");
    assert.equal(payload.kind, notice);
    assert.equal(payload.link, "kairos-agents://chat/abc123");
  }
  await push(world, env, inst, { kind: "alert", notice: "workFailed", activity_id: "run_9", activity_kind: "reply" });
  const failed = JSON.parse(world.calls.at(-1).init.body);
  assert.equal(failed.activity_id, "run_9");
  assert.equal(failed.activity_kind, "reply");
  assert.equal(failed.aps.alert.title, "Kairos");
  assert.equal(failed.aps["thread-id"], "workFailed");
  assert.equal(failed.aps["interruption-level"], "active");
});

test("alert with notice: unknown notice is refused; bad fields are cleaned or dropped", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  assert.equal((await push(world, env, inst, { kind: "alert", notice: "Free text" })).status, 400);
  assert.equal((await push(world, env, inst, { kind: "alert", notice: "message" })).status, 400);
  assert.equal(world.calls.length, 0);
  const res = await push(world, env, inst, {
    kind: "alert", notice: "question", who: "Kip‮\n\u0000", title: "Line one\nline two\u0007" + "y".repeat(200),
    link: "https://evil.example/x", request_id: "bad id with spaces", thread_id: "x".repeat(65), activity_id: "run_1",
  });
  assert.equal(res.status, 200);
  const payload = JSON.parse(world.calls[0].init.body);
  assert.equal(payload.aps.alert.title, "Kip");
  assert.ok(payload.aps.alert.subtitle.startsWith("Line one line two y"));
  assert.equal(Array.from(payload.aps.alert.subtitle).length, 80);
  assert.ok(!/[\u0000-\u001f‮]/.test(JSON.stringify(payload.aps.alert)));
  assert.equal(payload.link, undefined);
  assert.equal(payload.request_id, undefined);
  assert.equal(payload.activity_id, undefined); // only with its activity_kind
  assert.equal(payload.aps["thread-id"], "question");
  assert.equal(payload.aps["interruption-level"], "time-sensitive");
});

test("ring: voip topic, push type, priority, expiry equals the ring's expiry", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const res = await push(world, env, inst, { kind: "ring", ring_id: "ring_abc-1", expires_at: T0 + 55, who: "Kip" });
  assert.equal(res.status, 200);
  const { url, init } = world.calls[0];
  assert.equal(url, `https://api.sandbox.push.apple.com/3/device/${VOIP_TOKEN}`);
  assert.equal(init.headers["apns-topic"], "com.example.kairos.voip");
  assert.equal(init.headers["apns-push-type"], "voip");
  assert.equal(init.headers["apns-priority"], "10");
  assert.equal(init.headers["apns-expiration"], String(T0 + 55));
  assert.deepEqual(JSON.parse(init.body), { kind: "ring", ring_id: "ring_abc-1", expires_at: T0 + 55, caller: "Kip" });
});

test("ring: an expired or nearly expired ring sends nothing; missing voip token is 409", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  for (const exp of [T0 - 10, T0, T0 + 2]) {
    const res = await push(world, env, inst, { kind: "ring", ring_id: "r1", expires_at: exp });
    assert.equal(res.status, 409);
    assert.equal((await res.json()).error, "ring_expired");
  }
  assert.equal((await push(world, env, inst, { kind: "ring", ring_id: "r1", expires_at: T0 + 100000 })).status, 400);
  assert.equal((await push(world, env, inst, { kind: "ring", ring_id: "bad id!", expires_at: T0 + 30 })).status, 400);
  assert.equal(world.calls.length, 0);
  const noVoip = await register(world, env, { voip_token: null });
  const res = await push(world, env, noVoip, { kind: "ring", ring_id: "r2", expires_at: T0 + 30 });
  assert.equal(res.status, 409);
  assert.equal((await res.json()).error, "no_token");
  assert.equal(world.calls.length, 0);
});

test("ring: capped per minute", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  for (let i = 0; i < LIMITS.ringPerInstallPerMinute; i++) {
    assert.equal((await push(world, env, inst, { kind: "ring", ring_id: `r${i}`, expires_at: T0 + 50 })).status, 200);
  }
  assert.equal((await push(world, env, inst, { kind: "ring", ring_id: "rx", expires_at: T0 + 50 })).status, 429);
});

test("live activity: start, update, end go to the activity's own token with the right headers", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const base = { kind: "activity", push_token: ACTIVITY_TOKEN };
  assert.equal((await push(world, env, inst, { ...base, event: "start", activity_type: "ChatRunAttributes", attributes: { runId: "run_abc" }, content_state: { phase: "thinking" }, who: "Kip" })).status, 200);
  assert.equal((await push(world, env, inst, { ...base, event: "update", content_state: { phase: "writing" } })).status, 200);
  assert.equal((await push(world, env, inst, { ...base, event: "end", content_state: { phase: "done" }, dismissal_date: T0 + 30 })).status, 200);
  const [start, update, end] = world.calls;
  for (const c of world.calls) {
    assert.equal(c.url, `https://api.sandbox.push.apple.com/3/device/${ACTIVITY_TOKEN}`);
    assert.equal(c.init.headers["apns-topic"], "com.example.kairos.push-type.liveactivity");
    assert.equal(c.init.headers["apns-push-type"], "liveactivity");
  }
  assert.equal(start.init.headers["apns-priority"], "10");
  assert.equal(update.init.headers["apns-priority"], "5");
  assert.equal(end.init.headers["apns-priority"], "10");
  assert.deepEqual(JSON.parse(start.init.body).aps, {
    timestamp: T0, event: "start", "content-state": { phase: "thinking" }, "attributes-type": "ChatRunAttributes", attributes: { runId: "run_abc" }, alert: { title: "Kairos", body: "Kip is working" },
  });
  assert.deepEqual(JSON.parse(update.init.body).aps, { timestamp: T0, event: "update", "content-state": { phase: "writing" } });
  assert.deepEqual(JSON.parse(end.init.body).aps, { timestamp: T0, event: "end", "content-state": { phase: "done" }, "dismissal-date": T0 + 30 });
  // the activity token is not stored
  assert.ok(![...env.INSTALLS.map.values()].some((v) => v.includes(ACTIVITY_TOKEN)));
});

test("live activity: bad input refused", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  for (const bad of [
    { kind: "activity", event: "update", push_token: "nothex" },
    { kind: "activity", event: "pause", push_token: ACTIVITY_TOKEN },
    { kind: "activity", event: "start", push_token: ACTIVITY_TOKEN },
    { kind: "activity", event: "update", push_token: ACTIVITY_TOKEN, content_state: [1] },
    { kind: "nope" },
  ]) assert.equal((await push(world, env, inst, bad)).status, 400);
  assert.equal(world.calls.length, 0);
});

test("production installs use the production host", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env, { environment: "production" });
  await push(world, env, inst, { kind: "alert", what: "done" });
  assert.equal(world.calls[0].url, `https://api.push.apple.com/3/device/${APNS_TOKEN}`);
});

test("oversize payload is refused before Apple is called", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const res = await push(world, env, inst, { kind: "activity", event: "update", push_token: ACTIVITY_TOKEN, content_state: { blob: "x".repeat(5000) } });
  assert.equal(res.status, 413);
  assert.equal(world.calls.length, 0);
});

// ---------- provider token ----------

test("provider token: ES256 JWT with kid, iss, iat and a valid signature", async () => {
  const world = makeWorld();
  const { env, publicKey } = await makeEnv();
  const inst = await register(world, env);
  await push(world, env, inst, { kind: "alert", what: "done" });
  const auth = world.calls[0].init.headers.authorization;
  assert.ok(auth.startsWith("bearer "));
  const [h, c, s] = jwtParts(auth);
  assert.deepEqual(decode(h), { alg: "ES256", kid: "KEYID12345" });
  assert.deepEqual(decode(c), { iss: "TEAMID1234", iat: T0 });
  const sig = Buffer.from(s, "base64url");
  assert.equal(sig.length, 64);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, sig, new TextEncoder().encode(`${h}.${c}`));
  assert.ok(ok);
});

test("provider token: cached across pushes, refreshed after 40 minutes, never inside 20", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const send = async () => { world.clock += 0; await push(world, env, inst, { kind: "alert", what: "done" }); return world.calls.at(-1).init.headers.authorization; };
  const a = await send();
  world.clock = T0 + 10 * 60;
  const b = await send();
  world.clock = T0 + TOKEN_REFRESH_SECONDS - 1;
  const c = await send();
  assert.equal(a, b);
  assert.equal(a, c);
  world.clock = T0 + TOKEN_REFRESH_SECONDS;
  const d = await send();
  assert.notEqual(a, d);
  assert.equal(decode(jwtParts(d)[1]).iat, T0 + TOKEN_REFRESH_SECONDS);
});

test("provider token: concurrent pushes share one signing", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  await Promise.all([1, 2, 3].map(() => push(world, env, inst, { kind: "alert", what: "done" })));
  const tokens = new Set(world.calls.map((c) => c.init.headers.authorization));
  assert.equal(tokens.size, 1);
});

test("ExpiredProviderToken: one retry with a fresh token (when the old one is old enough)", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  await push(world, env, inst, { kind: "alert", what: "done" });
  world.clock = T0 + 30 * 60;
  world.statuses = [403, 200];
  world.apnsReason = "ExpiredProviderToken";
  const res = await push(world, env, inst, { kind: "alert", what: "done" });
  assert.equal(res.status, 200);
  const [, failed, retried] = world.calls;
  assert.notEqual(failed.init.headers.authorization, retried.init.headers.authorization);
});

// ---------- failure mapping and 410 cleanup ----------

test("410 on an alert removes the device token; the voip token stays", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  world.apnsStatus = 410; world.apnsReason = "Unregistered";
  const res = await push(world, env, inst, { kind: "alert", what: "message" });
  assert.equal(res.status, 410);
  assert.equal((await res.json()).error, "token_gone");
  const rec = JSON.parse(env.INSTALLS.map.get(`install:${inst.id}`));
  assert.equal(rec.apns_token, null);
  assert.equal(rec.voip_token, VOIP_TOKEN);
});

test("410 on the last remaining token deletes the whole registration", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env, { voip_token: null });
  world.apnsStatus = 410; world.apnsReason = "Unregistered";
  assert.equal((await push(world, env, inst, { kind: "alert", what: "message" })).status, 410);
  assert.equal(env.INSTALLS.map.has(`install:${inst.id}`), false);
});

test("410 on a ring removes the voip token", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  world.apnsStatus = 410; world.apnsReason = "Unregistered";
  assert.equal((await push(world, env, inst, { kind: "ring", ring_id: "r1", expires_at: T0 + 30 })).status, 410);
  const rec = JSON.parse(env.INSTALLS.map.get(`install:${inst.id}`));
  assert.equal(rec.voip_token, null);
  assert.equal(rec.apns_token, APNS_TOKEN);
});

test("410 on an activity token reports gone and changes nothing stored", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const before = env.INSTALLS.map.get(`install:${inst.id}`);
  world.apnsStatus = 410; world.apnsReason = "Unregistered";
  assert.equal((await push(world, env, inst, { kind: "activity", event: "update", push_token: ACTIVITY_TOKEN })).status, 410);
  assert.equal(env.INSTALLS.map.get(`install:${inst.id}`), before);
});

test("other Apple answers map to plain errors and keep the registration", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const cases = [[400, "BadDeviceToken", 422], [403, "InvalidProviderToken", 502], [429, "TooManyRequests", 503], [503, "ServiceUnavailable", 503]];
  for (const [apple, reason, ours] of cases) {
    world.apnsStatus = apple; world.apnsReason = reason;
    assert.equal((await push(world, env, inst, { kind: "alert", what: "done" })).status, ours);
  }
  assert.ok(env.INSTALLS.map.has(`install:${inst.id}`));
  world.deps.fetch = async () => { throw new Error("network"); };
  assert.equal((await push(world, env, inst, { kind: "alert", what: "done" })).status, 502);
});

// ---------- rate limit ----------

test("push is rate limited per install, resets next window, and other installs are unaffected", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  const inst = await register(world, env);
  const other = await register(world, env);
  for (let i = 0; i < LIMITS.pushPerInstallPerMinute; i++) {
    assert.equal((await push(world, env, inst, { kind: "alert", what: "done" })).status, 200);
  }
  const limited = await push(world, env, inst, { kind: "alert", what: "done" });
  assert.equal(limited.status, 429);
  assert.ok(Number(limited.headers.get("retry-after")) >= 1);
  assert.equal((await push(world, env, other, { kind: "alert", what: "done" })).status, 200);
  world.clock = T0 + 61;
  assert.equal((await push(world, env, inst, { kind: "alert", what: "done" })).status, 200);
});

// ---------- misc routes ----------

test("health, unknown routes, wrong methods, big bodies", async () => {
  const world = makeWorld();
  const { env } = await makeEnv();
  assert.equal((await call(world, env, "GET", "/v1/health")).status, 200);
  assert.equal((await call(world, env, "GET", "/nope")).status, 404);
  const inst = await register(world, env);
  assert.equal((await signed(world, env, inst, "PUT", {}, { path: `/v1/installs/${inst.id}/push` })).status, 405);
  assert.equal((await call(world, env, "POST", "/v1/installs", "x".repeat(LIMITS.maxBodyBytes + 1))).status, 413);
});

// ---------- logging ----------

test("nothing sensitive is ever logged", async () => {
  const logged = [];
  const orig = { log: console.log, info: console.info, warn: console.warn, error: console.error, debug: console.debug };
  for (const k of Object.keys(orig)) console[k] = (...a) => logged.push(a.map((x) => (typeof x === "string" ? x : JSON.stringify(x))).join(" "));
  const sensitive = [];
  try {
    const world = makeWorld();
    const { env } = await makeEnv();
    const inst = await register(world, env);
    sensitive.push(inst.secret, inst.verifier, inst.id, APNS_TOKEN, VOIP_TOKEN, ACTIVITY_TOKEN, "SECRET MESSAGE BODY", "Kip", "ring_zzz", env.APNS_KEY_P8, "TEAMID1234", "203.0.113.5", "com.example.kairos");
    await push(world, env, inst, { kind: "alert", what: "message", who: "Kip", text: "SECRET MESSAGE BODY" });
    await push(world, env, inst, { kind: "ring", ring_id: "ring_zzz", expires_at: T0 + 30, who: "Kip" });
    await push(world, env, inst, { kind: "activity", event: "update", push_token: ACTIVITY_TOKEN });
    await push(world, env, inst, { kind: "alert", what: "done" }, { sigOverride: "00".repeat(32) });
    world.apnsStatus = 410; world.apnsReason = "Unregistered";
    await push(world, env, inst, { kind: "alert", what: "message" });
    world.deps.fetch = async () => { throw new Error(`boom ${APNS_TOKEN}`); };
    await push(world, env, inst, { kind: "ring", ring_id: "ring_zzz", expires_at: T0 + 30 });
    await signed(world, env, inst, "DELETE");
  } finally {
    Object.assign(console, orig);
  }
  assert.ok(logged.length > 0, "relay should log short event lines");
  const all = logged.join("\n");
  for (const s of sensitive) assert.ok(!all.includes(s), `log leaked: ${s.slice(0, 8)}...`);
});
