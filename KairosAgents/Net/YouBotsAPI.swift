import Foundation

// The desktop routes behind You > Bots pages and Channels, as the phone reads them. Read from the desktop's own code:
//
// - GET /api/agents/defaults (routes/agent_routes.py over services/bot_record.py: defaults_view, read_defaults): the
//   new-bot defaults. Only five plain values are read; the persona text, routines and notes in it are left out.
// - GET /api/bots/keys (routes/bot_connections_routes.py over services/bot_keys.py: list_slots, get_slot): only
//   whether each slot is set. `last4`, `value` and `updated_at` are never read. GET /api/bots/resource-settings
//   (bot_keys.py: resource_settings): the helper choice, tidy time, quiet minutes and room capture.
// - GET /api/bots/skills-library (routes/bot_skills_routes.py over services/bot_skill_library.py: list_all, summary,
//   _view): each row's name, summary, tags, on or off and its `storage_revision`. The text, `source` and `path` are
//   never read. PATCH /api/bots/skills-library/{name} {expected_revision, enabled: false} turns one off.
// - GET /api/bot-usage/summary (group_by bot), /budget and /housekeeping (routes/bot_usage_routes.py over
//   services/bot_usage.py and services/bot_spend.py). PUT /housekeeping replaces BOTH values (a missing one resets).
// - GET /api/bot-lifecycle/templates (routes/bot_lifecycle_routes.py): the ready-made teams, names and descriptions only.
// - GET /api/bot-workbench/computers and POST /{bot}/computer/sleep (routes/bot_workbench_routes.py over
//   services/bot_workbench.py: inventory, docker_status). Admin accounts only.
// - GET /api/bots/connections (services/bot_connections.py: inventory, _mcp_apps, _native_apps): the apps. Only an
//   account's id, alias and status are read (its label is an email address); an app's failure text is never read.
//   PUT /api/bots/connections/{app}/accounts/{account}/alias, PATCH /api/bots/mcp/{id} {enabled: false}.
// - GET /api/connectors (routes/connector_routes.py: _shown over core/connectors/store.py: public): id, name, kind,
//   label, enabled, open and the status word. `settings`, `account`, `secrets_set`, `webhook_path`, the model id and
//   the status text are never read, and `allowed_senders` is only counted. PATCH /{id} {enabled: false}, POST /{id}/test.
// - GET /api/settings/discord-bots (routes/settings_routes.py over core/discord_bots_store.py: _masked): id, name,
//   whether a token is saved, whether an allowed user and a voice channel are set, and each override's id, label and
//   mode. The allowed user, the voice channel id, the channel ids and `account` are never read. PATCH
//   /discord-bots/{bot}/channels/{entry}, DELETE the same, PUT /discord-bots/{bot}/voice. GET /api/system/status:
//   only `discord_connected_bots` (bot names).
//
// - Lists are decoded item by item: one item of an unexpected shape is left out and counted, never the list.
// - Nothing here asks for or decodes a key, password, token, two-step seed, webhook address, topic, server address,
//   MCP command, args or link, `last4`, `value`, connector `settings` or `account`, or a raw allowed sender.

/// A change stopped before anything was sent to the desktop.
nonisolated struct YouBotsNotSent: Error, Sendable {
    let plain: String
}

/// A list item that is counted and never read: the desktop's value is not decoded at all.
nonisolated struct YouBotsSkipped: Decodable, Sendable {
    init(from decoder: Decoder) throws {}
}

/// A value that is only asked "is it set": true for a non-empty string (or a number or true), false for an empty
/// string or false. What it holds is read into nothing and never kept.
nonisolated struct YouBotsIsSet: Decodable, Sendable {
    let isSet: Bool

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let text = try? single.decode(String.self) {
            isSet = !text.isEmpty
        } else if let flag = try? single.decode(Bool.self) {
            isSet = flag
        } else {
            isSet = true
        }
    }
}

nonisolated enum YouBotsWire {
    /// An id goes into the path as it is only when it is plain letters, digits, - and _.
    static func pathID(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 80, id.unicodeScalars.allSatisfy({ scalar in
            (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122) || scalar == "-" || scalar == "_"
        }) else {
            throw YouBotsNotSent(plain: "An id could not be read, so nothing was sent.")
        }
        return id
    }

    /// An alias as the desktop takes it: one to 64 characters, words joined by single spaces, no control characters.
    static func alias(_ text: String) -> String? {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")
        guard !words.isEmpty, words.count <= 64, !words.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
        return words
    }

    /// Free text from the desktop, made safe to show.
    static func safe(_ text: String) -> String {
        YouVoiceWire.safe(text)
    }

    /// The first day of this month, 00:00 in UTC, as the usage routes count months.
    static func monthStart(_ now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: parts) ?? now
    }

    /// "May 2027", for the usage page.
    static func monthName(_ text: String?) -> String? {
        guard let text, text.count == 7 else { return nil }
        let parts = text.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return "\(names[month - 1]) \(year)"
    }

    /// Characters, counted the way the desktop counts them (Python code points).
    static func length(_ text: String) -> Int { text.unicodeScalars.count }
}

// MARK: - New bot defaults

