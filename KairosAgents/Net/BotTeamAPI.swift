import Foundation

// The desktop's team routes as the Bots area reads them (Bots pass 5). Shapes were read from:
// - routes/bot_department_routes.py with services/bot_departments.py (_new, rename, delete, set_flags, set_chief,
//   instructions, put_instructions)
// - services/bot_team_memory.py (listing, propose with accept, action delete)
// - routes/bot_team_routes.py (team_map) with core/bot_assignments.py (live_edges)
// - routes/bot_activity_routes.py with services/bot_activity_report.py (team_report)
// A team is the desktop's "department": its members are the bots whose `section` is the team's name.
// Lists decode item by item (`BotLossy`, Net/BotInboxAPI.swift): one odd row is left out, never the list.

// MARK: - Teams

/// One team record (bot_departments.py: _new, plus `paused` and `hands_off` once set_flags ran). The answer of
/// PUT flags, PUT chief and PATCH rename, and each of the map's `departments`.
nonisolated struct BotTmDepartmentDTO: Decodable, Sendable {
    var id: String
    var name: String?
    var order: Double?
    var chiefBotId: String?
    /// Other team ids this team's chief also manages. Free JSON so an odd value never drops the team.
    var alsoManages: JSONValue?
    /// A whole number that goes up on every change; rename sends it back (409 when stale).
    var revision: Int?
    var paused: Bool?
    var handsOff: Bool?

    /// The other teams the chief manages, as ids. Nil when the desktop's value is not a list of ids.
    var managed: [String]? {
        guard let alsoManages else { return [] }
        if alsoManages.isNull { return [] }
        guard let items = alsoManages.array else { return nil }
        let ids = items.compactMap(\.string)
        return ids.count == items.count ? ids : nil
    }
}

/// GET /api/bot-departments/{id} (bot_department_routes.py: get): the team record with every member, hidden ones
/// too (bot_departments.py: members). Read fresh right before a chief write and for the Delete team confirm.
nonisolated struct BotTmTeamReadDTO: Decodable {
    var id: String
    var name: String?
    var order: Double?
    var chiefBotId: String?
    var alsoManages: JSONValue?
    var revision: Int?
    var paused: Bool?
    var handsOff: Bool?
    var members: [BotLossy<BotTmMemberRefDTO>]?

    var department: BotTmDepartmentDTO {
        BotTmDepartmentDTO(id: id, name: name, order: order, chiefBotId: chiefBotId, alsoManages: alsoManages,
                           revision: revision, paused: paused, handsOff: handsOff)
    }
}

/// A member in that read: a whole bot record, of which only the id and whether it is hidden are kept.
nonisolated struct BotTmMemberRefDTO: Decodable, Sendable {
    var id: String
    var hidden: Bool?
}

/// One live hand-off on the team map (core/bot_assignments.py: live_edges, renamed by bot_team_routes.py).
/// `status` is queued, running, needs_input, waiting or resume (finished ones are left out by the desktop).
nonisolated struct BotTmHandoffDTO: Decodable, Sendable {
    var assignmentId: String?
    var sourceBotId: String?
    var targetBotId: String?
    var sourceName: String?
    var targetName: String?
    var reason: String?
    var status: String?
    var roomId: String?
}

/// GET /api/bot-team/map, read item by item, with the team records' pause switch (the shared `BotTeamMapDTO`
/// does not carry it).
nonisolated struct BotTmMapDTO: Decodable {
    var departments: [BotLossy<BotTmDepartmentDTO>]?
    var rooms: [BotLossy<BotRoomDTO>]?
    var handoffs: [BotLossy<BotTmHandoffDTO>]?
}

// MARK: - Instructions and memory

/// GET and PUT /api/bot-departments/{id}/instructions (bot_departments.py: instructions). `hash` is the
/// SHA-256 of the text, sent back as `expected_hash`.
nonisolated struct BotTmInstructionsDTO: Decodable, Sendable, Equatable {
    var text: String?
    var hash: String?
    var maxBytes: Int?
}

