import Foundation

// The desktop's Tasks routes (routes/task_routes.py) as the phone reads them: one decoder per answer and
// one function per route. Shapes were read from services/task_service.py (the task, card and run records),
// core/builtin_tasks.py (the automation library), core/outbox.py (a run's delivery), core/channels/registry.py
// (where results can go) and routes/run_routes.py with core/session_manager_store.py (a run's steps).
//
// - A task and a card are the same record; a card has `schedule_kind` "card" and a `status` on the board.
// - Times are epoch seconds (Double), except `next_run_at`, `run_at` and `scheduled_for`, which are ISO text.
// - Everything decodes with the shared snake_case decoder.

// MARK: - Tasks and cards

/// One record of GET /api/tasks (task_service.py: create_task, update_task, set_card_status). Also the answer
/// of POST /api/tasks, PATCH /api/tasks/{id} and POST /api/tasks/{id}/status.
nonisolated struct TaskRecordDTO: Decodable, Sendable {
    var id: String
    var name: String?
    var prompt: String?
    /// "once", "interval", "daily", "card", or a bot routine's "cron" or "limit_reset".
    var scheduleKind: String?
    var runAt: String?
    var intervalSeconds: Double?
    /// "HH:MM" in `time_zone`, or the desktop's own zone.
    var runTime: String?
    var timeZone: String?
    var enabled: Bool?
    var nextRunAt: String?
    var lastRunAt: Double?
    var createdAt: Double?
    var builtinAction: String?
    /// A channel id from GET /api/channels; nil or "" means the Tasks tab only.
    var deliverToChannel: String?
    /// A model id from GET /api/models/choices; nil or "" means Claude.
    var endpointId: String?
    var agentId: String?
    /// The webhook trigger that made it.
    var trigger: TaskTriggerRefDTO?
    /// Set while a run is going (claimed or started).
    var runStartedAt: Double?
    /// Present on a bot's routine; its schedule is edited from the bot.
    var routine: JSONValue?
    // Cards only.
    /// backlog, ready, running, review, done or blocked.
    var status: String?
    var dependsOn: [String]?
    var attempts: Int?
    var comments: [TaskCommentDTO]?
}

nonisolated struct TaskTriggerRefDTO: Decodable, Sendable {
    var id: String?
    var name: String?
}

/// A card's note, result or error (task_service.py: _comment). The newest "result" or "error" is what the
/// board shows.
nonisolated struct TaskCommentDTO: Decodable, Sendable {
    var at: Double?
    /// "result", "error", "feedback" or "note".
    var kind: String?
    var text: String?
    var by: String?
}

// MARK: - Runs

/// One run, newest first, from GET /api/tasks/{id}/runs (task_service.py: list_runs). POST /api/tasks/{id}/run
/// answers the newest one once the run has ended (or `{"ok": true}`, so every field is optional).
nonisolated struct TaskRunDTO: Decodable, Sendable {
    var id: String?
    var ok: Bool?
    var taskId: String?
    var startedAt: Double?
    /// When it finished.
    var ranAt: Double?
    var durationSeconds: Double?
    /// succeeded, failed, stopped, lost, or queued and running while it goes.
    var outcome: String?
    var output: String?
    var error: String?
    /// Only for records with no delivery row: true, false, or nil for no channel.
    var delivered: Bool?
    var deliveryId: String?
    var delivery: TaskDeliveryDTO?
    /// The model run behind it, for its steps (GET /api/runs/{run_id}).
    var runId: String?
    var source: String?
    var scheduledFor: String?
    var lateSeconds: Double?
    var model: String?
    var attempt: Int?
    var missedReason: String?
}

/// A run's channel message (outbox.py: public). Also the answer of POST /api/tasks/deliveries/{id}/retry.
nonisolated struct TaskDeliveryDTO: Decodable, Sendable {
    var id: String
    var channel: String?
    /// pending, sending, delivered, failed or unknown.
    var status: String?
    var attempts: Int?
    var nextTryAt: Double?
    var lastError: String?
    var createdAt: Double?
    var finishedAt: Double?
}

/// GET /api/runs/{run_id}: only the steps are read here (session_manager_store.py: run_events).
nonisolated struct TaskRunDetailDTO: Decodable, Sendable {
    var steps: [TaskRunStepDTO]?
}