nonisolated struct YouBotsDefaultValuesDTO: Decodable, Sendable {
    var threadLimit: JSONValue?
    var dailyRunCap: JSONValue?
    var keepSignedIn: JSONValue?
    var memoryUpkeep: JSONValue?
    var place: JSONValue?
}

/// GET /api/agents/defaults: only the five plain values of `defaults`.
nonisolated struct YouBotsDefaultsDTO: Decodable, Sendable {
    var defaults: YouBotsDefaultValuesDTO?
}

// MARK: - Keys (status only)

/// One key slot. `last4`, `value` and `updated_at` are not declared, so they are never read.
nonisolated struct YouBotsKeySlotDTO: Decodable, Sendable {
    var id: String
    var group: JSONValue?
    var label: JSONValue?
    var hint: JSONValue?
    var hasValue: JSONValue?
    var managedIn: JSONValue?
}

nonisolated struct YouBotsKeysDTO: Decodable, Sendable {
    var keys: [BotKnowLossy<YouBotsKeySlotDTO>]?
}

nonisolated struct YouBotsSkillReviewDTO: Decodable, Sendable {
    var enabled: JSONValue?
    var steps: JSONValue?
}

/// GET /api/bots/resource-settings. `helper_model` is a connection id: only whether one is chosen is kept.
nonisolated struct YouBotsResourceDTO: Decodable, Sendable {
    var helperModel: JSONValue?
    var tidyTime: JSONValue?
    var captureQuietMinutes: JSONValue?
    var roomCapture: JSONValue?
    var skillReview: YouBotsSkillReviewDTO?
    var revision: JSONValue?
}

// MARK: - Skill library

/// One library skill as a listing row: no text, no `source`, no `path`.
nonisolated struct YouBotsSkillDTO: Decodable, Sendable {
    var name: String
    var description: JSONValue?
    var origin: JSONValue?
    var enabled: JSONValue?
    var effectiveEnabled: JSONValue?
    var changedAfterReview: JSONValue?
    var retired: JSONValue?
    var storageRevision: JSONValue?
    var tags: [JSONValue]?
    var warnings: [JSONValue]?
    var everyBot: JSONValue?
}

/// GET /api/bots/skills-library. The waiting shares are only counted.
nonisolated struct YouBotsLibraryDTO: Decodable, Sendable {
    var skills: [BotKnowLossy<YouBotsSkillDTO>]?
    var pendingShares: [YouBotsSkipped]?
}

// MARK: - Spend and housekeeping

/// GET /api/bot-usage/budget (services/bot_spend.py: budget).
nonisolated struct YouBotsBudgetDTO: Decodable, Sendable {
    var monthlyUsd: JSONValue?
    var warnPercent: JSONValue?
    var month: JSONValue?
    var spentUsd: JSONValue?
    var spendUnknown: JSONValue?
    var unknownCostRuns: JSONValue?
    var capped: JSONValue?
    var nearCap: JSONValue?
    var costNote: JSONValue?
}

/// GET and PUT /api/bot-usage/housekeeping.
nonisolated struct YouBotsHousekeepingDTO: Decodable, Sendable {
    var eventRetentionDays: JSONValue?
    var eventSizeCapMb: JSONValue?
}

// MARK: - Templates

nonisolated struct YouBotsTeamMemberDTO: Decodable, Sendable {
    var name: JSONValue?
}

nonisolated struct YouBotsTeamPackageDTO: Decodable, Sendable {
    var bots: [BotKnowLossy<YouBotsTeamMemberDTO>]?
}

/// One ready-made team. The members' persona text is not declared, so it is never read.
nonisolated struct YouBotsTeamDTO: Decodable, Sendable {
    var id: String
    var name: JSONValue?
    var description: JSONValue?
    var package: YouBotsTeamPackageDTO?
}

nonisolated struct YouBotsTemplatesDTO: Decodable, Sendable {
    var teams: [BotKnowLossy<YouBotsTeamDTO>]?
}

// MARK: - Bot computers

nonisolated struct YouBotsComputerDTO: Decodable, Sendable {
    var botId: String
    var name: JSONValue?
    var running: JSONValue?
    var takenOver: JSONValue?
}

nonisolated struct YouBotsComputerLimitsDTO: Decodable, Sendable {
    var maxRunning: JSONValue?
    var idleMinutes: JSONValue?
}

nonisolated struct YouBotsDockerDTO: Decodable, Sendable {
    var available: JSONValue?
    var reason: JSONValue?
    var imageReady: JSONValue?
}

/// GET /api/bot-workbench/computers (admin accounts only).
nonisolated struct YouBotsComputersDTO: Decodable, Sendable {
    var computers: [BotKnowLossy<YouBotsComputerDTO>]?
    var settings: YouBotsComputerLimitsDTO?
    var docker: YouBotsDockerDTO?
}

// MARK: - Connected apps

nonisolated struct YouBotsAppUserDTO: Decodable, Sendable {
    var name: JSONValue?
}

/// One account of an app: its id, alias and status. Its label (an email address) and its error text are not declared.
nonisolated struct YouBotsAppAccountDTO: Decodable, Sendable {
    var id: String
    var alias: JSONValue?
    var status: JSONValue?
}

