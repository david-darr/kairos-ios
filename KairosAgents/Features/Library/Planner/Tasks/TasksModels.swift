import SwiftUI

// MARK: - Runs

/// Where a run's result was sent, and how that went.
nonisolated enum RunDelivery: Hashable, Sendable {
    case none
    case delivered(String?)
    case delivering(String?)
    case retrying(next: Date, attempts: Int, to: String?)
    case abandoned(String?)
    case interrupted(String?)
    case legacyFailed(String)

    var canSendAgain: Bool {
        switch self {
        case .abandoned, .interrupted: true
        default: false
        }
    }
}

/// One step in a run's timeline.
nonisolated struct RunStep: Identifiable, Hashable, Sendable {
    let id = UUID()
    var time: Date
    var label: String
    var tool: String? = nil
    var seconds: Double? = nil
    var detail: String? = nil
}

/// One recorded run of a scheduled task or a card.
nonisolated struct RunRecord: Identifiable, Hashable, Sendable {
    let id: String
    var started: Date?
    var finished: Date? = nil
    var seconds: Double?
    /// succeeded, failed, incomplete, stopped, or a raw label the phone does not know.
    var outcome: String
    var model: String? = nil
    var attempt: Int? = nil
    /// Set when the run started late: the time it was due.
    var lateFrom: Date? = nil
    var output: String? = nil
    var error: String? = nil
    var delivery: RunDelivery = .none
    /// nil when the run has no run ID (no Steps button); empty when nothing was recorded.
    var steps: [RunStep]? = nil
    /// Paired: the delivery row Send again retries (core/outbox.py).
    var deliveryID: String? = nil
    /// Paired: the model run whose steps are read on a tap (GET /api/runs/{id}).
    var runID: String? = nil

    var outcomeLabel: String {
        switch outcome {
        case "succeeded": "Succeeded"
        case "failed": "Failed"
        case "incomplete": "Didn't finish"
        case "stopped": "Stopped"
        case "running": "Running"
        case "queued": "Waiting to start"
        case "missed": "Missed"
        default: outcome
        }
    }

    var tone: PlannerTone {
        switch outcome {
        case "succeeded": .success
        case "failed": .danger
        case "incomplete", "stopped", "missed": .gold
        case "running", "queued": .working
        default: .muted
        }
    }

    var ok: Bool { outcome == "succeeded" }
    var when: Date? { started ?? finished }
}

// MARK: - Work board

nonisolated enum WorkColumn: String, CaseIterable, Hashable, Sendable {
    case backlog, ready, running, review, done, blocked

    var title: String {
        switch self {
        case .backlog: "Backlog"
        case .ready: "Ready"
        case .running: "Running"
        case .review: "Review"
        case .done: "Done"
        case .blocked: "Blocked"
        }
    }

    var emptyLine: String {
        switch self {
        case .backlog: "Nothing waiting in the backlog."
        case .ready: "Nothing is ready to run."
        case .running: "Nothing is running right now."
        case .review: "No results waiting for you."
        case .done: "Nothing finished yet."
        case .blocked: "Nothing is blocked."
        }
    }
}

nonisolated struct WorkCard: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var instructions: String
    var column: WorkColumn
    var agentID: String? = nil
    var agentMissing = false
    var model: String? = nil
    var modelMissing = false
    var waitsFor: [String] = []
    var attempt = 1
    var fromTrigger: String? = nil
    var result: String? = nil
    var error: String? = nil
    var startedAt: Date? = nil
    var created: Date
    var runs: [RunRecord] = []
    /// Paired: the model it runs on (nil is Claude).
    var endpointID: String? = nil
}

// MARK: - Scheduled tasks

nonisolated enum JobScheduleKind: String, CaseIterable, Hashable, Sendable {
    case once, daily, interval

    var title: String {
        switch self {
        case .once: "Once, at a time"
        case .daily: "Every day at..."
        case .interval: "Every N minutes"
        }
    }
}

