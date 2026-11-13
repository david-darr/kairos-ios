import Foundation

// The desktop's notes routes (routes/notes_routes.py over services/notes_service.py), as the phone reads them:
// one decoder per answer and one function per route.
//
// - A note is the service's own dict: id (12 hex characters), text, due_date (ISO 8601 text or null),
//   project, completed, created_at and updated_at (epoch seconds), vault_source (null, or where in the
//   vault the note was imported from).
// - The desktop has no pin, no saved order of its own, and no version check on a change: PATCH changes only
//   the fields it is sent, so the phone sends only the fields the person changed.
// - A due time is sent as UTC with milliseconds ("2027-03-05T17:00:00.000Z"), the way the desktop's own
//   web page sends it. One read with no zone is UTC, as the desktop reads it (notes_service.py: _utc).

// MARK: - Answers

/// One note (notes_service.py: create_note builds it; GET, POST and PATCH answer it).
/// Every field but the id is read leniently, so one odd note cannot hide the rest.
nonisolated struct NoteDTO: Decodable, Sendable {
    var id: String
    var text: JSONValue?
    var dueDate: JSONValue?
    var project: JSONValue?
    var completed: JSONValue?
    var createdAt: JSONValue?
    var updatedAt: JSONValue?
    /// Set only for a note imported from the vault's task list ({file, line, heading, vault}).
    var vaultSource: JSONValue?
    var dismissed: JSONValue?

    var isFromVault: Bool {
        guard let source = vaultSource else { return false }
        return !source.isNull
    }
}

