import Foundation

/// Sample answers shaped exactly like the desktop's, for the phone routes, the chat routes and the live
/// stream. Made-up content. `checks` decodes each one through its real decoder; the debug view
/// `chat.decoders` shows the result, because there is no test target.
nonisolated enum ChatSamples {

    // MARK: Phone routes (docs/PHONE-API.md)

    static let pairClaim = #"""
    {
      "token": "kph_sample_not_a_real_token",
      "device_id": "d_3f9c21",
      "account": { "username": "alex", "is_admin": true, "color": "teal" },
      "server": { "name": "Kairos", "version": "2.3.0" }
    }
    """#

    static let pairRefused = #"""
    { "detail": "That code is not right or has expired." }
    """#

    static let badRequest = #"""
    { "detail": [ { "type": "missing", "loc": ["body", "code"], "msg": "Field required" } ] }
    """#

    static let phoneSession = #"""
    { "account": { "username": "alex", "is_admin": true, "color": "teal" }, "device_id": "d_3f9c21", "server": { "name": "Kairos", "version": "2.3.0" } }
    """#

    static let phoneDevices = #"""
    { "devices": [
      { "id": "d_3f9c21", "name": "iPhone", "model": "iPhone17,1", "created_at": "2026-11-12T08:01:00Z", "last_seen_at": "2026-11-12T09:30:12.250Z", "current": true },
      { "id": "d_77aa02", "name": "Old phone", "model": "iPhone15,2", "created_at": "2026-10-01T10:00:00Z", "last_seen_at": null, "current": false }
    ] }
    """#

    static let phoneHome = #"""
    {
      "usage": [
        { "provider": "Claude", "percent": 64, "resets_at": "2026-11-14T15:05:00Z" },
        { "provider": "Codex", "percent": 22.5, "resets_at": null }
      ],
      "next_event": { "title": "Report due", "starts_at": "2026-11-13T17:00:00Z", "all_day": false },
      "needs_you": 2,
      "running": 1
    }
    """#

    static let phoneHomeEmpty = #"""
    { "usage": [], "next_event": null, "needs_you": 0, "running": 0 }
    """#

    static let ringState = #"""
    { "id": "5b1e77c2", "agent_id": "a1b2c3d4", "bot_name": "Kip", "status": "ringing", "seconds_left": 41 }
    """#

    // MARK: Chat routes

    static let sessions = #"""
    [
      { "id": "9f0c1a2b3c4d4e5f8a7b6c5d4e3f2a1b", "title": "Bike shop launch", "starred": true, "created_at": 1794300000.5, "updated_at": 1794386400.25,
        "message_count": 6, "model_endpoint_id": "ep_claude", "project_id": null, "open_mic": false, "agent_id": null, "is_forge": false, "launch_dir": null, "thread": null },
      { "id": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "title": "Check zip tie availability", "starred": false, "created_at": 1794380000.0, "updated_at": 1794390000.0,
        "message_count": 2, "model_endpoint_id": "ep_codex", "project_id": "p_home", "open_mic": false, "agent_id": null, "is_forge": false, "launch_dir": null, "thread": null },
      { "id": "c0ffee00c0ffee00c0ffee00c0ffee00", "title": "Faster image loading", "starred": false, "created_at": 1794200000.0, "updated_at": 1794210000.0,
        "message_count": 14, "model_endpoint_id": "ep_claude", "project_id": null, "open_mic": false, "agent_id": null, "is_forge": true, "launch_dir": null, "thread": null }
    ]
    """#

    static let session = #"""
    {
      "id": "9f0c1a2b3c4d4e5f8a7b6c5d4e3f2a1b", "title": "Bike shop launch", "owner_user": "alex", "starred": true,
      "created_at": 1794300000.5, "updated_at": 1794386400.25,
      "model_endpoint_id": "ep_claude", "model_override": "claude-opus", "model_effort": "high",
      "permission_mode": "base", "workspace_dir": null, "project_id": null, "enabled_integration_ids": null,
      "context_state": { "used_tokens": 79000, "model": "claude-opus", "capacity_tokens": 500000, "percent": 15.8, "estimated_capacity": true,
        "capacity_source": "curated",
        "parts": [ { "key": "system", "label": "Instructions", "tokens": 9000, "estimated": true }, { "key": "messages", "label": "Messages", "tokens": 70000, "estimated": true } ] },
      "messages": [
        { "role": "user", "content": "Find three rivals' prices and write a one-page plan.", "ts": 1794300001.0, "status": "complete",
          "attachments": [ { "id": "a1b2c3d4e5f6", "filename": "shop-photo.jpg", "url": "/chat-files/0123456789abcdef01234567" } ],
          "image_attachment_ids": ["a1b2c3d4e5f6"] },
        { "role": "assistant", "content": "I found three rival price lists and wrote the plan.\n\n[Launch plan.docx](/generated-files/1a2b3c4d5e6f_Launch%20plan.docx)\n\n![Booking page](/generated-images/0f0e0d0c0b0a_booking-page.png)\n\nSources: [Tune-up prices](https://cyclerepair.example/prices)",
          "ts": 1794300090.0, "status": "complete", "run_id": "run_77" },
        { "role": "user", "content": "Make it shorter.", "ts": 1794300200.0, "status": "complete" },
        { "role": "assistant", "content": "", "ts": 1794300210.0, "status": "failed", "failure_kind": "rate_limited", "failure_model_name": "Claude Opus", "failure_had_tools": false }
      ]
    }
    """#

    static let fork = #"""
    { "id": "feedbeef00112233445566778899aabb", "title": "Bike shop launch (fork)", "project_id": null }
    """#

    static let modelSet = #"""
    { "ok": true, "model_endpoint_id": "ep_claude", "model_override": null, "effort": "high" }
    """#

    static let start = #"""
    { "turn_id": "7d6c5b4a39281706f5e4d3c2b1a09f8e" }
    """#

    static let stop = #"""
    { "stopping": true }
    """#

    static let modelChoices = #"""
    [
      { "id": "ep_claude", "name": "Claude subscription", "model": "", "kind": "claude_cli", "supports_images": true, "mark": "claude" },
      { "id": "ep_codex", "name": "Codex", "model": "", "kind": "codex_cli", "supports_images": true, "mark": "openai" },
      { "id": "ep_local", "name": "This PC", "model": "qwen3:14b", "kind": "local", "supports_images": false, "mark": null }
    ]
    """#

    static let modelCatalog = #"""
    [
      { "id": "claude-opus", "display_name": "Claude Opus", "description": "Most capable", "alias": "opus", "default_effort": null,
        "supported_efforts": [ { "effort": "low", "description": "Quick" }, { "effort": "medium", "description": "" }, { "effort": "high", "description": "Thorough" } ],
        "context_window": 500000, "effective_context_percent": null, "source": "curated", "estimated": true },
      { "id": "claude-sonnet", "display_name": "Claude Sonnet", "description": "Fast", "alias": "sonnet", "default_effort": null,
        "supported_efforts": [], "context_window": 200000, "effective_context_percent": null, "source": "curated", "estimated": true }
    ]
    """#

    static let usage = #"""
    {
      "session_id": "9f0c1a2b3c4d4e5f8a7b6c5d4e3f2a1b", "source": "runs", "turns": 3, "runs": 5, "reported_runs": 3,
      "input_tokens": 182000, "output_tokens": 6400, "cache_read_tokens": 150000, "cache_write_tokens": 21000, "total_tokens": 188400,
      "tool_calls": 7, "cache_hit_percent": 82.4, "failed": 1, "stopped": 0,
      "cost": { "amount": 0.0123, "kind": "estimated", "unpriced_runs": 0 },
      "compactions": 0, "last_compaction": null, "helper_runs": 1, "side_runs": 1, "side_purposes": { "chat_summary": 1 },
      "parts": { "turns": { "runs": 3 }, "side": { "runs": 1 }, "helpers": { "runs": 1 }, "other": { "runs": 0 } },
      "last_reply": { "run_id": "run_77", "model": "claude-opus", "endpoint_id": "ep_claude", "ttft_seconds": 0.62, "tokens_per_second": 48.1, "output_tokens": 2100, "ended_at": 1794300090.0 },
      "first_run_at": 1794300001.0, "last_run_at": 1794300210.0,
      "context": { "used_tokens": 79000, "model": "claude-opus", "capacity_tokens": 500000, "percent": 15.8, "estimated_capacity": true,
        "parts": [ { "key": "system", "label": "Instructions", "tokens": 9000, "estimated": true }, { "key": "messages", "label": "Messages", "tokens": 70000, "estimated": true } ] },
      "model": { "model": "claude-opus", "provider": "Claude subscription", "kind": "claude_cli", "context_window": 500000, "context_window_estimated": true }
    }
    """#

    static let usageEmpty = #"""
    {
      "session_id": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "source": "runs", "turns": 0, "runs": 0, "reported_runs": 0,
      "input_tokens": null, "output_tokens": null, "cache_read_tokens": null, "cache_write_tokens": null, "total_tokens": null,
      "tool_calls": 0, "cache_hit_percent": null, "failed": 0, "stopped": 0, "cost": null,
      "compactions": 0, "last_compaction": null, "helper_runs": 0, "side_runs": 0, "side_purposes": {},
      "parts": {}, "last_reply": null, "first_run_at": null, "last_run_at": null, "context": null,
      "model": { "model": null, "provider": null, "kind": null, "context_window": null, "context_window_estimated": false }
    }
    """#

    static let context = #"""
    { "available": false }
    """#

    static let files = #"""
    [
      { "id": "0123456789abcdef01234567", "name": "shop-photo.jpg", "origin": "sent", "url": "/chat-files/0123456789abcdef01234567", "size": 906000, "exists": true, "created_at": 1794300001.0 },
      { "id": "aa11bb22cc33dd44ee55ff66", "name": "1a2b3c4d5e6f_Launch plan.docx", "origin": "generated", "url": "/generated-files/1a2b3c4d5e6f_Launch%20plan.docx", "size": 22000, "exists": true, "created_at": 1794386400.25 },
      { "id": "ffeeddccbbaa998877665544", "name": "old-notes.txt", "origin": "generated", "url": "/generated-files/9a8b7c6d5e4f_old-notes.txt", "size": null, "exists": false, "created_at": 1794386400.25 }
    ]
    """#

    static let artifact = #"""
    { "filename": "Launch plan.docx", "extension": "docx", "size": 22000, "kind": "office" }
    """#

    static let upload = #"""
    { "id": "a1b2c3d4e5f6", "filename": "shop-photo.jpg", "size": 906000, "url": "/chat-files/0123456789abcdef01234567" }
    """#

    static let summary = #"""
    { "summary": "Prices for three rivals were found and a one-page launch plan was written.", "stale": false, "message_count": 4, "summarized_count": 4, "created_at": 1794300300.0 }
    """#

    static let background = #"""
    {
      "items": [
        { "id": "helper:run_81", "kind": "subagent", "source": "kairos", "label": "Writing the one-page plan", "status": "running", "activity": "Drafting section 2", "startedAt": 1794300100.0, "endedAt": null, "detail": "result" },
        { "id": "command:17", "kind": "command", "source": "kairos", "label": "Export the price table", "status": "done", "activity": "", "startedAt": 1794300050.0, "endedAt": 1794300061.5, "detail": "result" }
      ],
      "notes": [ { "id": "command:17", "at": 1794300061.5, "text": "Background command finished: Export the price table" } ]
    }
    """#

    static let permissionResult = #"""
    { "status": "answered" }
    """#

    // MARK: The live stream (one JSON object per `data:` line)

    static let packetSnapshot = #"""
    { "type": "snapshot", "runs": {
        "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6": {
          "turnId": "7d6c5b4a39281706f5e4d3c2b1a09f8e", "sessionTitle": "Check zip tie availability",
          "prompt": "Find 8 inch black zip ties in stock near me today.", "text": "Two stores have them", "startedAt": 1794390000.0,
          "status": "processing", "stopping": false, "permission": null, "toolEvents": [],
          "toolSteps": [
            { "phase": "started", "id": "call_1", "name": "web_search", "summary": "Searched the first hardware store", "ok": true, "output": "", "at": 1794390002.0, "seconds": null },
            { "phase": "finished", "id": "call_1", "name": "web_search", "summary": "Searched the first hardware store", "ok": true, "output": "3 results", "at": 1794390004.5, "seconds": 2.5 }
          ],
          "handoffs": null, "runId": "run_90", "error": null, "revision": 9, "provider": "Codex", "waitingSince": null, "providerDetail": null
        }
    } }
    """#

    static let packetStarted = #"""
    { "type": "started", "sessionId": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "run": {
        "turnId": "7d6c5b4a39281706f5e4d3c2b1a09f8e", "sessionTitle": "Check zip tie availability", "prompt": "Find 8 inch black zip ties in stock near me today.",
        "text": "", "startedAt": 1794390000.0, "status": "processing", "stopping": false, "permission": null, "toolEvents": [], "toolSteps": [],
        "handoffs": null, "runId": null, "error": null, "revision": 1, "provider": "Codex", "waitingSince": 1794390000.0, "providerDetail": null } }
    """#

    static let packetChunk = #"""
    { "type": "chunk", "sessionId": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "turnId": "7d6c5b4a39281706f5e4d3c2b1a09f8e", "revision": 10, "chunk": " within 5 miles." }
    """#

    static let packetToolStep = #"""
    { "type": "tool_step", "sessionId": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "turnId": "7d6c5b4a39281706f5e4d3c2b1a09f8e", "revision": 11,
      "value": { "phase": "started", "id": "call_2", "name": "web_search", "summary": "Checking the corner shop", "ok": null, "output": "", "at": 1794390006.0, "seconds": null } }
    """#

    static let packetToolEvent = #"""
    { "type": "tool_event", "sessionId": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "turnId": "7d6c5b4a39281706f5e4d3c2b1a09f8e", "revision": 12,
      "value": { "kind": "computer", "action": "open", "url": "https://cyclerepair.example" } }
    """#

    static let packetApproval = #"""
    { "type": "update", "sessionId": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "turnId": "7d6c5b4a39281706f5e4d3c2b1a09f8e", "revision": 13,
      "changes": { "permission": {
        "kind": "permission", "id": "req_approve_1", "tool": "shell", "target": "npm run build", "title": "Run a command",
        "description": "Kairos wants to run a command in the shop-site folder.", "arguments": { "command": "npm run build", "cwd": "shop-site" },
        "choices": [
          { "id": "once", "label": "Allow once", "behavior": "allow", "scope": "once" },
          { "id": "session", "label": "Allow for this chat", "behavior": "allow", "scope": "session" },
          { "id": "reject", "label": "Reject", "behavior": "deny", "scope": "once" }
        ],
        "expires_at": 1794390126.0 } } }
    """#

    static let packetQuestion = #"""
    { "type": "update", "sessionId": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "turnId": "7d6c5b4a39281706f5e4d3c2b1a09f8e", "revision": 14,
      "changes": { "permission": {
        "id": "req_question_1", "kind": "question", "tool": "ask_user", "title": "Waiting for your response",
        "questions": [
          { "question": "Which store should I check first?", "header": "Store", "multiSelect": false,
            "options": [ { "label": "The hardware store", "description": "Closest, 2 miles" }, { "label": "The corner shop", "description": "" } ] },
          { "question": "Anything else to look for?", "header": "", "multiSelect": true, "options": [] }
        ],
        "choices": [], "arguments": {}, "expires_at": 1794391800.0 } } }
    """#

    static let packetCleared = #"""
    { "type": "update", "sessionId": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "turnId": "7d6c5b4a39281706f5e4d3c2b1a09f8e", "revision": 15, "changes": { "permission": null } }
    """#

    static let packetDone = #"""
    { "type": "update", "sessionId": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "turnId": "7d6c5b4a39281706f5e4d3c2b1a09f8e", "revision": 16,
      "changes": { "status": "done", "stopping": false, "permission": null, "error": null, "waitingSince": null, "providerDetail": null } }
    """#

    static let packetFailed = #"""
    { "type": "update", "sessionId": "1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6", "turnId": "7d6c5b4a39281706f5e4d3c2b1a09f8e", "revision": 16,
      "changes": { "status": "failed", "stopping": false, "permission": null, "error": "The selected model is rate limited. Choose another model to retry.", "waitingSince": null, "providerDetail": null } }
    """#

    static let packetHeartbeat = #"""
    { "type": "heartbeat" }
    """#

    static let packetBackground = #"""
    { "type": "bg_tasks", "sessionId": "9f0c1a2b3c4d4e5f8a7b6c5d4e3f2a1b",
      "items": [ { "id": "helper:run_81", "kind": "subagent", "source": "kairos", "label": "Writing the one-page plan", "status": "running", "activity": "Drafting section 2", "startedAt": 1794300100.0, "endedAt": null, "detail": "result" } ],
      "notes": [] }
    """#

    static let packetFollowup = #"""
    { "type": "bg_followup", "sessionId": "9f0c1a2b3c4d4e5f8a7b6c5d4e3f2a1b",
      "message": { "role": "assistant", "content": "The plan is written.", "ts": 1794300400.0, "run_id": "run_82", "background_followup": true } }
    """#

    /// The stream as it arrives on the wire: comment keepalives, blank lines and one event per `data:` line.
    static let wire = [
        ": keepalive",
        "",
        "data: " + #"{"type": "heartbeat"}"#,
        "",
        "data: " + #"{"type": "chunk", "sessionId": "abc", "turnId": "t1", "revision": 2, "chunk": "Hello"}"#,
        "event: ignored",
    ]

    // MARK: Checks

    private static func need<T>(_ value: T?, _ name: String) throws -> T {
        guard let value else { throw SampleMismatch("\(name) is missing") }
        return value
    }

    private static func expect(_ condition: Bool, _ name: String) throws {
        if !condition { throw SampleMismatch("\(name) is not what the sample holds") }
    }

    static let checks: [DecodeCheck] = [
        DecodeCheck("phone.pair") {
            let claim = try KJSON.decode(PhonePairClaimDTO.self, from: pairClaim)
            try expect(claim.token.hasPrefix("kph_"), "token")
            try expect(try need(claim.account?.isAdmin, "account.is_admin"), "account.is_admin")
            try expect(try need(claim.server?.version, "server.version") == "2.3.0", "server.version")
            return "token, \(try need(claim.account?.username, "account.username")), device \(try need(claim.deviceId, "device_id"))"
        },
        DecodeCheck("phone.errors") {
            let refused = try KJSON.decode(APIErrorBody.self, from: pairRefused)
            try expect(refused.text == "That code is not right or has expired.", "detail text")
            let bad = try KJSON.decode(APIErrorBody.self, from: badRequest)
            try expect(bad.text == "Field required", "detail list")
            return "text and list details"
        },
        DecodeCheck("phone.session") {
            let session = try KJSON.decode(PhoneSessionDTO.self, from: phoneSession)
            return "\(try need(session.account?.username, "account.username")) on \(try need(session.server?.name, "server.name"))"
        },
        DecodeCheck("phone.devices") {
            let devices = try need(try KJSON.decode(PhoneDevicesDTO.self, from: phoneDevices).devices, "devices")
            try expect(devices.count == 2, "devices")
            _ = try need(devices[0].createdAt?.date, "created_at as a date")
            _ = try need(devices[0].lastSeenAt?.date, "last_seen_at with fractions")
            try expect(devices[1].lastSeenAt?.date == nil, "null last_seen_at")
            try expect(try need(devices[0].current, "current"), "current")
            return "\(devices.count) phones"
        },
        DecodeCheck("phone.home") {
            let home = try KJSON.decode(PhoneHomeDTO.self, from: phoneHome)
            let usage = try need(home.usage, "usage")
            try expect(usage.count == 2 && usage[1].percent == 22.5, "usage")
            _ = try need(home.nextEvent?.startsAt?.date, "next_event.starts_at")
            try expect(home.needsYou == 2 && home.running == 1, "counts")
            let empty = try KJSON.decode(PhoneHomeDTO.self, from: phoneHomeEmpty)
            try expect(empty.nextEvent == nil && (empty.usage ?? []).isEmpty, "empty home")
            return "\(usage.count) providers, next \(try need(home.nextEvent?.title, "next_event.title"))"
        },
        DecodeCheck("phone.ring") {
            let ring = try KJSON.decode(PhoneRingStateDTO.self, from: ringState)
            try expect(try need(ring.status, "status") == "ringing", "status")
            return "\(try need(ring.botName, "bot_name")), \(Int(try need(ring.secondsLeft, "seconds_left"))) s left"
        },
        DecodeCheck("chat.sessions") {
            let rows = try KJSON.decode([ChatSessionRowDTO].self, from: sessions)
            try expect(rows.count == 3, "rows")
            try expect(try need(rows[0].starred, "starred"), "starred")
            try expect(try need(rows[2].isForge, "is_forge"), "is_forge")
            _ = try need(rows[0].updatedAt, "updated_at")
            return "\(rows.count) chats"
        },
        DecodeCheck("chat.session") {
            let chat = try KJSON.decode(ChatSessionDTO.self, from: session)
            let messages = try need(chat.messages, "messages")
            try expect(messages.count == 4, "messages")
            try expect(try need(chat.modelEffort, "model_effort") == "high", "model_effort")
            try expect(try need(chat.permissionMode, "permission_mode") == "base", "permission_mode")
            try expect(try need(messages[0].attachments?.first?.url, "attachments.url").hasPrefix("/chat-files/"), "attachment url")
            try expect(try need(messages[3].failureKind, "failure_kind") == "rate_limited", "failure_kind")
            try expect(try need(chat.contextState?.parts, "context_state.parts").count == 2, "context parts")
            return "\(messages.count) messages, \(Int(try need(chat.contextState?.usedTokens, "used_tokens"))) tokens"
        },
        DecodeCheck("chat.actions") {
            let forked = try KJSON.decode(ChatForkDTO.self, from: fork)
            let model = try KJSON.decode(ChatModelSetDTO.self, from: modelSet)
            let started = try KJSON.decode(ChatStartDTO.self, from: start)
            let stopped = try KJSON.decode(ChatStopDTO.self, from: stop)
            let answered = try KJSON.decode(ChatPermissionResultDTO.self, from: permissionResult)
            try expect(!forked.id.isEmpty, "fork id")
            try expect(try need(model.effort, "effort") == "high" && model.modelOverride == nil, "model answer")
            try expect(try need(stopped.stopping, "stopping"), "stopping")
            try expect(try need(answered.status, "status") == "answered", "status")
            return "turn \(try need(started.turnId, "turn_id").prefix(6))"
        },
        DecodeCheck("chat.models") {
            let choices = try KJSON.decode([ModelChoiceDTO].self, from: modelChoices)
            let catalog = try KJSON.decode([ModelCatalogEntryDTO].self, from: modelCatalog)
            try expect(choices.count == 3 && choices[2].mark == nil, "choices")
            try expect(try need(choices[0].supportsImages, "supports_images"), "supports_images")
            try expect(try need(catalog[0].supportedEfforts, "supported_efforts").count == 3, "efforts")
            return "\(choices.count) connections, \(catalog.count) versions, \(try need(catalog[0].displayName, "display_name"))"
        },
        DecodeCheck("chat.usage") {
            let full = try KJSON.decode(ChatUsageDTO.self, from: usage)
            try expect(try need(full.turns, "turns") == 3, "turns")
            try expect(try need(full.cacheHitPercent, "cache_hit_percent") == 82.4, "cache_hit_percent")
            try expect(try need(full.lastReply?.ttftSeconds, "last_reply.ttft_seconds") == 0.62, "ttft")
            try expect(try need(full.model?.contextWindowEstimated, "context_window_estimated"), "window estimated")
            try expect(try need(full.sidePurposes, "side_purposes").count == 1, "side purposes")
            let empty = try KJSON.decode(ChatUsageDTO.self, from: usageEmpty)
            try expect(empty.inputTokens == nil && empty.context == nil, "nothing reported stays nil")
            let reading = try KJSON.decode(ChatContextDTO.self, from: context)
            try expect(reading.available == false, "available")
            return "\(Int(try need(full.inputTokens, "input_tokens"))) in, \(Int(try need(full.outputTokens, "output_tokens"))) out"
        },
        DecodeCheck("chat.files") {
            let list = try KJSON.decode([ChatFileDTO].self, from: files)
            try expect(list.count == 3 && list[2].exists == false && list[2].size == nil, "files")
            let meta = try KJSON.decode(ChatArtifactDTO.self, from: artifact)
            try expect(try need(meta.kind, "kind") == "office" && meta.extension == "docx", "artifact")
            let sent = try KJSON.decode(ChatUploadDTO.self, from: upload)
            try expect(sent.id == "a1b2c3d4e5f6", "upload id")
            let short = try KJSON.decode(ChatSummaryDTO.self, from: summary)
            _ = try need(short.summary, "summary")
            let work = try KJSON.decode(ChatBackgroundDTO.self, from: background)
            try expect(try need(work.items, "items").count == 2, "background items")
            _ = try need(work.items?.first?.startedAt, "startedAt")
            return "\(list.count) files, \(work.items?.count ?? 0) background items"
        },
        DecodeCheck("live.snapshot") {
            let packet = try KJSON.decode(ChatLivePacketDTO.self, from: packetSnapshot)
            let run = try need(packet.runs?["1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6"], "runs by session id")
            try expect(try need(run.status, "status") == "processing", "status")
            try expect(try need(run.toolSteps, "toolSteps").count == 2, "toolSteps")
            try expect(try need(run.revision, "revision") == 9, "revision")
            let started = try KJSON.decode(ChatLivePacketDTO.self, from: packetStarted)
            try expect(try need(started.run?.turnId, "run.turnId").count == 32, "turn id")
            return "1 run, \(run.toolSteps?.count ?? 0) steps"
        },
        DecodeCheck("live.text and steps") {
            let chunk = try KJSON.decode(ChatLivePacketDTO.self, from: packetChunk)
            try expect(try need(chunk.chunk, "chunk") == " within 5 miles.", "chunk")
            try expect(try need(chunk.revision, "revision") == 10, "revision")
            let step = try KJSON.decode(ChatLivePacketDTO.self, from: packetToolStep)
            try expect(try need(step.step?.phase, "value.phase") == "started", "phase")
            try expect(step.step?.ok == nil, "ok is null while running")
            let event = try KJSON.decode(ChatLivePacketDTO.self, from: packetToolEvent)
            try expect(event.type == "tool_event", "tool_event")
            let beat = try KJSON.decode(ChatLivePacketDTO.self, from: packetHeartbeat)
            try expect(beat.type == "heartbeat" && beat.sessionId == nil, "heartbeat")
            return "chunk, step \(try need(step.step?.summary, "value.summary"))"
        },
        DecodeCheck("live.approval") {
            let packet = try KJSON.decode(ChatLivePacketDTO.self, from: packetApproval)
            let changes = try need(packet.changes, "changes")
            try expect(changes.hasPermission, "permission present")
            let request = try need(changes.permission, "permission")
            try expect(try need(request.kind, "kind") == "permission", "kind")
            try expect(try need(request.choices, "choices").count == 3, "choices")
            try expect(try need(request.choices?.last?.behavior, "behavior") == "deny", "behavior")
            _ = try need(request.expiresAt, "expires_at")
            try expect(request.arguments?["command"]?.string == "npm run build", "arguments")
            return "\(try need(request.title, "title")): \(request.choices?.count ?? 0) choices"
        },
        DecodeCheck("live.question") {
            let packet = try KJSON.decode(ChatLivePacketDTO.self, from: packetQuestion)
            let request = try need(packet.changes?.permission, "permission")
            try expect(try need(request.kind, "kind") == "question", "kind")
            let questions = try need(request.questions, "questions")
            try expect(questions.count == 2, "questions")
            try expect(try need(questions[0].options, "options").count == 2, "options")
            try expect(try need(questions[1].multiSelect, "multiSelect"), "multiSelect")
            return "\(questions.count) questions"
        },
        DecodeCheck("live.endings") {
            let cleared = try KJSON.decode(ChatLivePacketDTO.self, from: packetCleared)
            try expect(cleared.changes?.hasPermission == true && cleared.changes?.permission == nil, "a null permission closes the request")
            try expect(cleared.changes?.status == nil && cleared.changes?.hasError == false, "fields left out stay untouched")
            let done = try KJSON.decode(ChatLivePacketDTO.self, from: packetDone)
            try expect(try need(done.changes?.status, "status") == "done", "done")
            let failed = try KJSON.decode(ChatLivePacketDTO.self, from: packetFailed)
            try expect(try need(failed.changes?.error, "error").contains("rate limited"), "error")
            return "cleared, done, failed"
        },
        DecodeCheck("live.background") {
            let tasks = try KJSON.decode(ChatLivePacketDTO.self, from: packetBackground)
            try expect(try need(tasks.items, "items").first?.status == "running", "items")
            let followup = try KJSON.decode(ChatLivePacketDTO.self, from: packetFollowup)
            try expect(try need(followup.message?.content, "message.content") == "The plan is written.", "message")
            return "1 task, 1 follow-up"
        },
        DecodeCheck("live.wire") {
            let payloads = wire.compactMap { LiveEventStream.payload(of: $0) }
            try expect(payloads.count == 2, "two data lines out of six")
            let packets = try payloads.map { try KJSON.decode(ChatLivePacketDTO.self, from: $0) }
            try expect(packets[1].chunk == "Hello", "chunk text")
            return "\(payloads.count) events from \(wire.count) lines"
        },
    ]
}
