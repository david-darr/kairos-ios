# Coverage: Library planner (Calendar, Mail, Tasks)

Checklist: the feature inventory, sections "Email" (2.2), "Calendar" (2.5), "Tasks" (2.6) and their phone gaps.
Files live in `KairosAgents/Features/Library/Planner/`. Everything runs on made-up sample data behind a small
provider protocol (`CalendarProviding`, `MailProviding`, `TasksProviding`) so the desktop connection can replace it.
Debug pictures: `Tools/screens/library-planner.txt` (names `calendar-*`, `mail-*`, `tasks-*`).

## Calendar (`LibraryCalendarSection.swift`, `Calendar/`)

| Inventory feature | Where it lives |
|---|---|
| Calendar overview and subtitle | Section top. View and day remembered for the session in `CalStore.shared` |
| Day / Week / Month switch | `CalModeBar`: Agenda, Day, Week, Month (Agenda is new for the phone) |
| Day view | `CalTimeline` for the selected day, no legend |
| Previous / Next period | Chevrons in `CalNavRow` ("Previous period", "Next period"), also in Your calendars |
| Today (period label button) | The period label is the button, labelled "Today", says "Tap for today" when away |
| Period label formats | Month and year; "Nov 10 - 16" (month name when the week crosses months); "Tue, Nov 11"; Agenda range |
| Month grid (Monday first, real week count, outside days empty) | `CalMonthGrid` |
| Day indicators (today, selected) | Ring for today, gold for selected |
| Event pills and "+N more" | Up to two dots per day then "+N" |
| Select a day | Tap a month cell; it becomes the New event default |
| Multi-day placement, exclusive all-day ends | Shows on each day with "Day N of M" |
| Phone day strip | `CalWeekStrip`, swipe sideways for the next or last week, VoiceOver actions |
| Automatic refresh (Day, Week) | `TimelineView` every 60 s |
| Remembered view state | `CalStore.shared` |
| Week legend | `CalLegend` under Week |
| Week headings, all-day row | On the strip and at the top of the timeline |
| Hourly timeline, 30 min default length | 54 pt hours from 7 AM with "Show early hours (N before 7 AM)" |
| Overlapping events | Side by side lanes |
| Open an event | Every block and card opens `CalDetailSheet` |
| Current-time line | Labelled "Current time" |
| Initial scroll to 8 AM | No inner scroll; the timeline starts at 7 AM instead |
| Selected-day panel with count heading | `CalDayPanel` ("No events", "One event" ... "N events") |
| Upcoming under the day (Month) | Next 7 days grouped from "Today" |
| Agenda card content | `CalCard`: source tag, time range or due time, repeat icon, calendar colour |
| Google calendar colours | Card stripe, legend, swatches |
| Complete or reopen | Checkbox on Kairos events, notes and tab items; completed ones go to Archive |
| Edit / Delete event | Card menu and detail sheet, for Kairos events and writable Google calendars |
| Completed state and fade | Animated move to Archive with a message |
| Empty selected day / empty upcoming | "Nothing on this day." / "Nothing coming up." with "Add an event" |
| Panel busy state | Not drawn: sample data loads at once. Needs the desktop connection |
| Your calendars button and sheet | List button in the nav row and a row on the page; `CalSourcesSheet` |
| Local source toggles | "On your computer": Kairos, Notes with due times, Workspace deadlines, with swatches |
| Google calendar visibility | One switch per calendar; Holidays is read-only |
| Manage connection | Switches Library to Files, where Google Drive lives |
| Default calendar note | "New events go to Personal · Google by default." |
| Connect another calendar | Says plainly to add calendar accounts on the computer running Kairos |
| Reconnect for Calendar access | Not drawn: a desktop-side sign-in state the phone cannot fix |
| Disconnected state | "Connect your calendar" |
| Non-admin state | Not drawn: the phone owner is the Kairos owner |
| Availability error, revert on failed save | Not drawn: needs the desktop connection to fail |
| New event button | Round + in the nav row. The gold tab-bar button is shell-owned (request in the report) |
| Event dialog title and buttons | "New event" / "Edit event", Add / Save, Cancel |
| Title, Calendar picker (locked when editing), All day, Starts / Ends, Location, Description | `CalEventSheet` |
| Grouped layout | Timing group and details group |
| Phone date and time pills, "Ends (exclusive)" | Native DatePicker pills |
| Time zone (phone gap: was free text) | A real picker of common zones |
| Recurring edit scope | "Apply changes to: This event / All events in this series" (no loading state on sample data) |
| Repeat controls | Does not repeat / Daily / Weekly / Monthly, every 1-365, ends Never / On a date / After N (1-10,000, default 10), monthly line, custom Google rule read-only, hidden for one occurrence |
| Validation | "Enter a title, start and end", "End must be after start" |
| Created / saved messages | "Event created", "Event saved" |
| Delete confirmation with scope | `CalDeleteSheet`: "Delete this event?", this or the whole series, "Deleting...", "Event deleted" |
| Archive (phone gap: two steps away) | In Your calendars and directly on the page; `CalArchiveSheet` with Reopen, newest first, "Nothing archived yet." |
| Phone gap: week squeezes seven columns | Replaced by the week strip plus one roomy day timeline |
| Phone gap: month pills not tappable | Every event is tappable in the day panel and timeline |