/// GET /api/notes: a JSON list of notes. A note this app cannot read is skipped and counted, never guessed at.
nonisolated struct NotesListDTO: Decodable, Sendable {
    var notes: [NoteDTO] = []
    var skipped = 0

    init(from decoder: Decoder) throws {
        var list = try decoder.unkeyedContainer()
        while !list.isAtEnd {
            if let note = try? list.decode(NoteDTO.self) {
                notes.append(note)
            } else {
                // A failed decode does not move past the element; read it as anything to step over it.
                _ = try list.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

/// DELETE /api/notes/{id}: {"ok": true}.
nonisolated struct NotesOkDTO: Decodable, Sendable {
    var ok: Bool?
}

// MARK: - Wire helpers

nonisolated enum NotesWire {
    /// The 404 sentence PATCH sends for a note that is not there (notes_routes.py: update_note).
    static let missingDetail = "note not found"

    /// A due time as the desktop's web page sends it: UTC, milliseconds, "Z".
    static func dueText(_ date: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        format.timeZone = TimeZone(identifier: "UTC")
        return format.string(from: date)
    }

    static func due(_ value: JSONValue?) -> Date? {
        guard let text = value?.string, !text.isEmpty else { return nil }
        return FlexibleDate.parse(text)
    }

    static func time(_ value: JSONValue?) -> Date? {
        guard let seconds = value?.double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// A note id goes into the path as it is. One that could leave the notes path is refused.
    static func pathID(_ id: String) throws -> String {
        guard !id.isEmpty, id != ".", id != "..",
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else {
            throw APIError.unreadable("note id")
        }
        return id
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/notes (completed notes included, which is the route's default).
    func notesList() async throws -> NotesListDTO {
        try await get("/api/notes")
    }

    /// POST /api/notes. No project is sent, so the desktop files it as "personal", as its own page does.
    func notesCreate(text: String, due: Date?) async throws -> NoteDTO {
        try await post("/api/notes", json: [
            "text": text,
            "due_date": due.map(NotesWire.dueText) ?? NSNull(),
        ])
    }

    /// PATCH /api/notes/{id} with only the fields that changed. `due` set to nil clears the due time;
    /// leave `changesDue` false to leave it as it is.
    func notesUpdate(_ id: String, text: String? = nil, changesDue: Bool = false, due: Date? = nil,
                     completed: Bool? = nil) async throws -> NoteDTO {
        var body: [String: Any] = [:]
        if let text { body["text"] = text }
        if changesDue { body["due_date"] = due.map(NotesWire.dueText) ?? NSNull() }
        if let completed { body["completed"] = completed }
        return try await request("PATCH", "/api/notes/" + NotesWire.pathID(id), json: body)
    }

    /// DELETE /api/notes/{id}. A note imported from the vault is only hidden; its line stays in the vault.
    func notesDelete(_ id: String) async throws -> NotesOkDTO {
        try await request("DELETE", "/api/notes/" + NotesWire.pathID(id))
    }
}

// MARK: - Samples

/// A sample answer for every notes route, shaped like the desktop's own (made-up content).
nonisolated enum NotesSamples {

    static let list = #"""
    [
      {"id": "3f2a9c1b7d04", "text": "Book the van for the Saturday delivery", "due_date": "2027-03-06T09:00:00.000Z",
       "project": "personal", "completed": false, "created_at": 1793000000.25, "updated_at": 1793000100.5, "vault_source": null},
      {"id": "8e41b0c2a9f7", "text": "Order chain oil", "due_date": null, "project": "Shop", "completed": false,
       "created_at": 1792900000.0, "updated_at": 1792900000.0,
       "vault_source": {"file": "Tasks.md", "line": "- [ ] Order chain oil", "heading": "Shop", "vault": "/home/example/vault"}},
      {"id": "c07d5e3a1b62", "text": "Finish the weekly report", "due_date": "2027-03-05T17:00:00", "project": "personal",
       "completed": true, "created_at": 1792800000, "updated_at": 1792950000.75, "vault_source": null},
      {"text": "A note with no id"}
    ]
    """#

    static let created = #"""
    {"id": "5b9e2f0a4c18", "text": "Call the supplier about the inner tubes", "due_date": "2027-03-04T15:30:00.000Z",
     "project": "personal", "completed": false, "created_at": 1793100000.5, "updated_at": 1793100000.5, "vault_source": null}
    """#

    static let updated = #"""
    {"id": "5b9e2f0a4c18", "text": "Call the supplier about the inner tubes", "due_date": null,
     "project": "personal", "completed": true, "created_at": 1793100000.5, "updated_at": 1793100200.0, "vault_source": null}
    """#

    static let deleted = #"{"ok": true}"#

    static let missing = #"{"detail": "note not found"}"#

    static let checks: [DecodeCheck] = [
        DecodeCheck("notes.list") {
            let read = try KJSON.decode(NotesListDTO.self, from: NotesSamples.list)
            guard read.notes.count == 3, read.skipped == 1,
                  read.notes[1].isFromVault, !read.notes[0].isFromVault,
                  NotesWire.due(read.notes[0].dueDate) != nil, NotesWire.due(read.notes[1].dueDate) == nil,
                  read.notes[2].completed?.bool == true,
                  NotesWire.time(read.notes[2].createdAt) == Date(timeIntervalSince1970: 1_792_800_000) else {
                throw SampleMismatch("list fields")
            }
            return "3 notes, 1 skipped, vault flag"
        },
        DecodeCheck("notes.write") {
            let made = try KJSON.decode(NoteDTO.self, from: NotesSamples.created)
            let changed = try KJSON.decode(NoteDTO.self, from: NotesSamples.updated)
            let gone = try KJSON.decode(NotesOkDTO.self, from: NotesSamples.deleted)
            let refused = try KJSON.decode(APIErrorBody.self, from: NotesSamples.missing)
            guard made.id.count == 12, made.text?.string != nil, NotesWire.due(made.dueDate) != nil,
                  changed.completed?.bool == true, NotesWire.due(changed.dueDate) == nil,
                  gone.ok == true, refused.text == NotesWire.missingDetail else { throw SampleMismatch("write fields") }
            return "create, change, delete, missing"
        },
        DecodeCheck("notes.dates") {
            let sent = Date(timeIntervalSince1970: 1_804_266_000)
            let text = NotesWire.dueText(sent)
            guard text == "2027-03-05T17:00:00.000Z", NotesWire.due(.string(text)) == sent,
                  NotesWire.due(.string("2027-03-05T17:00:00")) == sent,
                  NotesWire.due(.string("2027-03-05T18:00:00+01:00")) == sent,
                  NotesWire.due(.string("not a date")) == nil,
                  (try? NotesWire.pathID("3f2a9c1b7d04")) != nil, (try? NotesWire.pathID("../x")) == nil else {
                throw SampleMismatch("due time as \(text)")
            }
            return "UTC out, three forms in"
        },
    ]
}
