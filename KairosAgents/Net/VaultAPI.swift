import Foundation

// The desktop's vault routes (routes/vault_routes.py), as the phone reads them: one decoder per answer
// and one function per route. Shapes were read from core/vault_graph.py and core/vault_library.py.
//
// - Paths are vault-relative with forward slashes and end in ".md" ("Projects/Launch plan.md").
// - Times are epoch seconds (Double).
// - The graph is decoded WITHOUT the snake_case conversion: its `frontmatter` keys are the note's own
//   property names and must arrive as written. Every other answer uses the shared decoder.

// MARK: - Graph

/// GET /api/vault/graph (vault_graph.py: _build). Every folder and note, every link between notes,
/// and every link to a note that does not exist. No note text: one call, cheap enough for thousands.
nonisolated struct VaultGraphDTO: Decodable, Sendable {
    var nodes: [VaultGraphNodeDTO]?
    var edges: [VaultGraphEdgeDTO]?
    var missing: [VaultGraphMissingDTO]?
}

/// A folder (`type` "folder", `id` "" for the vault root) or a note (`type` "note", `id` its path).
nonisolated struct VaultGraphNodeDTO: Decodable, Sendable {
    var id: String
    var type: String?
    var name: String?
    /// The note's folder ("" at the root). Notes only.
    var folder: String?
    var mtime: Double?
    var size: Int?
    /// The name is a date (YYYY-MM-DD).
    var daily: Bool?
    /// status, project, type and tags first, then a few short extras. A value is text or a list of text.
    var frontmatter: [String: JSONValue]?
    var hasFrontmatter: Bool?
    var words: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, name, folder, mtime, size, daily, frontmatter, words
        case hasFrontmatter = "has_frontmatter"
    }
}

/// `kind` "contains" (folder to child) or "link" (note to note).
nonisolated struct VaultGraphEdgeDTO: Decodable, Sendable {
    var source: String
    var target: String
    var kind: String?
}

/// A `[[link]]` whose target is not in the vault. `target` is the text as written.
nonisolated struct VaultGraphMissingDTO: Decodable, Sendable {
    var source: String
    var target: String
}

// MARK: - One note

/// GET /api/vault/note?path= (vault_routes.py: get_vault_note over vault_graph.read_vault_note_full),
/// and the body of a save (POST /api/vault/note answers `{ok: true, ...the same fields}` without links).
nonisolated struct VaultNoteDTO: Decodable, Sendable {
    var ok: Bool?
    var path: String?
    /// The whole file, properties block included, with LF line endings.
    var content: String?
    /// SHA-1 of the bytes on disk. Sent back on save; a different one on disk means a conflict.
    var version: String?
    var mtime: Double?
    var size: Int?
    var editable: Bool?
    var canEdit: Bool?
    var lineEnding: String?
    var bom: Bool?
    var links: [VaultNoteLinkDTO]?
    var backlinks: [VaultBacklinkDTO]?
    var lastChange: VaultLastChangeDTO?
}

/// One `[[link]]` in the note (vault_graph.py: resolve_links). `id` is the target's path when found.
nonisolated struct VaultNoteLinkDTO: Decodable, Sendable {
    var raw: String?
    var target: String?
    var heading: String?
    var alias: String?
    var embed: Bool?
    /// "note", "missing", or another kind the desktop resolves (an attachment).
    var kind: String?
    var id: String?
}

/// A note that links here, with the line it links from (vault_graph.py: backlink_contexts).
nonisolated struct VaultBacklinkDTO: Decodable, Sendable {
    var id: String
    var snippet: String?
}

/// Who last changed the note, in the desktop's own words (vault_library.py: last_change).
nonisolated struct VaultLastChangeDTO: Decodable, Sendable {
    var when: Double?
    var label: String?
    var kairos: Bool?
}

// MARK: - Search, related, pins, activity

/// GET /api/vault/search?q= . Matched words in `snippet` sit between `mark[0]` and `mark[1]`.
nonisolated struct VaultSearchDTO: Decodable, Sendable {
    var query: String?
    var mark: [String]?
    var results: [VaultFoundDTO]?
}

