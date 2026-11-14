import Foundation

// The desktop routes behind You > Account, Permissions, Agent tools, Computer use, Remote access (paired phones)
// and Forge settings, as the phone reads them. Read from the desktop's own code:
//
// - GET /api/auth/status (routes/auth_routes.py: status): who is asking. Only flags are read: two-step on,
//   switching PIN set, machine access. No PIN, password or setup key is ever in this answer or on the phone.
// - GET /api/phone/devices, DELETE /api/phone/devices/{id} (routes/phone_app_routes.py). An id is d_ and 24 hex.
// - GET /api/permissions, DELETE /api/permissions/{rule_id} (routes/permission_routes.py over core/permissions.py).
//   A member gets only their own rules and decisions; the delete has no owner check on the desktop, so the
//   phone offers only rows the list returned.
// - GET and POST /api/settings/agent-tools (routes/settings_routes.py, admin). POST replaces the whole
//   disabled list, so a switch-off re-reads it first and sends it back with one name added.
// - GET /api/settings: only computer_use and computer_steps_days are read (vault_dir, a personal path, is left out).
//   POST /api/settings/computer-use (admin) replaces the whole object: enabled, allow_non_admins,
//   allow_reactions, desktop.
// - GET /api/computer (core/computer.py: running; the owner's own or, for an admin, all), GET /api/computer/status
//   (admin), POST /api/computer/{owner}/stop. The page address, lease id and steps are left out.
// - GET /api/forge/root, GET and PUT /api/forge/terminal/settings (routes/forge_routes.py, admin).

// MARK: - Answers

/// GET /api/auth/status, the flags only.
nonisolated struct YouAccessAuthStatusDTO: Decodable, Sendable {
    var authEnabled: JSONValue?
    var username: JSONValue?
    var isAdmin: JSONValue?
    var machineAccess: JSONValue?
    var totpEnabled: JSONValue?
    var color: JSONValue?
    /// Whether switching into this account asks a PIN. A yes or no; the PIN itself never leaves the desktop.
    var switchPin: JSONValue?
}

/// One paired phone (phone_app_routes.py: devices).
nonisolated struct YouAccessDeviceDTO: Decodable, Sendable {
    var id: String
    var name: JSONValue?
    var model: JSONValue?
    var createdAt: FlexibleDate?
    var lastSeenAt: FlexibleDate?
    var current: JSONValue?
}

