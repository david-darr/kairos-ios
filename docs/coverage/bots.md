# Bots area: inventory coverage

Inventory: Kairos Redesign, Feature Inventory, section 2 (Bots mode and Studio), lines 2720-5878.
Studio, Content, video and design items belong to Make and are not listed here.
Chat itself (composer, transcript, message actions, slash commands, attachments) and calls belong to Home and chats and Native; they are listed at the end with their owner.

All screens live in `KairosAgents/Features/Bots/` and run on the sample data in `BotsStore` / `BotsSample`.
Debug names are `bots.<name>`; the picture list is `Tools/screens/bots.txt`.

## Bot page (tap the face in a chat)

| Feature | Where |
|---|---|
| Bot panel, full screen, opens on Inbox or Settings | `BotPanelView(bot:tab:)` > `BotPanelRoot` (BotPanelView.swift) |
| Hero: face, name, job, model, approval, status, team link | `BotPanelRoot.hero` |
| Bot menu: pin, all bots, team, report, duplicate, archive | `BotPanelRoot.botMenu` |
| Panel pushed from All bots, with a Message button into the chat | `BotsRoute.botPage` |

## Inbox

| Feature | Where |
|---|---|
| Needs you: approval card with Allow, Reject, Reply, Allow once, Allow for this chat, Allow for the team | `NeedsCardView` / `ApprovalBody` (BotInbox.swift) |
| Covers line and detail rows on approvals | `ApprovalBody` |
| Settled texts (allowed once, for this chat, for the team, rejected, answered, skipped, replied) | `Settled`, `SettledLine` |
| Questions: big tap-to-answer choices, single and multi pick, "Something else", Skip, Back, Next, Send answers, "Answer every question first." | `QuestionBody` |
| Multi-question tabs that keep the active one in view (phone gap closed) | `QuestionBody.tabs` (ScrollViewReader) |
| Review card: Approve, Request changes | `ReviewBody` |
| Working: live rows with progress and Stop; failed rows with Try again | `WorkRow` |
| Done and Ready for review with Mark done, Show all | `DoneRow`, `BotInboxSection` |
| Notifications: filters All, Unread, Needs you, Problems; Mark all read; pin; mark unread; missed call calls back | `BotNotificationsScreen` |
| Activity: grouped by day, source, 30 day note | `BotActivityScreen` |
| Bot report: 7 or 30 days, totals, what it made, recent runs, approvals, errors and fixes, Refresh | `BotReportScreen` |
| Team report | `TeamReportScreen` (TeamScreens.swift) |
| Inspector (raw run events) | Covered by Activity and Report; a separate inspector is not built (desktop debugging tool) |
| Learned-skill request card | Skills page "Waiting for you" (BotSettingsKnowledge.swift) |
| Peer contact approval card | Not built: the desktop never mounts it |

## Settings

