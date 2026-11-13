import SwiftUI

/// Where a desktop read stands, for one plain sentence on screen.
nonisolated enum TasksLiveLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// The sample Tasks content, kept aside while the phone shows the paired desktop's.
struct TasksSampleStash {
    var cards: [WorkCard]
    var jobs: [ScheduledJob]
    var routines: [JobRoutine]
    var triggers: [TrigRule]
    var requests: [TrigRequest]
    var activity: [TasksActivityRun]
    var search: String
    var draft: JobDraft
    var draftError: JobDraftField?
}

/// The paired desktop behind Tasks (routes/task_routes.py): the work board and the scheduled tasks
/// (GET /api/tasks, one record each), their runs (GET /api/tasks/{id}/runs), the automation library
/// (GET /api/tasks/builtin) and every write the board and the routines make. Triggers and the brief stay
/// on the desktop for now and say so. Unpaired, nothing here runs and Tasks shows its samples.
extension TasksStore {

    /// A key that changes when the phone is paired or unpaired, the desktop comes back,
    /// or a different desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// Which desktop and which account the tasks belong to. Live tasks are only ever shown under this key.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Still showing the live tasks a request was sent for. Checked after every await before writing a result.
    private func stillLive(_ account: String) -> Bool {
        isLive && liveAccount == account && Self.accountKey == account
    }

    /// Move between the samples and the paired desktop to match the connection.
    func followConnection() {
        let wantLive = !Connection.shared.usesSampleData
        if wantLive && isLive && liveAccount != Self.accountKey {
            // Another desktop or account: nothing read from the last one may stay on screen.
            resetLive()
        }
        guard wantLive != isLive else { return }
        if wantLive {
            sampleStash = TasksSampleStash(cards: cards, jobs: jobs, routines: routines, triggers: triggers,
                                           requests: requests, activity: activity, search: search,
                                           draft: draft, draftError: draftError)
            search = ""
            draft = JobDraft()
            draftError = nil
            resetLive()
            isLive = true
        } else {
            clearLive()
            isLive = false
            let stash = sampleStash
            let sample = TasksSampleProvider()
            cards = stash?.cards ?? sample.loadCards()
            jobs = stash?.jobs ?? sample.loadJobs()
            routines = stash?.routines ?? sample.loadRoutines()
            triggers = stash?.triggers ?? sample.loadTriggers()
            requests = stash?.requests ?? sample.loadRequests()
            activity = stash?.activity ?? sample.loadActivity()
            search = stash?.search ?? ""
            draft = stash?.draft ?? JobDraft()
            draftError = stash?.draftError
            sampleStash = nil
        }
    }

    /// Every live card, task, run and load state goes, ready to read the current account's tasks.
    private func resetLive() {
        cards = []
        jobs = []
        routines = []
        triggers = []
        requests = []
        activity = []
        clearLive()
        liveAccount = Self.accountKey
    }