/// One search or related hit (vault_library.py: search, related).
nonisolated struct VaultFoundDTO: Decodable, Sendable {
    var path: String
    var title: String?
    var snippet: String?
}

/// GET /api/vault/related?path= : notes sharing the most distinctive words, not already linked.
nonisolated struct VaultRelatedDTO: Decodable, Sendable {
    var path: String?
    var results: [VaultFoundDTO]?
}

/// GET and PUT /api/vault/pins: the signed-in person's pinned note paths, in order.
nonisolated struct VaultPinsDTO: Decodable, Sendable {
    var pins: [String]?
}

/// GET /api/vault/activity (no path): the most recently changed notes (vault_library.py: recent_changes).
nonisolated struct VaultActivityDTO: Decodable, Sendable {
    var recent: [VaultRecentDTO]?
}

nonisolated struct VaultRecentDTO: Decodable, Sendable {
    var path: String
    var name: String?
    var when: Double?
    /// "outside", or where a Kairos change came from.
    var source: String?
    var label: String?
    var eventId: String?
    var kairos: Bool?
}

// MARK: - Daily note

/// GET /api/vault/daily: where today's note goes and whether it exists.
nonisolated struct VaultDailyDTO: Decodable, Sendable {
    var date: String?
    var path: String?
    var exists: Bool?
    var folder: String?
    var template: String?
    var templateExists: Bool?
    var canCreate: Bool?
}

/// POST /api/vault/daily: today's note made from the template (or found). `index` is the one line it
/// would add to the folder's index note, offered and applied only on a tap.
nonisolated struct VaultDailyMadeDTO: Decodable, Sendable {
    var path: String?
    var created: Bool?
    var index: VaultIndexProposalDTO?
}

/// vault_graph.py: index_proposal. `content` is the whole index with `line` added; save it with `version`.
nonisolated struct VaultIndexProposalDTO: Decodable, Hashable, Sendable {
    var path: String
    var version: String?
    var line: String?
    var after: String?
    var content: String?
}

// MARK: - Calls

/// How a save ended.
nonisolated enum VaultSaveOutcome: Equatable, Sendable {
    case saved
    /// The note on disk is not the one that was opened (409 version_conflict).
    case conflict
    case failed(String)
}

nonisolated enum VaultWire {
    /// The graph keeps its property names as written (see the note at the top of this file).
    static func graph(_ data: Data) throws -> VaultGraphDTO {
        try JSONDecoder().decode(VaultGraphDTO.self, from: data)
    }

    /// The desktop's conflict sentence (vault_routes.py: post_vault_note).
    static let conflictDetail = "This note changed since you opened it."

    static func path(forID id: String) -> String { id + ".md" }

    static func id(forPath path: String) -> String {
        let clean = path.replacingOccurrences(of: "\\", with: "/")
        return clean.lowercased().hasSuffix(".md") ? String(clean.dropLast(3)) : clean
    }

    /// A frontmatter value as one line of text: a list is joined with commas.
    static func text(_ value: JSONValue) -> String? {
        if let text = value.string { return text }
        if let list = value.array { return list.compactMap(\.string).joined(separator: ", ") }
        if let number = value.double { return number == number.rounded() ? String(Int(number)) : String(number) }
        if let flag = value.bool { return flag ? "true" : "false" }
        return nil
    }
}

extension APIClient {

    /// GET /api/vault/graph
    func vaultGraph() async throws -> VaultGraphDTO {
        let data = try await bytes("/api/vault/graph")
        do {
            return try VaultWire.graph(data)
        } catch {
            throw APIError.unreadable(String(describing: error))
        }
    }

    /// GET /api/vault/note?path=
    func vaultNote(path: String) async throws -> VaultNoteDTO {
        try await get("/api/vault/note", query: ["path": path])
    }

    /// POST /api/vault/note with the version the note was opened at. A 409 whose detail is the
    /// conflict sentence means the file changed on the desktop since.
    func vaultSave(path: String, content: String, version: String, allowRemoveProperties: Bool) async throws -> VaultNoteDTO {
        try await post("/api/vault/note", json: [
            "path": path, "content": content, "version": version,
            "allow_remove_properties": allowRemoveProperties,
        ])
    }

