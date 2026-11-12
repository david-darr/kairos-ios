# Desktop area coverage

Checklist: the feature inventory, sections 3 (Forge), 4 (Browse), the Cookbook and model setup parts of 2.7, and the contained computer parts of the chats section. One line per feature: where it lives on the phone, or why it is not there. Everything runs on sample data until the desktop connection fills the stores (`ForgeStore`, `BrowseStore`, the Computer, Local models and PC files stores, each behind a small protocol).

Screens are in `KairosAgents/Features/Desktop/`. Debug names (`-kDebugView desktop.<name>`) are listed in `Tools/screens/desktop.txt`.

## Desktop tab root (`DesktopView.swift`)

- PC status (name, online, version, last seen): the glass card at the top.
- Wake the PC: "Wake your PC" on the card when it is asleep, with a waking state (`desktop.home-asleep`).
- Working, waiting for you and apps running counts: the three numbers on the card.
- Running apps: the "Running apps" cards, each opens its Preview.
- Forge sessions with change counts and "Waiting for you": the "Forge sessions" card; New opens Forge Home with the task box focused.
- The areas: the "On this PC" grid (Forge, Computer, Browse, Local models, Files on this PC, Projects). Forge, Local models, Files and Projects open in a full-screen workspace with a zoom from the tile; Computer and Browse push on the tab.

## Forge Home (`ForgeHomeScreen.swift`, `ForgeCharts.swift`)

- Forge introduction: "What should your agents work on?" over the task box.
- Appearance-aware banner: not drawn; the screen uses the app's ground and glow in both looks instead.
- Customize dashboard: the slider button in the header (one tap, not hidden in a disclosure), a sheet of five switches (`desktop.forge-customize`).
- Saved widget visibility: saved on this phone (`ForgeStore.widgets`).
- Loading, preference error and home error states: not shown on sample data; the real store will show them as `NoteLine`s.
- Task input: the "Describe the task..." box; the gold arrow starts it.
- Project picker: the project chip (menu) and the Session context sheet.
- Agent picker, model override picker, effort at launch: the model chip opens the Model sheet (agent, model, effort), visible without expanding anything.
- Execution location picker, explanation, existing branch picker with "already checked out" disabled: the Session context sheet (`desktop.new-session`).
- Mode picker (Build or Plan): the mode chip on the task box and the Session context sheet.
- Start session: the gold arrow; opens the new session with the task as its first message.
- Composer keyboard controls: the phone keyboard's return adds a line; the arrow starts.
- Compose focus: "New" on the Desktop tab and "New session" in a session focus the task box.
- Add project shortcut and add model shortcut: "All projects" and the Projects screen's +; Local models from the Desktop grid.
- Disabled start, disabled picker and starting states: the arrow is disabled for a blank task; "Starting..." while it starts.
- Branch loading and branch error states: not shown on sample data.
- Model catalog fallback and agent loading failure states: not shown on sample data.
- Session error state: not shown on sample data.
- First-commit warning, make first commit and retry, clear outdated recovery, busy and error states: start a task in recipe-notes; the warning card with "Make the first commit" appears, editing the task dismisses it.
- Working now: the "Working now" card with Waiting for you and Working labels; rows open the session; empty state "Ready to build" with New session.
- Live updates and periodic refresh: the store is observable; the real store will refresh it.
- Running services: the "Running services" card with port, title, command and Preview; empty "No apps running."
- Git activity: totals, a commits-by-day chart you touch and slide along to read each day, with lines added and removed (`desktop.chart`), date range under it, working-session count.
- Recent projects: the card; rows open the project page; "All projects" opens Projects.
- Repo lifespan: repository picker, commits and repo age tiles, and a row into the full Repo lifespan screen.
- Repo lifespan screen (`desktop.repo`): statistics with 30-day deltas, first and latest dates, commits over time (touch to read), languages donut with a tappable legend, commit rhythm heatmap you tap to read (fixes the hover-only gap), most changed files, contributors.
- No-project, loading, no-commits, unavailable and error states of the lifespan: not shown on sample data.
- Chart accessibility: the bars are an adjustable element (swipe up or down to step through days) with a summary label; the heatmap and donut have summary labels.

## Projects (`ForgeProjectsScreen.swift`)

