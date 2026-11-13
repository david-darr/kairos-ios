import Foundation

// The desktop's calendar routes, as the phone reads them: one decoder per answer and one function per route.
// Shapes were read from routes/calendar_routes.py, services/calendar_service.py, core/calendar_recurrence.py,
// routes/google_routes.py, core/google_workspace.py, core/tab_hooks.py and routes/notes_routes.py.
//
// - GET /api/calendar/events merges four kinds of item, told apart by `source`: "calendar" (Kairos's own
//   events, a repeating one already expanded into one item per day), "note" (a note with a due time),
//   "tab" (a workspace tab's deadline) and "google" (only for an admin account with Calendar connected).
// - A timed boundary is ISO 8601 with an offset ("2026-11-12T09:00:00-05:00"). An all-day boundary is a
//   date ("2026-11-12"); its end is exclusive for Google and when `end_exclusive` is true, else inclusive.
// - A note's due time may have no offset; the desktop reads that as UTC (notes_service._utc).

// MARK: - Items

/// One item of GET /api/calendar/events, GET /api/calendar/events/archived, GET /api/calendar/events/{id},
/// and the answer of POST and PATCH /api/calendar/events.
nonisolated struct CalEventDTO: Decodable, Sendable {
    /// Text for every kind the desktop makes; a tab may send a number, so it is read loosely.
    var id: JSONValue?
    var title: String?
    var start: String?
    var end: String?
    var allDay: Bool?
    var location: String?
    var description: String?
    /// "calendar", "note", "tab" or "google".
    var source: String?
    var completed: Bool?
    var timeZone: String?
    var endExclusive: Bool?
    /// The repeat rule: {frequency, interval, count?, until?}. On one event of a local series it is the series' rule.
    var recurrence: CalRecurrenceDTO?
    /// Set on one event of a series: the local series id, or Google's recurringEventId.
    var seriesId: String?
    var occurrenceDate: String?
    var updatedAt: Double?
    // Google only (google_workspace._map_calendar_event).
    var calendarId: String?
    var calendarColor: String?
    var calendarName: String?
    var editable: Bool?
    var recurrenceSupported: Bool?
    var guests: Int?
    // Tab only (tab_hooks.calendar_items).
    var sourceLabel: String?
    var toggleUrl: String?

    var idText: String { id?.plainText ?? "" }
}

/// calendar_recurrence.normalize: daily, weekly or monthly, every 1 to 365, ending after a count or on a date.
nonisolated struct CalRecurrenceDTO: Decodable, Hashable, Sendable {
    var frequency: String?
    var interval: Int?
    var count: Int?
    var until: String?
}

/// DELETE /api/calendar/events/{id}
nonisolated struct CalOkDTO: Decodable, Sendable {
    var ok: Bool?
}

// MARK: - Google

/// GET /api/google/status (google_workspace.status). Never a token.
nonisolated struct GoogleStatusDTO: Decodable, Sendable {
    var configured: Bool?
    var connected: Bool?
    var email: String?
    var calendarConnected: Bool?
    /// The calendars chosen to show, or null for "the ones Google marks selected".
    var calendarIds: [String]?
    var calendarAccount: String?
}

/// One of GET /api/google/calendar/calendars (google_workspace._fetch_calendar_list).
nonisolated struct GoogleCalendarDTO: Decodable, Sendable {
    var id: String
    var name: String?
    /// "#9fc6e7"
    var color: String?
    var primary: Bool?
    var timeZone: String?
    /// "owner", "writer", "reader" or "freeBusyReader".
    var accessRole: String?
    var selected: Bool?
}

/// PATCH /api/google/calendar/settings
nonisolated struct GoogleCalendarSettingsDTO: Decodable, Sendable {
    var calendarIds: [String]?
}

// MARK: - Notes

/// One of GET /api/notes (notes_service.list_notes), for the Archive's checked-off notes.
nonisolated struct CalNoteDTO: Decodable, Sendable {
    var id: String
    var text: String?
    var dueDate: String?
    var completed: Bool?
    var updatedAt: Double?
}

