import SwiftUI

// The paired desktop behind Desktop home and Forge sessions (Net/DeskForgeAPI.swift). Not paired, nothing
// here runs and the screens show their sample data from ForgeStore, exactly as before.
//
// Forge drives a coding agent on the person's own computer, so this is strict:
// - Nothing is shown as done before the desktop says so. There are no optimistic changes to put back.
// - A change the desktop refused did not happen. A change whose answer was lost is "could not confirm":
//   the desktop is read again and the screen shows what it really has.
// - Only a message carries a request id (one per message, reused when it is sent again). Starting a session,
//   ending one and starting an app do not, so they are never sent a second time: the desktop is read instead.
// - The phone answers a request with "once" choices only. A standing "always allow" is given on the desktop.

// MARK: - What the screens read

nonisolated enum DeskForgeLoad: Hashable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// How one change to the desktop ended.
nonisolated enum DeskForgeOutcome: Equatable, Sendable {
    case done
    /// Not sent: the same change is already on its way.
    case busy
    /// The desktop refused it, so it did not happen.
    case refused(String)
    /// The answer never arrived. The sentence says what the desktop has now.
    case unconfirmed(String)

    /// The sentence to show, or nil when there is nothing to say.
    var line: String? {
        switch self {
        case .done, .busy: return nil
        case .refused(let text), .unconfirmed(let text): return text
        }
    }
}

nonisolated enum DeskForgeRead<Value: Sendable>: Sendable {
    case fresh(Value)
    /// Overtaken, cancelled, or for a desktop that is no longer the paired one: it changes nothing.
    case stale
    case failed(String, missing: Bool)
}

nonisolated enum DeskForgeSent<Value: Sendable>: Sendable {
    case ok(Value)
    case refused(String)
    case lost(String)
    /// The paired desktop changed while it was on its way.
    case moved
}

nonisolated struct DeskForgeProject: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var path: String
    var lastOpened: String
    /// The saved app command, shown read only. Empty when none is set.
    var appCommand: String
    var git: DeskForgeGitDTO?

    var branch: String { git?.branch ?? "" }
    var row: ForgeProject { ForgeProject(id: id, name: name, path: path, branch: branch, lastOpened: lastOpened) }

    /// Why a session cannot start here, when the desktop already says so.
    var gitProblem: String? {
        switch git?.state {
        case "not_git": return "This folder is not a git repository."
        case "unavailable", "error": return git?.message ?? "This project's folder could not be read."
        default: return nil
        }
    }
}

nonisolated struct DeskForgeSession: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var projectID: String
    /// nil when the session works in place.
    var branch: String?
    var baseBranch: String
    var mode: ForgeMode
    var ended: Bool
    var updatedAt: Date?
    var endpointID: String?
}

nonisolated struct DeskForgeApp: Identifiable, Hashable, Sendable {
    var id: String { sessionID }
    var sessionID: String
    var projectID: String
    var port: Int
    var command: String
    var ready: Bool
}

/// One tool the agent used, keyed by the desktop's own step id.
nonisolated struct DeskForgeStep: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    /// "read", "search", "edit", "command" or "tool".
    var kind: String
    var summary: String
    var output: String?
    var failed = false
    var done = false

    var symbol: String {
        if failed { return "xmark.octagon" }
        switch kind {
        case "edit": return "pencil"
        case "command": return "terminal"
        case "search": return "magnifyingglass"
        case "read": return "doc.text"
        default: return "wrench.and.screwdriver"
        }
    }
}

/// The turn the desktop is running, or the one that just ended.
nonisolated struct DeskForgeLiveRun: Hashable, Sendable {
    var turnID: String
    var running: Bool
    var stopping: Bool
    var steps: [DeskForgeStep]
    /// The approval or question waiting on the person, exactly as the desktop sent it.
    var request: ChatPermissionDTO?
}

nonisolated struct DeskForgeTurn: Identifiable, Hashable, Sendable {
    let id: String
    var prompt: String
    var reply: String
    var failure: String?
    var afterBackground = false
    var runID: String?
    /// The saved chat already holds this turn's reply.
    var answered = false
    var live: DeskForgeLiveRun?
}

nonisolated struct DeskForgeRunTime: Hashable, Sendable {
    var start: Double
    var end: Double?
}

/// What one turn changed in the session's folder.
nonisolated struct DeskForgeCheckpoint: Hashable, Sendable {
    var id: String
    var created: Double
    var finished: Double?
    var changed: Bool
    var overlap: Bool
    var files: [String]
    /// How many of its changes were already put back.
    var restored: Int
    var changes: Int

    var undone: Bool { changes > 0 && restored == changes }
    var canUndo: Bool { changed && !overlap && changes > 0 && restored == 0 }
}

nonisolated struct DeskForgeDetail: Sendable {
    var load: DeskForgeLoad = .idle
    /// The desktop says it has no such session.
    var missing = false
    var title = ""
    var projectID = ""
    var branch: String?
    var baseBranch = ""
    var mode: ForgeMode = .build
    var ended = false
    var fullAccess = false
    var endpointID: String?
    var modelOverride: String?
    var effort: String?
    var workspace = ""
    var turns: [DeskForgeTurn] = []
    var skippedMessages = 0
    var checkpoints: [DeskForgeCheckpoint] = []
    var runTimes: [String: DeskForgeRunTime] = [:]
    /// A saved turn's steps, read when its work is opened.
    var steps: [String: [DeskForgeStep]] = [:]
    var stepsUnread: Set<String> = []
}

/// An action the desktop asks to approve over its own stream: starting an app, or merging back.
nonisolated struct DeskForgeApproval: Sendable {
    nonisolated enum Kind: Sendable { case app, merge }
    nonisolated enum Phase: Equatable, Sendable {
        case waiting, asking, answering, finishing
        /// Over. The sentence says how it ended.
        case ended(String)
    }
    var kind: Kind
    var phase: Phase
    var request: ChatPermissionDTO?
    var note: String?
}

/// What starting a session sends, kept so a lost answer is checked against what was sent.
nonisolated struct DeskForgeStart: Identifiable, Hashable, Sendable {
    var id: String { [projectID, isolation, branch ?? "", endpointID ?? "", mode, task].joined(separator: "|") }
    var projectID: String
    var task: String
    /// "build" or "plan".
    var mode: String
    /// "new_worktree", "existing_branch" or "in_place".
    var isolation: String
    var branch: String?
    var endpointID: String?
}

/// Where a start whose answer was lost stands. The desktop may still be making the session.
nonisolated enum DeskForgeStartPhase: Equatable, Sendable {
    case checking
    /// The session appeared on the desktop.
    case found(String)
    /// The window ended without it. `checked` is false when the last reads failed, so nothing is claimed.
    case over(checked: Bool)
}

nonisolated struct DeskForgeStartCheck: Sendable {
    var start: DeskForgeStart
    var phase: DeskForgeStartPhase
}

/// The one line the start screen shows about a start whose answer was lost.
nonisolated struct DeskForgeStartNotice: Sendable {
    var text: String
    var sessionID: String?
    var checking: Bool
}

// MARK: - The store

@Observable
final class DeskForgeLive {
    static let shared = DeskForgeLive()

    /// The desktop and account everything below was read for. Nothing else is ever shown.
    private var account = "sample"
    private var homeLoad: DeskForgeLoad = .idle
    private var projectList: [DeskForgeProject] = []
    private var sessionList: [DeskForgeSession] = []
    private var appList: [DeskForgeApp] = []
    private var dayList: [DeskForgeDayDTO] = []
    private var homeCounts: PhoneHomeDTO?
    private var runMap: [String: ChatRunDTO] = [:]
    private var modelList: [ModelChoiceDTO] = []
    private var detailMap: [String: DeskForgeDetail] = [:]
    private var busyKeys: Set<String> = []
    private var unsettledAnswers: Set<String> = []
    private var approvalMap: [String: DeskForgeApproval] = [:]
    private var branchMap: [String: [DeskForgeBranchDTO]] = [:]
    private var skippedRows = 0
    private var repoChoice: String?
    private var noteMap: [String: String] = [:]
    private var draftMap: [String: String] = [:]
    /// The words of a kept send that a read of the desktop has since shown: the session screen clears them from its box.
    private var settledMap: [String: String] = [:]
    /// Starts whose answer was lost, by project, branch and task. Kept here so leaving the screen changes nothing.
    private var startChecks: [String: DeskForgeStartCheck] = [:]
    /// The project a "New session" control asked for.
    var composeProjectID: String?