nonisolated struct YouBotsAppDTO: Decodable, Sendable {
    var id: String
    /// "mcp" for a tool server, "native" for the built-in ones.
    var kind: JSONValue?
    var label: JSONValue?
    var category: JSONValue?
    var description: JSONValue?
    var state: JSONValue?
    var enabled: JSONValue?
    var usedBy: [BotKnowLossy<YouBotsAppUserDTO>]?
    var accounts: [BotKnowLossy<YouBotsAppAccountDTO>]?
}

nonisolated struct YouBotsBotNameDTO: Decodable, Sendable {
    var name: JSONValue?
}

/// GET /api/bots/connections.
nonisolated struct YouBotsConnectionsDTO: Decodable, Sendable {
    var apps: [BotKnowLossy<YouBotsAppDTO>]?
    var botsWithoutApps: [BotKnowLossy<YouBotsBotNameDTO>]?
}

// MARK: - Channels

nonisolated struct YouBotsConnectorStatusDTO: Decodable, Sendable {
    /// "listening", "connected", "starting", "error" or "off". The text beside an error is not declared.
    var state: JSONValue?
}

/// One of the account's connectors. `settings`, `account`, `secrets_set`, `webhook_path`, `model_endpoint_id` and the
/// status text are not declared; `allowed_senders` is counted and never read.
nonisolated struct YouBotsConnectorDTO: Decodable, Sendable {
    var id: String
    var kind: JSONValue?
    var name: JSONValue?
    var label: JSONValue?
    var enabled: JSONValue?
    var twoWay: JSONValue?
    var webhook: JSONValue?
    var anyoneMayMessage: JSONValue?
    var allowedSenders: [YouBotsSkipped]?
    var status: YouBotsConnectorStatusDTO?

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, label, enabled, twoWay, webhook, status, allowedSenders
        case anyoneMayMessage = "open"
    }
}

/// One channel override of a Discord bot. The Discord channel id is not declared.
nonisolated struct YouBotsOverrideDTO: Decodable, Sendable {
    var id: String
    var label: JSONValue?
    /// "normal", "open" or "silent".
    var mode: JSONValue?
}

/// One Discord bot. The token is a yes or no; the allowed user and voice channel are only counted as set.
nonisolated struct YouBotsDiscordDTO: Decodable, Sendable {
    var id: String
    var name: JSONValue?
    var hasToken: JSONValue?
    var allowedUserId: YouBotsIsSet?
    var voiceChannelId: YouBotsIsSet?
    var channels: [BotKnowLossy<YouBotsOverrideDTO>]?
}

/// GET /api/system/status: only the names of the Discord bots that are connected now.
nonisolated struct YouBotsStatusDTO: Decodable, Sendable {
    var discordConnectedBots: [JSONValue]?
}

// MARK: - Calls

extension APIClient {

    func youBotsDefaults() async throws -> YouBotsDefaultsDTO {
        try await get("/api/agents/defaults")
    }

    func youBotsKeys() async throws -> YouBotsKeysDTO {
        try await get("/api/bots/keys")
    }

    func youBotsResources() async throws -> YouBotsResourceDTO {
        try await get("/api/bots/resource-settings")
    }

    func youBotsLibrary() async throws -> YouBotsLibraryDTO {
        try await get("/api/bots/skills-library")
    }

    /// PATCH /api/bots/skills-library/{name}: switch one library skill off, against the revision the person saw (409
    /// when it changed). The answer holds the skill's text and path, so it is never read.
    func youBotsSkillOff(_ name: String, revision: String) async throws {
        try await call("PATCH", "/api/bots/skills-library/" + YouBotsWire.pathID(name),
                       json: ["expected_revision": revision, "enabled": false])
    }

    func youBotsBudget() async throws -> YouBotsBudgetDTO {
        try await get("/api/bot-usage/budget")
    }

    /// GET /api/bot-usage/summary for every bot, grouped by bot.
    func youBotsUsageByBot(from: Date, to: Date) async throws -> BotKnowUsageSummaryDTO {
        try await get("/api/bot-usage/summary", query: ["from": BotKnowWire.iso(from), "to": BotKnowWire.iso(to), "group_by": "bot"])
    }

    func youBotsHousekeeping() async throws -> YouBotsHousekeepingDTO {
        try await get("/api/bot-usage/housekeeping")
    }

    /// PUT /api/bot-usage/housekeeping with BOTH values (a missing one is reset to its default).
    func youBotsSetHousekeeping(days: Int, megabytes: Double) async throws -> YouBotsHousekeepingDTO {
        try await request("PUT", "/api/bot-usage/housekeeping", json: ["event_retention_days": days, "event_size_cap_mb": megabytes])
    }

    func youBotsTemplates() async throws -> YouBotsTemplatesDTO {
        try await get("/api/bot-lifecycle/templates")
    }

    func youBotsComputers() async throws -> YouBotsComputersDTO {
        try await get("/api/bot-workbench/computers")
    }

    /// POST /api/bot-workbench/{bot}/computer/sleep: stops one bot's computer. Admin accounts only.
    func youBotsSleep(_ botID: String) async throws {
        try await call("POST", "/api/bot-workbench/" + YouBotsWire.pathID(botID) + "/computer/sleep")
    }

