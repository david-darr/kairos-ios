import Foundation

// The desktop routes behind Make home and the made list, as the phone reads them:
//
// - GET /api/front-desk/make (routes/front_desk_make_routes.py over services/front_desk_make.py: list_make):
//   {"items": [...], "making": [...]}. An item is {id ("design:<12 hex>" or "file:<24 hex>"), kind (design,
//   slides, website, files), title, updated_at (epoch seconds), thumb_url, open: {tab ("design" or
//   "artifact"), id (the design id, or the file's "/generated-files/<name>" path), session_id}}.
//   A making row is a front-desk task still being made: {id, title, thread_id, make_kind, created_at,
//   state ("working" or "needs_input")}. Any signed-in account may read it; it lists only that account's
//   own assistant threads, and answers empty lists when there is no assistant.
// - POST /api/front-desk/tasks (routes/front_desk_work_routes.py: start_task over services/front_desk_tasks.py:
//   start): {text, kind: "make", make_kind, send_id}. The body allows no other field. send_id is 8 to 80
//   characters; the same id with the same text and kind answers the same task again and starts nothing new,
//   the same id with other text is 409. A desktop account that is not the assistant's owner gets 404;
//   no assistant, or no model for it, is 422 with a sentence. The answer is the task as projected by
//   services/front_desk_work.py: project.
// - GET /api/front-desk/tasks/{id}: the same projection, 404 when it is not this account's.
// - POST /api/front-desk/tasks/{id}/again {turn_count}: sends the ask again only when the task is failed and
//   turn_count is still the one read; otherwise it answers the task as it is (front_desk_tasks.py: again).
//   The desktop dedupes the resend itself (send id "again:<task>:<count>").
// - GET /api/videos (routes/video_routes.py: list_videos over core/video_store.py: list_for_user): a JSON list of
//   whole video projects the account may see, newest first. Only id, title, updated, aspects and the beat
//   count are read here.

// MARK: - Answers

/// Where a made item opens (front_desk_make.py: list_make).
nonisolated struct MakeHomeOpenDTO: Decodable, Sendable {
    var tab: String?
    var id: String?
    var sessionId: String?
}

/// One made item. Every field but the id is read leniently, so one odd item cannot hide the rest.
nonisolated struct MakeHomeItemDTO: Decodable, Sendable {
    var id: String
    var kind: String?
    var title: JSONValue?
    var updatedAt: JSONValue?
    var thumbUrl: JSONValue?
    var open: MakeHomeOpenDTO?

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: Keys.self)
        id = try keys.decode(String.self, forKey: .id)
        kind = try? keys.decodeIfPresent(String.self, forKey: .kind)
        title = try? keys.decodeIfPresent(JSONValue.self, forKey: .title)
        updatedAt = try? keys.decodeIfPresent(JSONValue.self, forKey: .updatedAt)
        thumbUrl = try? keys.decodeIfPresent(JSONValue.self, forKey: .thumbUrl)
        open = try? keys.decodeIfPresent(MakeHomeOpenDTO.self, forKey: .open)
    }

    private enum Keys: String, CodingKey { case id, kind, title, updatedAt, thumbUrl, open }
}

/// A front-desk task, either a making row of GET /make or the whole projection of the task routes.
nonisolated struct MakeHomeTaskDTO: Decodable, Sendable {
    var id: String
    var title: String?
    var ask: String?
    var threadId: String?
    var makeKind: String?
    var createdAt: JSONValue?
    var state: String?
    var nextStep: String?
    var turnCount: JSONValue?
    var sendId: String?

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: Keys.self)
        id = try keys.decode(String.self, forKey: .id)
        title = try? keys.decodeIfPresent(String.self, forKey: .title)
        ask = try? keys.decodeIfPresent(String.self, forKey: .ask)
        threadId = try? keys.decodeIfPresent(String.self, forKey: .threadId)
        makeKind = try? keys.decodeIfPresent(String.self, forKey: .makeKind)
        createdAt = try? keys.decodeIfPresent(JSONValue.self, forKey: .createdAt)
        state = try? keys.decodeIfPresent(String.self, forKey: .state)
        nextStep = try? keys.decodeIfPresent(String.self, forKey: .nextStep)
        turnCount = try? keys.decodeIfPresent(JSONValue.self, forKey: .turnCount)
        sendId = try? keys.decodeIfPresent(String.self, forKey: .sendId)
    }

    private enum Keys: String, CodingKey { case id, title, ask, threadId, makeKind, createdAt, state, nextStep, turnCount, sendId }
}

