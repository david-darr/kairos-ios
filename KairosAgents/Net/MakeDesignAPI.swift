import Foundation

// The desktop's design routes (routes/design_routes.py over core/design_store.py, design_render.py,
// design_tools.py and design_comments.py), as the phone reads them.
//
// - A design id is 12 hex characters, a board is named by its slug, a comment id is 8 hex characters and an
//   element id is the board's own `data-kd` value. The phone keys everything by these, never by an id of its own.
// - No design route takes a revision: the last writer wins. Every write here sends only what changed, and the
//   screen reads the design again after it.
// - A board is drawn by the desktop: GET .../boards/{slug}/render answers a whole HTML page. Its picture links
//   carry a short-lived token, so the page is held in memory for the screen that shows it and nowhere else.
// - Asking a model for a change is a chat send (POST /api/chat/live) to a chat linked to the design. The same
//   `request_id` with the same message starts the turn once (services/chat_live.py: start); with another
//   message it is a 409.

// MARK: - Answers

/// A value that may fail to decode without failing the list or map around it.
nonisolated struct MakeDesignMaybe<Value: Decodable & Sendable>: Decodable, Sendable {
    var value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// One row of GET /api/designs (design_store.summary, plus board_titles and chat_title).
nonisolated struct MakeDesignRowDTO: Decodable, Sendable {
    var id: String
    var title: JSONValue?
    /// How many boards.
    var boards: JSONValue?
    var version: JSONValue?
    var updated: JSONValue?
    var firstBoard: JSONValue?
    var boardTitles: JSONValue?
    var chatTitle: JSONValue?
}

/// One board of a design (design_store._add_board, with the labels design_routes._client adds).
nonisolated struct MakeDesignBoardDTO: Decodable, Sendable {
    var title: JSONValue?
    var w: JSONValue?
    var h: JSONValue?
    var order: JSONValue?
    var format: JSONValue?
    var formatLabel: JSONValue?
    var grows: JSONValue?
    var section: JSONValue?
}

/// A chat linked to a design: {id, title}.
nonisolated struct MakeDesignChatDTO: Decodable, Sendable {
    var id: String
    var title: JSONValue?
}

/// The design's look: its name and its `--ds-*` values, with and without this design's own changes.
nonisolated struct MakeDesignSystemDTO: Decodable, Sendable {
    var name: JSONValue?
    var variables: [String: JSONValue]?
    var defaults: [String: JSONValue]?
}

/// A pinned comment (design_store.add_comment).
nonisolated struct MakeDesignCommentDTO: Decodable, Sendable {
    var id: String
    var board: JSONValue?
    var elementIds: JSONValue?
    var point: JSONValue?
    var text: JSONValue?
    /// "open", "addressed" or "resolved".
    var status: JSONValue?
    var madeOnVersion: JSONValue?
    var addressedIn: JSONValue?
}

/// GET /api/designs/{id}, and the `design` inside most write answers (design_routes._client).
/// `comments` and `render_available` come only with the GET.
nonisolated struct MakeDesignDTO: Decodable, Sendable {
    var id: String
    var title: JSONValue?
    var owner: JSONValue?
    var version: JSONValue?
    var updated: JSONValue?
    var boards: [String: MakeDesignMaybe<MakeDesignBoardDTO>]?
    var order: JSONValue?
    var chats: [MakeDesignMaybe<MakeDesignChatDTO>]?
    var system: MakeDesignMaybe<MakeDesignSystemDTO>?
    var tokenOverrides: JSONValue?
    var comments: [MakeDesignMaybe<MakeDesignCommentDTO>]?
    var renderAvailable: JSONValue?
}

/// One entry of GET /api/designs/{id}/versions (design_store.versions), and the answer to naming one.
nonisolated struct MakeDesignVersionDTO: Decodable, Sendable {
    var n: JSONValue?
    var at: JSONValue?
    var by: JSONValue?
    var tool: JSONValue?
    var summary: JSONValue?
    var name: JSONValue?
}

/// GET /api/designs/{id}/versions/{n}: the entry with the design as it was (`manifest`).
nonisolated struct MakeDesignVersionDetailDTO: Decodable, Sendable {
    nonisolated struct Snapshot: Decodable, Sendable {
        var title: JSONValue?
        var boards: [String: MakeDesignMaybe<MakeDesignBoardDTO>]?
    }

    var n: JSONValue?
    var manifest: Snapshot?
}

/// A write that answers the design: board-action {message, design}, restore and undo {version, design}.
nonisolated struct MakeDesignChangeDTO: Decodable, Sendable {
    var version: JSONValue?
    var message: JSONValue?
    var design: MakeDesignDTO?
}

/// POST .../boards/{slug}/text: {version, changed}.
nonisolated struct MakeDesignTextDTO: Decodable, Sendable {
    var version: JSONValue?
}

/// DELETE answers: {"ok": true}.
nonisolated struct MakeDesignOkDTO: Decodable, Sendable {
    var ok: Bool?
}

/// POST /api/designs/chat: the new chat in Design mode.
nonisolated struct MakeDesignChatStartDTO: Decodable, Sendable {
    var sessionId: String
}

/// GET .../boards/{slug}/html: the board's stored HTML and its outline as text.
nonisolated struct MakeDesignSourceDTO: Decodable, Sendable {
    var html: String
    var outline: String?
}

/// POST /api/designs/{id}/export: {filename, url, size, notes}.
nonisolated struct MakeDesignExportDTO: Decodable, Sendable {
    var filename: JSONValue?
    var notes: JSONValue?
}

/// POST /api/chat/live: the turn that started (or the one this `request_id` started before).
nonisolated struct MakeDesignTurnDTO: Decodable, Sendable {
    var turnId: String?
}

// MARK: - Wire helpers

/// One element of a board, read from the desktop's outline.
nonisolated struct MakeDesignElement: Identifiable, Hashable, Sendable {
    /// The board's own `data-kd` id.
    let id: String
    let tag: String
    /// The start of its text (the outline cuts it at 40 characters), or "".
    let label: String
    /// The outline cut the text short.
    let cut: Bool
    /// It holds other elements, so its text is not edited as one piece.
    let hasChildren: Bool

    var name: String { label.isEmpty ? "\(tag) \(id)" : label }
    var isText: Bool { !hasChildren && !label.isEmpty }
}

/// One selection or pinned comment sent with a message (core/design_comments.py: validate).
nonisolated struct MakeDesignReference: Hashable, Sendable {
    var designID: String
    var board: String
    var elementIDs: [String]
    var pointX: Double?
    var pointY: Double?
    var comment: String
    var commentID: String?
    var label: String

    var json: [String: Any] {
        var out: [String: Any] = [
            "kind": "design_comment", "design_id": designID, "board": board, "element_ids": elementIDs,
            "comment": comment, "label": label,
        ]
        if let pointX, let pointY, elementIDs.isEmpty {
            out["point"] = ["x": pointX, "y": pointY]
        } else {
            out["point"] = NSNull()
        }
        if let commentID { out["comment_id"] = commentID }
        return out
    }
}

nonisolated enum MakeDesignWire {
    /// The sentence the desktop sends when PNG, PDF or PowerPoint cannot be made without its own window.
    static let exportOnDesktop = "Export this from Kairos on your desktop."

    /// An id goes into the path as it is. One that could leave the designs path is refused.
    static func part(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 64, id.unicodeScalars.allSatisfy({ scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
        }) else { throw APIError.unreadable("design id") }
        return id
    }

    static func path(_ id: String, _ rest: String = "") throws -> String {
        "/api/designs/" + (try part(id)) + rest
    }

    static func time(_ value: JSONValue?) -> Date? {
        guard let seconds = value?.double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// The elements of a board from its outline (core/design_html.py: outline, describe). Each line is
    /// two spaces per level, then `id <tag>`, then now and then a detail, then the text in quotes.
    static func elements(outline: String) -> [MakeDesignElement] {
        var rows: [(depth: Int, id: String, tag: String, label: String)] = []
        for line in outline.split(separator: "\n", omittingEmptySubsequences: true) {
            let spaces = line.prefix(while: { $0 == " " }).count
            let text = line.dropFirst(spaces)
            guard let gap = text.firstIndex(of: " ") else { continue }
            let id = String(text[..<gap])
            let rest = text[text.index(after: gap)...]
            guard rest.hasPrefix("<"), let close = rest.firstIndex(of: ">") else { continue }
            let tag = String(rest[rest.index(after: rest.startIndex)..<close])
            let tail = rest[rest.index(after: close)...]
            var label = ""
            if tail.hasSuffix("\""), let open = tail.range(of: " \""), open.upperBound < tail.endIndex {
                label = String(tail[open.upperBound..<tail.index(before: tail.endIndex)])
            }
            rows.append((spaces / 2, id, tag, label))
        }
        var out: [MakeDesignElement] = []
        for (index, row) in rows.enumerated() where isElementID(row.id) {
            let parent = index + 1 < rows.count && rows[index + 1].depth > row.depth
            let cut = row.label.hasSuffix("...")
            out.append(MakeDesignElement(id: row.id, tag: row.tag, label: row.label, cut: cut, hasChildren: parent))
        }
        return out
    }

    /// An element id as the desktop makes them: a letter, then letters, digits and dashes, 32 at most.
    static func isElementID(_ id: String) -> Bool {
        let values = id.unicodeScalars.map(\.value)
        guard let first = values.first, values.count <= 32, first >= 97, first <= 122 else { return false }
        return values.allSatisfy { value in
            (value >= 97 && value <= 122) || (value >= 48 && value <= 57) || value == 45
        }
    }

    /// The whole text of an element that holds no other element, from the board's stored HTML
    /// (core/design_html.py: serialize writes `data-kd="id"`, quoted attributes and escaped text).
    /// Nil when the element is not there or holds another element.
    static func leafText(html: String, id: String) -> String? {
        guard isElementID(id), let mark = html.range(of: " data-kd=\"\(id)\""),
              let open = html[..<mark.lowerBound].lastIndex(of: "<") else { return nil }
        let tag = String(html[html.index(after: open)..<mark.lowerBound].prefix(while: { $0 != " " }))
        var index = mark.upperBound
        var quoted = false
        while index < html.endIndex {
            let character = html[index]
            if character == "\"" { quoted.toggle() }
            if character == ">" && !quoted { break }
            index = html.index(after: index)
        }
        guard index < html.endIndex else { return nil }
        let start = html.index(after: index)
        guard let next = html[start...].firstIndex(of: "<"), html[next...].hasPrefix("</\(tag)>") else { return nil }
        return unescape(String(html[start..<next]))
    }

    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// The desktop sends a board's page with a header that allows nothing but its own styles, fonts and
    /// pictures. A page loaded from text has no header, so the same rule goes into the page itself, with
    /// no script allowed at all (the web view runs none either).
    static func guarded(page: String, origin: String, designID: String) -> String {
        let rule = "default-src 'none'; style-src 'unsafe-inline'; font-src \(origin)/api/design-fonts/; "
            + "img-src data: \(origin)/api/designs/\(designID)/; script-src 'none'; connect-src 'none'; "
            + "form-action 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'"
        let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(rule)\">"
        guard let head = page.range(of: "<head>") else { return meta + page }
        return page.replacingCharacters(in: head, with: "<head>" + meta)
    }

    /// "#2f6f5e" or "#abc" as a number; nil for anything else (a name, a colour with see-through).
    static func hex(_ text: String) -> UInt32? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("#") else { return nil }
        var digits = String(value.dropFirst())
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 else { return nil }
        return UInt32(digits, radix: 16)
    }

    static func hexText(_ value: UInt32) -> String {
        let digits = String(value & 0xFFFFFF, radix: 16)
        return "#" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    /// A value the desktop will take for a token (core/design_systems.py: _safe_value).
    static func isSafeValue(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 200 else { return false }
        let lowered = value.lowercased()
        if lowered.contains("url(") || lowered.contains("expression") || lowered.contains("@import") { return false }
        return !value.contains { ";{}<>\\".contains($0) }
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/designs: the designs this account may see, newest change first.
    func makeDesignList() async throws -> [MakeDesignMaybe<MakeDesignRowDTO>] {
        try await get("/api/designs")
    }

    /// POST /api/designs: a new design with one phone board. It is made at once, with no key to send twice.
    func makeDesignCreate(title: String) async throws -> MakeDesignDTO {
        try await post("/api/designs", json: ["title": title])
    }

    /// GET /api/designs/{id}: the design, its boards, comments, linked chats and look.
    func makeDesignGet(_ id: String) async throws -> MakeDesignDTO {
        try await get(try MakeDesignWire.path(id))
    }

    /// DELETE /api/designs/{id}: the owner or an admin only (403 otherwise). It cannot be undone.
    func makeDesignDelete(_ id: String) async throws -> MakeDesignOkDTO {
        try await request("DELETE", try MakeDesignWire.path(id))
    }

    /// POST /api/designs/{id}/duplicate: a new design from this one, or from one of its versions.
    func makeDesignDuplicate(_ id: String, version: Int?) async throws -> MakeDesignDTO {
        var body: [String: Any] = [:]
        if let version { body["version"] = version }
        return try await post(try MakeDesignWire.path(id, "/duplicate"), json: body)
    }

    /// POST /api/designs/chat: a new chat in Design mode, linked to the design when one is named.
    func makeDesignChatStart(designID: String?, title: String) async throws -> MakeDesignChatStartDTO {
        var body: [String: Any] = ["title": title]
        if let designID { body["design_id"] = try MakeDesignWire.part(designID) }
        return try await post("/api/designs/chat", json: body)
    }

    /// POST /api/designs/{id}/link: let one of the person's chats change this design.
    func makeDesignLink(_ id: String, sessionID: String) async throws -> MakeDesignDTO {
        try await post(try MakeDesignWire.path(id, "/link"), json: ["session_id": sessionID])
    }

    /// GET /api/designs/{id}/boards/{slug}/render: the board as a whole page, now or as it was at a version.
    /// The page's picture links carry a short-lived token: show the page, never keep or log it.
    func makeDesignRender(_ id: String, board: String, version: Int?) async throws -> Data {
        let path = try MakeDesignWire.path(id, "/boards/" + MakeDesignWire.part(board) + "/render")
        return try await bytes(path, query: ["v": version.map { String($0) }])
    }

    /// GET /api/designs/{id}/boards/{slug}/html: the stored HTML and outline, for picking and editing elements.
    func makeDesignSource(_ id: String, board: String) async throws -> MakeDesignSourceDTO {
        try await get(try MakeDesignWire.path(id, "/boards/" + MakeDesignWire.part(board) + "/html"))
    }

    /// POST /api/designs/{id}/board-action with "reorder": the board's new place, 1 for first.
    func makeDesignReorder(_ id: String, board: String, place: Int) async throws -> MakeDesignChangeDTO {
        try await post(try MakeDesignWire.path(id, "/board-action"),
                       json: ["action": "reorder", "board": try MakeDesignWire.part(board), "order": place])
    }

    /// POST /api/designs/{id}/boards/{slug}/text: set one element's text. No model is involved.
    func makeDesignSetText(_ id: String, board: String, element: String, text: String) async throws -> MakeDesignTextDTO {
        try await post(try MakeDesignWire.path(id, "/boards/" + MakeDesignWire.part(board) + "/text"),
                       json: ["id": element, "text": text])
    }

    /// POST /api/designs/{id}/tokens: change only the named values, or clear every change this design made.
    /// `save_to_system` is never sent from the phone.
    func makeDesignTokens(_ id: String, set values: [String: String], clear: Bool) async throws -> MakeDesignDTO {
        var body: [String: Any] = [:]
        if !values.isEmpty { body["set"] = values }
        if clear { body["clear"] = true }
        return try await post(try MakeDesignWire.path(id, "/tokens"), json: body)
    }

    /// GET /api/designs/{id}/versions: newest first.
    func makeDesignVersions(_ id: String) async throws -> [MakeDesignMaybe<MakeDesignVersionDTO>] {
        try await get(try MakeDesignWire.path(id, "/versions"))
    }

    /// GET /api/designs/{id}/versions/{n}: the design as it was then.
    func makeDesignVersion(_ id: String, number: Int) async throws -> MakeDesignVersionDetailDTO {
        try await get(try MakeDesignWire.path(id, "/versions/\(number)"))
    }

    /// POST /api/designs/{id}/versions/{n}/restore: version n again, as a new version.
    func makeDesignRestore(_ id: String, number: Int) async throws -> MakeDesignChangeDTO {
        try await post(try MakeDesignWire.path(id, "/versions/\(number)/restore"))
    }

    /// POST /api/designs/{id}/versions/{n}/name: a name keeps the version; null removes the name.
    func makeDesignNameVersion(_ id: String, number: Int, name: String?) async throws -> MakeDesignVersionDTO {
        var body: [String: Any] = ["name": NSNull()]
        if let name { body["name"] = name }
        return try await post(try MakeDesignWire.path(id, "/versions/\(number)/name"), json: body)
    }

    /// POST /api/designs/{id}/undo: step back over the person's own latest direct edit (409 when there is none).
    func makeDesignUndo(_ id: String) async throws -> MakeDesignChangeDTO {
        try await post(try MakeDesignWire.path(id, "/undo"))
    }

    /// POST /api/designs/{id}/comments: pin a comment to elements, or to a point as fractions of the board.
    func makeDesignCommentAdd(_ id: String, board: String, elementIDs: [String], point: CGPoint?, text: String) async throws -> MakeDesignCommentDTO {
        var body: [String: Any] = ["board": board, "element_ids": elementIDs, "text": text]
        if let point { body["point"] = ["x": Double(point.x), "y": Double(point.y)] }
        return try await post(try MakeDesignWire.path(id, "/comments"), json: body)
    }

    /// PATCH /api/designs/{id}/comments/{comment}: only its status ("open" or "resolved") is sent.
    func makeDesignCommentStatus(_ id: String, comment: String, status: String) async throws -> MakeDesignCommentDTO {
        try await request("PATCH", try MakeDesignWire.path(id, "/comments/" + MakeDesignWire.part(comment)), json: ["status": status])
    }

    /// DELETE /api/designs/{id}/comments/{comment}.
    func makeDesignCommentDelete(_ id: String, comment: String) async throws -> MakeDesignOkDTO {
        try await request("DELETE", try MakeDesignWire.path(id, "/comments/" + MakeDesignWire.part(comment)))
    }

    /// POST /api/designs/{id}/export. "html" works anywhere; "png", "pdf" and "pptx" answer 503 unless the
    /// desktop app's own window is open. With a chat named, the file joins that chat's files.
    func makeDesignExport(_ id: String, format: String, sessionID: String?) async throws -> MakeDesignExportDTO {
        var body: [String: Any] = ["format": format]
        if let sessionID { body["session_id"] = sessionID }
        return try await post(try MakeDesignWire.path(id, "/export"), json: body)
    }

    /// POST /api/chat/live with the design's selections and comments as references. The same `requestID`
    /// with the same message and references starts the turn once.
    func makeDesignSend(sessionID: String, message: String, references: [MakeDesignReference], requestID: String) async throws -> MakeDesignTurnDTO {
        try await post("/api/chat/live", json: [
            "session_id": sessionID,
            "message": message,
            "attachment_ids": [String](),
            "references": references.map(\.json),
            "request_id": requestID,
        ])
    }
}

// MARK: - Samples

/// A sample answer for every design route, shaped like the desktop's own (made-up content).
nonisolated enum MakeDesignSamples {

    static let list = #"""
    [
      {"id": "3f2a9c1b7d04", "title": "Booking page", "owner": "alex", "boards": 3, "version": 7, "updated": 1793000100.5,
       "created": 1792900000.0, "chat_ids": ["c1"], "design_system": "kairos", "first_board": "home", "source": null,
       "board_titles": ["Home", "Book a service", "Phone home"], "chat_title": "Bike shop website"},
      {"id": "8e41b0c2a9f7", "title": "Shop poster", "owner": "alex", "boards": 1, "version": 1, "updated": 1792950000,
       "created": 1792950000, "chat_ids": [], "design_system": "kairos", "first_board": "screen-1", "source": null,
       "board_titles": ["Screen 1"], "chat_title": null},
      {"title": "A row with no id"},
      "not a row"
    ]
    """#

    static let design = #"""
    {"id": "3f2a9c1b7d04", "title": "Booking page", "owner": "alex", "version": 7, "updated": 1793000100.5,
     "created": 1792900000.0, "chat_ids": ["c1"], "design_system": "kairos", "first_board": "home", "source": null,
     "boards": {
       "home": {"title": "Home", "x": 0, "y": 0, "w": 1440, "h": 2210, "frame": "browser", "order": 1, "format": "website",
                "size": "desktop", "orientation": null, "min_h": 900, "content_h": 2210, "format_label": "Website · Desktop",
                "ratio": null, "grows": true, "section": "website:desktop"},
       "phone-home": {"title": "Phone home", "x": 0, "y": 2400, "w": 390, "h": 844, "frame": "phone", "order": 2,
                      "format": "app", "size": "phone", "orientation": "portrait", "format_label": "App · Phone",
                      "ratio": 0.4621, "grows": false, "section": "app:phone"},
       "odd": "not a board"
     },
     "notes": [], "token_overrides": {"--ds-accent": "#2f6f5e"}, "order": ["home", "phone-home"], "layout": "auto",
     "sections": [{"key": "website:desktop", "label": "Website · Desktop", "x": 0, "y": -40}], "formats": [],
     "chats": [{"id": "c1", "title": "Bike shop website"}, {"title": "no id"}],
     "system": {"id": "kairos", "name": "Kairos",
                "variables": {"--ds-bg": "#F3EADB", "--ds-accent": "#2f6f5e", "--ds-radius-2": "12px"},
                "defaults": {"--ds-bg": "#F3EADB", "--ds-accent": "#B8893B", "--ds-radius-2": "12px"}},
     "comments": [
       {"id": "a1b2c3d4", "board": "home", "element_ids": ["h1"], "point": null, "text": "Make the headline shorter.",
        "author": "alex", "status": "addressed", "made_on_version": 4, "addressed_in": 6, "created": 1792990000.1, "note": null},
       {"id": "e5f6a7b8", "board": "phone-home", "element_ids": [], "point": {"x": 0.5, "y": 0.82},
        "text": "Make this button easier to reach.", "author": "alex", "status": "open", "made_on_version": 7,
        "addressed_in": null, "created": 1793000000.0, "note": null},
       {"text": "a comment with no id"}
     ],
     "render_available": false}
    """#

    static let versions = #"""
    [
      {"n": 7, "at": 1793000100.5, "by": "You", "tool": "text_edit", "summary": "Edited text on Home",
       "boards_changed": ["home"], "changed_ids": {"home": ["h1"]}, "files": ["home"], "session_id": null,
       "user_edit": true, "name": null, "pinned": false, "exported": false},
      {"n": 6, "at": 1792995000.0, "by": "Kairos", "tool": "design_edit", "summary": "Shortened the headline",
       "boards_changed": ["home"], "changed_ids": {}, "files": ["home"], "session_id": "c1", "user_edit": false,
       "name": "Before the sale", "pinned": true, "exported": false},
      7
    ]
    """#

    static let version = #"""
    {"n": 6, "at": 1792995000.0, "by": "Kairos", "tool": "design_edit", "summary": "Shortened the headline",
     "manifest": {"title": "Booking page", "design_system": "kairos", "token_overrides": {}, "layout": "auto", "notes": [],
                  "boards": {"home": {"title": "Home", "x": 0, "y": 0, "w": 1440, "h": 1800, "frame": "browser",
                                      "order": 1, "format": "website", "size": "desktop", "orientation": null}}}}
    """#

    static let change = #"""
    {"version": 8, "design": {"id": "3f2a9c1b7d04", "title": "Booking page", "version": 8,
     "boards": {"home": {"title": "Home", "w": 1440, "h": 2210, "order": 2}, "phone-home": {"title": "Phone home", "w": 390, "h": 844, "order": 1}},
     "order": ["phone-home", "home"], "chats": [], "token_overrides": {}}}
    """#

    static let moved = #"""
    {"message": "Version 8: Moved home to position 2", "design": {"id": "3f2a9c1b7d04", "version": 8, "boards": {}, "order": []}}
    """#

    static let text = #"{"version": 9, "changed": {"home": ["h1"]}}"#

    static let comment = #"""
    {"id": "0c1d2e3f", "board": "home", "element_ids": ["btn2"], "point": null, "text": "Use the accent colour here.",
     "author": "alex", "status": "open", "made_on_version": 9, "addressed_in": null, "created": 1793000200.0, "note": null}
    """#

    static let ok = #"{"ok": true}"#

    static let chat = #"{"session_id": "5b9e2f0a4c18d7e6"}"#

    static let export = #"{"filename": "booking-page.zip", "url": "/generated-files/0a1b2c3d4e5f_booking-page.zip", "size": 18234, "notes": []}"#

    static let turn = #"{"turn_id": "9f8e7d6c5b4a39281706f5e4d3c2b1a0"}"#

    static let needsApp = #"{"detail": "PNG, PDF, PPTX and snapshots need the Kairos desktop app, which renders boards in its own window. The HTML zip export works anywhere."}"#

    static let source = #"""
    {"html": "<main data-kd=\"main\" style=\"padding: 24px\"><h1 data-kd=\"h1\" title=\"a > b\">Tune-ups &amp; repairs that keep you rolling all year</h1><p data-kd=\"p1\">Same-week service. <b data-kd=\"s1\">Free</b> safety check.</p><a data-kd=\"btn2\" data-kd-goto=\"book\">Book a service</a><img data-kd=\"img1\" alt=\"A bike\" src=\"assets/0000000000000000000000000000000000000000000000000000000000000000.png\"></main>",
     "outline": "main <main> \"Tune-ups & repairs that keep you rolling a...\"\n  h1 <h1> \"Tune-ups & repairs that keep you rolling a...\"\n  p1 <p> \"Same-week service. Free safety check.\"\n    s1 <b> \"Free\"\n  btn2 <a> goto=book \"Book a service\"\n  img1 <img> alt=\"A bike\"\n  <style> (120 characters of CSS)\n  - <div> \"No id\""}
    """#

    static let page = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Home</title></head><body>Home</body></html>"

    static let checks: [DecodeCheck] = [
        DecodeCheck("makedesign.list") {
            let read = try KJSON.decode([MakeDesignMaybe<MakeDesignRowDTO>].self, from: MakeDesignSamples.list)
            let rows = read.compactMap(\.value)
            guard read.count == 4, rows.count == 2, rows[0].id == "3f2a9c1b7d04", rows[0].boards?.int == 3,
                  rows[0].chatTitle?.string == "Bike shop website", rows[1].chatTitle?.string == nil,
                  rows[0].firstBoard?.string == "home", MakeDesignWire.time(rows[1].updated) != nil else {
                throw SampleMismatch("list fields")
            }
            return "2 designs, 2 skipped"
        },
        DecodeCheck("makedesign.design") {
            let read = try KJSON.decode(MakeDesignDTO.self, from: MakeDesignSamples.design)
            let boards = read.boards ?? [:]
            let comments = (read.comments ?? []).compactMap(\.value)
            let chats = (read.chats ?? []).compactMap(\.value)
            guard read.id == "3f2a9c1b7d04", read.version?.int == 7, boards.count == 3, boards["odd"]?.value == nil,
                  boards["phone-home"]?.value?.w?.double == 390, boards["home"]?.value?.grows?.bool == true,
                  boards["home"]?.value?.formatLabel?.string == "Website · Desktop",
                  read.order?.array?.compactMap(\.string) == ["home", "phone-home"],
                  chats.count == 1, chats[0].id == "c1", comments.count == 2, comments[1].point?["y"]?.double == 0.82,
                  comments[0].addressedIn?.int == 6, comments[0].elementIds?.array?.first?.string == "h1",
                  read.system?.value?.variables?["--ds-accent"]?.string == "#2f6f5e",
                  read.system?.value?.defaults?["--ds-accent"]?.string == "#B8893B",
                  read.tokenOverrides?["--ds-accent"]?.string == "#2f6f5e", read.renderAvailable?.bool == false else {
                throw SampleMismatch("design fields")
            }
            return "2 boards, 2 comments, 1 chat, look"
        },
        DecodeCheck("makedesign.versions") {
            let read = try KJSON.decode([MakeDesignMaybe<MakeDesignVersionDTO>].self, from: MakeDesignSamples.versions)
            let rows = read.compactMap(\.value)
            let detail = try KJSON.decode(MakeDesignVersionDetailDTO.self, from: MakeDesignSamples.version)
            guard read.count == 3, rows.count == 2, rows[0].n?.int == 7, rows[0].by?.string == "You",
                  rows[1].name?.string == "Before the sale", rows[0].name?.string == nil,
                  detail.n?.int == 6, detail.manifest?.boards?["home"]?.value?.h?.double == 1800 else {
                throw SampleMismatch("version fields")
            }
            return "2 versions, 1 skipped, snapshot"
        },
        DecodeCheck("makedesign.writes") {
            let change = try KJSON.decode(MakeDesignChangeDTO.self, from: MakeDesignSamples.change)
            let moved = try KJSON.decode(MakeDesignChangeDTO.self, from: MakeDesignSamples.moved)
            let text = try KJSON.decode(MakeDesignTextDTO.self, from: MakeDesignSamples.text)
            let comment = try KJSON.decode(MakeDesignCommentDTO.self, from: MakeDesignSamples.comment)
            let gone = try KJSON.decode(MakeDesignOkDTO.self, from: MakeDesignSamples.ok)
            let chat = try KJSON.decode(MakeDesignChatStartDTO.self, from: MakeDesignSamples.chat)
            let export = try KJSON.decode(MakeDesignExportDTO.self, from: MakeDesignSamples.export)
            let turn = try KJSON.decode(MakeDesignTurnDTO.self, from: MakeDesignSamples.turn)
            let refused = try KJSON.decode(APIErrorBody.self, from: MakeDesignSamples.needsApp)
            guard change.version?.int == 8, change.design?.order?.array?.first?.string == "phone-home",
                  moved.message?.string != nil, moved.design?.id == "3f2a9c1b7d04", text.version?.int == 9,
                  comment.id == "0c1d2e3f", comment.status?.string == "open", gone.ok == true,
                  chat.sessionId == "5b9e2f0a4c18d7e6", export.filename?.string == "booking-page.zip",
                  turn.turnId?.count == 32, refused.text.hasPrefix("PNG, PDF") else {
                throw SampleMismatch("write fields")
            }
            return "change, move, text, comment, delete, chat, export, turn"
        },
        DecodeCheck("makedesign.elements") {
            let read = try KJSON.decode(MakeDesignSourceDTO.self, from: MakeDesignSamples.source)
            let elements = MakeDesignWire.elements(outline: read.outline ?? "")
            let byID = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard elements.map(\.id) == ["main", "h1", "p1", "s1", "btn2", "img1"],
                  byID["main"]?.hasChildren == true, byID["h1"]?.isText == true, byID["h1"]?.cut == true,
                  byID["p1"]?.hasChildren == true, byID["p1"]?.isText == false, byID["btn2"]?.label == "Book a service",
                  byID["img1"]?.label == "", byID["img1"]?.isText == false,
                  MakeDesignWire.leafText(html: read.html, id: "h1") == "Tune-ups & repairs that keep you rolling all year",
                  MakeDesignWire.leafText(html: read.html, id: "btn2") == "Book a service",
                  MakeDesignWire.leafText(html: read.html, id: "p1") == nil,
                  MakeDesignWire.leafText(html: read.html, id: "img1") == nil,
                  MakeDesignWire.leafText(html: read.html, id: "nope") == nil else {
                throw SampleMismatch("outline or element text")
            }
            return "6 elements, whole text of 2, 3 refused"
        },
        DecodeCheck("makedesign.wire") {
            let guarded = MakeDesignWire.guarded(page: MakeDesignSamples.page, origin: "https://desk.example.com", designID: "3f2a9c1b7d04")
            let reference = MakeDesignReference(designID: "3f2a9c1b7d04", board: "home", elementIDs: [], pointX: 0.5, pointY: 0.25,
                                                comment: "Move this up.", commentID: "e5f6a7b8", label: "Home · Move this up.")
            let picked = MakeDesignReference(designID: "3f2a9c1b7d04", board: "home", elementIDs: ["h1"], pointX: 0.5, pointY: 0.25,
                                             comment: "", commentID: nil, label: "Home · Headline")
            guard guarded.contains("<head><meta http-equiv=\"Content-Security-Policy\""), guarded.contains("script-src 'none'"),
                  guarded.contains("img-src data: https://desk.example.com/api/designs/3f2a9c1b7d04/;"),
                  MakeDesignWire.guarded(page: "plain", origin: "https://desk.example.com", designID: "x").hasSuffix("plain"),
                  JSONSerialization.isValidJSONObject(reference.json), (reference.json["point"] as? [String: Double])?["y"] == 0.25,
                  reference.json["comment_id"] as? String == "e5f6a7b8", picked.json["point"] is NSNull,
                  picked.json["comment_id"] == nil, picked.json["kind"] as? String == "design_comment",
                  MakeDesignWire.hex("#2f6f5e") == 0x2F6F5E, MakeDesignWire.hex("#abc") == 0xAABBCC,
                  MakeDesignWire.hex("rgb(1,2,3)") == nil, MakeDesignWire.hex("#2f6f5e80") == nil,
                  MakeDesignWire.hexText(0x00A0FF) == "#00a0ff", MakeDesignWire.isSafeValue("14px"),
                  !MakeDesignWire.isSafeValue("red; x"), !MakeDesignWire.isSafeValue("url(x)"), !MakeDesignWire.isSafeValue(""),
                  (try? MakeDesignWire.path("3f2a9c1b7d04", "/undo")) == "/api/designs/3f2a9c1b7d04/undo",
                  (try? MakeDesignWire.part("../x")) == nil, (try? MakeDesignWire.part("phone-home")) != nil,
                  MakeDesignWire.isElementID("btn2"), !MakeDesignWire.isElementID("-"), !MakeDesignWire.isElementID("H1") else {
                throw SampleMismatch("page rule, reference, colour or path")
            }
            return "page rule, 2 references, colours, paths"
        },
    ]
}