    func youBotsApps() async throws -> YouBotsConnectionsDTO {
        try await get("/api/bots/connections")
    }

    /// PUT /api/bots/connections/{app}/accounts/{account}/alias.
    func youBotsSetAlias(app: String, account: String, alias: String) async throws {
        try await call("PUT", "/api/bots/connections/" + YouBotsWire.pathID(app) + "/accounts/" + YouBotsWire.pathID(account) + "/alias",
                       json: ["alias": alias])
    }

    /// PATCH /api/bots/mcp/{id} with only {enabled: false}. The answer holds the server's settings, so it is never read.
    func youBotsMcpOff(_ id: String) async throws {
        try await call("PATCH", "/api/bots/mcp/" + YouBotsWire.pathID(id), json: ["enabled": false])
    }

    func youBotsConnectors() async throws -> [BotKnowLossy<YouBotsConnectorDTO>] {
        try await get("/api/connectors")
    }

    /// PATCH /api/connectors/{id} with only {enabled: false}. The answer holds the connector's settings: never read.
    func youBotsConnectorOff(_ id: String) async throws {
        try await call("PATCH", "/api/connectors/" + YouBotsWire.pathID(id), json: ["enabled": false])
    }

    /// POST /api/connectors/{id}/test: sends one REAL message to where the channel sends notifications. There is no
    /// request id, so a caller never sends it twice after an answer was lost.
    func youBotsConnectorTest(_ id: String) async throws {
        try await call("POST", "/api/connectors/" + YouBotsWire.pathID(id) + "/test", json: [:])
    }

    func youBotsDiscordBots() async throws -> [BotKnowLossy<YouBotsDiscordDTO>] {
        try await get("/api/settings/discord-bots")
    }

    func youBotsStatus() async throws -> YouBotsStatusDTO {
        try await get("/api/system/status")
    }

    /// PATCH /api/settings/discord-bots/{bot}/channels/{entry} with only the mode ("normal" or "silent").
    func youBotsOverrideMode(bot: String, entry: String, mode: String) async throws {
        try await call("PATCH", "/api/settings/discord-bots/" + YouBotsWire.pathID(bot) + "/channels/" + YouBotsWire.pathID(entry),
                       json: ["mode": mode])
    }

    func youBotsRemoveOverride(bot: String, entry: String) async throws {
        try await call("DELETE", "/api/settings/discord-bots/" + YouBotsWire.pathID(bot) + "/channels/" + YouBotsWire.pathID(entry))
    }

    /// PUT /api/settings/discord-bots/{bot}/voice with an empty id: voice is off.
    func youBotsClearVoice(bot: String) async throws {
        try await call("PUT", "/api/settings/discord-bots/" + YouBotsWire.pathID(bot) + "/voice", json: ["voice_channel_id": ""])
    }
}

// MARK: - Samples

