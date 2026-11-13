import Foundation
import CryptoKit

// The desktop's routes behind a bot's knowledge and reach settings, as the Bots area reads them: memory,
// About you, usage and plan, conversations and folders (read and write), and skills, the skill library,
// access, reach, connections, browser and saved logins (read only).
//
// Shapes were read from: routes/bot_memory_routes.py with services/bot_memory.py (overview, read_file,
// notes_of, set_settings, apply_entry, revert) and services/bot_memory_entries.py (actions) and
// services/bot_memory_store.py (clip_index); routes/bot_recall_routes.py with services/bot_profile.py
// (get_about, put_about, learned, remove_learned); routes/bot_usage_routes.py with services/bot_usage.py
// (summary, runs, totals) and core/quota_usage.py (get_bot_plan, get_usage_overlay, _provider, _window);
// routes/agent_routes.py (threads, folders, _summary) with services/bot_threads.py; routes/bot_skills_routes.py
// with services/bot_skills.py (view), services/bot_skill_library.py (_view, summary, list_all, assigned),
// services/bot_skill_review.py (settings) and services/bot_skill_sharing.py (mode); routes/bot_access_routes.py
// with services/bot_grants.py (effective, _scope_level); routes/bot_peer_routes.py with services/bot_peers.py
// (view); routes/bot_connections_routes.py with services/bot_connections.py (inventory, _users),
// services/bot_logins.py (masked) and services/bot_onepassword.py (status); routes/bot_workbench_routes.py with
// services/bot_browser_profiles.py (list_profiles, used_by).
//
// - Lists are decoded item by item: one item of an unexpected shape is left out and counted, never the list.
// - Nothing here asks for or decodes a key, password, token or webhook address. A connected app's `accounts`
//   and `auth`, an access app's `accounts`, a skill's `source` and `path`, and 1Password's vaults are not read.
// - Every refusal is `{"detail": text}`, which `APIError` already reads.

// MARK: - Item by item

/// One list item that decodes, or nil when it does not. The list around it still decodes.
nonisolated struct BotKnowLossy<T: Decodable & Sendable>: Decodable, Sendable {
    var value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

nonisolated enum BotKnowWire {
    /// The decoded items of a lossy list, and how many were left out.
    static func items<T: Decodable & Sendable>(_ list: [BotKnowLossy<T>]?) -> (items: [T], skipped: Int) {
        let all = list ?? []
        let items = all.compactMap(\.value)
        return (items, all.count - items.count)
    }

    /// A time as the usage routes take it: ISO 8601 in UTC, with no plus sign.
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// The SHA-256 the desktop keeps for About you (bot_profile.py: _hash), as lower-case hex.
    static func aboutHash(_ text: String) -> String {
        BotKnowSHA.hex(Data(text.utf8))
    }
}

// MARK: - Memory

/// One note of the notebook's main page (bot_memory.py: notes_of). `learned` is a date "YYYY-MM-DD".
nonisolated struct BotKnowNoteDTO: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var section: String?
    var text: String?
    var source: String?
    var learned: String?
    var until: String?
    var superseded: String?
    var protected: Bool?
    var legacy: Bool?
}

/// The main page as the overview carries it: its hash (the `expected_hash` of every change), how much of it
/// a turn reads (store.clip_index), and its notes.
nonisolated struct BotKnowIndexDTO: Decodable, Sendable {
    var path: String?
    var hash: String?
    var exists: Bool?
    var loadedLines: Int?
    var storedLines: Int?
    var lineLimit: Int?
    var loadedBytes: Int?
    var storedBytes: Int?
    var byteLimit: Int?
    var clipped: Bool?
    var notes: [BotKnowLossy<BotKnowNoteDTO>]?
}

/// PATCH /api/bots/{id}/memory/settings answers this, and the overview carries it as `settings`.
nonisolated struct BotKnowMemorySettingsDTO: Decodable, Sendable, Equatable {
    var enabled: Bool?
    var upkeep: Bool?
    var roomCapture: Bool?
}

/// One notebook file in the overview (bot_memory.py: _file_info). Topics carry a name, title and description.
nonisolated struct BotKnowMemoryFileDTO: Decodable, Sendable {
    var path: String
    /// "index", "topic", "archive" or "log".
    var kind: String?
    var name: String?
    var title: String?
    var description: String?
    var bytes: Int?
}

nonisolated struct BotKnowTidyRowDTO: Decodable, Sendable {
    var id: String?
    var time: FlexibleDate?
    var actor: String?
    var summary: String?
}

nonisolated struct BotKnowMaintenanceDTO: Decodable, Sendable {
    var upkeep: Bool?
    var changes: Int?
    var last: BotKnowTidyRowDTO?
}

/// GET /api/bots/{id}/memory (bot_memory.py: overview).
nonisolated struct BotKnowMemoryDTO: Decodable, Sendable {
    var botId: String?
    var settings: BotKnowMemorySettingsDTO?
    var enabled: Bool?
    var index: BotKnowIndexDTO?
    var files: [BotKnowLossy<BotKnowMemoryFileDTO>]?
    var maintenance: BotKnowMaintenanceDTO?
}

/// The page after a change (bot_memory.py: read_file): its new hash and notes.
nonisolated struct BotKnowMemoryPageDTO: Decodable, Sendable {
    var path: String?
    var hash: String?
    var notes: [BotKnowLossy<BotKnowNoteDTO>]?
}

/// POST /api/bots/{id}/memory/entries: the page as it is now, and the journal row to undo it with.
nonisolated struct BotKnowEntryAnswerDTO: Decodable, Sendable {
    var file: BotKnowMemoryPageDTO?
    var changed: Bool?
    var displaced: Int?
    var changeId: String?
}

