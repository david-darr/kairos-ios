import Foundation

// The desktop's chat routes, as the phone reads them. Every shape was read from the desktop source;
// the Python file and function are named on each type. Times on these routes are epoch seconds.

// MARK: - Conversations

/// One row of GET /api/sessions (core/session_manager_store.py: list_sessions). No message bodies.
nonisolated struct ChatSessionRowDTO: Decodable, Hashable, Sendable {
    var id: String
    var title: String?
    var starred: Bool?
    var createdAt: Double?
    var updatedAt: Double?
    var messageCount: Int?
    var modelEndpointId: String?
    var projectId: String?
    var openMic: Bool?
    /// Set on a bot's conversation. GET /api/sessions leaves those out unless asked.
    var agentId: String?
    var isForge: Bool?
    var launchDir: String?
    var thread: BotThreadMetaDTO?
}

/// A file sent with a message (services/chat_service.py: _user_message_extra).
nonisolated struct ChatAttachmentDTO: Decodable, Hashable, Sendable {
    var id: String?
    var filename: String?
    var size: Double?
    /// "/chat-files/<id>" once the message is saved.
    var url: String?
}

/// One saved message (core/session_manager.py: _append_message, plus what a turn adds to it).
nonisolated struct ChatMessageDTO: Decodable, Hashable, Sendable {
    /// "user" or "assistant".
    var role: String?
    var content: String?
    var ts: Double?
    /// "complete", "failed", "interrupted" or "stopped".
    var status: String?
    var attachments: [ChatAttachmentDTO]?
    var imageAttachmentIds: [String]?
    var references: [JSONValue]?
    var runId: String?
    /// "rate_limited", "request_error" or "model_error" on a failed reply.
    var failureKind: String?
    var failureModelName: String?
    var failureModelEndpointId: String?
    var failureHadTools: Bool?
    var backgroundFollowup: JSONValue?
    var callSummaryId: String?
    var displayOnly: Bool?
    var kind: String?
    var botCreated: JSONValue?
}

/// `context_state` on a session and GET /api/sessions/{id}/context (core/token_usage.py: context_state).
nonisolated struct ChatContextDTO: Decodable, Hashable, Sendable {
    /// Only on the /context route. false means no reading yet.
    var available: Bool?
    var usedTokens: Double?
    var capacityTokens: Double?
    var percent: Double?
    var estimatedCapacity: Bool?
    var capacitySource: String?
    var model: String?
    var parts: [ChatContextPartDTO]?
}

/// One part of the context bar (core/context_breakdown.py).
nonisolated struct ChatContextPartDTO: Decodable, Hashable, Sendable {
    var key: String?
    var label: String?
    var tokens: Double?
    var estimated: Bool?
}

/// GET /api/sessions/{id} (routes/session_routes.py: get_session over core/session_manager.py: create_session).
nonisolated struct ChatSessionDTO: Decodable, Hashable, Sendable {
    var id: String
    var title: String?
    var starred: Bool?
    var createdAt: Double?
    var updatedAt: Double?
    var messages: [ChatMessageDTO]?
    var modelEndpointId: String?
    var modelOverride: String?
    var modelEffort: String?
    /// "base" (ask first) or "auto" (full access, admins only).
    var permissionMode: String?
    var workspaceDir: String?
    var projectId: String?
    var agentId: String?
    var forge: JSONValue?
    var openMic: Bool?
    var contextState: ChatContextDTO?
    var compactions: [JSONValue]?
}

/// POST /api/sessions/{id}/fork (routes/session_routes.py: fork_session).
nonisolated struct ChatForkDTO: Decodable, Hashable, Sendable {
    var id: String
    var title: String?
    var projectId: String?
}

/// POST /api/sessions/{id}/model (routes/session_routes.py: set_session_model).
nonisolated struct ChatModelSetDTO: Decodable, Hashable, Sendable {
    var ok: Bool?
    var modelEndpointId: String?
    var modelOverride: String?
    var effort: String?
}

