import Foundation

// The desktop's routine, trigger and watch routes as the Bots area reads them: one decoder per answer and
// one function per route. Shapes were read from routes/bot_routine_routes.py with services/bot_routines.py
// (view, run_view, preview, run_now), core/bot_schedules.py (the schedule kinds), routes/bot_event_routes.py
// with services/trigger_service.py (public) and services/bot_app_triggers.py (public), services/bot_limit_resets.py
// (windows), and routes/front_desk_watch_routes.py with services/front_desk_watch.py (state, settings).
//
// - Lists are decoded item by item: one item of an unexpected shape is left out and counted, never the list.
// - A webhook's address carries its secret. Nothing here asks for it or decodes it.
// - A routine's `schedule` is kept as free JSON and read with `BotRoutineWire.field`, which takes the key
//   in either spelling (the shared decoder may or may not convert a free object's keys).
// - Every refusal is `{"detail": text, ...}`, which `APIError` already reads.

// MARK: - Item by item

/// One list item that decodes, or nil when it does not. The list around it still decodes.
nonisolated struct BotRoutineLossy<T: Decodable & Sendable>: Decodable, Sendable {
    var value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - Routines

/// One routine as GET /api/bot-routines, GET /api/bot-routines/{id}, POST, PATCH and restore answer it
/// (bot_routines.py: view). `revision` is text such as "r3"; `next_run_at` is ISO text; `created_at` is epoch.
nonisolated struct BotRoutineDTO: Decodable, Sendable {
    var id: String
    var botId: String?
    var name: String?
    var instructions: String?
    var enabled: Bool?
    /// "notable" or "always".
    var report: String?
    /// once {at}, daily {time, weekdays?, time_zone}, interval {every_minutes, anchor_at, weekdays?, window?,
    /// ends_at?, time_zone}, cron {expression, time_zone}, limit_reset {endpoint_id, repeat}. Nil for an old goal
    /// whose schedule could not be read.
    var schedule: JSONValue?
    var sentence: String?
    var nextRunAt: String?
    /// "skip" or "queue".
    var overlap: String?
    /// "normal" or "read-and-draft".
    var access: String?
    var deliver: String?
    var durationMinutes: Int?
    var timeoutMinutes: Int?
    var continuity: Bool?
    var call: Bool?
    var runOnStartup: Bool?
    var resultsThreadId: String?
    var revision: String?
    var legacy: Bool?
    /// "needs_you", "working", "paused" or "done".
    var state: String?
    var status: BotRoutineStatusDTO?
    var running: Bool?
    var waiting: Bool?
    var recentRuns: [BotRoutineLossy<BotRoutineRunDTO>]?
    var lastRun: BotRoutineLossy<BotRoutineRunDTO>?
    /// Only with a start and an end: ISO times inside them, for the calendar.
    var occurrences: [String]?
    var createdAt: Double?
}

nonisolated struct BotRoutineStatusDTO: Decodable, Sendable {
    var failureStreak: Int?
    var checkTrouble: [JSONValue]?
    var queued: Bool?
}

/// One run (bot_routines.py: run_view). `started_at` and `finished_at` are epoch seconds, `scheduled_for` ISO text.
nonisolated struct BotRoutineRunDTO: Decodable, Sendable {
    var id: String
    var routineId: String?
    var name: String?
    /// queued, running, waiting, completed, cancelled, missed or failed.
    var status: String?
    var outcome: String?
    var scheduledFor: String?
    var startedAt: FlexibleDate?
    var finishedAt: FlexibleDate?
    var durationSeconds: Double?
    var triggerType: String?
    var attention: JSONValue?
    var seen: Bool?
    var summary: String?
    var error: String?
}

/// GET /api/bot-routines: {"routines": [...]}.
nonisolated struct BotRoutineListDTO: Decodable, Sendable {
    var routines: [BotRoutineLossy<BotRoutineDTO>]?
}

/// POST /api/bot-routines/preview (bot_schedules.py: preview, plus the normalized schedule).
nonisolated struct BotRoutinePreviewDTO: Decodable, Sendable {
    var sentence: String?
    var next: [String]?
    var timeZone: String?
}

/// POST /api/bot-routines/{id}/run: started, or the same request seen again within five minutes.
nonisolated struct BotRoutineRunAnswerDTO: Decodable, Sendable {
    var started: Bool?
    var duplicate: Bool?
    var run: BotRoutineLossy<BotRoutineRunDTO>?
}

// MARK: - Triggers

/// A webhook from GET /api/bot-webhooks or PATCH /api/bot-webhooks/{id} (trigger_service.py: public, without
/// the secret, and bot_event_routes.py: _shown), or a connected-app trigger from GET /api/bot-app-triggers or
/// PATCH /api/bot-app-triggers/{id} (bot_app_triggers.py: public). The address is never read.
nonisolated struct BotEventTriggerDTO: Decodable, Sendable {
    var id: String
    var name: String?
    var enabled: Bool?
    var agentId: String?
    var events: [String]?
    var autoRun: Bool?
    var promptTemplate: String?
    var lastEventAt: FlexibleDate?
    var pendingRuns: Int?
    var maxPending: Int?
    // Connected-app triggers only.
    /// "mail", "calendar" or "kairos".
    var adapter: String?
    var revision: Int?
    /// "ok", "error" or "needs_reconnect".
    var state: String?
    var lastError: String?
}

/// GET /api/bot-webhooks: {"webhooks": [...], "deleted": [...]}.
nonisolated struct BotWebhookListDTO: Decodable, Sendable {
    var webhooks: [BotRoutineLossy<BotEventTriggerDTO>]?
}

/// GET /api/bot-app-triggers: {"triggers": [...], "deleted": [...]}.
nonisolated struct BotAppTriggerListDTO: Decodable, Sendable {
    var triggers: [BotRoutineLossy<BotEventTriggerDTO>]?
}

// MARK: - Usage limits

/// One connected model's account windows (bot_limit_resets.py: normalize). `resets_at` is epoch seconds.
nonisolated struct BotLimitDTO: Decodable, Sendable {
    var endpointId: String
    var name: String?
    var provider: String?
    var blocked: Bool?
    var nearLimit: Bool?
    var resetsAt: FlexibleDate?
    var windows: [BotRoutineLossy<BotLimitWindowDTO>]?
}

nonisolated struct BotLimitWindowDTO: Decodable, Sendable {
    var name: String?
    var usedPercent: Double?
    var resetsAt: FlexibleDate?
}

/// GET /api/bot-limit-resets: {"limits": [...]}.
nonisolated struct BotLimitListDTO: Decodable, Sendable {
    var limits: [BotRoutineLossy<BotLimitDTO>]?
}

// MARK: - Kip's watch

/// GET /api/front-desk/watch (front_desk_watch.py: state). The watch is a routine of Kip's: `routine_id` and
/// `revision` are that routine's, so pausing it is a routine PATCH.
nonisolated struct BotWatchDTO: Decodable, Sendable {
    var routineId: String?
    var enabled: Bool?
    /// "working", "paused", "off" or "not_connected".
    var state: String?
    var revision: JSONValue?
    var lastCheckAt: FlexibleDate?
    var nextAt: String?
    var connected: BotWatchSourcesDTO?
    var available: Bool?
    var morning: BotWatchMorningDTO?

    var revisionText: String? {
        if let text = revision?.string { return text }
        if let number = revision?.int { return "r\(number)" }
        return nil
    }
}

nonisolated struct BotWatchSourcesDTO: Decodable, Sendable {
    var mail: Bool?
    var calendar: Bool?
}

/// The morning brief setting, also the answer of PATCH /api/front-desk/watch/settings. `time` is "HH:MM" in `zone`.
nonisolated struct BotWatchMorningDTO: Decodable, Sendable {
    var on: Bool?
    var time: String?
    var zone: String?
}

// MARK: - Reading the wire

nonisolated enum BotRoutineWire {
    /// A key of a free JSON object, as written ("time_zone") or as the shared decoder may turn it ("timeZone").
    static func field(_ object: JSONValue?, _ key: String) -> JSONValue? {
        guard let object else { return nil }
        if let value = object[key], !value.isNull { return value }
        let camel = camelCase(key)
        if camel != key, let value = object[camel], !value.isNull { return value }
        return nil
    }

    static func camelCase(_ key: String) -> String {
        let parts = key.split(separator: "_")
        guard let first = parts.first else { return key }
        return String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    /// A free JSON value as plain Foundation values, to send back as it came.
    static func plain(_ value: JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let flag): return flag
        case .number(let number): return number == number.rounded() && abs(number) < 1e15 ? Int(number) : number
        case .string(let text): return text
        case .array(let items): return items.map(plain)
        case .object(let fields):
            var out: [String: Any] = [:]
            for (key, item) in fields { out[snakeCase(key)] = plain(item) }
            return out
        }
    }

    /// "timeZone" as "time_zone"; a key already in snake case stays as it is.
    static func snakeCase(_ key: String) -> String {
        var out = ""
        for character in key {
            if character.isUppercase {
                out += "_" + character.lowercased()
            } else {
                out.append(character)
            }
        }
        return out
    }

    /// The decoded items of a lossy list, and how many were left out.
    static func items<T: Decodable & Sendable>(_ list: [BotRoutineLossy<T>]?) -> (items: [T], skipped: Int) {
        let all = list ?? []
        let items = all.compactMap(\.value)
        return (items, all.count - items.count)
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/bot-routines: every routine this account may see. With `start` and `end` (epoch seconds, at
    /// most 70 days apart) each enabled one also lists its occurrences between them.
    func botRoutines(start: Date? = nil, end: Date? = nil) async throws -> BotRoutineListDTO {
        var query: [String: String?] = [:]
        if let start, let end {
            query["start"] = String(Int(start.timeIntervalSince1970))
            query["end"] = String(Int(end.timeIntervalSince1970))
        }
        return try await get("/api/bot-routines", query: query)
    }

    /// GET /api/bot-routines/{id}: the routine with its last 20 runs.
    func botRoutine(_ id: String) async throws -> BotRoutineDTO {
        try await get("/api/bot-routines/\(id)")
    }

    /// POST /api/bot-routines: `bot_id`, `name`, `instructions`, `schedule` and only the options the person set.
    func botRoutineCreate(_ body: [String: Any]) async throws -> BotRoutineDTO {
        try await post("/api/bot-routines", json: body)
    }

    /// PATCH /api/bot-routines/{id}: only the changed fields, with `expected_revision` (409 when stale).
    func botRoutineUpdate(_ id: String, _ fields: [String: Any]) async throws -> BotRoutineDTO {
        try await request("PATCH", "/api/bot-routines/\(id)", json: fields)
    }

    /// DELETE /api/bot-routines/{id}: kept seven days so it can be restored.
    func botRoutineDelete(_ id: String, expectedRevision: String?) async throws {
        var body: [String: Any] = [:]
        if let expectedRevision { body["expected_revision"] = expectedRevision }
        try await call("DELETE", "/api/bot-routines/\(id)", json: body)
    }

    /// POST /api/bot-routines/{id}/restore
    func botRoutineRestore(_ id: String) async throws -> BotRoutineDTO {
        try await post("/api/bot-routines/\(id)/restore")
    }

    /// POST /api/bot-routines/{id}/run: starts the run and answers within a few seconds. The same
    /// `request_id` within five minutes starts nothing new (bot_routines.py: run_now).
    func botRoutineRun(_ id: String, requestID: String) async throws -> BotRoutineRunAnswerDTO {
        try await post("/api/bot-routines/\(id)/run", json: ["request_id": requestID])
    }

    /// POST /api/bot-routines/preview: the desktop's sentence and next times for a schedule, or its field error.
    func botRoutinePreview(_ schedule: [String: Any], count: Int = 3) async throws -> BotRoutinePreviewDTO {
        try await post("/api/bot-routines/preview", json: ["schedule": schedule, "count": count])
    }

    /// POST /api/bot-routine-runs/{id}/seen: the run no longer asks for attention.
    func botRoutineRunSeen(_ runID: String) async throws {
        try await call("POST", "/api/bot-routine-runs/\(runID)/seen")
    }

    /// GET /api/bot-webhooks
    func botWebhooks() async throws -> BotWebhookListDTO {
        try await get("/api/bot-webhooks")
    }

    /// PATCH /api/bot-webhooks/{id} with `enabled` only.
    func botWebhookSetEnabled(_ id: String, _ enabled: Bool) async throws -> BotEventTriggerDTO {
        try await request("PATCH", "/api/bot-webhooks/\(id)", json: ["enabled": enabled])
    }

    /// GET /api/bot-app-triggers
    func botAppTriggers() async throws -> BotAppTriggerListDTO {
        try await get("/api/bot-app-triggers")
    }

    /// PATCH /api/bot-app-triggers/{id} with `enabled` and `expected_revision` (409 when stale).
    func botAppTriggerSetEnabled(_ id: String, _ enabled: Bool, expectedRevision: Int?) async throws -> BotEventTriggerDTO {
        var body: [String: Any] = ["enabled": enabled]
        if let expectedRevision { body["expected_revision"] = String(expectedRevision) }
        return try await request("PATCH", "/api/bot-app-triggers/\(id)", json: body)
    }

    /// GET /api/bot-limit-resets
    func botLimitResets() async throws -> BotLimitListDTO {
        try await get("/api/bot-limit-resets")
    }

    /// POST /api/bot-limit-resets/after-reset: only this routine's next run moves to just after the reset.
    func botRoutineAfterReset(_ id: String) async throws -> BotRoutineDTO {
        try await post("/api/bot-limit-resets/after-reset", json: ["routine_id": id])
    }

    /// GET /api/front-desk/watch: only the account that owns Kip.
    func botWatch() async throws -> BotWatchDTO {
        try await get("/api/front-desk/watch")
    }

    /// PATCH /api/front-desk/watch/settings: `morning_on` and `morning_time` ("HH:MM"), only what changed.
    func botWatchSettings(_ fields: [String: Any]) async throws -> BotWatchMorningDTO {
        try await request("PATCH", "/api/front-desk/watch/settings", json: fields)
    }
}

// MARK: - Samples

/// A sample answer for every route above, shaped like the desktop's own (made-up content).
nonisolated enum BotRoutineSamples {

    static let list = #"""
    {"routines": [
      {"id": "a1b2c3d4e5f6", "bot_id": "agent_scout", "owner": "owner1", "name": "Morning summary",
       "instructions": "Summarise the day in five lines.", "enabled": true, "report": "notable",
       "schedule": {"kind": "daily", "time": "09:00", "time_zone": "America/New_York", "weekdays": [0, 1, 2, 3, 4]},
       "sentence": "Every weekday at 9 AM Eastern time", "next_run_at": "2027-01-05T14:00:00+00:00",
       "overlap": "skip", "access": "normal", "deliver": "normal", "duration_minutes": 30, "timeout_minutes": null,
       "continuity": false, "call": false, "run_on_startup": false, "attachments": [], "checks": [],
       "source_thread_id": null, "results_thread_id": null, "revision": "r3", "legacy": false, "state": "working",
       "status": {"skipped": {}, "check_trouble": [], "failure_streak": 0, "weekly": {}, "wake_at": null,
                  "queued": false, "held_until": null, "deferred_since": null},
       "running": false, "waiting": false,
       "recent_runs": [{"id": "run_1", "routine_id": "a1b2c3d4e5f6", "name": "Morning summary", "status": "completed",
                        "outcome": "succeeded", "scheduled_for": "2027-01-04T14:00:00+00:00", "started_at": 1793000000.5,
                        "finished_at": 1793000040.0, "duration_seconds": 39.5, "late_seconds": 0, "trigger_type": "schedule",
                        "event_ref": null, "retry_cause": null, "retry_count": 0, "execution_thread_id": null,
                        "destination": null, "attention": null, "seen": false, "report_state": null, "model_ran": true,
                        "summary": "Three meetings today.", "output": "Three meetings today.", "error": null,
                        "missed_occurrences": null, "run_id": "r_abc"}],
       "last_run": {"id": "run_1", "status": "completed", "outcome": "succeeded", "started_at": 1793000000.5,
                    "finished_at": 1793000040.0, "seen": false},
       "occurrences": ["2027-01-05T14:00:00+00:00", "2027-01-06T14:00:00+00:00"],
       "created_at": 1792000000.0},
      {"id": "b2c3d4e5f6a1", "bot_id": "agent_scout", "name": "Check the stock", "instructions": "List anything low.",
       "enabled": false, "schedule": {"kind": "interval", "every_minutes": 120, "anchor_at": "2027-01-04T08:00:00+00:00",
       "time_zone": null, "window": {"start": "08:00", "end": "18:00"}, "weekdays": [0, 1, 2, 3, 4, 5]},
       "sentence": "Every 2 hours on Mon, Tue, Wed, Thu, Fri, Sat between 8 AM and 6 PM", "next_run_at": null,
       "overlap": "queue", "access": "read-and-draft", "timeout_minutes": 15, "revision": "Lab12cd34ef56",
       "legacy": true, "state": "needs_you", "status": {"failure_streak": 2, "check_trouble": []},
       "running": false, "waiting": false, "recent_runs": [],
       "last_run": {"id": "run_2", "status": "failed", "error": "The model was not reachable.",
                    "attention": "failed twice", "seen": false, "finished_at": 1793001000.0}},
      {"id": "c3d4e5f6a1b2", "bot_id": "agent_quill", "name": "After the reset",
       "instructions": "Finish the draft.", "enabled": true,
       "schedule": {"kind": "limit_reset", "endpoint_id": "ep_sub", "repeat": "every_reset"},
       "sentence": "When the usage limit resets, every time", "revision": "r1", "state": "working",
       "status": {"failure_streak": 0}, "recent_runs": [], "last_run": null},
      {"id": "d4e5f6a1b2c3", "bot_id": "agent_quill", "name": 42}
    ]}
    """#

    static let preview = #"""
    {"sentence": "Every weekday at 9 AM Eastern time",
     "next": ["2027-01-05T14:00:00+00:00", "2027-01-06T14:00:00+00:00", "2027-01-07T14:00:00+00:00"],
     "time_zone": "America/New_York",
     "schedule": {"kind": "daily", "time": "09:00", "time_zone": "America/New_York", "weekdays": [0, 1, 2, 3, 4]}}
    """#

    static let ran = #"""
    {"started": true, "run": {"id": "run_3", "routine_id": "a1b2c3d4e5f6", "status": "running", "outcome": "running",
     "started_at": 1793002000.0, "finished_at": null, "seen": false}}
    """#

    static let ranAgain = #"""
    {"started": false, "duplicate": true, "run": null}
    """#

    static let stale = #"""
    {"detail": "This routine changed since you opened it. Reload it and try again.", "code": "stale", "field": null}
    """#

    static let webhooks = #"""
    {"webhooks": [
      {"id": "f1e2d3c4b5a6", "name": "New orders", "enabled": true, "preset": "generic", "action": "card",
       "agent_id": "agent_scout", "task_id": null, "room_id": null, "bot_id": null, "endpoint_id": null,
       "events": ["order.created"], "conditions": [], "title_template": "", "prompt_template": "Check the order.",
       "auto_run": false, "ingress": "address", "max_pending": 3, "owner_user": "owner1", "capture": false,
       "last_capture_at": null, "deliver_to_channel": null, "created_at": 1792000000.0, "last_event_at": 1793000000.0,
       "path": "/api/triggers/f1e2d3c4b5a6", "pending_runs": 1, "has_sample": true, "attempt_count": 4}
     ],
     "deleted": []}
    """#

    static let appTriggers = #"""
    {"triggers": [
      {"id": "a6b5c4d3e2f1", "owner_user": "owner1", "agent_id": "agent_scout", "name": "Mail from suppliers",
       "adapter": "mail", "events": ["mail.received"], "config": {}, "prompt_template": "Sort the message.",
       "title_template": "", "conditions": [], "auto_run": false, "enabled": false, "revision": 4,
       "delivery": "poll", "state": "needs_reconnect", "last_error": "Sign in to the mail account again.",
       "fail_streak": 3, "created_at": 1792000000.0, "updated_at": 1793000000.0, "deleted_at": null,
       "last_poll_at": 1793000000.0, "last_event_at": null, "next_poll_at": 1793000300.0,
       "delivery_label": "Checks every 5 minutes", "pending_runs": 0, "poisoned": 0},
      {"id": 7}
     ],
     "deleted": []}
    """#

    static let limits = #"""
    {"limits": [
      {"endpoint_id": "ep_sub", "name": "Claude (subscription)", "provider": "claude", "status": "ok", "stale": false,
       "windows": [{"name": "5-hour", "used_percent": 92.0, "resets_at": 1793010000.0, "blocked": false, "near_limit": true},
                   {"name": "Weekly", "used_percent": 40.0, "resets_at": 1793400000.0, "blocked": false, "near_limit": false}],
       "blocked": false, "near_limit": true, "resets_at": 1793010000.0}
    ]}
    """#

    static let watch = #"""
    {"routine_id": "e5f6a1b2c3d4", "enabled": true, "state": "working", "revision": "r2",
     "last_check_at": 1793000000.0, "last_result": null, "next_at": "2027-01-05T14:15:00+00:00",
     "connected": {"mail": true, "calendar": false}, "available": true, "edited": false,
     "morning": {"on": true, "time": "08:00", "zone": "America/New_York"}}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("botroutines.list") {
            let list = try KJSON.decode(BotRoutineListDTO.self, from: BotRoutineSamples.list)
            let (routines, skipped) = BotRoutineWire.items(list.routines)
            guard routines.count == 3, skipped == 1,
                  BotRoutineWire.field(routines[0].schedule, "time_zone")?.string == "America/New_York",
                  BotRoutineWire.field(routines[0].schedule, "weekdays")?.array?.count == 5,
                  routines[0].revision == "r3", routines[0].occurrences?.count == 2,
                  routines[0].recentRuns?.first?.value?.startedAt?.date != nil,
                  BotRoutineWire.field(BotRoutineWire.field(routines[1].schedule, "window"), "start")?.string == "08:00",
                  routines[1].status?.failureStreak == 2, routines[1].lastRun?.value?.attention != nil,
                  routines[1].timeoutMinutes == 15, routines[2].lastRun?.value == nil,
                  BotRoutineWire.field(routines[2].schedule, "repeat")?.string == "every_reset"
            else { throw SampleMismatch("routine fields") }
            return "\(routines.count) routines, \(skipped) left out"
        },
        DecodeCheck("botroutines.preview") {
            let preview = try KJSON.decode(BotRoutinePreviewDTO.self, from: BotRoutineSamples.preview)
            let ran = try KJSON.decode(BotRoutineRunAnswerDTO.self, from: BotRoutineSamples.ran)
            let again = try KJSON.decode(BotRoutineRunAnswerDTO.self, from: BotRoutineSamples.ranAgain)
            let stale = try KJSON.decode(APIErrorBody.self, from: BotRoutineSamples.stale)
            guard preview.next?.count == 3, TasksWire.date(preview.next?.first) != nil,
                  ran.started == true, ran.run?.value?.status == "running",
                  again.duplicate == true, again.run?.value == nil,
                  stale.text.hasPrefix("This routine changed") else { throw SampleMismatch("preview or run") }
            return "preview, run, duplicate, stale"
        },
        DecodeCheck("botroutines.triggers") {
            let hooks = BotRoutineWire.items(try KJSON.decode(BotWebhookListDTO.self, from: BotRoutineSamples.webhooks).webhooks)
            let apps = BotRoutineWire.items(try KJSON.decode(BotAppTriggerListDTO.self, from: BotRoutineSamples.appTriggers).triggers)
            guard hooks.items.count == 1, hooks.items[0].events == ["order.created"], hooks.items[0].pendingRuns == 1,
                  apps.items.count == 1, apps.skipped == 1, apps.items[0].revision == 4,
                  apps.items[0].adapter == "mail", apps.items[0].lastEventAt?.date == nil
            else { throw SampleMismatch("trigger fields") }
            return "a webhook, an app trigger, one left out"
        },
        DecodeCheck("botroutines.limits") {
            let limits = BotRoutineWire.items(try KJSON.decode(BotLimitListDTO.self, from: BotRoutineSamples.limits).limits)
            let watch = try KJSON.decode(BotWatchDTO.self, from: BotRoutineSamples.watch)
            guard limits.items.first?.nearLimit == true, limits.items.first?.resetsAt?.date != nil,
                  limits.items.first?.windows?.first?.value?.usedPercent == 92,
                  watch.revisionText == "r2", watch.morning?.time == "08:00", watch.connected?.mail == true
            else { throw SampleMismatch("limits or watch") }
            return "limits and the watch"
        },
        DecodeCheck("botroutines.wire") {
            let schedule = try KJSON.decode(JSONValue.self, from: #"{"kind": "interval", "every_minutes": 30, "window": {"start": "08:00", "end": "17:00"}}"#)
            let plain = BotRoutineWire.plain(schedule) as? [String: Any]
            guard plain?["every_minutes"] as? Int == 30, (plain?["window"] as? [String: Any])?["end"] as? String == "17:00",
                  BotRoutineWire.snakeCase("everyMinutes") == "every_minutes", BotRoutineWire.camelCase("time_zone") == "timeZone"
            else { throw SampleMismatch("wire helpers") }
            return "schedule sent back as it came"
        },
    ]
}