/// POST /api/bots/{id}/memory/journal/{change}/revert
nonisolated struct BotKnowRevertDTO: Decodable, Sendable {
    var reverted: String?
    var changeId: String?
}

/// POST /api/bots/{id}/memory/tidy: `passes` are the journal rows of each tidied page.
nonisolated struct BotKnowTidyDTO: Decodable, Sendable {
    var queued: Bool?
    var passes: [String]?
}

// MARK: - About you

/// One fact a bot learned about the person (bot_profile.py: learned). `at` is epoch seconds.
nonisolated struct BotKnowLearnedDTO: Decodable, Sendable, Equatable, Identifiable {
    var id: String
    var text: String?
    var learnedBy: String?
    var at: FlexibleDate?
}

/// GET /api/bots/profile (with `learned`) and PUT /api/bots/profile (without it).
nonisolated struct BotKnowAboutDTO: Decodable, Sendable {
    var text: String?
    var hash: String?
    var limit: Int?
    var chars: Int?
    var learned: [BotKnowLossy<BotKnowLearnedDTO>]?
}

// MARK: - Usage and plan

/// The totals of usage rows (bot_usage.py: totals); a group adds its `key`. `cost_usd` is null when no run in it
/// had a known price.
nonisolated struct BotKnowUsageTotalsDTO: Decodable, Sendable {
    var key: String?
    var runs: Int?
    var durationS: Double?
    var costUsd: Double?
    var unknownCostRuns: Int?
    var tokens: Int?
    var steps: Int?
    var tools: Int?
    var errors: Int?
}

/// GET /api/bot-usage/summary (bot_usage.py: summary).
nonisolated struct BotKnowUsageSummaryDTO: Decodable, Sendable {
    var totals: BotKnowUsageTotalsDTO?
    var groups: [BotKnowLossy<BotKnowUsageTotalsDTO>]?
    var groupBy: String?
    var costNote: String?
}

/// One run in the usage ledger (bot_usage.py: _observe). No message content.
nonisolated struct BotKnowUsageRunDTO: Decodable, Sendable {
    var runId: String
    var at: Double?
    var botId: String?
    var model: String?
    /// "person", "routine", "helper", or a trigger's own word.
    var trigger: String?
    var durationS: Double?
    var costUsd: Double?
    var outcome: String?
}

/// GET /api/bot-usage/runs
nonisolated struct BotKnowUsageRunsDTO: Decodable, Sendable {
    var rows: [BotKnowLossy<BotKnowUsageRunDTO>]?
    var total: Int?
}

nonisolated struct BotKnowPlanWindowDTO: Decodable, Sendable {
    var name: String?
    var usedPercent: Double?
    var resetsAt: FlexibleDate?
}

/// One subscription's reading (quota_usage.py: _provider). `status` is ok, stale, needs_sign_in, rate_limited,
/// unavailable or no_quota; `note` says why when it is not ok.
nonisolated struct BotKnowPlanProviderDTO: Decodable, Sendable {
    var provider: String?
    var status: String?
    var note: String?
    var stale: Bool?
    var windows: [BotKnowLossy<BotKnowPlanWindowDTO>]?
}

/// GET /api/bot-usage/plan (quota_usage.py: get_bot_plan). Only the providers are read.
nonisolated struct BotKnowPlanDTO: Decodable, Sendable {
    var providers: [BotKnowLossy<BotKnowPlanProviderDTO>]?
}

// MARK: - The bot record

/// The parts of the bot record these pages read (agent_routes.py: _summary over the stored record).
nonisolated struct BotKnowAgentFieldsDTO: Decodable, Sendable {
    var id: String
    var name: String?
    var revision: Int?
    var enabled: Bool?
    var dailyRunCap: Int?
    var runsToday: Int?
    /// "auto", "computer", "browser" or "off".
    var place: String?
    var keepSignedIn: Bool?
    var browserEnabled: Bool?
    /// "own", "guest" or "shared:<id>".
    var browserProfile: String?
    var folders: [BotKnowLossy<AgentFolderDTO>]?
}

/// GET /api/agents/{id}: only `agent` is read here.
nonisolated struct BotKnowAgentDTO: Decodable, Sendable {
    var agent: BotKnowAgentFieldsDTO?
}

// MARK: - Conversations and folders

/// GET /api/agents/{id}/threads, read row by row.
nonisolated struct BotKnowThreadListDTO: Decodable, Sendable {
    var mainId: String?
    var threads: [BotKnowLossy<BotThreadDTO>]?
}

/// POST /api/agents/{id}/threads/delete (bot_threads.py: delete_threads). Busy ones stay; one is always kept.
nonisolated struct BotKnowDeleteDTO: Decodable, Sendable {
    var deleted: [String]?
    var busy: [String]?
    var missing: [String]?
    var kept: [String]?
}

/// PUT /api/agents/{id}/folders/order
nonisolated struct BotKnowFolderOrderDTO: Decodable, Sendable {
    var folders: [BotKnowLossy<AgentFolderDTO>]?
}

/// DELETE /api/agents/{id}/folders/{folder}: its conversations go back to the main list.
nonisolated struct BotKnowFolderDeletedDTO: Decodable, Sendable {
    var ok: Bool?
    var cleared: Int?
}

// MARK: - Skills (read only)

