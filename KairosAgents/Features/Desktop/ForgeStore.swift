import SwiftUI

/// What the Desktop tab and Forge read and change. The sample store works on made-up data;
/// the real one will read `/api/forge/...` on the person's desktop and keep the same shape.
protocol ForgeProviding: AnyObject {
    var pc: PCStatus { get }
    var projects: [ForgeProject] { get }
    var sessions: [ForgeSessionInfo] { get }
    var apps: [RunningApp] { get }
}

@Observable
final class ForgeStore: ForgeProviding {
    static let shared = ForgeStore()

    var pc = ForgeSample.pc
    var projects = ForgeSample.projects
    var sessions = ForgeSample.sessions
    var apps = ForgeSample.apps
    /// Which Forge Home widgets show. Saved on this phone.
    var widgets: Set<ForgeWidget> = ForgeStore.savedWidgets() {
        didSet { UserDefaults.standard.set(widgets.map(\.rawValue), forKey: "forgeWidgets") }
    }

    private static func savedWidgets() -> Set<ForgeWidget> {
        guard let saved = UserDefaults.standard.stringArray(forKey: "forgeWidgets") else { return Set(ForgeWidget.allCases) }
        return Set(saved.compactMap(ForgeWidget.init(rawValue:)))
    }
    var repoProjectID = "p-shop"
    /// Set by the gold + on the Desktop tab (shell) or by any "New session" control.
    var composeRequested = false
    var waking = false

    var waitingCount: Int { sessions.filter { $0.state == .needsYou && !$0.ended }.count }
    var workingCount: Int { sessions.filter { $0.state == .working && !$0.ended }.count }
    var liveSessions: [ForgeSessionInfo] { sessions.filter { !$0.ended } }

    func project(_ id: String) -> ForgeProject? { projects.first { $0.id == id } }
    func session(_ id: String) -> ForgeSessionInfo? { sessions.first { $0.id == id } }
    func index(_ id: String) -> Int? { sessions.firstIndex { $0.id == id } }
    func apps(for sessionID: String) -> [RunningApp] { apps.filter { $0.sessionID == sessionID } }

    func sessions(in projectID: String) -> [ForgeSessionInfo] {
        sessions.filter { $0.projectID == projectID && !$0.ended }.sorted { rank($0.state) < rank($1.state) }
    }

    private func rank(_ state: ForgeState) -> Int {
        switch state {
        case .needsYou: 0
        case .working: 1
        case .done: 2
        case .idle: 3
        }
    }

    func update(_ id: String, _ change: (inout ForgeSessionInfo) -> Void) {
        guard let i = index(id) else { return }
        change(&sessions[i])
    }

    // MARK: PC

