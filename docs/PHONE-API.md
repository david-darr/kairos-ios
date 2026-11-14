# Phone API

What the phone app asks of the Kairos desktop. The desktop side is being built on a branch of the Kairos repo; this file is the contract both sides build to. If one side has to differ, say so in the report and change this file in the same change.

All paths are on the person's own desktop, over HTTPS. JSON in and out. Times are ISO 8601 in UTC.

## Pairing

A phone is paired once, with a code shown in the desktop app (Settings, Remote access, "Pair the iPhone app").

### `POST /api/phone/pair/start`

Signed-in desktop session only. Makes a code.

```json
{ "code": "482913", "expires_at": "2026-11-12T08:10:00Z", "address": "https://example-host:8422" }
```

- Six digits, valid 10 minutes, works once. Starting a new code cancels the old one for that account.
- `address` is the desktop's current remote address, or `null` when remote access is off.

### `POST /api/phone/pair/claim`

No session. The phone sends the code.

```json
{ "code": "482913", "device_name": "iPhone", "device_model": "iPhone17,1", "app_version": "0.1.0" }
```

Answers `200`:

```json
{
  "token": "kph_...",
  "device_id": "d_3f9c...",
  "account": { "username": "alex", "is_admin": true, "color": "teal" },
  "server": { "name": "Kairos", "version": "2.3.0" }
}
```

- `token` is shown once. The desktop keeps only a hash. The phone keeps it in the Keychain.
- Wrong or expired code: `400 {"detail": "That code is not right or has expired."}`.
- Too many tries (5 wrong codes from one address in 10 minutes, or 5 wrong tries against one code): `429 {"detail": "Too many tries. Make a new code on your desktop."}`, and the code is cancelled.

## Signing requests

Every later request carries `Authorization: Bearer kph_...`. The desktop treats it as that account, with the same rights as that account's browser session, on every `/api` route and on the live event stream. A revoked or unknown token gets `401`.

### `GET /api/phone/session`

Who am I, and is the token still good.

```json
{ "account": { "username": "alex", "is_admin": true, "color": "teal" }, "device_id": "d_3f9c...", "server": { "name": "Kairos", "version": "2.3.0" } }
```

### `GET /api/phone/devices`

The account's paired phones.

```json
{ "devices": [ { "id": "d_3f9c...", "name": "iPhone", "model": "iPhone17,1", "created_at": "...", "last_seen_at": "...", "current": true } ] }
```

### `DELETE /api/phone/devices/{id}`

Unpair a phone. `204`. Its token stops working at once, and its live streams close.

## Home at a glance

### `GET /api/phone/home`

One small read for the top of Home and for widgets.

```json
{
  "usage": [ { "provider": "Claude", "percent": 64, "resets_at": "..." } ],
  "next_event": { "title": "Report due", "starts_at": "...", "all_day": false },
  "needs_you": 2,
  "running": 1
}
```

`usage` may be empty, `next_event` may be `null`.

## Push

### `POST /api/phone/push/register`

```json
{ "apns_token": "hex", "voip_token": "hex or null", "environment": "sandbox", "locale": "en-US", "detail": "generic" }
```

`204`. One registration per device; sending again replaces it. `DELETE /api/phone/push/register` removes it.
`detail` is optional: the phone's notice level, `generic` or `hideTitles`. The phone sends the registration again
when the person changes it. With `hideTitles` the desktop leaves the chat's title out of every push; a missing or
unknown value (an older phone) counts as `generic`.

### `POST /api/phone/push/activity`

A Live Activity's own push token, so the desktop can update it while the app is closed.

```json
{ "activity_id": "run_abc", "kind": "chat_run", "push_token": "hex" }
```

`204`. The desktop sends pushes through the Kairos relay (`relay/` in this repo); it never holds the Apple key.

What each push must carry for the phone to act on it (notification kinds and their fields, the ring payload, Live Activity content) is written in `docs/coverage/native.md` under the push payload contract. The relay's own routes and signing are in `relay/README.md`.

## Rings

### `GET /api/rings/{ring_id}`

The state of one ring, so the phone can end a call screen for a ring that was answered elsewhere or ran out.

```json
{ "id": "...", "agent_id": "...", "bot_name": "Kip", "status": "ringing", "seconds_left": 41 }
```

`status` is one of `ringing`, `answered`, `declined`, `expired`.

## Everything else

Chats, bots, the inbox, approvals, files and settings use the desktop's existing routes unchanged (for example `/api/sessions`, `/api/chat/live`, `/api/chat/live/events`, `/api/agents`, `/api/bot-chat/...`, `/api/bot-attention/...`, `/api/permissions/...`). The app reads their shapes from the desktop's source.

## What a phone token is refused

A phone token is the account, with the same rights as its browser session, except on the routes the desktop keeps for itself. These answer a phone token with a refusal before the route runs:

- starting a pairing, the push relay, every `/api/auth/*` route except `status`, `/api/remote*`, `/api/system/backup*` and `/api/system/wipe*`;
- saved Browse passwords: `/api/browse/passwords*`;
- the Forge terminal: `/api/forge/sessions/{id}/terminals*`. `PUT /api/forge/terminal/settings` refuses `enabled: true` from a phone; a phone may still read the switch and turn it off.

Routes that answer only the desktop's own machine (loopback) never answer a phone either. On top of this the app itself holds back: it sends no key, password, token, sign-in or other change that widens access, and it acts on the real computer only where the screen says so.
