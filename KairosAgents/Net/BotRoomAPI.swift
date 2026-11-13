import Foundation

// The desktop's room routes as the Bots area reads them: one decoder per answer and one function per route.
// Shapes were read from routes/bot_room_routes.py, services/bot_rooms.py (public, message_view, messages,
// update, create, mark_read, the thread calls), services/bot_room_turns.py (submit, stop, hold) and
// core/bot_rooms_store.py (add_message, queue_list). The room itself is `BotRoomDTO` in Net/BotAPI.swift.
//
// - Lists are decoded item by item (`BotRoutineLossy`): one odd row is left out and counted, never the list.
// - A message is sent with a `send_id` made on this iPhone. The desktop stores a message once per send id: the
//   same id again returns the stored row with `replayed: true` and starts nothing (bot_rooms_store.add_message),
//   whatever text comes with it. So a retry after a lost answer reuses the id and can never send twice.
// - A room's working folder (`cwd`) is never sent from here.
// - Every refusal is `{"detail": text}`, which `APIError` already reads. A stale `expected_revision` is a 409.

// MARK: - Messages

/// One row of a room's transcript (bot_rooms.py: message_view). `role` is "person", "bot" or "system";
/// `kind` is "text", "card", "webhook_post", "handoff", "goal" or "chip" (a small system line).
nonisolated struct BotRmMessageDTO: Decodable, Hashable, Sendable {
    var id: String
    var roomId: String?
    var threadId: String?
    var seq: Int?
    var role: String?
    var botId: String?
    var text: String?
    var kind: String?
    var replyToId: String?
    var sendId: String?
    var runId: String?
    var turnId: String?
    var meta: JSONValue?
    var createdAt: FlexibleDate?
}

/// GET /api/bot-rooms/{id}/messages: one page of one thread, oldest first. `has_more`: older rows exist.
nonisolated struct BotRmMessagesDTO: Decodable, Sendable {
    var threadId: String?
    var messages: [BotRoutineLossy<BotRmMessageDTO>]?
    var hasMore: Bool?
    var lastSeq: Int?
}

/// POST /api/bot-rooms/{id}/messages (202, bot_room_turns.py: submit). `replayed`: this send id was stored
/// before and nothing new started. `queued`: the thread is working, so it waits its turn. `stopped`: the text
/// was a stop word and these bots were stopped.
nonisolated struct BotRmSendDTO: Decodable, Sendable {
    var message: BotRmMessageDTO?
    var queued: Bool?
    var queueId: String?
    var replayed: Bool?
    var stopped: [String]?
}

/// POST /api/bot-rooms/{id}/stop: the bots whose running turn was cut.
nonisolated struct BotRmStopDTO: Decodable, Sendable {
    var stopped: [String]?
}

/// POST /api/bot-rooms/{id}/holds
nonisolated struct BotRmHoldDTO: Decodable, Sendable {
    var botId: String?
    var held: Bool?
}

/// One waiting message (bot_room_routes.py: get_queue). `state` is "pending" (can be cancelled) or "dispatching".
nonisolated struct BotRmQueueItemDTO: Decodable, Hashable, Sendable {
    var id: String
    var state: String?
    var threadId: String?
    var text: String?
    var messageId: String?
    var position: Int?
}

nonisolated struct BotRmQueueDTO: Decodable, Sendable {
    var items: [BotRoutineLossy<BotRmQueueItemDTO>]?
}

/// One conversation of a room. The list adds `working`; create and rename answer the stored row.
nonisolated struct BotRmThreadDTO: Decodable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String?
    var goal: JSONValue?
    var createdAt: FlexibleDate?
    var working: Bool?
}

nonisolated struct BotRmThreadListDTO: Decodable, Sendable {
    var threads: [BotRoutineLossy<BotRmThreadDTO>]?
}

/// DELETE /api/bot-rooms/{id}/threads/{thread}: the ids removed. The desktop always keeps one thread, so
/// deleting the last one removes nothing.
nonisolated struct BotRmThreadDeleteDTO: Decodable, Sendable {
    var deleted: [String]?
}

/// POST /api/bot-rooms/{id}/read
nonisolated struct BotRmReadDTO: Decodable, Sendable {
    var unread: Int?
}

// MARK: - Who answers