    private func clearLive() {
        boardLoad = .idle
        jobsLoad = .idle
        libraryLoad = .idle
        jobRunsFailed = false
        cardRunsLoad = [:]
        liveModels = []
        modelsKnown = false
        liveChannels = []
        agentNames = [:]
        agentsKnown = false
        busy = []
        starting = []
        problem = nil
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    // MARK: What the screens ask

    /// The board may draw its columns: unpaired, once read, or while showing what was read before.
    var boardReady: Bool { !isLive || boardLoad == .loaded || !cards.isEmpty }
    var jobsReady: Bool { !isLive || jobsLoad == .loaded || !jobs.isEmpty }
    var libraryReady: Bool { !isLive || libraryLoad == .loaded || !routines.isEmpty }

    /// Something is moving on the desktop, so the board and the routines are read again every few seconds.
    var needsWatching: Bool {
        isLive && (cards.contains { $0.column == .ready || $0.column == .running } || jobs.contains { $0.runningSince != nil })
    }

    /// A card's or task's controls wait while a write for it is on its way.
    func waits(_ id: String) -> Bool { busy.contains(id) || starting.contains(id) }

    /// The model menu's choices while paired: "" is Claude, then the desktop's models.
    var modelIDs: [String] { [""] + liveModels.map(\.id) }

    func modelLabel(_ id: String) -> String {
        if id.isEmpty { return TasksOptions.defaultModel }
        if let model = liveModels.first(where: { $0.id == id }) { return model.name ?? model.model ?? "A model" }
        return modelsKnown ? "A removed model" : "Its own model"
    }

    /// The delivery menu's choices while paired: "" is the Tasks tab, then the desktop's channels,
    /// then the current one if it is no longer set up.
    func channelIDs(keeping current: String = "") -> [String] {
        let ids = [""] + liveChannels.map(\.id)
        return current.isEmpty || ids.contains(current) ? ids : ids + [current]
    }

    func channelLabel(_ id: String) -> String {
        if id.isEmpty { return TasksOptions.tabOnly }
        guard let channel = liveChannels.first(where: { $0.id == id }) else { return "\(id) (not set up)" }
        let label = channel.label ?? id
        return channel.configured == false ? "\(label) (not configured)" : label
    }

    // MARK: Reading

    /// Load everything once, when it has not been read yet.
    func loadLiveIfNeeded() async {
        guard isLive else { return }
        switch boardLoad {
        case .idle, .failed: await loadLive()
        case .loading, .loaded: break
        }
    }

    /// Read the models, channels and bots for names, then every task and card, then the routines' runs
    /// and the automation library.
    func loadLive() async {
        guard isLive else { return }
        let account = liveAccount
        if boardLoad != .loaded { boardLoad = .loading }
        if jobsLoad != .loaded { jobsLoad = .loading }
        do {
            let client = try liveClient()
            let models = try? await client.modelChoices()
            guard stillLive(account) else { return }
            if let models {
                liveModels = models
                modelsKnown = true
            }
            let channels = try? await client.taskChannels()
            guard stillLive(account) else { return }
            if let channels { liveChannels = channels }
            let agents = try? await client.agentRoster()
            guard stillLive(account) else { return }
            if let agents {
                var names: [String: String] = [:]
                for agent in agents { names[agent.id] = (agent.name?.isEmpty == false ? agent.name : nil) ?? "A bot" }
                agentNames = names
                agentsKnown = true
            }
            let all = try await client.tasksList()
            guard stillLive(account) else { return }
            let ran = show(all)
            boardLoad = .loaded
            jobsLoad = .loaded
            await loadRuns(ran, account: account)
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            boardLoad = .failed("Your work board could not be read. " + error.plainWords)
            jobsLoad = .failed("Your routines could not be read. " + error.plainWords)
        }
        await loadLibrary()
    }

    /// Read the tasks and cards again (after a write, or while something runs). Runs are read again only
    /// for what just finished.
    func refreshTasks() async {
        guard isLive else { return }
        let account = liveAccount
        do {
            let all = try await liveClient().tasksList()
            guard stillLive(account) else { return }
            let before = Dictionary(jobs.map { ($0.id, $0.runningSince) }, uniquingKeysWith: { first, _ in first })
            let beforeCards = Dictionary(cards.map { ($0.id, $0.column) }, uniquingKeysWith: { first, _ in first })
            show(all)
            boardLoad = .loaded
            jobsLoad = .loaded
            let finishedJobs = jobs.filter { (before[$0.id] ?? nil) != nil && $0.runningSince == nil }.map(\.id)
            let finishedCards = cards.filter { beforeCards[$0.id] == .running && $0.column != .running && cardRunsLoad[$0.id] != nil }.map(\.id)
            await loadRuns(finishedJobs, account: account)
            for id in finishedCards { await loadCardRuns(id) }
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            boardLoad = .failed("Your work board could not be read again. " + error.plainWords)
            jobsLoad = .failed("Your routines could not be read again. " + error.plainWords)
        }
    }

    /// Put the desktop's records on screen. Answers the scheduled tasks that have run, for their history.
    @discardableResult
    private func show(_ all: [TaskRecordDTO]) -> [String] {
        let oldCards = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let oldJobs = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var freshCards: [WorkCard] = []
        var freshJobs: [ScheduledJob] = []
        var ran: [String] = []
        for record in all {
            if record.scheduleKind == "card" {
                var card = liveCard(record)
                card.runs = oldCards[record.id]?.runs ?? []
                freshCards.append(card)
            } else {
                var job = liveJob(record)
                job.runs = oldJobs[record.id]?.runs ?? []
                freshJobs.append(job)
                if record.lastRunAt != nil { ran.append(record.id) }
            }
        }
        cards = freshCards
        jobs = freshJobs
        rebuildActivity()
        return ran
    }

    private func liveCard(_ record: TaskRecordDTO) -> WorkCard {
        let column = WorkColumn(rawValue: record.status ?? "") ?? .backlog
        var card = WorkCard(id: record.id, name: record.name ?? "Untitled card", instructions: record.prompt ?? "",
                            column: column, created: TasksWire.epoch(record.createdAt) ?? .distantPast)
        if let agent = record.agentId, !agent.isEmpty {
            card.agentID = agent
            card.agentMissing = agentsKnown && agentNames[agent] == nil
        }
        if let endpoint = record.endpointId, !endpoint.isEmpty {
            card.endpointID = endpoint
            if let model = liveModels.first(where: { $0.id == endpoint }) {
                card.model = model.name ?? model.model ?? "A model"
            } else if modelsKnown {
                card.modelMissing = true
            } else {
                card.model = "its own model"
            }
        }
        card.waitsFor = record.dependsOn ?? []
        card.attempt = max(1, record.attempts ?? 1)
        card.fromTrigger = record.trigger?.name
        if let last = (record.comments ?? []).last(where: { $0.kind == "result" || $0.kind == "error" }) {
            if last.kind == "error" { card.error = last.text ?? "" } else { card.result = last.text ?? "" }
        }
        if column == .running { card.startedAt = TasksWire.epoch(record.runStartedAt) }
        return card
    }

    private func liveJob(_ record: TaskRecordDTO) -> ScheduledJob {
        let next = TasksWire.date(record.nextRunAt)
        let kind: JobScheduleKind
        var note: String?
        switch record.scheduleKind {
        case "once": kind = .once
        case "daily": kind = .daily
        case "interval": kind = .interval
        default:
            kind = .interval
            note = "On its bot's own schedule"
        }
        var job = ScheduledJob(id: record.id, name: record.name ?? "Untitled task", prompt: record.prompt ?? "", kind: kind)
        job.fromDesktop = true
        job.desktopNext = next
        job.scheduleNote = note
        job.runAt = TasksWire.date(record.runAt) ?? next ?? Date()
        if kind == .daily {
            // The next time says it in this phone's own time; the stored "HH:MM" may be another zone's.
            if let next {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: next)
                job.dailyHour = parts.hour ?? 0
                job.dailyMinute = parts.minute ?? 0
            } else if let clock = TasksWire.clock(record.runTime) {
                job.dailyHour = clock.hour
                job.dailyMinute = clock.minute
            }
        }
        if let seconds = record.intervalSeconds, seconds > 0 { job.intervalMinutes = max(1, Int((seconds / 60).rounded())) }
        let endpoint = record.endpointId ?? ""
        job.endpointID = endpoint
        job.model = modelLabel(endpoint)
        let channel = record.deliverToChannel ?? ""
        job.channelID = channel
        job.deliver = channelLabel(channel)
        job.enabled = record.enabled ?? true
        job.builtinKey = (record.builtinAction?.isEmpty == false) ? record.builtinAction : nil
        job.agentID = (record.agentId?.isEmpty == false) ? record.agentId : nil
        job.fromTrigger = record.trigger != nil
        job.runningSince = TasksWire.epoch(record.runStartedAt)
        return job
    }