/// A private or library skill as a listing row (bot_skills.py: view, bot_skill_library.py: _view and summary),
/// without its text, source or path.
nonisolated struct BotKnowSkillDTO: Decodable, Sendable {
    var name: String
    var description: String?
    /// "private", "library", or how a library skill got there.
    var origin: String?
    var enabled: Bool?
    var effectiveEnabled: Bool?
    var changedAfterReview: Bool?
    var reviewedSha256: String?
    var sha256: String?
    var retired: Bool?
    var tags: [String]?
    var everyBot: Bool?
    var assignedBots: [String]?
    /// "every" or "bot", on a library skill this bot can use.
    var assignedVia: String?

    /// Never reviewed, or its text changed since: it needs a full read before it can be on.
    var needsReview: Bool { changedAfterReview == true || reviewedSha256 == nil || (sha256 != nil && reviewedSha256 != sha256) }
}

nonisolated struct BotKnowSkillSettingsDTO: Decodable, Sendable {
    /// Background review of finished work for skills (bot_skill_review.py: settings).
    var enabled: Bool?
    var steps: Int?
    /// "off", "ask" or "auto" (bot_skill_sharing.py: mode).
    var sharing: String?
}

/// GET /api/bots/{id}/skills. `requests` are learned-skill cards; only how many are counted.
nonisolated struct BotKnowSkillsDTO: Decodable, Sendable {
    var skills: [BotKnowLossy<BotKnowSkillDTO>]?
    var library: [BotKnowLossy<BotKnowSkillDTO>]?
    var requests: [JSONValue]?
    var settings: BotKnowSkillSettingsDTO?
}

/// GET /api/bots/skills-library. Assignments are read from each row's `every_bot` and `assigned_bots`.
nonisolated struct BotKnowLibraryDTO: Decodable, Sendable {
    var skills: [BotKnowLossy<BotKnowSkillDTO>]?
}

// MARK: - Access and reach (read only)

nonisolated struct BotKnowToolStateDTO: Decodable, Sendable {
    var name: String?
    /// "on" or "off".
    var state: String?
}

/// One app in the Access view (bot_grants.py: effective). `scope` is "off", "read", "write" or null (no limit
/// set). Its `accounts` are not read.
nonisolated struct BotKnowAccessAppDTO: Decodable, Sendable {
    var id: String
    var name: String?
    var kind: String?
    var available: Bool?
    var scope: String?
    var tools: [BotKnowLossy<BotKnowToolStateDTO>]?
}

nonisolated struct BotKnowGrantsDTO: Decodable, Sendable {
    /// null: every connected tool server; a list: only those.
    var integrationIds: [String]?
}

/// GET /api/bots/{id}/access. `mode` is "legacy" (every app allowed unless limited) or "explicit".
nonisolated struct BotKnowAccessDTO: Decodable, Sendable {
    var botId: String?
    var revision: Int?
    var mode: String?
    var grants: BotKnowGrantsDTO?
    var apps: [BotKnowLossy<BotKnowAccessAppDTO>]?
    var explanation: [String]?
}

/// GET /api/bot-peers/{id}/reach (bot_peers.py: view). `mode` is "all", "listed" or "none".
nonisolated struct BotKnowReachDTO: Decodable, Sendable {
    var botId: String?
    var mode: String?
    var peers: [String]?
    var revision: Int?
    var approvePeerComms: Bool?
}

// MARK: - Connections, browser and logins (read only)

nonisolated struct BotKnowAppUserDTO: Decodable, Sendable {
    var id: String?
    var name: String?
    var scope: String?
}

/// One app a bot could use (bot_connections.py: _mcp_apps, _native_apps, _available_catalog). `state` is
/// connected, expired, failed, pending, off, added, available or unavailable.
nonisolated struct BotKnowAppDTO: Decodable, Sendable {
    var id: String
    /// "mcp" for a tool server.
    var kind: String?
    var label: String?
    var category: String?
    var description: String?
    var state: String?
    var reason: String?
    var enabled: Bool?
    var usedBy: [BotKnowLossy<BotKnowAppUserDTO>]?
}

nonisolated struct BotKnowAppCountsDTO: Decodable, Sendable {
    var connected: Int?
    var total: Int?
}

/// GET /api/bots/connections (bot_connections.py: inventory).
nonisolated struct BotKnowConnectionsDTO: Decodable, Sendable {
    var apps: [BotKnowLossy<BotKnowAppDTO>]?
    var counts: BotKnowAppCountsDTO?
}

nonisolated struct BotKnowProfileUserDTO: Decodable, Sendable {
    var id: String?
    var name: String?
    var running: Bool?
}

/// One shared browser profile (bot_browser_profiles.py: list_profiles). GET /api/bot-workbench/profiles is
/// admin only and answers a plain list.
nonisolated struct BotKnowProfileDTO: Decodable, Sendable {
    var id: String
    var name: String?
    var usedBy: [BotKnowLossy<BotKnowProfileUserDTO>]?
}

/// One saved login without its password (bot_logins.py: masked). `bots` is "all" or a list of bot ids.
nonisolated struct BotKnowLoginDTO: Decodable, Sendable {
    var id: String
    var site: String?
    var username: String?
    var hasTotp: Bool?
    var bots: JSONValue?
    var lastUsed: FlexibleDate?

    var allBots: Bool { bots?.string == "all" }

    func usable(by botID: String) -> Bool {
        allBots || (bots?.array ?? []).contains { $0.string == botID }
    }
}

nonisolated struct BotKnowOnePasswordDTO: Decodable, Sendable {
    var available: Bool?
    var connected: Bool?
}

/// GET /api/bots/logins
nonisolated struct BotKnowLoginsDTO: Decodable, Sendable {
    var logins: [BotKnowLossy<BotKnowLoginDTO>]?
    var onepassword: BotKnowOnePasswordDTO?
}

// MARK: - Calls

extension APIClient {

    // Memory