/// A room's `default_responder` (bot_rooms.py: validate_responder).
nonisolated enum BotRmResponder: Equatable, Sendable {
    case auto(fallback: String?)
    case everyone
    case mentions
    case member(String)

    /// Read from the free JSON the desktop sends; an unknown kind is "mentions", the desktop's own fallback.
    static func read(_ value: JSONValue?) -> BotRmResponder {
        switch BotRoutineWire.field(value, "kind")?.string {
        case "auto": return .auto(fallback: BotRoutineWire.field(value, "fallback_bot_id")?.string)
        case "everyone": return .everyone
        case "member":
            if let id = BotRoutineWire.field(value, "bot_id")?.string { return .member(id) }
            return .mentions
        default: return .mentions
        }
    }

    /// As the desktop takes it.
    var wire: [String: Any] {
        switch self {
        case .auto(let fallback):
            var out: [String: Any] = ["kind": "auto"]
            if let fallback { out["fallback_bot_id"] = fallback }
            return out
        case .everyone: return ["kind": "everyone"]
        case .mentions: return ["kind": "mentions"]
        case .member(let id): return ["kind": "member", "bot_id": id]
        }
    }

    /// The same choice, ignoring an auto room's fallback.
    func sameChoice(_ other: BotRmResponder) -> Bool {
        switch (self, other) {
        case (.auto, .auto), (.everyone, .everyone), (.mentions, .mentions): return true
        case (.member(let a), .member(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/bot-rooms/{id}: 404 for a room that is not this account's or no longer exists.
    func botRoomGet(_ id: String) async throws -> BotRoomDTO {
        try await get("/api/bot-rooms/\(id)")
    }

    /// GET /api/bot-rooms/{id}/messages: the newest `limit` rows (at most 200) of a thread, or those before `before`
    /// (a seq). No thread: the room's first.
    func botRoomMessages(_ id: String, threadID: String?, limit: Int = 50, before: Int? = nil) async throws -> BotRmMessagesDTO {
        try await get("/api/bot-rooms/\(id)/messages", query: [
            "thread_id": threadID,
            "limit": String(limit),
            "before": before.map { String($0) },
        ])
    }

    /// POST /api/bot-rooms/{id}/messages with a `send_id` of 8 to 80 characters made on this iPhone.
    func botRoomSend(_ id: String, text: String, sendID: String, threadID: String?, replyTo: String?) async throws -> BotRmSendDTO {
        var body: [String: Any] = ["text": text, "send_id": sendID]
        if let threadID { body["thread_id"] = threadID }
        if let replyTo { body["reply_to_id"] = replyTo }
        return try await post("/api/bot-rooms/\(id)/messages", json: body)
    }

    /// POST /api/bot-rooms/{id}/stop: one bot's running turn, or with no bot everything: running turns, waiting
    /// messages, the room's goal and its hand-offs.
    func botRoomStop(_ id: String, botID: String?, threadID: String?) async throws -> BotRmStopDTO {
        var body: [String: Any] = [:]
        if let botID { body["bot_id"] = botID }
        if let threadID { body["thread_id"] = threadID }
        return try await post("/api/bot-rooms/\(id)/stop", json: body)
    }

    /// POST /api/bot-rooms/{id}/holds: hold a member (it takes no turns) or let it answer again.
    func botRoomHold(_ id: String, botID: String, held: Bool) async throws -> BotRmHoldDTO {
        try await post("/api/bot-rooms/\(id)/holds", json: ["bot_id": botID, "held": held])
    }

    /// GET /api/bot-rooms/{id}/queue: messages waiting for a turn.
    func botRoomQueue(_ id: String, threadID: String?) async throws -> BotRmQueueDTO {
        try await get("/api/bot-rooms/\(id)/queue", query: ["thread_id": threadID])
    }

    /// DELETE /api/bot-rooms/{id}/queue/{queue}: a waiting message stops waiting (409 once it started).
    func botRoomQueueCancel(_ id: String, queueID: String) async throws {
        try await call("DELETE", "/api/bot-rooms/\(id)/queue/\(queueID)")
    }

    /// POST /api/bot-rooms/{id}/read: read up to `seq`, or everything.
    func botRoomRead(_ id: String, seq: Int?) async throws -> BotRmReadDTO {
        var body: [String: Any] = [:]
        if let seq { body["seq"] = seq }
        return try await post("/api/bot-rooms/\(id)/read", json: body)
    }

    /// PATCH /api/bot-rooms/{id}: only the changed fields, with `expected_revision` (409 when stale, or when the
    /// members change while the room is working).
    func botRoomUpdate(_ id: String, _ fields: [String: Any]) async throws -> BotRoomDTO {
        try await request("PATCH", "/api/bot-rooms/\(id)", json: fields)
    }

    /// POST /api/bot-rooms: a room with its bots. `setup_done` so it can be used at once; no working folder.
    func botRoomCreate(name: String, context: String, botIDs: [String]) async throws -> BotRoomDTO {
        try await post("/api/bot-rooms", json: ["name": name, "context": context, "bot_ids": botIDs, "setup_done": true])
    }

    /// GET /api/bot-rooms/{id}/threads
    func botRoomThreads(_ id: String) async throws -> BotRmThreadListDTO {
        try await get("/api/bot-rooms/\(id)/threads")
    }

    /// POST /api/bot-rooms/{id}/threads
    func botRoomThreadCreate(_ id: String, title: String) async throws -> BotRmThreadDTO {
        try await post("/api/bot-rooms/\(id)/threads", json: ["title": title])
    }

    /// PATCH /api/bot-rooms/{id}/threads/{thread}
    func botRoomThreadRename(_ id: String, threadID: String, title: String) async throws -> BotRmThreadDTO {
        try await request("PATCH", "/api/bot-rooms/\(id)/threads/\(threadID)", json: ["title": title])
    }

    /// DELETE /api/bot-rooms/{id}/threads/{thread}: the thread and every message in it (409 while it works).
    func botRoomThreadDelete(_ id: String, threadID: String) async throws -> BotRmThreadDeleteDTO {
        try await request("DELETE", "/api/bot-rooms/\(id)/threads/\(threadID)")
    }
}

// MARK: - Samples

/// A sample answer for every route above, shaped like the desktop's own (made-up content).
nonisolated enum BotRoomSamples {

    static let room = #"""
    {"id": "a1b2c3d4e5f60718", "name": "Spring sale", "context": "Shop", "description": "", "bulletin": "Keep it short.",
     "cwd": null, "default_responder": {"kind": "member", "bot_id": "agent_quill"}, "turn_timeout_minutes": 5,
     "setup_state": "done", "pinned_message_id": "m0000000000000002", "revision": 4, "created_at": 1792000000.0,
     "archived_at": null,
     "members": [{"bot_id": "agent_quill", "name": "Quill", "held": false, "working": true, "waiting": false,
                  "seat_session_id": "s1", "last_seen_seq": 2},
                 {"bot_id": "agent_scout", "name": "Scout", "held": true, "working": false, "waiting": false,
                  "seat_session_id": null, "last_seen_seq": 0}],
     "working": true, "unread": 1, "last_seq": 3,
     "threads": [{"id": "t000000000000001", "title": "", "goal": null}]}
    """#

    static let messages = #"""
    {"thread_id": "t000000000000001", "has_more": true, "last_seq": 4,
     "messages": [
      {"id": "m0000000000000001", "room_id": "a1b2c3d4e5f60718", "thread_id": "t000000000000001", "seq": 1,
       "role": "person", "bot_id": null, "text": "Draft the sale post.", "kind": "text", "reply_to_id": null,
       "send_id": "phone-0001-abcd", "run_id": null, "turn_id": null, "meta": {"mode": "text"}, "created_at": 1793000000.0},
      {"id": "m0000000000000002", "room_id": "a1b2c3d4e5f60718", "thread_id": "t000000000000001", "seq": 2,
       "role": "bot", "bot_id": "agent_quill", "text": "Here is a first draft.", "kind": "text", "reply_to_id": null,
       "send_id": null, "run_id": "r1", "turn_id": "u1", "meta": {"hop": 0, "origin": "person", "outcome": "settled"},
       "created_at": 1793000020.5},
      {"id": "m0000000000000003", "room_id": "a1b2c3d4e5f60718", "thread_id": "t000000000000001", "seq": 3,
       "role": "system", "bot_id": null, "text": "Scout was stopped.", "kind": "chip", "reply_to_id": null,
       "send_id": null, "run_id": null, "turn_id": null, "meta": {"kind_hint": "turn", "outcome": "cancelled"},
       "created_at": 1793000030.0},
      {"id": 7, "text": "odd row"}
     ]}
    """#

    static let sent = #"""
    {"message": {"id": "m0000000000000004", "room_id": "a1b2c3d4e5f60718", "thread_id": "t000000000000001", "seq": 4,
                 "role": "person", "bot_id": null, "text": "Make it shorter.", "kind": "text", "reply_to_id": null,
                 "send_id": "phone-0002-abcd", "run_id": null, "turn_id": null, "meta": {"mode": "text"},
                 "created_at": 1793000040.0},
     "queued": true, "queue_id": "q000000000000001", "held": [], "released": []}
    """#

    static let replayed = #"""
    {"message": {"id": "m0000000000000004", "seq": 4, "role": "person", "text": "Make it shorter.",
                 "send_id": "phone-0002-abcd", "created_at": 1793000040.0},
     "queued": false, "queue_id": null, "replayed": true}
    """#

    static let queue = #"""
    {"items": [{"id": "q000000000000001", "state": "pending", "thread_id": "t000000000000001", "text": "Make it shorter.",
                "message_id": "m0000000000000004", "position": 1},
               {"state": "pending"}]}
    """#

    static let threads = #"""
    {"threads": [{"id": "t000000000000001", "title": "", "goal": null, "created_at": 1792000000.0, "working": true},
                 {"id": "t000000000000002", "title": "Captions", "goal": null, "created_at": 1792500000.0, "working": false}]}
    """#

    static let stopped = #"""
    {"stopped": ["agent_quill"]}
    """#

    static let stale = #"""
    {"detail": "The room changed. Reload and try again."}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("botrooms.room") {
            let room = try KJSON.decode(BotRoomDTO.self, from: BotRoomSamples.room)
            guard room.revision == 4, room.members?.count == 2, room.members?.first?.working == true,
                  room.members?.last?.held == true, room.pinnedMessageId == "m0000000000000002",
                  BotRmResponder.read(room.defaultResponder) == .member("agent_quill"),
                  BotRmResponder.read(try KJSON.decode(JSONValue.self, from: #"{"kind": "auto", "fallback_bot_id": "b1"}"#)) == .auto(fallback: "b1"),
                  BotRmResponder.read(try KJSON.decode(JSONValue.self, from: #"{"kind": "new"}"#)) == .mentions,
                  room.turnTimeoutMinutes == 5, room.setupState == "done"
            else { throw SampleMismatch("room fields") }
            return "a room, two members, who answers"
        },
        DecodeCheck("botrooms.messages") {
            let page = try KJSON.decode(BotRmMessagesDTO.self, from: BotRoomSamples.messages)
            let (rows, skipped) = BotRoutineWire.items(page.messages)
            guard rows.count == 3, skipped == 1, page.hasMore == true, page.lastSeq == 4,
                  rows[0].sendId == "phone-0001-abcd", rows[1].botId == "agent_quill", rows[1].createdAt?.date != nil,
                  rows[2].kind == "chip", rows[2].role == "system", rows[0].seq == 1
            else { throw SampleMismatch("message fields") }
            return "\(rows.count) messages, \(skipped) left out"
        },
        DecodeCheck("botrooms.send") {
            let sent = try KJSON.decode(BotRmSendDTO.self, from: BotRoomSamples.sent)
            let again = try KJSON.decode(BotRmSendDTO.self, from: BotRoomSamples.replayed)
            let queue = BotRoutineWire.items(try KJSON.decode(BotRmQueueDTO.self, from: BotRoomSamples.queue).items)
            let threads = BotRoutineWire.items(try KJSON.decode(BotRmThreadListDTO.self, from: BotRoomSamples.threads).threads)
            let stop = try KJSON.decode(BotRmStopDTO.self, from: BotRoomSamples.stopped)
            let stale = try KJSON.decode(APIErrorBody.self, from: BotRoomSamples.stale)
            guard sent.queued == true, sent.message?.sendId == "phone-0002-abcd", sent.replayed == nil,
                  again.replayed == true, again.message?.id == "m0000000000000004",
                  queue.items.count == 1, queue.skipped == 1, queue.items[0].state == "pending",
                  threads.items.count == 2, threads.items[0].working == true, threads.items[1].title == "Captions",
                  stop.stopped == ["agent_quill"], stale.text.hasPrefix("The room changed")
            else { throw SampleMismatch("send, queue, threads or stop") }
            return "send, replay, queue, threads, stop, stale"
        },
        DecodeCheck("botrooms.wire") {
            let member = BotRmResponder.member("b2").wire
            let auto = BotRmResponder.auto(fallback: nil).wire
            guard member["kind"] as? String == "member", member["bot_id"] as? String == "b2",
                  auto["kind"] as? String == "auto", auto["fallback_bot_id"] == nil,
                  BotRmResponder.auto(fallback: "x").sameChoice(.auto(fallback: nil)),
                  !BotRmResponder.member("a").sameChoice(.member("b")),
                  BotRoomLiveMap.sendID().count >= 8, BotRoomLiveMap.sendID().count <= 80
            else { throw SampleMismatch("responder wire") }
            return "who answers sent as the desktop takes it"
        },
    ]
}
