import SwiftUI

// The paired desktop behind a Forge session's changes, diffs, Git sheet, files and app
// (Net/DeskChangesAPI.swift). Not paired, nothing here runs and the screens show their sample data from
// ForgeStore, exactly as before.
//
// These screens change real repositories on the person's real computer, so the phone does less:
// - Nothing is shown as done before the desktop says so. A change whose answer was lost is "could not
//   confirm": the desktop is read again and compared with what was SENT, and nothing is sent twice.
// - Reverts, commit, pull, push, merge, restart, stop and an overwrite each draw a confirm first.
// - A file that can hold secrets (`.env*`, keys, credentials...) is never opened or shown on the phone.
// - Creating or switching a branch, the terminal and the app's page are not on the phone at all.
// - The agent working in the session turns writes off (the desktop's own lock would only make them wait).

// MARK: - What the screens read

nonisolated struct DeskChangesReading: Sendable {
    var load: DeskForgeLoad = .idle
    var files: [DeskChangesFile] = []
    var skipped = 0
}

nonisolated struct DeskChangesGitState: Sendable {
    var load: DeskForgeLoad = .idle
    var git: DeskChangesGit?
}

nonisolated struct DeskChangesFolder: Sendable {
    var load: DeskForgeLoad = .idle
    var entries: [DeskChangesEntry] = []
}

/// A file as the desktop had it when the editor was filled: the text, its `hash` and its `mtime`.
nonisolated struct DeskChangesFileText: Hashable, Sendable {
    var content: String
    var hash: String
    var mtime: String

    init?(_ dto: DeskChangesFileTextDTO) {
        guard dto.binary != true, let content = dto.content, let hash = dto.hash, !hash.isEmpty,
              let mtime = dto.mtime, !mtime.isEmpty else { return nil }
        self.content = content
        self.hash = hash
        self.mtime = mtime
    }
}

/// One open file: what the editor was FILLED from, what the person typed since, and what the desktop has now.
nonisolated struct DeskChangesFileState: Sendable {
    var load: DeskForgeLoad = .idle
    var filled = ""
    var hash = ""
    var mtime = ""
    var binary = false
    /// The desktop sent no hash or mtime, so this file cannot be saved against anything.
    var canSave = true
    /// nil while the person has not changed the text.
    var draft: String?
    /// A newer version the desktop has, seen after the editor was filled (a 409, or a read).
    var newer: DeskChangesFileText?
    /// A save was sent and its answer never arrived: saving stays off until the desktop has been read again.
    var unsettled = false
    /// The text of that save, to compare with what the desktop has.
    var sent: String?
    var line: String?

    var shown: String { draft ?? filled }
    var dirty: Bool { draft != nil }

    mutating func adopt(_ text: DeskChangesFileText) {
        filled = text.content
        hash = text.hash
        mtime = text.mtime
        newer = nil
        canSave = true
    }
}

nonisolated struct DeskChangesAppState: Sendable {
    var load: DeskForgeLoad = .idle
    var app: DeskChangesAppDTO?
    var logs: [String] = []
    var logsLoad: DeskForgeLoad = .idle
}

/// What an approval was started against, to say how it ended when the stream closed without a result.
nonisolated struct DeskChangesBaseline: Sendable {
    var git: DeskChangesGit?
    var startedAt: Double?
}

/// An action the desktop asks to approve over its own stream: a push, a merge back, an app restart.
nonisolated struct DeskChangesApproval: Sendable {
    nonisolated enum Kind: Sendable { case push, merge, restart }
    var kind: Kind
    var phase: DeskForgeApproval.Phase
    var request: ChatPermissionDTO?
    var note: String?

    var active: Bool {
        if case .ended = phase { return false }
        return true
    }
}

/// Where a commit whose answer was lost stands. Commit takes no request id, so it is never sent twice.
nonisolated struct DeskChangesHold: Sendable {
    nonisolated enum Phase: Equatable, Sendable {
        case checking
        /// The branch's files or commits changed: the screen now shows what the desktop has.
        case changed
        /// The window ended without a change. `checked` is false when the last reads failed.
        case quiet(checked: Bool)
    }
    var phase: Phase
}

// MARK: - The store

@Observable
final class DeskChangesLive {
    static let shared = DeskChangesLive()

    /// The desktop and account everything below was read for. Nothing else is ever shown.
    private var account = "sample"
    private var changeMap: [String: DeskChangesReading] = [:]
    private var gitMap: [String: DeskChangesGitState] = [:]
    private var folderMap: [String: DeskChangesFolder] = [:]
    private var fileMap: [String: DeskChangesFileState] = [:]
    private var appMap: [String: DeskChangesAppState] = [:]
    private var goneMap: [String: String] = [:]
    private var staleMap: [String: String] = [:]
    private var noteMap: [String: String] = [:]
    private var busyKeys: Set<String> = []
    private var approvalMap: [String: DeskChangesApproval] = [:]
    private var holdMap: [String: DeskChangesHold] = [:]

    @ObservationIgnored private var reads: [String: Int] = [:]
    @ObservationIgnored private var writeSerial = 0
    @ObservationIgnored private var inFlight = 0
    @ObservationIgnored private var streams: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var watches: [String: Task<Void, Never>] = [:]

    private init() {}

    // MARK: Which desktop

    /// Paired (whether or not the desktop is answering right now): the screens show the desktop, never samples.
    var on: Bool { DeskForgeLive.shared.on }
    /// Forge answers an admin account only.
    var isAdmin: Bool { DeskForgeLive.shared.isAdmin }