/// GET /api/front-desk/make. A row this app cannot read is skipped and counted, never guessed at.
nonisolated struct MakeHomeListDTO: Decodable, Sendable {
    var items: [MakeHomeItemDTO] = []
    var making: [MakeHomeTaskDTO] = []
    var skipped = 0

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: Keys.self)
        if var list = try? keys.nestedUnkeyedContainer(forKey: .items) {
            while !list.isAtEnd {
                if let item = try? list.decode(MakeHomeItemDTO.self) { items.append(item) } else {
                    _ = try list.decode(JSONValue.self)
                    skipped += 1
                }
            }
        }
        if var list = try? keys.nestedUnkeyedContainer(forKey: .making) {
            while !list.isAtEnd {
                if let task = try? list.decode(MakeHomeTaskDTO.self) { making.append(task) } else {
                    _ = try list.decode(JSONValue.self)
                    skipped += 1
                }
            }
        }
    }

    private enum Keys: String, CodingKey { case items, making }
}

/// One video project, only the fields Make home shows (core/video_store.py).
nonisolated struct MakeHomeVideoDTO: Decodable, Sendable {
    var id: String
    var title: String?
    var updated: JSONValue?
    var aspects: [String]?
    var beatCount = 0

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: Keys.self)
        id = try keys.decode(String.self, forKey: .id)
        title = try? keys.decodeIfPresent(String.self, forKey: .title)
        updated = try? keys.decodeIfPresent(JSONValue.self, forKey: .updated)
        aspects = try? keys.decodeIfPresent([String].self, forKey: .aspects)
        beatCount = (try? keys.decodeIfPresent([JSONValue].self, forKey: .beats))?.count ?? 0
    }

    private enum Keys: String, CodingKey { case id, title, updated, aspects, beats }
}