    /// GET /api/bots/{id}/memory
    func botKnowledgeMemory(_ botID: String) async throws -> BotKnowMemoryDTO {
        try await get("/api/bots/\(botID)/memory")
    }

    /// PATCH /api/bots/{id}/memory/settings: `enabled`, `upkeep`, `room_capture`, only what changed.
    func botKnowledgeMemorySettings(_ botID: String, _ fields: [String: Any]) async throws -> BotKnowMemorySettingsDTO {
        try await request("PATCH", "/api/bots/\(botID)/memory/settings", json: fields)
    }

    /// POST /api/bots/{id}/memory/entries on the main page: `append` with a section and text, or `remove` with the
    /// note's id. Always with the page hash read (409 when it changed since).
    func botKnowledgeMemoryEntry(_ botID: String, action: String, expectedHash: String, section: String? = nil,
                                 text: String? = nil, target: String? = nil) async throws -> BotKnowEntryAnswerDTO {
        var body: [String: Any] = ["action": action, "path": "MEMORY.md", "expected_hash": expectedHash]
        if let section { body["section"] = section }
        if let text { body["text"] = text }
        if let target { body["target"] = target }
        return try await post("/api/bots/\(botID)/memory/entries", json: body)
    }

    /// POST /api/bots/{id}/memory/journal/{change}/revert: Undo one change, only while the page is as it left it.
    func botKnowledgeMemoryRevert(_ botID: String, change: String) async throws -> BotKnowRevertDTO {
        try await post("/api/bots/\(botID)/memory/journal/\(change)/revert")
    }

    /// POST /api/bots/{id}/memory/tidy: 409 unless keeping its notes tidy is on.
    func botKnowledgeMemoryTidy(_ botID: String) async throws -> BotKnowTidyDTO {
        try await post("/api/bots/\(botID)/memory/tidy")
    }

    // About you

    /// GET /api/bots/profile: the signed-in account's own text and learned facts.
    func botKnowledgeAbout() async throws -> BotKnowAboutDTO {
        try await get("/api/bots/profile")
    }

    /// PUT /api/bots/profile with the hash of the text read (409 when it changed since).
    func botKnowledgeAboutSave(text: String, expectedHash: String) async throws -> BotKnowAboutDTO {
        try await request("PUT", "/api/bots/profile", json: ["text": text, "expected_hash": expectedHash])
    }

    /// POST /api/bots/profile/learned/{id}/remove: bots will not learn it again.
    func botKnowledgeLearnedRemove(_ factID: String) async throws {
        try await call("POST", "/api/bots/profile/learned/\(factID)/remove")
    }

    // Usage

    /// GET /api/bot-usage/summary for one bot, grouped by model.
    func botKnowledgeUsageSummary(_ botID: String, from: Date, to: Date) async throws -> BotKnowUsageSummaryDTO {
        try await get("/api/bot-usage/summary", query: ["bot_id": botID, "from": BotKnowWire.iso(from),
                                                        "to": BotKnowWire.iso(to), "group_by": "model"])
    }

    /// GET /api/bot-usage/runs for one bot, newest first.
    func botKnowledgeUsageRuns(_ botID: String, from: Date, to: Date, limit: Int = 20) async throws -> BotKnowUsageRunsDTO {
        try await get("/api/bot-usage/runs", query: ["bot_id": botID, "from": BotKnowWire.iso(from),
                                                     "to": BotKnowWire.iso(to), "limit": String(limit)])
    }

    /// GET /api/bot-usage/plan. With `refresh` the desktop reads the subscriptions again (it keeps 45 seconds).
    func botKnowledgePlan(refresh: Bool) async throws -> BotKnowPlanDTO {
        try await get("/api/bot-usage/plan", query: ["refresh": refresh ? "true" : nil])
    }

    // The bot record

    /// GET /api/agents/{id}: the record's place, browser, folders and run counts.
    func botKnowledgeAgent(_ botID: String) async throws -> BotKnowAgentDTO {
        try await get("/api/agents/\(botID)")
    }

    // Conversations

    /// GET /api/agents/{id}/threads with the archived ones too.
    func botKnowledgeThreads(_ botID: String) async throws -> BotKnowThreadListDTO {
        try await get("/api/agents/\(botID)/threads", query: ["include_archived": "1"])
    }

    /// POST /api/agents/{id}/threads/delete
    func botKnowledgeDeleteThreads(_ botID: String, ids: [String]) async throws -> BotKnowDeleteDTO {
        try await post("/api/agents/\(botID)/threads/delete", json: ["thread_ids": ids])
    }

    /// POST /api/agents/{id}/folders
    func botKnowledgeAddFolder(_ botID: String, name: String) async throws -> AgentFolderDTO {
        try await post("/api/agents/\(botID)/folders", json: ["name": name])
    }

    /// PATCH /api/agents/{id}/folders/{folder} with a new name.
    func botKnowledgeRenameFolder(_ botID: String, folderID: String, name: String) async throws -> AgentFolderDTO {
        try await request("PATCH", "/api/agents/\(botID)/folders/\(folderID)", json: ["name": name])
    }

    /// PUT /api/agents/{id}/folders/order: every folder id, in the new order.
    func botKnowledgeOrderFolders(_ botID: String, ids: [String]) async throws -> BotKnowFolderOrderDTO {
        try await request("PUT", "/api/agents/\(botID)/folders/order", json: ["ids": ids])
    }

    /// DELETE /api/agents/{id}/folders/{folder}
    func botKnowledgeDeleteFolder(_ botID: String, folderID: String) async throws -> BotKnowFolderDeletedDTO {
        try await request("DELETE", "/api/agents/\(botID)/folders/\(folderID)")
    }