    private static let desktopChanged = "Your paired desktop changed. Try again."
    static let goneLine = "This session is not on your desktop any more."
    static let endedLine = "This session has ended, so its changes and files are not on your desktop any more."

    private var current: Bool { on && account == DeskForgeLive.accountKey }

    private func stillLive(_ account: String) -> Bool {
        on && self.account == account && DeskForgeLive.accountKey == account
    }

    /// Before anything is read: drop whatever was read for another desktop, another account or sample mode.
    private func follow() {
        let key = DeskForgeLive.accountKey
        guard account != key else { return }
        for task in streams.values { task.cancel() }
        for task in watches.values { task.cancel() }
        streams = [:]
        watches = [:]
        account = key
        changeMap = [:]
        gitMap = [:]
        folderMap = [:]
        fileMap = [:]
        appMap = [:]
        goneMap = [:]
        staleMap = [:]
        noteMap = [:]
        busyKeys = []
        approvalMap = [:]
        holdMap = [:]
        reads = [:]
    }

    /// The account to read for, once the connection is ready, or nil when this is not a live admin phone.
    private func readyAccount() async -> String? {
        guard on, isAdmin else { return nil }
        follow()
        let account = self.account
        var waited = 0
        while Connection.shared.state == .connecting, waited < 80, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        return stillLive(account) ? account : nil
    }

    // MARK: What was read

    func changes(_ sid: String) -> DeskChangesReading? { current ? changeMap[sid] : nil }
    func git(_ sid: String) -> DeskChangesGitState? { current ? gitMap[sid] : nil }
    func folder(_ sid: String, _ path: String) -> DeskChangesFolder? { current ? folderMap[Self.pathKey(sid, path)] : nil }
    func file(_ sid: String, _ path: String) -> DeskChangesFileState? { current ? fileMap[Self.pathKey(sid, path)] : nil }
    func app(_ sid: String) -> DeskChangesAppState? { current ? appMap[sid] : nil }
    /// Set when the desktop has no such session, or it has ended: the screens show only this line.
    func gone(_ sid: String) -> String? { current ? goneMap[sid] : nil }
    /// Set when the last read of this session failed and what is shown may be out of date.
    func stale(_ sid: String) -> String? { current ? staleMap[sid] : nil }
    func note(_ sid: String) -> String? { current ? noteMap[sid] : nil }
    func clearNote(_ sid: String) { noteMap[sid] = nil }
    func isBusy(_ key: String) -> Bool { current && busyKeys.contains(key) }
    func approval(_ sid: String) -> DeskChangesApproval? { current ? approvalMap[sid] : nil }
    func hold(_ sid: String) -> DeskChangesHold? { current ? holdMap[sid] : nil }

    /// The agent is working in this session (read when a screen opens and before each change).
    func agentRunning(_ sid: String) -> Bool { DeskForgeLive.shared.isRunning(sid) }

    /// A Git change is on its way, a lost commit is being checked, or an approval is open: no other Git change starts.
    func gitLocked(_ sid: String) -> Bool {
        guard current else { return false }
        if busyKeys.contains("git:" + sid) || holdMap[sid]?.phase == .checking { return true }
        return approvalMap[sid]?.kind != .restart && approvalMap[sid]?.active == true
    }

    func clearHold(_ sid: String) {
        if let phase = holdMap[sid]?.phase, phase != .checking { holdMap[sid] = nil }
    }

    /// The one line about a commit whose answer was lost, or nil.
    func holdLine(_ sid: String) -> String? {
        switch hold(sid)?.phase {
        case .checking?:
            return "Your desktop did not confirm the commit, and this phone is checking. Commit stays off until it knows."
        case .changed?:
            return "Your desktop's files changed after the commit was sent. The lists below show what it has now."
        case .quiet(let checked)?:
            return checked
                ? "This phone did not see a commit appear. It may not have happened: look at your desktop's Git before you commit again."
                : "This phone could not read your desktop to check the commit. Look at your desktop's Git before you commit again."
        case nil:
            return nil
        }
    }

    static func pathKey(_ sid: String, _ path: String) -> String { sid + "|" + path }

    // MARK: Reading the desktop

    /// One read. It answers `.fresh` only when it is still the newest read of its kind, for the desktop it was
    /// sent to, and no change was on its way or finished meanwhile (then it is read again). A cancelled read is
    /// not an error: it changes nothing.
    private func read<Value: Sendable>(_ key: String, _ account: String,
                                       _ fetch: (APIClient) async throws -> Value) async -> DeskForgeRead<Value> {
        let serial = (reads[key] ?? 0) + 1
        reads[key] = serial
        for _ in 0..<3 {
            let writes = writeSerial
            do {
                guard let client = Connection.shared.client else { throw APIError.notPaired }
                let value = try await fetch(client)
                guard stillLive(account), reads[key] == serial else { return .stale }
                guard writes == writeSerial, inFlight == 0 else { continue }
                return .fresh(value)
            } catch {
                if error is CancellationError || Task.isCancelled { return .stale }
                Connection.shared.note(error)
                guard stillLive(account), reads[key] == serial else { return .stale }
                var missing = false
                if let api = error as? APIError, case .server(let status, _) = api, status == 404 { missing = true }
                return .failed(error.plainWords, missing: missing)
            }
        }
        // Every try overlapped a change on its way. A newer read of the same kind answers instead, if there is one;
        // otherwise the screen says so with Try again and never stays on "Reading".
        guard stillLive(account), reads[key] == serial else { return .stale }
        return .failed("Your desktop was busy with another change. Try again in a moment.", missing: false)
    }

