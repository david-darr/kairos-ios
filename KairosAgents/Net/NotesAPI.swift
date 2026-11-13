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
        return parseDue(text)
    }

    /// The desktop has a due time for this note, but not one this app can read. Such a note shows that,
    /// and the phone never sends a due time for it, so a time the person never saw is not replaced.
    static func dueUnreadable(_ value: JSONValue?) -> Bool {
        guard let value, !value.isNull else { return false }
        guard let text = value.string else { return true }
        // An empty due is no due on the desktop too (notes_service.py: `if not n.get("due_date")`).
        return !text.isEmpty && parseDue(text) == nil
    }

    /// A due time in the ISO 8601 forms Python's `datetime.fromisoformat` reads, because the desktop stores
    /// whatever text it is given (an agent's tool call, an import) and reads it back with that:
    /// a date ("2027-03-05", "20270305"), then "T", "t" or a space, then "17", "17:00", "17:00:00",
    /// "170000", with fractional seconds after "." or "," (any number of digits), then no zone (UTC, as
    /// notes_service.py: _utc), "Z", "+01", "+01:00", "+0100" or "+01:00:00". A date alone is that day
    /// here, at local midnight. Anything else (week dates, other separators, spaces around it) answers nil,
    /// and the note then says it has a due time this app cannot read.
    static func parseDue(_ raw: String) -> Date? {
        let bytes = Array(raw.utf8)
        var at = 0
        func number(_ count: Int) -> Int? {
            guard at + count <= bytes.count else { return nil }
            var value = 0
            for index in at..<(at + count) {
                let byte = bytes[index]
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            at += count
            return value
        }
        func take(_ character: Character) -> Bool {
            guard at < bytes.count, let ascii = character.asciiValue, bytes[at] == ascii else { return false }
            at += 1
            return true
        }
        func isDigit() -> Bool { at < bytes.count && bytes[at] >= 48 && bytes[at] <= 57 }

        guard let year = number(4), year >= 1 else { return nil }
        let dashed = take("-")
        guard let month = number(2) else { return nil }
        if dashed { guard take("-") else { return nil } }
        guard let day = number(2) else { return nil }
        if at == bytes.count {
            return checkedDate(year, month, day, 0, 0, 0, 0, in: .current)
        }
        guard take("T") || take("t") || take(" "), let hour = number(2) else { return nil }
        var minute = 0
        var second = 0
        var nanos = 0
        func fraction() -> Bool {
            guard take(".") || take(",") else { return true }
            var digits = 0
            var value = 0
            while isDigit() {
                if digits < 9 { value = value * 10 + Int(bytes[at] - 48) }
                digits += 1
                at += 1
            }
            guard digits > 0 else { return false }
            for _ in min(digits, 9)..<9 { value *= 10 }
            nanos = value
            return true
        }
        if take(":") {
            guard let minutes = number(2) else { return nil }
            minute = minutes
            if take(":") {
                guard let seconds = number(2) else { return nil }
                second = seconds
                guard fraction() else { return nil }
            }
        } else if isDigit() {
            guard let minutes = number(2) else { return nil }
            minute = minutes
            if isDigit() {
                guard let seconds = number(2) else { return nil }
                second = seconds
                guard fraction() else { return nil }
            }
        }
        var zone = TimeZone(secondsFromGMT: 0)
        if take("Z") {
            // UTC.
        } else if at < bytes.count, bytes[at] == 43 || bytes[at] == 45 {
            let sign = bytes[at] == 45 ? -1 : 1
            at += 1
            guard let hours = number(2) else { return nil }
            var minutes = 0
            var seconds = 0
            if take(":") {
                guard let value = number(2) else { return nil }
                minutes = value
                if take(":") {
                    guard let value = number(2) else { return nil }
                    seconds = value
                    let keep = nanos
                    guard fraction() else { return nil }
                    nanos = keep
                }
            } else if isDigit() {
                guard let value = number(2) else { return nil }
                minutes = value
            }
            guard hours < 24, minutes < 60, seconds < 60 else { return nil }
            zone = TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60 + seconds))
        }
        guard at == bytes.count, let zone else { return nil }
        return checkedDate(year, month, day, hour, minute, second, nanos, in: zone)
    }

    /// The date for these parts, or nil when they name no real time (a 30 February, a 25 o'clock).
    private static func checkedDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
                                    _ second: Int, _ nanos: Int, in zone: TimeZone) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour),
              (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute,
                                   second: second, nanosecond: nanos)
        guard let date = calendar.date(from: parts) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return date
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
        DecodeCheck("notes.dueforms") {
            // Every form Python's datetime.fromisoformat reads that the desktop may hold (it stores any text).
            let sent = Date(timeIntervalSince1970: 1_804_266_000)
            func same(_ text: String, _ offset: TimeInterval = 0) -> Bool {
                guard let read = NotesWire.parseDue(text) else { return false }
                return abs(read.timeIntervalSince(sent) - offset) < 0.000_01
            }
            let forms: [(String, TimeInterval)] = [
                ("2027-03-05T17:00", 0), ("2027-03-05T17", 0), ("2027-03-05 17:00:00", 0), ("2027-03-05 17:00", 0),
                ("2027-03-05t17:00:00", 0), ("2027-03-05T17:00:00.123456", 0.123456),
                ("2027-03-05T17:00:00,5", 0.5), ("2027-03-05T17:00:00.123456+00:00", 0.123456),
                ("2027-03-05T17:00:00Z", 0), ("2027-03-05T12:00:00-05:00", 0),
                ("2027-03-05T12:00:00-0500", 0), ("2027-03-05T22:00+05", 0), ("20270305T170000", 0),
                ("20270305T170000Z", 0), ("2027-03-05T1700", 0),
            ]
            for (text, offset) in forms where !same(text, offset) {
                throw SampleMismatch("due form \(text)")
            }
            var local = Calendar(identifier: .gregorian)
            local.timeZone = .current
            let midnight = local.date(from: DateComponents(year: 2027, month: 3, day: 5))
            guard NotesWire.parseDue("2027-03-05") == midnight, NotesWire.parseDue("20270305") == midnight else {
                throw SampleMismatch("date-only due")
            }
            for bad in ["2027-02-30T10:00", "2027-03-05T25:00", "2027-03-05T17:00:00+25:00", "2027-03-05X17:00",
                        "2027-W10-5", "2027-03-05T17:00:", "next Friday", "2027-3-5", " 2027-03-05T17:00"]
            where NotesWire.parseDue(bad) != nil {
                throw SampleMismatch("read \(bad)")
            }
            let odd = try KJSON.decode(NoteDTO.self, from: #"{"id": "a1b2c3d4e5f6", "text": "Ring the shop", "due_date": "next Friday"}"#)
            let unreadable = NotesStore.liveNote(odd, order: 0)
            guard unreadable.due == nil, unreadable.dueUnreadable,
                  NotesWire.dueUnreadable(.number(5)), !NotesWire.dueUnreadable(.string("")),
                  !NotesWire.dueUnreadable(.null), !NotesWire.dueUnreadable(nil),
                  !NotesWire.dueUnreadable(.string("2027-03-05 17:00")) else {
                throw SampleMismatch("unreadable due flag")
            }
            return "\(forms.count + 2) forms read, 9 refused, flag set"
        },
    ]
}