- Project list with initial marks, path, busy dot, change totals, App running: the Projects screen (`desktop.projects`).
- Open project: tap a row (project page).
- Add project menu (Open folder, Clone repo, New repo): + in the header opens the Add project sheet with a switch (`desktop.add-project`).
- Existing-folder form: name, folder path, Browse folders with Parent folder, Recent chat workspaces, required-field error, "Adding project..." state.
- Clone and New project forms: name, address with examples, "New folder under C:/Projects", "Cloning repository..." state.
- Project context menu (Open on Home, Copy path, Remove from list with a confirm that keeps the files): the "..." button on every row and a long press (fixes the right-click-only gap and the rail dependency).
- Empty state "Open a folder to begin": shown when the list is empty, with Add project.
- Truncated folder list, root loading and root error states: not shown on sample data.

## Project page (`ForgeProjectScreen`)

- Sessions list with search, Today and Earlier, Working now filter: the project page (`desktop.project`).
- Session identity and status (title, agent, branch or In place, mode, line totals, state with relative time): `ForgeSessionRow`.
- Session ordering by status, then recent: `ForgeStore.sessions(in:)`.
- Rename and Delete: the "..." on each row and a long press; Delete confirms.
- Running apps strip: glass chips under the filters, each opens Preview (fixes "running apps not visible inside a project").
- New session: + in the header opens Forge Home with this project and the task box focused.
- Empty and no-results states: "No sessions" and "No matching sessions".
- Removed-worktree state: ended sessions leave the list; an ended session opened directly is read only.

## A session (`ForgeSessionScreen.swift`)

- Session identity: header title and project with branch; the actions sheet shows project, agent and model.
- Build or Plan: a switch in the composer, always visible (fixes phone gap 3); disabled while the agent works.
- Mode explanation and plan note: the actions sheet, and a line above the composer in Plan.
- In-place warning: a note at the top of an in-place session.
- Model picker: the model chip in the composer, always visible, opens the Model sheet (agent fixed, model and effort change) (`desktop.model`).
- Permission mode (Supervised or Full access): a chip in the composer, always visible; Full access needs a swipe up (`desktop.full-access`). Fixes phone gap 1.
- Message input "Ask, build, or describe a change", send, empty and read-only disabled states: the composer.
- Message queue: while the agent works, the send button queues; queued messages show in the transcript and run next.
- Stop: the stop button beside send while it works.
- Workspace context: the folder path and branch under the text box.
- Conversation log, expand long prompts (Show more, Show less): the transcript.
- Automatic following and Jump to latest: the transcript stays at the bottom; a "Latest" pill appears when you scroll up.
- Expandable work history with duration and read, edit and command counts: the work card per turn.
- Tool steps, command output, failed steps: rows inside the work card (`desktop.session-working` shows a failed step).
- Inline edit diffs: file cards with counts and up to six lines; tap opens the full diff.
- Working, stopping and stopped states: pulsing dot and "Working 41s", "Stopped".
- Reduced motion: the pulsing dots stop when Reduce Motion is on.
- Background task strip: the "Running the test suite" pill above the composer, opens Computer to watch.
- Background follow-up: turns marked "After background work".
- Inline permission prompt with Allow and Deny (Deny in red), submitting state: the "Needs you" card in the turn (`desktop.session`).
- Per-turn review (files and lines, Review, Undo with a confirm, Keep): the review card under a finished turn; hidden while working, after Keep, or for read-only sessions.
- Session header controls (Run app or Preview, Terminal, REA, End session): the "..." actions sheet with three big tiles and rows (`desktop.session-actions`); the Changes count is a button in the header. Fixes phone gap 4 as far as one tap.
- Running apps visible inside a session: chips under the header, every running app with its port (fixes phone gap 9).
- End session: the actions sheet; Merge back and remove (swipe up), Keep branch, Discard (swipe up when there are changes), Keep and leave; changes warning and in-place notice; returns to where you came from (`desktop.end`).
- REA toggle: a switch in the actions sheet.
- Surface tabs, pin, close, split panes, drag tabs, resize, preview or terminal beside the conversation: not on the phone by design; each surface (Changes, Explorer, a file, Terminal, Preview) is its own pushed screen with swipe back.
- History error, inline diff fallback ("Binary file"): binary files show "Binary file" in their card.

## Changes and diffs (`ForgeChangesScreen.swift`)

