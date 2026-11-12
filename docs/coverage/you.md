# Coverage: You

The You area: the You sheet, every Settings panel, the Tool Store, added tabs, Search, the welcome and the tour.
Checklist: the feature inventory, section 5 (Settings, accounts and the phone shell), section 2.1 (the app shell), and the Tool Store parts of section 2.7. Everything runs on sample data.
Where a feature lives is written as Screen > group. "Desktop only" means a control that acts on the Windows desktop itself; it is left out or explained in one sentence, never drawn disabled.

## Settings window and navigation (5, 2.1)
- Grouped navigation: You (YouView) > General, Models and voice, Connections, Bots, Your data, Access, Administration
- Settings search: You > Search settings (titles and keywords; "No setting matches" state)
- Access-aware navigation: not on the phone yet: sample data is an admin; member hiding needs the account's role from the desktop
- Page headers and scope caption: every page is SettingsPage (title, one-line subtitle; admin pages say "Admin")
- Subpage navigation, phone Back, swipe back: NavigationStack inside the You sheet; back button and edge swipe
- Floating window, close, minimize, move, resize, keep reachable, minimized state: desktop only (window chrome)
- Keyboard-openable rows: not on the phone (no keyboard); every row is a 44 pt button with an accessibility label
- Shared presentation, switch feedback, disabled switches: YouKit (SettingsGroup, rows, StatusPill, NoteText); switches change at once
- No search matches: You > search shows "No setting matches"

## Models (2.2, 2.3, model setup guide)
- Setup guide "Help me set up a model": Models > Choose how Kairos thinks (ModelGuideScreen: the five choices, glossary, API key path works; sign-in steps say they finish on the desktop)
- Antigravity, Claude Code CLI, Codex CLI, Local, API connections: Add a model (AddModelScreen) per kind
- Provider presets, image capability, add model, required fields, add failed: Add a model
- Connection list, details, measured speed, Test, Test all, image switch, Remove with confirm: Models
- Long chats (85%), Model for helpers, helper limits, no automatic helper state: Models > Long chats, Helpers
- Share a connection, Shared with you: Models > Shared with (sheet), Shared with you
- States (no models, testing, OK ms, failed, small window, helper save): Models
- Machine-access gating and own-account wording: Choose how Kairos thinks (sample is an admin)

## Integrations and MCP catalog (2.4, 2.5)
- Add integration menu, API service, CalDAV, CardDAV, iCal, MCP server forms, cancel, validation, submitting: Integrations > + menu > AddIntegrationScreen(kind:)
- Email shortcut: Add integration (email) is an IMAP/SMTP form, since the desktop's Email tab jump has no phone equivalent
- Popular GitHub connection, search, filters, rows, connected and not connected states, empty and no-match: Integrations
- MCP sign-in (waiting, result), sign-out, Sync now, synced contacts, remove: IntegrationDetailScreen
- Browse and search the MCP catalog, docs, add, add and sign in, Added pill, pending, no matches, REA, model guidance: MCP catalog
- Also MCP tools in Bots: Connected apps (BotsSettings)
- Google accounts (Integrations and Google): Google (accounts, services, reconnect, disconnect, add another account)

## Channels (2.6, 2.7, 2.8)
- Unified list, live status, on/off switch, open settings, add a channel, platform categories, delivery note, loading, no channels, Discord and connector states: Channels
- Connector status, enable, send test, remove, webhook address with Copy, platform fields, kept secrets, allowed senders, anyone can message, chat model, save, setup guide, create, switched off, unknown kind, adding, add failed: Channel and Add a channel
- Telegram, WhatsApp and every other kind (Slack, Signal, iMessage, Matrix, Mattermost, IRC, Email, SMS, LINE, webhook, ntfy, Teams, Google Chat, Feishu, DingTalk, WeCom): Add a channel picker with each kind's fields
- Discord setup steps, add bot, allowed user, default model, remove, overrides (Normal, Open, Silent), add and remove override, Channel ID steps, delivery targets, voice channel, When a bot calls you, states: Discord bot

## Reach me (2.9)
- Pause or resume all bots, Message me order, Call me order, quiet hours, each bot, recent log, the honest note: Reach me