/// GET /api/phone/devices, read phone by phone so one odd row cannot empty the list.
nonisolated struct YouAccessDevicesDTO: Decodable, Sendable {
    var devices: [YouAccessDeviceDTO] = []
    var skipped = 0

    private enum Keys: String, CodingKey { case devices }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        guard keyed.contains(.devices), (try? keyed.decodeNil(forKey: .devices)) == false else { return }
        var list = try keyed.nestedUnkeyedContainer(forKey: .devices)
        while !list.isAtEnd {
            if let device = try? list.decode(YouAccessDeviceDTO.self) {
                devices.append(device)
            } else {
                _ = try list.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

/// One saved permission rule (core/permissions.py: answer, ensure_seeded, grant_standing).
nonisolated struct YouAccessRuleDTO: Decodable, Sendable {
    var id: String
    var tool: JSONValue?
    /// The command, folder or site the rule covers, as the desktop keeps it. Null covers the whole tool.
    var content: JSONValue?
    /// "allow" or "deny".
    var behavior: JSONValue?
    /// "forever" or "session".
    var scope: JSONValue?
    var grantedAt: JSONValue?
    var grantedBy: JSONValue?
    /// "built-in", "settings", "asked" or "asked-team".
    var source: JSONValue?
    var adminOnly: JSONValue?
    var teamName: JSONValue?
    var botId: JSONValue?
}

/// One line of the permission audit (core/permissions.py: _record). No id of its own.
nonisolated struct YouAccessAuditDTO: Decodable, Sendable {
    var at: JSONValue?
    var decision: JSONValue?
    var tool: JSONValue?
    var content: JSONValue?
    var scope: JSONValue?
    var by: JSONValue?
}

/// GET /api/permissions: {"rules": [...], "audit": [... the last 50]}. Both read row by row.
nonisolated struct YouAccessPermissionsDTO: Decodable, Sendable {
    var rules: [YouAccessRuleDTO] = []
    var audit: [YouAccessAuditDTO] = []
    var skipped = 0

    private enum Keys: String, CodingKey { case rules, audit }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        if keyed.contains(.rules), (try? keyed.decodeNil(forKey: .rules)) == false {
            var list = try keyed.nestedUnkeyedContainer(forKey: .rules)
            while !list.isAtEnd {
                if let rule = try? list.decode(YouAccessRuleDTO.self) {
                    rules.append(rule)
                } else {
                    _ = try list.decode(JSONValue.self)
                    skipped += 1
                }
            }
        }
        if keyed.contains(.audit), (try? keyed.decodeNil(forKey: .audit)) == false {
            var list = try keyed.nestedUnkeyedContainer(forKey: .audit)
            while !list.isAtEnd {
                if let entry = try? list.decode(YouAccessAuditDTO.self) {
                    audit.append(entry)
                } else {
                    _ = try list.decode(JSONValue.self)
                }
            }
        }
    }
}

/// GET /api/settings/agent-tools: {"available": [names], "disabled": [names], "extra_allowed": [names]}.
nonisolated struct YouAccessAgentToolsDTO: Decodable, Sendable {
    var available: JSONValue?
    var disabled: JSONValue?
    var extraAllowed: JSONValue?

    var availableNames: [String] { YouAccessWire.names(available) }
    var disabledNames: [String] { YouAccessWire.names(disabled) }
    var extraNames: [String] { YouAccessWire.names(extraAllowed) }
    /// The disabled list could be read as names, so it can be sent back with one more.
    var disabledReadable: Bool {
        guard let disabled else { return true }
        if disabled.isNull { return true }
        guard let items = disabled.array else { return false }
        return items.allSatisfy { $0.string != nil }
    }
}

/// The computer_use object (core/settings.py defaults: all four false).
nonisolated struct YouAccessComputerUseDTO: Decodable, Sendable {
    var enabled: JSONValue?
    var allowNonAdmins: JSONValue?
    var allowReactions: JSONValue?
    var desktop: JSONValue?

    /// All four values as yes or no, or nil when one is missing or odd (then nothing is sent back).
    var values: YouAccessComputerUseValues? {
        guard let enabled = enabled?.bool, let others = allowNonAdmins?.bool,
              let reactions = allowReactions?.bool, let desktop = desktop?.bool else { return nil }
        return YouAccessComputerUseValues(enabled: enabled, allowNonAdmins: others, allowReactions: reactions, desktop: desktop)
    }
}

nonisolated struct YouAccessComputerUseValues: Hashable, Sendable {
    var enabled: Bool
    var allowNonAdmins: Bool
    var allowReactions: Bool
    var desktop: Bool
}

/// GET /api/settings, only the computer-use parts.
nonisolated struct YouAccessSettingsDTO: Decodable, Sendable {
    var computerUse: YouAccessComputerUseDTO?
    var computerStepsDays: JSONValue?
}

/// POST /api/settings/computer-use: {"ok": true, "computer_use": {...}}.
nonisolated struct YouAccessComputerUseSavedDTO: Decodable, Sendable {
    var ok: JSONValue?
    var computerUse: YouAccessComputerUseDTO?
}

/// One running computer (core/computer.py: running). The address, lease id and steps are left out.
nonisolated struct YouAccessRunningDTO: Decodable, Sendable {
    /// "chat:<session id>" or "agent:<bot id>".
    var owner: String
    var title: JSONValue?
    var desktop: JSONValue?
    var takenOver: JSONValue?
    var recording: JSONValue?
    var startedAt: JSONValue?
}

/// GET /api/computer: a JSON list, read row by row.
nonisolated struct YouAccessRunningListDTO: Decodable, Sendable {
    var computers: [YouAccessRunningDTO] = []
    var skipped = 0

    init(from decoder: Decoder) throws {
        var list = try decoder.unkeyedContainer()
        while !list.isAtEnd {
            if let item = try? list.decode(YouAccessRunningDTO.self) {
                computers.append(item)
            } else {
                _ = try list.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

nonisolated struct YouAccessProfileDTO: Decodable, Sendable {
    var id: String
    var name: JSONValue?
    var running: JSONValue?
}

/// GET /api/computer/status (admin): Docker and the kept browser profiles.
nonisolated struct YouAccessComputerStatusDTO: Decodable, Sendable {
    var dockerAvailable: JSONValue?
    var dockerReason: JSONValue?
    var imageReady: JSONValue?
    var desktopImageReady: JSONValue?
    var profiles: [YouAccessProfileDTO] = []

    private enum Keys: String, CodingKey { case dockerAvailable, dockerReason, imageReady, desktopImageReady, profiles }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        dockerAvailable = try? keyed.decodeIfPresent(JSONValue.self, forKey: .dockerAvailable)
        dockerReason = try? keyed.decodeIfPresent(JSONValue.self, forKey: .dockerReason)
        imageReady = try? keyed.decodeIfPresent(JSONValue.self, forKey: .imageReady)
        desktopImageReady = try? keyed.decodeIfPresent(JSONValue.self, forKey: .desktopImageReady)
        if keyed.contains(.profiles), (try? keyed.decodeNil(forKey: .profiles)) == false,
           var list = try? keyed.nestedUnkeyedContainer(forKey: .profiles) {
            while !list.isAtEnd {
                if let profile = try? list.decode(YouAccessProfileDTO.self) {
                    profiles.append(profile)
                } else {
                    _ = try list.decode(JSONValue.self)
                }
            }
        }
    }
}

/// GET /api/forge/root: {"path": "..."}. Only the last folder name is kept on the phone.
nonisolated struct YouAccessForgeRootDTO: Decodable, Sendable {
    var path: JSONValue?

    var folderName: String? { path?.string.flatMap(YouAccessWire.lastFolder) }
}

/// GET and PUT /api/forge/terminal/settings: {"forge_terminal_remote": bool}.
nonisolated struct YouAccessForgeTerminalDTO: Decodable, Sendable {
    var forgeTerminalRemote: JSONValue?
}

/// {"status": "revoked"} or {"ok": true}.
nonisolated struct YouAccessOkDTO: Decodable, Sendable {
    var ok: JSONValue?
    var status: JSONValue?
}

// MARK: - Wire helpers

nonisolated enum YouAccessWire {
    /// The account colours the desktop uses (core/auth.py: ACCOUNT_COLORS), as the phone draws them.
    static func colorHex(_ name: String?) -> UInt32 {
        switch (name ?? "").lowercased() {
        case "teal": 0x5FAFA8
        case "blue": 0x8FB8D6
        case "plum": 0xB49ACF
        case "red": 0xD98A80
        case "amber": 0xD9B260
        case "green": 0x8FB27E
        case "slate": 0x9AA3AD
        case "orange": 0xE0A878
        default: 0xD9B260
        }
    }

    /// A JSON list of names; anything that is not text is left out.
    static func names(_ value: JSONValue?) -> [String] {
        (value?.array ?? []).compactMap { $0.string?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The last folder of a Windows or POSIX path, so the whole personal path is never shown.
    static func lastFolder(_ path: String) -> String? {
        let parts = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).map(String.init).filter { !$0.isEmpty && !$0.hasSuffix(":") }
        return parts.last
    }

    /// The desktop sends 0 (1970) for a time it does not have, so anything before the year 2000 is not known.
    static let earliestKnown = Date(timeIntervalSince1970: 946_684_800)

    static func time(_ value: JSONValue?) -> Date? {
        guard let seconds = value?.double else { return nil }
        return known(Date(timeIntervalSince1970: seconds))
    }

    static func known(_ date: Date?) -> Date? {
        guard let date, date >= earliestKnown else { return nil }
        return date
    }

    /// A paired phone's id, as the desktop's route accepts it (phone_app_routes.py: ^d_[0-9a-f]{24}$).
    static func deviceID(_ id: String) throws -> String {
        let hex = id.dropFirst(2)
        guard id.hasPrefix("d_"), hex.count == 24, hex.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw YouAccessNotSent(plain: "The phone's id could not be read, so nothing was sent.")
        }
        return id
    }

    /// A rule id (uuid4 hex) goes into the path as it is; anything that could leave the path is refused.
    static func ruleID(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 80,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else {
            throw YouAccessNotSent(plain: "This rule's id could not be read, so nothing was sent.")
        }
        return id
    }

    /// A computer's owner ("chat:<id>" or "agent:<id>"), refused when it could leave the path.
    static func ownerPath(_ owner: String) throws -> String {
        let parts = owner.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "chat" || parts[0] == "agent", !parts[1].isEmpty, parts[1].count <= 120,
              parts[1].unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == "." }),
              parts[1] != ".", parts[1] != ".." else {
            throw YouAccessNotSent(plain: "This computer's owner could not be read, so nothing was sent.")
        }
        return owner
    }
}

// MARK: - Calls

extension APIClient {

    func youAccessAuthStatus() async throws -> YouAccessAuthStatusDTO {
        try await get("/api/auth/status")
    }

    func youAccessDevices() async throws -> YouAccessDevicesDTO {
        try await get("/api/phone/devices")
    }

    /// DELETE /api/phone/devices/{id}: 204. That phone's token stops working at once.
    func youAccessUnpair(_ deviceID: String) async throws {
        try await call("DELETE", "/api/phone/devices/" + YouAccessWire.deviceID(deviceID))
    }

    func youAccessPermissions() async throws -> YouAccessPermissionsDTO {
        try await get("/api/permissions")
    }

    /// DELETE /api/permissions/{rule_id}: {"status": "revoked"}; 404 "No such rule".
    func youAccessRevokeRule(_ ruleID: String) async throws -> YouAccessOkDTO {
        try await request("DELETE", "/api/permissions/" + YouAccessWire.ruleID(ruleID))
    }

    func youAccessAgentTools() async throws -> YouAccessAgentToolsDTO {
        try await get("/api/settings/agent-tools")
    }

    /// POST /api/settings/agent-tools with the whole disabled list: {"ok": true}.
    func youAccessSetDisabledTools(_ names: [String]) async throws -> YouAccessOkDTO {
        try await post("/api/settings/agent-tools", json: ["disabled_tools": names])
    }

    func youAccessSettings() async throws -> YouAccessSettingsDTO {
        try await get("/api/settings")
    }

    /// POST /api/settings/computer-use with all four values (the route replaces the whole object).
    func youAccessSetComputerUse(_ values: YouAccessComputerUseValues) async throws -> YouAccessComputerUseSavedDTO {
        try await post("/api/settings/computer-use", json: [
            "enabled": values.enabled,
            "allow_non_admins": values.allowNonAdmins,
            "allow_reactions": values.allowReactions,
            "desktop": values.desktop,
        ])
    }

    func youAccessComputers() async throws -> YouAccessRunningListDTO {
        try await get("/api/computer")
    }

    func youAccessComputerStatus() async throws -> YouAccessComputerStatusDTO {
        try await get("/api/computer/status")
    }

    /// POST /api/computer/{owner}/stop: {"ok": true}; 404 "computer is closed" when it already stopped.
    func youAccessStopComputer(_ owner: String) async throws -> YouAccessOkDTO {
        try await post("/api/computer/" + YouAccessWire.ownerPath(owner) + "/stop")
    }

    func youAccessForgeRoot() async throws -> YouAccessForgeRootDTO {
        try await get("/api/forge/root")
    }

    func youAccessForgeTerminal() async throws -> YouAccessForgeTerminalDTO {
        try await get("/api/forge/terminal/settings")
    }

    /// PUT /api/forge/terminal/settings with enabled false. The desktop also closes terminals opened remotely.
    /// The phone never sends true.
    func youAccessForgeTerminalOff() async throws -> YouAccessForgeTerminalDTO {
        try await request("PUT", "/api/forge/terminal/settings", json: ["enabled": false])
    }
}

// MARK: - Samples

/// A sample answer for every route above, shaped like the desktop's own (made-up content).
nonisolated enum YouAccessSamples {

    static let authStatus = #"""
    {"auth_enabled": true, "setup_required": false, "username": "alex", "is_admin": true, "machine_access": true,
     "own_sign_in": false, "totp_enabled": true, "color": "teal", "switch_pin": false, "other_users_exist": true,
     "local_access_locked": false, "instance": ""}
    """#

    static let devices = #"""
    {"devices": [
      {"id": "d_0123456789abcdef01234567", "name": "iPhone", "model": "iPhone17,1",
       "created_at": "2026-11-03T09:00:00Z", "last_seen_at": "2026-11-12T08:10:00Z", "current": true},
      {"id": "d_89abcdef0123456789abcdef", "name": "Old iPhone", "model": "iPhone15,2",
       "created_at": "2026-09-20T10:00:00Z", "last_seen_at": null, "current": false},
      {"name": "A phone with no id"}
    ]}
    """#

    static let permissions = #"""
    {"rules": [
      {"id": "7f3c2a1b9d8e4f6a8b7c6d5e4f3a2b1c", "tool": "Bash", "content": "git status", "behavior": "allow",
       "scope": "forever", "granted_at": 1793000000.5, "granted_by": "alex", "source": "asked"},
      {"id": "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d", "tool": "Read", "content": null, "behavior": "allow",
       "scope": "forever", "granted_at": 1792000000, "granted_by": "jarvis", "source": "built-in", "admin_only": false},
      {"id": "9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b", "tool": "WebFetch", "content": "example.com", "behavior": "deny",
       "scope": "session", "granted_at": 1793100000, "granted_by": "alex", "source": "asked", "bot_id": "scout"},
      {"tool": "Write"}
    ],
    "audit": [
      {"at": 1793000000.5, "decision": "allow", "tool": "Bash", "content": "git status", "scope": "forever", "by": "alex", "request_id": "r1"},
      {"at": 1793100500, "decision": "revoked", "rule_id": "abc"},
      {"at": 1793200000, "decision": "chat_mode_changed", "session_id": "s1", "mode": "plan", "by": "alex"}
    ]}
    """#

    static let agentTools = #"""
    {"available": ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "WebFetch", "WebSearch", "Task", "TodoWrite", "NotebookEdit"],
     "disabled": ["WebFetch"], "extra_allowed": ["mcp__design__create_page"]}
    """#

    static let settings = #"""
    {"onboarding_complete": true, "vault_dir": "/home/example/vault", "disabled_tools": [], "auto_compact": true,
     "computer_use": {"enabled": true, "allow_non_admins": false, "allow_reactions": false, "desktop": true},
     "computer_steps_days": 7, "helper_endpoint_id": null, "helper_endpoint": null, "ring_preference": "app"}
    """#

    static let computerUseSaved = #"""
    {"ok": true, "computer_use": {"enabled": false, "allow_non_admins": false, "allow_reactions": false, "desktop": true}}
    """#

    static let computers = #"""
    [
      {"owner": "agent:scout", "url": "https://example.com/parts", "title": "Parts list", "last_action": 1793000000,
       "taken_over": false, "waiting_model": false, "desktop": false, "recording": false, "lease_id": "lease-sample",
       "started_at": 1792999000, "steps": []},
      {"owner": "chat:5b9e2f0a4c18", "url": "https://example.com/invoices", "title": "", "taken_over": true,
       "desktop": true, "started_at": 1793000100},
      {"title": "No owner"}
    ]
    """#

    static let computerStatus = #"""
    {"docker_available": false, "docker_reason": "Docker is not running.", "image_ready": false,
     "desktop_image_ready": false, "profiles": [{"id": "scout", "name": "Scout", "running": true}, {"name": "No id"}]}
    """#

    static let forgeRoot = #"{"path": "C:\\Users\\example\\Kairos\\Forge"}"#

    static let forgeTerminal = #"{"forge_terminal_remote": true}"#

    static let revoked = #"{"status": "revoked"}"#

    static let checks: [DecodeCheck] = [
        DecodeCheck("youaccess.auth") {
            let read = try KJSON.decode(YouAccessAuthStatusDTO.self, from: YouAccessSamples.authStatus)
            guard read.username?.string == "alex", read.isAdmin?.bool == true, read.totpEnabled?.bool == true,
                  read.switchPin?.bool == false, read.machineAccess?.bool == true,
                  YouAccessWire.colorHex(read.color?.string) == 0x5FAFA8 else { throw SampleMismatch("auth flags") }
            return "flags, colour"
        },
        DecodeCheck("youaccess.devices") {
            let read = try KJSON.decode(YouAccessDevicesDTO.self, from: YouAccessSamples.devices)
            guard read.devices.count == 2, read.skipped == 1, read.devices[0].current?.bool == true,
                  read.devices[0].lastSeenAt?.date != nil, read.devices[1].lastSeenAt?.date == nil,
                  (try? YouAccessWire.deviceID(read.devices[0].id)) != nil,
                  (try? YouAccessWire.deviceID("d_../x")) == nil else { throw SampleMismatch("devices") }
            return "2 phones, 1 skipped"
        },
        DecodeCheck("youaccess.permissions") {
            let read = try KJSON.decode(YouAccessPermissionsDTO.self, from: YouAccessSamples.permissions)
            guard read.rules.count == 3, read.skipped == 1, read.audit.count == 3,
                  read.rules[0].content?.string == "git status", read.rules[1].content?.isNull == true,
                  read.rules[2].behavior?.string == "deny", read.rules[2].scope?.string == "session",
                  YouAccessWire.time(read.rules[0].grantedAt) != nil,
                  (try? YouAccessWire.ruleID(read.rules[0].id)) != nil, (try? YouAccessWire.ruleID("a/b")) == nil else {
                throw SampleMismatch("permissions")
            }
            let live = YouAccessLive.rules(from: read)
            let lines = YouAccessLive.decisions(from: read)
            guard live.count == 3, live[1].who == "built in", lines.count == 3, lines[0].title.hasPrefix("Changed") else {
                throw SampleMismatch("permission rows")
            }
            return "3 rules, 1 skipped, 3 decisions"
        },
        DecodeCheck("youaccess.tools") {
            let read = try KJSON.decode(YouAccessAgentToolsDTO.self, from: YouAccessSamples.agentTools)
            guard read.availableNames.count == 11, read.disabledNames == ["WebFetch"], read.disabledReadable,
                  read.extraNames == ["mcp__design__create_page"] else { throw SampleMismatch("tools") }
            let odd = try KJSON.decode(YouAccessAgentToolsDTO.self, from: #"{"available": ["Bash"], "disabled": [1]}"#)
            guard !odd.disabledReadable else { throw SampleMismatch("odd disabled list") }
            return "11 tools, 1 off, 1 extra"
        },
        DecodeCheck("youaccess.computeruse") {
            let read = try KJSON.decode(YouAccessSettingsDTO.self, from: YouAccessSamples.settings)
            let saved = try KJSON.decode(YouAccessComputerUseSavedDTO.self, from: YouAccessSamples.computerUseSaved)
            guard let values = read.computerUse?.values, values.enabled, values.desktop, !values.allowNonAdmins,
                  read.computerStepsDays?.int == 7, saved.computerUse?.values?.enabled == false,
                  saved.computerUse?.values?.desktop == true else { throw SampleMismatch("computer use") }
            let partial = try KJSON.decode(YouAccessSettingsDTO.self, from: #"{"computer_use": {"enabled": true}}"#)
            guard partial.computerUse?.values == nil else { throw SampleMismatch("partial object") }
            return "four values, saved, partial refused"
        },
        DecodeCheck("youaccess.computers") {
            let read = try KJSON.decode(YouAccessRunningListDTO.self, from: YouAccessSamples.computers)
            let status = try KJSON.decode(YouAccessComputerStatusDTO.self, from: YouAccessSamples.computerStatus)
            guard read.computers.count == 2, read.skipped == 1, read.computers[1].takenOver?.bool == true,
                  (try? YouAccessWire.ownerPath(read.computers[0].owner)) != nil,
                  (try? YouAccessWire.ownerPath("chat:../x")) == nil, (try? YouAccessWire.ownerPath("file:x")) == nil,
                  status.dockerAvailable?.bool == false, status.profiles.count == 1,
                  status.profiles[0].running?.bool == true else { throw SampleMismatch("computers") }
            return "2 running, 1 skipped, status"
        },
        DecodeCheck("youaccess.forge") {
            let root = try KJSON.decode(YouAccessForgeRootDTO.self, from: YouAccessSamples.forgeRoot)
            let terminal = try KJSON.decode(YouAccessForgeTerminalDTO.self, from: YouAccessSamples.forgeTerminal)
            let gone = try KJSON.decode(YouAccessOkDTO.self, from: YouAccessSamples.revoked)
            guard root.folderName == "Forge", YouAccessWire.lastFolder("/home/example/forge/") == "forge",
                  terminal.forgeTerminalRemote?.bool == true, gone.status?.string == "revoked" else {
                throw SampleMismatch("forge")
            }
            return "folder name only, terminal on"
        },
        DecodeCheck("youaccess.mask") {
            // Made-up values only.
            let cases: [(String, String)] = [
                ("git status", "git status"),
                ("curl -H 'Authorization: Bearer madeupvalue' https://example.com/x",
                 "curl -H 'Authorization: Bearer ••••' https://example.com/x"),
                ("https://someone:notreal@example.com/sign-in", "https://example.com/sign-in"),
                ("https://example.com/cb?code=abc&state=xyz", "https://example.com/cb?code=••••&state=••••"),
                ("export API_KEY=madeup && run", "export API_KEY=•••• && run"),
                ("login password=\"two words\" now", "login password=•••• now"),
                ("use secret=madeup", "use secret=••••"),
                ("send abcdefghij0123456789ABCDEFGHIJ ok", "send •••• ok"),
                ("aaaaaaaaaabbbbbbbbbbcccccccccc", "aaaaaaaaaabbbbbbbbbbcccccccccc"),
                ("Edit(projects/bike-shop-2/Sources/Checkout.swift)", "Edit(projects/bike-shop-2/Sources/Checkout.swift)"),
            ]
            for (text, wanted) in cases where youAccessMasked(text) != wanted {
                throw SampleMismatch("mask: " + wanted)
            }
            let read = try KJSON.decode(YouAccessPermissionsDTO.self, from: #"""
            {"rules": [{"id": "0a1b2c3d", "tool": "Bash", "content": "deploy --token=madeup"}],
             "audit": [{"at": 1793000000, "decision": "allow", "tool": "Bash", "content": "deploy --token=madeup"}]}
            """#)
            let rows = YouAccessLive.rules(from: read)
            let lines = YouAccessLive.decisions(from: read)
            guard rows.first?.content == "deploy --token=••••", rows.first?.id == "0a1b2c3d",
                  lines.first?.title.contains("madeup") == false else { throw SampleMismatch("masked rows") }
            return "\(cases.count) texts, rows masked, id kept"
        },
        DecodeCheck("youaccess.guards") {
            let devices = try KJSON.decode(YouAccessDevicesDTO.self, from: #"""
            {"devices": [{"id": "d_0123456789abcdef01234567", "created_at": 0, "last_seen_at": "1970-01-01T00:00:00Z"}]}
            """#)
            guard devices.devices.count == 1,
                  YouAccessWire.known(devices.devices[0].createdAt?.date) == nil,
                  YouAccessWire.known(devices.devices[0].lastSeenAt?.date) == nil,
                  YouAccessWire.time(.number(100)) == nil, YouAccessWire.time(.number(1793000000)) != nil,
                  YouAccessLive.ago(Date(timeIntervalSince1970: 0)) == "not yet" else { throw SampleMismatch("old dates") }
            guard notSent({ try YouAccessWire.ruleID("a/b") }), notSent({ try YouAccessWire.deviceID("d_x") }),
                  notSent({ try YouAccessWire.ownerPath("chat:../x") }) else {
                throw SampleMismatch("a bad id was not refused as not sent")
            }
            return "dates before 2000 not known, bad ids not sent"
        },
    ]

    /// The path guard refused this id as never sent.
    private static func notSent(_ guardCall: () throws -> String) -> Bool {
        do {
            _ = try guardCall()
            return false
        } catch {
            return error is YouAccessNotSent
        }
    }
}
