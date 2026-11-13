import SwiftUI

/// Everything the Tasks section shows and changes. One store for the session, so the board's column,
/// the search and an unsent schedule form survive leaving Tasks.
@Observable
final class TasksStore {
    static let shared = TasksStore(provider: TasksSampleProvider())

    var cards: [WorkCard]
    var jobs: [ScheduledJob]
    var routines: [JobRoutine]
    var triggers: [TrigRule]
    var requests: [TrigRequest]
    var activity: [TasksActivityRun]

    var column: WorkColumn = .ready
    var search = ""
    var showAllJobs = false
    var range: TasksRange = .week
    var draft = JobDraft()
    var draftError: JobDraftField? = nil
    var debugApplied = false

    // Paired with a desktop (TasksLive.swift). Unpaired, none of this is used and the screens show the samples.
    var isLive = false
    var liveAccount = "sample"
    var sampleStash: TasksSampleStash?
    var boardLoad: TasksLiveLoad = .idle
    var jobsLoad: TasksLiveLoad = .idle
    var libraryLoad: TasksLiveLoad = .idle
    var jobRunsFailed = false
    var cardRunsLoad: [String: TasksLiveLoad] = [:]
    var liveModels: [ModelChoiceDTO] = []
    var modelsKnown = false
    var liveChannels: [TaskChannelDTO] = []
    var agentNames: [String: String] = [:]
    var agentsKnown = false
    /// Cards and tasks with a write on its way: their controls wait.
    var busy: Set<String> = []
    /// Where a routine should deliver, chosen on this phone and not yet sent (routine id to channel id).
    var pickedChannel: [String: String] = [:]
    /// Cards and tasks with a Run now on its way (the desktop answers when the run ends).
    var starting: Set<String> = []
    /// One plain sentence for the person, said once and cleared.
    var problem: String?
    /// Writes on their way, and a count that moves whenever one is sent or answered: a list read that
    /// began before the last move may picture the desktop before that write, so it is not shown.
    var writing = 0
    var writeGeneration = 0
    /// A Schedule whose answer was lost: the form waits until a read shows whether it landed.
    var scheduleCheck: TasksScheduleCheck?

    init(provider: TasksProviding) {
        cards = provider.loadCards()
        jobs = provider.loadJobs()
        routines = provider.loadRoutines()
        triggers = provider.loadTriggers()
        requests = provider.loadRequests()
        activity = provider.loadActivity()
    }

    // MARK: Lookups

    func card(_ id: String) -> WorkCard? { cards.first { $0.id == id } }
    func job(_ id: String) -> ScheduledJob? { jobs.first { $0.id == id } }
    func trigger(_ id: String) -> TrigRule? { triggers.first { $0.id == id } }

    func cards(in column: WorkColumn) -> [WorkCard] {
        cards.filter { $0.column == column }.sorted { $0.created < $1.created }
    }

    func count(_ column: WorkColumn) -> Int { cards.filter { $0.column == column }.count }

    /// A card is waiting while any card it waits for is not Done.
    func isWaiting(_ card: WorkCard) -> Bool {
        card.waitsFor.contains { id in self.card(id)?.column != .done }
    }

    func waitNames(_ card: WorkCard) -> String {
        card.waitsFor.map { self.card($0)?.name ?? "a deleted card" }.joined(separator: ", ")
    }

    func agentName(_ id: String?, missing: Bool) -> String {
        if missing { return "a deleted agent" }
        guard let id else { return "Kairos" }
        return botName(id)
    }

    /// A bot's name: the paired desktop's, or the sample's.
    func botName(_ id: String) -> String {
        guard isLive else { return SampleData.bot(id).name }
        return agentNames[id] ?? "a bot"
    }

    /// "Scout · Claude Opus · waits for Draft the newsletter · attempt 2 of 3 · from trigger GitHub pushes"
    func meta(_ card: WorkCard) -> String {
        var parts: [String] = []
        if card.agentMissing { parts.append("a deleted agent") } else if let id = card.agentID { parts.append(botName(id)) }
        if card.modelMissing { parts.append("a removed model") } else { parts.append(card.model ?? "Claude") }
        if !card.waitsFor.isEmpty { parts.append("waits for \(waitNames(card))") }
        if card.attempt > 1 { parts.append("attempt \(card.attempt) of 3") }
        if let trigger = card.fromTrigger { parts.append("from trigger \(trigger)") }
        return parts.joined(separator: " · ")
    }

    var orderedJobs: [ScheduledJob] { jobs.filter(\.enabled) + jobs.filter { !$0.enabled } }

    var allRuns: [RunRecord] { jobs.flatMap(\.runs) }

    // MARK: Search

