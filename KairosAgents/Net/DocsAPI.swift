import Foundation

// The desktop's Library documents and chat files, as the phone reads them: one decoder per answer and
// one function per route. Shapes were read from:
//
// - routes/document_routes.py over services/documents_service.py. A document is {id (12 hex), title, tags,
//   created_at, updated_at (epoch seconds)}; one read also has `content`. There is NO revision or hash:
//   PATCH writes whatever it is sent. The phone reads the document just before a save and refuses when a
//   field it is about to send changed on the desktop since the form was filled. DELETE answers {"ok": true}
//   even for a document that is already gone. Search returns at most 5 hits {id, title, snippet}.
// - routes/chat_routes.py over core/chat_files.py: GET /api/chat/files/library is a list of
//   {session_id, title, files: [{id, name, origin ("attachment", "created", "generated"), url, size
//   (null when gone), exists, created_at}]}, one group per model chat that has files.
// - core/chat_artifacts.py: GET /api/chat/artifacts?session_id&url says {filename, extension, size, kind};
//   GET /api/chat/artifacts/content serves the bytes (text and Markdown up to 2 MB, images, PDF).
// - routes/session_routes.py: GET /api/sessions/{id} answers 404 for a chat that is gone.

// MARK: - Documents

/// One Library document. Every field but the id is read leniently.
nonisolated struct DocsDocumentDTO: Decodable, Sendable {
    var id: String
    var title: JSONValue?
    var content: JSONValue?
    var tags: JSONValue?
    var createdAt: JSONValue?
    var updatedAt: JSONValue?
}