// MARK: - Reading and writing times

nonisolated enum CalendarWire {

    /// A date ("2026-11-12") as that day's midnight on this phone.
    static func localDay(_ text: String) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return CalDates.cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func isDateOnly(_ text: String) -> Bool { text.count == 10 && !text.contains("T") }

    /// A moment. Text with no offset is read in `naiveZone` (the event's zone, or UTC for a note).
    static func instant(_ raw: String, naiveZone: String) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if isDateOnly(text) { return localDay(text) }
        if let dot = text.firstIndex(of: ".") {
            var end = text.index(after: dot)
            while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
            text.removeSubrange(dot..<end)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        plain.timeZone = TimeZone(identifier: naiveZone) ?? TimeZone(identifier: "UTC")
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            plain.dateFormat = pattern
            if let date = plain.date(from: text) { return date }
        }
        return nil
    }

    /// "2026-11-12" for the day `date` falls on, on this phone.
    static func dayText(_ date: Date) -> String {
        let parts = CalDates.cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The same moment written in `zone` with its offset ("2026-11-12T09:00:00-05:00"), so the desktop keeps
    /// exactly the moment the phone showed and files it under the event's zone.
    static func instantText(_ date: Date, zone: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(identifier: zone) ?? TimeZone(identifier: "UTC")
        return iso.string(from: date)
    }

    /// A whole range in UTC, as the desktop's own web client sends it.
    static func rangeText(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(identifier: "UTC")
        return iso.string(from: date)
    }

    /// "#9fc6e7" as 0x9FC6E7.
    static func hex(_ text: String?) -> UInt32? {
        guard var text, text.hasPrefix("#") else { return nil }
        text.removeFirst()
        guard text.count == 6 else { return nil }
        return UInt32(text, radix: 16)
    }

    // MARK: Rules

    static func rule(_ dto: CalRecurrenceDTO?) -> CalRepeat {
        guard let dto, let freq = CalRepeatFreq(rawValue: dto.frequency ?? ""), freq != .none else { return CalRepeat() }
        var rule = CalRepeat(freq: freq, interval: max(1, dto.interval ?? 1))
        if let count = dto.count {
            rule.end = .afterCount
            rule.count = count
        } else if let until = dto.until, let day = localDay(until) {
            rule.end = .onDate
            rule.until = day
        }
        return rule
    }

    /// The rule as the desktop takes it (calendar_recurrence.normalize), or nil for "does not repeat".
    static func ruleJSON(_ rule: CalRepeat) -> [String: Any]? {
        guard rule.custom == nil, rule.freq != .none else { return nil }
        var json: [String: Any] = ["frequency": rule.freq.rawValue, "interval": max(1, min(365, rule.interval))]
        switch rule.end {
        case .never: break
        case .afterCount: json["count"] = max(1, min(10_000, rule.count))
        case .onDate: json["until"] = dayText(rule.until)
        }
        return json
    }

    // MARK: Items

    /// Why a Google event is shown without Edit and Delete on the phone, or nil.
    static func googleReadOnly(_ dto: CalEventDTO) -> String? {
        if (dto.guests ?? 0) > 0 {
            return "This event has guests, so it cannot be changed from your phone. Change it on your desktop."
        }
        if dto.seriesId != nil || dto.recurrenceSupported == false {
            return "This event repeats in Google. Change it on your desktop."
        }
        return nil
    }

    /// One desktop item in the Calendar's own shape. nil for an item with no id or no start.
    static func event(_ dto: CalEventDTO) -> CalEvent? {
        let id = dto.idText
        guard !id.isEmpty, let rawStart = dto.start, !rawStart.isEmpty else { return nil }
        let source: CalSourceKind
        switch dto.source {
        case "google": source = .google
        case "note": source = .notes
        case "tab": source = .tab
        default: source = .kairos
        }
        let zone = (dto.timeZone?.isEmpty == false ? dto.timeZone : nil) ?? (source == .notes ? "UTC" : TimeZone.current.identifier)
        let rawEnd = (dto.end?.isEmpty == false ? dto.end : nil) ?? rawStart
        let allDay = (dto.allDay ?? false) && isDateOnly(rawStart)
        let start: Date
        let end: Date
        if allDay {
            guard let first = localDay(rawStart) else { return nil }
            var last: Date
            if isDateOnly(rawEnd), let day = localDay(rawEnd) {
                let exclusive = source == .google || dto.endExclusive == true
                last = exclusive ? day : CalDates.add(1, to: day)
            } else if let moment = instant(rawEnd, naiveZone: zone) {
                last = CalDates.add(1, to: CalDates.day(moment))
            } else {
                last = CalDates.add(1, to: first)
            }
            if last <= first { last = CalDates.add(1, to: first) }
            start = first
            end = last
        } else {
            guard let first = instant(rawStart, naiveZone: zone) else { return nil }
            let last = instant(rawEnd, naiveZone: zone) ?? first
            start = first
            end = max(first, last)
        }

        // Google expands its own repeats and the phone never edits them, so they only say that they repeat.
        var repeats = source == .google ? CalRepeat() : Self.rule(dto.recurrence)
        if (dto.seriesId != nil || (source == .google && dto.recurrence != nil)) && !repeats.repeats { repeats.custom = "Repeats" }

        var ref = CalLiveRef(id: id, seriesID: dto.seriesId)
        if source == .google {
            ref.calendarID = dto.calendarId
            ref.calendarName = dto.calendarName
            ref.colorHex = hex(dto.calendarColor)
            ref.editable = dto.editable ?? false
            ref.guests = dto.guests ?? 0
            ref.readOnlyReason = googleReadOnly(dto)
        } else if source == .tab {
            if let url = dto.toggleUrl, url.hasPrefix("/api/"), !url.contains("\\") { ref.toggleURL = url }
        }
        return CalEvent(
            id: "\(dto.source ?? "calendar"):\(dto.calendarId ?? ""):\(id)",
            title: (dto.title?.isEmpty == false ? dto.title : nil) ?? "Untitled event",
            start: start, end: end, allDay: allDay, source: source,
            calendarID: source == .google ? dto.calendarId : nil,
            tabName: source == .tab ? dto.sourceLabel : nil,
            location: dto.location ?? "", notes: dto.description ?? "",
            timeZone: dto.timeZone.flatMap { TimeZone(identifier: $0) != nil ? $0 : nil } ?? TimeZone.current.identifier,
            repeatRule: repeats, completed: dto.completed ?? false,
            completedAt: dto.updatedAt.map { Date(timeIntervalSince1970: $0) },
            live: ref
        )
    }

    /// A checked-off note with a due time, for the Archive.
    static func archivedNote(_ dto: CalNoteDTO) -> CalEvent? {
        guard dto.completed == true, let due = dto.dueDate, !due.isEmpty,
              let when = instant(due, naiveZone: "UTC") else { return nil }
        return CalEvent(id: "note::\(dto.id)", title: (dto.text?.isEmpty == false ? dto.text : nil) ?? "Note",
                        start: when, end: when, source: .notes, completed: true,
                        completedAt: dto.updatedAt.map { Date(timeIntervalSince1970: $0) },
                        live: CalLiveRef(id: dto.id))
    }

    /// The `start` and `end` the desktop takes: dates for an all-day event (end exclusive), else moments in `zone`.
    static func boundaries(allDay: Bool, start: Date, end: Date, zone: String) -> (start: String, end: String) {
        allDay ? (dayText(start), dayText(end)) : (instantText(start, zone: zone), instantText(end, zone: zone))
    }

    /// Google's {date} or {dateTime, timeZone} for one boundary.
    static func googleBoundary(allDay: Bool, _ date: Date, zone: String) -> [String: Any] {
        allDay ? ["date": dayText(date)] : ["dateTime": instantText(date, zone: zone), "timeZone": zone]
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/calendar/events?start=&end= : everything shown in [start, end).
    func calendarEvents(start: Date, end: Date) async throws -> [CalEventDTO] {
        try await get("/api/calendar/events", query: ["start": CalendarWire.rangeText(start), "end": CalendarWire.rangeText(end)])
    }

    /// GET /api/calendar/events/archived : checked-off Kairos events, latest first.
    func calendarArchived() async throws -> [CalEventDTO] {
        try await get("/api/calendar/events/archived")
    }

    /// GET /api/calendar/events/{id}?scope=series : the series an event belongs to, for "All events in this series".
    func calendarSeries(_ id: String) async throws -> CalEventDTO {
        try await get("/api/calendar/events/\(id)", query: ["scope": "series"])
    }

    // The three writes read only the status. A 2xx means the desktop has it; the body (the event, or {ok: true},
    // see CalendarSamples.created and .deleted) is not decoded, so an answer this app cannot read is never
    // reported as a failed write that someone might then send again.

    /// POST /api/calendar/events : a new Kairos event.
    func calendarCreate(_ body: [String: Any]) async throws {
        try await call("POST", "/api/calendar/events", json: body)
    }

    /// PATCH /api/calendar/events/{id} : `scope` ("occurrence" or "series") travels in the body.
    func calendarUpdate(_ id: String, _ body: [String: Any]) async throws {
        try await call("PATCH", "/api/calendar/events/\(id)", json: body)
    }

    /// DELETE /api/calendar/events/{id}?scope=
    func calendarDelete(_ id: String, scope: String) async throws {
        try await call("DELETE", "/api/calendar/events/\(id)", query: ["scope": scope])
    }

    /// GET /api/google/status
    func googleStatus() async throws -> GoogleStatusDTO {
        try await get("/api/google/status")
    }

    /// GET /api/google/calendar/calendars
    func googleCalendars() async throws -> [GoogleCalendarDTO] {
        try await get("/api/google/calendar/calendars")
    }

    /// PATCH /api/google/calendar/settings : the whole list of calendars to show.
    func googleCalendarSettings(_ ids: [String]) async throws -> GoogleCalendarSettingsDTO {
        try await request("PATCH", "/api/google/calendar/settings", json: ["calendar_ids": ids])
    }

    /// POST /api/google/calendar/action : create, update or delete one Google event. The answer is Google's own
    /// event (or {deleted: true}) and is not read: the range is read again after.
    func googleCalendarAction(_ body: [String: Any]) async throws {
        try await call("POST", "/api/google/calendar/action", json: body)
    }

    /// GET /api/notes?include_completed=true
    func calendarNotes() async throws -> [CalNoteDTO] {
        try await get("/api/notes", query: ["include_completed": "true"])
    }

    /// PATCH any desktop path with {completed}: a note (/api/notes/{id}) or a tab item's own toggle path.
    func calendarSetCompleted(path: String, _ completed: Bool) async throws {
        try await call("PATCH", path, json: ["completed": completed])
    }
}

// MARK: - Samples

/// A sample answer for every calendar route the phone reads, shaped like the desktop's own (made-up content).
nonisolated enum CalendarSamples {

    static let events = #"""
    [
      {"id": "a1b2c3d4e5f6", "title": "Bike shop stock check", "start": "2027-01-04T11:00:00-05:00",
       "end": "2027-01-04T12:00:00-05:00", "all_day": false, "location": "Back room", "description": "Count tubes.",
       "created_at": 1793000000.0, "updated_at": 1793000000.0, "sync_id": null, "external_uid": null,
       "completed": false, "recurrence": null, "time_zone": "America/New_York", "end_exclusive": false, "source": "calendar"},
      {"id": "0f9e8d7c6b5a~2027-01-05", "title": "Gym", "start": "2027-01-05T18:00:00-05:00",
       "end": "2027-01-05T19:00:00-05:00", "all_day": false, "location": "", "description": "",
       "created_at": 1793000000.0, "updated_at": 1793000000.0, "completed": false,
       "recurrence": {"frequency": "weekly", "interval": 1, "count": 10}, "time_zone": "America/New_York",
       "end_exclusive": false, "source": "calendar", "series_id": "0f9e8d7c6b5a", "occurrence_date": "2027-01-05"},
      {"id": "1122aabbccdd", "title": "Weekend trip", "start": "2027-01-09", "end": "2027-01-11", "all_day": true,
       "location": "Lake cabin", "description": "", "completed": false, "recurrence": null, "time_zone": "America/New_York",
       "end_exclusive": true, "source": "calendar"},
      {"id": "3344eeff0011", "title": "Late shift", "start": "2027-01-06T23:00:00-05:00", "end": "2027-01-07T01:30:00-05:00",
       "all_day": false, "location": "", "description": "", "completed": false, "recurrence": null,
       "time_zone": "America/New_York", "end_exclusive": false, "source": "calendar"},
      {"id": "5566aabb7788", "title": "Report due", "start": "2027-01-08T17:00:00", "end": "2027-01-08T17:00:00",
       "all_day": false, "location": "", "description": "", "source": "note", "completed": false},
      {"id": "q-17", "title": "Send the Lakeside quote", "start": "2027-01-06T10:00:00+00:00", "end": "2027-01-06T10:00:00+00:00",
       "all_day": false, "source": "tab", "source_label": "CRM", "toggle_url": "/api/tabs/crm/quotes/q-17"},
      {"id": "g8h7j6k5", "title": "Supplier call", "start": "2027-01-04T11:30:00-05:00", "end": "2027-01-04T12:15:00-05:00",
       "all_day": false, "time_zone": "America/New_York", "location": "", "description": "Ask about dates.", "source": "google",
       "calendar_id": "shop@example.com", "calendar_color": "#9fc6e7", "calendar_name": "Shop", "editable": true,
       "web_link": "https://calendar.example.com/event", "series_id": null, "original_start": null, "recurrence": null,
       "recurrence_supported": true, "recurrence_raw": [], "guests": 0, "meeting_url": null},
      {"id": "g1_20270105T150000Z", "title": "Team standup", "start": "2027-01-05T10:00:00-05:00",
       "end": "2027-01-05T10:15:00-05:00", "all_day": false, "time_zone": "America/New_York", "location": "Video call",
       "description": "", "source": "google", "calendar_id": "team@example.com", "calendar_color": "#7bd148",
       "calendar_name": "Team", "editable": true, "series_id": "g1", "original_start": {"dateTime": "2027-01-05T10:00:00-05:00"},
       "recurrence": null, "recurrence_supported": true, "recurrence_raw": [], "guests": 3, "meeting_url": "https://meet.example.com/abc"},
      {"id": "h0l1d4y", "title": "Harvest festival", "start": "2027-01-10", "end": "2027-01-11", "all_day": true,
       "time_zone": "UTC", "location": "", "description": "", "source": "google", "calendar_id": "holidays@example.com",
       "calendar_color": null, "calendar_name": "Holidays", "editable": false, "series_id": null, "recurrence": null,
       "recurrence_supported": true, "recurrence_raw": [], "guests": 0, "meeting_url": null}
    ]
    """#

    static let created = #"""
    {"id": "77aa88bb99cc", "title": "Plan next week", "start": "2027-01-08T16:00:00-05:00", "end": "2027-01-08T16:30:00-05:00",
     "all_day": false, "location": "", "description": "", "created_at": 1793100000.0, "updated_at": 1793100000.0,
     "sync_id": null, "external_uid": null, "completed": false, "recurrence": {"frequency": "monthly", "interval": 1, "until": "2027-06-30"},
     "time_zone": "America/New_York", "end_exclusive": false}
    """#

    static let deleted = #"{"ok": true}"#

    static let archived = #"""
    [{"id": "99ffee001122", "title": "Call the plumber", "start": "2027-01-03T10:00:00-05:00", "end": "2027-01-03T10:30:00-05:00",
      "all_day": false, "completed": true, "updated_at": 1793050000.0, "recurrence": null, "time_zone": "America/New_York",
      "end_exclusive": false, "source": "calendar"}]
    """#

    static let notes = #"""
    [{"id": "n1n2n3n4n5n6", "text": "Renew bike insurance", "due_date": "2027-01-02T12:00:00", "project": "personal",
      "completed": true, "created_at": 1792900000.0, "updated_at": 1793010000.0, "vault_source": null},
     {"id": "n7n8n9n0n1n2", "text": "Water the plants", "due_date": null, "project": "personal",
      "completed": true, "created_at": 1792900000.0, "updated_at": 1793010000.0, "vault_source": {"file": "Tasks.md", "line": 4}}]
    """#

    static let status = #"""
    {"configured": true, "connected": true, "email": "you@example.com", "client_id": "",
     "granted_scopes": ["https://www.googleapis.com/auth/calendar"], "calendar_connected": true,
     "calendar_ids": ["shop@example.com", "team@example.com"], "calendar_account": "acct1",
     "accounts": [{"id": "acct1", "email": "you@example.com", "default": true, "error": null, "can_send_email": false, "calendar_connected": true}],
     "default_account": "acct1", "active_account": "acct1"}
    """#

    static let calendars = #"""
    [{"id": "shop@example.com", "name": "Shop", "color": "#9fc6e7", "primary": true, "time_zone": "America/New_York",
      "access_role": "owner", "selected": true},
     {"id": "holidays@example.com", "name": "Holidays", "color": "#16a765", "primary": false, "time_zone": "UTC",
      "access_role": "reader", "selected": false}]
    """#

    static let settings = #"{"calendar_ids": ["shop@example.com"]}"#

    private static func mapped() throws -> [CalEvent] {
        try KJSON.decode([CalEventDTO].self, from: events).compactMap(CalendarWire.event)
    }

    static let checks: [DecodeCheck] = [
        DecodeCheck("calendar.events") {
            let items = try CalendarSamples.mapped()
            guard items.count == 9,
                  items.filter({ $0.source == .kairos }).count == 4,
                  items.filter({ $0.source == .google }).count == 3,
                  items.first(where: { $0.source == .notes }) != nil,
                  items.first(where: { $0.source == .tab })?.live?.toggleURL == "/api/tabs/crm/quotes/q-17",
                  items.allSatisfy({ $0.live != nil && $0.end >= $0.start }) else { throw SampleMismatch("event kinds or times") }
            return "\(items.count) items, four kinds"
        },
        DecodeCheck("calendar.allday") {
            let items = try CalendarSamples.mapped()
            guard let trip = items.first(where: { $0.title == "Weekend trip" }), trip.allDay,
                  CalendarWire.dayText(trip.start) == "2027-01-09", CalendarWire.dayText(trip.end) == "2027-01-11",
                  let fest = items.first(where: { $0.title == "Harvest festival" }), fest.allDay,
                  CalendarWire.dayText(fest.end) == "2027-01-11" else { throw SampleMismatch("all-day dates") }
            let sent = CalendarWire.boundaries(allDay: true, start: trip.start, end: trip.end, zone: "UTC")
            guard sent.start == "2027-01-09", sent.end == "2027-01-11" else { throw SampleMismatch("all-day boundaries sent") }
            // An old inclusive date-only end gains a day.
            let old = try KJSON.decode(CalEventDTO.self, from: #"{"id": "x", "start": "2027-01-09", "end": "2027-01-09", "all_day": true, "source": "calendar"}"#)
            guard let one = CalendarWire.event(old), CalendarWire.dayText(one.end) == "2027-01-10" else { throw SampleMismatch("inclusive end") }
            return "exclusive ends, one inclusive"
        },
        DecodeCheck("calendar.midnight") {
            let items = try CalendarSamples.mapped()
            guard let late = items.first(where: { $0.title == "Late shift" }) else { throw SampleMismatch("late shift") }
            let length = late.end.timeIntervalSince(late.start)
            guard abs(length - 9000) < 1,
                  late.start == CalendarWire.instant("2027-01-07T04:00:00Z", naiveZone: "UTC"),
                  CalendarWire.instantText(late.start, zone: "America/New_York") == "2027-01-06T23:00:00-05:00",
                  let note = items.first(where: { $0.source == .notes }),
                  note.start == CalendarWire.instant("2027-01-08T17:00:00+00:00", naiveZone: "UTC"),
                  CalendarWire.instant("2027-01-08T17:00:00.123456-05:00", naiveZone: "UTC") == CalendarWire.instant("2027-01-08T22:00:00Z", naiveZone: "UTC")
            else { throw SampleMismatch("times across midnight") }
            return "2 h 30 m across midnight, naive is UTC"
        },
        DecodeCheck("calendar.readonly") {
            let items = try CalendarSamples.mapped()
            guard let gym = items.first(where: { $0.title == "Gym" }), gym.live?.seriesID == "0f9e8d7c6b5a",
                  gym.repeatRule.freq == .weekly, gym.repeatRule.end == .afterCount, gym.live?.readOnlyReason == nil,
                  let standup = items.first(where: { $0.title == "Team standup" }), standup.live?.guests == 3,
                  standup.live?.readOnlyReason != nil, standup.repeatRule.repeats,
                  let call = items.first(where: { $0.title == "Supplier call" }), call.live?.readOnlyReason == nil,
                  call.live?.colorHex == 0x9FC6E7,
                  let fest = items.first(where: { $0.title == "Harvest festival" }), fest.live?.editable == false
            else { throw SampleMismatch("what can change") }
            return "series, guests, read-only calendar"
        },
        DecodeCheck("calendar.write") {
            let made = try KJSON.decode(CalEventDTO.self, from: CalendarSamples.created)
            let gone = try KJSON.decode(CalOkDTO.self, from: CalendarSamples.deleted)
            let rule = CalendarWire.rule(made.recurrence)
            guard made.idText == "77aa88bb99cc", rule.freq == .monthly, rule.end == .onDate,
                  CalendarWire.dayText(rule.until) == "2027-06-30",
                  (CalendarWire.ruleJSON(rule)?["until"] as? String) == "2027-06-30",
                  CalendarWire.ruleJSON(CalRepeat()) == nil, gone.ok == true else { throw SampleMismatch("create or delete") }
            return "created, rule both ways, deleted"
        },
        DecodeCheck("calendar.archive") {
            let events = try KJSON.decode([CalEventDTO].self, from: CalendarSamples.archived).compactMap(CalendarWire.event)
            let notes = try KJSON.decode([CalNoteDTO].self, from: CalendarSamples.notes).compactMap(CalendarWire.archivedNote)
            guard events.count == 1, events[0].completed, notes.count == 1, notes[0].live?.id == "n1n2n3n4n5n6" else {
                throw SampleMismatch("archive")
            }
            return "1 event, 1 note"
        },
        DecodeCheck("calendar.google") {
            let status = try KJSON.decode(GoogleStatusDTO.self, from: CalendarSamples.status)
            let list = try KJSON.decode([GoogleCalendarDTO].self, from: CalendarSamples.calendars)
            let chosen = try KJSON.decode(GoogleCalendarSettingsDTO.self, from: CalendarSamples.settings)
            guard status.calendarConnected == true, status.calendarIds?.count == 2, list.count == 2,
                  list[0].accessRole == "owner", list[0].primary == true, CalendarWire.hex(list[1].color) == 0x16A765,
                  chosen.calendarIds == ["shop@example.com"] else { throw SampleMismatch("google fields") }
            return "status, calendars, settings"
        },
    ]
}
