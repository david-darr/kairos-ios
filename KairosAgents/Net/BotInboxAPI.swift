import Foundation

// The desktop's routes behind a bot's Inbox half (Bots pass 1), as the phone reads them. Shapes were read from:
// - services/bot_attention.py: inbox (_row), notifications, activity, thread_events
// - core/bot_attention_store.py: notifications, observations (the stored rows)
// - services/bot_activity_report.py: bot_report, approvals_of, _produced
// - routes/task_routes.py and services/task_service.py: the task and card records
// Every list decodes item by item: one row this app cannot read is left out and counted, never the whole list.

/// One list item that decodes when it can. A row that does not fit leaves `value` nil instead of failing the list.
nonisolated struct BotLossy<T: Decodable>: Decodable {
    var value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// What a lossy list held: the rows read, and how many were left out.
nonisolated struct BotLossyList<T> {
    var items: [T]
    var skipped: Int

    init(_ rows: [BotLossy<T>]?) where T: Decodable {
        let all = rows ?? []
        items = all.compactMap(\.value)
        skipped = all.count - items.count
    }
}

// MARK: - The inbox

/// GET /api/bot-attention/inbox (bot_attention.py: inbox), rows read one by one. Each row is the shared
/// `BotInboxRowDTO` (Net/BotAPI.swift).
nonisolated struct BotInboxLossyDTO: Decodable {
    var rows: [BotLossy<BotInboxRowDTO>]?
    var counts: [String: Int]?
    var count: Int?
}

// MARK: - Notifications

/// GET /api/bot-attention/notifications (bot_attention.py: notifications), rows read one by one.
nonisolated struct BotNotificationsLossyDTO: Decodable {
    var rows: [BotLossy<BotNotificationDTO>]?
    var unread: Int?
}

// MARK: - Activity

/// One entry of GET /api/bot-attention/bots/{id}/activity (bot_attention.py: activity, thread_events).
/// `source` is "kairos-runtime" (a stored observation: data keys type, status, label, detail, outcome, turn_id,
/// run_id, message_id) or "kairos-run-timeline" (a run step: data keys kind, name, ok, detail, seconds).
nonisolated struct BotActivityEntryDTO: Decodable, Hashable, Sendable {
    var id: String
    var kind: String?
    var at: Double?
    var source: String?
    var data: [String: JSONValue]?
    var runId: String?
}

nonisolated struct BotActivityDTO: Decodable {
    var entries: [BotLossy<BotActivityEntryDTO>]?
    var total: Int?
}

// MARK: - The bot's report

/// GET /api/bot-reports/bots/{id}?days= (bot_activity_report.py: bot_report).
nonisolated struct BotReportDTO: Decodable {
    var bot: BotReportBotDTO?
    var days: Int?
    var since: Double?
    var generatedAt: Double?
    var totals: BotReportTotalsDTO?
    var produced: [BotLossy<BotReportProducedDTO>]?
    var approvals: BotReportApprovalsDTO?
    var errors: [BotLossy<BotReportErrorDTO>]?
    var runs: [BotLossy<BotReportRunDTO>]?
}

nonisolated struct BotReportBotDTO: Decodable, Hashable, Sendable {
    var id: String?
    var name: String?
    var team: String?
    var teamId: String?
}

nonisolated struct BotReportTotalsDTO: Decodable, Hashable, Sendable {
    var runs: Int?
    var finished: Int?
    var failed: Int?
    var tokens: Int?
    /// Nil when no run in the window was priced (run_cost.summarize), never 0 for unknown.
    var costUsd: Double?
    /// False when some runs have no price, so the spend may be higher.
    var costComplete: Bool?
}

/// One kind of thing it made (bot_activity_report.py: _produced).
nonisolated struct BotReportProducedDTO: Decodable, Hashable, Sendable {
    var key: String?
    var label: String?
    var count: Int?
    var items: [String]?
}

nonisolated struct BotReportApprovalsDTO: Decodable, Hashable, Sendable {
    var summary: BotReportApprovalSummaryDTO?
}

nonisolated struct BotReportApprovalSummaryDTO: Decodable, Hashable, Sendable {
    var asked: Int?
    var allowed: Int?
    var denied: Int?
    var expired: Int?
    var team: Int?
    var couldNotAsk: Int?
}

nonisolated struct BotReportErrorDTO: Decodable, Hashable, Sendable {
    var at: Double?
    var what: String?
    var fix: String?
}

/// One recent run. `outcome` is the run store's own word ("finished", "failed", "stopped", or another);
/// `result` is the desktop's plain label for it.
nonisolated struct BotReportRunDTO: Decodable, Hashable, Sendable {
    var id: String
    var what: String?
    var startedAt: Double?
    var endedAt: Double?
    var outcome: String?
    var result: String?
    var tokens: Int?
    var costUsd: Double?
    var model: String?
    var toolCalls: Int?
}

// MARK: - A bot's work

/// One record of GET /api/tasks (task_service.py), only what a bot's Working and Done lists need.
/// A card has `schedule_kind` "card" and a board `status`; a routine has a schedule and `run_started_at` while it runs.
nonisolated struct BotWorkCardDTO: Decodable {
    var id: String
    var name: String?
    var scheduleKind: String?
    /// backlog, ready, running, review, done or blocked (cards only).
    var status: String?
    var agentId: String?
    var createdAt: Double?
    var statusChangedAt: Double?
    var lastRunAt: Double?
    var runStartedAt: Double?
    var attempts: Int?
    var comments: [BotLossy<TaskCommentDTO>]?

    /// The newest result or error note, which is what the desktop's board shows.
    var latestNote: String? {
        let notes = (comments ?? []).compactMap(\.value)
        return notes.last { $0.kind == "result" || $0.kind == "error" }?.text
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/bot-attention/inbox, read row by row.
    func botInboxRows() async throws -> BotInboxLossyDTO {
        try await get("/api/bot-attention/inbox")
    }

    /// GET /api/bot-attention/notifications, read row by row. Every bot's; the screen keeps one bot's.
    func botNotificationRows() async throws -> BotNotificationsLossyDTO {
        try await get("/api/bot-attention/notifications")
    }

    /// GET /api/bot-attention/bots/{id}/activity: newest first, at most `limit` (the desktop caps it at 400).
    func botActivity(_ botID: String, limit: Int = 300) async throws -> BotActivityDTO {
        try await get("/api/bot-attention/bots/\(botID)/activity", query: ["limit": String(limit)])
    }

    /// GET /api/bot-reports/bots/{id}?days= (1 to 90).
    func botReport(_ botID: String, days: Int) async throws -> BotReportDTO {
        try await get("/api/bot-reports/bots/\(botID)", query: ["days": String(max(1, min(days, 90)))])
    }

    /// GET /api/tasks, read record by record.
    func botWorkCards() async throws -> [BotLossy<BotWorkCardDTO>] {
        try await get("/api/tasks")
    }
}

// MARK: - Samples

/// A sample answer for every route above, shaped like the desktop's own (made-up content).
nonisolated enum BotInboxSamples {

    static let inbox = #"""
    {"rows": [
      {"id": "item:a1b2c3d4e5f6", "source_id": "item:a1b2c3d4e5f6", "kind": "question",
       "sender": {"id": "agent_scout", "name": "Scout"}, "subject": "Which supplier should I ask first?",
       "snippet": "Two have the part in stock.", "body": "Two have the part in stock. One is cheaper, one is faster.",
       "at": 1793000000.5, "status": "open",
       "target": {"tab": "botsShell", "agentId": "agent_scout", "sessionId": "s_1"},
       "actions": ["reply", "close"], "revision": "0f1e2d3c4b5a69788796a5b4c3d2e1f0", "answer": null,
       "questions": [], "read": false, "done": false, "bucket": "needs-you"},
      {"id": "review:b2c3d4e5f6a1", "source_id": "review:b2c3d4e5f6a1", "kind": "review",
       "sender": {"id": "agent_scout", "name": "Scout"}, "subject": "Draft the spring newsletter",
       "snippet": "Draft ready: 320 words.", "body": "Draft ready: 320 words.", "at": 1792999000.0, "status": "open",
       "target": {"tab": "botsShell", "agentId": "agent_scout"}, "actions": ["approve", "reply", "open"],
       "revision": "1a2b3c4d5e6f708192a3b4c5d6e7f801", "answer": null, "questions": [],
       "read": true, "done": false, "bucket": "needs-you"},
      {"id": "item:c3d4e5f6a1b2", "kind": "report", "sender": {"id": "agent_scout", "name": "Scout"},
       "subject": "Stock check done", "at": 1792990000.0, "status": "resolved", "actions": [],
       "revision": "2b3c4d5e6f708192a3b4c5d6e7f80112", "read": true, "done": false, "bucket": "done"},
      {"kind": "question", "subject": "A row with no id"}
    ], "counts": {"needs-you": 2, "news": 0, "done": 1}, "count": 2}
    """#

    static let notifications = #"""
    {"rows": [
      {"kind": "missed-call", "agent_id": "agent_scout", "title": "Scout called you", "body": "About the order",
       "target": {"tab": "botsShell", "agentId": "agent_scout"}, "inbox_id": null, "at": 1793000100.0,
       "backlog": false, "call_back": {"ring_id": "ring_1"}, "id": "5f4e3d2c1b0a99887766554433221100",
       "source_id": "ring:ring_1", "read": false, "pinned": true},
      {"kind": "turn-failed", "agent_id": "agent_scout", "title": "Reply could not finish",
       "body": "Reply could not finish", "target": {"tab": "botsShell", "agentId": "agent_scout", "sessionId": "s_1"},
       "inbox_id": null, "at": 1793000000.0, "backlog": false, "id": "4e3d2c1b0a9988776655443322110099",
       "source_id": "turn:s_1:t_1:turn-failed", "read": true, "pinned": false},
      {"kind": "question", "agent_id": "agent_quill", "title": "Which colour for the poster?", "body": "Blue or green",
       "target": {"tab": "botsShell", "agentId": "agent_quill"}, "inbox_id": "item:d4e5f6a1b2c3", "at": 1792990000.0,
       "backlog": true, "id": "3d2c1b0a998877665544332211009988", "source_id": "item:d4e5f6a1b2c3",
       "read": false, "pinned": false},
      {"kind": "done", "title": "A row with no id", "read": "maybe"}
    ], "unread": 2}
    """#

    static let activity = #"""
    {"entries": [
      {"id": "run:run_abc:1", "kind": "runtime", "at": 1793000003.0, "source": "kairos-run-timeline",
       "data": {"kind": "tool_finished", "name": "web_search", "ok": true, "detail": "5 results", "seconds": 1.8},
       "run_id": "run_abc", "target": {"tab": "botsShell", "agentId": "agent_scout", "sessionId": "s_1"}},
      {"id": "9a8b7c6d5e4f30211203f4e5d6c7b8a9", "kind": "runtime", "at": 1793000000.0, "source": "kairos-runtime",
       "data": {"type": "turn.completed", "status": "completed", "label": "Reply ready", "turn_id": "t_1"},
       "target": {"tab": "botsShell", "agentId": "agent_scout", "sessionId": "s_1"}},
      {"kind": "runtime", "at": "yesterday"}
    ], "total": 3}
    """#

    static let report = #"""
    {"bot": {"id": "agent_scout", "name": "Scout", "role": "Finds sources", "color": "#5B8DEF",
             "approval_mode": "ask", "team": "Shop", "team_id": "dep_1"},
     "days": 7, "since": 1792400000.0, "generated_at": 1793000000.0,
     "totals": {"runs": 12, "finished": 10, "failed": 2, "tokens": 615000, "cost_usd": 1.72, "cost_complete": false},
     "produced": [{"key": "files", "label": "Files", "count": 3, "items": ["prices.csv", "notes.md"]},
                  {"key": "replies", "label": "Conversations it replied in", "count": 6, "items": []},
                  {"key": 5}],
     "approvals": {"summary": {"asked": 4, "allowed": 3, "denied": 1, "expired": 0, "team": 2, "could_not_ask": 0},
                   "recent": [{"at": 1792999000.0, "text": "Send email: you allowed it once.", "outcome": "allow",
                               "source": "asked", "thread_id": "s_1"}]},
     "errors": [{"at": 1792998000.0, "what": "The model's limit was reached.",
                 "fix": "Wait for it to reset, or pick another model in its Model settings.",
                 "link": {"tab": "botsShell", "agentId": "agent_scout", "runId": "run_x"}},
                {"at": null, "what": "1 step(s) did not run because nobody was there to ask.", "fix": "Keep it open.",
                 "link": null}],
     "runs": [{"id": "run_abc", "what": "Card: Rival prices", "started_at": 1792999900.0, "ended_at": 1792999960.0,
               "outcome": "finished", "result": "Finished", "tokens": 42000, "cost_usd": 0.12, "model": "a-model",
               "tool_calls": 5, "steps": ["Searched the web (3 times)"], "failed_steps": [], "truncated": false,
               "link": {"tab": "botsShell", "agentId": "agent_scout", "runId": "run_abc"}},
              {"id": "run_def", "what": "Conversation turn", "started_at": 1792999000.0, "ended_at": null,
               "outcome": "running", "result": "running", "tokens": null, "cost_usd": null, "model": null,
               "tool_calls": 0, "steps": [], "failed_steps": [], "truncated": false, "link": null},
              {"what": "A run with no id"}]}
    """#

    static let work = #"""
    [
      {"id": "c1a2b3c4d5e6", "name": "Rival prices", "prompt": "Compare three shops.", "schedule_kind": "card",
       "status": "running", "agent_id": "agent_scout", "created_at": 1792990000.0, "attempts": 1,
       "run_started_at": 1793000000.0, "status_changed_at": 1793000000.0, "comments": []},
      {"id": "c2b3c4d5e6f1", "name": "Supplier email", "schedule_kind": "card", "status": "blocked",
       "agent_id": "agent_scout", "created_at": 1792980000.0, "attempts": 3,
       "comments": [{"at": 1792990000.0, "kind": "error", "text": "Could not sign in.", "by": "jarvis"},
                    {"at": "bad", "kind": 7}]},
      {"id": "c3c4d5e6f1a2", "name": "Weekly report", "schedule_kind": "card", "status": "done",
       "agent_id": "agent_scout", "created_at": 1792970000.0, "status_changed_at": 1792999000.0,
       "comments": [{"at": 1792998000.0, "kind": "result", "text": "Report sent.", "by": "jarvis"}]},
      {"id": "t4d5e6f1a2b3", "name": "Morning check", "schedule_kind": "daily", "agent_id": "agent_scout",
       "created_at": 1792960000.0, "run_started_at": 1793000100.0, "enabled": true},
      {"name": "A record with no id"}
    ]
    """#

    static let responded = #"""
    {"ok": true, "result": "sent back with your note; it will redo it"}
    """#

    static let refused = #"""
    {"detail": "That request is no longer available. Reload and try again."}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("bots.inbox") {
            let inbox = try KJSON.decode(BotInboxLossyDTO.self, from: BotInboxSamples.inbox)
            let rows = BotLossyList(inbox.rows)
            let needs = rows.items.filter { $0.bucket == "needs-you" && $0.sender?.id == "agent_scout" }
            guard rows.items.count == 3, rows.skipped == 1, needs.count == 2,
                  needs[0].actions == ["reply", "close"], needs[1].actions?.contains("approve") == true,
                  needs[1].revision?.isEmpty == false, inbox.counts?["needs-you"] == 2,
                  BotsInboxWire.lane(needs[0].id) == "item", BotsInboxWire.lane(needs[1].id) == "review"
            else { throw SampleMismatch("inbox rows") }
            let answer = try KJSON.decode(BotInboxRespondResultDTO.self, from: BotInboxSamples.responded)
            let refused = try KJSON.decode(APIErrorBody.self, from: BotInboxSamples.refused)
            guard answer.ok == true, refused.text.hasPrefix("That request") else { throw SampleMismatch("respond") }
            return "2 waiting, 1 resolved, 1 left out"
        },
        DecodeCheck("bots.notifications") {
            let feed = try KJSON.decode(BotNotificationsLossyDTO.self, from: BotInboxSamples.notifications)
            let rows = BotLossyList(feed.rows)
            let mine = rows.items.filter { $0.agentId == "agent_scout" }
            guard rows.items.count == 3, rows.skipped == 1, mine.count == 2, mine[0].pinned == true,
                  mine[0].callBack?.ringId == "ring_1", mine[1].read == true, feed.unread == 2,
                  BotsInboxWire.noticeLook(mine[0].kind).label == "Missed call",
                  BotsInboxWire.noticeLook(mine[1].kind).problem
            else { throw SampleMismatch("notification rows") }
            return "2 for one bot, 1 left out"
        },
        DecodeCheck("bots.activity") {
            let activity = try KJSON.decode(BotActivityDTO.self, from: BotInboxSamples.activity)
            let rows = BotLossyList(activity.entries)
            guard rows.items.count == 2, rows.skipped == 1, rows.items[0].runId == "run_abc",
                  rows.items[0].data?["ok"]?.bool == true, rows.items[0].data?["seconds"]?.double == 1.8
            else { throw SampleMismatch("activity entries") }
            let lines = rows.items.map(BotsInboxWire.activityLine)
            guard lines[0].source == "Run timeline", lines[0].title == "web_search",
                  lines[1].title == "Reply ready", lines[1].source == "Runtime event"
            else { throw SampleMismatch("activity lines") }
            return "a run step and a runtime event, 1 left out"
        },
        DecodeCheck("bots.report") {
            let report = try KJSON.decode(BotReportDTO.self, from: BotInboxSamples.report)
            let runs = BotLossyList(report.runs)
            let made = BotLossyList(report.produced)
            let errors = BotLossyList(report.errors)
            guard report.days == 7, report.totals?.runs == 12, report.totals?.costUsd == 1.72,
                  report.totals?.costComplete == false, report.approvals?.summary?.couldNotAsk == 0,
                  runs.items.count == 2, runs.skipped == 1, runs.items[1].costUsd == nil,
                  made.items.count == 2, made.skipped == 1, errors.items.count == 2,
                  BotsInboxWire.tokens(615_000) == "615K", BotsInboxWire.money(1.72) == "$1.72"
            else { throw SampleMismatch("report fields") }
            return "totals, 2 runs, 2 made, 2 errors"
        },
        DecodeCheck("bots.work") {
            let all = BotLossyList(try KJSON.decode([BotLossy<BotWorkCardDTO>].self, from: BotInboxSamples.work))
            let mine = all.items.filter { $0.agentId == "agent_scout" }
            let sorted = BotsInboxWire.workRows(mine)
            guard all.items.count == 4, all.skipped == 1, mine[1].latestNote == "Could not sign in.",
                  mine[2].latestNote == "Report sent.", sorted.working.count == 3, sorted.done.count == 1,
                  sorted.working.contains(where: { $0.id == "c2b3c4d5e6f1" && $0.state == .failed }),
                  sorted.working.contains(where: { $0.id == "t4d5e6f1a2b3" && $0.canStop })
            else { throw SampleMismatch("work records") }
            return "3 working or stuck, 1 done, 1 left out"
        },
    ]
}