## Phone lines (2.10)
- Provider, keys, Phone on, numbers, public address and webhook paths, incoming call PIN, who answers, calls to other people, recent calls (Transcript), do-not-call list, save and remove, US texting note: Phone line

## Remote access (2.11) and paired phones
- Explanation, checklist, refresh, account login, address and port, turn on, HTTPS note, live, reconnecting, certificate expired, copy, turn off, states: Remote access
- Get Tailscale, allow through the firewall: desktop only (they install software and change the Windows firewall); the checklist says so
- Paired phones (phone API): Remote access > Paired phones (unpair with confirm, pair another phone)
- Your desktop connection: You > Your desktop links ConnectionScreen() (Home and chats team)

## Forge settings (2.12)
- Forge root folder: Forge (path shown; changed on the desktop)
- Allow the terminal over Remote Access: Forge > Terminal

## Vault (2.13)
- Current folder, the task-list sync note, Sync now, syncing, synced counts, already up to date, failed: Vault
- Choose folder: desktop only (a native folder picker); one sentence on the page

## Speech and voice (2.14)
- Voice choice (Kairos Voice, GPT-Live, ElevenLabs) with keys and checks: Voice > Voice
- Standard and HD voice, HD voices with Play: Voice > Voice quality (HD download is desktop only, said in one sentence)
- Pronunciations: Voice > Pronunciations
- Recognition models, Smart Turn, downloads and states: Voice > Listening
- Backup voice, Open Mic voice: Voice > Backup and Open Mic
- Microphone selection, reveal names, output device: the iPhone's own microphone and speaker are used; one sentence on the page
- Voice servers on this computer (Voicebox, another server), graphics-card runtime: desktop only
- Realtime on a free Gemini key: Voice > Realtime on a free Gemini key
- Bot call voice (live voice, read typed replies, idle minutes): Bot call voice

## Notifications (2.15)
- All phone notification settings (kinds, privacy levels, permission): the native layer's NotificationSettingsScreen on main. You > Notifications opens NotificationsRowDestination, a one-line slot the lead points at it when merging.
- Bots on this computer (desktop alerts), other enrollments, test notification: covered by the native screen; the desktop's own switches stay on the desktop

