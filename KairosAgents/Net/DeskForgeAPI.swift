import Foundation

// The desktop's Forge routes (routes/forge_routes.py over services/forge_projects.py, forge_sessions.py,
// forge_apps.py, forge_session_git.py and forge_git.py), as the phone reads them for Desktop home and
// Forge sessions. Every /api/forge route answers an admin account only (the router's require_admin).
//
// - A Forge session is a chat session with a `forge` record. Its turns run through the chat routes
//   (POST /api/chat/live with a request id, /api/chat/live/stop, /api/permissions/{id}/answer), which
//   Net/ChatAPI.swift already has; this file adds the Forge routes around them.
// - POST /api/forge/sessions takes no request id: it makes a worktree, a branch and the session, and the
//   task itself is then sent as the session's first message.
// - The phone never calls: PUT /root, POST /apps/shutdown, the terminal routes, the project add, new and
//   clone routes, PUT app/command, GET app/suggest, first-commit, or DELETE /api/sessions/{id} for a Forge
//   session (that one would leave the worktree behind).

// MARK: - Lists

/// A JSON list read item by item: one odd row is skipped and counted, never the whole list.
nonisolated struct DeskForgeList<Item: Decodable & Sendable>: Decodable, Sendable {
    var items: [Item] = []
    var skipped = 0

    init(from decoder: Decoder) throws {
        var list = try decoder.unkeyedContainer()
        while !list.isAtEnd {
            if let item = try? list.decode(Item.self) {
                items.append(item)
            } else {
                // A failed decode does not move past the element; read it as anything to step over it.
                _ = try list.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

// MARK: - Projects

nonisolated struct DeskForgeDayDTO: Decodable, Hashable, Sendable {
    var date: String?
    var commits: Int?
    var added: Int?
    var removed: Int?
}

nonisolated struct DeskForgeDeltaDTO: Decodable, Hashable, Sendable {
    var commits: Int?
    var contributors: Int?
    var added: Int?
    var removed: Int?
}

nonisolated struct DeskForgeBucketDTO: Decodable, Hashable, Sendable {
    var date: String?
    var commits: Int?
}

/// `lifespan` of a git summary (forge_git.py: _summarize). Commit times are epoch seconds.
nonisolated struct DeskForgeLifespanDTO: Decodable, Hashable, Sendable {
    var commits: Int?
    var contributors: Int?
    var firstCommit: Double?
    var lastCommit: Double?
    var added: Int?
    var removed: Int?
    var ageDays: Int?
    var delta: DeskForgeDeltaDTO?
    /// "weekly" or "monthly".
    var bucket: String?
    var buckets: [DeskForgeBucketDTO]?
}

nonisolated struct DeskForgeLanguageDTO: Decodable, Hashable, Sendable {
    /// A file extension (".ts"), "No extension" or "Other".
    var name: String?
    var bytes: Double?
}

/// One row of `hotspots` (path) or `contributors` (name).
nonisolated struct DeskForgeRankDTO: Decodable, Hashable, Sendable {
    var path: String?
    var name: String?
    var commits: Int?
    var added: Int?
    var removed: Int?
}

/// A project's git summary (forge_git.py: summary, or routes/forge_routes.py: read_summary's error shape).
nonisolated struct DeskForgeGitDTO: Decodable, Hashable, Sendable {
    /// "ok", "empty" (no commits), "not_git", "unavailable" or "error".
    var state: String?
    var message: String?
    var branch: String?
    var activity: [DeskForgeDayDTO]?
    var lifespan: DeskForgeLifespanDTO?
    var languages: [DeskForgeLanguageDTO]?
    /// Seven weekdays (Monday first), 24 hours each.
    var rhythm: [[Int]]?
    var hotspots: [DeskForgeRankDTO]?
    var contributors: [DeskForgeRankDTO]?
}

/// One row of GET /api/forge/projects (forge_projects.py: add builds it; the route adds `git`).
/// Everything but the id is read leniently, so one odd summary cannot hide a project.
nonisolated struct DeskForgeProjectDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
    var path: String?
    var addedAt: Double?
    var lastOpenedAt: Double?
    /// The saved app command, shown read only. Set on the desktop.
    var appCommand: String?
    var git: DeskForgeGitDTO?

    private enum CodingKeys: String, CodingKey {
        case id, name, path, addedAt, lastOpenedAt, appCommand, git
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        path = try? container.decodeIfPresent(String.self, forKey: .path)
        addedAt = try? container.decodeIfPresent(Double.self, forKey: .addedAt)
        lastOpenedAt = try? container.decodeIfPresent(Double.self, forKey: .lastOpenedAt)
        appCommand = try? container.decodeIfPresent(String.self, forKey: .appCommand)
        git = try? container.decodeIfPresent(DeskForgeGitDTO.self, forKey: .git)
    }
}

/// One row of GET /api/forge/projects/{id}/branches. `worktree` is set when the branch is checked out.
nonisolated struct DeskForgeBranchDTO: Decodable, Hashable, Sendable {
    var name: String
    var worktree: String?
}

nonisolated struct DeskForgeWorkingDTO: Decodable, Hashable, Sendable {
    var id: String?
    var title: String?
    var projectName: String?
}

/// GET /api/forge/activity: the last 14 days over every project, and the sessions working now.
nonisolated struct DeskForgeActivityDTO: Decodable, Hashable, Sendable {
    var days: [DeskForgeDayDTO]?
    var working: [DeskForgeWorkingDTO]?
}

// MARK: - Sessions

/// A session's `forge` record (forge_sessions.py: create). `removed` is set once the session has ended.
nonisolated struct DeskForgeDetailsDTO: Decodable, Hashable, Sendable {
    var projectId: String?
    var worktree: String?
    var branch: String?
    var baseBranch: String?
    /// "build" or "plan".
    var mode: String?
    /// "new_worktree", "existing_branch" or "in_place".
    var isolation: String?
    var removed: Bool?
}

/// One row of GET /api/forge/projects/{id}/sessions (a chat header plus `forge` and `workspace_dir`).
nonisolated struct DeskForgeSessionRowDTO: Decodable, Hashable, Sendable {
    var id: String
    var title: String?
    var createdAt: Double?
    var updatedAt: Double?
    var messageCount: Int?
    var modelEndpointId: String?
    var forge: DeskForgeDetailsDTO?
    var workspaceDir: String?
}

/// GET /api/forge/sessions/{id}, POST /api/forge/sessions and POST .../mode: the whole chat session
/// (routes/session_routes.py: _for_client). Only what the phone shows is read.
nonisolated struct DeskForgeSessionDTO: Decodable, Sendable {
    var id: String
    var title: String?
    var createdAt: Double?
    var updatedAt: Double?
    var messages: DeskForgeList<ChatMessageDTO>?
    var modelEndpointId: String?
    var modelOverride: String?
    var modelEffort: String?
    /// "base" (asks first) or "auto" (full access).
    var permissionMode: String?
    var workspaceDir: String?
    var forge: DeskForgeDetailsDTO?
}

/// DELETE /api/forge/sessions/{id} and POST .../end (forge_sessions.py: remove; forge_session_git.py: end).
nonisolated struct DeskForgeEndDTO: Decodable, Hashable, Sendable {
    var ok: Bool?
    var branch: String?
    var keptProjectFolder: Bool?
    var branchDiscarded: Bool?
    /// "Worktree removed, but the branch was kept. ..." when a discard could not delete the branch.
    var warning: String?
}

nonisolated struct DeskForgeOkDTO: Decodable, Hashable, Sendable {
    var ok: Bool?
}

// MARK: - Checkpoints and runs

nonisolated struct DeskForgeChangeDTO: Decodable, Hashable, Sendable {
    var path: String?
    /// Set once this file was put back.
    var restoredAt: Double?
}

nonisolated struct DeskForgeRootDTO: Decodable, Hashable, Sendable {
    var changes: [DeskForgeChangeDTO]?
}

/// One row of GET /api/forge/sessions/{id}/checkpoints (core/file_checkpoints.py: list_events): what one
/// turn changed in the session's folder. It belongs to the turn whose run it started and finished inside.
nonisolated struct DeskForgeCheckpointDTO: Decodable, Hashable, Sendable {
    var id: String
    var created: Double?
    var finished: Double?
    /// "running", "changed" or "unchanged".
    var status: String?
    /// Another checkpoint ran over the same folder at the same time: it cannot be undone safely.
    var overlap: Bool?
    var roots: [DeskForgeRootDTO]?
}

/// POST .../checkpoints/{event}/undo: the files put back.
nonisolated struct DeskForgeUndoDTO: Decodable, Hashable, Sendable {
    var restored: [JSONValue]?
}

/// One row of GET /api/runs?session_id= (the session store's `runs` table).
nonisolated struct DeskForgeRunRowDTO: Decodable, Hashable, Sendable {
    var id: String
    /// "chat" for a turn of the session.
    var surface: String?
    var startedAt: Double?
    var endedAt: Double?
}

/// One step of GET /api/runs/{id} (`run_events`): "tool_started" carries the tool's input in `detail`,
/// "tool_finished" what it returned.
nonisolated struct DeskForgeRunStepDTO: Decodable, Hashable, Sendable {
    var kind: String?
    var name: String?
    var ok: Bool?
    var detail: String?
}

nonisolated struct DeskForgeRunDTO: Decodable, Sendable {
    var id: String?
    var steps: DeskForgeList<DeskForgeRunStepDTO>?
}

// MARK: - Apps

/// GET .../app/status and one row of GET /api/forge/apps/running (forge_apps.py: status).
nonisolated struct DeskForgeAppDTO: Decodable, Hashable, Sendable {
    var sessionId: String?
    var projectId: String?
    /// The command as it was started, with the port filled in.
    var command: String?
    var running: Bool?
    var ready: Bool?
    var port: Int?
}

/// One packet of an approval stream (routes/forge_routes.py: approval_stream): a request to approve,
/// then the result (`status`) or why it did not happen (`error`).
nonisolated struct DeskForgeStreamPacketDTO: Decodable, Sendable {
    var permission: ChatPermissionDTO?
    var finished = false
    var error: String?

    private enum CodingKeys: String, CodingKey { case permission, status, error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        permission = try? container.decodeIfPresent(ChatPermissionDTO.self, forKey: .permission)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        finished = container.contains(.status)
    }
}

// MARK: - Wire helpers

nonisolated enum DeskForgeWire {
    /// An approval stream stays quiet while the person decides (the desktop waits 120 seconds) and while an
    /// app starts (30 more), so it gets its own longer wait.
    static let streamSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 200
        configuration.timeoutIntervalForResource = 600
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    /// An id goes into the path as it is. One that could leave its path is refused.
    static func pathID(_ id: String) throws -> String {
        guard !id.isEmpty, id != ".", id != "..",
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else {
            throw APIError.unreadable("forge id")
        }
        return id
    }

    /// What a tool was pointed at, from the input the desktop saved for a run step: the file, command,
    /// query or address in it. Text that is not JSON is shown as it is, shortened.
    static func target(_ detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return "" }
        // Read with the keys as the desktop wrote them (KJSON would rename "file_path").
        if let data = detail.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data),
           let fields = object as? [String: Any] {
            for key in ["file_path", "path", "command", "cmd", "query", "pattern", "url"] {
                if let text = fields[key] as? String, !text.isEmpty { return text }
            }
            if let changes = fields["changes"] as? [[String: Any]] {
                let paths = changes.compactMap { $0["path"] as? String }
                if !paths.isEmpty { return paths.joined(separator: ", ") }
            }
            return ""
        }
        return String(detail.prefix(200))
    }

    /// The desktop's own sorting of a tool by its name: an edit, a command, a read or another tool.
    static func stepKind(_ name: String?) -> String {
        let lower = (name ?? "").lowercased()
        func has(_ words: [String]) -> Bool { words.contains { lower.contains($0) } }
        if has(["edit", "write", "patch", "file_change"]) { return "edit" }
        if has(["shell", "bash", "exec", "command", "terminal"]) { return "command" }
        if has(["search", "grep", "glob"]) { return "search" }
        if has(["read", "file"]) { return "read" }
        return "tool"
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/forge/projects: this account's projects, newest opened first, each with its git summary.
    func deskForgeProjects() async throws -> DeskForgeList<DeskForgeProjectDTO> {
        try await get("/api/forge/projects")
    }

    /// GET /api/forge/projects/{id}/summary.
    func deskForgeProjectSummary(_ id: String) async throws -> DeskForgeGitDTO {
        try await get("/api/forge/projects/" + DeskForgeWire.pathID(id) + "/summary")
    }

    /// GET /api/forge/projects/{id}/sessions: ended sessions included (`forge.removed`).
    func deskForgeProjectSessions(_ id: String) async throws -> DeskForgeList<DeskForgeSessionRowDTO> {
        try await get("/api/forge/projects/" + DeskForgeWire.pathID(id) + "/sessions")
    }

    /// GET /api/forge/projects/{id}/branches.
    func deskForgeProjectBranches(_ id: String) async throws -> DeskForgeList<DeskForgeBranchDTO> {
        try await get("/api/forge/projects/" + DeskForgeWire.pathID(id) + "/branches")
    }

    /// DELETE /api/forge/projects/{id}: drops the record only. The folder and its files stay.
    func deskForgeProjectRemove(_ id: String) async throws -> DeskForgeOkDTO {
        try await request("DELETE", "/api/forge/projects/" + DeskForgeWire.pathID(id))
    }

    /// GET /api/forge/activity.
    func deskForgeActivity() async throws -> DeskForgeActivityDTO {
        try await get("/api/forge/activity")
    }

    /// GET /api/forge/apps/running.
    func deskForgeAppsRunning() async throws -> DeskForgeList<DeskForgeAppDTO> {
        try await get("/api/forge/apps/running")
    }

    /// GET /api/forge/sessions/{id}/app/status.
    func deskForgeAppStatus(_ sessionID: String) async throws -> DeskForgeAppDTO {
        try await get("/api/forge/sessions/" + DeskForgeWire.pathID(sessionID) + "/app/status")
    }

    /// GET /api/forge/sessions/{id}.
    func deskForgeSession(_ id: String) async throws -> DeskForgeSessionDTO {
        try await get("/api/forge/sessions/" + DeskForgeWire.pathID(id))
    }

    /// POST /api/forge/sessions. Makes the worktree, the branch and the session; it does not send the task.
    /// There is no request id: after a lost answer the caller reads the sessions again and never sends twice.
    /// `isolation` is "new_worktree", "existing_branch" (with `branch`) or "in_place".
    func deskForgeSessionCreate(projectId: String, task: String, endpointId: String?, mode: String,
                                isolation: String, branch: String?) async throws -> DeskForgeSessionDTO {
        var body: [String: Any] = ["project_id": projectId, "task": task, "mode": mode, "isolation": isolation]
        if let endpointId { body["model_endpoint_id"] = endpointId }
        if let branch { body["branch"] = branch }
        return try await post("/api/forge/sessions", json: body)
    }

    /// POST /api/forge/sessions/{id}/mode: "build" or "plan". 409 while a turn runs.
    func deskForgeSetMode(_ id: String, mode: String) async throws -> DeskForgeSessionDTO {
        try await post("/api/forge/sessions/" + DeskForgeWire.pathID(id) + "/mode", json: ["mode": mode])
    }

    /// GET /api/forge/sessions/{id}/checkpoints, newest first.
    func deskForgeCheckpoints(_ id: String) async throws -> DeskForgeList<DeskForgeCheckpointDTO> {
        try await get("/api/forge/sessions/" + DeskForgeWire.pathID(id) + "/checkpoints")
    }

    /// POST .../checkpoints/{event}/undo with `confirmed`. 409 when a file changed since, and nothing is put back.
    func deskForgeUndo(_ id: String, checkpoint: String) async throws -> DeskForgeUndoDTO {
        try await post("/api/forge/sessions/" + DeskForgeWire.pathID(id) + "/checkpoints/"
                       + DeskForgeWire.pathID(checkpoint) + "/undo", json: ["confirmed": true])
    }

    /// DELETE /api/forge/sessions/{id}, never with `discard`: removes the worktree and ends the session.
    /// The branch and the conversation stay. 409 when the worktree has uncommitted changes.
    func deskForgeSessionRemove(_ id: String) async throws -> DeskForgeEndDTO {
        try await request("DELETE", "/api/forge/sessions/" + DeskForgeWire.pathID(id))
    }

    /// POST /api/forge/sessions/{id}/end with "keep-branch" or "discard". Discard carries `confirmed`.
    /// ("merge" answers an approval stream: see `deskForgeApprovalStream`.)
    func deskForgeEnd(_ id: String, option: String, confirmed: Bool) async throws -> DeskForgeEndDTO {
        try await post("/api/forge/sessions/" + DeskForgeWire.pathID(id) + "/end",
                       json: ["option": option, "confirmed": confirmed])
    }

    /// GET /api/runs?session_id=: the session's runs, newest first.
    func deskForgeRuns(sessionID: String) async throws -> DeskForgeList<DeskForgeRunRowDTO> {
        try await get("/api/runs", query: ["session_id": sessionID, "limit": "500"])
    }

    /// GET /api/runs/{id}: one run with its steps.
    func deskForgeRun(_ id: String) async throws -> DeskForgeRunDTO {
        try await get("/api/runs/" + DeskForgeWire.pathID(id))
    }

    /// POST a route that answers an approval stream (app start, end with merge). The caller reads its lines:
    /// a request to approve, then a result or an error. Closing it cancels the action on the desktop.
    func deskForgeApprovalStream(_ path: String, json: [String: Any]?) async throws -> URLSession.AsyncBytes {
        var request = try urlRequest("POST", path)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 200
        if let json {
            guard JSONSerialization.isValidJSONObject(json) else { throw APIError.unreadable("request") }
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (bytes, response) = try await DeskForgeWire.streamSession.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // A refusal is a small JSON body, not a stream: read it for its sentence.
                var body = Data()
                for try await byte in bytes {
                    body.append(byte)
                    if body.count > 65_536 { break }
                }
                try APIClient.check(response, body: body)
            }
            try APIClient.check(response, body: Data())
            return bytes
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError.from(error)
        }
    }

    /// POST /api/forge/sessions/{id}/app/start: starts the project's saved app command.
    func deskForgeAppStart(_ sessionID: String) async throws -> URLSession.AsyncBytes {
        try await deskForgeApprovalStream("/api/forge/sessions/" + DeskForgeWire.pathID(sessionID) + "/app/start", json: nil)
    }

    /// POST /api/forge/sessions/{id}/end with "merge": merges the branch back, then ends the session.
    func deskForgeEndWithMerge(_ sessionID: String) async throws -> URLSession.AsyncBytes {
        try await deskForgeApprovalStream("/api/forge/sessions/" + DeskForgeWire.pathID(sessionID) + "/end",
                                          json: ["option": "merge", "confirmed": true])
    }
}

// MARK: - Samples

/// A sample answer for every Forge route the phone reads, shaped like the desktop's own (made-up content).
nonisolated enum DeskForgeSamples {

    static let projects = #"""
    [
      {"id": "3f2a9c1b7d04", "name": "shop-site", "path": "/home/example/projects/shop-site", "added_at": 1793000000.5,
       "last_opened_at": 1793100000.25, "app_command": "npm run dev -- --host 127.0.0.1 --port {port}",
       "app_command_hash": "ab12",
       "git": {"state": "ok", "head": "9f1c2ab", "branch": "main",
               "last_commit": {"sha": "9f1c2ab", "at": 1793090000, "subject": "Stack the product grid"},
               "activity": [{"date": "2026-11-12", "commits": 2, "added": 40, "removed": 6},
                            {"date": "2026-11-13", "commits": 0, "added": 0, "removed": 0}],
               "lifespan": {"commits": 214, "contributors": 3, "first_commit": 1779000000, "last_commit": 1793090000,
                            "added": 18420, "removed": 6310, "age_days": 162,
                            "delta": {"commits": 18, "contributors": 1, "added": 1240, "removed": -220, "age_days": 30},
                            "bucket": "weekly", "buckets": [{"date": "2026-11-02", "commits": 9}, {"date": "2026-11-09", "commits": 12}]},
               "languages": [{"name": ".ts", "bytes": 48200}, {"name": ".css", "bytes": 21600}, {"name": "Other", "bytes": 900}],
               "rhythm": [[0,0,0,0,0,0,0,0,0,1,2,3,1,0,2,4,1,0,0,0,0,0,0,0],
                          [0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0],
                          [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                          [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                          [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                          [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                          [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]],
               "hotspots": [{"path": "src/styles/layout.css", "commits": 31, "added": 820, "removed": 410}],
               "contributors": [{"name": "Alex Example", "commits": 120, "added": 9800, "removed": 3200}]}},
      {"id": "8e41b0c2a9f7", "name": "recipe-notes", "path": "/home/example/projects/recipe-notes", "added_at": 1792900000,
       "last_opened_at": null, "git": {"state": "not_git", "message": "Not a git repository"}},
      {"id": "c07d5e3a1b62", "name": "inventory-api", "path": "/home/example/projects/inventory-api", "added_at": 1792800000,
       "last_opened_at": null, "git": {"state": 7}},
      {"name": "A project with no id"}
    ]
    """#

    static let branches = #"""
    [{"name": "main", "worktree": "/home/example/projects/shop-site"},
     {"name": "forge/mobile-layout-a1b2c3", "worktree": null},
     {"worktree": "/home/example/x"}]
    """#

    static let activity = #"""
    {"days": [{"date": "2026-11-12", "commits": 2, "added": 40, "removed": 6}, {"date": "2026-11-13", "commits": 1, "added": 3, "removed": 0}],
     "projects": [{"id": "3f2a9c1b7d04", "name": "shop-site", "state": "ok", "message": null}],
     "working": [{"id": "5b9e2f0a4c18", "title": "Mobile layout prototype", "project_name": "shop-site"}]}
    """#

    static let sessionRows = #"""
    [
      {"id": "5b9e2f0a4c18", "title": "Mobile layout prototype", "starred": false, "created_at": 1793100000.5,
       "updated_at": 1793100600.0, "message_count": 4, "model_endpoint_id": "ep_claude", "project_id": null,
       "open_mic": false, "agent_id": null, "is_forge": true, "launch_dir": null, "thread": null,
       "forge": {"project_id": "3f2a9c1b7d04", "worktree": "/home/example/Kairos Projects/.worktrees/shop-site-3f2a9c1b7d04/mobile-layout-a1b2c3",
                 "branch": "forge/mobile-layout-a1b2c3", "base_branch": "main", "base_commit": "9f1c2ab", "mode": "build",
                 "isolation": "new_worktree", "forge_root": "/home/example/Kairos Projects"},
       "workspace_dir": "/home/example/Kairos Projects/.worktrees/shop-site-3f2a9c1b7d04/mobile-layout-a1b2c3"},
      {"id": "a1b2c3d4e5f6", "title": "Fix the checkout total", "created_at": 1792800000, "updated_at": 1792800900,
       "message_count": 2, "model_endpoint_id": null,
       "forge": {"project_id": "3f2a9c1b7d04", "worktree": "/home/example/projects/shop-site", "branch": "main",
                 "base_branch": "main", "base_commit": "9f1c2ab", "mode": "plan", "isolation": "in_place", "removed": true},
       "workspace_dir": "/home/example/projects/shop-site"},
      {"title": "A session with no id"}
    ]
    """#

    static let session = #"""
    {"id": "5b9e2f0a4c18", "title": "Mobile layout prototype", "owner_user": "alex", "starred": false,
     "created_at": 1793100000.5, "updated_at": 1793100600.0,
     "messages": [
       {"role": "user", "content": "Make the shop pages work on phones.", "ts": 1793100001.0},
       {"role": "assistant", "content": "The page grid now stacks under 900 pixels.", "ts": 1793100190.0, "status": "complete", "run_id": "r_111"},
       {"role": "user", "content": "Remove the old hero image.", "ts": 1793100400.0},
       {"role": "assistant", "content": "", "ts": 1793100420.0, "status": "stopped", "run_id": "r_112"},
       17
     ],
     "model_endpoint_id": "ep_claude", "model_override": "claude-example-1", "model_effort": "high",
     "permission_mode": "base",
     "workspace_dir": "/home/example/Kairos Projects/.worktrees/shop-site-3f2a9c1b7d04/mobile-layout-a1b2c3",
     "forge": {"project_id": "3f2a9c1b7d04", "worktree": "/home/example/Kairos Projects/.worktrees/shop-site-3f2a9c1b7d04/mobile-layout-a1b2c3",
               "branch": "forge/mobile-layout-a1b2c3", "base_branch": "main", "base_commit": "9f1c2ab", "mode": "build",
               "isolation": "new_worktree"},
     "enabled_integration_ids": null}
    """#

    static let ended = #"""
    {"ok": true, "branch": "forge/mobile-layout-a1b2c3", "kept_project_folder": false,
     "warning": "Worktree removed, but the branch was kept. The branch is not fully merged."}
    """#

    static let checkpoints = #"""
    [
      {"id": "c1", "created": 1793100010.0, "finished": 1793100180.0, "source": "chat:5b9e2f0a4c18", "status": "changed",
       "overlap": false,
       "roots": [{"path": "/home/example/Kairos Projects/.worktrees/shop-site-3f2a9c1b7d04/mobile-layout-a1b2c3",
                  "changes": [{"path": "src/styles/layout.css", "before": "aa", "after": "bb"},
                              {"path": "src/components/NavBar.tsx", "before": null, "after": "cc", "restored_at": 1793100300.0}],
                  "skipped": []}]},
      {"id": "c2", "created": 1793100405.0, "finished": null, "source": "chat:5b9e2f0a4c18", "status": "running",
       "overlap": false, "roots": []},
      {"created": 5}
    ]
    """#

    static let undone = #"""
    {"restored": [{"root": "/home/example/x", "path": "src/styles/layout.css"}]}
    """#

    static let runs = #"""
    [
      {"id": "r_112", "parent_id": null, "surface": "chat", "session_id": "5b9e2f0a4c18", "started_at": 1793100401.0,
       "ended_at": 1793100421.0, "outcome": "stopped", "tool_calls": 1, "label": "Mobile layout prototype", "tokens_per_second": null},
      {"id": "r_111", "surface": "chat", "session_id": "5b9e2f0a4c18", "started_at": 1793100002.0, "ended_at": 1793100191.0,
       "outcome": "finished", "tool_calls": 3, "label": "Mobile layout prototype", "tokens_per_second": 41.5},
      {"surface": "helper"}
    ]
    """#

    static let run = #"""
    {"id": "r_111", "surface": "chat", "started_at": 1793100002.0, "ended_at": 1793100191.0, "outcome": "finished",
     "steps": [
       {"at": 1793100005.0, "kind": "tool_started", "name": "Read", "ok": null, "detail": "{\"file_path\": \"src/styles/layout.css\"}", "seconds": null},
       {"at": 1793100006.0, "kind": "tool_finished", "name": "Read", "ok": true, "detail": ".page { display: grid; }", "seconds": 0.4},
       {"at": 1793100020.0, "kind": "tool_started", "name": "Bash", "ok": null, "detail": "{\"command\": \"npm run lint\"}", "seconds": null},
       {"at": 1793100031.0, "kind": "tool_finished", "name": "Bash", "ok": false, "detail": "1 problem found", "seconds": 11.0},
       {"at": 1793100040.0, "kind": "note", "name": null, "ok": null, "detail": "", "seconds": null},
       "odd"
     ],
     "parent": null, "children": [], "helpers": [], "task_run": null}
    """#

    static let appStatus = #"""
    {"session_id": "5b9e2f0a4c18", "project_id": "3f2a9c1b7d04", "command": "npm run dev -- --host 127.0.0.1 --port 51734",
     "running": true, "ready": true, "port": 51734, "ports": [51734], "url": "http://127.0.0.1:51734/", "exit_code": null,
     "started_at": 1793100700.0}
    """#

    static let appsRunning = #"""
    [{"session_id": "5b9e2f0a4c18", "project_id": "3f2a9c1b7d04", "command": "npm run dev -- --host 127.0.0.1 --port 51734",
      "running": true, "ready": false, "port": 51734, "ports": [51734], "url": "http://127.0.0.1:51734/", "exit_code": null,
      "started_at": 1793100700.0},
     {"session_id": 4}]
    """#

    static let appStopped = #"{"session_id": "5b9e2f0a4c18", "running": false, "ready": false, "ports": []}"#

    static let streamAsk = #"""
    {"permission": {"kind": "permission", "id": "0f9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c", "tool": "forge_app_start",
      "target": "npm run dev -- --host 127.0.0.1 --port 51734", "title": "Run app?",
      "description": "Command: npm run dev -- --host 127.0.0.1 --port 51734\nFolder: /home/example/projects/shop-site",
      "arguments": {"command": "npm run dev -- --host 127.0.0.1 --port 51734", "folder": "/home/example/projects/shop-site",
                    "argv": ["npm", "run", "dev"]},
      "choices": [{"id": "once", "label": "Approve command", "behavior": "allow", "scope": "once"},
                  {"id": "reject", "label": "Cancel", "behavior": "deny", "scope": "once"}],
      "expires_at": 1793100820.0}}
    """#

    static let streamDone = #"{"status": {"session_id": "5b9e2f0a4c18", "running": true, "ready": true, "port": 51734}}"#

    static let streamRefused = #"{"error": "App command was not approved."}"#

    static let noCommits = #"{"detail": "recipe-notes has no commits yet. Make a first commit to start a session."}"#

    static let checks: [DecodeCheck] = [
        DecodeCheck("deskforge.projects") {
            let read = try KJSON.decode(DeskForgeList<DeskForgeProjectDTO>.self, from: DeskForgeSamples.projects)
            guard read.items.count == 3, read.skipped == 1 else { throw SampleMismatch("project rows") }
            let first = read.items[0]
            guard first.appCommand?.contains("{port}") == true, first.git?.state == "ok", first.git?.branch == "main",
                  first.git?.lifespan?.commits == 214, first.git?.lifespan?.delta?.removed == -220,
                  first.git?.rhythm?.count == 7, first.git?.rhythm?.first?.count == 24,
                  first.git?.languages?.count == 3, first.git?.hotspots?.first?.path == "src/styles/layout.css",
                  first.lastOpenedAt != nil, read.items[1].lastOpenedAt == nil, read.items[1].git?.state == "not_git",
                  // An odd summary leaves the project in the list with no summary.
                  read.items[2].git == nil, read.items[2].name == "inventory-api" else {
                throw SampleMismatch("project fields")
            }
            return "3 projects, 1 skipped, odd summary kept out"
        },
        DecodeCheck("deskforge.lists") {
            let branches = try KJSON.decode(DeskForgeList<DeskForgeBranchDTO>.self, from: DeskForgeSamples.branches)
            let activity = try KJSON.decode(DeskForgeActivityDTO.self, from: DeskForgeSamples.activity)
            let rows = try KJSON.decode(DeskForgeList<DeskForgeSessionRowDTO>.self, from: DeskForgeSamples.sessionRows)
            guard branches.items.count == 2, branches.skipped == 1, branches.items[0].worktree != nil,
                  branches.items[1].worktree == nil,
                  activity.days?.count == 2, activity.working?.first?.projectName == "shop-site",
                  rows.items.count == 2, rows.skipped == 1,
                  rows.items[0].forge?.isolation == "new_worktree", rows.items[0].forge?.removed == nil,
                  rows.items[0].forge?.projectId == "3f2a9c1b7d04", rows.items[0].modelEndpointId == "ep_claude",
                  rows.items[1].forge?.removed == true, rows.items[1].forge?.mode == "plan" else {
                throw SampleMismatch("list fields")
            }
            return "branches, activity, session rows"
        },
        DecodeCheck("deskforge.session") {
            let read = try KJSON.decode(DeskForgeSessionDTO.self, from: DeskForgeSamples.session)
            let turns = DeskForgeLive.turns(read.messages?.items ?? [], modelName: "Example")
            let done = try KJSON.decode(DeskForgeEndDTO.self, from: DeskForgeSamples.ended)
            let refused = try KJSON.decode(APIErrorBody.self, from: DeskForgeSamples.noCommits)
            guard read.messages?.items.count == 4, read.messages?.skipped == 1, read.permissionMode == "base",
                  read.modelOverride == "claude-example-1", read.modelEffort == "high",
                  read.forge?.baseBranch == "main",
                  turns.count == 2, turns[0].runID == "r_111", turns[0].failure == nil,
                  turns[1].reply.isEmpty, turns[1].failure != nil,
                  done.ok == true, done.warning != nil, done.keptProjectFolder == false,
                  refused.text.hasSuffix("Make a first commit to start a session.") else {
                throw SampleMismatch("session fields")
            }
            return "4 messages, 1 skipped, 2 turns, ended"
        },
        DecodeCheck("deskforge.review") {
            let points = try KJSON.decode(DeskForgeList<DeskForgeCheckpointDTO>.self, from: DeskForgeSamples.checkpoints)
            let undone = try KJSON.decode(DeskForgeUndoDTO.self, from: DeskForgeSamples.undone)
            let rows = try KJSON.decode(DeskForgeList<DeskForgeRunRowDTO>.self, from: DeskForgeSamples.runs)
            let run = try KJSON.decode(DeskForgeRunDTO.self, from: DeskForgeSamples.run)
            let steps = DeskForgeLive.steps(saved: run.steps?.items ?? [])
            let times = DeskForgeLive.runTimes(rows.items)
            let mine = DeskForgeLive.checkpoints(points.items)
            guard points.items.count == 2, points.skipped == 1, undone.restored?.count == 1,
                  rows.items.count == 2, rows.skipped == 1, run.steps?.items.count == 5, run.steps?.skipped == 1,
                  steps.count == 2, steps[0].summary == "src/styles/layout.css", steps[0].done, !steps[0].failed,
                  steps[1].summary == "npm run lint", steps[1].failed, steps[1].output == "1 problem found",
                  mine.count == 2, mine[0].files.count == 2, mine[0].restored == 1, mine[0].changed, !mine[1].changed,
                  // The first turn's run holds the first checkpoint; the stopped turn's run holds none that finished.
                  DeskForgeLive.checkpoint(for: "r_111", times: times, in: mine)?.id == "c1",
                  DeskForgeLive.checkpoint(for: "r_112", times: times, in: mine) == nil,
                  DeskForgeWire.target("not json at all") == "not json at all",
                  DeskForgeWire.target(#"{"other": 1}"#).isEmpty,
                  DeskForgeWire.stepKind("mcp__files__write_file") == "edit", DeskForgeWire.stepKind("Grep") == "search",
                  (try? DeskForgeWire.pathID("5b9e2f0a4c18")) != nil, (try? DeskForgeWire.pathID("../x")) == nil else {
                throw SampleMismatch("review fields")
            }
            return "checkpoints, runs, steps, turn match"
        },
        DecodeCheck("deskforge.apps") {
            let one = try KJSON.decode(DeskForgeAppDTO.self, from: DeskForgeSamples.appStatus)
            let list = try KJSON.decode(DeskForgeList<DeskForgeAppDTO>.self, from: DeskForgeSamples.appsRunning)
            let stopped = try KJSON.decode(DeskForgeAppDTO.self, from: DeskForgeSamples.appStopped)
            let ask = try KJSON.decode(DeskForgeStreamPacketDTO.self, from: DeskForgeSamples.streamAsk)
            let done = try KJSON.decode(DeskForgeStreamPacketDTO.self, from: DeskForgeSamples.streamDone)
            let refused = try KJSON.decode(DeskForgeStreamPacketDTO.self, from: DeskForgeSamples.streamRefused)
            guard one.running == true, one.ready == true, one.port == 51734, one.sessionId == "5b9e2f0a4c18",
                  list.items.count == 1, list.skipped == 1, stopped.running == false, stopped.port == nil,
                  ask.permission?.tool == "forge_app_start", ask.permission?.target?.hasPrefix("npm run dev") == true,
                  ask.permission?.choices?.count == 2, !ask.finished, ask.error == nil,
                  DeskForgeLive.onceChoice(ask.permission, allow: true) == "once",
                  DeskForgeLive.onceChoice(ask.permission, allow: false) == "reject",
                  done.finished, done.permission == nil, !refused.finished, refused.error == "App command was not approved." else {
                throw SampleMismatch("app fields")
            }
            return "status, running list, approval stream"
        },
    ]
}