    /// A failed read: remembers a session that is gone, and answers the state the screen should show.
    private func failure(_ sid: String, _ why: String, missing: Bool, loaded: Bool) -> DeskForgeLoad {
        if missing {
            goneMap[sid] = Self.goneLine
        } else if why.contains("has ended") {
            goneMap[sid] = Self.endedLine
        } else if loaded {
            staleMap[sid] = "Your desktop could not be read just now, so this may be out of date. " + why
        }
        return .failed(why)
    }

    private func readFresh(_ sid: String) {
        goneMap[sid] = nil
        staleMap[sid] = nil
    }

    /// Changes and the Diff screen: every changed file with its blocks.
    @discardableResult
    func loadChanges(_ sid: String) async -> Bool {
        guard let account = await readyAccount() else { return false }
        _ = await DeskForgeLive.shared.readRuns()
        return await refreshChanges(sid, account)
    }

    @discardableResult
    private func refreshChanges(_ sid: String, _ account: String) async -> Bool {
        let loaded = changeMap[sid]?.load == .loaded
        if !loaded { changeMap[sid, default: DeskChangesReading()].load = .loading }
        switch await read("changes:" + sid, account, { try await $0.deskChangesList(sid) }) {
        case .stale:
            return false
        case .failed(let why, let missing):
            let state = failure(sid, why, missing: missing, loaded: loaded)
            if !loaded { changeMap[sid, default: DeskChangesReading()].load = state }
            return false
        case .fresh(let dto):
            let mapped = DeskChangesWire.changes(dto)
            readFresh(sid)
            changeMap[sid] = DeskChangesReading(load: .loaded, files: mapped.files, skipped: mapped.skipped)
            return true
        }
    }

    /// The Git sheet's status.
    @discardableResult
    func loadGit(_ sid: String) async -> Bool {
        guard let account = await readyAccount() else { return false }
        _ = await DeskForgeLive.shared.readRuns()
        return await refreshGit(sid, account)
    }

    @discardableResult
    private func refreshGit(_ sid: String, _ account: String) async -> Bool {
        let loaded = gitMap[sid]?.load == .loaded
        if !loaded { gitMap[sid, default: DeskChangesGitState()].load = .loading }
        switch await read("git:" + sid, account, { try await $0.deskChangesGit(sid) }) {
        case .stale:
            return false
        case .failed(let why, let missing):
            let state = failure(sid, why, missing: missing, loaded: loaded)
            if !loaded { gitMap[sid, default: DeskChangesGitState()].load = state }
            return false
        case .fresh(let dto):
            readFresh(sid)
            gitMap[sid] = DeskChangesGitState(load: .loaded, git: DeskChangesWire.git(dto))
            return true
        }
    }

    /// One folder of the session's files.
    func loadFolder(_ sid: String, path: String) async {
        guard let account = await readyAccount() else { return }
        let key = Self.pathKey(sid, path)
        guard path.isEmpty || DeskChangesWire.pathOK(path), !DeskChangesWire.isSecret(path) else {
            folderMap[key] = DeskChangesFolder(load: .failed("This folder cannot be opened from the phone."), entries: [])
            return
        }
        let loaded = folderMap[key]?.load == .loaded
        if !loaded { folderMap[key, default: DeskChangesFolder()].load = .loading }
        switch await read("folder:" + key, account, { try await $0.deskChangesFolder(sid, path: path) }) {
        case .stale:
            break
        case .failed(let why, let missing):
            let state = failure(sid, why, missing: missing, loaded: loaded)
            if !loaded { folderMap[key, default: DeskChangesFolder()].load = state }
        case .fresh(let dto):
            readFresh(sid)
            folderMap[key] = DeskChangesFolder(load: .loaded, entries: DeskChangesWire.entries(dto))
        }
    }

    private func edit(_ key: String, _ change: (inout DeskChangesFileState) -> Void) {
        var state = fileMap[key] ?? DeskChangesFileState()
        change(&state)
        fileMap[key] = state
    }

    /// One file's text. While the person has typed, what the editor was filled from stays: a newer version on
    /// the desktop is kept beside it, never over it.
    @discardableResult
    func loadFile(_ sid: String, path: String, force: Bool = false) async -> Bool {
        let key = Self.pathKey(sid, path)
        guard !DeskChangesWire.isSecret(path) else {
            edit(key) { $0.load = .failed(DeskChangesWire.secretLine) }
            return false
        }
        guard DeskChangesWire.pathOK(path) else {
            edit(key) { $0.load = .failed("This file's name cannot be opened from the phone. Open it in Kairos on your desktop.") }
            return false
        }
        guard let account = await readyAccount() else { return false }
        _ = await DeskForgeLive.shared.readRuns()
        let loaded = fileMap[key]?.load == .loaded
        if !loaded { edit(key) { $0.load = .loading } }
        switch await read("file:" + key, account, { try await $0.deskChangesFile(sid, path: path) }) {
        case .stale:
            return false
        case .failed(let why, let missing):
            let state = failure(sid, why, missing: missing, loaded: loaded)
            if !loaded { edit(key) { $0.load = state } }
            return false
        case .fresh(let dto):
            readFresh(sid)
            apply(dto, key: key, force: force)
            return true
        }
    }