nonisolated struct ScheduledJob: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var prompt: String
    var kind: JobScheduleKind
    var runAt = Date()
    var dailyHour = 6
    var dailyMinute = 0
    var intervalMinutes = 30
    var model = TasksOptions.defaultModel
    var deliver = TasksOptions.tabOnly
    var enabled = true
    var builtinKey: String? = nil
    var agentID: String? = nil
    var fromTrigger = false
    var runningSince: Date? = nil
    /// Newest first.
    var runs: [RunRecord] = []
    /// Paired: read from the desktop, whose own next time is used instead of working one out here.
    var fromDesktop = false
    var desktopNext: Date? = nil
    /// Paired: the model id (nil or "" is Claude) and the channel id (nil or "" is the Tasks tab only).
    var endpointID: String? = nil
    var channelID: String? = nil
    /// Paired: a schedule the phone cannot draw (a bot's routine), in words.
    var scheduleNote: String? = nil

    var builtin: Bool { builtinKey != nil }
    /// A plain schedule: no agent, routine, trigger or built-in action. Only these can be shared.
    var plain: Bool { builtinKey == nil && agentID == nil && !fromTrigger }
    var displayName: String { builtin ? "\(name) · built-in" : name }
    var ended: Bool {
        if fromDesktop { return kind == .once && scheduleNote == nil && (desktopNext.map { $0 <= Date() } ?? true) }
        return kind == .once && runAt < Date()
    }

    var nextRun: Date? {
        guard enabled else { return nil }
        if fromDesktop { return desktopNext }
        let calendar = Calendar.current
        let now = Date()
        switch kind {
        case .once:
            return runAt > now ? runAt : nil
        case .daily:
            var parts = calendar.dateComponents([.year, .month, .day], from: now)
            parts.hour = dailyHour
            parts.minute = dailyMinute
            let today = calendar.date(from: parts) ?? now
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        case .interval:
            let last = runs.first?.when ?? now
            var next = last.addingTimeInterval(Double(intervalMinutes * 60))
            while next < now { next = next.addingTimeInterval(Double(intervalMinutes * 60)) }
            return next
        }
    }

    var scheduleSummary: String {
        if let scheduleNote {
            if let next = nextRun { return "\(scheduleNote) - next \(TasksDates.short(next))" }
            return scheduleNote
        }
        switch kind {
        case .once:
            let at = runAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            return ended ? "Once at \(at) (done)" : "Once at \(at)"
        case .daily:
            let time = TasksDates.clock(hour: dailyHour, minute: dailyMinute)
            if let next = nextRun { return "Every day at \(time) - next \(TasksDates.short(next))" }
            return "Every day at \(time)"
        case .interval:
            if let next = nextRun { return "Every \(intervalMinutes)m - next \(TasksDates.time(next))" }
            return "Every \(intervalMinutes)m"
        }
    }

    var nextLine: String {
        if let runningSince { return "Running now, started \(TasksDates.time(runningSince))" }
        if let next = nextRun { return "Next \(TasksDates.short(next))" }
        return "Not scheduled"
    }
}

/// The unsent "Schedule a task" form, kept while the person leaves and comes back.
nonisolated struct JobDraft: Hashable, Sendable {
    var name = ""
    var prompt = ""
    var kind: JobScheduleKind = .daily
    var runAt = Date().addingTimeInterval(3600)
    var dailyTime = TasksDates.todayAt(hour: 6, minute: 0)
    var minutes = "30"
    var model = TasksOptions.defaultModel
    var deliver = TasksOptions.tabOnly
    /// Paired: the model id and channel id ("" is the default).
    var endpointID = ""
    var channelID = ""

    var hasText: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty || !prompt.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

nonisolated enum JobDraftField: Hashable, Sendable {
    case name, prompt, runAt, time, minutes

    var message: String {
        switch self {
        case .name: "Name: give the task a name."
        case .prompt: "Prompt to run: say what the task should do."
        case .runAt: "Run at: pick when it runs."
        case .time: "At (time): pick a time of day."
        case .minutes: "Every (min): use a whole number of minutes, 1 or more."
        }
    }
}

/// A ready-made routine from the automation library.
nonisolated struct JobRoutine: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var about: String
    var usesModel: Bool
    var hour: Int? = nil
    var everyHours: Int? = nil
    var deliver = TasksOptions.tabOnly
    var enabled = false
    /// Paired: the channel id it delivers to ("" is the Tasks tab only), and the task it made when turned on.
    var channelID = ""
    var taskID: String? = nil

    var cadence: String {
        if let hour { return "every day at \(TasksDates.clock(hour: hour, minute: 0))" }
        return "every \(everyHours ?? 6)h"
    }
}

// MARK: - Triggers

nonisolated enum TrigSource: String, CaseIterable, Hashable, Sendable {
    case github, generic

    var badge: String { self == .github ? "GitHub" : "Webhook" }
    var title: String { self == .github ? "GitHub" : "Any service (signed JSON)" }
}