## Mail (`LibraryMailSection.swift`, `Mail/`)

The real tab is triage plus accounts, not an inbox; that is what is built.

| Inventory feature | Where it lives |
|---|---|
| Email view and Accounts button | Round button on the summary card and an "Email accounts" row; both open the Email accounts sheet |
| Connect an account | Form inside the accounts sheet: address, password (never stored), IMAP host and 993, SMTP host and 465; "Fill in email, password, and both host fields first"; clears all but ports; "Account added" |
| Account cards | Address and hosts, Test connection ("Testing...", "IMAP: OK · SMTP: OK" or the failure), Remove with confirm and "Account removed", "No accounts connected" with "Connect an account" |
| Sending accounts | Intro line, one row per address with "can send" / "needs permission to send"; "Add another provider" opens the form; "No sending accounts yet." |
| Allow sending / Add Google account (phone gap) | A phone cannot sign in to Google: one plain sentence says to do it on the computer running Kairos |
| Important today | Summary card: Kip, last-checked line, "Unread scanned" and "Important", "Refresh now" with "Reading your inbox..." then a summary message, stored error in red, both empty states with "Refresh now" |
| Item rows | Sender initial, subject or "(no subject)", sender, time, gold reason |
| Phone summary and Needs you list | Summary card, then "Needs a reply", then "Also important" |
| Drafting a reply that waits for approval | Message sheet: "Draft a reply", "Mark as handled". Draft sheet: Kip writes, editable reply, From (accounts that cannot send are disabled), To, Subject, "Swipe up to send", "Save as draft" marks the row "Draft waiting" |
| Page search "Search mail and accounts" | Search pill with "No matches for ..." |
| Workspace confirm, empty, stats | System confirm, `PlannerEmpty`, `PlannerStat` |

## Tasks (`LibraryTasksSection.swift`, `Tasks/`)

