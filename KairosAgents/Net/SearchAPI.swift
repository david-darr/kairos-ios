import Foundation

// The desktop routes Search needs that no other area's client covers, both reads: the text search over bot
// conversations (routes/bot_chat_routes.py GET /api/bot-chat/search over services/bot_chat_service.py search),
// and what one conversation is (routes/session_routes.py GET /api/sessions/{id}, with
// services/bot_attention.py target_for), so a bot's conversation never opens as a model chat.
//
// - The answer is {"query": text, "hits": [hit]}. A hit is one matching message: session_id, bot_id, title
//   (the conversation's), message_id, leaf_id, role ("user" or "assistant"), ts, active, other_version and a
//   snippet of the message around the match. Newest first, at most `limit` (1 to 100).
// - The desktop answers 422 for an empty or overlong query and 503 when its search is busy.
// - Search only reads: nothing here writes to the desktop.

// MARK: - Answers

/// One hit. Every field but the conversation id is read leniently, so one odd hit cannot hide the rest.
nonisolated struct SearchBotChatHitDTO: Decodable, Sendable {
    var sessionId: String
    var botId: JSONValue?
    var title: JSONValue?
    var snippet: JSONValue?
    var role: JSONValue?
    var ts: JSONValue?
    var otherVersion: JSONValue?

    /// The bot's id, when the desktop sent one as text.
    var bot: String? {
        guard let id = botId?.string, !id.isEmpty else { return nil }
        return id
    }

    /// True for a match in a version of the conversation that is not the one on screen.
    var isOtherVersion: Bool { otherVersion?.bool == true }
}