/// POST /api/sessions/{id}/permission-mode.
nonisolated struct ChatPermissionModeDTO: Decodable, Hashable, Sendable {
    var mode: String?
}

/// Answers that only say it worked.
nonisolated struct ChatOkDTO: Decodable, Hashable, Sendable {
    var ok: Bool?
}

// MARK: - Live turns

/// One step of a tool the model used: `value` of a tool_step packet and an entry of `toolSteps`
/// (services/chat_service.py: stream_message).
nonisolated struct ChatToolStepDTO: Decodable, Hashable, Sendable {
    /// "started" or "finished".
    var phase: String?
    var id: String?
    var name: String?
    var summary: String?
    var ok: Bool?
    var output: String?
    var at: Double?
    var seconds: Double?
}

/// One answer an approval offers (core/permissions.py).
nonisolated struct ChatPermissionChoiceDTO: Decodable, Hashable, Sendable {
    var id: String?
    var label: String?
    /// "allow" or "deny".
    var behavior: String?
    var scope: String?
}

nonisolated struct ChatQuestionOptionDTO: Decodable, Hashable, Sendable {
    var label: String?
    var description: String?
}

/// One question the model asks (core/permissions.py: normalize_questions). Answers are keyed by `question`.
nonisolated struct ChatQuestionDTO: Decodable, Hashable, Sendable {
    var question: String?
    var header: String?
    var multiSelect: Bool?
    var options: [ChatQuestionOptionDTO]?
}

/// A request waiting on the person: `permission` on a run (core/permissions.py: Request.payload).
nonisolated struct ChatPermissionDTO: Decodable, Hashable, Sendable {
    var id: String?
    /// "permission" (an approval) or "question".
    var kind: String?
    var tool: String?
    var target: String?
    var title: String?
    var description: String?
    var arguments: JSONValue?
    var choices: [ChatPermissionChoiceDTO]?
    var questions: [ChatQuestionDTO]?
    var expiresAt: Double?
}

/// A server-owned turn (services/chat_live.py: start, _visible).
nonisolated struct ChatRunDTO: Decodable, Hashable, Sendable {
    var turnId: String?
    var sessionTitle: String?
    var prompt: String?
    var text: String?
    var startedAt: Double?
    /// "processing", "done", "failed" or "stopped".
    var status: String?
    var stopping: Bool?
    var permission: ChatPermissionDTO?
    var toolSteps: [ChatToolStepDTO]?
    var toolEvents: [JSONValue]?
    var handoffs: JSONValue?
    var runId: String?
    var error: String?
    var revision: Int?
    var provider: String?
    var waitingSince: Double?
    var providerDetail: String?
}

/// `changes` of an update packet (services/chat_live.py: _update): only the fields that changed.
/// A field sent as null (a request that closed, an error cleared) is different from a field left out,
/// so each one records whether it was present.
nonisolated struct ChatRunChangesDTO: Decodable, Hashable, Sendable {
    var status: String?
    var stopping: Bool?
    var hasPermission = false
    var permission: ChatPermissionDTO?
    var hasError = false
    var error: String?
    var runId: String?
    var hasProviderDetail = false
    var providerDetail: String?
    var hasWaitingSince = false
    var waitingSince: Double?

    private enum CodingKeys: String, CodingKey {
        case status, stopping, permission, error, runId, providerDetail, waitingSince
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        stopping = try container.decodeIfPresent(Bool.self, forKey: .stopping)
        hasPermission = container.contains(.permission)
        permission = try container.decodeIfPresent(ChatPermissionDTO.self, forKey: .permission)
        hasError = container.contains(.error)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        runId = try container.decodeIfPresent(String.self, forKey: .runId)
        hasProviderDetail = container.contains(.providerDetail)
        providerDetail = try container.decodeIfPresent(String.self, forKey: .providerDetail)
        hasWaitingSince = container.contains(.waitingSince)
        waitingSince = try container.decodeIfPresent(Double.self, forKey: .waitingSince)
    }
}