    @ObservationIgnored private var reads: [String: Int] = [:]
    @ObservationIgnored private var writeSerial = 0
    /// One request id per send: the text, the id, and what the desktop showed before it (turn count, run turn).
    @ObservationIgnored private var pendingSends: [String: (text: String, id: String, turns: Int, turnID: String?)] = [:]
    @ObservationIgnored private var startTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var streams: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var polls = 0

    private init() {}

    // MARK: Which desktop

    /// Paired (whether or not the desktop is answering right now): the screens show the desktop, never samples.
    var on: Bool { !Connection.shared.usesSampleData }

    /// Forge answers an admin account only.
    var isAdmin: Bool { Connection.shared.desktop?.isAdmin ?? false }

    static let adminLine = "Forge needs an admin account on your desktop."

    // Screens that still show made-up data. While paired their links stay closed. The lead turns each one on
    // when the pass that makes it live is merged.
    /// Explorer, files, the Git sheet, Changes and Diff.
    static let changesAndFilesLive = true
    static let computerLive = false
    static let browseLive = false
    static let localModelsLive = false
    static let pcFilesLive = false
    /// True while at least one Desktop home tile is still closed: the one line about them shows.
    static var desktopTilesWaiting: Bool { !(computerLive && browseLive && localModelsLive && pcFilesLive) }
    private static let desktopChanged = "Your paired desktop changed. Try again."

    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username + "|" + (desktop.isAdmin ? "admin" : "member")
    }

    /// Changes when the phone is paired or unpaired, the desktop comes back, or another desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    private var current: Bool { on && account == Self.accountKey }

    private func stillLive(_ account: String) -> Bool {
        on && self.account == account && Self.accountKey == account
    }

    /// Before anything is read: drop whatever was read for another desktop, another account or sample mode.
    private func follow() {
        let key = Self.accountKey
        guard account != key else { return }
        for task in streams.values { task.cancel() }
        streams = [:]
        for task in startTasks.values { task.cancel() }
        startTasks = [:]
        startChecks = [:]
        account = key
        homeLoad = .idle
        projectList = []
        sessionList = []
        appList = []
        dayList = []
        homeCounts = nil
        runMap = [:]
        modelList = []
        detailMap = [:]
        busyKeys = []
        unsettledAnswers = []
        approvalMap = [:]
        branchMap = [:]
        skippedRows = 0
        repoChoice = nil
        noteMap = [:]
        draftMap = [:]
        settledMap = [:]
        composeProjectID = nil
        reads = [:]
        pendingSends = [:]
    }

    private static func waitWhileConnecting() async {
        var waited = 0
        while Connection.shared.state == .connecting, waited < 80, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
    }

    // MARK: Reading what was read

    var load: DeskForgeLoad { current ? homeLoad : .loading }
    var projects: [DeskForgeProject] { current ? projectList : [] }
    var sessions: [DeskForgeSession] { current ? sessionList : [] }
    var apps: [DeskForgeApp] { current ? appList : [] }
    var days: [DeskForgeDayDTO] { current ? dayList : [] }
    var counts: PhoneHomeDTO? { current ? homeCounts : nil }
    var models: [ModelChoiceDTO] { current ? modelList : [] }
    var skipped: Int { current ? skippedRows : 0 }

    func project(_ id: String) -> DeskForgeProject? { projects.first { $0.id == id } }
    func session(_ id: String) -> DeskForgeSession? { sessions.first { $0.id == id } }
    func detail(_ id: String) -> DeskForgeDetail? { current ? detailMap[id] : nil }
    func app(for sessionID: String) -> DeskForgeApp? { apps.first { $0.sessionID == sessionID } }
    func approval(_ sessionID: String) -> DeskForgeApproval? { current ? approvalMap[sessionID] : nil }
    func branches(_ projectID: String) -> [DeskForgeBranchDTO]? { current ? branchMap[projectID] : nil }
    func note(_ sessionID: String) -> String? { current ? noteMap[sessionID] : nil }
    func isBusy(_ key: String) -> Bool { current && busyKeys.contains(key) }
    func isUnsettled(_ requestID: String) -> Bool { current && unsettledAnswers.contains(requestID) }

    func clearNote(_ sessionID: String) { noteMap[sessionID] = nil }

    /// The words of an unconfirmed send that the desktop turned out to have.
    func settledSend(_ sessionID: String) -> String? { current ? settledMap[sessionID] : nil }
    func clearSettledSend(_ sessionID: String) { settledMap[sessionID] = nil }

    /// A first task that was not sent, handed to the session's box once.
    func takeDraft(_ sessionID: String) -> String? {
        guard current else { return nil }
        let text = draftMap[sessionID]
        draftMap[sessionID] = nil
        return text
    }

    /// Open sessions of one project, the ones waiting on the person first.
    func sessions(in projectID: String) -> [DeskForgeSession] {
        sessions.filter { $0.projectID == projectID }
    }

    var openSessions: [DeskForgeSession] { sessions.filter { !$0.ended } }

    /// The project Repo lifespan shows on Forge Home: the one picked on this phone, else the newest.
    var repoProjectID: String? {
        get {
            if let repoChoice, project(repoChoice) != nil { return repoChoice }
            return projects.first?.id
        }
        set { repoChoice = newValue }
    }

    func isRunning(_ sessionID: String) -> Bool {
        current && runMap[sessionID]?.status == "processing"
    }

    func state(of sessionID: String) -> ForgeState {
        guard current, let run = runMap[sessionID] else { return .idle }
        if run.status == "processing" { return run.permission?.id != nil ? .needsYou : .working }
        return run.status == "done" ? .done : .idle
    }

    func modelName(_ endpointID: String?) -> String {
        guard let endpointID else { return "No model" }
        return models.first { $0.id == endpointID }?.name ?? "Model"
    }

    /// A session as one row of a list. Change counts are not read here, so the row shows none.
    func info(_ session: DeskForgeSession) -> ForgeSessionInfo {
        let model = modelName(session.endpointID)
        return ForgeSessionInfo(
            id: session.id, title: session.title.isEmpty ? "Session" : session.title, projectID: session.projectID,
            branch: session.branch, mode: session.mode, access: .supervised, agent: model, model: model, effort: "",
            state: state(of: session.id), updated: ChatFormat.listTime(session.updatedAt),
            today: session.updatedAt.map { Calendar.current.isDateInToday($0) } ?? false,
            turns: [], changes: [],
            git: GitInfo(branch: session.branch ?? session.baseBranch, upstream: nil, ahead: 0, behind: 0, staged: [], unstaged: [], branches: []),
            ended: session.ended)
    }

    /// What the session screen draws: the saved turns, then the turn that is running or just ended.
    func transcript(_ id: String) -> [DeskForgeTurn] {
        guard let shown = detail(id), shown.load == .loaded else { return [] }
        var turns = shown.turns
        guard let run = runMap[id], let turnID = run.turnId, !turnID.isEmpty else { return turns }
        let running = run.status == "processing"
        let prompt = run.prompt ?? ""
        var text = run.text ?? ""
        // The live stream has the newest words of the same turn before the next read does.
        if let streamed = ChatStore.shared.runs[id], streamed.turnID == turnID, streamed.text.count > text.count {
            text = streamed.text
        }
        let live = DeskForgeLiveRun(turnID: turnID, running: running, stopping: running && (run.stopping ?? false),
                                    steps: Self.steps(live: run.toolSteps ?? []), request: running ? run.permission : nil)
        if let last = turns.indices.last, !prompt.isEmpty, turns[last].prompt == prompt,
           !turns[last].answered || (run.runId != nil && turns[last].runID == run.runId) {
            turns[last].live = live
            if !turns[last].answered {
                turns[last].reply = TranscriptParsing.body(text).text
                if !running { turns[last].failure = Self.runFailure(run, text: text) }
            }
        } else if running {
            var turn = DeskForgeTurn(id: "live-" + turnID, prompt: prompt, reply: TranscriptParsing.body(text).text)
            turn.live = live
            turns.append(turn)
        }
        return turns
    }

    /// The checkpoint that belongs to one saved turn, when its run and the checkpoints were read.
    func checkpoint(for turn: DeskForgeTurn, in id: String) -> DeskForgeCheckpoint? {
        guard let shown = detail(id), let runID = turn.runID else { return nil }
        return Self.checkpoint(for: runID, times: shown.runTimes, in: shown.checkpoints)
    }

    private func runSignature(_ id: String) -> String {
        guard let run = runMap[id] else { return "" }
        return "\(run.turnId ?? "")|\(run.status ?? "")"
    }

    // MARK: Mapping

    nonisolated static func makeProject(_ dto: DeskForgeProjectDTO) -> DeskForgeProject {
        let opened = dto.lastOpenedAt.map { ChatFormat.listTime(Date(timeIntervalSince1970: $0)) } ?? ""
        let path = dto.path ?? ""
        let name = (dto.name ?? "").isEmpty ? (path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? "Project") : (dto.name ?? "")
        return DeskForgeProject(id: dto.id, name: name, path: path, lastOpened: opened,
                                appCommand: dto.appCommand ?? "", git: dto.git)
    }

    nonisolated static func makeSession(id: String, title: String?, updatedAt: Double?, endpointID: String?,
                                    forge: DeskForgeDetailsDTO?) -> DeskForgeSession? {
        guard let forge, let projectID = forge.projectId, !projectID.isEmpty else { return nil }
        let inPlace = forge.isolation == "in_place"
        return DeskForgeSession(
            id: id, title: title ?? "", projectID: projectID, branch: inPlace ? nil : forge.branch,
            baseBranch: forge.baseBranch ?? forge.branch ?? "", mode: forge.mode == "plan" ? .plan : .build,
            ended: forge.removed ?? false, updatedAt: updatedAt.map { Date(timeIntervalSince1970: $0) },
            endpointID: endpointID)
    }

    /// A session's saved messages as turns: each question with the reply that followed it.
    nonisolated static func turns(_ messages: [ChatMessageDTO], modelName: String) -> [DeskForgeTurn] {
        var result: [DeskForgeTurn] = []
        for (index, message) in messages.enumerated() {
            if message.displayOnly == true { continue }
            let content = message.content ?? ""
            if message.role == "user" {
                result.append(DeskForgeTurn(id: "m\(index)", prompt: content.isEmpty ? "(attachment)" : content, reply: ""))
                continue
            }
            guard message.role == "assistant" else { continue }
            var failure: String?
            switch message.status ?? "complete" {
            case "failed":
                failure = TranscriptParsing.failureLine(kind: message.failureKind, model: message.failureModelName ?? modelName, partial: !content.isEmpty)
            case "stopped":
                failure = content.isEmpty ? "Stopped before a response started." : "Stopped. The partial reply was saved."
            case "interrupted":
                failure = content.isEmpty ? "The response was interrupted." : "The response was interrupted. The partial reply was saved."
            default:
                break
            }
            var followup = false
            if let value = message.backgroundFollowup, !value.isNull, value.bool != false { followup = true }
            let reply = TranscriptParsing.body(content).text
            if let last = result.indices.last, !result[last].answered, !followup {
                result[last].reply = reply
                result[last].failure = failure
                result[last].runID = message.runId
                result[last].answered = true
            } else {
                var turn = DeskForgeTurn(id: "m\(index)", prompt: "", reply: reply)
                turn.failure = failure
                turn.afterBackground = followup
                turn.runID = message.runId
                turn.answered = true
                result.append(turn)
            }
        }
        return result
    }

    private nonisolated static func runFailure(_ run: ChatRunDTO, text: String) -> String? {
        switch run.status {
        case "failed": return run.error ?? "The reply failed. Check the model's connection, or pick another model."
        case "stopped": return text.isEmpty ? "Stopped before a response started." : "Stopped. The partial reply was saved."
        default: return nil
        }
    }

    private nonisolated static func settle(_ step: inout DeskForgeStep, ok: Bool?, output: String?) {
        step.done = true
        step.failed = ok == false
        if let output, !output.isEmpty, step.kind == "command" || step.failed {
            step.output = String(output.prefix(1500))
        }
    }

    /// The running turn's steps. A "started" step adds a line; its "finished" twin (same id) closes it.
    nonisolated static func steps(live events: [ChatToolStepDTO]) -> [DeskForgeStep] {
        var result: [DeskForgeStep] = []
        for (index, event) in events.enumerated() {
            let id = event.id ?? "live-\(index)"
            if let at = result.firstIndex(where: { $0.id == id }) {
                if event.phase == "finished" { settle(&result[at], ok: event.ok, output: event.output) }
                if result[at].summary.isEmpty { result[at].summary = event.summary ?? "" }
                continue
            }
            var step = DeskForgeStep(id: id, name: event.name ?? "", kind: DeskForgeWire.stepKind(event.name),
                                     summary: event.summary ?? "")
            if event.phase == "finished" { settle(&step, ok: event.ok, output: event.output) }
            result.append(step)
        }
        return result
    }

    /// A saved run's steps. Older timelines carry no call id: a finish closes the first open call of its name.
    nonisolated static func steps(saved events: [DeskForgeRunStepDTO]) -> [DeskForgeStep] {
        var result: [DeskForgeStep] = []
        for (index, event) in events.enumerated() {
            let name = event.name ?? ""
            if event.kind == "tool_started" {
                result.append(DeskForgeStep(id: "saved-\(index)", name: name, kind: DeskForgeWire.stepKind(name),
                                            summary: DeskForgeWire.target(event.detail)))
            } else if event.kind == "tool_finished" {
                if let at = result.firstIndex(where: { !$0.done && $0.name == name }) {
                    settle(&result[at], ok: event.ok, output: event.detail)
                } else {
                    var step = DeskForgeStep(id: "saved-\(index)", name: name, kind: DeskForgeWire.stepKind(name), summary: "")
                    settle(&step, ok: event.ok, output: event.detail)
                    result.append(step)
                }
            }
        }
        return result
    }

    nonisolated static func runTimes(_ rows: [DeskForgeRunRowDTO]) -> [String: DeskForgeRunTime] {
        var result: [String: DeskForgeRunTime] = [:]
        for row in rows where row.surface == nil || row.surface == "chat" {
            guard let start = row.startedAt else { continue }
            result[row.id] = DeskForgeRunTime(start: start, end: row.endedAt)
        }
        return result
    }

    nonisolated static func checkpoints(_ rows: [DeskForgeCheckpointDTO]) -> [DeskForgeCheckpoint] {
        rows.compactMap { row in
            guard let created = row.created else { return nil }
            let changes = (row.roots ?? []).flatMap { $0.changes ?? [] }
            var files: [String] = []
            for change in changes {
                if let path = change.path, !files.contains(path) { files.append(path) }
            }
            return DeskForgeCheckpoint(
                id: row.id, created: created, finished: row.finished, changed: row.status == "changed",
                overlap: row.overlap ?? false, files: files,
                restored: changes.filter { $0.restoredAt != nil }.count, changes: changes.count)
        }
    }

    /// A checkpoint starts inside its turn's run and ends before the run does. Matched by that, never by
    /// "the newest", so Undo is always for the turn it sits under.
    nonisolated static func checkpoint(for runID: String, times: [String: DeskForgeRunTime],
                                       in list: [DeskForgeCheckpoint]) -> DeskForgeCheckpoint? {
        guard let time = times[runID], let end = time.end else { return nil }
        return list.first { point in
            guard let finished = point.finished else { return false }
            return point.created >= time.start && point.created <= end && finished <= end
        }
    }

    /// The choice the phone may send: allow once, or deny. Standing grants are given on the desktop.
    nonisolated static func onceChoice(_ request: ChatPermissionDTO?, allow: Bool) -> String? {
        (request?.choices ?? []).first { choice in
            (choice.behavior == "allow") == allow && (allow ? true : choice.behavior == "deny")
                && (choice.scope ?? "once") == "once" && !(choice.id ?? "").isEmpty
        }?.id
    }

    /// A project's history in the repo screen's own shape.
    nonisolated static func repo(_ git: DeskForgeGitDTO?) -> RepoStats? {
        guard let git, let life = git.lifespan, git.state == "ok" || git.state == "empty" else { return nil }
        func day(_ seconds: Double?) -> String {
            guard let seconds else { return "none" }
            return Date(timeIntervalSince1970: seconds).formatted(.dateTime.month(.abbreviated).day().year())
        }
        let colors: [UInt32] = [Palette.botPowder, Palette.botRose, Palette.botSand, Palette.botSage, Palette.botLilac]
        let total = (git.languages ?? []).reduce(0.0) { $0 + max(0, $1.bytes ?? 0) }
        var languages: [LanguageShare] = []
        for (index, language) in (git.languages ?? []).enumerated() {
            guard let name = language.name, !name.isEmpty, total > 0, !languages.contains(where: { $0.name == name }) else { continue }
            languages.append(LanguageShare(name: name, percent: max(0, language.bytes ?? 0) / total * 100,
                                           colorHex: colors[index % colors.count]))
        }
        var rhythm = git.rhythm ?? []
        if rhythm.count != 7 || rhythm.contains(where: { $0.count != 24 }) {
            rhythm = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        }
        func rows(_ list: [DeskForgeRankDTO]?, name: (DeskForgeRankDTO) -> String?) -> [RankedRow] {
            var result: [RankedRow] = []
            for item in list ?? [] {
                guard let text = name(item), !text.isEmpty, !result.contains(where: { $0.name == text }) else { continue }
                result.append(RankedRow(name: text, commits: item.commits ?? 0, added: item.added ?? 0, removed: item.removed ?? 0))
            }
            return result
        }
        return RepoStats(
            commits: life.commits ?? 0, commitsDelta: life.delta?.commits ?? 0,
            contributors: life.contributors ?? 0, contributorsDelta: life.delta?.contributors ?? 0,
            added: life.added ?? 0, addedDelta: life.delta?.added ?? 0,
            removed: life.removed ?? 0, removedDelta: life.delta?.removed ?? 0,
            ageDays: life.ageDays ?? 0, first: day(life.firstCommit), latest: day(life.lastCommit),
            history: (life.buckets ?? []).map { $0.commits ?? 0 },
            historyLabel: life.bucket == "monthly" ? "By month" : "By week",
            languages: languages, rhythm: rhythm,
            files: rows(git.hotspots) { $0.path }, people: rows(git.contributors) { $0.name })
    }

    // MARK: Reading the desktop

    /// One read. It answers `.fresh` only when it is still the newest read of its kind, for the desktop it
    /// was sent to, and no change finished while it was on its way (then it is read again). A cancelled
    /// read is not an error: it changes nothing.
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
                guard writes == writeSerial else { continue }
                return .fresh(value)
            } catch {
                if error is CancellationError || Task.isCancelled { return .stale }
                Connection.shared.note(error)
                guard stillLive(account), reads[key] == serial else { return .stale }
                var missing = false
                if case .server(status: 404, _) = error as? APIError { missing = true }
                return .failed(error.plainWords, missing: missing)
            }
        }
        return .stale
    }

    /// Desktop home and Forge Home: the counts, then (admin accounts) projects, sessions, apps and activity.
    func loadHome() async {
        guard on else { return }
        follow()
        let account = self.account
        if homeLoad != .loaded { homeLoad = .loading }
        await Self.waitWhileConnecting()
        guard stillLive(account) else { return }
        if case .fresh(let home) = await read("counts", account, { try await $0.phoneHome() }) { homeCounts = home }
        guard stillLive(account) else { return }
        guard isAdmin else {
            homeLoad = .loaded
            return
        }
        switch await read("projects", account, { try await $0.deskForgeProjects() }) {
        case .stale:
            return
        case .failed(let why, _):
            if homeLoad != .loaded { homeLoad = .failed("Your Forge projects could not be read. " + why) }
            return
        case .fresh(let list):
            projectList = list.items.map(Self.makeProject)
            skippedRows = list.skipped
        }
        var rows: [DeskForgeSession] = []
        for project in projectList.prefix(20) {
            let projectID = project.id
            switch await read("sessions:" + projectID, account, { try await $0.deskForgeProjectSessions(projectID) }) {
            case .stale:
                return
            case .failed(let why, _):
                if homeLoad != .loaded {
                    homeLoad = .failed("Your Forge sessions could not be read. " + why)
                    return
                }
                rows += sessionList.filter { $0.projectID == projectID }
            case .fresh(let list):
                rows += list.items.compactMap {
                    Self.makeSession(id: $0.id, title: $0.title, updatedAt: $0.updatedAt, endpointID: $0.modelEndpointId, forge: $0.forge)
                }
            }
        }
        sessionList = rows.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        homeLoad = .loaded
        if case .fresh(let list) = await read("models", account, { try await $0.modelChoices() }) { modelList = list }
        if case .fresh(let activity) = await read("activity", account, { try await $0.deskForgeActivity() }) {
            dayList = activity.days ?? []
        }
        await readRuns()
        await readApps()
    }

    /// The light read while Desktop home is in front: the counts, the running turns and the apps.
    func refreshHome() async {
        guard on else { return }
        follow()
        // Not read yet (a first read that failed, was overtaken or was cancelled): read it all.
        guard homeLoad == .loaded else {
            await loadHome()
            return
        }
        let account = self.account
        if case .fresh(let home) = await read("counts", account, { try await $0.phoneHome() }) { homeCounts = home }
        guard stillLive(account), isAdmin else { return }
        await readRuns()
        await readApps()
    }

    /// Every running turn (and the ones that just ended), as the desktop has them now.
    @discardableResult
    func readRuns() async -> Bool {
        guard on, isAdmin else { return false }
        follow()
        let account = self.account
        guard case .fresh(let packet) = await read("runs", account, { try await $0.chatSnapshot() }) else { return false }
        runMap = packet.runs ?? [:]
        for id in Array(pendingSends.keys) { settlePending(id) }
        // The desktop was read after every answer sent so far: a request still listed is still waiting.
        unsettledAnswers = []
        return true
    }

    @discardableResult
    func readApps() async -> Bool {
        guard on, isAdmin else { return false }
        follow()
        let account = self.account
        guard case .fresh(let list) = await read("apps", account, { try await $0.deskForgeAppsRunning() }) else { return false }
        appList = list.items.compactMap { app in
            guard let sessionID = app.sessionId, app.running == true, let port = app.port else { return nil }
            return DeskForgeApp(sessionID: sessionID, projectID: app.projectId ?? "", port: port,
                                command: app.command ?? "", ready: app.ready ?? false)
        }
        return true
    }

    @discardableResult
    private func readProjects() async -> Bool {
        guard on, isAdmin else { return false }
        let account = self.account
        guard case .fresh(let list) = await read("projects", account, { try await $0.deskForgeProjects() }) else { return false }
        projectList = list.items.map(Self.makeProject)
        skippedRows = list.skipped
        sessionList.removeAll { session in !projectList.contains { $0.id == session.projectID } }
        return true
    }

    /// The branches a session can work on, for "Existing branch".
    func loadBranches(_ projectID: String) async {
        guard on, isAdmin else { return }
        follow()
        let account = self.account
        if case .fresh(let list) = await read("branches:" + projectID, account, { try await $0.deskForgeProjectBranches(projectID) }) {
            branchMap[projectID] = list.items
        }
    }

    /// One project's history again, for the repo screen.
    func loadSummary(_ projectID: String) async {
        guard on, isAdmin else { return }
        follow()
        let account = self.account
        if case .fresh(let git) = await read("summary:" + projectID, account, { try await $0.deskForgeProjectSummary(projectID) }),
           let index = projectList.firstIndex(where: { $0.id == projectID }) {
            projectList[index].git = git
        }
    }

    private func edit(_ id: String, _ change: (inout DeskForgeDetail) -> Void) {
        var detail = detailMap[id] ?? DeskForgeDetail()
        change(&detail)
        detailMap[id] = detail
    }

    private func show(_ dto: DeskForgeSessionDTO) {
        let id = dto.id
        let name = modelName(dto.modelEndpointId)
        edit(id) { detail in
            detail.load = .loaded
            detail.missing = false
            detail.title = dto.title ?? ""
            detail.projectID = dto.forge?.projectId ?? ""
            detail.branch = dto.forge?.isolation == "in_place" ? nil : dto.forge?.branch
            detail.baseBranch = dto.forge?.baseBranch ?? ""
            detail.mode = dto.forge?.mode == "plan" ? .plan : .build
            detail.ended = dto.forge?.removed ?? false
            detail.fullAccess = dto.permissionMode == "auto"
            detail.endpointID = dto.modelEndpointId
            detail.modelOverride = dto.modelOverride
            detail.effort = dto.modelEffort
            detail.workspace = dto.workspaceDir ?? dto.forge?.worktree ?? ""
            detail.turns = Self.turns(dto.messages?.items ?? [], modelName: name)
            detail.skippedMessages = dto.messages?.skipped ?? 0
        }
        settlePending(id)
        guard let row = Self.makeSession(id: id, title: dto.title, updatedAt: dto.updatedAt, endpointID: dto.modelEndpointId, forge: dto.forge) else { return }
        if let index = sessionList.firstIndex(where: { $0.id == id }) {
            sessionList[index] = row
        } else {
            sessionList.insert(row, at: 0)
        }
    }

    /// One session with its turns. Answers true only when the screen now shows what the desktop has.
    @discardableResult
    func loadSession(_ id: String) async -> Bool {
        guard on, isAdmin else { return false }
        follow()
        let account = self.account
        if detailMap[id]?.load != .loaded { edit(id) { $0.load = .loading } }
        await Self.waitWhileConnecting()
        guard stillLive(account) else { return false }
        if modelList.isEmpty, case .fresh(let list) = await read("models", account, { try await $0.modelChoices() }) {
            modelList = list
        }
        switch await read("session:" + id, account, { try await $0.deskForgeSession(id) }) {
        case .stale:
            return false
        case .failed(let why, let missing):
            edit(id) { detail in
                if missing {
                    detail.missing = true
                    detail.load = .failed("This session is not on your desktop any more.")
                } else if detail.load != .loaded {
                    detail.load = .failed("This session could not be read. " + why)
                }
            }
            return false
        case .fresh(let dto):
            show(dto)
        }
        // Which run each turn was, and what it changed, for Undo. Without them the turns still show.
        if case .fresh(let rows) = await read("runrows:" + id, account, { try await $0.deskForgeRuns(sessionID: id) }) {
            edit(id) { $0.runTimes = Self.runTimes(rows.items) }
        }
        await readCheckpoints(id)
        await readRuns()
        await readApps()
        return stillLive(account)
    }

    @discardableResult
    private func readCheckpoints(_ id: String) async -> Bool {
        let account = self.account
        guard case .fresh(let points) = await read("checkpoints:" + id, account, { try await $0.deskForgeCheckpoints(id) }) else { return false }
        edit(id) { $0.checkpoints = Self.checkpoints(points.items) }
        return true
    }

    /// While a session is on screen: read the running turns, and the session again when a turn began or ended.
    func pollSession(_ id: String) async {
        guard on, isAdmin else { return }
        let before = runSignature(id)
        guard await readRuns() else { return }
        polls += 1
        if runSignature(id) != before {
            await loadSession(id)
        } else if polls % 5 == 0 {
            await readApps()
        }
    }

    /// A saved turn's steps, read once when its work is opened.
    func loadSteps(_ id: String, runID: String) async {
        guard on, isAdmin, detailMap[id]?.steps[runID] == nil else { return }
        follow()
        let account = self.account
        switch await read("run:" + runID, account, { try await $0.deskForgeRun(runID) }) {
        case .fresh(let run):
            edit(id) { detail in
                detail.steps[runID] = Self.steps(saved: run.steps?.items ?? [])
                detail.stepsUnread.remove(runID)
            }
        case .failed:
            edit(id) { $0.stepsUnread.insert(runID) }
        case .stale:
            break
        }
    }

    // MARK: Changing the desktop

    /// The desktop refused the request, so it certainly did not do it. Anything else (not reached, timed out,
    /// an answer this app could not read, a server error, a cancelled wait) may have come after it did.
    private static func refused(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
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

    /// Send one change, once. Reads that were on their way when it ended are read again.
    private func attempt<Value: Sendable>(_ account: String,
                                          _ send: (APIClient) async throws -> Value) async -> DeskForgeSent<Value> {
        do {
            guard let client = Connection.shared.client else { throw APIError.notPaired }
            let value = try await send(client)
            writeSerial += 1
            return stillLive(account) ? .ok(value) : .moved
        } catch {
            writeSerial += 1
            Connection.shared.note(error)
            guard stillLive(account) else { return .moved }
            return Self.refused(error) ? .refused(error.plainWords) : .lost(error.plainWords)
        }
    }

    private static func unchecked(_ what: String, _ why: String) -> String {
        "Your desktop did not confirm \(what), and it could not be read to check. Look again in a moment before trying again. " + why
    }

    /// Start a session: make it on the desktop, then send the task as its first message.
    /// Making it has no request id, so it is sent once. After a lost answer the desktop may still be making it
    /// (its worktree can take longer than the phone waits), so the project's sessions are read again for about
    /// 90 seconds, here in the store, and Start stays off for this exact start. It is never sent twice.
    /// Answers the session's id when one exists, even if the task could not be sent.
    func startSession(_ start: DeskForgeStart) async -> (id: String?, outcome: DeskForgeOutcome) {
        if isChecking(start) { return (nil, .busy) }
        guard let account = begin("start") else { return (nil, .busy) }
        defer { finish("start", account) }
        let projectID = start.projectID
        // Only sessions that were really read can prove that one is new.
        guard case .fresh(let known) = await read("sessions:" + projectID, account, { try await $0.deskForgeProjectSessions(projectID) }) else {
            return (nil, .refused("Your sessions could not be read first, so nothing was started. Try again."))
        }
        let before = Set(known.items.map(\.id))
        let task = start.task.trimmingCharacters(in: .whitespacesAndNewlines)
        var made: String?
        switch await attempt(account, {
            try await $0.deskForgeSessionCreate(projectId: projectID, task: task, endpointId: start.endpointID,
                                                mode: start.mode, isolation: start.isolation, branch: start.branch)
        }) {
        case .moved:
            return (nil, .refused(Self.desktopChanged))
        case .refused(let why):
            return (nil, .refused("No session was started. " + why))
        case .ok(let dto):
            show(dto)
            made = dto.id
        case .lost:
            if case .fresh(let now) = await read("sessions:" + projectID, account, { try await $0.deskForgeProjectSessions(projectID) }),
               let found = Self.newSession(in: now.items, before: before, task: task) {
                adopt(found)
                made = found.id
            } else {
                // Not there yet does not mean it will not be: keep reading, and keep Start off for this task.
                watchStart(start, before: before, account: account)
                return (nil, .unconfirmed(Self.startChecking))
            }
        }
        guard let id = made else { return (nil, .refused("No session was started.")) }
        // The task goes as the session's first message, under its own request id.
        let sent = await send(task, to: id)
        if sent == .done { return (id, .done) }
        draftMap[id] = task
        let line = "The session was made, but your task was not sent. It is in the box below. " + (sent.line ?? "")
        noteMap[id] = line
        return (id, .unconfirmed(line))
    }

    private static let startChecking = "Your desktop did not confirm the new session, and this phone is checking. Start stays off for this task until it knows."

    /// A session that was not there before the start and carries this task's title.
    private nonisolated static func newSession(in rows: [DeskForgeSessionRowDTO], before: Set<String>, task: String) -> DeskForgeSessionRowDTO? {
        rows.first { row in
            !before.contains(row.id) && !(row.title ?? "").isEmpty && (row.title ?? "").prefix(60) == task.prefix(60)
        }
    }

    private func adopt(_ found: DeskForgeSessionRowDTO) {
        if let row = Self.makeSession(id: found.id, title: found.title, updatedAt: found.updatedAt, endpointID: found.modelEndpointId, forge: found.forge),
           !sessionList.contains(where: { $0.id == row.id }) {
            sessionList.insert(row, at: 0)
        }
    }

    static func startKey(_ start: DeskForgeStart) -> String {
        [start.projectID, start.branch ?? "", start.task.trimmingCharacters(in: .whitespacesAndNewlines)].joined(separator: "|")
    }

    /// True while the phone is still checking whether the desktop made the session for this start.
    func isChecking(_ start: DeskForgeStart?) -> Bool {
        guard current, let start, let phase = startChecks[Self.startKey(start)]?.phase else { return false }
        switch phase {
        // Found: the session exists, so the same task must be opened there, never started again.
        case .checking, .found: return true
        case .over: return false
        }
    }

    /// What to say about a start whose answer was lost, or nil when there is nothing to say.
    var startNotice: DeskForgeStartNotice? {
        guard current else { return nil }
        if startChecks.values.contains(where: { $0.phase == .checking }) {
            return DeskForgeStartNotice(text: Self.startChecking, sessionID: nil, checking: true)
        }
        // A found session is shown before an ended check, so it is never cleared unseen.
        for check in startChecks.values {
            if case .found(let id) = check.phase {
                return DeskForgeStartNotice(text: "Your desktop made the session after all. Your task is in its box, not sent yet.", sessionID: id, checking: false)
            }
        }
        for check in startChecks.values {
            if case .over(let checked) = check.phase {
                let text = checked
                    ? "This phone did not see a new session for this task. It may still be in the making on your desktop. Check this project's sessions before you start again."
                    : "This phone could not read your desktop to check. Look at this project's sessions in Kairos on your desktop before you start again."
                return DeskForgeStartNotice(text: text, sessionID: nil, checking: false)
            }
        }
        return nil
    }

    /// Clears the one notice on screen: a found session first, else one ended check. Never the others.
    func clearStartNotice() {
        if let key = startChecks.first(where: { if case .found = $0.value.phase { return true } else { return false } })?.key {
            startChecks[key] = nil
            return
        }
        if let key = startChecks.first(where: { if case .over = $0.value.phase { return true } else { return false } })?.key {
            startChecks[key] = nil
        }
    }

    private func watchStart(_ start: DeskForgeStart, before: Set<String>, account: String) {
        let key = Self.startKey(start)
        let projectID = start.projectID
        let task = start.task.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ended checks go; a found session stays until the person opens it.
        startChecks = startChecks.filter { if case .over = $0.value.phase { return false } else { return true } }
        startChecks[key] = DeskForgeStartCheck(start: start, phase: .checking)
        startTasks[key]?.cancel()
        startTasks[key] = Task { [weak self] in
            guard let self else { return }
            let end = Date().addingTimeInterval(90)
            var phase: DeskForgeStartPhase = .over(checked: false)
            while Date() < end {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { return }
                if !self.stillLive(account) {
                    self.startChecks[key]?.phase = .over(checked: false)
                    self.startTasks[key] = nil
                    return
                }
                switch await self.read("sessions:" + projectID, account, { try await $0.deskForgeProjectSessions(projectID) }) {
                case .fresh(let now):
                    if let found = Self.newSession(in: now.items, before: before, task: task) {
                        self.adopt(found)
                        self.draftMap[found.id] = task
                        self.noteMap[found.id] = "The session was made, but your task was not sent. It is in the box below."
                        phase = .found(found.id)
                    } else {
                        phase = .over(checked: true)
                    }
                case .failed:
                    phase = .over(checked: false)
                case .stale:
                    if Task.isCancelled { return }
                }
                if case .found = phase { break }
            }
            if Task.isCancelled { return }
            if !self.stillLive(account) { phase = .over(checked: false) }
            self.startChecks[key]?.phase = phase
            self.startTasks[key] = nil
        }
    }

    /// The kept request id belongs to ONE send. Once a read of the desktop shows that message's turn it is
    /// dropped, so a later new message with the same words gets a new id and really runs.
    private func settlePending(_ id: String) {
        guard let pending = pendingSends[id], !busyKeys.contains("send:" + id) else { return }
        var arrived = false
        if let run = runMap[id], let turnID = run.turnId, turnID != pending.turnID, run.prompt == pending.text {
            arrived = true
        } else if let turns = detailMap[id]?.turns, detailMap[id]?.load == .loaded, turns.count > pending.turns,
                  turns.last(where: { !$0.prompt.isEmpty })?.prompt == pending.text {
            arrived = true
        }
        guard arrived else { return }
        pendingSends[id] = nil
        // The screen takes these words out of its box, so they cannot be sent a second time by mistake.
        settledMap[id] = pending.text
        noteMap[id] = "Your desktop got this message."
    }

    /// Send a message to a session. One request id per message: sending the same words again reuses it, and the
    /// desktop then answers the turn it already started instead of running the message twice.
    func send(_ text: String, to id: String) async -> DeskForgeOutcome {
        let key = "send:" + id
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        let requestID: String
        if let pending = pendingSends[id], pending.text == text {
            requestID = pending.id
        } else {
            requestID = UUID().uuidString
            pendingSends[id] = (text, requestID, detailMap[id]?.turns.count ?? 0, runMap[id]?.turnId)
        }
        let turnsBefore = detailMap[id]?.turns.count ?? 0
        switch await attempt(account, {
            try await $0.chatStart(sessionId: id, message: text, attachmentIds: [], requestId: requestID)
        }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            pendingSends[id] = nil
            noteMap[id] = nil
            await loadSession(id)
            return .done
        case .refused(let why):
            pendingSends[id] = nil
            return .refused("Your message was not sent. " + why)
        case .lost(let why):
            let sawRuns = await readRuns()
            if sawRuns, let run = runMap[id], run.status == "processing", run.prompt == text {
                pendingSends[id] = nil
                await loadSession(id)
                return .done
            }
            let sawSession = await loadSession(id)
            if sawSession, let turns = detailMap[id]?.turns, turns.count > turnsBefore,
               turns.last(where: { !$0.prompt.isEmpty })?.prompt == text {
                pendingSends[id] = nil
                return .done
            }
            let safe = " Your text is still in the box. Sending these same words again is safe: your desktop runs one message once. "
            if sawRuns && sawSession {
                return .unconfirmed("Your desktop did not confirm this message, and it is not in the session." + safe + why)
            }
            return .unconfirmed("Your desktop did not confirm this message, and the session could not be read to check." + safe + why)
        }
    }

    /// Allow once, or deny, a request the agent is waiting on.
    func answer(_ request: ChatPermissionDTO, allow: Bool, in id: String) async -> DeskForgeOutcome {
        guard let requestID = request.id, let choice = Self.onceChoice(request, allow: allow) else {
            return .refused("Answer this one in Kairos on your desktop.")
        }
        let key = "answer:" + requestID
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.permissionAnswer(requestID, choice: choice) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            await readRuns()
            return .done
        case .refused(let why):
            await readRuns()
            return .refused("Your answer was not taken. " + why)
        case .lost(let why):
            // Not confirmed: the card's buttons stay off until the desktop has been read again.
            unsettledAnswers.insert(requestID)
            guard await readRuns() else {
                return .unconfirmed(Self.unchecked("your answer", why))
            }
            if runMap[id]?.permission?.id == requestID {
                return .unconfirmed("Your desktop did not confirm your answer and is still waiting. You can answer again. " + why)
            }
            return .unconfirmed("Your desktop did not confirm your answer. The request is no longer waiting there, and this shows what it has now. " + why)
        }
    }

    /// Stop the running turn. The turn is named, so a late Stop never ends the next one.
    func stop(_ id: String) async -> DeskForgeOutcome {
        guard let turnID = runMap[id]?.turnId, runMap[id]?.status == "processing" else {
            await readRuns()
            return .done
        }
        let key = "stop:" + id
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.chatStop(sessionId: id, turnId: turnID) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            await readRuns()
            return .done
        case .refused(let why):
            await readRuns()
            return .refused("The turn was not stopped. " + why)
        case .lost(let why):
            guard await readRuns() else { return .unconfirmed(Self.unchecked("Stop", why)) }
            if runMap[id]?.status != "processing" || runMap[id]?.stopping == true || runMap[id]?.turnId != turnID { return .done }
            return .unconfirmed("Your desktop did not confirm Stop, and the turn is still running there. Stop it again. " + why)
        }
    }

    /// Build or Plan. The desktop refuses while a turn runs.
    func setMode(_ id: String, _ mode: ForgeMode) async -> DeskForgeOutcome {
        let key = "mode:" + id
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        let sent = mode == .plan ? "plan" : "build"
        switch await attempt(account, { try await $0.deskForgeSetMode(id, mode: sent) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok(let dto):
            show(dto)
            return .done
        case .refused(let why):
            return .refused("The mode was not changed. " + why)
        case .lost(let why):
            guard await loadSession(id) else { return .unconfirmed(Self.unchecked("the mode", why)) }
            if detailMap[id]?.mode == mode { return .done }
            return .unconfirmed("Your desktop did not confirm the mode, and it still has \(detailMap[id]?.mode.rawValue ?? "the old one"). " + why)
        }
    }

    /// Back to Supervised. The phone never gives Full access.
    func setSupervised(_ id: String) async -> DeskForgeOutcome {
        let key = "access:" + id
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.chatSetPermissionMode(id, mode: "base") }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            await loadSession(id)
            return .done
        case .refused(let why):
            return .refused("The permission mode was not changed. " + why)
        case .lost(let why):
            guard await loadSession(id) else { return .unconfirmed(Self.unchecked("the permission mode", why)) }
            if detailMap[id]?.fullAccess == false { return .done }
            return .unconfirmed("Your desktop did not confirm the change, and this session still has Full access there. " + why)
        }
    }

    /// Switch the session to another model connection, on that connection's own default version and effort.
    func setModel(_ id: String, endpointID: String) async -> DeskForgeOutcome {
        let key = "model:" + id
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.chatSetModel(id, endpointId: endpointID, override: nil, effort: nil) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            await loadSession(id)
            return .done
        case .refused(let why):
            return .refused("The model was not changed. " + why)
        case .lost(let why):
            guard await loadSession(id) else { return .unconfirmed(Self.unchecked("the model", why)) }
            if detailMap[id]?.endpointID == endpointID { return .done }
            return .unconfirmed("Your desktop did not confirm the model, and the session still uses \(modelName(detailMap[id]?.endpointID)). " + why)
        }
    }

    func rename(_ id: String, to title: String) async -> DeskForgeOutcome {
        let key = "rename:" + id
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.chatRename(id, title: title) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            await loadSession(id)
            return .done
        case .refused(let why):
            return .refused("The session was not renamed. " + why)
        case .lost(let why):
            guard await loadSession(id) else { return .unconfirmed(Self.unchecked("the new name", why)) }
            if detailMap[id]?.title == title { return .done }
            return .unconfirmed("Your desktop did not confirm the new name, and the session is still called \(detailMap[id]?.title ?? "its old name") there. " + why)
        }
    }

    /// Put back the files one turn changed. The desktop checks later edits first and puts back nothing on a conflict.
    func undo(_ id: String, checkpoint: String) async -> DeskForgeOutcome {
        let key = "undo:" + checkpoint
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.deskForgeUndo(id, checkpoint: checkpoint) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            await readCheckpoints(id)
            return .done
        case .refused(let why):
            await readCheckpoints(id)
            return .refused("Nothing was put back. " + why)
        case .lost(let why):
            guard await readCheckpoints(id) else { return .unconfirmed(Self.unchecked("the undo", why)) }
            if detailMap[id]?.checkpoints.first(where: { $0.id == checkpoint })?.undone == true { return .done }
            return .unconfirmed("Your desktop did not confirm the undo, and it does not show this turn's files as put back. " + why)
        }
    }

    /// End a session: "keep-branch" removes the worktree and keeps the branch, "discard" also deletes the branch
    /// and its changes. Ending has no request id, so after a lost answer the session is read, never ended again.
    func end(_ id: String, option: String) async -> DeskForgeOutcome {
        await close(id, what: "the end of this session") { client in
            try await client.deskForgeEnd(id, option: option, confirmed: option == "discard")
        }
    }

    /// Remove a session's worktree from a list (the Forge route, never the chat's own delete). The branch and
    /// the conversation are kept, and the desktop refuses when the worktree has uncommitted changes.
    func removeWorktree(_ id: String) async -> DeskForgeOutcome {
        await close(id, what: "removing the worktree") { client in
            try await client.deskForgeSessionRemove(id)
        }
    }

    private func close(_ id: String, what: String,
                       _ send: (APIClient) async throws -> DeskForgeEndDTO) async -> DeskForgeOutcome {
        let key = "end:" + id
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, send) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok(let result):
            if let warning = result.warning, !warning.isEmpty { noteMap[id] = warning }
            if !(await loadSession(id)), let index = sessionList.firstIndex(where: { $0.id == id }) {
                // The desktop said it ended; the row says so even if the session could not be read again.
                sessionList[index].ended = true
                edit(id) { $0.ended = true }
            }
            return .done
        case .refused(let why):
            return .refused("The session was not ended. " + why)
        case .lost(let why):
            guard await loadSession(id) else { return .unconfirmed(Self.unchecked(what, why)) }
            if detailMap[id]?.ended == true { return .done }
            return .unconfirmed("Your desktop did not confirm \(what), and the session is still open there. " + why)
        }
    }

    /// Take a project off the list. Its folder and files stay on the desktop.
    func removeProject(_ id: String) async -> DeskForgeOutcome {
        let key = "project:" + id
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.deskForgeProjectRemove(id) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            projectList.removeAll { $0.id == id }
            sessionList.removeAll { $0.projectID == id }
            return .done
        case .refused(let why):
            await readProjects()
            return .refused("The project was not removed. " + why)
        case .lost(let why):
            guard await readProjects() else { return .unconfirmed(Self.unchecked("removing the project", why)) }
            if !projectList.contains(where: { $0.id == id }) { return .done }
            return .unconfirmed("Your desktop did not confirm, and the project is still in its list. " + why)
        }
    }

    // MARK: Approval streams

    /// Start the project's saved app command in a session's folder. The desktop asks to approve a command it
    /// has not approved before; the request shows here exactly as it sent it.
    @discardableResult
    func startApp(_ id: String) -> Bool { runApproval(id, .app) }

    /// Merge the session's branch back and end it. The desktop asks to approve the merge first.
    /// Answers false when nothing was started, for example while another approval is still waiting.
    @discardableResult
    func endWithMerge(_ id: String) -> Bool { runApproval(id, .merge) }

    func dismissApproval(_ id: String) {
        if case .ended? = approvalMap[id]?.phase { approvalMap[id] = nil }
    }

    private func runApproval(_ id: String, _ kind: DeskForgeApproval.Kind) -> Bool {
        guard on, isAdmin else { return false }
        follow()
        guard streams[id] == nil else { return false }
        let account = self.account
        approvalMap[id] = DeskForgeApproval(kind: kind, phase: .waiting)
        streams[id] = Task { [weak self] in
            await self?.readApproval(id, kind, account)
            if let self, self.account == account { self.streams[id] = nil }
        }
        return true
    }

    /// The project's saved app command as the desktop has it now, or nil when it could not be read.
    func freshAppCommand(_ projectID: String) async -> String? {
        guard on, isAdmin else { return nil }
        guard await readProjects() else { return nil }
        return project(projectID)?.appCommand
    }

    /// Read one approval stream to its end. It is sent once: when it closes without a result, the desktop is
    /// read to see what happened, and the action is never started a second time from here.
    private func readApproval(_ id: String, _ kind: DeskForgeApproval.Kind, _ account: String) async {
        var done = false
        var refusal: String?
        var lost: String?
        do {
            guard let client = Connection.shared.client else { throw APIError.notPaired }
            let bytes: URLSession.AsyncBytes
            switch kind {
            case .app: bytes = try await client.deskForgeAppStart(id)
            case .merge: bytes = try await client.deskForgeEndWithMerge(id)
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
                    approvalMap[id]?.request = request
                    approvalMap[id]?.phase = .asking
                    approvalMap[id]?.note = nil
                }
            }
            if !done && refusal == nil { lost = "The connection closed before your desktop answered." }
        } catch {
            if !(error is CancellationError) { Connection.shared.note(error) }
            if Self.refused(error) { refusal = error.plainWords } else { lost = error.plainWords }
        }
        writeSerial += 1
        guard stillLive(account) else { return }
        approvalMap[id]?.request = nil
        approvalMap[id]?.note = nil
        let sentence: String
        switch kind {
        case .app:
            let read = await readApps()
            guard stillLive(account) else { return }
            let running = appList.contains { $0.sessionID == id }
            if done || (read && running) {
                sentence = "The app is running on your desktop."
            } else if let refusal {
                sentence = "The app was not started. " + refusal
            } else if read {
                sentence = "Your desktop did not confirm the start, and the app is not running there. " + (lost ?? "")
            } else {
                sentence = Self.unchecked("the start", lost ?? "")
            }
        case .merge:
            let read = await loadSession(id)
            guard stillLive(account) else { return }
            let ended = detailMap[id]?.ended == true
            if done || (read && ended) {
                if done, !read, let index = sessionList.firstIndex(where: { $0.id == id }) {
                    sessionList[index].ended = true
                    edit(id) { $0.ended = true }
                }
                sentence = "Merged back, and the session has ended."
            } else if let refusal {
                sentence = "The session was not ended. " + refusal
            } else if read {
                sentence = "Your desktop did not confirm the merge, and the session is still open there. Check its branch on your desktop before merging again. " + (lost ?? "")
            } else {
                sentence = Self.unchecked("the merge", lost ?? "")
            }
        }
        approvalMap[id]?.phase = .ended(sentence)
    }

    /// Approve once, or cancel, the request an approval stream is showing. The stream itself then says how it
    /// ended, so a lost answer here is never taken for a yes or a no.
    func answerApproval(_ id: String, allow: Bool) async {
        guard current, approvalMap[id]?.phase == .asking, let request = approvalMap[id]?.request,
              let requestID = request.id, let choice = Self.onceChoice(request, allow: allow) else { return }
        let account = self.account
        approvalMap[id]?.phase = .answering
        approvalMap[id]?.note = nil
        do {
            guard let client = Connection.shared.client else { throw APIError.notPaired }
            _ = try await client.permissionAnswer(requestID, choice: choice)
            guard stillLive(account) else { return }
            if approvalMap[id]?.phase == .answering { approvalMap[id]?.phase = .finishing }
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), approvalMap[id]?.phase == .answering else { return }
            approvalMap[id]?.phase = .asking
            approvalMap[id]?.note = Self.refused(error)
                ? "Your answer was not taken. " + error.plainWords
                : "Your desktop did not confirm your answer. If it took it, this finishes by itself. If not, answer again. " + error.plainWords
        }
    }
}