/// One team memory entry (bot_team_memory.py). `kind` is person, place, decision or term; `status` is proposed
/// (a bot suggested it) or accepted. `revision` is a 64 character hash sent back to delete it.
nonisolated struct BotTmMemoryEntryDTO: Decodable, Sendable, Identifiable {
    var id: String
    var kind: String?
    var name: String?
    var detail: String?
    var status: String?
    var sourceBotId: String?
    var pinned: Bool?
    var revision: String?
    var createdAt: Double?
    var updatedAt: Double?
}

/// GET /api/bot-departments/{id}/memory
nonisolated struct BotTmMemoryListDTO: Decodable {
    var entries: [BotLossy<BotTmMemoryEntryDTO>]?
    var maxPromptBytes: Int?
}

// MARK: - The team report

/// GET /api/bot-reports/teams/{id}?days= (bot_activity_report.py: team_report).
nonisolated struct BotTmReportDTO: Decodable {
    var team: BotTmReportTeamDTO?
    var days: Int?
    var generatedAt: Double?
    var totals: BotTmReportTotalsDTO?
    var members: [BotLossy<BotTmReportMemberDTO>]?
    var produced: [BotLossy<BotReportProducedDTO>]?
}

nonisolated struct BotTmReportTeamDTO: Decodable, Sendable {
    var id: String?
    var name: String?
}

/// The team's totals. `cost_usd` is nil when no member's runs were priced, never 0 for unknown.
nonisolated struct BotTmReportTotalsDTO: Decodable, Sendable {
    var runs: Int?
    var finished: Int?
    var failed: Int?
    var tokens: Int?
    var costUsd: Double?
    /// Times the team's bots asked the person.
    var asked: Int?
    /// Steps that went ahead as the team's own work.
    var team: Int?
    var couldNotAsk: Int?
}

/// One member's line in the team report.
nonisolated struct BotTmReportMemberDTO: Decodable, Sendable {
    var botId: String
    var name: String?
    var role: String?
    /// light, standard or strong, when a team template gave it one.
    var tier: String?
    var runs: Int?
    var failed: Int?
    var tokens: Int?
    var costUsd: Double?
    var asked: Int?
    var teamAllowed: Int?
    var couldNotAsk: Int?
    var last: BotTmReportLastDTO?
}

/// The member's newest run in the window.
nonisolated struct BotTmReportLastDTO: Decodable, Sendable {
    var what: String?
    var result: String?
    var endedAt: Double?
}

// MARK: - Calls

extension APIClient {

    /// GET /api/bot-team/map: every team of this account with its pause switch, rooms and live hand-offs.
    func botTeamLiveMap() async throws -> BotTmMapDTO {
        try await get("/api/bot-team/map")
    }

    /// GET /api/bot-departments/{id}: one team record with all its members.
    func botTeamRead(_ teamID: String) async throws -> BotTmTeamReadDTO {
        try await get("/api/bot-departments/\(teamID)")
    }

    /// PATCH /api/bot-departments/{id}: a new name with the team's `expected_revision`. The desktop moves every
    /// member to the new name, and refuses (409) while one of them is working or when the revision is stale.
    func botTeamRename(_ teamID: String, name: String, expectedRevision: Int) async throws -> BotTmDepartmentDTO {
        try await request("PATCH", "/api/bot-departments/\(teamID)", json: ["name": name, "expected_revision": expectedRevision])
    }

    /// DELETE /api/bot-departments/{id}: the team goes and its bots leave it (their `section` is cleared).
    /// Refused (409) while one of its bots is working.
    func botTeamDelete(_ teamID: String) async throws {
        try await call("DELETE", "/api/bot-departments/\(teamID)")
    }

    /// PUT /api/bot-departments/{id}/flags with `paused` only.
    func botTeamSetPaused(_ teamID: String, _ paused: Bool) async throws -> BotTmDepartmentDTO {
        try await request("PUT", "/api/bot-departments/\(teamID)/flags", json: ["paused": paused])
    }