/// One item of background work in a chat (services/background_tasks.py: list_items).
nonisolated struct ChatBackgroundItemDTO: Decodable, Hashable, Sendable {
    var id: String
    /// "subagent", "command", "agent", "helper", "computer", "app_server", "scheduled" or "task".
    var kind: String?
    var source: String?
    var label: String?
    /// "running", "queued", "waiting", "scheduled", "done", "failed" or "stopped".
    var status: String?
    var activity: String?
    var startedAt: Double?
    var endedAt: Double?
    var detail: String?
}

/// GET /api/chat/background/{session_id} (routes/background_task_routes.py).
nonisolated struct ChatBackgroundDTO: Decodable, Hashable, Sendable {
    var items: [ChatBackgroundItemDTO]?
    var notes: [JSONValue]?
}

/// One packet of GET /api/chat/live/events (services/chat_live.py), as one loose shape. Read `type`:
/// - "snapshot": runs (session id to run)
/// - "started": sessionId, run
/// - "chunk": sessionId, turnId, revision, chunk
/// - "update": sessionId, turnId, revision, changes
/// - "tool_step": sessionId, turnId, revision, value
/// - "tool_event": sessionId, turnId, revision, value (free-form)
/// - "heartbeat"
/// - "bg_tasks": sessionId, items, notes
/// - "bg_followup": sessionId, message
/// - "design_changed": designId
/// Bot packets ("bot_queue", "bot_card" and so on) share the stream; decode those as `BotLivePacketDTO`.
nonisolated struct ChatLivePacketDTO: Decodable, Sendable {
    var type: String
    var sessionId: String?
    var turnId: String?
    var revision: Int?
    var chunk: String?
    var run: ChatRunDTO?
    var runs: [String: ChatRunDTO]?
    var changes: ChatRunChangesDTO?
    var step: ChatToolStepDTO?
    var items: [ChatBackgroundItemDTO]?
    var message: ChatMessageDTO?
    var designId: String?

    private enum CodingKeys: String, CodingKey {
        case type, sessionId, turnId, revision, chunk, run, runs, changes, value, items, message, designId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        sessionId = try? container.decodeIfPresent(String.self, forKey: .sessionId)
        turnId = try? container.decodeIfPresent(String.self, forKey: .turnId)
        revision = try? container.decodeIfPresent(Int.self, forKey: .revision)
        chunk = try? container.decodeIfPresent(String.self, forKey: .chunk)
        // Only read each body for the packet types that carry it, so a bot packet with its own
        // `items` or `message` shape never fails here.
        switch type {
        case "snapshot":
            runs = try container.decodeIfPresent([String: ChatRunDTO].self, forKey: .runs)
        case "started":
            run = try container.decodeIfPresent(ChatRunDTO.self, forKey: .run)
        case "update":
            changes = try container.decodeIfPresent(ChatRunChangesDTO.self, forKey: .changes)
        case "tool_step":
            step = try container.decodeIfPresent(ChatToolStepDTO.self, forKey: .value)
        case "bg_tasks":
            items = try container.decodeIfPresent([ChatBackgroundItemDTO].self, forKey: .items)
        case "bg_followup":
            message = try container.decodeIfPresent(ChatMessageDTO.self, forKey: .message)
        case "design_changed":
            designId = try? container.decodeIfPresent(String.self, forKey: .designId)
        default:
            break
        }
    }
}

/// POST /api/chat/live (routes/chat_routes.py: start_live_chat). A bot's conversation also answers
/// `queued`, `queueId`, `reason` and `messageId`.
nonisolated struct ChatStartDTO: Decodable, Hashable, Sendable {
    var turnId: String?
    var queued: Bool?
    var queueId: String?
    var reason: String?
    var messageId: String?
}