    /// `force`: the person picked Reload (or the editor needs the desktop's hash), so the desktop's text is taken.
    /// Otherwise a newer text is only kept aside in `newer`: what the editor shows never changes under the person.
    private func apply(_ dto: DeskChangesFileTextDTO, key: String, force: Bool) {
        edit(key) { state in
            if dto.binary == true {
                state.binary = true
                state.filled = ""
                state.draft = nil
                state.load = .loaded
                return
            }
            state.binary = false
            guard let desk = DeskChangesFileText(dto) else {
                // No hash or mtime: it can be read, never saved.
                state.filled = dto.content ?? ""
                state.hash = ""
                state.mtime = ""
                state.canSave = false
                state.load = .loaded
                return
            }
            if state.load != .loaded || force {
                // First fill, or the person asked for it: the desktop's text, with its hash and mtime.
                state.adopt(desk)
                state.line = nil
            } else if state.unsettled, let sent = state.sent {
                let outcome = Self.settle(&state, sent: sent, with: desk)
                state.line = outcome.line
            } else if desk.hash == state.hash {
                // The same text, only touched: the mtime it is saved against moves with it.
                state.mtime = desk.mtime
                state.newer = nil
            } else {
                state.newer = desk
            }
            state.load = .loaded
        }
    }

    /// A save whose answer was lost, compared with what the desktop has when it was read again.
    private nonisolated static func settle(_ state: inout DeskChangesFileState, sent: String,
                                           with desk: DeskChangesFileText) -> DeskForgeOutcome {
        state.sent = nil
        state.unsettled = false
        if desk.content == sent {
            state.adopt(desk)
            if state.draft == sent { state.draft = nil }
            return .done
        }
        if desk.hash == state.hash {
            state.mtime = desk.mtime
            return .unconfirmed("Your desktop did not confirm the save, and it still has the older text, so nothing was saved. Your text is still here. Saving again is safe.")
        }
        state.newer = desk
        return .unconfirmed("Your desktop did not confirm the save, and the file there has other text now. Your text is still here. Reload it, or keep yours.")
    }

    /// The app's status and its last log lines.
    func loadApp(_ sid: String) async {
        guard let account = await readyAccount() else { return }
        _ = await DeskForgeLive.shared.readRuns()
        _ = await refreshApp(sid, account)
    }

    @discardableResult
    private func refreshApp(_ sid: String, _ account: String) async -> Bool {
        var ok = false
        let loaded = appMap[sid]?.load == .loaded
        if !loaded { appMap[sid, default: DeskChangesAppState()].load = .loading }
        switch await read("app:" + sid, account, { try await $0.deskChangesAppStatus(sid) }) {
        case .stale:
            break
        case .failed(let why, let missing):
            let state = failure(sid, why, missing: missing, loaded: loaded)
            if !loaded { appMap[sid, default: DeskChangesAppState()].load = state }
        case .fresh(let dto):
            readFresh(sid)
            appMap[sid, default: DeskChangesAppState()].app = dto
            appMap[sid, default: DeskChangesAppState()].load = .loaded
            ok = true
        }
        let logsLoaded = appMap[sid]?.logsLoad == .loaded
        if !logsLoaded { appMap[sid, default: DeskChangesAppState()].logsLoad = .loading }
        switch await read("applogs:" + sid, account, { try await $0.deskChangesAppLogs(sid) }) {
        case .stale:
            break
        case .failed(let why, _):
            if !logsLoaded { appMap[sid, default: DeskChangesAppState()].logsLoad = .failed(why) }
        case .fresh(let dto):
            appMap[sid, default: DeskChangesAppState()].logs = dto.lines?.items ?? []
            appMap[sid, default: DeskChangesAppState()].logsLoad = .loaded
        }
        return ok
    }

    // MARK: Changing the desktop