/// GET /api/videos: a JSON list, read item by item.
nonisolated struct MakeHomeVideosDTO: Decodable, Sendable {
    var videos: [MakeHomeVideoDTO] = []
    var skipped = 0

    init(from decoder: Decoder) throws {
        var list = try decoder.unkeyedContainer()
        while !list.isAtEnd {
            if let video = try? list.decode(MakeHomeVideoDTO.self) { videos.append(video) } else {
                _ = try list.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

// MARK: - Wire helpers

/// What the desktop makes through the Make box (front_desk_tasks.py: MAKE_KINDS).
nonisolated enum MakeHomeKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case design, slides, website, files

    var id: String { rawValue }

    /// A kind this app does not know reads as nil; its item still shows, as a file.
    static func from(_ wire: String?) -> MakeHomeKind? { wire.flatMap(MakeHomeKind.init(rawValue:)) }

    var title: String {
        switch self {
        case .design: "Design"
        case .slides: "Slides"
        case .website: "Web page"
        case .files: "Files"
        }
    }

    var symbol: String {
        switch self {
        case .design: "paintpalette"
        case .slides: "rectangle.on.rectangle"
        case .website: "globe"
        case .files: "doc.text"
        }
    }

    var prompt: String {
        switch self {
        case .design: "A booking page for..."
        case .slides: "Six slides that explain..."
        case .website: "A one page site for..."
        case .files: "A one page plan for..."
        }
    }

    /// The shelf it sits on in the phone's own kinds.
    var shelf: MadeKind {
        switch self {
        case .design, .website: .design
        case .slides: .deck
        case .files: .document
        }
    }
}

/// Where a live made item opens on the phone.
nonisolated enum MakeHomeOpen: Hashable, Sendable {
    case design(String)
    case video(String)
    case file(sessionID: String, url: String, name: String)
}

nonisolated enum MakeHomeWire {
    /// The most the desktop takes in one ask (front_desk_work_routes.py: TaskBody.text).
    static let textLimit = 4000

    /// A new send id for one tap: 8 to 80 characters.
    static func newSendID() -> String { "ios-" + UUID().uuidString.lowercased() }

    /// The desktop's own check before it links a made item (static/js/botsMakeModel.js: makeTarget).
    static func open(_ item: MakeHomeItemDTO) -> MakeHomeOpen? {
        guard let open = item.open, let id = open.id, !id.isEmpty else { return nil }
        if open.tab == "design" { return isHex(id, 12) ? .design(id) : nil }
        guard open.tab == "artifact", let session = open.sessionId, !session.isEmpty,
              isFilePath(id) else { return nil }
        let name = String(id.split(separator: "/").last ?? "")
        return .file(sessionID: session, url: id, name: name)
    }

    /// "/generated-files/<name>" or "/generated-images/<name>", with no slash, colon, space or escape trick.
    static func isFilePath(_ path: String) -> Bool {
        let prefixes = ["/generated-files/", "/generated-images/"]
        guard let prefix = prefixes.first(where: { path.hasPrefix($0) }) else { return false }
        let name = path.dropFirst(prefix.count)
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        let banned = CharacterSet(charactersIn: "/\\:?#").union(.whitespacesAndNewlines)
        guard name.unicodeScalars.allSatisfy({ !banned.contains($0) }) else { return false }
        let lower = name.lowercased()
        return !["%2f", "%5c", "%2e", "%00"].contains(where: { lower.contains($0) })
    }

    static func isHex(_ text: String, _ count: Int) -> Bool {
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        return text.count == count && text.unicodeScalars.allSatisfy { hex.contains($0) }
    }

    static func time(_ value: JSONValue?) -> Date? {
        guard let seconds = value?.double, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// A task id goes into the path as it is. One that could leave the tasks path is refused.
    static func pathID(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 80,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else {
            throw APIError.unreadable("task id")
        }
        return id
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/front-desk/make, every kind.
    func makeHomeList() async throws -> MakeHomeListDTO {
        try await get("/api/front-desk/make")
    }

    /// POST /api/front-desk/tasks: start making. Starts a model turn on the desktop. Send the same id again only
    /// for the same tap, with the same text and kind.
    func makeHomeStart(text: String, kind: MakeHomeKind, sendID: String) async throws -> MakeHomeTaskDTO {
        try await post("/api/front-desk/tasks", json: [
            "text": text,
            "kind": "make",
            "make_kind": kind.rawValue,
            "send_id": sendID,
        ])
    }

    /// GET /api/front-desk/tasks/{id}.
    func makeHomeTask(_ id: String) async throws -> MakeHomeTaskDTO {
        try await get("/api/front-desk/tasks/" + MakeHomeWire.pathID(id))
    }

    /// POST /api/front-desk/tasks/{id}/again with the turn count read with the failure.
    func makeHomeAgain(_ id: String, turnCount: Int) async throws -> MakeHomeTaskDTO {
        try await post("/api/front-desk/tasks/" + MakeHomeWire.pathID(id) + "/again", json: ["turn_count": turnCount])
    }

    /// GET /api/videos.
    func makeHomeVideos() async throws -> MakeHomeVideosDTO {
        try await get("/api/videos")
    }
}

// MARK: - Samples

/// A sample answer for every Make home route, shaped like the desktop's own (made-up content).
nonisolated enum MakeHomeSamples {

    static let list = #"""
    {
      "items": [
        {"id": "design:3f2a9c1b7d04", "kind": "website", "title": "Bike shop booking page", "updated_at": 1793000100.5,
         "thumb_url": "/api/designs/3f2a9c1b7d04/boards/b1/thumb",
         "open": {"tab": "design", "id": "3f2a9c1b7d04", "session_id": "s-1a2b3c"}},
        {"id": "design:8e41b0c2a9f7", "kind": "slides", "title": "Repair class", "updated_at": 1792990000,
         "thumb_url": null, "open": {"tab": "design", "id": "8e41b0c2a9f7", "session_id": "s-4d5e6f"}},
        {"id": "file:0a1b2c3d4e5f60718293a4b5", "kind": "files", "title": "Launch plan.docx", "updated_at": 1792980000.0,
         "thumb_url": null, "open": {"tab": "artifact", "id": "/generated-files/1a2b3c4d5e6f_Launch-plan.docx", "session_id": "s-7a8b9c"}},
        {"id": "file:ffeeddccbbaa998877665544", "kind": "files", "title": "old notes.txt", "updated_at": 1792970000,
         "thumb_url": null, "open": {"tab": "artifact", "id": "/generated-files/9a8b7c6d5e4f_old notes.txt", "session_id": "s-7a8b9c"}},
        {"id": "design:c07d5e3a1b62", "kind": "poster", "title": "A kind from a newer desktop", "updated_at": 1792960000,
         "open": {"tab": "design", "id": "c07d5e3a1b62", "session_id": "s-1a2b3c"}},
        {"kind": "design", "title": "No id"}
      ],
      "making": [
        {"id": "5b9e2f0a4c18d7e6f501", "title": "A price list for the shop", "thread_id": "s-0f1e2d", "make_kind": "design",
         "created_at": 1793000200.25, "state": "working"}
      ]
    }
    """#

    static let task = #"""
    {"id": "5b9e2f0a4c18d7e6f501", "title": "A price list for the shop", "ask": "A price list for the shop",
     "thread_id": "s-0f1e2d", "origin": "make", "make_kind": "design", "source": null, "why": "", "channel_tag": "",
     "resolved_at": null, "created_at": 1793000200.25, "send_id": "ios-6b1f0e2a-3c4d-4e5f-8a9b-0c1d2e3f4a5b",
     "state": "working", "next_step": "Just started", "updated_at": 1793000200.25, "turn_count": 1}
    """#

    static let failed = #"""
    {"id": "5b9e2f0a4c18d7e6f501", "title": "A price list for the shop", "ask": "A price list for the shop",
     "thread_id": "s-0f1e2d", "make_kind": "design", "created_at": 1793000200.25, "state": "failed",
     "next_step": "Could not finish: The model is busy. Try again shortly", "updated_at": 1793000300, "turn_count": 1}
    """#

    static let videos = #"""
    [
      {"id": "a1b2c3d4e5f6", "title": "Spring ride tips", "look": "motion-type", "beats": [{"kind": "title", "bars": 2}, {"kind": "list", "bars": 4}],
       "bpm": 120, "fps": 30, "aspects": ["9:16"], "owner": "alex", "chat_ids": [], "visible_to": [], "version": 3,
       "created": 1792900000.5, "updated": 1793000000.5},
      {"title": "A video with no id"}
    ]
    """#

    static let conflict = #"{"detail": "This send ID was already used for another task"}"#
    static let notOwner = #"{"detail": "Task or suggestion not found"}"#

    static let checks: [DecodeCheck] = [
        DecodeCheck("makehome.list") {
            let read = try KJSON.decode(MakeHomeListDTO.self, from: MakeHomeSamples.list)
            guard read.items.count == 5, read.making.count == 1, read.skipped == 1,
                  MakeHomeKind.from(read.items[0].kind) == .website, MakeHomeKind.from(read.items[4].kind) == nil,
                  MakeHomeWire.open(read.items[0]) == .design("3f2a9c1b7d04"),
                  MakeHomeWire.open(read.items[2]) == .file(sessionID: "s-7a8b9c", url: "/generated-files/1a2b3c4d5e6f_Launch-plan.docx",
                                                           name: "1a2b3c4d5e6f_Launch-plan.docx"),
                  MakeHomeWire.open(read.items[3]) == nil,
                  MakeHomeWire.time(read.items[1].updatedAt) == Date(timeIntervalSince1970: 1_792_990_000),
                  read.making[0].state == "working", read.making[0].threadId == "s-0f1e2d" else {
                throw SampleMismatch("list fields")
            }
            return "5 items, 1 making, 1 skipped, links checked"
        },
        DecodeCheck("makehome.task") {
            let started = try KJSON.decode(MakeHomeTaskDTO.self, from: MakeHomeSamples.task)
            let failed = try KJSON.decode(MakeHomeTaskDTO.self, from: MakeHomeSamples.failed)
            let clash = try KJSON.decode(APIErrorBody.self, from: MakeHomeSamples.conflict)
            let refused = try KJSON.decode(APIErrorBody.self, from: MakeHomeSamples.notOwner)
            guard started.id.count == 20, started.state == "working", started.turnCount?.int == 1,
                  started.ask == "A price list for the shop", MakeHomeKind.from(started.makeKind) == .design,
                  failed.state == "failed", failed.nextStep?.hasPrefix("Could not finish") == true,
                  !clash.text.isEmpty, refused.text == "Task or suggestion not found",
                  (try? MakeHomeWire.pathID(started.id)) != nil, (try? MakeHomeWire.pathID("../x")) == nil else {
                throw SampleMismatch("task fields")
            }
            let id = MakeHomeWire.newSendID()
            guard (8...80).contains(id.count) else { throw SampleMismatch("send id length \(id.count)") }
            return "start, failed, 409, 404, send id"
        },
        DecodeCheck("makehome.videos") {
            let read = try KJSON.decode(MakeHomeVideosDTO.self, from: MakeHomeSamples.videos)
            guard read.videos.count == 1, read.skipped == 1, read.videos[0].beatCount == 2,
                  read.videos[0].aspects == ["9:16"], MakeHomeWire.time(read.videos[0].updated) != nil,
                  MakeHomeWire.isHex(read.videos[0].id, 12) else { throw SampleMismatch("video fields") }
            guard MakeHomeWire.isFilePath("/generated-images/abc.png"), !MakeHomeWire.isFilePath("/generated-files/a%2Fb"),
                  !MakeHomeWire.isFilePath("/generated-files/../x"), !MakeHomeWire.isFilePath("/chat-files/x") else {
                throw SampleMismatch("file path check")
            }
            return "1 video, 1 skipped, paths checked"
        },
    ]
}