nonisolated enum TrigAction: String, CaseIterable, Hashable, Sendable {
    case card, task

    var title: String { self == .card ? "Make a card" : "Run a task or agent goal" }
}

nonisolated struct TrigEvent: Identifiable, Hashable, Sendable {
    let id = UUID()
    var name: String
    var at: Date
    var detail: String? = nil
    /// waiting, started, approved, skipped, filtered, duplicate, setup, rejected, too_many, failed, or raw.
    var outcome: String

    var label: String {
        switch outcome {
        case "waiting": "Waiting for you"
        case "started": "Started"
        case "approved": "Approved"
        case "skipped": "Skipped"
        case "filtered": "Filtered out"
        case "duplicate": "Duplicate"
        case "setup": "Setup check"
        case "rejected": "Rejected"
        case "too_many": "Too many"
        case "failed": "Failed"
        default: outcome
        }
    }

    var tone: PlannerTone {
        switch outcome {
        case "waiting": .gold
        case "started", "approved": .success
        case "rejected", "too_many", "failed": .danger
        default: .muted
        }
    }
}

nonisolated struct TrigRule: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var source: TrigSource
    var action: TrigAction
    var agentID: String? = nil
    var agentMissing = false
    var jobID: String? = nil
    var jobMissing = false
    var enabled = true
    var autoRun = false
    var events = ""
    var conditionPath = ""
    var conditionValue = ""
    var cardTitle = ""
    var instructions = ""
    var askOn = TasksOptions.askOptions[0]
    var lastEvent: Date? = nil
    var address: String
    /// Only right after creation or a new secret.
    var freshSecret: String? = nil
    var recent: [TrigEvent] = []
}

/// An outside event waiting for the person's OK.
nonisolated struct TrigRequest: Identifiable, Hashable, Sendable {
    let id: String
    var triggerID: String
    var triggerName: String
    var summary: String
    var eventType: String
    var at: Date
}

/// One dot's worth of history for the activity grid.
nonisolated struct TasksActivityRun: Hashable, Sendable {
    var at: Date
    var ok: Bool
}

nonisolated enum TasksRange: String, CaseIterable, Hashable, Sendable {
    case week = "Week", month = "Month", year = "Year"
}

// MARK: - Options and dates

nonisolated enum TasksOptions {
    static let defaultModel = "Claude (default)"
    static let models = [defaultModel, "Claude Opus", "GPT-6.1 Sol", "Qwen local"]
    static let tabOnly = "Tasks tab only"
    static let channels = [tabOnly, "Discord", "Telegram"]
    static let configured: Set<String> = [tabOnly, "Discord"]
    static let askOptions = ["In the app", "The agent's channel", "Discord"]

    static func channelLabel(_ channel: String) -> String {
        if configured.contains(channel) { return channel }
        if channels.contains(channel) { return "\(channel) (not configured)" }
        return "\(channel) (not set up)"
    }

    /// The channels to offer for a saved task: the usual ones, plus its own if it is no longer set up.
    static func channelOptions(keeping current: String) -> [String] {
        channels.contains(current) ? channels : channels + [current]
    }
}

nonisolated enum TasksDates {
    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    static func clock(hour: Int, minute: Int) -> String { time(todayAt(hour: hour, minute: minute)) }

    static func todayAt(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    /// "Tue 6:00 AM"
    static func short(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "Today 6:00 AM", "Yesterday 9:12 PM", "Tue 6:00 AM" this week, then "Nov 3, 6:00 AM".
    static func relative(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today \(time(date))" }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time(date))" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow \(time(date))" }
        if abs(date.timeIntervalSinceNow) < 6 * 86_400 { return short(date) }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "duration unknown" }
        let whole = Int(seconds.rounded())
        if whole < 60 { return "\(whole)s" }
        if whole < 3600 { return "\(whole / 60)m \(whole % 60)s" }
        return "\(whole / 3600)h \((whole % 3600) / 60)m"
    }
}

// MARK: - Provider

/// Where Tasks reads its data. The sample stands in until the desktop connection fills this in.
protocol TasksProviding {
    func loadCards() -> [WorkCard]
    func loadJobs() -> [ScheduledJob]
    func loadRoutines() -> [JobRoutine]
    func loadTriggers() -> [TrigRule]
    func loadRequests() -> [TrigRequest]
    func loadActivity() -> [TasksActivityRun]
}