// MARK: - Small shared views

/// One quiet line on a Forge screen: loading, or what failed, with one plain action.
struct DeskForgeLine: View {
    let text: String
    var action: String? = nil
    var perform: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let action, let perform {
                Button {
                    Haptics.tap()
                    perform()
                } label: {
                    Text(action)
                        .font(KFont.ui(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.goldText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .kCard(radius: 16)
    }
}

/// What a Forge screen shows in place of its content while paired and not readable yet:
/// the admin line for a member account, the loading note, or what failed with Try again.
struct DeskForgeGate: View {
    let load: DeskForgeLoad
    var reading = "Reading Forge from your desktop."
    let retry: () -> Void

    var body: some View {
        if !DeskForgeLive.shared.isAdmin {
            DeskForgeLine(text: DeskForgeLive.adminLine)
        } else if case .failed(let why) = load {
            DeskForgeLine(text: why, action: "Try again", perform: retry)
        } else {
            DeskForgeLine(text: reading)
        }
    }
}

/// An action the desktop asks to approve (starting an app, merging back), drawn exactly as it was sent:
/// the tool's name, what it is aimed at, and the desktop's own description. Approve once, or cancel.
struct DeskForgeApprovalCard: View {
    let sessionID: String
    let approval: DeskForgeApproval
    @State private var live = DeskForgeLive.shared

    private var title: String { approval.kind == .app ? "Starting the app" : "Merging back" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch approval.phase {
            case .waiting:
                progress("Waiting for your desktop.")
            case .answering:
                progress("Sending your answer.")
            case .finishing:
                progress(approval.kind == .app ? "Approved. Waiting for the app to be ready." : "Approved. Merging on your desktop.")
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

/// A request's own words, as the desktop's own approval card draws them: the title, the tool, the target and
/// the description in full, then everything it asked for (its arguments). Text only, selectable, scrollable
/// when long, never shortened. Only the sign-in part of a remote address is left out (scheme://user:pass@host
/// shows as scheme://host).
struct DeskForgeRequestText: View {
    let request: ChatPermissionDTO

    /// `scheme://user:pass@host` as `scheme://host`. Nothing else is changed.
    static func hideSignIn(_ text: String) -> String {
        text.replacingOccurrences(of: "([A-Za-z][A-Za-z0-9+.-]*://)[^/\\s?#]*@", with: "$1", options: .regularExpression)
    }

    private static func foundation(_ value: JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let flag): return flag
        case .number(let number): return number
        case .string(let text): return text
        case .array(let list): return list.map { foundation($0) }
        case .object(let map): return map.mapValues { foundation($0) }
        }
    }

    /// The arguments as the desktop's card shows them: a string as it is, anything else as indented JSON.
    static func argumentsText(_ value: JSONValue?) -> String? {
        guard let value, !value.isNull else { return nil }
        if case .string(let text) = value { return text.isEmpty ? nil : text }
        let object = foundation(value)
        // A bare number or true/false is not a JSON document on its own: show it as it is.
        guard JSONSerialization.isValidJSONObject(object) else {
            if let number = object as? Double, number == number.rounded(), abs(number) < 1e15 { return String(Int64(number)) }
            return "\(object)"
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.hideSignIn(request.title ?? request.tool ?? "Allow this?"))
                .font(KFont.ui(17, .semibold))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let tool = request.tool, !tool.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Tool").font(KFont.ui(13, .medium)).foregroundStyle(Palette.inkFaint)
                    Text(tool).font(CodeFont.mono(12.5)).foregroundStyle(Palette.ink).textSelection(.enabled)
                }
            }
            if let description = request.description, !description.isEmpty {
                Text(Self.hideSignIn(description))
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let target = request.target, !target.isEmpty {
                DeskForgeScrollText(text: Self.hideSignIn(target))
            }
            if let arguments = Self.argumentsText(request.arguments) {
                Text("What it asked for").font(KFont.ui(13, .medium)).foregroundStyle(Palette.inkFaint)
                DeskForgeScrollText(text: Self.hideSignIn(arguments))
            }
        }
    }
}

/// A block of code-like text, whole and selectable. Short text takes its own height; long text scrolls inside.
struct DeskForgeScrollText: View {
    let text: String
    @State private var height: CGFloat = 60

    var body: some View {
        ScrollView(.vertical) {
            Text(text)
                .font(CodeFont.mono(12.5))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(height, 1), 240))
        .background(Palette.groundDeep.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