- Baseline changes list with M, A, D and U marks, paths and line totals: the Changes screen (`desktop.changes`).
- Changes totals: header count button in the session; totals at the top of Changes.
- Refresh changes: the refresh button and pull to refresh.
- Open full diff: tap a file.
- Unified diff with hunks, old and new line numbers and markers: the diff screen (`desktop.diff`), lines scroll sideways.
- Revert file: a button on each Changes row and in the diff header, with a confirm that names the scope.
- Revert hunk: "Revert hunk" on each hunk, 44 point target, with a confirm.
- Empty, no-session, binary and revert-disabled states: all shown in text.
- Moved-hunk state: not shown on sample data.

## Git (`ForgeGitSheet`)

- Branch status (branch, ahead, behind, upstream or "No upstream"): top of the Git sheet (`desktop.git`).
- Staged and unstaged files with Stage and Unstage per file, Stage all and Unstage all in the section headers; tapping a file opens its diff.
- Commit message and Commit ("Commit 3" or "Commit all 4"), disabled with no message or no changes.
- Push or Publish, Pull with the behind count.
- Merge back: in plain view, with a swipe up to confirm (fixes phone gap 8).
- Switch branch and Create branch.
- Busy, success and running states: buttons wait, "Committed" and the other results show in green; a note while the agent works.

## Explorer and files (`ForgeFilesScreens.swift`)

- File tree with folders, indentation and changed-file styling: the Explorer screen (`desktop.explorer`).
- Workspace root and session-aware browsing: the header shows the project path; a note says worktree or project folder.
- Expand folders, Collapse all, Refresh Explorer, loading state: all in the Explorer.
- Open files: tap a file (the phone has no temporary tabs, each file is its own screen).
- Read-only viewer with line numbers: the file screen (`desktop.file`).
- Editable session files, Save, Saved and Unsaved states, saving state, draft retention: Edit, then Save; unsaved edits come back when you reopen the file.
- Binary state "Binary file. Read only.": image files.
- Disk-conflict dialog (Overwrite or Reload): saving while the agent works.
- Language-aware colouring: keywords, strings, numbers and comments are coloured in the viewer (`CodeColour`); the editor is plain monospaced text.

## Terminal (`ForgeTerminalScreen`)

- Interactive terminal with typing and output: the Terminal screen (`desktop.terminal`).
- Key row: Esc, Tab (completes), Ctrl (sticky, then a letter: Ctrl C, Ctrl L), Ctrl C, the four arrows (up and down walk the history), Paste, Copy output. Fixes phone gap 2.
- Multiple terminals: + in the header, terminal chips with close.
- Copy and paste: the key row.
- Terminal links: a localhost link opens Preview.
- Closed state: "Terminal closed." after exit or closing the last one.
- Sizing, theme, output recovery and reconnecting: handled by the real connection; not shown on sample data.

## Run app and Preview (`ForgeRunScreens.swift`, `ForgeRunAppSheet`)

- Run-app dialog with command guidance, suggested commands, Save and run, disabled state: the Run app sheet (`desktop.run-app`).
- Action approval for the app: follows the session's permission mode; Restart notes it asks first.
- Preview of the running app: a drawn page standing in for the app (`desktop.preview`).
- App address with path entry and invalid-path guidance, Back and Forward with disabled ends, Reload: the address bar.
- Open in browser: opens Browse.
- Responsive widths (Desktop, Tablet, Phone): the switch under the address.
- Logs with Stop app and Restart: the Logs sheet (`desktop.preview-logs`).
- Starting and stopped states: "Starting app..." and "App stopped" with Run app.
- Native visibility handling and the web-client limitation notice: not needed on the phone.

## Phone-only entries from the desktop web app

- Phone Forge Home overview, New and Sessions pager, Workspace sheet, Projects sheet, Sessions list, session header, actions sheet, Git dock and Commit sheet, Session context sheet, sheet mechanics: replaced by the native screens above (Forge Home, project page, actions sheet, Git sheet, Session context sheet, system sheets with swipe down).
- "Explorer" and "Editor" duplicate (inventory duplicate 1): one "Explorer" only.
- "Changes" used for two panels (duplicate 2): "Changes" is the file list, "Git" is Git.

## Computer (`ComputerScreen.swift`, `ComputerFrame.swift`, `ComputerSheets.swift`)