/// GET /api/bot-chat/search. Hits are read one by one: a hit this app cannot read is skipped and counted.
nonisolated struct SearchBotChatsDTO: Decodable, Sendable {
    var query: String?
    var hits: [SearchBotChatHitDTO] = []
    var skipped = 0

    private enum CodingKeys: String, CodingKey {
        case query, hits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try? container.decodeIfPresent(String.self, forKey: .query)
        guard container.contains(.hits), (try? container.decodeNil(forKey: .hits)) != true else { return }
        var list = try container.nestedUnkeyedContainer(forKey: .hits)
        while !list.isAtEnd {
            if let hit = try? list.decode(SearchBotChatHitDTO.self) {
                hits.append(hit)
            } else {
                // A failed decode does not move past the element; read it as anything to step over it.
                _ = try list.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

/// Where a bot conversation opens, from GET /api/sessions/{id} (session_routes.py get_session with
/// bot_attention.target_for): {"tab": "botsRoom", "roomId"} for a bot's seat in a room, else
/// {"tab": "botsShell", "agentId", "sessionId"}.
nonisolated struct SearchBotsTargetDTO: Decodable, Sendable {
    var tab: String?
    var roomId: String?
    var agentId: String?
    var sessionId: String?

    private enum CodingKeys: String, CodingKey {
        case tab, roomId, agentId, sessionId
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        tab = try? box.decodeIfPresent(String.self, forKey: .tab)
        roomId = try? box.decodeIfPresent(String.self, forKey: .roomId)
        agentId = try? box.decodeIfPresent(String.self, forKey: .agentId)
        sessionId = try? box.decodeIfPresent(String.self, forKey: .sessionId)
    }
}

/// GET /api/sessions/{id}: only what says what the conversation is. `agent_id` is set for a bot's conversation
/// (its own, or its seat in a room), and then `bots_target` says where it opens. The rest of the session is not read.
nonisolated struct SearchSessionDTO: Decodable, Sendable {
    var id: String?
    var agentId: String?
    var botsTarget: SearchBotsTargetDTO?

    private enum CodingKeys: String, CodingKey {
        case id, agentId, botsTarget
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try? box.decodeIfPresent(String.self, forKey: .id)
        agentId = try? box.decodeIfPresent(String.self, forKey: .agentId)
        botsTarget = try? box.decodeIfPresent(SearchBotsTargetDTO.self, forKey: .botsTarget)
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/bot-chat/search?q=&limit= . The desktop takes 1 to 200 characters, counted as Python counts them
    /// (code points), so the cap counts Unicode scalars.
    func searchBotChats(_ query: String, limit: Int = 30) async throws -> SearchBotChatsDTO {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: trimmed.unicodeScalars.prefix(200))
        let words = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return try await get("/api/bot-chat/search", query: ["q": words, "limit": String(max(1, min(limit, 100)))])
    }

    /// GET /api/sessions/{id}: what one conversation is, to open it in the right place. A read.
    func searchSession(_ id: String) async throws -> SearchSessionDTO {
        try await get("/api/sessions/" + (try DocsWire.pathID(id)))
    }
}

// MARK: - Samples

/// A sample answer for the bot chat search, shaped like the desktop's own (made-up content).
nonisolated enum SearchSamples {

    static let botChats = #"""
    {"query": "tyre", "hits": [
      {"session_id": "s-3f2a9c1b", "bot_id": "a-scout", "title": "Spring stock", "message_id": "m-1", "leaf_id": "m-4",
       "role": "assistant", "ts": 1793000000.5, "active": true, "other_version": false,
       "snippet": "...the city tyre in two widths before the spring rush"},
      {"session_id": "s-8e41b0c2", "bot_id": "a-quill", "title": "Newsletter", "message_id": "m-9", "leaf_id": "m-9",
       "role": "user", "ts": 1792990000, "active": false, "other_version": true, "snippet": "tyre pressure for city riding"},
      {"session_id": "s-c07d5e3a", "bot_id": null, "title": null, "message_id": null, "leaf_id": null,
       "role": "user", "ts": "2027-03-05T10:00:00", "active": true, "other_version": false, "snippet": "tyre levers"},
      {"bot_id": "a-scout", "snippet": "a hit with no conversation"}
    ]}
    """#

    static let empty = #"{"query": "zz", "hits": []}"#

    static let busy = #"{"detail": "Search is busy. Try again in a moment."}"#

    static let botSession = #"""
    {"id": "s-3f2a9c1b", "title": "Spring stock", "agent_id": "a-scout", "messages": [{"role": "user", "content": "hi"}],
     "permission_mode": "base", "bots_target": {"tab": "botsShell", "agentId": "a-scout", "sessionId": "s-3f2a9c1b"}}
    """#

    static let seatSession = #"""
    {"id": "s-8e41b0c2", "agent_id": "a-quill", "bots_target": {"tab": "botsRoom", "roomId": "r-51c0"}}
    """#

    static let modelSession = #"{"id": "s-c07d5e3a", "title": "Shop hours", "agent_id": null, "messages": []}"#

    static let checks: [DecodeCheck] = [
        DecodeCheck("search.session") {
            let bot = try KJSON.decode(SearchSessionDTO.self, from: SearchSamples.botSession)
            let seat = try KJSON.decode(SearchSessionDTO.self, from: SearchSamples.seatSession)
            let model = try KJSON.decode(SearchSessionDTO.self, from: SearchSamples.modelSession)
            let odd = try KJSON.decode(SearchSessionDTO.self, from: #"{"id": 7, "agent_id": 3, "bots_target": "x"}"#)
            guard bot.agentId == "a-scout", bot.botsTarget?.tab == "botsShell", bot.botsTarget?.sessionId == "s-3f2a9c1b",
                  seat.botsTarget?.tab == "botsRoom", seat.botsTarget?.roomId == "r-51c0",
                  model.agentId == nil, model.botsTarget == nil, model.id == "s-c07d5e3a",
                  odd.id == nil, odd.agentId == nil, odd.botsTarget == nil else {
                throw SampleMismatch("session place")
            }
            return "bot, room seat, model chat, odd fields"
        },
        DecodeCheck("search.botchats") {
            let read = try KJSON.decode(SearchBotChatsDTO.self, from: SearchSamples.botChats)
            guard read.query == "tyre", read.hits.count == 3, read.skipped == 1,
                  read.hits[0].sessionId == "s-3f2a9c1b", read.hits[0].bot == "a-scout",
                  read.hits[0].title?.string == "Spring stock", !read.hits[0].isOtherVersion,
                  read.hits[1].isOtherVersion, read.hits[2].bot == nil, read.hits[2].title?.isNull == true,
                  read.hits[0].snippet?.string?.contains("tyre") == true else {
                throw SampleMismatch("bot chat hits")
            }
            return "3 hits, 1 skipped, other version flag"
        },
        DecodeCheck("search.empty") {
            let none = try KJSON.decode(SearchBotChatsDTO.self, from: SearchSamples.empty)
            let missing = try KJSON.decode(SearchBotChatsDTO.self, from: #"{"query": "zz"}"#)
            let refused = try KJSON.decode(APIErrorBody.self, from: SearchSamples.busy)
            guard none.hits.isEmpty, none.skipped == 0, missing.hits.isEmpty,
                  refused.text.hasPrefix("Search is busy") else { throw SampleMismatch("empty or busy") }
            return "no hits, no list, busy"
        },
    ]
}