    private func rebuildActivity() {
        activity = jobs.flatMap(\.runs)
            .filter { $0.outcome != "running" && $0.outcome != "queued" }
            .compactMap { run in run.when.map { TasksActivityRun(at: $0, ok: run.ok) } }
    }

    // MARK: Runs

    private func loadRuns(_ ids: [String], account: String) async {
        guard !ids.isEmpty else { return }
        var failed = false
        for id in ids {
            do {
                let runs = try await liveClient().taskRuns(id)
                guard stillLive(account) else { return }
                if let index = jobs.firstIndex(where: { $0.id == id }) { jobs[index].runs = runs.map(liveRun) }
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                failed = true
            }
        }
        jobRunsFailed = failed
        rebuildActivity()
    }

    /// Read one routine's history again (its sheet opened, or it just ran).
    func loadJobRuns(_ id: String) async {
        guard isLive else { return }
        await loadRuns([id], account: liveAccount)
    }

    /// Read one card's history (its sheet opened, or it just ran).
    func loadCardRuns(_ id: String) async {
        guard isLive else { return }
        let account = liveAccount
        if cardRunsLoad[id] != .loaded { cardRunsLoad[id] = .loading }
        do {
            let runs = try await liveClient().taskRuns(id)
            guard stillLive(account) else { return }
            if let index = cards.firstIndex(where: { $0.id == id }) { cards[index].runs = runs.map(liveRun) }
            cardRunsLoad[id] = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            if case .server(status: 404, _) = error as? APIError {
                cardRunsLoad[id] = .failed("This card is not on your desktop any more.")
            } else {
                cardRunsLoad[id] = .failed("The run history could not be read. " + error.plainWords)
            }
        }
    }