| Feature | Where |
|---|---|
| At a glance / Overview | `BotSettingsList.glance`, `OverviewSettings` |
| Model, connection, catalogue, effort, keep warm, fallbacks, "switch them too" | `ModelSettings` (BotSettings.swift) |
| Approval Ask, Edits, Auto, Full; lowering applies at once; raising confirmed on the phone (phone gap closed); Full needs a swipe up | `ApprovalSettings`, `RaiseLevelSheet`, `SwipeToConfirm` |
| This conversation vs the whole bot, Follow the bot again | `ApprovalSettings` |
| Messages outside the app, per-day allowance and meter | `ApprovalSettings` |
| Always allowed commands with Remove | `ApprovalSettings` |
| Voice, provider, speak replies, call mode, live voice, read typed replies, end idle call, tell me when it needs me | `VoiceSettings` |
| Where it reports (channels) | `DeliverySettings` |
| Limits: bot on, runs per day, daily meter, monthly spend cap | `LimitsSettings` |
| Standing instructions, introduction, reply style | `InstructionsSettings` |
| History with Undo | `HistorySettings` |
| Routines list, switches, last run, failed in a row, needs-you fix, Run now, Pause, Delete with Bring it back | `RoutinesScreen`, `RoutineRow` (RoutineScreens.swift) |
| Keep an eye on my day (Kip), morning brief time | `RoutinesScreen.watchCard` |
| Routine editor: repeat chips, more options, days, time, interval, only between hours, stop after, custom schedule presets, time zone, limit reset, instructions, run limit, if still going, post results to, start with Kairos, remember last report, read and draft only, show as a call, live sentence and next 3 times, validation | `RoutineEditorScreen` |
| 44 point repeat chips, weekday circles and time chips (phone gap closed) | `ChipPicker`, `dayCircles`, `TimeChip` |
| Webhook trigger: name, events, most at once, run straight away warning, Connect it step with Copy, Send a test, Replace address, recent calls | `TriggerEditorScreen` |
| App event trigger: app, event, summary filter, Send a test, Check now, arrivals | `TriggerEditorScreen` |
| Automation calendar: day view, week strip, month jump (phone gap closed), now line, limit reset marker, tap a block, tap an hour to add | `CalendarDayView`, `AutomationCalendarScreen` (AutomationCalendar.swift) |
| Automations (all bots): composer, Set it up yourself menu, bot filter, List / Calendar, groups, details sheet with trouble, next times, runs, Run now, Pause, Edit, Delete, limit warning with Move to after reset | `AutomationsScreen`, `AutomationDetailSheet` |
| Memory: on/off, capacity meter, search, notes by heading, add, remove, topics, keep tidy, learn from rooms, Tidy now | `MemorySettings` |
| About you with autosave states, learned facts with Remove | `AboutYouSettings` |
| Skills: waiting for review, on/off with full-text review, origins, every bot, import from a link, write a command with name rules, learning switches | `SkillsSettings`, `SkillReviewSheet`, `WriteSkillSheet`, `ImportSkillSheet` |
| Skill library: search, Every bot, This bot | `SkillLibrarySettings` |
| Access and grants: per app Off, Read only, Read and change with tool counts; tool servers; stay signed in; reach; ask before contacting; where it works | `AccessSettings` (BotSettingsReach.swift) |
| Connections: search, filter, states, connect, reconnect, test, disconnect, add a tool server (paste, name, remote or local) | `ConnectionsSettings`, `AddServerSheet` |
| Browser profiles: browser on, profile choice, shared profiles with rename and delete, create (60 chars, 20 max), saved logins with Sign out | `BrowserSettings` |
| Usage and plan: period, totals, daily runs, where it went, plan meters with Refresh, runs, links to report and limits | `UsageSettings` |
| Conversations and folders: list by folder, rename, pin, read/unread, move to folder, snooze, stop snoozing, copy link, make main, archive, delete (main kept), select mode with bulk archive/delete, new conversation, new folder, folder rename, move up/down, delete | `ConversationsSettings` |
| Look and name: name and job, live Mascot preview, 8 shapes, 6 colours, 5 accessories plus none, Shuffle, save; Kip locked | `BotLookScreen`, `MascotPicker` (BotLook.swift) |
| Team section (team, chief) | Settings row to `TeamScreen` |
| Who can see it | Not built: the open-source desktop has one account per computer, so there is nothing to choose |
| Price overrides, trace waterfall, housekeeping (trace days, size cap) | Not built: desktop admin tools; the report and usage pages show the numbers |
| Signed-in sites via the computer workbench, place chooser | Where it works is in Access; the live computer is Desktop's area (ComputerScreen) |
| Picture upload and "make a picture" avatars, expression select | Not built: the phone uses the Mascot look only; uploads would need the desktop image pipeline |

## Teams and rooms