## Appearance (2.16, 2.17, 2.18, Kip)
- The look (Night, Light, Match iPhone): Appearance > The look (changes the app at once)
- Live preview: Appearance > preview card (style, colour, effect and Kip)
- Background style (Kairos, Color, Image, Flow, Liquid glass, Animated): Appearance > Background
- Base-colour presets and custom colour: Appearance > Base colour (swatches and ColorPicker with hex)
- Choose, replace, remove image, tint: Appearance > Your picture (photo library)
- Flow dials and Animate background: Appearance > Flow (sliders)
- Liquid glass wallpaper, Glass and Dither: Appearance > Wallpaper; See through to the desktop is desktop only (one sentence)
- Animated piece picker with search, look, panels, animate art, credit: Appearance > Art and How it plays
- Your own animation upload: not on the phone yet: the picture path covers stills; animation files need the desktop's storage rules
- Background effect, density, tint, animate: Appearance > Background effect
- Standard or Terminal chat style, Plain or Cards: Appearance > Chats (they set the desktop's chats; the phone uses bubbles)
- Kip style (Flat, Halftone, Pixel, Hidden): Appearance > Kip's style with live previews
- Halftone scenes, replace, reset: Appearance > Halftone scenes
- Scene focus point: not on the phone yet: replacing a scene is there; dragging the crop point is planned with real pictures
- Reset appearance: Appearance > Reset (confirm)
- App icon: Appearance > App icon (needs alternate icon assets in the build; until then it says the icon arrives later)
- The notch (all of 2.18 and the notch sections of 2.1): desktop only (a Windows overlay window); one sentence in Appearance
- Matching native title bar, coordinated colours, persistence: desktop only or automatic

## Layout (2.19 and the 2.1 layout lines)
- What sits on the tab bar: Layout > The tab bar preview and Shortcut on the bar (pins one area, same as dragging from Jump to)
- Home arrangement, visibility, tab cards, reset Home: Layout > Home
- Desktop pinned strip (up, down, unpin, pin a tab): Layout > Your desktop's pinned strip
- Sidebar groups, move buttons, visibility (Home locked), reset sidebar: Layout > Your desktop's sidebar
- Drag sidebar tabs: replaced by the up and down arrows on the phone
- Immediate saving, movement limits, hidden state: Layout

## Account (2.20, 2.32, 2.33, 2.1 profile and switcher)
- Identity, role, This computer: Account > Signed in; You header
- Change password, two-step setup, confirm, disable: Account > Password, Two-step sign-in
- Account colour: Account > Switching accounts (rings update live on the You sheet)
- Switching PIN set and remove: Account > Switching accounts
- Account switcher strip with colours: You > Accounts on this phone
- One-tap switch, switch with a PIN (tries left, wait): You > switcher > PIN sheet; Accounts on this device
- Account state marks (Open now, Sign in again, PIN, One tap) and PIN badge: You switcher and Accounts on this device
- Add another account (limit 9), sign in, two-step code: Sign in (SignInScreen)
- Forgot password and reset code: Sign in > Forgot password? > Enter your code
- Sign out of one, sign out of all: You > Sign out; Accounts on this device
- Signed-in accounts chooser: You switcher (the same list)
- End-the-call guard: not on the phone yet: call state belongs to the native call screen; switching during a call is a merge-time check
- Ctrl+Shift+1 to 9: desktop only; listed in Shortcuts
- Clean reload: switching updates the whole You sheet from the store; full data reload comes with the desktop connection
- First admin account, local-access lock screen: desktop only (first run of the desktop)
- Signed out mid-use: not on the phone yet: needs the connection's 401 handling (Home and chats team)

## Shortcuts (2.21, keyboard help)
- Shortcut reference, Quick Entry key, account switch key: Shortcuts (read-only, with the phone's equivalents)

## Administration (2.22 to 2.30)
- Computer use (all switches, keep steps, Docker, profiles, running computers): Computer use
- Agent tools (switches, extra tools, save): Agent tools
- Permissions (grants, revoke, recent decisions, paired terminals, states): Permissions
- Hooks list, pause all, switch, details by action, test event, edit, delete, recent runs, coverage note, states: Hooks and Hook
- Hook creation: name, event, examples, tools, agent and source scope, action and its fields, template, command, timeout, block on failure, command confirm, save, errors: Add a hook
- Users: people, This computer, reset password, role, delete, add user, states: Users
- System: diagnostics, back up (with secrets switch), restore and pending restore, restore history, export and import, wipe with two confirms: Backups and system
- Logs: file picker, level, area, time, chat filters, search, entries, follow, states: Logs
- Runs: outcome filter, list, steps, states: Runs
- Sandbox changes: change sets, diff, apply, discard, too large, limits: Sandbox changes
- File checkpoints: review, choose files, restore, guidance and states: File checkpoints

## Bots pages (2.31)
- Connected apps: Connected apps (apps with detail, accounts, alias, reconnect, disconnect; MCP servers with health, switch, test, edit, remove); local commands and "Look on this computer" are desktop only
- Keys, helper model, tidy time, memory wait, room capture: Keys
- Signed-in sites and 1Password: Signed-in sites
- About you and learned facts: About you (autosave)
- Skill library: Skill library (shares, search, tags, review, every bot, import, paste)
- Bot preferences (interface, width, font, switches, density, new bot defaults, concurrency, replay tour and welcome, check setup): Bot preferences; send key is a desktop keyboard setting
- Bot voice: Bot call voice
- Usage and spend, cap, per bot: Usage and spend
- Housekeeping: Housekeeping
- Templates (explore, import, share): Templates; From folder is desktop only
- Bot computers: Bot computers
- Image generation: Image generation

## Phone shell items owned here (2.35, 2.1)
- Settings on phone: the You sheet
- Phone Settings in three places (duplicate): one place, the You sheet (avatar on Home, Search > Open settings)
- More sheet, sidebar, drawers, pager, composer, Forge, activity: Shell, Home, Desktop and Native teams, not You
- Kip sheet on phone, Show Kip: Appearance > Kip's style

## Command palette (2.1) -> Search
- Open: Search button on each tab (shell); Search sheet (SearchView)
- Search commands, go to tabs and custom tabs, bots, open settings: Search > Areas, Added tabs, Bots, Settings
- Run task: Search > Actions > Run task: Morning brief (running and ran messages)
- Actions: new chat, new note, call any bot (opens the call screen), pause or resume the content team, new Forge session, open settings, take the tour, switch account
- Chats, files and notes: Search > Chats, Files, Notes
- No matches: "Nothing matches" with a hint
- Keyboard selection and key legend: Return runs the first hit; arrows are desktop only

## Onboarding (2.1 first-run wizard) and the welcome
- The welcome carousel: OnboardingFlow (kept)
- Permission moments: notifications, microphone, camera, each its own page with Allow and Not now (PermissionPage). The notifications step is WelcomeNotificationSlot, for the native NotificationAskCard at merge. Microphone and camera ask only when the build has their usage text (see the report).
- Model, vault, Discord, remote access steps: the phone connects to an already set-up desktop, so these live on the desktop's first run; on the phone they are Models, Vault, Channels and Remote access in You
- Finish: the welcome ends on Connect your desktop (ConnectView), then the tour starts the first time

## App tour (2.1)
- Start the tour: You > Help > Take the tour; Search > Take the tour; Bot preferences > Replay the tour; after the first welcome
- Tour stops: an overlay over the real app pointing at the tab bar, holding it for Jump to, the gold circle, a bot's face, Search and You (Tour.swift)
- Step controls: n of N, Back, Next, Done, End tour, tap to go on
- Ending and text version: You > Help lists every part in words
- Replay the welcome: You > Help

## Updates
- The desktop updates itself on quit; there is no remote update control. You > Help > About says so and shows both versions.

## Tool Store (2.7)
- Store overview, search, category filters, Added only, result count, section counts: Tool Store
- Manage skills, Add MCP server, Install a skill from GitHub, Build with Kairos, Build a tab, Install a tab, Refresh community: Tool Store > + menu
- Featured card, community update banner, Shared library, Design systems: Tool Store
- Loading, empty and no-match with Show all: Tool Store (loading arrives with the desktop data)
- Phone layout (sticky search, chips, + menu, dense rows with status pills, detail): Tool Store rows open StoreItemScreen
- Skill card, view skill, share with this Kairos, share to the store, unreadable skill: Store item (skill)
- Skill manager: create, import from Files with scan review, list, edit (in the item), delete, approve for models: Manage skills sheet and Store item
- GitHub skill installer with scan review: Install a skill from GitHub sheet
- Tool server cards, health, Check, held tools with Accept and Accept all, custom server dialog with validation, server sign-in: Store item (tool) and Add MCP server sheet
- Add-ons: install, enable, reinstall, remove, restart note: Store item (add-on)
- Creative tool and Roblox workspace cards: the Game studio add-on stands for them
- Tabs: groups, status pills, review files with SHA-256, approve, on and off, add and remove, export, share; install a tab (file or GitHub folder, replace switch, scan): Store item (tab), Install a tab sheet
- Tab builder brief: Build a tab (BuildTabScreen)
- Community catalog: install with scan review, update, turn back on, revoked, remove: Store item (community)
- REA setup: Store item (REA) > Review and add (download approval sheet)
- GitHub account and submissions (device code, copy, waiting, signed in, submissions, sign out, signed-out text): Tool Store > Sharing to the store and the GitHub sheet
- Sharing and publishing (metadata, rules, preview files, MIT consent, open pull request, done, states): Share to the store sheet
- Design systems: looks, default, share, remove: Store item (design system); making a new style from photos is not on the phone yet: it reads files with the desktop's tools
- Model setup guide and builders: Models > Choose how Kairos thinks; Build with Kairos sheet

## Added tabs (2.1 custom destinations)
- Custom tab host: AddedTabScreen (native header and menu: reload, details, turn off, remove; the tab's own sample HTML in a web view, in both looks, no network)
- Add a tab: AddTabScreen (your tabs, prebuilt, build your own, install)
- Added tabs in Jump to: the shell's Jump to panel (shell team)