    /// The status the desktop refused the request with, or nil when it may have come after the change was made
    /// (not reached, timed out, an answer this app could not read, a server error, a cancelled wait).
    private static func refusal(_ error: Error) -> Int? {
        guard let api = error as? APIError else { return nil }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return 0
        case .server(let status, _): return (400..<500).contains(status) ? status : nil
        case .offline, .unreadable: return nil
        }
    }

    private nonisolated enum Sent<Value: Sendable>: Sendable {
        case ok(Value)
        case refused(String, status: Int)
        case lost(String)
        /// The paired desktop changed while it was on its way.
        case moved
    }

    private func begin(_ key: String) -> String? {
        guard on, isAdmin else { return nil }
        follow()
        guard !busyKeys.contains(key) else { return nil }
        busyKeys.insert(key)
        return account
    }

    private func finish(_ key: String, _ account: String) {
        if self.account == account { busyKeys.remove(key) }
    }

    /// Send one change, once. Reads that overlap it are read again.
    private func attempt<Value: Sendable>(_ account: String,
                                          _ send: (APIClient) async throws -> Value) async -> Sent<Value> {
        inFlight += 1
        do {
            guard let client = Connection.shared.client else { throw APIError.notPaired }
            let value = try await send(client)
            inFlight -= 1
            writeSerial += 1
            return stillLive(account) ? .ok(value) : .moved
        } catch {
            inFlight -= 1
            writeSerial += 1
            Connection.shared.note(error)
            guard stillLive(account) else { return .moved }
            if let status = Self.refusal(error) { return .refused(error.plainWords, status: status) }
            return .lost(error.plainWords)
        }
    }

    private static func unchecked(_ what: String, _ why: String) -> String {
        "Your desktop did not confirm \(what), and it could not be read to check. Look again in a moment before trying again. " + why
    }

    /// The sentence to show instead of a change while the agent works in the session, or nil.
    private func working(_ sid: String, _ what: String) async -> String? {
        _ = await DeskForgeLive.shared.readRuns()
        return agentRunning(sid) ? "\(what) is off while the agent is working." : nil
    }

    // MARK: Reverts

    /// Put a file back to how the session started (an untracked or added file is deleted).
    func revertFile(_ sid: String, path: String) async -> DeskForgeOutcome {
        guard !DeskChangesWire.isSecret(path) else { return .refused(DeskChangesWire.secretLine) }
        if let line = await working(sid, "Reverting") { return .refused(line) }
        let key = "revert:" + sid
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.deskChangesRevertFile(sid, path: path) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            await refreshChanges(sid, account)
            return .done
        case .refused(let why, _):
            await refreshChanges(sid, account)
            return .refused("Nothing was reverted. " + why)
        case .lost(let why):
            guard await refreshChanges(sid, account) else { return .unconfirmed(Self.unchecked("the revert", why)) }
            if changeMap[sid]?.files.contains(where: { $0.path == path }) != true { return .done }
            return .unconfirmed("Your desktop did not confirm the revert, and the file still shows changes there. " + why)
        }
    }

    /// Put one block back. The desktop names it by its hash and refuses when it changed since.
    func revertHunk(_ sid: String, path: String, hash: String) async -> DeskForgeOutcome {
        guard !DeskChangesWire.isSecret(path) else { return .refused(DeskChangesWire.secretLine) }
        if let line = await working(sid, "Reverting") { return .refused(line) }
        let key = "revert:" + sid
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        func present() -> Bool {
            changeMap[sid]?.files.first(where: { $0.path == path })?.hunks.contains(where: { $0.hash == hash }) == true
        }
        switch await attempt(account, { try await $0.deskChangesRevertHunk(sid, path: path, hash: hash) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            await refreshChanges(sid, account)
            return .done
        case .refused(let why, _):
            await refreshChanges(sid, account)
            return .refused("Nothing was reverted. " + why)
        case .lost(let why):
            guard await refreshChanges(sid, account) else { return .unconfirmed(Self.unchecked("the revert", why)) }
            if !present() { return .done }
            return .unconfirmed("Your desktop did not confirm the revert, and the block is still there. " + why)
        }
    }

    // MARK: Git

    private func setGit(_ sid: String, _ dto: DeskChangesGitDTO) {
        readFresh(sid)
        gitMap[sid] = DeskChangesGitState(load: .loaded, git: DeskChangesWire.git(dto))
    }

    /// Stage or unstage one file, or every file (`path` nil).
    func stage(_ sid: String, path: String?, unstage: Bool) async -> DeskForgeOutcome {
        if let path, !unstage, DeskChangesWire.isSecret(path) { return .refused(DeskChangesWire.secretLine) }
        guard !gitLocked(sid) else { return .busy }
        let key = "git:" + sid
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        let word = unstage ? "unstage" : "stage"
        func wanted(_ git: DeskChangesGit) -> Bool {
            if let path { return git.staged.contains { $0.path == path } == !unstage }
            return unstage ? git.staged.isEmpty : git.unstaged.isEmpty
        }
        if path == nil, !unstage {
            // Stage all adds every unstaged file, so git is read again first: a file that can hold secrets stops it.
            guard await refreshGit(sid, account), let fresh = gitMap[sid]?.git else {
                return .refused("Your desktop could not be read, so nothing was staged. Try again.")
            }
            if fresh.unstaged.contains(where: { DeskChangesWire.isSecret($0.path) }) {
                return .refused("A file that can hold secrets is among the changes, so Stage all is off. Stage the other files one by one.")
            }
        }
        switch await attempt(account, { try await $0.deskChangesGitAction(sid, action: word, path: path) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok(let dto):
            setGit(sid, dto)
            return .done
        case .refused(let why, _):
            await refreshGit(sid, account)
            return .refused("Nothing was changed. " + why)
        case .lost(let why):
            guard await refreshGit(sid, account), let git = gitMap[sid]?.git else {
                return .unconfirmed(Self.unchecked("the change", why))
            }
            if wanted(git) { return .done }
            return .unconfirmed("Your desktop did not confirm the change, and the lists show what it has now. " + why)
        }
    }

    /// Commit the staged files, and only those: `expected` is the list the person confirmed. The desktop commits
    /// every file when nothing is staged, so git is read again just before sending, and the commit goes only if the
    /// staged set is exactly `expected` and holds no file that can hold secrets.
    /// There is no request id: after a lost answer the branch is read again, here in the store, and Commit stays
    /// off until it knows. It is never sent a second time from here.
    func commit(_ sid: String, message: String, expected: [String]) async -> DeskForgeOutcome {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .refused("Write a commit message first.") }
        guard !expected.isEmpty else { return .refused("Stage what you want in this commit first.") }
        guard !gitLocked(sid) else { return .busy }
        guard gitMap[sid]?.git != nil else { return .refused("Read the branch from your desktop first.") }
        if let line = await working(sid, "Committing") { return .refused(line) }
        let key = "git:" + sid
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        guard await refreshGit(sid, account), let before = gitMap[sid]?.git else {
            return .refused("Your desktop could not be read, so nothing was committed. Try again.")
        }
        let staged = before.staged.map(\.path)
        if staged.isEmpty {
            return .refused("Nothing is staged on your desktop now, so nothing was committed. Stage what you want first.")
        }
        if Set(staged) != Set(expected) || staged.count != expected.count {
            return .refused("The staged files changed on your desktop, so nothing was committed. The list now shows what it has.")
        }
        if staged.contains(where: { DeskChangesWire.isSecret($0) }) {
            return .refused("A staged file can hold secrets, so nothing was committed. Unstage it, or commit in Kairos on your desktop.")
        }
        switch await attempt(account, { try await $0.deskChangesGitAction(sid, action: "commit", message: text) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok(let dto):
            setGit(sid, dto)
            return .done
        case .refused(let why, _):
            await refreshGit(sid, account)
            return .refused("Nothing was committed. " + why)
        case .lost(let why):
            watchCommit(sid, before: before, account: account)
            return .unconfirmed(holdLine(sid, why: why))
        }
    }

    private func holdLine(_ sid: String, why: String) -> String {
        (holdLine(sid) ?? "") + " " + why
    }

    private func watchCommit(_ sid: String, before: DeskChangesGit, account: String) {
        watches[sid]?.cancel()
        holdMap[sid] = DeskChangesHold(phase: .checking)
        watches[sid] = Task { [weak self] in
            guard let self else { return }
            var checked = false
            // A commit's hooks may run for up to two minutes on the desktop.
            for _ in 0..<26 {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                guard self.stillLive(account) else { return }
                checked = await self.refreshGit(sid, account)
                if checked, self.gitMap[sid]?.git?.signature != before.signature {
                    self.holdMap[sid] = DeskChangesHold(phase: .changed)
                    self.watches[sid] = nil
                    return
                }
            }
            if Task.isCancelled { return }
            self.holdMap[sid] = DeskChangesHold(phase: .quiet(checked: checked))
            self.watches[sid] = nil
        }
    }

    /// Pull the upstream (fast-forward only). The repository's own hooks run on the desktop.
    func pull(_ sid: String) async -> DeskForgeOutcome {
        guard !gitLocked(sid) else { return .busy }
        guard let before = gitMap[sid]?.git, before.upstream != nil else {
            return .refused("Push this branch once on your desktop to set its upstream before pulling.")
        }
        if let line = await working(sid, "Pulling") { return .refused(line) }
        let key = "git:" + sid
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.deskChangesGitAction(sid, action: "pull") }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok(let dto):
            setGit(sid, dto)
            return .done
        case .refused(let why, _):
            await refreshGit(sid, account)
            return .refused("Nothing was pulled. " + why)
        case .lost(let why):
            guard await refreshGit(sid, account), let now = gitMap[sid]?.git else {
                return .unconfirmed(Self.unchecked("the pull", why))
            }
            if now.behind < before.behind { return .done }
            return .unconfirmed("Your desktop did not confirm the pull. Its branch is \(now.behind) behind there now. " + why)
        }
    }

    // MARK: Approval streams (push, merge back, restart)

    /// Start an action the desktop asks to approve. Answers false when nothing was started.
    @discardableResult
    func startApproval(_ sid: String, _ kind: DeskChangesApproval.Kind) -> Bool {
        guard on, isAdmin else { return false }
        follow()
        guard streams[sid] == nil, approvalMap[sid]?.active != true else { return false }
        if kind != .restart, gitLocked(sid) { return false }
        let account = self.account
        let baseline = DeskChangesBaseline(git: gitMap[sid]?.git, startedAt: appMap[sid]?.app?.startedAt)
        approvalMap[sid] = DeskChangesApproval(kind: kind, phase: .waiting)
        streams[sid] = Task { [weak self] in
            await self?.readApproval(sid, kind, account, baseline)
            if let self, self.account == account { self.streams[sid] = nil }
        }
        return true
    }

    func dismissApproval(_ sid: String) {
        if case .ended? = approvalMap[sid]?.phase { approvalMap[sid] = nil }
    }

    /// Read one approval stream to its end. It is sent once: when it closes without a result, the desktop is read
    /// to see what happened, compared with what it had before, and the action is never started again from here.
    private func readApproval(_ sid: String, _ kind: DeskChangesApproval.Kind, _ account: String,
                              _ baseline: DeskChangesBaseline) async {
        var done = false
        var refusal: String?
        var lost: String?
        do {
            guard let client = Connection.shared.client else { throw APIError.notPaired }
            let bytes: URLSession.AsyncBytes
            switch kind {
            case .push: bytes = try await client.deskChangesGitStream(sid, action: "push")
            case .merge: bytes = try await client.deskChangesGitStream(sid, action: "merge")
            case .restart: bytes = try await client.deskChangesAppRestart(sid)
            }
            for try await line in bytes.lines {
                guard stillLive(account) else { return }
                guard let payload = LiveEventStream.payload(of: line),
                      let packet = try? KJSON.decode(DeskForgeStreamPacketDTO.self, from: payload) else { continue }
                if let error = packet.error {
                    refusal = error
                    break
                }
                if packet.finished {
                    done = true
                    break
                }
                if let request = packet.permission, request.id != nil {
                    approvalMap[sid]?.request = request
                    approvalMap[sid]?.phase = .asking
                    approvalMap[sid]?.note = nil
                }
            }
            if !done && refusal == nil { lost = "The connection closed before your desktop answered." }
        } catch {
            if !(error is CancellationError) { Connection.shared.note(error) }
            if Self.refusal(error) != nil { refusal = error.plainWords } else { lost = error.plainWords }
        }
        writeSerial += 1
        guard stillLive(account) else { return }
        approvalMap[sid]?.request = nil
        approvalMap[sid]?.note = nil
        let sentence: String
        switch kind {
        case .push:
            let read = await refreshGit(sid, account)
            guard stillLive(account) else { return }
            let now = gitMap[sid]?.git
            let pushed = (baseline.git?.upstream == nil && now?.upstream != nil)
                || ((baseline.git?.ahead ?? 0) > 0 && (now?.ahead ?? 1) == 0)
            if done || (read && pushed) {
                sentence = "Pushed. Your desktop has the branch."
            } else if let refusal {
                sentence = "Nothing was pushed. " + refusal
            } else if read {
                sentence = "Your desktop did not confirm the push, and the branch still looks ahead there. Check it in Kairos on your desktop before pushing again. " + (lost ?? "")
            } else {
                sentence = Self.unchecked("the push", lost ?? "")
            }
        case .merge:
            let read = await refreshGit(sid, account)
            guard stillLive(account) else { return }
            let merged = baseline.git?.unmerged == true && gitMap[sid]?.git?.unmerged == false
            if done || (read && merged) {
                sentence = "Merged back. The session is still open."
            } else if let refusal {
                sentence = "Nothing was merged. " + refusal
            } else if read {
                sentence = "Your desktop did not confirm the merge, and the branch still looks unmerged there. Check it in Kairos on your desktop before merging again. " + (lost ?? "")
            } else {
                sentence = Self.unchecked("the merge", lost ?? "")
            }
        case .restart:
            let read = await refreshApp(sid, account)
            guard stillLive(account) else { return }
            let app = appMap[sid]?.app
            let restarted = app?.running == true && (app?.startedAt ?? 0) > (baseline.startedAt ?? 0)
            if done || (read && restarted) {
                sentence = "The app restarted on your desktop."
            } else if let refusal {
                sentence = "The restart did not go through. " + refusal + " Your desktop stops the app first, so it is "
                    + (read ? (app?.running == true ? "running" : "stopped") : "possibly stopped") + " now."
            } else if read {
                sentence = "Your desktop did not confirm the restart. The app is \(app?.running == true ? "running" : "stopped") there now. Your desktop stops the app first and then asks for approval, so cancelling leaves it stopped. " + (lost ?? "")
            } else {
                sentence = Self.unchecked("the restart", lost ?? "")
            }
        }
        approvalMap[sid]?.phase = .ended(sentence)
    }

    /// Approve once, or cancel, the request an approval stream is showing. The stream itself then says how it
    /// ended, so a lost answer here is never taken for a yes or a no.
    func answerApproval(_ sid: String, allow: Bool) async {
        guard current, approvalMap[sid]?.phase == .asking, let request = approvalMap[sid]?.request,
              let requestID = request.id, let choice = DeskForgeLive.onceChoice(request, allow: allow) else { return }
        let account = self.account
        approvalMap[sid]?.phase = .answering
        approvalMap[sid]?.note = nil
        do {
            guard let client = Connection.shared.client else { throw APIError.notPaired }
            _ = try await client.permissionAnswer(requestID, choice: choice)
            guard stillLive(account) else { return }
            if approvalMap[sid]?.phase == .answering { approvalMap[sid]?.phase = .finishing }
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), approvalMap[sid]?.phase == .answering else { return }
            approvalMap[sid]?.phase = .asking
            approvalMap[sid]?.note = Self.refusal(error) != nil
                ? "Your answer was not taken. " + error.plainWords
                : "Your desktop did not confirm your answer. If it took it, this finishes by itself. If not, answer again. " + error.plainWords
        }
    }

    // MARK: Files

    /// What the person typed. Not while a save is on its way.
    func setDraft(_ sid: String, path: String, _ text: String) {
        let key = Self.pathKey(sid, path)
        guard current, !busyKeys.contains("file:" + key), var state = fileMap[key],
              state.load == .loaded, !state.binary, !state.unsettled else { return }
        if text == state.filled {
            // Back to what it started as. A newer desktop version stays aside until the person picks Reload.
            state.draft = nil
        } else {
            state.draft = text
        }
        fileMap[key] = state
    }

    /// Save the person's text with the hash and mtime the editor was filled from. `overwrite` is sent only by
    /// Keep mine, after the person confirmed that the desktop's newer version is replaced.
    func save(_ sid: String, path: String, overwrite: Bool) async -> DeskForgeOutcome {
        let key = Self.pathKey(sid, path)
        guard !DeskChangesWire.isSecret(path), let snapshot = fileMap[key], let text = snapshot.draft, !snapshot.binary,
              snapshot.canSave, snapshot.load == .loaded, !snapshot.unsettled else { return .busy }
        if overwrite, snapshot.newer == nil { return .busy }
        if !overwrite, snapshot.newer != nil {
            return .refused("This file changed on your desktop. Reload it, or keep yours.")
        }
        guard text.utf8.count <= 1_048_576 else { return .refused("This file is too long to save from the phone (1 MB).") }
        if let line = await working(sid, "Saving") { return .refused(line) }
        let busy = "file:" + key
        guard let account = begin(busy) else { return .busy }
        defer { finish(busy, account) }
        // What was sent: the text, and the hash and mtime it was filled from.
        let hash = snapshot.hash
        let mtime = snapshot.mtime
        switch await attempt(account, { try await $0.deskChangesSave(sid, path: path, content: text, hash: hash, mtime: mtime, overwrite: overwrite) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok(let dto):
            if let desk = DeskChangesFileText(dto) {
                edit(key) { state in
                    state.adopt(desk)
                    if state.draft == text { state.draft = nil }
                    state.line = nil
                }
            } else {
                // The answer carried no hash: take the text as saved and read the file again for its hash.
                edit(key) { state in
                    state.filled = text
                    state.draft = nil
                    state.canSave = false
                }
                await loadFile(sid, path: path, force: true)
            }
            return .done
        case .refused(let why, let status):
            if status == 409 {
                await loadFile(sid, path: path)
                if fileMap[key]?.newer != nil {
                    return .refused("This file changed on your desktop. Your text is still here. Reload it, or keep yours.")
                }
                return .refused("Your desktop touched this file, but its text is the same. Your text is still here. Save again.")
            }
            return .refused("Your text was not saved. " + why)
        case .lost(let why):
            edit(key) { state in
                state.unsettled = true
                state.sent = text
            }
            guard case .fresh(let dto) = await read("file:" + key, account, { try await $0.deskChangesFile(sid, path: path) }),
                  let desk = DeskChangesFileText(dto) else {
                return .unconfirmed(Self.unchecked("the save", why) + " Your text is still here.")
            }
            var outcome = DeskForgeOutcome.done
            edit(key) { outcome = Self.settle(&$0, sent: text, with: desk) }
            if case .unconfirmed(let line) = outcome { return .unconfirmed(line + " " + why) }
            return outcome
        }
    }

    /// The person has read the sentence on the file: it goes.
    func dismissLine(_ sid: String, path: String) {
        let key = Self.pathKey(sid, path)
        guard current, fileMap[key] != nil else { return }
        edit(key) { $0.line = nil }
    }

    /// Drop the person's text and take what the desktop has. The screen asks first when there is text to lose.
    func reload(_ sid: String, path: String) async {
        let key = Self.pathKey(sid, path)
        guard !busyKeys.contains("file:" + key) else { return }
        edit(key) { state in
            state.draft = nil
            state.newer = nil
            state.line = nil
            state.unsettled = false
            state.sent = nil
        }
        await loadFile(sid, path: path, force: true)
    }

    // MARK: App

    /// Stop the session's app. Stop takes no request id: after a lost answer the status is read, never sent again.
    func stopApp(_ sid: String) async -> DeskForgeOutcome {
        let key = "app:" + sid
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.deskChangesAppStop(sid) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok(let dto):
            appMap[sid, default: DeskChangesAppState()].app = dto
            appMap[sid, default: DeskChangesAppState()].load = .loaded
            _ = await refreshApp(sid, account)
            return .done
        case .refused(let why, _):
            _ = await refreshApp(sid, account)
            return .refused("The app was not stopped. " + why)
        case .lost(let why):
            guard await refreshApp(sid, account) else { return .unconfirmed(Self.unchecked("Stop", why)) }
            if appMap[sid]?.app?.running != true { return .done }
            return .unconfirmed("Your desktop did not confirm Stop, and the app is still running there. " + why)
        }
    }
}