| Feature | Where |
|---|---|
| Team page: faces, chief crown, status, Pause / Resume, rooms, routines, hand-offs, report, map, departments | `TeamScreen` (TeamScreens.swift) |
| Team options: Manage bots, Team instructions (byte count), Team memory (groups, add, delete), Team settings (preview then apply), Suggest models (cost line), Chief of Staff, Rename, Delete | `TeamSheetView` |
| Team map on the phone: one column of team cards, bot tiles with status and model, Pause per team, move a bot to another team with confirm (no drag on phone), Other bots, tags @everyone @team @bot, message box with receipts, Handoffs disclosure, New room, New team | `TeamMapScreen`, `NewTeamSheet`, `NewRoomSheet` |
| Departments: teams grouped, move a team, new department | `DepartmentsScreen` |
| Hand-offs and assignments: rows and chips with verb, status, done when | `HandoffRow`, `HandoffChip` |
| Room as a group chat: faces, bubbles, @mention suggestions, replies from mentioned or auto bot, working members with Stop and Stop all, queue with Cancel, held banner with Resume, pinned bar, find with N of M, export via share, reply/copy/pin | `RoomScreen` (RoomScreen.swift) |
| Room settings: name, who answers, turn limit, instructions; members (1 to 20, locked while working); room conversations | `RoomSettingsSheet` |
| Room call | Native area (`CallView`); not wired from rooms yet |

## Making bots

| Feature | Where |
|---|---|
| Make a bot: blank, every option, ready-made carousel, presets with delete, packages, archived, defaults, all bots | `BotMakerScreen` |
| Create flow, simple: name, job, look card with live face, colours, Shuffle, defaults note | `BotCreateSheet` (BotCreateFlow.swift) |
| Create flow, advanced: Identity, Soul (bytes), starting notes with headings and total, Model and effort, Routines (up to 10), Access with Full access swipe, Delivery | `BotCreateSheet.advancedPart` |
| Discard draft confirm, duplicate name check, routine validation | `BotCreateSheet` |
| Ready state with "What should this bot help with first?" A to E | `BotCreateSheet.ready` |
| Ready-made bots: categories, cards, try asking, suggested routines off | `ReadyMadeScreen` |
| New-bot defaults with Clear confirm | `DefaultsSheet` |
| Packages: Explore teams, preview with includes, teams, rooms, model per bot, cost line, Add; Import via the file picker; Share personas with toggles, preview, share | `PackagesScreen`, `PackagePreviewSheet` |
| Archived bots: restore, delete, restore all, delete all | `ArchivedBotsScreen` |
| Build a team from a folder (Scout) | Not built: needs a folder path on the desktop |
| Workspace backup and restore | Not built: unreachable on the desktop too |

## All bots

| Feature | Where |
|---|---|
| Search bots and conversations (2 characters, results, Nothing found) | `AllBotsScreen.results` |
| Pinned faces with needs-you counts | `AllBotsScreen.pinnedRow` |
| Needs attention, grouped by team, Other bots, chief crown | `AllBotsScreen.section` |
| Bot menu reachable on the phone: visible ··· button and long press (phone gap closed): Open, Inbox and settings, Pin, New conversation, New folder, Make or Remove chief, Duplicate, Save as preset, Archive with Undo, Delete | `AllBotsScreen.menuItems` |
| Reorder pins and bots with 44 point up and down buttons (phone gap closed) | `AllBotsScreen.reorderList` |
| New bot, ready-made, new room, team map, automations, departments, archived | header menu |
| Simple / Advanced interface switch, sidebar width and density | Not built: the phone has one layout |

## Owned by other areas

Composer, transcript, message tray, slash commands, drafts, attachments, data cards, widgets, bot apps, find and export in a chat: Home and chats. Calls, call pill, rings: Native. Computer and browser workbench: Desktop. Studio and Content: Make.

## Data

Everything runs on `BotsStore.shared` (sample). `BotsProviding` is the seam for the desktop routes (`/api/agents`, `/api/bot-attention`, `/api/bot-rooms`, `/api/bot-team`). Changes made here (a new look, a new bot) do not yet reach other areas, which read `SampleData`.