/// GET /api/documents: newest first. A row this app cannot read is skipped and counted.
nonisolated struct DocsDocumentListDTO: Decodable, Sendable {
    var documents: [DocsDocumentDTO] = []
    var skipped = 0

    init(from decoder: Decoder) throws {
        var list = try decoder.unkeyedContainer()
        while !list.isAtEnd {
            if let item = try? list.decode(DocsDocumentDTO.self) {
                documents.append(item)
            } else {
                _ = try list.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

/// One hit of GET /api/documents/search. `snippet` is empty for a title match.
nonisolated struct DocsSearchHitDTO: Decodable, Sendable {
    var id: String
    var title: JSONValue?
    var snippet: JSONValue?
}

nonisolated struct DocsSearchDTO: Decodable, Sendable {
    var hits: [DocsSearchHitDTO] = []

    init(from decoder: Decoder) throws {
        var list = try decoder.unkeyedContainer()
        while !list.isAtEnd {
            if let item = try? list.decode(DocsSearchHitDTO.self) {
                hits.append(item)
            } else {
                _ = try list.decode(JSONValue.self)
            }
        }
    }
}

/// DELETE /api/documents/{id}.
nonisolated struct DocsOkDTO: Decodable, Sendable {
    var ok: Bool?
}

// MARK: - Chat files

nonisolated struct DocsChatFileDTO: Decodable, Sendable {
    var id: String
    var name: JSONValue?
    var origin: JSONValue?
    var url: JSONValue?
    var size: JSONValue?
    var exists: JSONValue?
    var createdAt: JSONValue?
}

nonisolated struct DocsChatGroupDTO: Decodable, Sendable {
    var sessionId: String
    var title: String?
    var files: [DocsChatFileDTO] = []
    var skipped = 0

    enum CodingKeys: String, CodingKey { case sessionId, title, files }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try box.decode(String.self, forKey: .sessionId)
        title = try? box.decodeIfPresent(String.self, forKey: .title)
        if var list = try? box.nestedUnkeyedContainer(forKey: .files) {
            while !list.isAtEnd {
                if let item = try? list.decode(DocsChatFileDTO.self) {
                    files.append(item)
                } else {
                    _ = try list.decode(JSONValue.self)
                    skipped += 1
                }
            }
        }
    }
}

/// GET /api/chat/files/library.
nonisolated struct DocsChatLibraryDTO: Decodable, Sendable {
    var groups: [DocsChatGroupDTO] = []
    var skipped = 0

    init(from decoder: Decoder) throws {
        var list = try decoder.unkeyedContainer()
        while !list.isAtEnd {
            if let item = try? list.decode(DocsChatGroupDTO.self) {
                groups.append(item)
                skipped += item.skipped
            } else {
                _ = try list.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

/// GET /api/chat/artifacts (chat_artifacts.py: resolve).
nonisolated struct DocsArtifactDTO: Decodable, Sendable {
    var filename: String?
    var ext: String?
    var size: Double?
    var kind: String?

    enum CodingKeys: String, CodingKey {
        case filename, size, kind
        case ext = "extension"
    }
}

/// GET /api/sessions/{id}: only the id matters here (the chat is still there).
nonisolated struct DocsSessionDTO: Decodable, Sendable {
    var id: String?
}

// MARK: - Wire helpers

/// How the phone can show one chat file, from the desktop's own `kind`.
nonisolated enum DocsFileKind: String, Sendable {
    case image, markdown, text, html, pdf, office, video, audio, download
    /// A kind this app does not know: shown as a plain line, never guessed at.
    case other

    init(wire: String?) {
        self = DocsFileKind(rawValue: wire ?? "") ?? .other
    }
}

nonisolated enum DocsWire {
    /// The 404 sentence the documents routes send.
    static let missingDetail = "document not found"
    /// The desktop's own composer cap, also the most the phone brings over to share.
    static let maxBytes = 25 * 1024 * 1024

    static func time(_ value: JSONValue?) -> Date? {
        guard let seconds = value?.double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// A document id goes into the path as it is. One that could leave the path is refused.
    static func pathID(_ id: String) throws -> String {
        guard !id.isEmpty, id != ".", id != "..",
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else {
            throw APIError.unreadable("id")
        }
        return id
    }

    static func origin(_ value: JSONValue?) -> ChatDocsOrigin {
        switch value?.string {
        case "attachment": return .sent
        case "created": return .created
        case "generated": return .generated
        default: return .other
        }
    }

    static func look(forName name: String) -> ChatDocument.Look {
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic": return .design
        case "xlsx", "xls", "csv", "tsv", "numbers": return .sheet
        default: return .page
        }
    }

    /// The title the desktop gives an imported file (documents_service.py: import_document).
    static func importTitle(_ filename: String) -> String {
        let base = (filename as NSString).lastPathComponent
        return (base as NSString).deletingPathExtension
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/documents
    func docsList() async throws -> DocsDocumentListDTO {
        try await get("/api/documents")
    }

    /// GET /api/documents/{id}: the document with its content.
    func docsGet(_ id: String) async throws -> DocsDocumentDTO {
        try await get("/api/documents/" + DocsWire.pathID(id))
    }

    /// GET /api/documents/search?q= (at most 5 hits).
    func docsSearch(_ query: String) async throws -> DocsSearchDTO {
        try await get("/api/documents/search", query: ["q": query])
    }

    /// POST /api/documents
    func docsCreate(title: String, content: String) async throws -> DocsDocumentDTO {
        try await post("/api/documents", json: ["title": title, "content": content])
    }

    /// POST /api/documents/import: always a new document, titled from the file name.
    func docsImport(filename: String, content: String) async throws -> DocsDocumentDTO {
        try await post("/api/documents/import", json: ["filename": filename, "content": content])
    }

    /// PATCH /api/documents/{id} with only the fields that changed.
    func docsUpdate(_ id: String, title: String?, content: String?) async throws -> DocsDocumentDTO {
        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        if let content { body["content"] = content }
        return try await request("PATCH", "/api/documents/" + DocsWire.pathID(id), json: body)
    }

    /// DELETE /api/documents/{id}
    func docsDelete(_ id: String) async throws -> DocsOkDTO {
        try await request("DELETE", "/api/documents/" + DocsWire.pathID(id))
    }

    /// GET /api/chat/files/library
    func docsChatFiles() async throws -> DocsChatLibraryDTO {
        try await get("/api/chat/files/library")
    }

    /// GET /api/chat/artifacts?session_id&url
    func docsFileInfo(sessionId: String, url: String) async throws -> DocsArtifactDTO {
        try await get("/api/chat/artifacts", query: ["session_id": sessionId, "url": url])
    }

    /// GET /api/chat/artifacts/content. `download` true always sends the original bytes.
    func docsFileBytes(sessionId: String, url: String, download: Bool) async throws -> Data {
        try await bytes("/api/chat/artifacts/content", query: [
            "session_id": sessionId, "url": url, "download": download ? "true" : nil,
        ])
    }

    /// GET /api/sessions/{id}: is this chat still on the desktop.
    func docsChatSession(_ id: String) async throws -> DocsSessionDTO {
        try await get("/api/sessions/" + DocsWire.pathID(id))
    }
}

// MARK: - Samples

/// A sample answer for every route above, shaped like the desktop's own (made-up content).
nonisolated enum DocsSamples {

    static let list = #"""
    [
      {"id": "3f2a9c1b7d04", "title": "Weekly report", "tags": [], "created_at": 1793000000.25, "updated_at": 1793000500.5},
      {"id": "8e41b0c2a9f7", "title": "Launch plan", "tags": ["shop"], "created_at": 1792900000, "updated_at": 1792900000},
      {"title": "A row with no id"}
    ]
    """#

    static let one = #"""
    {"id": "3f2a9c1b7d04", "title": "Weekly report", "tags": [], "created_at": 1793000000.25,
     "updated_at": 1793000500.5, "content": "Sales were up.\r\n\nTwo bikes wait on parts."}
    """#

    static let search = #"""
    [{"id": "8e41b0c2a9f7", "title": "Launch plan", "snippet": ""},
     {"id": "3f2a9c1b7d04", "title": "Weekly report", "snippet": "…Two bikes wait on parts."},
     {"title": "no id"}]
    """#

    static let deleted = #"{"ok": true}"#

    static let missing = #"{"detail": "document not found"}"#

    static let chatFiles = #"""
    [
      {"session_id": "a1b2c3d4e5f60718", "title": "Bike shop launch", "files": [
        {"id": "0123456789abcdef01234567", "name": "Opening hours.txt", "origin": "attachment",
         "url": "/chat-files/0123456789abcdef01234567", "size": 1200, "exists": true, "created_at": 1793000000.5},
        {"id": "89abcdef0123456789abcdef", "name": "Booking page.png", "origin": "generated",
         "url": "/generated-images/booking.png", "size": null, "exists": false, "created_at": 1792990000},
        {"id": "fedcba9876543210fedcba98", "name": "Notes.md", "origin": "teleported",
         "url": "/chat-files/fedcba9876543210fedcba98", "size": 300, "exists": true, "created_at": null},
        {"name": "no id"}
      ]},
      {"title": "A group with no session"}
    ]
    """#

    static let info = #"{"filename": "Opening hours.txt", "extension": "txt", "size": 1200, "kind": "text"}"#

    static let session = #"{"id": "a1b2c3d4e5f60718", "title": "Bike shop launch", "messages": []}"#

    static let checks: [DecodeCheck] = [
        DecodeCheck("docs.list") {
            let read = try KJSON.decode(DocsDocumentListDTO.self, from: DocsSamples.list)
            let one = try KJSON.decode(DocsDocumentDTO.self, from: DocsSamples.one)
            guard read.documents.count == 2, read.skipped == 1,
                  read.documents[0].title?.string == "Weekly report",
                  DocsWire.time(read.documents[1].updatedAt) == Date(timeIntervalSince1970: 1_792_900_000),
                  one.content?.string?.contains("\r\n") == true,
                  (try? DocsWire.pathID(one.id)) != nil, (try? DocsWire.pathID("../x")) == nil else {
                throw SampleMismatch("documents")
            }
            return "2 documents, 1 skipped, content kept as sent"
        },
        DecodeCheck("docs.write") {
            let found = try KJSON.decode(DocsSearchDTO.self, from: DocsSamples.search)
            let gone = try KJSON.decode(DocsOkDTO.self, from: DocsSamples.deleted)
            let refused = try KJSON.decode(APIErrorBody.self, from: DocsSamples.missing)
            guard found.hits.count == 2, found.hits[0].snippet?.string == "",
                  gone.ok == true, refused.text == DocsWire.missingDetail,
                  DocsWire.importTitle("Meeting notes.md") == "Meeting notes" else {
                throw SampleMismatch("search, delete, missing")
            }
            return "search, delete, missing, import title"
        },
        DecodeCheck("docs.chatfiles") {
            let read = try KJSON.decode(DocsChatLibraryDTO.self, from: DocsSamples.chatFiles)
            let info = try KJSON.decode(DocsArtifactDTO.self, from: DocsSamples.info)
            let chat = try KJSON.decode(DocsSessionDTO.self, from: DocsSamples.session)
            guard read.groups.count == 1, read.skipped == 2, read.groups[0].files.count == 3,
                  DocsWire.origin(read.groups[0].files[0].origin) == .sent,
                  DocsWire.origin(read.groups[0].files[2].origin) == .other,
                  read.groups[0].files[1].exists?.bool == false,
                  read.groups[0].files[1].size?.isNull == true,
                  info.ext == "txt", DocsFileKind(wire: info.kind) == .text, DocsFileKind(wire: "hologram") == .other,
                  chat.id == "a1b2c3d4e5f60718" else {
                throw SampleMismatch("chat files")
            }
            let live = DocsLiveStore.liveGroups(read)
            guard live.count == 1, live[0].files[1].available == false, live[0].files[0].bytes == 1200,
                  live[0].files[0].url != nil else { throw SampleMismatch("chat files in screen shape") }
            return "1 group, 2 skipped, origins and gone files"
        },
    ]
}