nonisolated struct TaskRunStepDTO: Decodable, Sendable {
    var at: Double?
    /// tool_started, tool_finished, quota, checkpoint, stopped, failed, truncated.
    var kind: String?
    var name: String?
    var ok: Bool?
    var detail: String?
    var seconds: Double?
}

// MARK: - Library and choices

/// One of GET /api/tasks/builtin (task_routes.py: get_builtin_tasks over builtin_tasks.list_builtin_tasks).
nonisolated struct TaskBuiltinDTO: Decodable, Sendable {
    var actionId: String
    var label: String?
    var description: String?
    var kind: String?
    var defaultIntervalSeconds: Double?
    var defaultDailyTime: String?
    var usesModel: Bool?
    var enabled: Bool?
    /// The task it made when turned on, if any.
    var taskId: String?
    var deliverToChannel: String?
}

/// One of GET /api/channels (channels/registry.py: list_channels).
nonisolated struct TaskChannelDTO: Decodable, Sendable {
    var id: String
    var label: String?
    var configured: Bool?
}

/// POST /api/tasks/{id}/stop and DELETE /api/tasks/{id}.
nonisolated struct TaskOKDTO: Decodable, Sendable {
    var ok: Bool?
}

// MARK: - Reading the wire

nonisolated enum TasksWire {
    /// An ISO date-time as the desktop writes it: with or without fractional seconds (Python writes six
    /// digits), with an offset or "Z", or with no offset at all (read as this phone's local time).
    static func date(_ text: String?) -> Date? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        // Drop the fractional part: the formatters below disagree on how many digits they accept.
        if let dot = text.firstIndex(of: "."), let timeMark = text.firstIndex(of: "T"), dot > timeMark {
            var end = text.index(after: dot)
            while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
            text.removeSubrange(dot..<end)
        }
        let zoned = ISO8601DateFormatter()
        zoned.formatOptions = [.withInternetDateTime]
        if let date = zoned.date(from: text) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        return nil
    }

    static func epoch(_ seconds: Double?) -> Date? {
        guard let seconds, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// "06:30" as (6, 30).
    static func clock(_ text: String?) -> (hour: Int, minute: Int)? {
        let parts = (text ?? "").split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let minute = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// A time the desktop reads back (fromisoformat), in UTC with an offset.
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// The step names the desktop's own timeline uses (static/js/runTimeline.js).
    static func stepLabel(_ kind: String?) -> String {
        switch kind {
        case "tool_started": "Started"
        case "tool_finished": "Finished"
        case "quota": "Quota"
        case "checkpoint": "Checkpoint"
        case "stopped": "Stopped"
        case "failed": "Failed"
        case "truncated": "More steps"
        case let other?: other
        case nil: "Step"
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try KJSON.decode(type, from: data)
        } catch {
            throw APIError.unreadable(String(describing: error))
        }
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/tasks: every task and card this account may see.
    func tasksList() async throws -> [TaskRecordDTO] {
        try await get("/api/tasks")
    }

    /// GET /api/tasks/{id}/runs: newest first, up to 50.
    func taskRuns(_ id: String) async throws -> [TaskRunDTO] {
        try await get("/api/tasks/\(id)/runs")
    }

    /// POST /api/tasks: a card (`schedule_kind` "card") or a scheduled task.
    func taskCreate(_ body: [String: Any]) async throws -> TaskRecordDTO {
        try await post("/api/tasks", json: body)
    }

    /// PATCH /api/tasks/{id}: name, prompt, enabled, deliver_to_channel, endpoint_id, depends_on.
    func taskUpdate(_ id: String, _ fields: [String: Any]) async throws -> TaskRecordDTO {
        try await request("PATCH", "/api/tasks/\(id)", json: fields)
    }

    /// POST /api/tasks/{id}/status: move a card. Review to Ready with a note is "request changes".
    func taskCardStatus(_ id: String, status: String, note: String?) async throws -> TaskRecordDTO {
        var body: [String: Any] = ["status": status]
        if let note { body["note"] = note }
        return try await post("/api/tasks/\(id)/status", json: body)
    }

    /// DELETE /api/tasks/{id}: the task or card and its run history.
    func taskDelete(_ id: String) async throws {
        try await call("DELETE", "/api/tasks/\(id)")
    }

    /// POST /api/tasks/{id}/run. The desktop answers only once the run has ended, so this waits as long as
    /// this phone allows (about three minutes). A timeout does not mean the run failed.
    func taskRunNow(_ id: String) async throws -> TaskRunDTO {
        var request = try urlRequest("POST", "/api/tasks/\(id)/run")
        request.timeoutInterval = 175
        return try TasksWire.decode(TaskRunDTO.self, try await send(request))
    }

    /// POST /api/tasks/{id}/stop: 409 when it is not running.
    func taskStop(_ id: String) async throws {
        try await call("POST", "/api/tasks/\(id)/stop")
    }

    /// POST /api/tasks/deliveries/{id}/retry: only a failed or unknown delivery (409 otherwise).
    func taskDeliveryRetry(_ deliveryID: String) async throws -> TaskDeliveryDTO {
        try await post("/api/tasks/deliveries/\(deliveryID)/retry")
    }

    /// GET /api/tasks/builtin
    func tasksBuiltin() async throws -> [TaskBuiltinDTO] {
        try await get("/api/tasks/builtin")
    }

    /// POST /api/tasks/builtin/{action_id}/enable: turns it on, making its task the first time.
    func taskBuiltinEnable(_ actionID: String, channel: String?) async throws -> TaskRecordDTO {
        var body: [String: Any] = [:]
        if let channel, !channel.isEmpty { body["deliver_to_channel"] = channel }
        return try await post("/api/tasks/builtin/\(actionID)/enable", json: body)
    }

    /// GET /api/channels
    func taskChannels() async throws -> [TaskChannelDTO] {
        try await get("/api/channels")
    }

    /// GET /api/runs/{run_id}
    func taskRunDetail(_ runID: String) async throws -> TaskRunDetailDTO {
        try await get("/api/runs/\(runID)")
    }
}

// MARK: - Samples

/// A sample answer for every Tasks route the phone reads, shaped like the desktop's own (made-up content).
nonisolated enum TasksSamples {

    static let list = #"""
    [
      {"id": "a1b2c3d4e5f6", "name": "Morning summary", "prompt": "Summarise the day in five lines.",
       "schedule_kind": "daily", "run_at": null, "interval_seconds": null, "run_time": "06:30", "enabled": true,
       "next_run_at": "2027-01-05T06:30:00+00:00", "last_run_at": 1793000000.25, "created_at": 1792000000.0,
       "builtin_action": null, "deliver_to_channel": "discord", "endpoint_id": null, "agent_id": null,
       "report_when": null, "trigger": null, "reply_to": null, "context": ""},
      {"id": "b2c3d4e5f6a1", "name": "Check the stock", "prompt": "List anything under five units.",
       "schedule_kind": "interval", "run_at": null, "interval_seconds": 7200, "run_time": null, "enabled": false,
       "next_run_at": "2027-01-04T10:00:00.123456+00:00", "last_run_at": null, "created_at": 1792000100.0,
       "builtin_action": null, "deliver_to_channel": null, "endpoint_id": "ep_local", "agent_id": null,
       "run_started_at": 1793000500.0},
      {"id": "c3d4e5f6a1b2", "name": "Daily brief", "prompt": "(built-in: Daily brief)", "schedule_kind": "daily",
       "run_time": "07:00", "enabled": true, "next_run_at": "2027-01-05T07:00:00+00:00", "created_at": 1792000200.0,
       "builtin_action": "daily_brief", "deliver_to_channel": null, "endpoint_id": null, "agent_id": null},
      {"id": "d4e5f6a1b2c3", "name": "Draft the newsletter", "prompt": "Write a short spring newsletter.",
       "schedule_kind": "card", "run_at": null, "interval_seconds": null, "run_time": null, "enabled": true,
       "next_run_at": null, "last_run_at": 1793000300.0, "created_at": 1792000300.0, "builtin_action": null,
       "deliver_to_channel": null, "endpoint_id": null, "agent_id": "agent_quill",
       "trigger": {"id": "tr_1", "name": "Website form"},
       "status": "review", "depends_on": [], "attempts": 1, "claimed_until": null,
       "comments": [{"at": 1793000200.0, "kind": "feedback", "text": "Shorter, please.", "by": "alex"},
                    {"at": 1793000300.0, "kind": "result", "text": "Draft ready: 320 words.", "by": "jarvis"}]},
      {"id": "e5f6a1b2c3d4", "name": "Make the sale poster", "prompt": "An A4 poster for the sale.",
       "schedule_kind": "card", "created_at": 1792000400.0, "status": "ready", "depends_on": ["d4e5f6a1b2c3"],
       "attempts": 0, "comments": []},
      {"id": "f6a1b2c3d4e5", "name": "Weekly check", "prompt": "Look over open work.", "schedule_kind": "cron",
       "enabled": true, "next_run_at": "2027-01-08T09:00:00+00:00", "created_at": 1792000500.0,
       "agent_id": "agent_scout", "routine": {"schedule": {"kind": "cron", "expression": "0 9 * * 5"}, "revision": 2}}
    ]
    """#

    static let runs = #"""
    [
      {"id": "r1a2b3c4d5e6", "task_id": "a1b2c3d4e5f6", "task_name": "Morning summary", "started_at": 1793000000.25,
       "ran_at": 1793000042.0, "duration_seconds": 41.8, "outcome": "succeeded", "output": "Three events today.",
       "error": null, "delivered": true, "delivery_id": "dl1234567890", "run_id": "run_abc", "source": "schedule",
       "scheduled_for": "2027-01-04T06:30:00+00:00", "late_seconds": 360, "endpoint_id": null, "model": "Claude",
       "attempt": null, "automation_status": "completed",
       "delivery": {"id": "dl1234567890", "channel": "discord", "status": "failed", "attempts": 9,
                    "next_try_at": 1793086000.0, "last_error": "Missing access", "created_at": 1793000042.0,
                    "finished_at": 1793086000.0}},
      {"id": "r2b3c4d5e6f1", "task_id": "a1b2c3d4e5f6", "task_name": "Morning summary", "started_at": null,
       "ran_at": 1792900000.0, "duration_seconds": null, "outcome": "lost", "output": "",
       "error": "Missed scheduled run: the app was not running.", "delivered": null, "delivery_id": null,
       "run_id": null, "source": "schedule", "scheduled_for": "2027-01-03T06:30:00+00:00", "late_seconds": null,
       "model": "Claude", "attempt": null, "automation_status": "missed", "missed_reason": "the app was not running"},
      {"id": "r3c4d5e6f1a2", "task_id": "a1b2c3d4e5f6", "ran_at": 1792800000.0, "output": "An old run.", "error": null}
    ]
    """#

    static let ranNow = #"""
    {"id": "r4d5e6f1a2b3", "task_id": "a1b2c3d4e5f6", "started_at": 1793001000.0, "ran_at": 1793001030.5,
     "duration_seconds": 30.5, "outcome": "succeeded", "output": "Done.", "error": null, "delivered": null,
     "delivery_id": "dl0987654321", "run_id": "run_def", "source": "manual", "model": "Claude",
     "delivery": {"id": "dl0987654321", "channel": "discord", "status": "pending", "attempts": 1,
                  "next_try_at": 1793001090.0, "last_error": "timeout", "created_at": 1793001030.5, "finished_at": null}}
    """#

    static let builtin = #"""
    [
      {"action_id": "daily_brief", "label": "Daily brief", "description": "Your day in a few lines.", "kind": "prompt",
       "default_interval_seconds": 86400, "default_daily_time": "07:00", "uses_model": true, "enabled": true,
       "task_id": "c3d4e5f6a1b2", "deliver_to_channel": null},
      {"action_id": "tidy_sessions", "label": "Tidy old chats", "description": "Archives chats nobody opened in a month.",
       "kind": "action", "default_interval_seconds": 21600, "default_daily_time": null, "uses_model": false,
       "enabled": false, "task_id": null, "deliver_to_channel": null}
    ]
    """#

    static let channels = #"""
    [{"id": "discord", "label": "Discord", "configured": true},
     {"id": "discord:b1:c1", "label": "Discord, #shop (Shop bot)", "configured": true}]
    """#

    static let retried = #"""
    {"id": "dl1234567890", "channel": "discord", "status": "pending", "attempts": 0, "next_try_at": 1793090000.0,
     "last_error": "Missing access", "created_at": 1793090000.0, "finished_at": null}
    """#

    static let runDetail = #"""
    {"id": "run_abc", "surface": "task", "task_id": "a1b2c3d4e5f6", "started_at": 1793000000.3, "ended_at": 1793000042.0,
     "label": "Morning summary", "tokens_per_second": null,
     "steps": [{"at": 1793000001.0, "kind": "tool_started", "name": "calendar_list", "ok": null, "detail": null, "seconds": null},
               {"at": 1793000003.0, "kind": "tool_finished", "name": "calendar_list", "ok": true, "detail": "3 events", "seconds": 1.8}],
     "parent": null, "children": [], "helpers": [], "task_run": {"outcome": "succeeded", "delivered": true}}
    """#

    static let refused = #"""
    {"detail": "this card is running, finished, or still waiting on other cards"}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("tasks.list") {
            let all = try KJSON.decode([TaskRecordDTO].self, from: TasksSamples.list)
            let cards = all.filter { $0.scheduleKind == "card" }
            guard all.count == 6, cards.count == 2,
                  cards.first?.comments?.last?.kind == "result", cards.first?.trigger?.name == "Website form",
                  cards.last?.dependsOn == ["d4e5f6a1b2c3"],
                  all[1].intervalSeconds == 7200, all[1].runStartedAt != nil, all[2].builtinAction == "daily_brief",
                  all[5].routine != nil,
                  TasksWire.date(all[0].nextRunAt) != nil, TasksWire.date(all[1].nextRunAt) != nil,
                  TasksWire.clock(all[0].runTime)?.minute == 30 else { throw SampleMismatch("task fields") }
            return "\(all.count - cards.count) tasks, \(cards.count) cards"
        },
        DecodeCheck("tasks.runs") {
            let runs = try KJSON.decode([TaskRunDTO].self, from: TasksSamples.runs)
            guard runs.count == 3, runs[0].delivery?.status == "failed", runs[0].lateSeconds == 360,
                  runs[0].runId == "run_abc", runs[1].missedReason != nil, runs[2].outcome == nil,
                  TasksWire.date(runs[0].scheduledFor) != nil else { throw SampleMismatch("run fields") }
            return "delivery, late, missed, old record"
        },
        DecodeCheck("tasks.run") {
            let ran = try KJSON.decode(TaskRunDTO.self, from: TasksSamples.ranNow)
            let bare = try KJSON.decode(TaskRunDTO.self, from: #"{"ok": true}"#)
            let refused = try KJSON.decode(APIErrorBody.self, from: TasksSamples.refused)
            guard ran.outcome == "succeeded", ran.delivery?.attempts == 1, bare.ok == true, bare.id == nil,
                  refused.text.hasPrefix("this card") else { throw SampleMismatch("run now fields") }
            return "a run, a bare ok, a refusal"
        },
        DecodeCheck("tasks.library") {
            let library = try KJSON.decode([TaskBuiltinDTO].self, from: TasksSamples.builtin)
            let channels = try KJSON.decode([TaskChannelDTO].self, from: TasksSamples.channels)
            guard library.count == 2, library[0].taskId != nil, TasksWire.clock(library[0].defaultDailyTime)?.hour == 7,
                  library[1].usesModel == false, channels.count == 2, channels[0].configured == true
            else { throw SampleMismatch("library or channels") }
            return "library and channels"
        },
        DecodeCheck("tasks.delivery") {
            let retried = try KJSON.decode(TaskDeliveryDTO.self, from: TasksSamples.retried)
            let detail = try KJSON.decode(TaskRunDetailDTO.self, from: TasksSamples.runDetail)
            guard retried.status == "pending", detail.steps?.count == 2, detail.steps?.last?.seconds == 1.8,
                  TasksWire.stepLabel(detail.steps?.first?.kind) == "Started" else { throw SampleMismatch("delivery or steps") }
            return "retry and steps"
        },
    ]
}