    private func liveRun(_ record: TaskRunDTO) -> RunRecord {
        var outcome = record.outcome ?? ((record.error ?? "").isEmpty ? "succeeded" : "failed")
        if outcome == "lost" { outcome = record.missedReason == nil ? "incomplete" : "missed" }
        let late = (record.lateSeconds ?? 0) > 0 ? TasksWire.date(record.scheduledFor) : nil
        let output = record.output.flatMap { $0.isEmpty ? nil : $0 }
        let error = record.error.flatMap { $0.isEmpty ? nil : $0 }
        return RunRecord(id: record.id ?? UUID().uuidString, started: TasksWire.epoch(record.startedAt),
                         finished: TasksWire.epoch(record.ranAt), seconds: record.durationSeconds, outcome: outcome,
                         model: record.model, attempt: record.attempt, lateFrom: late, output: output, error: error,
                         delivery: liveDelivery(record.delivery, delivered: record.delivered), steps: nil,
                         deliveryID: record.delivery?.id, runID: record.runId)
    }

    /// The delivery the way the desktop's own history says it (static/js/runHistory.js: deliveryState).
    private func liveDelivery(_ delivery: TaskDeliveryDTO?, delivered: Bool?) -> RunDelivery {
        guard let delivery else {
            switch delivered {
            case true?: return .delivered(nil)
            case false?: return .legacyFailed("it did not go through")
            case nil: return .none
            }
        }
        let to: String? = delivery.channel.map { id in liveChannels.first { $0.id == id }?.label ?? id }
        switch delivery.status {
        case "delivered":
            return .delivered(to)
        case "pending", "sending":
            if let attempts = delivery.attempts, attempts > 0 {
                return .retrying(next: TasksWire.epoch(delivery.nextTryAt) ?? Date(), attempts: attempts, to: to)
            }
            return .delivering(to)
        case "failed":
            return .abandoned(to)
        default:
            return .interrupted(to)
        }
    }

    /// One run's steps (GET /api/runs/{run_id}), for the Steps button.
    func loadSteps(_ runID: String) async throws -> [RunStep] {
        let detail = try await liveClient().taskRunDetail(runID)
        return (detail.steps ?? []).map { step in
            var label = TasksWire.stepLabel(step.kind)
            if step.ok == false && step.kind == "tool_finished" { label += " (failed)" }
            let detail = step.detail.flatMap { $0.isEmpty ? nil : String($0.prefix(240)) }
            return RunStep(time: TasksWire.epoch(step.at) ?? Date(), label: label, tool: step.name, seconds: step.seconds, detail: detail)
        }
    }

    /// Send again on a delivery that failed or was cut off. Shown as sending at once, put back if refused.
    func sendAgainLive(run runID: String) {
        guard isLive else { return }
        let account = liveAccount
        var found: (deliveryID: String, before: RunDelivery)?
        for job in jobs { if let run = job.runs.first(where: { $0.id == runID }), let id = run.deliveryID { found = (id, run.delivery) } }
        for card in cards { if let run = card.runs.first(where: { $0.id == runID }), let id = run.deliveryID { found = (id, run.delivery) } }
        guard let found else {
            problem = "This message cannot be sent again from here."
            return
        }
        let to: String? = {
            switch found.before {
            case .abandoned(let to), .interrupted(let to): return to
            default: return nil
            }
        }()
        setDelivery(runID, .delivering(to))
        Task {
            do {
                let fresh = try await liveClient().taskDeliveryRetry(found.deliveryID)
                guard stillLive(account) else { return }
                setDelivery(runID, liveDelivery(fresh, delivered: nil))
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                setDelivery(runID, found.before)
                problem = "It was not sent again. " + error.plainWords
            }
        }
    }