    var searching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private func matches(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespaces))
    }

    var matchingCards: [WorkCard] { cards.filter { matches($0.name) || matches($0.instructions) } }
    var matchingJobs: [ScheduledJob] { orderedJobs.filter { matches($0.name) || matches($0.prompt) } }
    var matchingRoutines: [JobRoutine] { routines.filter { matches($0.label) || matches($0.about) } }

    // MARK: Board

    func move(_ id: String, to column: WorkColumn) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].column = column
        if column != .running { cards[index].startedAt = nil }
    }

    func runCard(_ id: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].column = .running
        cards[index].startedAt = Date()
        cards[index].error = nil
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard let index = self.cards.firstIndex(where: { $0.id == id }), self.cards[index].column == .running else { return }
            withAnimation(Motion.snappy) {
                let started = self.cards[index].startedAt ?? Date()
                self.cards[index].column = .review
                self.cards[index].result = "Finished. A first version is ready for you to look over."
                self.cards[index].runs.insert(RunRecord(id: UUID().uuidString, started: started, finished: Date(),
                                                        seconds: Date().timeIntervalSince(started), outcome: "succeeded",
                                                        model: self.cards[index].model ?? "Claude", attempt: self.cards[index].attempt,
                                                        output: "Finished. A first version is ready for you to look over.",
                                                        steps: [RunStep(time: started, label: "Started"), RunStep(time: Date(), label: "Finished")]), at: 0)
                self.cards[index].startedAt = nil
            }
        }
    }

    func stopCard(_ id: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].column = .blocked
        cards[index].startedAt = nil
        cards[index].error = "Stopped by you before it finished."
    }

    func retryCard(_ id: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].attempt = min(3, cards[index].attempt + 1)
        cards[index].error = nil
        cards[index].column = .ready
    }

    func requestChanges(_ id: String, note: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].instructions += "\n\nChange: \(note)"
        cards[index].result = nil
        cards[index].column = .ready
    }

    func deleteCard(_ id: String) {
        cards.removeAll { $0.id == id }
        for index in cards.indices { cards[index].waitsFor.removeAll { $0 == id } }
    }

    func addCard(name: String, instructions: String, model: String, waitsFor: String?, ready: Bool) {
        let card = WorkCard(id: UUID().uuidString, name: name, instructions: instructions,
                            column: ready ? .ready : .backlog,
                            model: model == TasksOptions.defaultModel ? nil : model,
                            waitsFor: waitsFor.map { [$0] } ?? [], created: Date())
        cards.append(card)
        column = card.column
    }

    // MARK: Scheduled tasks

    /// Checks the form the way the desktop does; returns the field that is wrong, or schedules it.
    func schedule() -> JobDraftField? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .name }
        if prompt.isEmpty { return .prompt }
        var job = ScheduledJob(id: UUID().uuidString, name: name, prompt: prompt, kind: draft.kind,
                               model: draft.model, deliver: draft.deliver)
        switch draft.kind {
        case .once:
            if draft.runAt <= Date() { return .runAt }
            job.runAt = draft.runAt
        case .daily:
            let parts = Calendar.current.dateComponents([.hour, .minute], from: draft.dailyTime)
            guard let hour = parts.hour, let minute = parts.minute else { return .time }
            job.dailyHour = hour
            job.dailyMinute = minute
        case .interval:
            guard let minutes = Int(draft.minutes.trimmingCharacters(in: .whitespaces)), minutes >= 1 else { return .minutes }
            job.intervalMinutes = minutes
        }
        jobs.insert(job, at: 0)
        draft = JobDraft()
        draftError = nil
        return nil
    }

    /// Leaving the form keeps it only if the name or the prompt has text.
    func leaveDraft() {
        if !draft.hasText {
            draft = JobDraft()
            draftError = nil
        }
    }

    /// Returns the message to show.
    func toggleJob(_ id: String) -> String? {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return nil }
        if !jobs[index].enabled && jobs[index].ended { return nil }
        jobs[index].enabled.toggle()
        if let key = jobs[index].builtinKey, let r = routines.firstIndex(where: { $0.id == key }) {
            routines[r].enabled = jobs[index].enabled
        }
        return jobs[index].enabled
            ? "Schedule turned on for its next time."
            : "Schedule turned off. History kept; an active run can finish."
    }

    func runJob(_ id: String, onResult: @escaping (String) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].runningSince == nil else { return }
        let started = Date()
        jobs[index].runningSince = started
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard let index = self.jobs.firstIndex(where: { $0.id == id }), self.jobs[index].runningSince == started else { return }
            let job = self.jobs[index]
            let delivered = job.deliver != TasksOptions.tabOnly
            let reachable = TasksOptions.configured.contains(job.deliver)
            let run = RunRecord(id: UUID().uuidString, started: started, finished: Date(),
                                seconds: Date().timeIntervalSince(started), outcome: "succeeded",
                                model: job.model == TasksOptions.defaultModel ? "Claude Sonnet" : job.model, attempt: 1,
                                output: TasksSampleProvider.freshOutput(for: job.name),
                                delivery: delivered ? (reachable ? .delivered(job.deliver) : .retrying(next: Date().addingTimeInterval(600), attempts: 1, to: job.deliver)) : .none,
                                steps: [RunStep(time: started, label: "Started"),
                                        RunStep(time: started.addingTimeInterval(1), label: "Read notes", tool: "vault_search", seconds: 1.2),
                                        RunStep(time: Date(), label: "Finished")])
            withAnimation(Motion.snappy) {
                self.jobs[index].runningSince = nil
                self.jobs[index].runs.insert(run, at: 0)
                self.activity.append(TasksActivityRun(at: Date(), ok: true))
            }
            if !delivered {
                onResult("\(job.name) ran.")
            } else if reachable {
                onResult("\(job.name) ran and was delivered.")
            } else {
                onResult("\(job.name) ran. Delivery will be retried.")
            }
        }
    }

    func stopJob(_ id: String) -> String? {
        guard let index = jobs.firstIndex(where: { $0.id == id }), let started = jobs[index].runningSince else { return nil }
        jobs[index].runningSince = nil
        jobs[index].runs.insert(RunRecord(id: UUID().uuidString, started: started, finished: Date(),
                                          seconds: Date().timeIntervalSince(started), outcome: "stopped",
                                          model: "Claude Sonnet", attempt: 1, steps: []), at: 0)
        activity.append(TasksActivityRun(at: Date(), ok: false))
        return "Stopping \(jobs[index].name)"
    }

    func setJobModel(_ id: String, _ model: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].model = model
    }

    func setJobDelivery(_ id: String, _ channel: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].deliver = channel
    }

    func deleteJob(_ id: String) {
        guard let job = job(id) else { return }
        if let key = job.builtinKey, let r = routines.firstIndex(where: { $0.id == key }) { routines[r].enabled = false }
        jobs.removeAll { $0.id == id }
    }

    /// Send again on an abandoned or interrupted delivery.
    func sendAgain(run runID: String) {
        func update(_ runs: inout [RunRecord]) -> Bool {
            guard let r = runs.firstIndex(where: { $0.id == runID }) else { return false }
            let to: String? = {
                switch runs[r].delivery {
                case .abandoned(let to), .interrupted(let to): return to
                default: return nil
                }
            }()
            runs[r].delivery = .delivering(to)
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(Motion.snappy) { self.finishSend(runID, to: to) }
            }
            return true
        }
        for index in jobs.indices where update(&jobs[index].runs) { return }
        for index in cards.indices where update(&cards[index].runs) { return }
    }

    private func finishSend(_ runID: String, to: String?) {
        for index in jobs.indices {
            if let r = jobs[index].runs.firstIndex(where: { $0.id == runID }) { jobs[index].runs[r].delivery = .delivered(to) }
        }
        for index in cards.indices {
            if let r = cards[index].runs.firstIndex(where: { $0.id == runID }) { cards[index].runs[r].delivery = .delivered(to) }
        }
    }

    // MARK: Automation library

    func setRoutineDelivery(_ id: String, _ channel: String) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].deliver = channel
    }

    func enableRoutine(_ id: String) -> String {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return "" }
        routines[index].enabled = true
        let routine = routines[index]
        if let j = jobs.firstIndex(where: { $0.builtinKey == id }) {
            jobs[j].enabled = true
            jobs[j].deliver = routine.deliver
        } else {
            var job = ScheduledJob(id: "job-\(id)", name: routine.label, prompt: routine.about,
                                   kind: routine.hour == nil ? .interval : .daily,
                                   deliver: routine.deliver, builtinKey: id)
            if let hour = routine.hour { job.dailyHour = hour } else { job.intervalMinutes = (routine.everyHours ?? 6) * 60 }
            jobs.insert(job, at: 0)
        }
        return "\(routine.label) turned on"
    }

    func disableRoutine(_ id: String) -> String {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return "" }
        routines[index].enabled = false
        if let j = jobs.firstIndex(where: { $0.builtinKey == id }) { jobs[j].enabled = false }
        return "\(routines[index].label) turned off. History kept."
    }

    // MARK: Triggers

    /// Approving makes the work start; returns the next step to say.
    func approve(_ requestID: String) -> String {
        guard let request = requests.first(where: { $0.id == requestID }) else { return "" }
        requests.removeAll { $0.id == requestID }
        guard let t = triggers.firstIndex(where: { $0.id == request.triggerID }) else { return "Approved." }
        markEvent(request, outcome: "approved", in: t)
        if triggers[t].action == .card {
            cards.append(WorkCard(id: UUID().uuidString, name: request.summary, instructions: triggers[t].instructions,
                                  column: .ready, agentID: triggers[t].agentID, fromTrigger: triggers[t].name, created: Date()))
            return "Approved. A card is in Ready."
        }
        if let jobID = triggers[t].jobID, job(jobID) != nil {
            runJob(jobID) { _ in }
            return "Approved. The task is running."
        }
        return "Approved."
    }

    func skip(_ requestID: String) {
        guard let request = requests.first(where: { $0.id == requestID }) else { return }
        requests.removeAll { $0.id == requestID }
        if let t = triggers.firstIndex(where: { $0.id == request.triggerID }) { markEvent(request, outcome: "skipped", in: t) }
    }

    private func markEvent(_ request: TrigRequest, outcome: String, in t: Int) {
        if let e = triggers[t].recent.firstIndex(where: { $0.outcome == "waiting" && $0.name == request.eventType }) {
            triggers[t].recent[e].outcome = outcome
        }
    }

    func setTriggerEnabled(_ id: String, _ on: Bool) {
        guard let index = triggers.firstIndex(where: { $0.id == id }) else { return }
        triggers[index].enabled = on
    }

    func setAutoRun(_ id: String, _ on: Bool) {
        guard let index = triggers.firstIndex(where: { $0.id == id }) else { return }
        triggers[index].autoRun = on
    }

    func saveTrigger(_ id: String, events: String, path: String, value: String, title: String, instructions: String) {
        guard let index = triggers.firstIndex(where: { $0.id == id }) else { return }
        triggers[index].events = events
        triggers[index].conditionPath = path.trimmingCharacters(in: .whitespaces)
        triggers[index].conditionValue = path.trimmingCharacters(in: .whitespaces).isEmpty ? "" : value
        triggers[index].cardTitle = title
        triggers[index].instructions = instructions
    }

    func newSecret(_ id: String) {
        guard let index = triggers.firstIndex(where: { $0.id == id }) else { return }
        triggers[index].freshSecret = TasksSampleProvider.makeSecret()
    }

    func forgetSecret(_ id: String) {
        guard let index = triggers.firstIndex(where: { $0.id == id }) else { return }
        triggers[index].freshSecret = nil
    }

    func deleteTrigger(_ id: String) {
        triggers.removeAll { $0.id == id }
        requests.removeAll { $0.triggerID == id }
    }

    func addTrigger(name: String, source: TrigSource, action: TrigAction, agentID: String?, jobID: String?,
                    events: String, title: String, instructions: String, askOn: String) -> String {
        let id = "tr-\(UUID().uuidString.prefix(6).lowercased())"
        let trigger = TrigRule(id: id, name: name, source: source, action: action,
                               agentID: action == .card ? agentID : nil,
                               jobID: action == .task ? jobID : nil,
                               events: events, cardTitle: title, instructions: instructions, askOn: askOn,
                               address: "https://your-kairos.example/hooks/t/\(id.dropFirst(3))",
                               freshSecret: TasksSampleProvider.makeSecret())
        triggers.append(trigger)
        return id
    }

    /// "Makes a card for Scout", "Runs Morning summary", "Runs a removed task".
    func describe(_ trigger: TrigRule) -> String {
        switch trigger.action {
        case .card:
            return "Makes a card for \(agentName(trigger.agentID, missing: trigger.agentMissing))"
        case .task:
            if trigger.jobMissing { return "Runs a removed task" }
            if let id = trigger.jobID, let job = job(id) {
                if let agent = job.agentID { return "Runs \(job.name) for \(botName(agent))" }
                return "Runs \(job.name)"
            }
            return "Runs a removed task"
        }
    }

    // MARK: Activity

    func activityCounts() -> (done: Int, other: Int) {
        let start = rangeStart(range)
        let runs = activity.filter { $0.at >= start }
        let done = runs.filter(\.ok).count
        return (done, runs.count - done)
    }

    func rangeStart(_ range: TasksRange) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch range {
        case .week: return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .year: return calendar.date(byAdding: .day, value: -359, to: today) ?? today
        }
    }

    /// One value per dot: nil for no runs, true when every run there succeeded, false otherwise.
    func activityCells() -> [Bool?] {
        let calendar = Calendar.current
        let start = rangeStart(range)
        let count: Int
        let step: (Date) -> Int
        switch range {
        case .week:
            count = 7 * 24
            step = { Int($0.timeIntervalSince(start) / 3600) }
        case .month:
            count = 30
            step = { calendar.dateComponents([.day], from: start, to: $0).day ?? -1 }
        case .year:
            count = 360
            step = { calendar.dateComponents([.day], from: start, to: $0).day ?? -1 }
        }
        var cells = [Bool?](repeating: nil, count: count)
        for run in activity where run.at >= start {
            let index = step(run.at)
            guard index >= 0, index < count else { continue }
            cells[index] = (cells[index] ?? true) && run.ok
        }
        return cells
    }
}