    // Read only

    /// GET /api/bots/{id}/skills
    func botKnowledgeSkills(_ botID: String) async throws -> BotKnowSkillsDTO {
        try await get("/api/bots/\(botID)/skills")
    }

    /// GET /api/bots/skills-library
    func botKnowledgeLibrary() async throws -> BotKnowLibraryDTO {
        try await get("/api/bots/skills-library")
    }

    /// GET /api/bots/{id}/access
    func botKnowledgeAccess(_ botID: String) async throws -> BotKnowAccessDTO {
        try await get("/api/bots/\(botID)/access")
    }

    /// GET /api/bot-peers/{id}/reach
    func botKnowledgeReach(_ botID: String) async throws -> BotKnowReachDTO {
        try await get("/api/bot-peers/\(botID)/reach")
    }

    /// GET /api/bots/connections
    func botKnowledgeConnections() async throws -> BotKnowConnectionsDTO {
        try await get("/api/bots/connections")
    }

    /// GET /api/bot-workbench/profiles: admin accounts only.
    func botKnowledgeProfiles() async throws -> [BotKnowLossy<BotKnowProfileDTO>] {
        try await get("/api/bot-workbench/profiles")
    }

    /// GET /api/bots/logins: sites and usernames, never a password.
    func botKnowledgeLogins() async throws -> BotKnowLoginsDTO {
        try await get("/api/bots/logins")
    }
}

// MARK: - SHA-256