// MARK: - Small shared views

/// What a review screen shows in place of its content: the one line for a member account, a session the
/// desktop does not have, the loading note, or what failed with Try again.
struct DeskChangesGate: View {
    let sessionID: String
    let load: DeskForgeLoad
    var reading = "Reading this session from your desktop."
    let retry: () -> Void
    @State private var live = DeskChangesLive.shared

    var body: some View {
        if let gone = live.gone(sessionID), DeskForgeLive.shared.isAdmin {
            DeskForgeLine(text: gone)
        } else {
            DeskForgeGate(load: load, reading: reading, retry: retry)
        }
    }
}

/// One screen with a header and one line, for what stays on the desktop.
struct DeskChangesLineScreen: View {
    let title: String
    var subtitle: String? = nil
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeskForgeLine(text: line)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: title, subtitle: subtitle) }
        .kScreen()
    }
}

/// An action the desktop asks to approve (a push, a merge back, a restart), drawn exactly as it was sent:
/// the tool's name, what it is aimed at and the desktop's own description, with any sign-in part of a remote
/// address left out. Approve once, or cancel.
struct DeskChangesApprovalCard: View {
    let sessionID: String
    let approval: DeskChangesApproval
    @State private var live = DeskChangesLive.shared

    private var title: String {
        switch approval.kind {
        case .push: "Pushing the branch"
        case .merge: "Merging back"
        case .restart: "Restarting the app"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch approval.phase {
            case .waiting:
                progress("Waiting for your desktop.")
            case .answering:
                progress("Sending your answer.")
            case .finishing:
                progress("Approved. Waiting for your desktop to finish.")
            case .ended(let sentence):
                Text(sentence)
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.tap()
                    live.dismissApproval(sessionID)
                } label: {
                    Text("OK")
                        .font(KFont.ui(15, .semibold))
                        .foregroundStyle(Palette.goldText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            case .asking:
                if let request = approval.request {
                    DeskForgeRequestText(request: request)
                    if let note = approval.note {
                        HintLine(text: note, symbol: "exclamationmark.triangle", color: Palette.goldText)
                    }
                    let allow = DeskForgeLive.onceChoice(request, allow: true)
                    let deny = DeskForgeLive.onceChoice(request, allow: false)
                    HStack(spacing: 10) {
                        if deny != nil {
                            PillButton(title: "Cancel", look: .danger, wide: true) {
                                Haptics.tap()
                                Task { await live.answerApproval(sessionID, allow: false) }
                            }
                        }
                        if allow != nil {
                            PillButton(title: "Approve once", look: .filled, wide: true) {
                                Haptics.tap()
                                Task { await live.answerApproval(sessionID, allow: true) }
                            }
                        }
                    }
                    if allow == nil {
                        HintLine(text: "Approve this one in Kairos on your desktop.")
                    }
                }
            }
        }
        .padding(14)
        .kCard(radius: 20, raised: true)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.gold.opacity(0.5), lineWidth: 1))
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(Palette.goldText)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                Text(text).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }
}
