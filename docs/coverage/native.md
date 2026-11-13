# Native coverage

Notifications, calls (CallKit and PushKit), Live Activities and the Dynamic Island, and widgets.
Inventory: the brief's section 5 catalogue. Every design is drawn by the same SwiftUI view in the widget
extension and in the app's gallery (`-kDebugView native.<name>`, list in `Tools/screens/native.txt`).

## The catalogue, row by row

| Function | Notification | Live Activity and Dynamic Island | Widget |
|---|---|---|---|
| Bot rings or calls you | VoIP push reported to CallKit: native incoming-call screen with Answer and Decline (`CallCenter.reportRing`). Missed call: `missedCall` with Call back | `call` kind: face, name, timer, Mute and End on the Lock Screen, compact (face, timer), minimal, expanded (Mute, End). Gallery `activity-call`, `activity-ends` (muted). In-app: `CallView` and the minimize pill (`call`, `call-pill`) | Quick actions: Call Kip |
| Bot needs you (approval, question) | `approval`: "Kip wants your approval", Approve, Deny, Reply inline. `question`: "Scout is waiting for your answer", Reply inline, Open. Time sensitive, communication style (the bot's face) | A running reply shows "Waiting for you" and the hand in the island (`activity-ends`) | Needs you: small, medium, circular, rectangular, inline |
| Reply ready (long turn) | `replyReady`: "Your reply is ready", Open | `reply` kind: step, title, where it saves, sub-agent chips, Open chat and Stop; Done and Couldn't finish with Retry (`activity-reply`) | |
| Background task, routine run | `workDone` (Open), `workFailed` (Open, Try again) | `task` kind: progress ring, bar, Stop; Done, Couldn't finish (`activity-task`) | Running work: small, medium, large, circular, rectangular |
| Bot team cycle | `teamUpdate`: one update from Producer per cycle, never per post | `team` kind: Research, Script, Render, Post track, stage count in the island (`activity-team`) | Team status: small, medium, rectangular |
| Post published, TikTok tap | `posted`: "Posted to YouTube (Private)"; `needsTap`: "1 TikTok post needs your tap" | `render` kind: Render and Upload track with percent (`activity-render`) | Latest post: small, medium, rectangular |
| Platform warning | `channelWarning`: "A channel is paused", time sensitive | | |
| Spend near or at the cap, unknown | `spendNear`, `spendCap` (time sensitive), `spendUnknown`, each with the reason | | Spend this month: small, circular, rectangular, inline |
| Calendar and morning brief | `event` (time sensitive, Remind me in 10 minutes), `morningBrief` (passive) | | Next event: small, rectangular, inline |
| Forge session waiting | `forgeWaiting`: "Session waiting for you" | `forge` kind: Build and Test track (`activity-forge`) | Desktop and sessions: small, medium, rectangular |
| Model usage | `usage`: "Claude is near its limit" (passive) | | Usage per provider: small, medium, circular, rectangular |
| Quick actions | | | Ask Kip, Call Kip, open a pinned tab: small, medium, circular, rectangular |

Every notification, Live Activity and widget opens a `NativeLink` (`kairos-agents://chat/<id>`, `bot/<id>`,
`approval/<request>?bot=<id>`, `ring/<id>?bot=<id>`, `call/<bot>`, `ask/<bot>`, `area/<area>`, `tab/<title>`, `home`, `desktop`).

## Privacy

Three levels in Notifications settings (`native.settings`): Who and what kind (default: the bot and the kind of
event, plus the chat's title), Private (titles hidden too, on notifications, Live Activities and widgets; gallery
`activity-private`), Show a preview (opt-in: one line of the message). Widgets carry counts and titles, never
messages, and can be turned off. Lock Screen previews fall back to "Kairos" when iOS hides previews.

## Push payload (what the desktop and the relay send)

- Alerts: `aps.alert` with title = who it is from (the bot's or model's name, else "Kairos"), subtitle = the chat's
  title when sent, body = the kind's fixed line (`approval` "Kip wants your approval", `question` "Kip is waiting for
  your answer", `replyReady` "Your reply is ready", `workDone` "Kip finished a task", `workFailed` "Kip couldn't
  finish"); `aps.category` = `kairos.<kind>`, `aps.interruption-level` (time sensitive for approval and question),
  `thread-id` (`bot-<id>` or `chat-<id>`), and custom keys `link` (a `kairos-agents://` URL: `approval/<request>?bot=<id>`
  for a bot's approval, `chat/<id>` for a chat), `request_id` (approvals: choices `once`, `reject`, or `reply` with
  text), `activity_id`, `activity_kind`, `kind`. Never message text. The relay builds this from the desktop's fields
  (`relay/README.md`); an action without a `request_id` opens the link instead. Remote alerts are drawn by iOS, so the
  Private level cannot hide the subtitle on the phone, and the desktop does not know the level yet: titles show.
  The desktop sends "reply ready" only for a turn of 30 seconds or more, or one started from the phone.
- VoIP (topic `app.kairos-agents.mobile.voip`): `ring_id`, `agent_id`, `bot_name`, `expires_at` (seconds), optional
  `kind: bot_call_end`. Only for a real ring. Repeats of one ring map to one call id.
- Ring ended elsewhere: a background push `{"kind": "bot_call_end", "ring_id", "outcome"}` (not VoIP).
- Live Activity updates: ActivityKit pushes to each activity's token (sent with `PushBridge.registerActivity`),
  content-state matching `KairosActivityAttributes.ContentState`. A push-to-start token is sent as activity id `push-to-start`.

## What the shell and the connection must wire (not in Native's files)

- `KairosAgentsApp`: `@UIApplicationDelegateAdaptor(NativeAppDelegate.self) var native` (PushKit must start at launch).
- `ShellView`: `.nativeLinks()` just above `.environment(router)` (deep links, the call cover, the call pill, settings).
- `project.yml` (app-only build): the Info.plist keys in `project-widgets.yml` (background modes, usage strings,
  URL scheme, `NSSupportsLiveActivities`); without them TestFlight builds cannot ring or open links.
- You: a row that opens `NotificationSettingsScreen()`; Onboarding: show `NotificationAskCard()` after pairing.
- Connection: fill `PushBridge`, `NativeBridge.stop` and `.retry` (`/api/chat/live/stop`, a retry route),
  `CallAudioBridge` (`/api/agent-calls` audio), call `WidgetSync.publish(_:)` with real numbers and
  `LiveActivities.shared.begin/update/finish` from the live event stream.

## What is verified

- Compile (project-widgets.yml, app plus extension) is green; a one-off `#warning` in `KairosWidgets/` proved the
  extension target itself compiles. The app-only build (project.yml) compiles and runs in the Build workflow.
- Every gallery picture in `Tools/screens/native.txt` was looked at in Night, and the widgets and settings in Light.
- The app-only build has no microphone string or Live Activity key, so `CallCenter` and `LiveActivities` check
  Info.plist before asking (asking for the microphone without the string ends the app; it did in the first run).

## Cannot be proven without a signed build on a real phone

- The real Lock Screen, Dynamic Island and Home Screen rendering (the gallery draws the same views, but iOS frames,
  sizes, vibrancy and stale handling only show on a device).
- VoIP pushes, the CallKit incoming-call screen on a locked phone, audio session hand-over, Bluetooth and speaker routes.
- Notification actions from the Lock Screen (Approve needs Face ID), inline reply, time-sensitive delivery,
  communication-style avatars (needs the Communication Notifications capability in the signed profile).
- App Group sharing between the app and the extension, push tokens, Live Activity push updates.
- Bot-sent remote notifications showing the bot's face: needs a Notification Service Extension (a new App ID);
  today only notifications the app posts itself get the face.