| Inventory feature | Where it lives |
|---|---|
| Tasks page heading and line | "Build with Kairos" row carries the line under the switch |
| Build with Kairos (Automation brief) | `TasksBriefSheet`: three required questions, "Model to build it", "Start the chat" |
| Page sections and order | Search, Build, Run history, Work board, Routines, Triggers, Automation library |
| Recorded runs activity grid | `TasksActivityCard`: Week / Month / Year, 24-column dots, "Runs this week", "X done · Y other outcomes", footnote |
| Triggers unavailable (non-admin) | Not drawn: the phone owner is the Kairos owner |
| Page search "Search tasks and cards" | Search pill filters cards, routines and the library, "No matches for ..." |
| Schedule a task form | `JobScheduleSheet`: Name, Prompt, Schedule kind with only the matching field, Model, Deliver to, Schedule |
| Inline refusals | Exact five messages, field marked, cleared on edit |
| Unsent draft kept | Kept in `TasksStore.shared` when name or prompt has text, cleared after scheduling |
| Phone "New task" button | Round + by Routines (and the empty state). Gold tab-bar button is shell-owned (request in the report) |
| Task identity and schedule summary, "· built-in" | `JobRow`, `JobSheet` title |
| Enabled first, "Turned off" heading | `JobListView` |
| Turn off / Turn on with messages, ended one-time schedule | `JobSheet` |
| Run now / Running... / Stop and result messages | `JobSheet` (ran, delivered, delivery will be retried, stopping) |
| Per-task Model and Deliver to, "(not set up)" | `JobSheet` menus |
| Share with this Kairos (plain schedules) | `JobSheet` |
| Share automation to the store | `JobSheet` "Share to the Tool Store" (non-built-in) |
| Delete task with confirm | `TasksConfirmSheet`, "Task deleted" |
| Live updates while running | Store updates the row and sheet when the sample run ends |
| Latest run summary, output, delivery notice | `JobSheet` "Last run" |
| Run history disclosure | `JobSheet` "Run history (N)" with `RunHistoryList` |
| Empty state | "No scheduled tasks" with Kip asleep and "Schedule a task" |
| Routines heading with See all | `JobListView`: first three, "See all N" / "Show less" |
| Routine row (phone gap: output hidden) | Each row shows next run, last run and the start of its output in the list |
| Automation library, delivery, Enable / Disable | `JobLibraryView` with the inventory messages; enabling adds a "· built-in" routine |
| Work board (phone gap: six side-scrolling columns) | `WorkBoardView`: column chips with counts, one column at a time, swipe sideways between columns |
| Add a card form | `WorkAddCardSheet`: Name, What to do, Model, Waits for, "Add to Ready" / "Add to Backlog", the three messages |
| Live board updates | Running sample cards finish into Review |
| Card meta line | Agent, model or "a removed model", waits for, attempt N of 3, from trigger |
| Result / Last error, open in Review and Blocked | `WorkCardView` |
| Card actions by column | Ready, Run now, Hold, Stop to Blocked, Approve, "What should change?" with Request changes, Retry, Reopen, Delete with confirm |
| Run history on a card | `WorkCardSheet` |
| Triggers introduction, Add a trigger | `TrigListView` |
| Waiting for you, Skip, Approve, next-step message | Approval cards; Approve uses `TrigApproveSheet` with "Swipe up to approve" |
| Trigger rows, badges, last event or "never", Runs straight away / Asks first, on/off switch, missing targets | `TrigListView` |
| Empty "No triggers yet" | `TrigListView` |
| Add a trigger (all fields, card or task states, approval notice, inline error) | `TrigAddSheet`, opens details with the fresh secret |
| Trigger details (address with Copy, one-time secret, GitHub and generic guidance, reachability, New secret, Delete, On, Run straight away with warning, Events, Field condition, wording, Save, Recent events with coloured pills, empty) | `TrigDetailSheet` |
| Approval / save error states | Not drawn: sample data does not fail. Needs the desktop connection |
| Run rows: outcome, time, duration formats, model, attempt, late, output or error, "(no output)", Show all N, "No runs yet." | `RunHistoryList` |
| Steps timeline and "No steps recorded" | `RunStepTimeline` |
| Delivery states and Send again | `RunHistoryList`: delivered, delivering, automatic retry, abandoned, interrupted (Send again), legacy failure |
| Run summary line, computer step screenshots | Summary in run rows; computer screenshots not drawn (sample runs have no computer steps) |
| Run task from the palette and Home | Search and Home are other areas |
| Swarm / Teams | Not here: teams belong to the Bots area |
