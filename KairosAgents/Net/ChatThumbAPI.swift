import Foundation

// What the chat screens read to draw real thumbnails and a chat's designs, as the phone reads them.
//
// - A file's bytes: GET /api/chat/artifacts/content (routes/chat_routes.py: artifact_content). It answers a
//   FileResponse, which honours a byte range, and it has no HEAD. So a thumbnail asks for the file once and reads
//   the answer's headers first: a file over the cap is never downloaded past its headers.
// - A chat's designs: GET /api/designs?chat=<session id> (routes/design_routes.py: list_designs over
//   core/design_store.py: summary). One design: GET /api/designs/{id}.
// - A design's first board as a picture: GET /api/designs/{id}/boards/{slug}/thumb (a PNG, or 404 when the
//   desktop cannot draw it).
//
// Nothing here marks the connection as broken: a thumbnail that fails is a thumbnail that is not drawn.

// MARK: - What the screens hold

/// A design a message links to: `[Design: title](/designs/<12 hex>)` (core/design_tools.py: the link a chat writes).
nonisolated struct ChatThumbRef: Hashable, Sendable {
    var id: String
    var title: String
}

/// A design of a chat, as its card shows it.
nonisolated struct ChatThumbDesign: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var boardCount = 0
    var version = 0
    /// Epoch seconds the design was made.
    var created: Double?
    /// The slug of its first board, for the picture.
    var firstBoard: String?
    /// The desktop listed it for this chat. false means it was only named by a link in a message.
    var listed = true
}

/// One message, as far as placing design cards is concerned.
nonisolated struct ChatThumbSlot: Hashable, Sendable {
    var id: String
    var assistant: Bool
    /// Read from the saved chat (it has its own time), as opposed to the reply being written.
    var saved: Bool
    var time: Date?
    var refs: [ChatThumbRef]
}

/// What to read of a file: the whole of it up to a cap, or only its start.
nonisolated struct ChatThumbPlan: Hashable, Sendable {
    /// Ask for only this many bytes from the start, when the desktop honours a range.
    var start: Int?
    /// The most bytes of a whole file the phone will take.
    var whole: Int
}

nonisolated enum ChatThumbFetched: Sendable {
    case bytes(Data)
    case tooBig
    case failed
}

// MARK: - Answers