/// POST /api/chat/live/stop.
nonisolated struct ChatStopDTO: Decodable, Hashable, Sendable {
    var stopping: Bool?
}

/// POST /api/permissions/{id}/answer and /respond.
nonisolated struct ChatPermissionResultDTO: Decodable, Hashable, Sendable {
    /// "answered" or "skipped".
    var status: String?
}

// MARK: - Models

/// One row of GET /api/models/choices (routes/model_routes.py: model_choices).
nonisolated struct ModelChoiceDTO: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String?
    var model: String?
    /// "local", "api", "claude_cli", "codex_cli" or "antigravity_cli".
    var kind: String?
    var supportsImages: Bool?
    var mark: String?
}

nonisolated struct ModelEffortDTO: Decodable, Hashable, Sendable {
    var effort: String?
    var description: String?
}

/// One row of GET /api/models/{endpoint_id}/catalog (core/model_catalog.py, core/model_discovery.py).
nonisolated struct ModelCatalogEntryDTO: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var displayName: String?
    var description: String?
    var defaultEffort: String?
    var supportedEfforts: [ModelEffortDTO]?
    var contextWindow: Double?
    var estimated: Bool?
}

// MARK: - Usage and files

nonisolated struct ChatUsageModelDTO: Decodable, Hashable, Sendable {
    var model: String?
    var provider: String?
    var kind: String?
    var contextWindow: Double?
    var contextWindowEstimated: Bool?
}

nonisolated struct ChatLastReplyDTO: Decodable, Hashable, Sendable {
    var runId: String?
    var model: String?
    var ttftSeconds: Double?
    var tokensPerSecond: Double?
    var outputTokens: Double?
}

/// GET /api/sessions/{id}/usage (core/session_usage.py: summarize, plus `context` and `model`).
/// A figure the provider did not report is null, never 0.
nonisolated struct ChatUsageDTO: Decodable, Hashable, Sendable {
    var sessionId: String?
    var turns: Int?
    var runs: Int?
    var reportedRuns: Int?
    var inputTokens: Double?
    var outputTokens: Double?
    var cacheReadTokens: Double?
    var cacheWriteTokens: Double?
    var totalTokens: Double?
    var toolCalls: Double?
    var cacheHitPercent: Double?
    var failed: Int?
    var stopped: Int?
    var cost: JSONValue?
    var compactions: Int?
    var lastCompaction: JSONValue?
    var helperRuns: Int?
    var sideRuns: Int?
    var sidePurposes: [String: Int]?
    var lastReply: ChatLastReplyDTO?
    var context: ChatContextDTO?
    var model: ChatUsageModelDTO?
}

/// One row of GET /api/chat/files (core/chat_files.py: list_for_session).
nonisolated struct ChatFileDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
    /// "sent", "model" or "generated".
    var origin: String?
    /// "/chat-files/<id>", "/generated-files/<name>" or "/generated-images/<name>".
    var url: String?
    var size: Double?
    var exists: Bool?
    var createdAt: Double?
}

/// GET /api/chat/artifacts (core/chat_artifacts.py: resolve).
nonisolated struct ChatArtifactDTO: Decodable, Hashable, Sendable {
    var filename: String?
    var `extension`: String?
    var size: Double?
    /// "image", "video", "audio", "pdf", "html", "markdown", "text", "office" or "download".
    var kind: String?
}

/// POST /api/chat/attachments (routes/chat_routes.py: upload_attachment).
nonisolated struct ChatUploadDTO: Decodable, Hashable, Sendable {
    var id: String
    var filename: String?
    var size: Double?
    var url: String?
}

/// GET and POST /api/chat/summary (services/chat_summary.py: _state).
nonisolated struct ChatSummaryDTO: Decodable, Hashable, Sendable {
    var summary: String?
    var stale: Bool?
    var messageCount: Int?
    var summarizedCount: Int?
    var createdAt: Double?
}