    private func setDelivery(_ runID: String, _ delivery: RunDelivery) {
        for index in jobs.indices {
            if let r = jobs[index].runs.firstIndex(where: { $0.id == runID }) { jobs[index].runs[r].delivery = delivery }
        }
        for index in cards.indices {
            if let r = cards[index].runs.firstIndex(where: { $0.id == runID }) { cards[index].runs[r].delivery = delivery }
        }
    }

    // MARK: The board

    /// Move a card: shown at once, put back if the desktop refuses. Review to Ready with a note is
    /// "request changes"; Blocked to Ready is a retry.
    func moveLive(_ id: String, to column: WorkColumn, note: String? = nil, done: String, say: @escaping (String) -> Void) {
        guard isLive, let index = cards.firstIndex(where: { $0.id == id }), !waits(id) else { return }
        let account = liveAccount
        let before = cards[index]
        cards[index].column = column
        if column != .running { cards[index].startedAt = nil }
        if column == .ready && before.column == .review { cards[index].result = nil }
        if column == .ready && before.column == .blocked { cards[index].error = nil }
        let shown = cards[index]
        busy.insert(id)
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                let saved = try await liveClient().taskCardStatus(id, status: column.rawValue, note: note)
                guard stillLive(account) else { return }
                if let now = cards.firstIndex(where: { $0.id == id }) {
                    var fresh = liveCard(saved)
                    fresh.runs = cards[now].runs
                    cards[now] = fresh
                }
                say(done)
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if let now = cards.firstIndex(where: { $0.id == id }), cards[now] == shown {
                    withAnimation(Motion.snappy) { cards[now] = before }
                }
                say("The card was not moved. " + error.plainWords)
            }
        }
    }

    /// Run a card now. The desktop answers when the run ends, so the board is read again a moment after
    /// asking, to show it running. A timeout is not a failure: the run may well be going.
    func runCardLive(_ id: String, say: @escaping (String) -> Void) {
        guard isLive, let card = self.card(id), !waits(id) else { return }
        let account = liveAccount
        starting.insert(id)
        say("Starting \(card.name)")
        let watch = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled, stillLive(account) { await refreshTasks() }
        }
        Task {
            defer { if stillLive(account) { starting.remove(id) } }
            do {
                _ = try await liveClient().taskRunNow(id)
                watch.cancel()
                guard stillLive(account) else { return }
                await refreshTasks()
                await loadCardRuns(id)
                switch self.card(id)?.column {
                case .review?: say("\(card.name) finished. The result is in Review.")
                case .blocked?: say("\(card.name) did not finish. It is in Blocked.")
                default: say("\(card.name) ran.")
                }
            } catch {
                watch.cancel()
                guard stillLive(account) else { return }
                say(runProblem(error, name: card.name))
                await refreshTasks()
            }
        }
    }

    /// What a Run now that did not come back cleanly means, in plain words.
    private func runProblem(_ error: Error, name: String) -> String {
        let api = error as? APIError
        if error is CancellationError || api?.isOffline == true {
            // The run may still be going on the desktop; asking again could start it twice.
            // A long run is not the desktop going away, so a timeout leaves the connection alone.
            if let api, api != APIError.from(URLError(.timedOut)) { Connection.shared.note(api) }
            return "Your desktop did not say how \(name) went. It may still be running; this list shows what your desktop has."
        }
        Connection.shared.note(error)
        if case .server(status: 409, _)? = api {
            let words = error.plainWords
            return "\(name) did not start. " + words.prefix(1).uppercased() + String(words.dropFirst())
        }
        return "\(name) did not start. " + error.plainWords
    }

    func stopLive(_ id: String, say: @escaping (String) -> Void) {
        guard isLive, !busy.contains(id) else { return }
        let account = liveAccount
        busy.insert(id)
        let name = card(id)?.name ?? job(id)?.name ?? "It"
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                try await liveClient().taskStop(id)
                guard stillLive(account) else { return }
                say(card(id) != nil ? "Stopping. The card goes to Blocked." : "Stopping \(name)")
                try? await Task.sleep(for: .seconds(0.8))
                guard stillLive(account) else { return }
                await refreshTasks()
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if case .server(status: 409, _) = error as? APIError {
                    say("\(name) was not running.")
                } else {
                    say("\(name) was not stopped. " + error.plainWords)
                }
                await refreshTasks()
            }
        }
    }

    /// Delete a card or a task on the desktop. Removed from the screen only once the desktop has done it.
    func deleteLive(_ id: String, done: String, say: @escaping (String) -> Void) {
        guard isLive, !busy.contains(id) else { return }
        let account = liveAccount
        busy.insert(id)
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                try await liveClient().taskDelete(id)
                guard stillLive(account) else { return }
                withAnimation(Motion.snappy) {
                    cards.removeAll { $0.id == id }
                    for index in cards.indices { cards[index].waitsFor.removeAll { $0 == id } }
                    jobs.removeAll { $0.id == id }
                }
                rebuildActivity()
                say(done)
                if routines.contains(where: { $0.taskID == id }) { await loadLibrary() }
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if case .server(status: 404, _) = error as? APIError {
                    say("It was already gone from your desktop.")
                    await refreshTasks()
                } else {
                    say("Nothing was deleted. " + error.plainWords)
                }
            }
        }
    }

    /// Add a card on the desktop. Answers a plain sentence when it was not added.
    func addCardLive(name: String, instructions: String, endpointID: String, waitsFor: String?, ready: Bool) async -> String? {
        guard isLive else { return "Your desktop is not connected." }
        let account = liveAccount
        var body: [String: Any] = ["name": name, "prompt": instructions, "schedule_kind": "card",
                                   "status": ready ? "ready" : "backlog", "depends_on": waitsFor.map { [$0] } ?? []]
        if !endpointID.isEmpty { body["endpoint_id"] = endpointID }
        do {
            let made = try await liveClient().taskCreate(body)
            guard stillLive(account) else { return "Your desktop changed while the card was being added." }
            if !cards.contains(where: { $0.id == made.id }) { cards.append(liveCard(made)) }
            column = ready ? .ready : .backlog
            await refreshTasks()
            return nil
        } catch {
            Connection.shared.note(error)
            return "The card was not added. " + error.plainWords
        }
    }

    // MARK: Scheduled tasks

    /// Run a scheduled task now. Same as a card: the answer comes when it ends, and a timeout says so plainly.
    func runJobLive(_ id: String, onResult: @escaping (String) -> Void) {
        guard isLive, let job = self.job(id), !waits(id), job.runningSince == nil else { return }
        let account = liveAccount
        starting.insert(id)
        let watch = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled, stillLive(account) { await refreshTasks() }
        }
        Task {
            defer { if stillLive(account) { starting.remove(id) } }
            do {
                let run = try await liveClient().taskRunNow(id)
                watch.cancel()
                guard stillLive(account) else { return }
                await refreshTasks()
                await loadJobRuns(id)
                if run.outcome == "stopped" {
                    onResult("\(job.name) was stopped.")
                } else if let error = run.error, !error.isEmpty {
                    onResult("\(job.name) failed. \(error)")
                } else if run.delivered == false {
                    onResult("\(job.name) ran, but delivery failed. Check Settings > Channels.")
                } else if run.delivered == true {
                    onResult("\(job.name) ran and was delivered.")
                } else if run.delivery != nil {
                    onResult("\(job.name) ran. Delivery will be retried.")
                } else {
                    onResult("\(job.name) ran.")
                }
            } catch {
                watch.cancel()
                guard stillLive(account) else { return }
                onResult(runProblem(error, name: job.name))
                await refreshTasks()
            }
        }
    }

    /// Change one scheduled task's fields: shown at once, put back if the desktop refuses.
    private func updateJobLive(_ id: String, _ fields: [String: Any], change: (inout ScheduledJob) -> Void,
                               done: String?, failed: String, say: @escaping (String) -> Void) {
        guard isLive, let index = jobs.firstIndex(where: { $0.id == id }), !busy.contains(id) else { return }
        let account = liveAccount
        let before = jobs[index]
        change(&jobs[index])
        let shown = jobs[index]
        busy.insert(id)
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                let saved = try await liveClient().taskUpdate(id, fields)
                guard stillLive(account) else { return }
                if let now = jobs.firstIndex(where: { $0.id == id }) {
                    var fresh = liveJob(saved)
                    fresh.runs = jobs[now].runs
                    jobs[now] = fresh
                }
                if let done { say(done) }
                if before.builtin { await loadLibrary() }
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if let now = jobs.firstIndex(where: { $0.id == id }), jobs[now] == shown { jobs[now] = before }
                say(failed + " " + error.plainWords)
            }
        }
    }

    func toggleJobLive(_ id: String, say: @escaping (String) -> Void) {
        guard let job = self.job(id) else { return }
        if !job.enabled && job.ended {
            say("This one-time schedule has ended. Use Run now or schedule a new task.")
            return
        }
        let on = !job.enabled
        updateJobLive(id, ["enabled": on], change: { $0.enabled = on },
                      done: on ? "Schedule turned on for its next time." : "Schedule turned off. History kept; an active run can finish.",
                      failed: on ? "The schedule was not turned on." : "The schedule was not turned off.", say: say)
    }

    func setJobModelLive(_ id: String, _ endpointID: String, say: @escaping (String) -> Void) {
        guard job(id)?.endpointID ?? "" != endpointID else { return }
        let label = modelLabel(endpointID)
        updateJobLive(id, ["endpoint_id": endpointID], change: { $0.endpointID = endpointID; $0.model = label },
                      done: nil, failed: "The model was not changed.", say: say)
    }

    func setJobDeliveryLive(_ id: String, _ channelID: String, say: @escaping (String) -> Void) {
        guard job(id)?.channelID ?? "" != channelID else { return }
        let label = channelLabel(channelID)
        updateJobLive(id, ["deliver_to_channel": channelID], change: { $0.channelID = channelID; $0.deliver = label },
                      done: nil, failed: "Where it delivers was not changed.", say: say)
    }

    /// Schedule the form's task on the desktop: the field that is wrong, or a sentence when the desktop
    /// refused it, or neither when it was scheduled.
    func scheduleLive() async -> (field: JobDraftField?, problem: String?) {
        guard isLive else { return (nil, "Your desktop is not connected.") }
        let account = liveAccount
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return (.name, nil) }
        if prompt.isEmpty { return (.prompt, nil) }
        var body: [String: Any] = ["name": name, "prompt": prompt, "schedule_kind": draft.kind.rawValue]
        switch draft.kind {
        case .once:
            if draft.runAt <= Date() { return (.runAt, nil) }
            body["run_at"] = TasksWire.iso(draft.runAt)
        case .daily:
            let parts = Calendar.current.dateComponents([.hour, .minute], from: draft.dailyTime)
            guard let hour = parts.hour, let minute = parts.minute else { return (.time, nil) }
            body["run_time"] = String(format: "%02d:%02d", hour, minute)
            // The time is this phone's: the desktop keeps it there even if its own zone differs.
            body["time_zone"] = TimeZone.current.identifier
        case .interval:
            guard let minutes = Int(draft.minutes.trimmingCharacters(in: .whitespaces)), minutes >= 1 else { return (.minutes, nil) }
            body["interval_seconds"] = minutes * 60
        }
        if !draft.endpointID.isEmpty { body["endpoint_id"] = draft.endpointID }
        if !draft.channelID.isEmpty { body["deliver_to_channel"] = draft.channelID }
        do {
            let made = try await liveClient().taskCreate(body)
            guard stillLive(account) else { return (nil, "Your desktop changed while the task was being scheduled.") }
            if !jobs.contains(where: { $0.id == made.id }) { jobs.insert(liveJob(made), at: 0) }
            draft = JobDraft()
            draftError = nil
            await refreshTasks()
            return (nil, nil)
        } catch {
            Connection.shared.note(error)
            return (nil, "It was not scheduled. " + error.plainWords)
        }
    }

    // MARK: Automation library

    func loadLibrary() async {
        guard isLive else { return }
        let account = liveAccount
        if libraryLoad != .loaded { libraryLoad = .loading }
        do {
            let list = try await liveClient().tasksBuiltin()
            guard stillLive(account) else { return }
            let chosen = Dictionary(routines.map { ($0.id, $0.channelID) }, uniquingKeysWith: { first, _ in first })
            routines = list.map { item in
                let clock = TasksWire.clock(item.defaultDailyTime)
                let hours = max(1, Int(((item.defaultIntervalSeconds ?? 21_600) / 3600).rounded()))
                let channel = item.deliverToChannel ?? chosen[item.actionId] ?? ""
                return JobRoutine(id: item.actionId, label: item.label ?? item.actionId, about: item.description ?? "",
                                  usesModel: item.usesModel ?? true, hour: clock?.hour,
                                  everyHours: clock == nil ? hours : nil, deliver: channelLabel(channel),
                                  enabled: item.enabled ?? false, channelID: channel, taskID: item.taskId)
            }
            libraryLoad = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            libraryLoad = .failed("The automation library could not be read. " + error.plainWords)
        }
    }

    /// The channel a routine will deliver to once turned on. Only a choice on this phone until then.
    func setRoutineChannel(_ id: String, _ channelID: String) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].channelID = channelID
        routines[index].deliver = channelLabel(channelID)
    }

    func enableRoutineLive(_ id: String, say: @escaping (String) -> Void) {
        guard isLive, let index = routines.firstIndex(where: { $0.id == id }), !busy.contains(id) else { return }
        let account = liveAccount
        let routine = routines[index]
        routines[index].enabled = true
        busy.insert(id)
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                _ = try await liveClient().taskBuiltinEnable(id, channel: routine.channelID)
                guard stillLive(account) else { return }
                say("\(routine.label) turned on")
                await refreshTasks()
                await loadLibrary()
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if let now = routines.firstIndex(where: { $0.id == id }) { routines[now].enabled = routine.enabled }
                say("\(routine.label) was not turned on. " + error.plainWords)
            }
        }
    }

    func disableRoutineLive(_ id: String, say: @escaping (String) -> Void) {
        guard isLive, let index = routines.firstIndex(where: { $0.id == id }), !busy.contains(id) else { return }
        let routine = routines[index]
        guard let taskID = routine.taskID else {
            say("\(routine.label) cannot be turned off from here. Turn it off in Kairos on your desktop.")
            return
        }
        let account = liveAccount
        routines[index].enabled = false
        busy.insert(id)
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                _ = try await liveClient().taskUpdate(taskID, ["enabled": false])
                guard stillLive(account) else { return }
                say("\(routine.label) turned off. History kept.")
                await refreshTasks()
                await loadLibrary()
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if let now = routines.firstIndex(where: { $0.id == id }) { routines[now].enabled = routine.enabled }
                say("\(routine.label) was not turned off. " + error.plainWords)
            }
        }
    }
}

// MARK: - Shared pieces

/// One quiet line on a Tasks screen: loading, or what failed with a Try again.
struct TasksLiveLine: View {
    let text: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button {
                    Haptics.tap()
                    retry()
                } label: {
                    Text("Try again")
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
        .padding(.vertical, 4)
        .frame(minHeight: 48)
        .kCard(radius: 16)
    }
}

/// The load line for one part of Tasks: nothing once read, a quiet line while reading, Try again when it failed.
struct TasksLoadLine: View {
    let state: TasksLiveLoad
    var waiting = "Reading your desktop."
    let retry: () -> Void

    var body: some View {
        switch state {
        case .loading:
            TasksLiveLine(text: waiting)
        case .failed(let text):
            TasksLiveLine(text: text, retry: retry)
        case .idle, .loaded:
            EmptyView()
        }
    }
}

/// The quiet line on a Tasks part that is not connected to the desktop yet.
struct TasksNotLiveNote: View {
    let text: String

    var body: some View {
        HintLine(text: text, symbol: "info.circle")
            .padding(.horizontal, 4)
    }
}