/// A value that may fail to decode without failing the list around it.
nonisolated struct ChatThumbMaybe<Value: Decodable & Sendable>: Decodable, Sendable {
    var value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// One row of GET /api/designs (design_store.summary, plus board_titles and chat_title).
nonisolated struct ChatThumbDesignRowDTO: Decodable, Sendable {
    var id: String
    var title: JSONValue?
    /// How many boards.
    var boards: JSONValue?
    var version: JSONValue?
    var created: JSONValue?
    var firstBoard: JSONValue?
}

/// GET /api/designs/{id} (design_routes._client). Only what a card needs: the board order is read as a list of
/// slugs, never as the `boards` map, whose keys the decoder would rewrite.
nonisolated struct ChatThumbDesignOneDTO: Decodable, Sendable {
    var id: String
    var title: JSONValue?
    var version: JSONValue?
    var created: JSONValue?
    var order: JSONValue?
}

// MARK: - Reading what the desktop sent

nonisolated enum ChatThumbWire {
    /// A design id is 12 lowercase hex characters (core/design_store.py: DESIGN_ID).
    static func isDesignID(_ text: String) -> Bool {
        text.count == 12 && text.allSatisfy { "0123456789abcdef".contains($0) }
    }

    /// A board slug goes into a path: letters, digits, dash and underscore only.
    static func isSlug(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 80 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func title(_ value: JSONValue?) -> String {
        let text = (value?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Untitled design" : text
    }

    /// A row of a chat's design list. nil when it has no usable id.
    static func listed(_ row: ChatThumbDesignRowDTO) -> ChatThumbDesign? {
        guard isDesignID(row.id) else { return nil }
        let first = row.firstBoard?.string.flatMap { isSlug($0) ? $0 : nil }
        return ChatThumbDesign(id: row.id, title: title(row.title), boardCount: max(0, row.boards?.int ?? 0),
                               version: row.version?.int ?? 0, created: row.created?.double, firstBoard: first)
    }

    /// One design read by id. It is not "listed": it is a design a message named.
    static func detailed(_ one: ChatThumbDesignOneDTO) -> ChatThumbDesign? {
        guard isDesignID(one.id) else { return nil }
        let order = (one.order?.array ?? []).compactMap { $0.string }.filter { isSlug($0) }
        return ChatThumbDesign(id: one.id, title: title(one.title), boardCount: order.count, version: one.version?.int ?? 0,
                               created: one.created?.double, firstBoard: order.first, listed: false)
    }

    /// The whole size out of "bytes 0-99/1234". nil when the desktop wrote "*" or nothing.
    static func totalSize(contentRange: String?) -> Int? {
        guard let contentRange, let slash = contentRange.lastIndex(of: "/") else { return nil }
        return Int(contentRange[contentRange.index(after: slash)...].trimmingCharacters(in: .whitespaces))
    }

    /// The name a design link carries, without the "Design:" the chat writes in front of it.
    static func linkTitle(_ label: String) -> String {
        var text = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("design:") { text = String(text.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return text.isEmpty ? "Design" : text
    }
}

// MARK: - Where a design card sits

/// Where each design card is drawn. The desktop draws a design card where the chat wrote the design's link, so a
/// message that links a design carries it. A design of the chat that no message links goes under the first reply
/// saved at or after the time the design was made (the turn that made it), else under the last reply, which is the
/// one being written during a live turn.
nonisolated enum ChatThumbPlacement {
    static func place(slots: [ChatThumbSlot], listed: [ChatThumbDesign]) -> [String: [ChatThumbDesign]] {
        var result: [String: [ChatThumbDesign]] = [:]
        var placed = Set<String>()
        let byID = Dictionary(listed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for slot in slots where slot.assistant {
            for ref in slot.refs where placed.insert(ref.id).inserted {
                let design = byID[ref.id] ?? ChatThumbDesign(id: ref.id, title: ref.title, listed: false)
                result[slot.id, default: []].append(design)
            }
        }
        let lastAssistant = slots.last { $0.assistant }
        let rest = listed.filter { !placed.contains($0.id) }.sorted { ($0.created ?? 0) < ($1.created ?? 0) }
        for design in rest {
            let when = design.created.map { Date(timeIntervalSince1970: $0 - 2) }
            let target = slots.first { slot in
                guard slot.assistant, slot.saved, let time = slot.time, let when else { return false }
                return time >= when
            } ?? lastAssistant
            if let target { result[target.id, default: []].append(design) }
        }
        return result
    }
}

// MARK: - Routes

extension APIClient {

    /// GET /api/designs?chat=: the designs that belong to one chat, read row by row so one odd row never empties the list.
    func chatThumbDesigns(chat: String) async throws -> [ChatThumbDesign] {
        let rows: [ChatThumbMaybe<ChatThumbDesignRowDTO>] = try await get("/api/designs", query: ["chat": chat])
        return rows.compactMap { $0.value }.compactMap(ChatThumbWire.listed)
    }

    /// GET /api/designs/{id}: one design a message named.
    func chatThumbDesignOne(_ id: String) async throws -> ChatThumbDesign {
        guard ChatThumbWire.isDesignID(id) else { throw APIError.unreadable("design id") }
        let one: ChatThumbDesignOneDTO = try await get("/api/designs/\(id)")
        guard let design = ChatThumbWire.detailed(one) else { throw APIError.unreadable("design") }
        return design
    }

    /// GET /api/designs/{id}/boards/{slug}/thumb: the board as a PNG. 404 when the desktop cannot draw it.
    func chatThumbDesignImage(id: String, board: String) async throws -> Data {
        guard ChatThumbWire.isDesignID(id), ChatThumbWire.isSlug(board) else { throw APIError.unreadable("design board") }
        return try await bytes("/api/designs/\(id)/boards/\(board)/thumb")
    }

    /// The request for a chat file's bytes. The phone token rides in the header the client sets, nowhere else.
    func chatThumbFileRequest(sessionId: String, url: String, download: Bool, rangeEnd: Int?) throws -> URLRequest {
        var request = try urlRequest("GET", "/api/chat/artifacts/content", query: [
            "session_id": sessionId,
            "url": url,
            "download": download ? "true" : nil,
        ])
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let rangeEnd { request.setValue("bytes=0-\(rangeEnd)", forHTTPHeaderField: "Range") }
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
}

// MARK: - Reading a file with a cap

/// One read of one file. It looks at the answer's headers before it takes any body, never takes more than the
/// plan allows, and cancels the transfer the moment a file is over the cap. It never touches the connection's
/// state and never follows a redirect, so the token goes to the desktop's own address and nowhere else.
nonisolated final class ChatThumbFetcher: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let plan: ChatThumbPlan
    private let lock = NSLock()
    private var buffer = Data()
    private var limit = 0
    private var ranged = false
    private var rangeTotal: Int?
    private var done = false
    private var continuation: CheckedContinuation<ChatThumbFetched, Never>?
    private var session: URLSession?
    private var task: URLSessionDataTask?

    init(plan: ChatThumbPlan) {
        self.plan = plan
    }

    func run(_ request: URLRequest) async -> ChatThumbFetched {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ChatThumbFetched, Never>) in
                lock.lock()
                if done {
                    lock.unlock()
                    continuation.resume(returning: .failed)
                    return
                }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 90
                configuration.waitsForConnectivity = false
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                self.session = session
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.finish(.failed)
        }
    }

    private func finish(_ result: ChatThumbFetched) {
        lock.lock()
        guard !done else {
            lock.unlock()
            return
        }
        done = true
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        let task = self.task
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(returning: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failed)
            return
        }
        let length = http.expectedContentLength
        switch http.statusCode {
        case 206:
            guard let start = plan.start else {
                completionHandler(.cancel)
                finish(.failed)
                return
            }
            lock.lock()
            ranged = true
            limit = start
            rangeTotal = ChatThumbWire.totalSize(contentRange: http.value(forHTTPHeaderField: "Content-Range"))
            lock.unlock()
        case 200:
            // The whole file is coming (the desktop ignored a range, or none was asked for). Over the cap: stop here.
            if length > Int64(plan.whole) {
                completionHandler(.cancel)
                finish(.tooBig)
                return
            }
            lock.lock()
            limit = plan.whole
            lock.unlock()
        default:
            completionHandler(.cancel)
            finish(.failed)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffer.append(data)
        let over = buffer.count > limit
        let isRanged = ranged
        if over && isRanged { buffer = buffer.prefix(limit) }
        let kept = buffer
        lock.unlock()
        guard over else { return }
        // A ranged answer longer than asked is cut to what was asked; a whole file over the cap is too big.
        finish(isRanged ? .bytes(kept) : .tooBig)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let kept = buffer
        let finished = done
        lock.unlock()
        guard !finished else { return }
        finish(error == nil && !kept.isEmpty ? .bytes(kept) : .failed)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // The token is for the desktop's own address. A redirect is not followed.
        completionHandler(nil)
    }
}

// MARK: - Samples

/// Sample answers for the routes above, shaped like the desktop's own (made-up content), and decode checks.
nonisolated enum ChatThumbSamples {

    static let designList = #"""
    [
      {"id": "0a1b2c3d4e5f", "title": "Booking page", "owner": "owner", "boards": 3, "version": 7, "updated": 1794300000.5,
       "created": 1794200000.25, "chat_ids": ["1a2b3c4d5e6f47a8b9c0d1e2f3a4b5c6"], "design_system": "builtin",
       "first_board": "screen-1", "source": null, "board_titles": ["Home", "Prices", "Contact"], "chat_title": "Booking"},
      {"id": "9f8e7d6c5b4a", "title": null, "boards": 0, "version": 0, "created": null, "first_board": null},
      {"title": "A row with no id"},
      {"id": "not-a-design-id", "title": "A row with a bad id", "first_board": "x"},
      {"id": "1122334455aa", "title": "Flyer", "boards": 1, "version": 2, "created": 1794290000, "first_board": "../escape"}
    ]
    """#

    static let designOne = #"""
    {"id": "0a1b2c3d4e5f", "title": "Booking page", "owner": "owner", "boards": {"screen-1": {"title": "Home", "order": 0}},
     "order": ["screen-1", "screen_2"], "version": 7, "created": 1794200000.25, "chats": [{"id": "1a2b3c4d5e6f", "title": "Booking"}],
     "comments": [], "render_available": true}
    """#

    static let reply = "Here is the first version.\n\n[Design: Booking page](/designs/0a1b2c3d4e5f)\n\nTell me what to change."

    private static func need<T>(_ value: T?, _ name: String) throws -> T {
        guard let value else { throw SampleMismatch("missing \(name)") }
        return value
    }

    private static func expect(_ condition: Bool, _ name: String) throws {
        if !condition { throw SampleMismatch("wrong \(name)") }
    }

    static let checks: [DecodeCheck] = [
        DecodeCheck("chatthumb.designs") {
            let rows = try KJSON.decode([ChatThumbMaybe<ChatThumbDesignRowDTO>].self, from: designList)
            try expect(rows.count == 5, "rows")
            let designs = rows.compactMap { $0.value }.compactMap(ChatThumbWire.listed)
            // The row with no id and the row with a bad id are left out; the rest stay.
            try expect(designs.count == 3, "designs kept")
            let first = try need(designs.first, "first design")
            try expect(first.id == "0a1b2c3d4e5f" && first.title == "Booking page" && first.boardCount == 3 && first.version == 7, "first fields")
            try expect(first.firstBoard == "screen-1" && first.created == 1794200000.25 && first.listed, "first board and time")
            let bare = designs[1]
            try expect(bare.title == "Untitled design" && bare.firstBoard == nil && bare.created == nil, "null fields are no value")
            try expect(designs[2].firstBoard == nil, "a slug that is not safe is no board")
            return "\(designs.count) designs of \(rows.count) rows"
        },
        DecodeCheck("chatthumb.design") {
            let one = try KJSON.decode(ChatThumbDesignOneDTO.self, from: designOne)
            let design = try need(ChatThumbWire.detailed(one), "design")
            try expect(design.boardCount == 2 && design.firstBoard == "screen-1" && !design.listed, "boards from the order list")
            try expect(design.version == 7, "version")
            return "\(design.title), \(design.boardCount) boards"
        },
        DecodeCheck("chatthumb.links") {
            let body = TranscriptParsing.body(reply)
            try expect(body.designs == [ChatThumbRef(id: "0a1b2c3d4e5f", title: "Booking page")], "design ref")
            try expect(!body.text.contains("/designs/") && body.text.contains("Tell me what to change."), "link taken out of the words")
            let twice = TranscriptParsing.body(reply + "\n\n[Design: Booking page](/designs/0a1b2c3d4e5f)")
            try expect(twice.designs.count == 1, "a design linked twice is one card")
            let short = TranscriptParsing.body("[Design: x](/designs/abc)")
            try expect(short.designs.isEmpty, "an id that is not 12 hex characters is no design")
            try expect(ChatThumbWire.linkTitle("Design: Flyer") == "Flyer" && ChatThumbWire.linkTitle("  ") == "Design", "link title")
            return "1 design in the reply"
        },
        DecodeCheck("chatthumb.place") {
            let made = ChatThumbDesign(id: "0a1b2c3d4e5f", title: "A", created: 90)
            let later = ChatThumbDesign(id: "9f8e7d6c5b4a", title: "B", created: 200)
            let live = ChatThumbDesign(id: "1122334455aa", title: "C", created: 999)
            let slots = [
                ChatThumbSlot(id: "u1", assistant: false, saved: true, time: Date(timeIntervalSince1970: 50), refs: []),
                ChatThumbSlot(id: "a1", assistant: true, saved: true, time: Date(timeIntervalSince1970: 100),
                              refs: [ChatThumbRef(id: "0a1b2c3d4e5f", title: "A"), ChatThumbRef(id: "aabbccddeeff", title: "Gone")]),
                ChatThumbSlot(id: "a2", assistant: true, saved: true, time: Date(timeIntervalSince1970: 300), refs: []),
                ChatThumbSlot(id: "live", assistant: true, saved: false, time: Date(timeIntervalSince1970: 400), refs: []),
            ]
            let placed = ChatThumbPlacement.place(slots: slots, listed: [made, later, live])
            try expect(placed["a1"]?.map(\.id) == ["0a1b2c3d4e5f", "aabbccddeeff"], "linked designs sit under the message that links them")
            try expect(placed["a1"]?.last?.listed == false, "a link the desktop did not list still gets a card")
            try expect(placed["a2"]?.map(\.id) == ["9f8e7d6c5b4a"], "a design with no link sits under the reply of the turn that made it")
            try expect(placed["live"]?.map(\.id) == ["1122334455aa"], "a design made during the turn sits under the reply being written")
            try expect(placed["u1"] == nil, "nothing under the person's own message")
            let none = ChatThumbPlacement.place(slots: [slots[0]], listed: [made])
            try expect(none.isEmpty, "no reply, no card")
            return "\(placed.count) messages carry cards"
        },
        DecodeCheck("chatthumb.range") {
            try expect(ChatThumbWire.totalSize(contentRange: "bytes 0-99/1234") == 1234, "total")
            try expect(ChatThumbWire.totalSize(contentRange: "bytes 0-99/*") == nil, "unknown total")
            try expect(ChatThumbWire.totalSize(contentRange: nil) == nil, "no header")
            try expect(ChatThumbWire.isDesignID("0a1b2c3d4e5f") && !ChatThumbWire.isDesignID("0A1B2C3D4E5F") && !ChatThumbWire.isDesignID("abc"), "design id")
            try expect(ChatThumbWire.isSlug("screen-1") && ChatThumbWire.isSlug("a_b") && !ChatThumbWire.isSlug("a/b") && !ChatThumbWire.isSlug(""), "slug")
            return "range and ids read"
        },
    ]
}
