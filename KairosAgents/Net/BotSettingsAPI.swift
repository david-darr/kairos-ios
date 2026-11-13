import Foundation

// One bot's settings as the Bots area reads them from the paired desktop: one decoder per answer and one
// function per route. Shapes were read from routes/agent_routes.py with services/agent_service.py (update,
// read_soul, profile_history, rollback_profile, the avatar vocabulary), services/bot_record.py (clean_field,
// overview), services/bot_profile_history.py (rows), services/bot_threads.py (follow_model),
// routes/bot_approval_routes.py with core/bot_policy.py (list_command_rules) and core/bot_outbound.py (usage),
// routes/bot_voice_routes.py with services/bot_voice.py (live_settings) and core/call_voices.py (catalog).
//
// - The bot itself is `AgentDTO` (Net/BotAPI.swift), read with `agentDetail` and changed with `agentUpdate`.
//   Every PATCH carries `expected_revision`; the desktop answers 409 when the profile changed since.
// - Lists are decoded item by item: one item of an unexpected shape is left out, never the list.
// - A free JSON object is read with `BotSetWire.field`, which takes a key in either spelling.

// MARK: - Item by item

/// One list item that decodes, or nil when it does not. The list around it still decodes.
nonisolated struct BotSetLossy<T: Decodable & Sendable>: Decodable, Sendable {
    var value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - Standing instructions

/// GET /api/agents/{id}/soul (agent_service.py: read_soul). `in_sync` false means SOUL.md was edited by hand on
/// the desktop; the desktop then refuses any save of the instructions until that edit is kept or discarded.
nonisolated struct BotSetSoulDTO: Decodable, Sendable {
    var soul: String?
    var fileText: String?
    var inSync: Bool?
    /// The bot's profile revision.
    var revision: Int?
    var bytes: Int?
    var limit: Int?
}

// MARK: - History

/// One change to a bot's profile (bot_profile_history.py: append). `before` and `after` are left out of
/// standing-instruction rows in the list; the single-row route has them.
nonisolated struct BotSetHistoryRowDTO: Decodable, Sendable, Identifiable {
    var id: String
    /// Epoch seconds.
    var ts: Double?
    /// "user", "bot", "file", "import" or "system".
    var actor: String?
    /// The record field, for example "soul", "model_override" or "enabled".
    var field: String?
    var summary: String?
    var before: JSONValue?
    var after: JSONValue?
    var revision: Int?
}

/// GET /api/agents/{id}/history: newest first, and the bot's revision now.
nonisolated struct BotSetHistoryDTO: Decodable, Sendable {
    var rows: [BotSetLossy<BotSetHistoryRowDTO>]?
    var revision: Int?
}

/// POST /api/agents/{id}/history/{row}/rollback.
nonisolated struct BotSetRollbackDTO: Decodable, Sendable {
    var agent: AgentDTO?
    var soulFile: BotSetSoulDTO?
}

// MARK: - Overview

/// GET /api/agents/{id}/overview (bot_record.py: overview).
nonisolated struct BotSetOverviewDTO: Decodable, Sendable {
    var who: BotSetOverviewWhoDTO?
    var does: BotSetOverviewDoesDTO?
    var reaches: BotSetOverviewReachDTO?
    /// Plain sentences: what it will not do.
    var wont: [BotSetLossy<String>]?
    var recent: [BotSetLossy<BotSetOverviewRunDTO>]?
    var grants: BotSetOverviewGrantsDTO?
}

nonisolated struct BotSetOverviewWhoDTO: Decodable, Sendable {
    var name: String?
    var role: String?
    var blurb: String?
    var section: String?
}

nonisolated struct BotSetOverviewItemDTO: Decodable, Sendable {
    var id: String
    var name: String?
    var enabled: Bool?
}

nonisolated struct BotSetOverviewDoesDTO: Decodable, Sendable {
    var routines: [BotSetLossy<BotSetOverviewItemDTO>]?
    var triggers: [BotSetLossy<BotSetOverviewItemDTO>]?
    var openCards: Int?
    var peers: [BotSetLossy<String>]?
}

nonisolated struct BotSetOverviewReachDTO: Decodable, Sendable {
    var endpointId: String?
    var modelOverride: String?
    var modelEffort: String?
    /// The text "all", or a list of app ids.
    var integrations: JSONValue?
    var place: String?
    var keepSignedIn: Bool?
    var deliverToChannel: String?
}

nonisolated struct BotSetOverviewRunDTO: Decodable, Sendable {
    var taskId: String?
    var name: String?
    /// When it finished.
    var ranAt: FlexibleDate?
    var outcome: String?
}

nonisolated struct BotSetOverviewGrantsDTO: Decodable, Sendable {
    var approvalMode: String?
}

// MARK: - Model

/// POST /api/agents/{id}/threads/follow-model (bot_threads.py: follow_model). Busy ones were left as they were.
nonisolated struct BotSetFollowModelDTO: Decodable, Sendable {
    var updated: [String]?
    var busy: [String]?
}

/// One fallback model of a bot: an entry of `fallback` (bot_record.py: _clean_fallback).
nonisolated struct BotSetFallback: Hashable, Sendable {
    var endpointID: String
    var modelOverride: String?

    var plain: [String: Any] {
        var out: [String: Any] = ["endpoint_id": endpointID]
        if let modelOverride { out["model_override"] = modelOverride }
        return out
    }
}

// MARK: - Approval

/// One remembered command (core/bot_policy.py: add_command_rule).
nonisolated struct BotSetCommandRuleDTO: Decodable, Sendable {
    var id: String
    var command: String?
    /// The folder it runs in, as a full path on the desktop.
    var cwd: String?
    var provider: String?
    var createdAt: Double?
}

/// GET /api/bots-approvals/{id}/commands.
nonisolated struct BotSetCommandListDTO: Decodable, Sendable {
    var rules: [BotSetLossy<BotSetCommandRuleDTO>]?
    var limit: Int?
    var stateCorrupt: Bool?
}

/// GET /api/bots-approvals/{id}/outbound (bot_outbound.py: usage, plus the policy).
nonisolated struct BotSetOutboundDTO: Decodable, Sendable {
    /// "ask" or "allow".
    var policy: String?
    var cap: Int?
    var used: Int?
    var reserved: Int?
    var remaining: Int?
    var resetsAt: FlexibleDate?
}

// MARK: - Voice

/// One voice of the account's voice engine (call_voices.py: catalog).
nonisolated struct BotSetVoiceDTO: Decodable, Sendable {
    var id: String
    var name: String?
}

/// GET /api/bot-voice/voices. Only the voices and the error are read; nothing else of the engine.
nonisolated struct BotSetVoiceListDTO: Decodable, Sendable {
    var voices: [BotSetLossy<BotSetVoiceDTO>]?
    var error: String?
}

/// GET /api/bot-voice/live-settings (bot_voice.py: live_settings). Per account, not per bot.
nonisolated struct BotSetLiveVoiceDTO: Decodable, Sendable {
    /// "marin", "cedar", "coral", "sage" or "ash".
    var voice: String?
    var readTyped: Bool?
    var idleMinutes: Int?
}

// MARK: - Reading the wire

nonisolated enum BotSetWire {
    /// A key of a free JSON object, as written ("endpoint_id") or as the shared decoder turns it ("endpointId").
    static func field(_ object: JSONValue?, _ key: String) -> JSONValue? {
        guard let object else { return nil }
        if let value = object[key], !value.isNull { return value }
        let parts = key.split(separator: "_")
        guard let first = parts.first, parts.count > 1 else { return nil }
        let camel = String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        if let value = object[camel], !value.isNull { return value }
        return nil
    }

    /// A bot's fallback list, in order. An entry without a connection is left out.
    static func fallbacks(_ value: JSONValue?) -> [BotSetFallback] {
        (value?.array ?? []).compactMap { item in
            guard let endpoint = field(item, "endpoint_id")?.string, !endpoint.isEmpty else { return nil }
            return BotSetFallback(endpointID: endpoint, modelOverride: field(item, "model_override")?.string)
        }
    }

    /// The outside-message policy stored on a bot ("ask" when none is stored).
    static func outboundPolicy(_ value: JSONValue?) -> String {
        field(value, "policy")?.string ?? "ask"
    }

    /// The decoded items of a lossy list, and how many were left out.
    static func items<T: Decodable & Sendable>(_ list: [BotSetLossy<T>]?) -> (items: [T], skipped: Int) {
        let all = list ?? []
        let items = all.compactMap(\.value)
        return (items, all.count - items.count)
    }

    /// An optional text to send: the text, or JSON null.
    static func text(_ value: String?) -> Any { value.map { $0 as Any } ?? NSNull() }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/agents/{id}/soul: the standing instructions, whether SOUL.md was hand-edited, and the revision.
    func botSettingsSoul(_ botID: String) async throws -> BotSetSoulDTO {
        try await get("/api/agents/\(botID)/soul")
    }

    /// GET /api/agents/{id}/overview
    func botSettingsOverview(_ botID: String) async throws -> BotSetOverviewDTO {
        try await get("/api/agents/\(botID)/overview")
    }

    /// GET /api/agents/{id}/history: the newest `limit` changes (1 to 500).
    func botSettingsHistory(_ botID: String, limit: Int = 100) async throws -> BotSetHistoryDTO {
        try await get("/api/agents/\(botID)/history", query: ["limit": String(limit)])
    }

    /// GET /api/agents/{id}/history/{row}: one change with its full before and after.
    func botSettingsHistoryRow(_ botID: String, rowID: String) async throws -> BotSetHistoryRowDTO {
        try await get("/api/agents/\(botID)/history/\(rowID)")
    }

    /// POST /api/agents/{id}/history/{row}/rollback: put the instructions back as they were before that change.
    /// Only standing-instruction rows. 409 when the profile or SOUL.md changed since they were read.
    func botSettingsRollback(_ botID: String, rowID: String, expectedRevision: Int, expectedFileText: String?) async throws -> BotSetRollbackDTO {
        try await post("/api/agents/\(botID)/history/\(rowID)/rollback", json: [
            "expected_revision": expectedRevision,
            "expected_file_text": BotSetWire.text(expectedFileText),
        ])
    }

    /// POST /api/agents/{id}/threads/follow-model: every conversation goes back to the bot's own model.
    func botSettingsFollowModel(_ botID: String) async throws -> BotSetFollowModelDTO {
        try await post("/api/agents/\(botID)/threads/follow-model")
    }

    /// GET /api/bots-approvals/{id}/commands: the commands this bot may always run.
    func botSettingsCommands(_ botID: String) async throws -> BotSetCommandListDTO {
        try await get("/api/bots-approvals/\(botID)/commands")
    }

    /// DELETE /api/bots-approvals/{id}/commands/{rule}: the bot asks again for that command. 404 when it is gone.
    func botSettingsRemoveCommand(_ botID: String, ruleID: String) async throws {
        try await call("DELETE", "/api/bots-approvals/\(botID)/commands/\(ruleID)")
    }

    /// GET /api/bots-approvals/{id}/outbound: the outside-message policy and today's allowance.
    func botSettingsOutbound(_ botID: String) async throws -> BotSetOutboundDTO {
        try await get("/api/bots-approvals/\(botID)/outbound")
    }

    /// GET /api/bot-voice/voices: the account's voice engine and its voices.
    func botSettingsVoices() async throws -> BotSetVoiceListDTO {
        try await get("/api/bot-voice/voices")
    }

    /// GET /api/bot-voice/live-settings: live voice, read typed replies and idle end, for every bot.
    func botSettingsLiveVoice() async throws -> BotSetLiveVoiceDTO {
        try await get("/api/bot-voice/live-settings")
    }
}

// MARK: - Samples

/// A sample answer for every route above, shaped like the desktop's own (made-up content).
nonisolated enum BotSettingsSamples {

    static let agent = #"""
    {"id": "agent_scout", "name": "Scout", "role": "Finds parts and prices", "blurb": "I look things up.",
     "soul": "Keep it short.", "instructions": "Keep it short.", "revision": 7, "endpoint_id": "ep_claude",
     "model_override": "claude-sonnet", "model_effort": "high", "color": "#b9d2e3", "enabled": true,
     "daily_run_cap": 12, "deliver_to_channel": "telegram", "integration_ids": null,
     "avatar": {"version": 3, "character": "ajar", "shape": "tall", "color": "#B9D2E3", "acc": "quill", "finish": "halftone"},
     "approval_mode": "auto", "outbound": {"policy": "ask", "daily_cap": 25},
     "fallback": [{"endpoint_id": "ep_codex"}, {"endpoint_id": "ep_api", "model_override": "small-model"}, {"model_override": "x"}],
     "cache_keep_warm": "follow", "builtin": null, "reply_style": "conversational", "notifications": true,
     "speak_replies": false, "voice_id": "af_bella", "call_mode": "turns", "status": "idle", "runs_today": 3}
    """#

    static let soul = #"""
    {"soul": "Keep it short.", "file_text": "Keep it short, and sign off.", "in_sync": false, "revision": 7,
     "bytes": 14, "limit": 24000}
    """#

    static let history = #"""
    {"rows": [
      {"id": "h3", "ts": 1793000000.0, "actor": "user", "field": "soul", "summary": "Changed soul", "revision": 7,
       "receipt_id": null},
      {"id": "h2", "ts": 1792990000.0, "actor": "bot", "field": "model_effort", "summary": "Changed model effort",
       "before": "medium", "after": "high", "revision": 6, "receipt_id": "r1"},
      {"id": 9}
     ],
     "revision": 7}
    """#

    static let historyRow = #"""
    {"id": "h3", "ts": 1793000000.0, "actor": "user", "field": "soul", "summary": "Changed soul",
     "before": "Be brief.", "after": "Keep it short.", "revision": 7, "receipt_id": null}
    """#

    static let overview = #"""
    {"who": {"name": "Scout", "role": "Finds parts and prices", "blurb": "", "section": "Shop", "color": "#b9d2e3",
             "avatar": null},
     "does": {"routines": [{"id": "t1", "name": "Morning prices", "schedule_kind": "daily", "run_time": "09:00",
                            "interval_seconds": null, "enabled": true}],
              "triggers": [{"id": "w1", "name": "New orders", "enabled": false}], "open_cards": 2, "peers": ["Quill"]},
     "reaches": {"endpoint_id": "ep_claude", "model_override": null, "model_effort": null, "integrations": "all",
                 "place": "auto", "keep_signed_in": false, "deliver_to_channel": null},
     "wont": ["It stops after 12 runs a day.", "It will not use mail."],
     "recent": [{"task_id": "t1", "name": "Morning prices", "ran_at": 1793000000.0, "outcome": "succeeded"},
                {"task_id": "t1", "name": "Morning prices", "ran_at": "2027-01-04T09:00:30", "outcome": "failed"}],
     "grants": {"approval_mode": "auto", "outbound": {"policy": "ask", "daily_cap": 25}, "always_allow": [],
                "tool_scope": {"allow": [], "deny": []}, "connector_scopes": {}},
     "setup": [{"id": "identity", "done": true, "label": "Give it a name and a job", "section": "identity"}]}
    """#

    static let commands = #"""
    {"rules": [
      {"id": "a1b2c3d4e5f6a7b8", "command": "npm test", "cwd": "/home/owner/shop-site", "provider": "claude",
       "created_at": 1793000000.0, "by": "owner1", "request_id": "q1"},
      {"id": 5}
     ],
     "limit": 200, "state_corrupt": false}
    """#

    static let outbound = #"""
    {"policy": "ask", "cap": 25, "used": 3, "reserved": 0, "remaining": 22, "date": "2027-01-04",
     "zone": "America/New_York", "resets_at": 1793030000.0}
    """#

    static let voices = #"""
    {"protocol": "kokoro", "voices": [{"id": "af_bella", "name": "Bella"}, {"id": "am_adam", "name": "Adam"}, {"name": "No id"}],
     "models": ["kokoro"]}
    """#

    static let liveVoice = #"""
    {"voice": "marin", "read_typed": false, "idle_minutes": 5}
    """#

    static let followModel = #"""
    {"updated": ["s1", "s2"], "busy": ["s3"]}
    """#

    static let stale = #"""
    {"detail": "The profile changed. Reload it before saving."}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("botsettings.agent") {
            let agent = try KJSON.decode(AgentDTO.self, from: BotSettingsSamples.agent)
            let fallbacks = BotSetWire.fallbacks(agent.fallback)
            guard agent.revision == 7, agent.modelEffort == "high", agent.deliverToChannel == "telegram",
                  agent.avatar?.finish == "halftone", agent.mascotShape == .tall,
                  fallbacks == [BotSetFallback(endpointID: "ep_codex"), BotSetFallback(endpointID: "ep_api", modelOverride: "small-model")],
                  BotSetWire.outboundPolicy(agent.outbound) == "ask", agent.replyStyle == "conversational"
            else { throw SampleMismatch("agent fields") }
            let sent = BotSetChange.applying(["model_effort": NSNull(), "fallback": [BotSetFallback(endpointID: "ep_codex").plain],
                                                  "enabled": false, "name": "Scout 2"], to: agent)
            guard sent.modelEffort == nil, BotSetWire.fallbacks(sent.fallback).count == 1, sent.enabled == false,
                  BotSetChange.has(sent, ["model_effort": NSNull(), "enabled": false, "name": " Scout 2 "]),
                  !BotSetChange.has(agent, ["enabled": false])
            else { throw SampleMismatch("applying and comparing a change") }
            return "agent, fallbacks, a change applied and compared"
        },
        DecodeCheck("botsettings.soul") {
            let soul = try KJSON.decode(BotSetSoulDTO.self, from: BotSettingsSamples.soul)
            let stale = try KJSON.decode(APIErrorBody.self, from: BotSettingsSamples.stale)
            guard soul.inSync == false, soul.fileText?.hasSuffix("sign off.") == true, soul.revision == 7,
                  stale.text.hasPrefix("The profile changed") else { throw SampleMismatch("soul fields") }
            return "hand-edited file, stale refusal"
        },
        DecodeCheck("botsettings.history") {
            let history = try KJSON.decode(BotSetHistoryDTO.self, from: BotSettingsSamples.history)
            let (rows, skipped) = BotSetWire.items(history.rows)
            let row = try KJSON.decode(BotSetHistoryRowDTO.self, from: BotSettingsSamples.historyRow)
            guard rows.count == 2, skipped == 1, rows[0].field == "soul", rows[0].before == nil,
                  rows[1].after?.string == "high", history.revision == 7, row.before?.string == "Be brief."
            else { throw SampleMismatch("history rows") }
            return "\(rows.count) rows, \(skipped) left out"
        },
        DecodeCheck("botsettings.overview") {
            let overview = try KJSON.decode(BotSetOverviewDTO.self, from: BotSettingsSamples.overview)
            let recent = BotSetWire.items(overview.recent).items
            guard overview.who?.name == "Scout", overview.does?.openCards == 2,
                  BotSetWire.items(overview.does?.routines).items.first?.name == "Morning prices",
                  BotSetWire.items(overview.wont).items.count == 2, overview.reaches?.integrations?.string == "all",
                  recent.count == 2, recent[0].ranAt?.date != nil, recent[1].ranAt?.date != nil,
                  overview.grants?.approvalMode == "auto"
            else { throw SampleMismatch("overview fields") }
            return "who, does, reaches, will not, recent"
        },
        DecodeCheck("botsettings.approval") {
            let commands = try KJSON.decode(BotSetCommandListDTO.self, from: BotSettingsSamples.commands)
            let outbound = try KJSON.decode(BotSetOutboundDTO.self, from: BotSettingsSamples.outbound)
            let (rules, skipped) = BotSetWire.items(commands.rules)
            guard rules.count == 1, skipped == 1, rules[0].command == "npm test", commands.limit == 200,
                  outbound.policy == "ask", outbound.used == 3, outbound.cap == 25, outbound.resetsAt?.date != nil
            else { throw SampleMismatch("commands or outbound") }
            return "a remembered command, one left out, the allowance"
        },
        DecodeCheck("botsettings.voice") {
            let voices = try KJSON.decode(BotSetVoiceListDTO.self, from: BotSettingsSamples.voices)
            let live = try KJSON.decode(BotSetLiveVoiceDTO.self, from: BotSettingsSamples.liveVoice)
            let follow = try KJSON.decode(BotSetFollowModelDTO.self, from: BotSettingsSamples.followModel)
            let (items, skipped) = BotSetWire.items(voices.voices)
            guard items.count == 2, skipped == 1, items[0].name == "Bella", live.idleMinutes == 5, live.readTyped == false,
                  follow.updated?.count == 2, follow.busy == ["s3"]
            else { throw SampleMismatch("voices, live voice or follow model") }
            return "voices, live voice, follow model"
        },
        DecodeCheck("botsettings.form") {
            // Filled at revision 5. The person edits only the introduction.
            var form = BotSetForm(account: "a", revision: 5, values: ["soul": "T0", "blurb": "B0"])
            var mine = ["soul": "T0", "blurb": "B1"]
            // The instructions were put back on the desktop (6): the untouched field follows, the revision moves.
            let refill = form.rebase(form: mine, desktop: ["soul": "T-1", "blurb": "B0"], revision: 6, acknowledge: false)
            mine["soul"] = "T-1"
            guard refill == ["soul"], form.revision == 6, form.edited(mine) == ["blurb"]
            else { throw SampleMismatch("an untouched field after a read") }
            // The desktop changed the introduction too (7): the person's text stays and the old revision is kept.
            _ = form.rebase(form: mine, desktop: ["soul": "T-1", "blurb": "B2"], revision: 7, acknowledge: false)
            guard form.revision == 6, form.clashed == ["blurb"], form.edited(mine) == ["blurb"]
            else { throw SampleMismatch("a clash before a refusal") }
            // After the refusal (409): only the edit is sent, with the new revision.
            _ = form.rebase(form: mine, desktop: ["soul": "T-1", "blurb": "B2"], revision: 7, acknowledge: true)
            guard form.revision == 7, form.edited(mine) == ["blurb"]
            else { throw SampleMismatch("a clash after a refusal") }
            // Saved: the desktop has the person's text.
            _ = form.rebase(form: mine, desktop: ["soul": "T-1", "blurb": "B1"], revision: 8, acknowledge: false)
            guard form.revision == 8, form.edited(mine).isEmpty, form.clashed.isEmpty
            else { throw SampleMismatch("a saved form") }
            guard BotSetForm.name("  Scout   Two ") == "Scout Two", BotSetForm.job(" Finds parts \n") == "Finds parts",
                  BotSetForm.length("e\u{301}") == 2
            else { throw SampleMismatch("tidying and counting like the desktop") }
            return "untouched, clashed, refused, saved; names, jobs and lengths as the desktop has them"
        },
    ]
}