/// A sample answer for every route above, shaped like the desktop's own (made-up content).
nonisolated enum YouBotsSamples {

    static let defaults = #"""
    {"defaults": {"role": "Helper", "blurb": "Does small jobs.", "soul": "Be brief.", "thread_limit": 3, "daily_run_cap": 50,
                  "keep_signed_in": true, "memory_upkeep": true, "place": "auto", "routines": [{"name": "Morning"}]},
     "model_selection": {"endpoint_id": "a1b2c3d4e5f6", "model_override": null, "model_effort": null, "source": "the first Claude connection"},
     "suggested_name": "Scout"}
    """#

    static let keys = #"""
    {"groups": ["AI", "Servers", "Voice"],
     "keys": [{"id": "github", "group": "Servers", "label": "GitHub token", "hint": "Starts with ghp_.", "secret": true, "has_value": true,
               "updated_at": 1793000000, "last4": "ab12", "testable": true},
              {"id": "highlevel-location", "group": "Apps", "label": "HighLevel location id", "hint": "The sub-account id.", "secret": false,
               "has_value": true, "value": "loc-secret-1", "last4": "et-1", "testable": false},
              {"id": "elevenlabs", "group": "Voice", "label": "ElevenLabs key", "hint": "From your profile.", "secret": true, "has_value": false,
               "last4": null, "testable": true},
              {"id": "model:112233445566", "group": "AI", "label": "OpenRouter", "hint": "Model keys are set in Settings > Models.",
               "secret": true, "has_value": true, "managed_in": "models"},
              {"label": "no id"}]}
    """#

    static let resources = #"""
    {"helper_model": null, "tidy_time": "03:00", "capture_quiet_minutes": 5, "room_capture": "ask",
     "timezone": null, "skill_review": {"enabled": true, "steps": 10}, "revision": 4}
    """#

    static let library = #"""
    {"skills": [{"name": "weekly-report", "description": "Writes the Friday report.", "tags": ["writing"], "sha256": "aa",
                 "warnings": [], "source": "https://example.com/private/path?token=abc", "origin": "library", "enabled": true,
                 "reviewed_sha256": "aa", "retired": false, "storage_revision": "r1a2b3", "changed_after_review": false,
                 "effective_enabled": true, "path": "/x/SKILL.md", "every_bot": true, "assigned_bots": [], "reference_names": []},
                {"name": "receipt-filing", "description": "Files receipts by month.", "tags": [], "origin": "global", "enabled": false,
                 "storage_revision": "r9z8y7", "changed_after_review": true, "effective_enabled": false, "warnings": ["runs a command"],
                 "every_bot": false},
                {"description": "no name"}],
     "assignments": {"version": 1, "revision": 3, "every": ["weekly-report"], "bots": {}},
     "pending_shares": [{"id": "s1", "bot_id": "a1b2", "skill": "trip-budget", "status": "pending"}]}
    """#

    static let budget = #"""
    {"monthly_usd": 40.0, "warn_percent": 80, "month": "2027-01", "spent_usd": 31.6, "spend_unknown": false,
     "unknown_cost_runs": 0, "capped": false, "near_cap": false, "cost_note": "List-price equivalent, not billed"}
    """#

    static let usage = #"""
    {"totals": {"runs": 12, "duration_s": 840.5, "cost_usd": 31.6, "unknown_cost_runs": 0, "tokens": 240000, "steps": 60, "tools": 31, "errors": 1},
     "groups": [{"key": "a1b2c3d4e5", "runs": 9, "duration_s": 600.0, "cost_usd": 21.1, "unknown_cost_runs": 0, "tokens": 200000, "steps": 45, "tools": 25, "errors": 1},
                {"key": "b2c3d4e5f6", "runs": 3, "duration_s": 240.5, "cost_usd": null, "unknown_cost_runs": 3, "tokens": 40000, "steps": 15, "tools": 6, "errors": 0},
                {"key": 5}],
     "group_by": "bot", "cost_note": "List-price equivalent, not billed"}
    """#

    static let housekeeping = #"""
    {"event_retention_days": 30, "event_size_cap_mb": 50}
    """#

    static let templates = #"""
    {"teams": [{"id": "research-desk", "name": "Research desk", "description": "A lead, a reader and a writer.",
                "package": {"manifest": {"format": "kairos.package", "sha256": "ee"},
                            "bots": [{"key": "lead", "name": "Atlas", "soul": "You lead a small research team."},
                                     {"key": "reader", "name": "Sage", "soul": "You find sources."}, 7],
                            "skills": [], "connections": []}},
               {"id": "odd", "name": "No package"},
               {"name": "no id"}],
     "ready": {"version": 1, "bots": []}}
    """#

    static let computers = #"""
    {"computers": [{"bot_id": "a1b2c3d4e5", "name": "Scout", "running": true, "since": 1793000000.0, "last_action_at": 1793000100.0,
                    "taken_over": false, "profile": "own"},
                   {"bot_id": "b2c3d4e5f6", "name": "Quill", "running": false, "since": null, "last_action_at": null, "taken_over": false, "profile": "own"},
                   {"bot_id": "c3d4e5f6a7", "name": "Mason", "running": true, "taken_over": true},
                   {"name": "no id"}],
     "settings": {"max_running": 2, "idle_minutes": 10},
     "docker": {"available": true, "reason": "", "image_ready": true, "desktop_image_ready": false}}
    """#

    static let apps = #"""
    {"apps": [{"id": "google", "kind": "native", "label": "Google Workspace", "category": "Productivity", "description": "Mail and calendar.",
               "state": "connected", "reason": "", "multi_account": true,
               "accounts": [{"id": "acct_AbC123", "label": "owner@example.com", "status": "connected", "error": null, "default": true, "alias": "Shop"},
                            {"id": "acct_DeF456", "label": "second@example.com", "status": "error", "error": "token https://x.example/?k=secret", "alias": ""}],
               "used_by": [{"id": "a1b2", "name": "Kip", "scope": "write", "color": "#c8a24a"}], "limited_for": [], "tools": null},
              {"id": "m1a2b3c4d5e6", "kind": "mcp", "label": "Shop server", "category": "Tool servers", "description": "An MCP tool server.",
               "state": "failed", "reason": "Could not reach https://user:pw@shop.example:8443/mcp?key=abc", "enabled": true, "auth": "none",
               "accounts": [{"id": "server", "label": "Shop server", "status": "error", "error": "down", "default": true}], "used_by": [], "tools": 4},
              {"id": "m2a3b4c5d6e7", "kind": "mcp", "label": "Maps", "state": "off", "reason": "Switched off.", "enabled": false, "used_by": []},
              {"id": "catalog:notes", "kind": "mcp", "label": "Notes", "state": "available", "used_by": []},
              {"label": "no id"}],
     "categories": [], "counts": {"connected": 1, "total": 5}, "bots_without_apps": [{"id": "a1b2", "name": "Ledger"}, 4]}
    """#

    static let connectors = #"""
    [{"id": "0a1b2c3d4e", "kind": "telegram", "name": "Telegram", "enabled": true, "settings": {"default_chat_id": "55501234"},
      "allowed_senders": ["55501234", "55501235"], "open": false, "model_endpoint_id": "a1b2c3d4e5f6", "created_at": 1792000000.0,
      "account": "owner", "secrets_set": {"bot_token": true}, "label": "Telegram", "two_way": true, "webhook": false,
      "status": {"state": "listening", "detail": "", "since": 1793000000.0}, "webhook_path": null},
     {"id": "1b2c3d4e5f", "kind": "whatsapp", "name": "Shop WhatsApp", "enabled": true, "settings": {"phone_number_id": "100200300400500"},
      "allowed_senders": [], "open": true, "label": "WhatsApp", "two_way": true, "webhook": true,
      "status": {"state": "error", "detail": "401 for https://graph.example/v1?access_token=secret"},
      "webhook_path": "/api/connectors/1b2c3d4e5f/webhook"},
     {"id": "2c3d4e5f6a", "kind": "ntfy", "name": "Phone alerts", "enabled": false, "settings": {"topic": "shop-alerts-7f3k"},
      "allowed_senders": [], "open": false, "label": "ntfy", "two_way": false, "webhook": false, "status": {"state": "off", "detail": ""}},
     {"name": "no id"}]
    """#

    static let discordBots = #"""
    [{"id": "d1e2f3a4b5c6", "name": "Kairos", "allowed_user_id": "123456789012345678", "model_endpoint_id": "a1b2c3d4e5f6", "has_token": true,
      "account": "owner", "voice_channel_id": "222333444555666777",
      "channels": [{"id": "a1b2c3d4", "discord_channel_id": "987654321098765432", "label": "shop-orders", "mode": "open"},
                   {"id": "b2c3d4e5", "discord_channel_id": "987654321098765433", "label": "announcements", "mode": "silent"},
                   {"discord_channel_id": "1", "label": "no id"}]},
     {"id": "e2f3a4b5c6d7", "name": "Shop helper", "allowed_user_id": null, "model_endpoint_id": null, "has_token": true, "account": "owner",
      "channels": [], "voice_channel_id": null},
     {"id": "f3a4b5c6d7e8", "name": "Old bot", "allowed_user_id": "", "has_token": true, "voice_channel_id": "", "channels": []},
     {"name": "no id"}]
    """#

    static let status = #"""
    {"scheduler_running": true, "next_task": null, "enabled_task_count": 2, "discord_connected_bots": ["Kairos"],
     "model_endpoint_count": 2, "vault_ok": true}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("youbots.defaults") {
            let read = try KJSON.decode(YouBotsDefaultsDTO.self, from: YouBotsSamples.defaults)
            guard read.defaults?.threadLimit?.int == 3, read.defaults?.dailyRunCap?.int == 50, read.defaults?.keepSignedIn?.bool == true,
                  read.defaults?.memoryUpkeep?.bool == true, read.defaults?.place?.string == "auto" else { throw SampleMismatch("defaults") }
            return "five plain values, no persona text"
        },
        DecodeCheck("youbots.keys") {
            let read = try KJSON.decode(YouBotsKeysDTO.self, from: YouBotsSamples.keys)
            let rows = BotKnowWire.items(read.keys)
            let resources = try KJSON.decode(YouBotsResourceDTO.self, from: YouBotsSamples.resources)
            guard rows.items.count == 4, rows.skipped == 1, rows.items[0].hasValue?.bool == true, rows.items[2].hasValue?.bool == false,
                  rows.items[3].managedIn?.string == "models", rows.items[1].group?.string == "Apps",
                  resources.helperModel?.isNull ?? true, resources.tidyTime?.string == "03:00", resources.captureQuietMinutes?.int == 5,
                  resources.roomCapture?.string == "ask", resources.skillReview?.steps?.int == 10 else { throw SampleMismatch("keys") }
            return "4 slots, 1 left out, a yes or no only"
        },
        DecodeCheck("youbots.library") {
            let read = try KJSON.decode(YouBotsLibraryDTO.self, from: YouBotsSamples.library)
            let rows = BotKnowWire.items(read.skills)
            guard rows.items.count == 2, rows.skipped == 1, rows.items[0].storageRevision?.string == "r1a2b3",
                  rows.items[0].effectiveEnabled?.bool == true, rows.items[0].tags?.first?.string == "writing",
                  rows.items[1].enabled?.bool == false, rows.items[1].changedAfterReview?.bool == true,
                  rows.items[1].warnings?.count == 1, read.pendingShares?.count == 1 else { throw SampleMismatch("library") }
            return "2 skills, 1 left out, a revision, shares counted"
        },
        DecodeCheck("youbots.spend") {
            let budget = try KJSON.decode(YouBotsBudgetDTO.self, from: YouBotsSamples.budget)
            let usage = try KJSON.decode(BotKnowUsageSummaryDTO.self, from: YouBotsSamples.usage)
            let groups = BotKnowWire.items(usage.groups)
            let hk = try KJSON.decode(YouBotsHousekeepingDTO.self, from: YouBotsSamples.housekeeping)
            guard budget.monthlyUsd?.double == 40, budget.spentUsd?.double == 31.6, budget.warnPercent?.int == 80,
                  budget.month?.string == "2027-01", budget.capped?.bool == false, YouBotsWire.monthName("2027-01") == "January 2027",
                  groups.items.count == 2, groups.skipped == 1, groups.items[0].key == "a1b2c3d4e5", groups.items[1].costUsd == nil,
                  hk.eventRetentionDays?.int == 30, hk.eventSizeCapMb?.double == 50 else { throw SampleMismatch("spend") }
            return "budget, 2 bots, housekeeping"
        },
        DecodeCheck("youbots.templates") {
            let read = try KJSON.decode(YouBotsTemplatesDTO.self, from: YouBotsSamples.templates)
            let teams = BotKnowWire.items(read.teams)
            let members = BotKnowWire.items(teams.items[0].package?.bots)
            guard teams.items.count == 2, teams.skipped == 1, teams.items[0].name?.string == "Research desk",
                  members.items.map({ $0.name?.string ?? "" }) == ["Atlas", "Sage"], members.skipped == 1,
                  teams.items[1].package == nil else { throw SampleMismatch("templates") }
            return "2 teams, member names only"
        },
        DecodeCheck("youbots.computers") {
            let read = try KJSON.decode(YouBotsComputersDTO.self, from: YouBotsSamples.computers)
            let rows = BotKnowWire.items(read.computers)
            guard rows.items.count == 3, rows.skipped == 1, rows.items[0].running?.bool == true, rows.items[1].running?.bool == false,
                  rows.items[2].takenOver?.bool == true, read.settings?.maxRunning?.int == 2, read.settings?.idleMinutes?.int == 10,
                  read.docker?.available?.bool == true, read.docker?.imageReady?.bool == true else { throw SampleMismatch("computers") }
            return "3 computers, 1 left out, limits and docker"
        },
        DecodeCheck("youbots.apps") {
            let read = try KJSON.decode(YouBotsConnectionsDTO.self, from: YouBotsSamples.apps)
            let apps = BotKnowWire.items(read.apps)
            let google = apps.items[0]
            let accounts = BotKnowWire.items(google.accounts)
            let without = BotKnowWire.items(read.botsWithoutApps)
            guard apps.items.count == 4, apps.skipped == 1, google.id == "google", accounts.items.count == 2,
                  accounts.items[0].alias?.string == "Shop", accounts.items[1].status?.string == "error",
                  BotKnowWire.items(google.usedBy).items.first?.name?.string == "Kip", apps.items[1].enabled?.bool == true,
                  apps.items[2].enabled?.bool == false, apps.items[3].state?.string == "available",
                  without.items.count == 1, without.skipped == 1, without.items[0].name?.string == "Ledger" else { throw SampleMismatch("apps") }
            guard YouBotsWire.alias("  Work   mail ") == "Work mail", YouBotsWire.alias("") == nil,
                  YouBotsWire.alias(String(repeating: "a", count: 65)) == nil else { throw SampleMismatch("alias") }
            return "4 apps, accounts without their label, no failure text"
        },
        DecodeCheck("youbots.connectors") {
            let rows = BotKnowWire.items(try KJSON.decode([BotKnowLossy<YouBotsConnectorDTO>].self, from: YouBotsSamples.connectors))
            guard rows.items.count == 3, rows.skipped == 1, rows.items[0].id == "0a1b2c3d4e", rows.items[0].allowedSenders?.count == 2,
                  rows.items[0].anyoneMayMessage?.bool == false, rows.items[0].status?.state?.string == "listening",
                  rows.items[0].twoWay?.bool == true, rows.items[0].label?.string == "Telegram",
                  rows.items[1].anyoneMayMessage?.bool == true, rows.items[1].status?.state?.string == "error", rows.items[1].webhook?.bool == true,
                  rows.items[1].allowedSenders?.count == 0, rows.items[2].enabled?.bool == false, rows.items[2].twoWay?.bool == false
            else { throw SampleMismatch("connectors") }
            return "3 channels, senders counted, no settings"
        },
        DecodeCheck("youbots.discord") {
            let rows = BotKnowWire.items(try KJSON.decode([BotKnowLossy<YouBotsDiscordDTO>].self, from: YouBotsSamples.discordBots))
            let overrides = BotKnowWire.items(rows.items[0].channels)
            let status = try KJSON.decode(YouBotsStatusDTO.self, from: YouBotsSamples.status)
            guard rows.items.count == 3, rows.skipped == 1, rows.items[0].id == "d1e2f3a4b5c6", rows.items[0].hasToken?.bool == true,
                  rows.items[0].allowedUserId?.isSet == true, rows.items[0].voiceChannelId?.isSet == true,
                  rows.items[1].allowedUserId == nil, rows.items[1].voiceChannelId == nil,
                  rows.items[2].allowedUserId?.isSet == false, rows.items[2].voiceChannelId?.isSet == false,
                  overrides.items.count == 2, overrides.skipped == 1, overrides.items[0].mode?.string == "open", overrides.items[1].label?.string == "announcements",
                  status.discordConnectedBots?.compactMap({ $0.string }) == ["Kairos"] else { throw SampleMismatch("discord") }
            return "3 Discord bots, 2 overrides, no ids of users or channels"
        },
        DecodeCheck("youbots.guards") {
            guard (try? YouBotsWire.pathID("0a1b2c3d4e")) != nil, (try? YouBotsWire.pathID("acct_AbC-123")) != nil,
                  (try? YouBotsWire.pathID("a/b")) == nil, (try? YouBotsWire.pathID("..")) == nil, (try? YouBotsWire.pathID("")) == nil,
                  YouBotsWire.length("a\u{1F600}b") == 3 else { throw SampleMismatch("id guards") }
            return "ids that could leave a path are refused"
        },
        DecodeCheck("youbots.shaping") {
            let defaults = YouBotsLive.defaultsState(try KJSON.decode(YouBotsDefaultsDTO.self, from: YouBotsSamples.defaults))
            let keys = YouBotsLive.keyRows(try KJSON.decode(YouBotsKeysDTO.self, from: YouBotsSamples.keys))
            let resources = YouBotsLive.resourcesState(try KJSON.decode(YouBotsResourceDTO.self, from: YouBotsSamples.resources))
            let skills = YouBotsLive.skillRows(try KJSON.decode(YouBotsLibraryDTO.self, from: YouBotsSamples.library))
            let spendRead = YouBotsLive.spendState(try KJSON.decode(YouBotsBudgetDTO.self, from: YouBotsSamples.budget))
            let bots = YouBotsLive.botSpendRows(try KJSON.decode(BotKnowUsageSummaryDTO.self, from: YouBotsSamples.usage))
            let hk = YouBotsLive.housekeepingState(try KJSON.decode(YouBotsHousekeepingDTO.self, from: YouBotsSamples.housekeeping))
            let teams = YouBotsLive.teamRows(try KJSON.decode(YouBotsTemplatesDTO.self, from: YouBotsSamples.templates))
            let computersDTO = try KJSON.decode(YouBotsComputersDTO.self, from: YouBotsSamples.computers)
            let computers = YouBotsLive.computerRows(computersDTO)
            let info = YouBotsLive.computerState(computersDTO)
            let apps = YouBotsLive.appRows(try KJSON.decode(YouBotsConnectionsDTO.self, from: YouBotsSamples.apps))
            let channels = YouBotsLive.channelRows(try KJSON.decode([BotKnowLossy<YouBotsConnectorDTO>].self, from: YouBotsSamples.connectors))
            let discord = YouBotsLive.discordRows(try KJSON.decode([BotKnowLossy<YouBotsDiscordDTO>].self, from: YouBotsSamples.discordBots))
            guard defaults.threadLimit == 3, defaults.place == "auto",
                  keys.rows.count == 4, keys.rows[0].label == "GitHub token", keys.rows[0].hasValue, !keys.rows[2].hasValue, keys.rows[3].inModels,
                  resources.helper == "automatic", resources.tidyTime == "03:00", resources.roomCapture == "ask"
            else { throw SampleMismatch("defaults and keys") }
            guard skills.rows.count == 2, skills.rows[0].id == "weekly-report", skills.rows[0].effective, skills.rows[0].revision == "r1a2b3",
                  skills.rows[0].origin == "In the library", skills.rows[1].warning, !skills.rows[1].enabled, skills.rows[1].origin == "From the Tool Store"
            else { throw SampleMismatch("skills") }
            guard let spend = spendRead, spend.cap == 40, spend.ratio > 0.78, spend.ratio < 0.80, !spend.capped,
                  bots.rows.count == 2, bots.rows[0].id == "a1b2c3d4e5", bots.rows[0].runs == 9, bots.rows[1].cost == nil,
                  hk == YouBotsHousekeeping(days: 30, megabytes: 50), YouBotsLive.wholeMegabytes(0.25) == 1, YouBotsLive.wholeMegabytes(50) == 50
            else { throw SampleMismatch("spend and housekeeping") }
            guard teams.rows.count == 2, teams.rows[0].members == ["Atlas", "Sage"], teams.rows[1].members.isEmpty,
                  computers.rows.count == 3, computers.rows[0].running, !computers.rows[1].running, computers.rows[2].takenOver,
                  info.maxRunning == 2, info.idleMinutes == 10, info.dockerAvailable == true, info.imageReady == true
            else { throw SampleMismatch("teams and computers") }
            guard apps.rows.count == 3, apps.rows[0].accounts.count == 2, apps.rows[0].accounts[0].alias == "Shop", apps.rows[0].usedBy == ["Kip"],
                  apps.rows[1].isMCP, apps.rows[1].enabled, !apps.rows[2].enabled, apps.rows[1].state == "failed",
                  apps.without == ["Ledger"]
            else { throw SampleMismatch("apps") }
            guard channels.rows.count == 3, channels.rows[0].senders == 2, channels.rows[0].state == "listening", channels.rows[1].state == "error",
                  channels.rows[1].anyone, channels.rows[1].webhook, !channels.rows[2].enabled, channels.rows[2].state == "off", !channels.rows[2].twoWay
            else { throw SampleMismatch("channels") }
            guard discord.rows.count == 3, !discord.rows[2].hasAllowedUser, !discord.rows[2].hasVoice,
                  discord.rows[0].hasToken, discord.rows[0].hasAllowedUser, discord.rows[0].hasVoice,
                  discord.rows[0].overrides.map(\.mode) == ["open", "silent"], discord.rows[0].overrides.map(\.label) == ["shop-orders", "announcements"],
                  !discord.rows[1].hasAllowedUser, !discord.rows[1].hasVoice, discord.rows[1].overrides.isEmpty
            else { throw SampleMismatch("discord") }
            return "every list shaped, nothing private kept"
        },
    ]
}