    /// GET /api/bot-departments/{id}/instructions
    func botTeamInstructions(_ teamID: String) async throws -> BotTmInstructionsDTO {
        try await get("/api/bot-departments/\(teamID)/instructions")
    }

    /// PUT /api/bot-departments/{id}/instructions with the text and the hash it was read at (409 when it changed).
    func botTeamSetInstructions(_ teamID: String, text: String, expectedHash: String) async throws -> BotTmInstructionsDTO {
        try await request("PUT", "/api/bot-departments/\(teamID)/instructions", json: ["text": text, "expected_hash": expectedHash])
    }

    /// PUT /api/bot-departments/{id}/chief: a member as chief, or nil for none. No revision check: with a bot the
    /// desktop saves `also_manages` exactly as sent (an empty list when it is left out); with none it saves an empty
    /// list. Callers send the list from a read made just before this call.
    func botTeamSetChief(_ teamID: String, botID: String?, alsoManages: [String]) async throws -> BotTmDepartmentDTO {
        let body: [String: Any] = ["bot_id": botID.map { $0 as Any } ?? NSNull(), "also_manages": alsoManages]
        return try await request("PUT", "/api/bot-departments/\(teamID)/chief", json: body)
    }

    /// GET /api/bot-departments/{id}/memory
    func botTeamMemory(_ teamID: String) async throws -> BotTmMemoryListDTO {
        try await get("/api/bot-departments/\(teamID)/memory")
    }

    /// POST /api/bot-departments/{id}/memory: an entry the person adds is accepted at once.
    func botTeamAddMemory(_ teamID: String, kind: String, name: String, detail: String) async throws -> BotTmMemoryEntryDTO {
        try await post("/api/bot-departments/\(teamID)/memory", json: ["kind": kind, "name": name, "detail": detail])
    }

    /// DELETE /api/bot-departments/{id}/memory/{entry} with the entry's `expected_revision` (409 when it changed).
    func botTeamDeleteMemory(_ teamID: String, entryID: String, expectedRevision: String) async throws {
        try await call("DELETE", "/api/bot-departments/\(teamID)/memory/\(entryID)", json: ["expected_revision": expectedRevision])
    }

    /// GET /api/bot-reports/teams/{id}?days= (1 to 90).
    func botTeamReport(_ teamID: String, days: Int) async throws -> BotTmReportDTO {
        try await get("/api/bot-reports/teams/\(teamID)", query: ["days": String(max(1, min(days, 90)))])
    }
}

// MARK: - Samples