/// GET /api/projects and POST /api/projects (core/projects.py: create_project).
nonisolated struct ChatProjectDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
    var instructions: String?
    var documentIds: [String]?
    var updatedAt: Double?
}

// MARK: - Routes

/// A text for a JSON body, or JSON null.
nonisolated func jsonOrNull(_ value: String?) -> Any {
    if let value { return value }
    return NSNull()
}

extension APIClient {

    // MARK: Conversations

    /// GET /api/sessions: the person's model chats, starred first, then newest. Bots' conversations are left out.
    func chatSessions() async throws -> [ChatSessionRowDTO] {
        try await get("/api/sessions")
    }

    /// POST /api/sessions: a new chat. A chat named "New Chat" takes its title from the first message.
    func chatCreate(title: String = "New Chat") async throws -> ChatSessionDTO {
        try await post("/api/sessions", json: ["title": title])
    }

    /// GET /api/sessions/{id}: the chat with every message.
    func chatSession(_ id: String) async throws -> ChatSessionDTO {
        try await get("/api/sessions/\(id)")
    }

    func chatRename(_ id: String, title: String) async throws {
        try await call("PATCH", "/api/sessions/\(id)", json: ["title": title])
    }

    /// GET /api/projects: the person's chat projects, by name.
    func chatProjects() async throws -> [ChatProjectDTO] {
        try await get("/api/projects")
    }

    /// POST /api/projects.
    func chatProjectCreate(name: String, instructions: String) async throws -> ChatProjectDTO {
        try await post("/api/projects", json: ["name": name, "instructions": instructions])
    }

    /// POST /api/sessions/{id}/project: put the chat in a project, or nil to take it out.
    func chatSetProject(_ id: String, projectId: String?) async throws {
        try await call("POST", "/api/sessions/\(id)/project", json: ["project_id": jsonOrNull(projectId)])
    }

    func chatStar(_ id: String, starred: Bool) async throws {
        try await call("POST", "/api/sessions/\(id)/star", json: ["starred": starred])
    }

    /// DELETE /api/sessions/{id}. Refused with 409 while a reply runs.
    func chatDelete(_ id: String) async throws {
        try await call("DELETE", "/api/sessions/\(id)")
    }

    /// POST /api/sessions/{id}/fork: a new chat that ends at the message with this index.
    func chatFork(_ id: String, throughIndex: Int) async throws -> ChatForkDTO {
        try await post("/api/sessions/\(id)/fork", json: ["through_index": throughIndex])
    }

    /// POST /api/sessions/{id}/rewind: keep the first `keep` messages and delete the rest (edit and regenerate).
    func chatRewind(_ id: String, keep: Int) async throws -> ChatSessionDTO {
        try await post("/api/sessions/\(id)/rewind", json: ["keep": keep])
    }

    /// POST /api/sessions/{id}/model. `override` nil follows the connection; `effort` nil sends none.
    func chatSetModel(_ id: String, endpointId: String?, override: String?, effort: String?) async throws -> ChatModelSetDTO {
        var body: [String: Any] = [:]
        body["model_endpoint_id"] = jsonOrNull(endpointId)
        body["model_override"] = jsonOrNull(override)
        body["effort"] = jsonOrNull(effort)
        return try await post("/api/sessions/\(id)/model", json: body)
    }

    /// POST /api/sessions/{id}/permission-mode: "base" or "auto". Auto is for admins only (403).
    func chatSetPermissionMode(_ id: String, mode: String) async throws -> ChatPermissionModeDTO {
        try await post("/api/sessions/\(id)/permission-mode", json: ["mode": mode])
    }

    func chatUsage(_ id: String) async throws -> ChatUsageDTO {
        try await get("/api/sessions/\(id)/usage")
    }

    func chatContext(_ id: String) async throws -> ChatContextDTO {
        try await get("/api/sessions/\(id)/context")
    }

