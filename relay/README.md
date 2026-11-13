# Kairos push relay

A very small web service that lets the Kairos desktop app send push notifications to the Kairos iPhone app.

## Why it exists

Apple's push service only accepts messages from the app's developer, using a private push key. That key must never sit on people's PCs. So Kairos desktop apps send a short request to this relay, and the relay, which holds the key, passes the push to Apple.

It is a Cloudflare Worker: plain JavaScript, no dependencies, no build step.

## What it stores, and what it never stores

Stored, per phone, under a random install id:

- the phone's push token (and its call token, if it has one)
- whether the phone is a sandbox or production build
- a one-way hash of the phone's secret (see "How the desktop proves itself")

Never stored: message text, bot replies, audio, call history, Live Activity tokens, or the phone's IP address. Rate-limit counters use a hash of the caller's address and expire within hours.

Never logged: tokens, secrets, signatures, request bodies or push payloads. The only log lines are short events such as `push`, with a kind and a status number. The tests check this.

Registrations are removed when Apple says a token is no longer valid (status 410), and when the desktop asks.

## What each push says

- **Alert:** who it is from as the title, and one fixed line for what kind: "Kip wants your approval", "Kip is waiting for your answer", "Your reply is ready", "Kip finished a task", "A task couldn't finish". These are the phone's own lines, word for word, and a test checks them against the app. The chat's title, when the desktop sends one, is the subtitle. The relay builds the line from a fixed list, so a caller cannot send a message's text. It also sets the notification category (`kairos.<notice>`, which gives the phone its Allow, Deny and Reply buttons), a thread id so one chat's notifications group, and passes on a `kairos-agents://` link and opaque ids so a tap opens the right chat or approval.
- **Old style alert:** a request with `what` and no `notice` still gets the original generic line ("Kip sent you a message", "Kip needs you", "Kip is waiting for your approval", "Kip finished a task") under the title "Kairos".
- **Call (ring):** a ring id, an expiry time and a short caller label. The relay refuses a ring that has already expired, so the phone is never woken for a call that is over.
- **Live Activity:** start, update, end, sent to that activity's own token with a small status object. Keep that object generic (a phase name, a percentage). Do not put message content in it.

## Routes

All bodies are JSON. Errors look like `{"error":"code","message":"plain sentence"}`.

| Route | Auth | Purpose |
|---|---|---|
| `GET /v1/health` | none | `{"ok":true}` |
| `POST /v1/installs` | none, 10 per hour per address | register a phone |
| `PUT /v1/installs/{id}` | signed | replace its tokens |
| `DELETE /v1/installs/{id}` | signed | remove the registration, `204` |
| `POST /v1/installs/{id}/push` | signed | send a push |

Register: `{"apns_token":"hex","voip_token":"hex or null","environment":"sandbox"|"production"}` returns `201 {"install_id":"...","secret":"..."}`. The secret is shown once.

Push bodies:

```json
{"kind":"alert","notice":"approval|question|replyReady|workDone|workFailed","who":"Kip","title":"optional chat title","link":"kairos-agents://chat/abc","request_id":"optional","thread_id":"optional","activity_id":"optional","activity_kind":"optional","collapse_id":"optional"}
{"kind":"alert","what":"message|needs_you|approval|done","who":"Kip","collapse_id":"optional"}
{"kind":"ring","ring_id":"abc","expires_at":1800000060,"who":"Kip"}
{"kind":"activity","event":"start","push_token":"hex","activity_type":"ChatRunAttributes","attributes":{},"content_state":{},"who":"Kip"}
{"kind":"activity","event":"update|end","push_token":"hex","content_state":{},"stale_date":0,"dismissal_date":0}
```

Alert fields with `notice`: `who` is cut to 40 characters and `title` to 80, each made one line (control characters, line breaks and direction overrides become spaces); a missing `who` reads "Kairos". `link` must be a `kairos-agents://` link of a known kind, `request_id` and `activity_id` up to 128 letters, digits and `_ . : -`, `thread_id` and `collapse_id` up to 64. A field that fails its check is dropped, not sent; an unknown `notice` is refused with `400`. `activity_id` goes out only with `activity_kind`. Without `thread_id`, a chat link groups by chat (`chat-<id>`), anything else by kind. Approvals and questions are time sensitive. Any other field (such as message text) is ignored.

Success is `200 {"ok":true,"apns_id":"..."}`. Other answers: `401` bad signature, `409` ring expired or no token of that kind, `410` token gone (and removed), `422` Apple rejected it, `429` slow down (see `retry-after`), `503` Apple busy.

## How the desktop proves itself

At registration the relay returns a random secret and keeps only its SHA-256 hash (lowercase hex). The desktop computes that same hash from its secret and uses the hex text as an HMAC-SHA256 key. Each signed request carries:

- `X-Kairos-Timestamp`: unix seconds
- `X-Kairos-Signature`: lowercase hex HMAC-SHA256 of `timestamp + "\n" + METHOD + "\n" + path + "\n" + sha256hex(raw body)`

Requests more than 2 minutes off the relay's clock are refused, so a captured request cannot be replayed later. Because the relay needs the hash to check signatures, someone who could read the storage could push to those phones (the fixed lines only, with a name and a title). Treat the KV namespace as private.

## Limits

Per phone: 30 pushes a minute, and 6 rings a minute. Per address: 10 registrations an hour. The counters live in KV, which is not instant across the world, so treat these as a brake on runaway loops, not an exact meter.

## Deploy

You need a Cloudflare account, Node 18 or newer, and the push key (`.p8`) from your Apple developer account. Run these from this `relay/` folder.

1. Create the storage: `npx wrangler kv namespace create INSTALLS`. Copy the id it prints into `wrangler.toml` (`REPLACE_WITH_KV_NAMESPACE_ID`).
2. In `wrangler.toml`, set `BUNDLE_ID` to the iPhone app's bundle identifier. Do not commit your real values to a public repository.
3. Set the three secrets. Each command asks you to paste the value:
   - `npx wrangler secret put APNS_KEY_P8` (paste the whole `.p8` file, including the BEGIN and END lines)
   - `npx wrangler secret put APNS_KEY_ID` (the key's 10 character id)
   - `npx wrangler secret put APNS_TEAM_ID` (your developer team id)
4. Deploy: `npx wrangler deploy`. Wrangler prints the relay's address. Put it in the desktop app's settings.
5. Check it: open `<address>/v1/health`. You should see `{"ok":true}`.

To test the code without deploying: `npm test` (Node 22, nothing to install).

## Cost at small scale

Apple's push service is free. Cloudflare's free Workers plan covers 100,000 requests a day, but free KV allows only 1,000 writes a day, and every registration and every push (rate-limit counter) writes. For a few testers that is fine. Past that, Workers Paid is about 5 US dollars a month and includes millions of writes. Check Cloudflare's current pricing before you rely on these numbers.

## Privacy note for the app

Kairos uses a small relay to deliver notifications. The relay and Apple can see that a notification or call was sent to your phone, and when. They do not see your messages, your audio, or what a bot said. Notifications name who and what kind ("Kip wants your approval") and the chat's title, nothing more. When the app's Private setting is on, the phone tells the desktop and the desktop leaves the chat's title out, so the relay never receives it. The relay keeps your phone's push token until you remove the phone in Kairos settings or Apple reports the token invalid. Push is opt-in.

## Not verified yet

This was written and tested against mocks. Nothing has been sent to Apple. Before relying on it, test on a real device: a sandbox alert, a ring that opens the call screen, and a Live Activity start, update and end.