    /// GET /api/vault/search?q=
    func vaultSearch(_ query: String) async throws -> VaultSearchDTO {
        try await get("/api/vault/search", query: ["q": query])
    }

    /// GET /api/vault/related?path=
    func vaultRelated(path: String) async throws -> VaultRelatedDTO {
        try await get("/api/vault/related", query: ["path": path])
    }

    /// GET /api/vault/pins
    func vaultPins() async throws -> VaultPinsDTO {
        try await get("/api/vault/pins")
    }

    /// PUT /api/vault/pins: the whole list, in order. Answers the list as stored.
    func vaultSetPins(_ paths: [String]) async throws -> VaultPinsDTO {
        try await request("PUT", "/api/vault/pins", json: ["pins": paths])
    }

    /// GET /api/vault/activity
    func vaultActivity() async throws -> VaultActivityDTO {
        try await get("/api/vault/activity")
    }

    /// GET /api/vault/daily
    func vaultDaily() async throws -> VaultDailyDTO {
        try await get("/api/vault/daily")
    }

    /// POST /api/vault/daily
    func vaultMakeDaily() async throws -> VaultDailyMadeDTO {
        try await post("/api/vault/daily")
    }
}

// MARK: - Samples

/// A sample answer for every vault route, shaped like the desktop's own (made-up content).
nonisolated enum VaultSamples {

    static let graph = #"""
    {
      "nodes": [
        {"id": "", "type": "folder", "name": "Vault"},
        {"id": "Projects", "type": "folder", "name": "Projects"},
        {"id": "Home.md", "type": "note", "name": "Home", "folder": "", "mtime": 1793000000.125, "size": 220,
         "daily": false, "has_frontmatter": false, "words": 31},
        {"id": "Projects/Launch plan.md", "type": "note", "name": "Launch plan", "folder": "Projects",
         "mtime": 1793100000.5, "size": 812, "daily": false,
         "frontmatter": {"status": "active", "project": "Bike shop", "tags": ["launch", "spring"], "due_date": "2027-03-01"},
         "has_frontmatter": true, "words": 140}
      ],
      "edges": [
        {"source": "", "target": "Projects", "kind": "contains"},
        {"source": "", "target": "Home.md", "kind": "contains"},
        {"source": "Projects", "target": "Projects/Launch plan.md", "kind": "contains"},
        {"source": "Home.md", "target": "Projects/Launch plan.md", "kind": "link"}
      ],
      "missing": [{"source": "Projects/Launch plan.md", "target": "Supplier list"}]
    }
    """#

    static let note = #"""
    {
      "path": "Projects/Launch plan.md",
      "content": "---\nstatus: active\nproject: Bike shop\n---\n# Launch plan\n\nSee [[Home]] and [[Supplier list]].\n",
      "version": "3f786850e387550fdab836ed7e6dc881de23001b", "mtime": 1793100000.5, "size": 812,
      "editable": true, "line_ending": "lf", "bom": false,
      "links": [
        {"raw": "Home", "target": "Home", "heading": "", "alias": "", "embed": false, "kind": "note", "id": "Home.md"},
        {"raw": "Supplier list", "target": "Supplier list", "heading": "", "alias": "", "embed": false, "kind": "missing", "id": null}
      ],
      "backlinks": [{"id": "Home.md", "snippet": "Start with the [[Launch plan]]."}],
      "can_edit": true,
      "last_change": {"when": 1793100000.5, "label": "Edited outside Kairos", "kairos": false}
    }
    """#

    static let saved = #"""
    {"ok": true, "path": "Projects/Launch plan.md", "content": "# Launch plan\n", "version": "89e6c98d92887913cadf06b2adb97f26cde4849b",
     "mtime": 1793100100.0, "size": 15, "editable": true, "line_ending": "lf", "bom": false}
    """#

    static let conflict = #"""
    {"detail": "This note changed since you opened it.", "code": "version_conflict", "current_version": "89e6c98d92887913cadf06b2adb97f26cde4849b"}
    """#

    static let search = "{\"query\": \"price\", \"mark\": [\"\u{E000}\", \"\u{E001}\"], \"results\": [{\"path\": \"Projects/Launch plan.md\", \"title\": \"Launch plan\", \"snippet\": \"Check the \u{E000}price\u{E001} list before Friday.\"}]}"

    static let related = #"""
    {"path": "Projects/Launch plan.md", "results": [{"path": "Ideas/Spring sale.md", "title": "Spring sale", "snippet": "Bikes and tyres"}]}
    """#

    static let pins = #"{"pins": ["Projects/Launch plan.md", "Home.md"]}"#

    static let activity = #"""
    {"recent": [{"path": "Projects/Launch plan.md", "name": "Launch plan", "when": 1793100000.5, "source": "outside",
                 "label": "Edited outside Kairos", "event_id": null, "kairos": false}]}
    """#

    static let daily = #"""
    {"date": "2027-01-04", "path": "Daily notes/2027-01-04.md", "exists": false, "folder": "Daily notes",
     "template": "Daily notes/Daily note template.md", "template_exists": true, "can_create": true}
    """#

    static let dailyMade = #"""
    {"path": "Daily notes/2027-01-04.md", "created": true,
     "index": {"path": "Daily notes/Daily notes.md", "version": "da39a3ee5e6b4b0d3255bfef95601890afd80709",
               "line": "- [[2027-01-04]]: daily session log.", "after": "- [[2027-01-03]]: daily session log.",
               "content": "# Daily notes\n- [[2027-01-03]]: daily session log.\n- [[2027-01-04]]: daily session log.\n"}}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("vault.graph") {
            let decoded = try VaultWire.graph(Data(VaultSamples.graph.utf8))
            let notes = (decoded.nodes ?? []).filter { $0.type == "note" }
            guard notes.count == 2, let plan = notes.last, plan.hasFrontmatter == true,
                  plan.frontmatter?["due_date"] != nil,
                  VaultWire.text(plan.frontmatter?["tags"] ?? .null) == "launch, spring",
                  (decoded.edges ?? []).filter({ $0.kind == "link" }).count == 1,
                  decoded.missing?.first?.target == "Supplier list" else { throw SampleMismatch("graph fields") }
            return "\(notes.count) notes, property names kept"
        },
        DecodeCheck("vault.note") {
            let read = try KJSON.decode(VaultNoteDTO.self, from: VaultSamples.note)
            guard read.version?.count == 40, read.canEdit == true, read.links?.count == 2,
                  read.backlinks?.first?.id == "Home.md", read.lastChange?.label != nil,
                  VaultWire.id(forPath: read.path ?? "") == "Projects/Launch plan" else { throw SampleMismatch("note fields") }
            return "version, links, backlinks"
        },
        DecodeCheck("vault.save") {
            let done = try KJSON.decode(VaultNoteDTO.self, from: VaultSamples.saved)
            let refused = try KJSON.decode(APIErrorBody.self, from: VaultSamples.conflict)
            guard done.ok == true, done.version != nil, refused.text == VaultWire.conflictDetail else { throw SampleMismatch("save fields") }
            return "saved and conflict"
        },
        DecodeCheck("vault.search") {
            let found = try KJSON.decode(VaultSearchDTO.self, from: VaultSamples.search)
            let near = try KJSON.decode(VaultRelatedDTO.self, from: VaultSamples.related)
            guard found.mark?.count == 2, found.results?.first?.snippet?.contains("\u{E000}") == true,
                  near.results?.count == 1 else { throw SampleMismatch("search fields") }
            return "marks and related"
        },
        DecodeCheck("vault.pins") {
            let pinned = try KJSON.decode(VaultPinsDTO.self, from: VaultSamples.pins)
            let changed = try KJSON.decode(VaultActivityDTO.self, from: VaultSamples.activity)
            guard pinned.pins?.count == 2, changed.recent?.first?.label != nil else { throw SampleMismatch("pins or recent") }
            return "pins and recent"
        },
        DecodeCheck("vault.daily") {
            let status = try KJSON.decode(VaultDailyDTO.self, from: VaultSamples.daily)
            let made = try KJSON.decode(VaultDailyMadeDTO.self, from: VaultSamples.dailyMade)
            guard status.templateExists == true, status.exists == false, made.created == true,
                  made.index?.content?.contains(made.index?.line ?? "?") == true else { throw SampleMismatch("daily fields") }
            return "status, made, index line"
        },
    ]
}