    // MARK: Turns

    /// POST /api/chat/live: start a server-owned turn. The same `requestId` sent twice starts it once.
    func chatStart(sessionId: String, message: String, attachmentIds: [String], requestId: String) async throws -> ChatStartDTO {
        try await post("/api/chat/live", json: [
            "session_id": sessionId,
            "message": message,
            "attachment_ids": attachmentIds,
            "references": [[String: Any]](),
            "request_id": requestId,
        ])
    }

    /// POST /api/chat/live/stop. Naming the turn means a late Stop never ends the next one.
    func chatStop(sessionId: String, turnId: String?) async throws -> ChatStopDTO {
        var body: [String: Any] = ["session_id": sessionId]
        if let turnId { body["turn_id"] = turnId }
        return try await post("/api/chat/live/stop", json: body)
    }

    /// GET /api/chat/live/snapshot: every running turn of the person's chats, as one "snapshot" packet.
    func chatSnapshot() async throws -> ChatLivePacketDTO {
        try await get("/api/chat/live/snapshot")
    }

    /// POST /api/chat/compact: summarise older turns. Nothing is deleted.
    func chatCompact(sessionId: String) async throws {
        try await call("POST", "/api/chat/compact", json: ["session_id": sessionId])
    }

    func chatSummary(sessionId: String) async throws -> ChatSummaryDTO {
        try await get("/api/chat/summary", query: ["session_id": sessionId])
    }

    func chatMakeSummary(sessionId: String, force: Bool) async throws -> ChatSummaryDTO {
        try await post("/api/chat/summary", json: ["session_id": sessionId, "force": force])
    }

    func chatBackground(sessionId: String) async throws -> ChatBackgroundDTO {
        try await get("/api/chat/background/\(sessionId)")
    }

    // MARK: Approvals and questions

    /// POST /api/permissions/{id}/answer with one of the request's choice ids. 409 when it is no longer waiting.
    func permissionAnswer(_ requestId: String, choice: String) async throws -> ChatPermissionResultDTO {
        try await post("/api/permissions/\(requestId)/answer", json: ["choice": choice])
    }

    /// POST /api/permissions/{id}/respond: answers keyed by each question's own text, or skip.
    func permissionRespond(_ requestId: String, answers: [String: Any]?, skip: Bool) async throws -> ChatPermissionResultDTO {
        var body: [String: Any] = ["skip": skip]
        if let answers, !skip { body["answers"] = answers }
        return try await post("/api/permissions/\(requestId)/respond", json: body)
    }

    // MARK: Models

    func modelChoices() async throws -> [ModelChoiceDTO] {
        try await get("/api/models/choices")
    }

    /// GET /api/models/{endpoint_id}/catalog: the versions one connection offers. Empty is a normal answer.
    func modelCatalog(endpointId: String) async throws -> [ModelCatalogEntryDTO] {
        try await get("/api/models/\(endpointId)/catalog")
    }

    // MARK: Files

    /// POST /api/chat/attachments (25 MB at most). The id goes in the next message's `attachment_ids`.
    func chatUpload(_ file: OutgoingFile) async throws -> ChatUploadDTO {
        try await upload("/api/chat/attachments", file: file)
    }

    func chatFiles(sessionId: String) async throws -> [ChatFileDTO] {
        try await get("/api/chat/files", query: ["session_id": sessionId])
    }

    func chatArtifact(sessionId: String, url: String) async throws -> ChatArtifactDTO {
        try await get("/api/chat/artifacts", query: ["session_id": sessionId, "url": url])
    }

    /// GET /api/chat/artifacts/content: the file's own bytes. `download` true always sends the original.
    func chatArtifactBytes(sessionId: String, url: String, download: Bool) async throws -> Data {
        try await bytes("/api/chat/artifacts/content", query: [
            "session_id": sessionId,
            "url": url,
            "download": download ? "true" : nil,
        ])
    }
}