    func wake() {
        waking = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(Motion.snappy) {
                pc.asleep = false
                pc.online = true
                waking = false
            }
            Haptics.success()
        }
    }

    // MARK: Sessions

    @discardableResult
    func startSession(project: String, task: String, mode: ForgeMode, location: ForgeLocation, branch: String?, model: String, effort: String) -> String {
        let id = "s-\(UUID().uuidString.prefix(6))"
        let title = String(task.prefix(40))
        let place: String?
        switch location {
        case .worktree: place = "kairos/" + title.lowercased().split(separator: " ").prefix(3).joined(separator: "-")
        case .branch: place = branch
        case .inPlace: place = nil
        }
        let session = ForgeSessionInfo(
            id: id, title: title, projectID: project, branch: place, mode: mode, access: .supervised,
            agent: "Claude Code", model: model, effort: effort, state: .working, updated: "now", today: true,
            turns: [ForgeTurn(id: "t1", prompt: task, reply: "", steps: [ForgeStep(kind: .read, summary: "Reading the project")], duration: "Working 0s", running: true)],
            changes: [],
            git: GitInfo(branch: place ?? "main", upstream: nil, ahead: 0, behind: 0, staged: [], unstaged: [], branches: ["main"])
        )
        sessions.insert(session, at: 0)
        finishTurnLater(id)
        return id
    }

    func send(_ text: String, to id: String) {
        guard let session = session(id) else { return }
        if session.state == .working {
            update(id) { $0.queued.append(text) }
            return
        }
        update(id) {
            $0.turns.append(ForgeTurn(id: UUID().uuidString, prompt: text, reply: "", steps: [ForgeStep(kind: .read, summary: "Reading the files it needs")], duration: "Working 0s", running: true))
            $0.state = .working
            $0.updated = "now"
        }
        finishTurnLater(id)
    }

    private func finishTurnLater(_ id: String) {
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(Motion.snappy) {
                update(id) { session in
                    guard let last = session.turns.indices.last else { return }
                    session.turns[last].running = false
                    session.turns[last].duration = "Worked 2s"
                    session.turns[last].reply = "This is sample data. Connect your desktop and the agent will do this for real."
                    if !session.queued.isEmpty {
                        let next = session.queued.removeFirst()
                        session.turns.append(ForgeTurn(id: UUID().uuidString, prompt: next, reply: "This is sample data. Queued messages run one after another.", steps: [], duration: "Worked 1s"))
                    }
                    session.state = .done
                }
            }
        }
    }

    func answer(_ id: String, allow: Bool) {
        update(id) { session in
            guard let i = session.turns.lastIndex(where: { $0.ask != nil }) else { return }
            session.turns[i].ask = nil
            session.turns[i].running = false
            if allow {
                session.turns[i].steps.append(ForgeStep(kind: .command, summary: "npm run build", output: "built in 2.1 s"))
                session.turns[i].reply = "Removed the old hero image and the build passes."
                session.turns[i].duration = "Worked 1m 02s"
            } else {
                session.turns[i].reply = "Understood. I left the image in place."
                session.turns[i].duration = "Stopped"
            }
            session.state = .done
            session.updated = "now"
        }
    }

    func stop(_ id: String) {
        update(id) { session in
            guard let last = session.turns.indices.last else { return }
            session.turns[last].running = false
            session.turns[last].duration = "Stopped"
            session.turns[last].ask = nil
            session.state = .idle
            session.background = nil
        }
    }

    func setReview(_ id: String, turn: String, _ review: TurnReview) {
        update(id) { session in
            guard let i = session.turns.firstIndex(where: { $0.id == turn }) else { return }
            session.turns[i].review = review
            if review == .undone {
                let files = Set(session.turns[i].files)
                session.changes.removeAll { files.contains($0.path) }
                session.git.unstaged.removeAll { files.contains($0) }
            }
        }
    }

    // MARK: Changes

    func revertFile(_ id: String, path: String) {
        update(id) { session in
            session.changes.removeAll { $0.path == path }
            session.git.unstaged.removeAll { $0 == path }
            session.git.staged.removeAll { $0 == path }
        }
    }

    func revertHunk(_ id: String, path: String, hunk: UUID) {
        update(id) { session in
            guard let f = session.changes.firstIndex(where: { $0.path == path }) else { return }
            session.changes[f].hunks.removeAll { $0.id == hunk }
            if session.changes[f].hunks.isEmpty {
                session.changes.remove(at: f)
                session.git.unstaged.removeAll { $0 == path }
            }
        }
    }

    // MARK: Git

    func stage(_ id: String, _ path: String, _ on: Bool) {
        update(id) { session in
            if on {
                session.git.unstaged.removeAll { $0 == path }
                if !session.git.staged.contains(path) { session.git.staged.append(path) }
            } else {
                session.git.staged.removeAll { $0 == path }
                if !session.git.unstaged.contains(path) { session.git.unstaged.append(path) }
            }
        }
    }

    func stageAll(_ id: String, _ on: Bool) {
        update(id) { session in
            if on {
                session.git.staged += session.git.unstaged
                session.git.unstaged = []
            } else {
                session.git.unstaged += session.git.staged
                session.git.staged = []
            }
        }
    }

    func commit(_ id: String) {
        update(id) { session in
            // Commits the staged files, or every change when nothing is staged.
            if session.git.staged.isEmpty { session.git.unstaged = [] } else { session.git.staged = [] }
            session.git.ahead += 1
        }
    }

    func push(_ id: String) {
        update(id) { session in
            if session.git.upstream == nil { session.git.upstream = "origin/" + session.git.branch }
            session.git.ahead = 0
        }
    }

    func pull(_ id: String) {
        update(id) { $0.git.behind = 0 }
    }

    func switchBranch(_ id: String, to branch: String) {
        update(id) { $0.git.branch = branch }
    }

    func createBranch(_ id: String, _ name: String) {
        update(id) { session in
            session.git.branches.append(name)
            session.git.branch = name
            session.git.upstream = nil
        }
    }

    // MARK: Ending

    func end(_ id: String, _ choice: ForgeEndChoice) {
        guard choice != .keepAndLeave else { return }
        update(id) { $0.ended = true }
        apps.removeAll { $0.sessionID == id }
    }

    // MARK: Apps

    func runApp(_ sessionID: String, command: String) {
        guard apps(for: sessionID).isEmpty, let session = session(sessionID) else { return }
        let port = 5173 + apps.count + 1
        apps.append(RunningApp(id: UUID().uuidString, port: port, sessionID: sessionID, title: session.title, command: command))
    }

    func stopApp(_ appID: String) {
        apps.removeAll { $0.id == appID }
    }
}