/// A sample answer for every route above, shaped like the desktop's own (made-up content).
nonisolated enum BotTeamSamples {

    static let map = #"""
    {"departments": [
      {"id": "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5", "name": "Content", "order": 0, "chief_bot_id": "c3d4e5f6a7",
       "also_manages": [], "created_at": 1793300000.0, "revision": 4, "owner_user": "owner1",
       "paused": true, "hands_off": false, "model_tiers": {"c3d4e5f6a7": "strong"}},
      {"id": "e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6", "name": "Shop floor", "order": 1, "chief_bot_id": null,
       "also_manages": ["d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5"], "created_at": 1793300100.0, "revision": 1, "owner_user": "owner1"},
      {"id": 12, "name": "Odd"}
     ],
     "members": [],
     "bots": [],
     "rooms": [
      {"id": "r00m00000001", "name": "Content team", "context": "", "description": "Producer and Scout",
       "bulletin": "", "cwd": null, "default_responder": {"kind": "auto"}, "turn_timeout_minutes": 5,
       "setup_state": "done", "pinned_message_id": null, "revision": 4, "created_at": 1793400000.0, "archived_at": null,
       "members": [{"bot_id": "c3d4e5f6a7", "name": "Producer", "held": false, "working": true, "waiting": false},
                   {"bot_id": "a1b2c3d4e5", "name": "Scout", "held": false, "working": false, "waiting": false}],
       "working": true, "unread": 2, "last_seq": 14, "threads": []}
     ],
     "handoffs": [
      {"assignment_id": "as0001", "source": "c3d4e5f6a7", "target": "a1b2c3d4e5", "reason": "Find three spring sale ideas",
       "status": "running", "room_id": "r00m00000001", "source_bot_id": "c3d4e5f6a7", "target_bot_id": "a1b2c3d4e5",
       "source_name": "Producer", "target_name": "Scout"},
      {"assignment_id": "as0002", "source": "c3d4e5f6a7", "target": "a1b2c3d4e5", "reason": "Check the prices",
       "status": "needs_input", "room_id": null, "source_bot_id": "c3d4e5f6a7", "target_bot_id": "a1b2c3d4e5",
       "source_name": "Producer", "target_name": "Scout"}
     ]}
    """#

    static let department = #"""
    {"id": "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5", "name": "Studio", "order": 0, "chief_bot_id": null,
     "also_manages": [], "created_at": 1793300000.0, "revision": 5, "owner_user": "owner1", "paused": false}
    """#

    static let team = #"""
    {"id": "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5", "name": "Content", "order": 0, "chief_bot_id": "c3d4e5f6a7",
     "also_manages": ["e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6"], "created_at": 1793300000.0, "revision": 6,
     "owner_user": "owner1", "paused": true,
     "members": [{"id": "c3d4e5f6a7", "name": "Producer", "section": "Content", "hidden": false},
                 {"id": "a1b2c3d4e5", "name": "Scout", "section": "Content", "hidden": true},
                 {"name": "No id"}]}
    """#

    static let instructions = #"""
    {"text": "Keep captions under 20 words.", "hash": "4f1c2b3a4f1c2b3a4f1c2b3a4f1c2b3a4f1c2b3a4f1c2b3a4f1c2b3a4f1c2b3a", "max_bytes": 24000}
    """#

    static let memory = #"""
    {"entries": [
      {"kind": "decision", "name": "Sale dates", "detail": "The spring sale runs the first two weeks of April.",
       "aliases": [], "key": "", "pinned": false, "source_quote": "", "id": "m1", "status": "accepted",
       "source_bot_id": null, "created_at": 1793300000.0, "updated_at": 1793300000.0, "history": [],
       "revision": "aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44"},
      {"kind": "person", "name": "Sam", "detail": "Runs the repair bench on weekends.", "aliases": ["Sammy"],
       "key": "", "pinned": true, "source_quote": "", "id": "m2", "status": "proposed", "source_bot_id": "a1b2c3d4e5",
       "created_at": 1793300100.0, "updated_at": 1793300100.0, "history": [],
       "revision": "bb11bb22cc33dd44ee55ff66aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44"},
      {"kind": "place", "id": 3}
     ],
     "max_prompt_bytes": 6000}
    """#

    static let report = #"""
    {"team": {"id": "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5", "name": "Content", "internal_tools": 2},
     "days": 7, "generated_at": 1793400000.0,
     "totals": {"runs": 12, "finished": 10, "failed": 2, "tokens": 48000, "cost_usd": 1.25, "asked": 3, "team": 5, "could_not_ask": 0},
     "members": [
      {"bot_id": "c3d4e5f6a7", "name": "Producer", "role": "Runs the content team", "color": "#B9D2E3", "tier": "strong",
       "runs": 8, "failed": 1, "tokens": 30000, "cost_usd": 0.9, "asked": 2, "team_allowed": 4, "could_not_ask": 0,
       "last": {"what": "Routine: Morning plan", "result": "Finished", "ended_at": 1793399000.0,
                "link": {"tab": "botsShell", "agentId": "c3d4e5f6a7", "runId": "run1"}},
       "produced": [{"key": "scripts", "label": "Scripts", "count": 2, "items": ["Spring sale"]}]},
      {"bot_id": "a1b2c3d4e5", "name": "Scout", "role": "Research", "color": null, "tier": null,
       "runs": 4, "failed": 1, "tokens": 18000, "cost_usd": null, "asked": 1, "team_allowed": 1, "could_not_ask": 0,
       "last": null, "produced": []},
      {"name": "No id"}
     ],
     "produced": [{"key": "scripts", "label": "Scripts", "count": 2, "items": ["Spring sale"]},
                  {"key": "replies", "label": "Conversations it replied in", "count": 3, "items": []}]}
    """#

    static let stale = #"""
    {"detail": "The team changed. Reload it first"}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("botteams.map") {
            let map = try KJSON.decode(BotTmMapDTO.self, from: BotTeamSamples.map)
            let teams = BotLossyList(map.departments)
            let rooms = BotLossyList(map.rooms)
            let edges = BotLossyList(map.handoffs)
            guard teams.items.count == 2, teams.skipped == 1,
                  teams.items[0].paused == true, teams.items[0].revision == 4, teams.items[0].managed == [],
                  teams.items[1].paused == nil, teams.items[1].managed?.count == 1, teams.items[1].chiefBotId == nil,
                  rooms.items.first?.members?.count == 2,
                  edges.items.count == 2, edges.items[0].targetBotId == "a1b2c3d4e5", edges.items[1].roomId == nil,
                  BotTmMap.handoff(edges.items[1])?.status == "Waiting for you"
            else { throw SampleMismatch("team map") }
            return "\(teams.items.count) teams, \(teams.skipped) left out, \(edges.items.count) hand-offs"
        },
        DecodeCheck("botteams.writes") {
            let team = try KJSON.decode(BotTmDepartmentDTO.self, from: BotTeamSamples.department)
            let instructions = try KJSON.decode(BotTmInstructionsDTO.self, from: BotTeamSamples.instructions)
            let stale = try KJSON.decode(APIErrorBody.self, from: BotTeamSamples.stale)
            guard team.name == "Studio", team.revision == 5, team.paused == false,
                  instructions.hash?.count == 64, instructions.maxBytes == 24000,
                  stale.text.hasPrefix("The team changed") else { throw SampleMismatch("team writes") }
            return "rename, instructions, stale"
        },
        DecodeCheck("botteams.team") {
            let read = try KJSON.decode(BotTmTeamReadDTO.self, from: BotTeamSamples.team)
            let members = BotLossyList(read.members)
            guard read.department.chiefBotId == "c3d4e5f6a7", read.department.managed == ["e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6"],
                  read.revision == 6, read.paused == true,
                  members.items.count == 2, members.skipped == 1, members.items[1].hidden == true
            else { throw SampleMismatch("team read") }
            return "\(members.items.count) members, \(members.skipped) left out"
        },
        DecodeCheck("botteams.memory") {
            let list = BotLossyList(try KJSON.decode(BotTmMemoryListDTO.self, from: BotTeamSamples.memory).entries)
            guard list.items.count == 2, list.skipped == 1, list.items[0].revision?.count == 64,
                  list.items[1].status == "proposed", list.items[1].sourceBotId == "a1b2c3d4e5",
                  BotTmMap.kindTitle(list.items[0].kind) == "Decisions"
            else { throw SampleMismatch("team memory") }
            return "\(list.items.count) entries, \(list.skipped) left out"
        },
        DecodeCheck("botteams.report") {
            let report = try KJSON.decode(BotTmReportDTO.self, from: BotTeamSamples.report)
            let members = BotLossyList(report.members)
            let produced = BotLossyList(report.produced)
            guard report.totals?.runs == 12, report.totals?.costUsd == 1.25, report.totals?.asked == 3,
                  members.items.count == 2, members.skipped == 1, members.items[0].last?.result == "Finished",
                  members.items[1].costUsd == nil, members.items[1].last == nil,
                  produced.items.count == 2, produced.items[1].items?.isEmpty == true
            else { throw SampleMismatch("team report") }
            return "totals, \(members.items.count) members, \(produced.items.count) kinds made"
        },
    ]
}