- Live computer view with title, address and last action: the screen view drawn from sample frames (`desktop.computer`).
- Watch state ("Kairos has control") and Take over or Hand back: the bar under the screen.
- Mouse clicks mapped to 1280 by 800: tap when you have control; a ring marks the point (`desktop.computer-control`).
- Drag and scroll: drag and the scroll mode when you have control.
- Typing and keys: the keyboard button and a key row (Esc, Tab, Ctrl, Alt, Win, arrows, Enter, Backspace, Ctrl+C, Ctrl+V).
- Stop (keeps the last frame) and the Computer closed state (`desktop.computer` with start closed).
- Record and Stop recording, then the skill review: when you have control.
- Steps replay (Step N of M, Previous and Next, Before, After and Click, export, make a skill): the Steps sheet (`desktop.computer-steps`).
- Desktop hint and error toasts: in the status line.

## Local models, the Cookbook (`LocalModelsScreen.swift`, `LocalModelsSetup.swift`)

- Cookbook view, engine switch (Ollama, Built-in engine), setup guide button, search: the Local models screen (`desktop.models`, `desktop.models-engine`).
- Installed models with size and running, model count, running status card: the Installed section.
- Use in chat (Adding, then Added), Delete with a confirm, Start for the built-in engine: each row's menu.
- Unreachable, error and empty states: `desktop.models-empty` and the offline state.
- Curated catalog with Browse all, Pull or Download with dot progress, failure and retry: the Catalog section.
- Recommended local model with background download: in the setup guide.
- Setup guide "Choose how Kairos thinks" with the connection choices and their status: the setup sheet (`desktop.models-setup`). Signing in, installing Codex and entering an API key happen on the PC; the sheet says so.

## Files on this PC (`PCFilesScreen.swift`)

- Places and projects, folder drill-down, file rows with size and date, sort and search: `desktop.files`, `desktop.files-folder`.
- File preview for text and images, Open on PC, Send to phone (share), Ask Kairos about it, Copy path: `desktop.files-preview`.
- Writes and deletes happen on the PC; the screen says so.

## Browse (`BrowseScreen.swift`, `BrowseSheets.swift`, `BrowseModels.swift`)

- Browse on the phone at all (phone gap 1): the Browse screen drives the PC's Browse tabs (`desktop.browse`).
- Mode entry, stored mode, unsupported-client message, sidebar and rail, Back to Kairos: replaced by the Desktop tab tile and the back button.
- Personal profile, per-account profile, account switch, persistent sign-ins, hidden live tabs: on the PC; the phone shows the PC's tabs for the signed-in account.
- New tab, Home screen with Speed Dial, search box, tiles, tile menu (open, rename, change address, refresh picture, remove) by long press and a visible menu, Add a site, Suggestions with Add, Customize home: the home page of a blank tab (`desktop.browse-home`) and its sheets.
- Tab list, switch, close, reopen closed, pin, mute, duplicate, new tab: the tabs sheet (`desktop.browse-tabs`).
- Address field, suggestions while typing, refused addresses, Back, Forward, Reload and Stop, Home: the bottom address bar.
- Find in page and zoom (25 to 500 percent, remembered per site): the page menu.
- Print, DevTools, fullscreen video, DRM, spellcheck: on the PC only; browser settings says so.
- Page errors, pop-up blocked notice, permission prompt strip, in-use strip with Stop, save-password offer, saved sign-in fill: strips above the page.
- Site info (secure or not, ads and trackers on or off here, the six permissions with Ask, Allow, Block, pop-ups, pin this site): the site sheet (`desktop.browse-site`).
- Screen-sharing picker and computer sound: on the PC only; the in-use strip shows when a site has the screen.
- Remembered site answers with Remove, search engine, sound output, ad blocking status: browser settings (`desktop.browse-settings`).
- Downloads with Pause, Resume, Cancel, Open on PC, Show in folder, Remove: the downloads sheet (`desktop.browse-downloads`).
- Saved passwords list without values, search, delete with a confirm, never-save list, let bots use saved passwords, bot uses: the passwords sheet (`desktop.browse-passwords`). Showing, copying, adding and importing passwords stay on the PC; the sheet says so.
- History with search, delete one, clear the last hour with a confirm: the history sheet (`desktop.browse-history`).
- Customize the browser look and Chameleon (blend with the open site): browser settings, "Look on your PC".
- Bot work list: a sheet from the page menu.
- Ask Kairos about the page and share the page (phone gap 12): the Ask sheet (`desktop.browse-ask`) and Share.
- Side pane and in-chat browser pane, bot browser profiles, Prepare post and page reads: owned by Home and chats, Bots and Make; not in this area.