nonisolated enum BotKnowSHA {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Samples

/// A sample answer for every route above, shaped like the desktop's own (made-up content).
nonisolated enum BotKnowledgeSamples {

    static let memory = #"""
    {"bot_id": "a1b2c3d4e5", "bot_name": "Scout",
     "settings": {"enabled": true, "upkeep": true, "room_capture": false}, "enabled": true,
     "index": {"path": "MEMORY.md", "text": "## Preferences\n- 2027-01-04 · from owner · Replies stay short.\n",
               "hash": "9f2c4e1a0b7d6c5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e", "exists": true,
               "loaded_lines": 12, "stored_lines": 12, "loaded_bytes": 640, "stored_bytes": 640,
               "line_limit": 200, "byte_limit": 24576, "clipped": false,
               "notes": [
                 {"id": "0a1b2c3d4e", "section": "Preferences", "text": "Replies stay short.", "source": "owner",
                  "learned": "2027-01-04", "until": null, "superseded": null, "protected": false, "legacy": false},
                 {"id": "1b2c3d4e5f", "section": "Notes", "text": "The weekly report goes out on Fridays.",
                  "source": "agent", "learned": "2027-01-02", "until": "2027-03-01", "superseded": null,
                  "protected": false, "legacy": false},
                 {"id": "2c3d4e5f6a", "section": "Notes", "text": "Old opening hours.", "source": "agent",
                  "learned": "2026-12-01", "until": null, "superseded": "2027-01-03", "protected": false, "legacy": false},
                 {"id": 7}
               ]},
     "files": [
       {"path": "MEMORY.md", "kind": "index", "bytes": 640, "hash": "9f2c", "lines": 12, "read_only": false,
        "limit": 24576, "modified": 1793000000.0},
       {"path": "memory/suppliers.md", "kind": "topic", "bytes": 300, "hash": "aa11", "lines": 6, "read_only": false,
        "limit": 65536, "name": "suppliers", "title": "Suppliers", "description": "Who sends parts and when.",
        "aliases": [], "modified": 1793000100.0},
       {"path": "memory/log/2027-01-04.md", "kind": "log", "bytes": 80, "read_only": true}
     ],
     "maintenance": {"upkeep": true, "changes": 4,
                     "last": {"id": "c0ffee12", "time": 1793001000.0, "actor": "upkeep", "summary": "Tidied MEMORY.md"}}}
    """#

    static let entry = #"""
    {"file": {"path": "MEMORY.md", "kind": "index", "bytes": 600, "hash": "1e2d3c4b5a6f7e8d9c0b1a2f3e4d5c6b7a8f9e0d1c2b3a4f5e6d7c8b9a0f1e2d",
              "lines": 10, "read_only": false, "limit": 24576, "text": "", "exists": true,
              "notes": [{"id": "1b2c3d4e5f", "section": "Notes", "text": "The weekly report goes out on Fridays.",
                         "source": "agent", "learned": "2027-01-02", "until": "2027-03-01", "superseded": null,
                         "protected": false, "legacy": false}]},
     "changed": true, "displaced": 0, "change_id": "d1e2f3a4"}
    """#

    static let memorySettings = #"""
    {"enabled": true, "upkeep": false, "room_capture": true}
    """#

    static let stale = #"""
    {"detail": "this note changed since you opened it; reload it first"}
    """#

    static let about = #"""
    {"text": "I run a small bike shop. Keep replies short.", "hash": "4d6a0c2b9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b",
     "limit": 24000, "chars": 44,
     "learned": [{"id": "f1a2b3c4d5e6", "text": "Prefers mornings for calls.", "learned_by": "Scout", "at": 1793000000.0},
                 {"id": "a9b8c7d6e5f4", "text": "Ships on Tuesdays.", "learned_by": "a bot", "at": null},
                 {"text": "no id"}],
     "limits": {"learned": 200}}
    """#

    static let usage = #"""
    {"totals": {"runs": 12, "duration_s": 840.5, "cost_usd": 1.25, "unknown_cost_runs": 2, "tokens": 240000,
                "steps": 60, "tools": 31, "errors": 1},
     "groups": [{"key": "claude-sonnet", "runs": 9, "duration_s": 600.0, "cost_usd": 1.0, "unknown_cost_runs": 0,
                 "tokens": 200000, "steps": 45, "tools": 25, "errors": 1},
                {"key": "Unknown", "runs": 3, "duration_s": 240.5, "cost_usd": null, "unknown_cost_runs": 2,
                 "tokens": 40000, "steps": 15, "tools": 6, "errors": 0},
                {"key": 5}],
     "group_by": "model", "cost_note": "List-price equivalent, not billed"}
    """#

    static let runs = #"""
    {"rows": [{"at": 1793000000.0, "run_id": "run_a1", "bot_id": "a1b2c3d4e5", "thread_id": "s1", "endpoint_id": "ep1",
               "model_kind": "claude_cli", "model": "claude-sonnet", "tokens": {"input": 1000, "output": 200},
               "cost_usd": 0.12, "cost_source": "list", "trigger": "routine", "routine_id": "t1", "duration_s": 42.0,
               "outcome": "succeeded", "tools": 3, "steps": 4, "tool_errors": 0, "parent_id": null},
              {"at": 1792990000.0, "run_id": "run_a2", "bot_id": "a1b2c3d4e5", "model": null, "trigger": "person",
               "duration_s": 5.5, "cost_usd": null, "outcome": "failed"},
              {"at": 1}],
     "total": 3, "offset": 0, "limit": 20}
    """#

    static let plan = #"""
    {"providers": [{"provider": "claude", "status": "ok", "note": "", "updated_at": 1793000000.0, "stale": false,
                    "windows": [{"name": "5-hour", "used_percent": 42.5, "resets_at": 1793010000.0},
                                {"name": "Weekly", "used_percent": 91.0, "resets_at": null}]},
                   {"provider": "codex", "windows": [], "stale": true, "status": "needs_sign_in",
                    "note": "Sign-in has expired or is missing. Open the CLI once to renew it."}],
     "models": [{"id": "ep1", "name": "Claude", "kind": "claude_cli"}]}
    """#

    static let agent = #"""
    {"agent": {"id": "a1b2c3d4e5", "name": "Scout", "revision": 7, "enabled": true, "daily_run_cap": 50, "runs_today": 3,
               "place": "auto", "keep_signed_in": true, "browser_enabled": true, "browser_profile": "shared:0a1b2c3d4e5f",
               "folders": [{"id": "f0a1b2c3d4", "name": "Clients", "emoji": "", "order": 0},
                           {"id": "f1b2c3d4e5", "name": "Old", "emoji": "", "order": 1}, {"name": "no id"}],
               "status": "idle", "needs_you": 0},
     "soul_file": null, "goals": [], "cards": []}
    """#

    static let threads = #"""
    {"main_id": "s1",
     "threads": [
       {"id": "s1", "title": "Main", "created_at": 1792000000.0, "updated_at": 1793000000.0, "message_count": 12,
        "model_endpoint_id": "ep1", "model_override": null, "model_effort": null, "follows_bot_model": true,
        "thread": {"main": true, "folder_id": null, "pinned": true, "archived_at": null, "snoozed_until": null,
                   "approval_mode": null, "place": null, "unread": false, "opened_by": "person", "link": null},
        "status": "idle", "preview": "The report is ready."},
       {"id": "s2", "title": "Spring order", "updated_at": 1792900000.0,
        "thread": {"main": false, "folder_id": "f0a1b2c3d4", "pinned": false, "archived_at": 1792950000.0,
                   "snoozed_until": 0, "unread": true},
        "status": "working", "preview": ""},
       {"title": "no id"}
     ]}
    """#

    static let deleted = #"""
    {"deleted": ["s3"], "busy": ["s2"], "missing": [], "kept": []}
    """#

    static let skills = #"""
    {"skills": [{"name": "weekly-report", "description": "Writes the Friday report.", "tags": [], "sha256": "aa",
                 "skill_sha256": "bb", "warnings": [], "source": "written:bot settings", "origin": "private",
                 "enabled": true, "reviewed_sha256": "aa", "retired": false, "imported_at": 1792000000.0,
                 "storage_revision": "r1", "skipped_files": [], "applied_stage_id": null, "changed_after_review": false,
                 "effective_enabled": true, "path": "/x/SKILL.md", "reference_names": []},
                {"name": "price-check", "description": "Checks supplier prices.", "sha256": "cc", "origin": "private",
                 "enabled": false, "reviewed_sha256": null, "retired": false, "changed_after_review": false,
                 "effective_enabled": false, "reference_names": []},
                {"description": "no name"}],
     "library": [{"name": "summarise", "description": "Short summaries.", "origin": "library", "enabled": true,
                  "sha256": "dd", "reviewed_sha256": "dd", "every_bot": true, "assigned_bots": [],
                  "effective_enabled": true, "changed_after_review": false, "assigned_via": "every"}],
     "requests": [{"id": "q1", "status": "proposed"}],
     "notes": [],
     "settings": {"enabled": true, "steps": 10, "sharing": "ask"}}
    """#

    static let library = #"""
    {"skills": [{"name": "summarise", "description": "Short summaries.", "origin": "library", "enabled": true,
                 "sha256": "dd", "reviewed_sha256": "dd", "every_bot": true, "assigned_bots": [],
                 "effective_enabled": true, "changed_after_review": false, "tags": ["writing"]},
                {"name": "invoice", "description": "Drafts invoices.", "origin": "shared", "enabled": false,
                 "sha256": "ee", "reviewed_sha256": null, "every_bot": false, "assigned_bots": ["a1b2c3d4e5"],
                 "effective_enabled": false, "changed_after_review": true}],
     "assignments": {"version": 1, "revision": 3, "every": ["summarise"], "bots": {"a1b2c3d4e5": ["invoice"]}},
     "pending_shares": []}
    """#

    static let access = #"""
    {"bot_id": "a1b2c3d4e5", "revision": 4, "mode": "explicit", "catalogue_revision": "c9",
     "grants": {"tool_scope": {"allow": [], "deny": []}, "connector_scopes": {"google": "read"},
                "integration_ids": ["m1"], "connector_tools": {}, "grants_version": 2},
     "native": [{"name": "files", "description": "Read files.", "effect": "read", "app": null, "available": true,
                 "unavailable": "", "state": "on", "reason": "", "code": ""}],
     "apps": [{"id": "google", "name": "Google", "kind": "native", "available": true, "unavailable": "", "scope": "read",
               "grant": null, "accounts": [{"id": "acc1", "label": "Work"}],
               "tools": [{"name": "calendar_list", "state": "on", "reason": "", "code": ""},
                         {"name": "calendar_create", "state": "off", "reason": "read only", "code": "scope"}]},
              {"id": "m1", "name": "Shop server", "kind": "mcp", "available": true, "scope": null, "accounts": [],
               "tools": [{"name": "orders", "state": "on"}]},
              {"name": "no id"}],
     "explanation": ["This is the most the bot can do.", "Only the apps and tools you chose below are allowed."]}
    """#

    static let reach = #"""
    {"bot_id": "a1b2c3d4e5", "mode": "listed", "peers": ["b2c3d4e5f6"], "revision": 7, "approve_peer_comms": true}
    """#

    static let connections = #"""
    {"apps": [{"id": "m1", "kind": "mcp", "label": "Shop server", "category": "Tool servers",
               "description": "An MCP tool server.", "state": "connected", "reason": "", "enabled": true, "auth": "none",
               "multi_account": false, "accounts": [], "tools": 4, "held_tools": 0,
               "used_by": [{"id": "a1b2c3d4e5", "name": "Scout", "scope": "write", "color": "#c8a24a"}],
               "limited_for": [], "catalog_id": null},
              {"id": "google", "kind": "native", "label": "Google", "category": "Productivity", "description": "Mail and calendar.",
               "state": "expired", "reason": "", "accounts": [{"id": "x", "label": "Work", "status": "expired"}],
               "used_by": [], "limited_for": []},
              {"id": "catalog:notes", "kind": "mcp", "label": "Notes", "category": "Productivity", "description": "",
               "state": "available", "used_by": []},
              {"label": "no id"}],
     "categories": [], "counts": {"connected": 1, "total": 3}, "bots_without_apps": []}
    """#

    static let profiles = #"""
    [{"id": "0a1b2c3d4e5f", "name": "Shop accounts", "created_at": 1792000000.0,
      "used_by": [{"id": "a1b2c3d4e5", "name": "Scout", "running": false}]},
     {"id": "1b2c3d4e5f6a", "name": "Research", "used_by": []},
     {"name": "no id"}]
    """#

    static let logins = #"""
    {"logins": [{"id": "l1", "site": "shop.example.com", "username": "orders", "hosts": ["shop.example.com"],
                 "has_totp": true, "exact_host": false, "bots": "all", "source": "settings", "last_used": 1793000000.0,
                 "created_at": 1792000000.0, "updated_at": 1792000000.0},
                {"id": "l2", "site": "supplier.example.org", "username": "buyer", "hosts": ["supplier.example.org"],
                 "has_totp": false, "bots": ["b2c3d4e5f6"], "last_used": null},
                {"site": "no id"}],
     "onepassword": {"available": true, "reason": "", "connected": false, "vaults": []}}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("botknow.memory") {
            let memory = try KJSON.decode(BotKnowMemoryDTO.self, from: BotKnowledgeSamples.memory)
            let notes = BotKnowWire.items(memory.index?.notes)
            let files = BotKnowWire.items(memory.files).items
            let entry = try KJSON.decode(BotKnowEntryAnswerDTO.self, from: BotKnowledgeSamples.entry)
            let settings = try KJSON.decode(BotKnowMemorySettingsDTO.self, from: BotKnowledgeSamples.memorySettings)
            let stale = try KJSON.decode(APIErrorBody.self, from: BotKnowledgeSamples.stale)
            guard notes.items.count == 3, notes.skipped == 1, notes.items[1].until == "2027-03-01",
                  notes.items[2].superseded != nil, memory.index?.lineLimit == 200, memory.index?.storedLines == 12,
                  memory.index?.hash?.count == 64, memory.settings?.roomCapture == false, memory.settings?.upkeep == true,
                  files.filter({ $0.kind == "topic" }).first?.title == "Suppliers",
                  memory.maintenance?.last?.time?.date != nil,
                  entry.changeId == "d1e2f3a4", entry.file?.hash?.count == 64, BotKnowWire.items(entry.file?.notes).items.count == 1,
                  settings.roomCapture == true, stale.text.hasPrefix("this note changed")
            else { throw SampleMismatch("memory fields") }
            return "\(notes.items.count) notes, \(notes.skipped) left out, a change and its undo id"
        },
        DecodeCheck("botknow.about") {
            let about = try KJSON.decode(BotKnowAboutDTO.self, from: BotKnowledgeSamples.about)
            let learned = BotKnowWire.items(about.learned)
            guard about.limit == 24_000, about.hash?.count == 64, learned.items.count == 2, learned.skipped == 1,
                  learned.items[0].learnedBy == "Scout", learned.items[0].at?.date != nil, learned.items[1].at?.date == nil,
                  // The desktop's hash is SHA-256 of the UTF-8 text (bot_profile.py: _hash).
                  BotKnowWire.aboutHash("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                  BotKnowWire.aboutHash("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            else { throw SampleMismatch("about fields") }
            return "text, hash, 2 learned facts, 1 left out"
        },
        DecodeCheck("botknow.usage") {
            let usage = try KJSON.decode(BotKnowUsageSummaryDTO.self, from: BotKnowledgeSamples.usage)
            let groups = BotKnowWire.items(usage.groups)
            let runs = BotKnowWire.items(try KJSON.decode(BotKnowUsageRunsDTO.self, from: BotKnowledgeSamples.runs).rows)
            let plan = BotKnowWire.items(try KJSON.decode(BotKnowPlanDTO.self, from: BotKnowledgeSamples.plan).providers).items
            guard usage.totals?.runs == 12, usage.totals?.costUsd == 1.25, usage.totals?.durationS == 840.5,
                  usage.totals?.unknownCostRuns == 2, groups.items.count == 2, groups.skipped == 1,
                  groups.items[1].costUsd == nil, usage.costNote?.hasPrefix("List-price") == true,
                  runs.items.count == 2, runs.skipped == 1, runs.items[0].trigger == "routine", runs.items[1].model == nil,
                  plan.count == 2, BotKnowWire.items(plan[0].windows).items.first?.usedPercent == 42.5,
                  BotKnowWire.items(plan[0].windows).items.last?.resetsAt?.date == nil, plan[1].status == "needs_sign_in"
            else { throw SampleMismatch("usage fields") }
            return "totals, 2 groups, 2 runs, 2 plans"
        },
        DecodeCheck("botknow.conversations") {
            let agent = try KJSON.decode(BotKnowAgentDTO.self, from: BotKnowledgeSamples.agent)
            let list = try KJSON.decode(BotKnowThreadListDTO.self, from: BotKnowledgeSamples.threads)
            let threads = BotKnowWire.items(list.threads)
            let deleted = try KJSON.decode(BotKnowDeleteDTO.self, from: BotKnowledgeSamples.deleted)
            let folders = BotKnowWire.items(agent.agent?.folders)
            guard agent.agent?.browserProfile == "shared:0a1b2c3d4e5f", agent.agent?.runsToday == 3,
                  agent.agent?.dailyRunCap == 50, folders.items.count == 2, folders.skipped == 1,
                  list.mainId == "s1", threads.items.count == 2, threads.skipped == 1,
                  threads.items[0].thread?.main == true, threads.items[1].thread?.archivedAt != nil,
                  threads.items[1].thread?.snoozedUntil == 0, threads.items[1].thread?.folderId == "f0a1b2c3d4",
                  deleted.busy == ["s2"], deleted.deleted == ["s3"]
            else { throw SampleMismatch("conversation fields") }
            return "2 folders, 2 conversations, a delete answer"
        },
        DecodeCheck("botknow.skills") {
            let skills = try KJSON.decode(BotKnowSkillsDTO.self, from: BotKnowledgeSamples.skills)
            let own = BotKnowWire.items(skills.skills)
            let library = BotKnowWire.items(try KJSON.decode(BotKnowLibraryDTO.self, from: BotKnowledgeSamples.library).skills).items
            guard own.items.count == 2, own.skipped == 1, own.items[0].needsReview == false, own.items[1].needsReview,
                  BotKnowWire.items(skills.library).items.first?.assignedVia == "every", skills.requests?.count == 1,
                  skills.settings?.sharing == "ask", skills.settings?.enabled == true,
                  library.count == 2, library[0].everyBot == true, library[1].assignedBots == ["a1b2c3d4e5"], library[1].needsReview
            else { throw SampleMismatch("skill fields") }
            return "2 skills, 1 left out, the library"
        },
        DecodeCheck("botknow.reach") {
            let access = try KJSON.decode(BotKnowAccessDTO.self, from: BotKnowledgeSamples.access)
            let apps = BotKnowWire.items(access.apps)
            let reach = try KJSON.decode(BotKnowReachDTO.self, from: BotKnowledgeSamples.reach)
            let connections = try KJSON.decode(BotKnowConnectionsDTO.self, from: BotKnowledgeSamples.connections)
            let found = BotKnowWire.items(connections.apps)
            let profiles = BotKnowWire.items(try KJSON.decode([BotKnowLossy<BotKnowProfileDTO>].self, from: BotKnowledgeSamples.profiles))
            let logins = try KJSON.decode(BotKnowLoginsDTO.self, from: BotKnowledgeSamples.logins)
            let saved = BotKnowWire.items(logins.logins)
            guard access.mode == "explicit", access.grants?.integrationIds == ["m1"], apps.items.count == 2, apps.skipped == 1,
                  apps.items[0].scope == "read", BotKnowWire.items(apps.items[0].tools).items.filter({ $0.state == "on" }).count == 1,
                  apps.items[1].scope == nil,
                  reach.mode == "listed", reach.approvePeerComms == true,
                  found.items.count == 3, found.skipped == 1, found.items[0].usedBy?.first?.value?.name == "Scout",
                  connections.counts?.connected == 1,
                  profiles.items.count == 2, profiles.skipped == 1, profiles.items[0].usedBy?.count == 1,
                  saved.items.count == 2, saved.skipped == 1, saved.items[0].allBots, saved.items[0].hasTotp == true,
                  saved.items[1].usable(by: "b2c3d4e5f6"), !saved.items[1].usable(by: "a1b2c3d4e5"),
                  saved.items[1].lastUsed?.date == nil, logins.onepassword?.connected == false
            else { throw SampleMismatch("access, reach, connection or login fields") }
            return "access, reach, 3 apps, 2 profiles, 2 logins"
        },
    ]
}
