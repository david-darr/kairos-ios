import SwiftUI

// MARK: - Plain data

/// Where a calendar item comes from. Google items carry their calendar; tab items carry the tab's name.
nonisolated enum CalSourceKind: String, CaseIterable, Hashable, Sendable {
    case kairos, google, notes, tab
}

/// One connected Google calendar.
nonisolated struct CalCalendar: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var colorHex: UInt32
    var visible = true
    var writable = true
}

nonisolated enum CalRepeatFreq: String, CaseIterable, Hashable, Sendable {
    case none, daily, weekly, monthly

    var title: String {
        switch self {
        case .none: "Does not repeat"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    func unit(_ count: Int) -> String {
        switch self {
        case .none: ""
        case .daily: count == 1 ? "day" : "days"
        case .weekly: count == 1 ? "week" : "weeks"
        case .monthly: count == 1 ? "month" : "months"
        }
    }
}

nonisolated enum CalRepeatEnd: String, CaseIterable, Hashable, Sendable {
    case never, onDate, afterCount

    var title: String {
        switch self {
        case .never: "Never"
        case .onDate: "On a date"
        case .afterCount: "After a number of events"
        }
    }
}

nonisolated struct CalRepeat: Hashable, Sendable {
    var freq: CalRepeatFreq = .none
    var interval = 1
    var end: CalRepeatEnd = .never
    var until = Date()
    var count = 10
    /// A rule made somewhere else (Google). Kept as it is and shown read-only.
    var custom: String? = nil
    /// The one custom rule the sample uses: every weekday.
    var weekdaysOnly = false

    var repeats: Bool { freq != .none || custom != nil }

    var summary: String {
        if let custom { return custom }
        switch freq {
        case .none: return "Does not repeat"
        default:
            let every = interval == 1 ? freq.title : "Every \(interval) \(freq.unit(interval))"
            switch end {
            case .never: return every
            case .onDate: return "\(every), until \(until.formatted(.dateTime.month(.abbreviated).day()))"
            case .afterCount: return "\(every), \(count) times"
            }
        }
    }
}

nonisolated struct CalEvent: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var allDay = false
    var source: CalSourceKind
    var calendarID: String? = nil
    var tabName: String? = nil
    var location = ""
    var notes = ""
    var timeZone = TimeZone.current.identifier
    var repeatRule = CalRepeat()
    var completed = false
    var completedAt: Date? = nil
    /// Day keys of occurrences removed from a series ("this event" deletes and edits).
    var skips: Set<String> = []
}

/// One appearance of an event on the calendar (a repeating event has many).
nonisolated struct CalOccurrence: Identifiable, Hashable, Sendable {
    var event: CalEvent
    var start: Date
    var end: Date

    var id: String { event.id + "~" + String(Int(start.timeIntervalSince1970)) }
    var isSeries: Bool { event.repeatRule.repeats }
    var isNote: Bool { event.source == .notes || event.source == .tab }

    /// "9:00 - 9:30 AM", "All day", "Due 5:00 PM"
    var timeText: String {
        if event.allDay { return "All day" }
        let from = start.formatted(date: .omitted, time: .shortened)
        if end <= start { return "Due \(from)" }
        return "\(from) - \(end.formatted(date: .omitted, time: .shortened))"
    }
}

nonisolated enum CalMode: String, CaseIterable, Hashable, Sendable {
    case agenda = "Agenda", day = "Day", week = "Week", month = "Month"
}

nonisolated enum CalScope: String, CaseIterable, Hashable, Sendable {
    case this, series

    var title: String { self == .this ? "This event" : "All events in this series" }
}

// MARK: - Dates

nonisolated enum CalDates {
    /// Monday-first gregorian calendar in the phone's zone.
    static var cal: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.locale = Locale.current
        calendar.timeZone = TimeZone.current
        return calendar
    }

    static func day(_ date: Date) -> Date { cal.startOfDay(for: date) }
    static func add(_ days: Int, to date: Date) -> Date { cal.date(byAdding: .day, value: days, to: date) ?? date }
    static func weekStart(_ date: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: date)?.start ?? day(date) }
    static func monthStart(_ date: Date) -> Date { cal.dateInterval(of: .month, for: date)?.start ?? day(date) }
    static func at(_ date: Date, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }
    static func same(_ a: Date, _ b: Date) -> Bool { cal.isDate(a, inSameDayAs: b) }
    static func key(_ date: Date) -> String {
        let parts = cal.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// "Today", "Tomorrow" or "Tue, Nov 11".
    static func dayTitle(_ date: Date) -> String {
        if same(date, Date()) { return "Today" }
        if same(date, add(1, to: Date())) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Tuesday, November 11"
    static func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    static func countHeading(_ count: Int) -> String {
        switch count {
        case 0: "No events"
        case 1: "One event"
        case 2: "Two events"
        case 3: "Three events"
        default: "\(count) events"
        }
    }

    static func zoneLabel(_ id: String) -> String {
        let city = id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id
        let abbreviation = TimeZone(identifier: id)?.abbreviation() ?? ""
        return abbreviation.isEmpty ? city : "\(city) (\(abbreviation))"
    }

    static var commonZones: [String] {
        let list = ["America/Los_Angeles", "America/Denver", "America/Chicago", "America/New_York", "Europe/London",
                    "Europe/Paris", "Europe/Berlin", "Asia/Kolkata", "Asia/Tokyo", "Australia/Sydney", "UTC"]
        let here = TimeZone.current.identifier
        return [here] + list.filter { $0 != here }
    }
}

// MARK: - Data source

/// Where the calendar's items come from. The sample stands in until the desktop is connected.
protocol CalendarProviding {
    var accountEmail: String { get }
    func loadEvents() -> [CalEvent]
    func loadCalendars() -> [CalCalendar]
}

// MARK: - Store

@Observable
final class CalStore {
    /// One store for the session, so the view, the day and the hidden sources survive leaving Calendar.
    static let shared = CalStore(provider: CalSampleProvider())

    let accountEmail: String
    var events: [CalEvent]
    var calendars: [CalCalendar]
    var hiddenSources: Set<CalSourceKind> = []
    var googleConnected = true
    var mode: CalMode = .week
    var selected: Date
    var showEarly = false
    var debugApplied = false

    init(provider: CalendarProviding) {
        accountEmail = provider.accountEmail
        events = provider.loadEvents()
        calendars = provider.loadCalendars()
        selected = CalDates.day(Date())
    }

    var today: Date { CalDates.day(Date()) }

    // Looks

    func calendar(_ id: String?) -> CalCalendar? { calendars.first { $0.id == id } }

    func tint(_ event: CalEvent) -> Color {
        switch event.source {
        case .kairos: Palette.gold
        case .google: Color(hex: calendar(event.calendarID)?.colorHex ?? 0x5B8DB8)
        case .notes: Color(hex: CalSampleProvider.notesHex)
        case .tab: Color(hex: CalSampleProvider.tabHex)
        }
    }

    func sourceName(_ event: CalEvent) -> String {
        switch event.source {
        case .kairos: "Kairos"
        case .google: calendar(event.calendarID)?.name ?? "Google"
        case .notes: "Notes"
        case .tab: event.tabName ?? "Tab"
        }
    }

    func canEdit(_ event: CalEvent) -> Bool {
        switch event.source {
        case .kairos: true
        case .google: googleConnected && (calendar(event.calendarID)?.writable ?? false)
        case .notes, .tab: false
        }
    }

    func canComplete(_ event: CalEvent) -> Bool { event.source != .google && !event.repeatRule.repeats }

    var writableCalendars: [CalCalendar] { googleConnected ? calendars.filter(\.writable) : [] }

    /// New events go to the first writable Google calendar, or Kairos.
    var defaultCalendarID: String { writableCalendars.first?.id ?? "kairos" }

    func isVisible(_ event: CalEvent) -> Bool {
        if event.source == .google {
            return googleConnected && (calendar(event.calendarID)?.visible ?? true)
        }
        return !hiddenSources.contains(event.source)
    }

    // Reading

    func master(_ id: String) -> CalEvent? { events.first { $0.id == id } }

    func items(on day: Date) -> [CalOccurrence] {
        let start = CalDates.day(day)
        return items(from: start, to: CalDates.add(1, to: start))
    }

    func items(from start: Date, to end: Date) -> [CalOccurrence] {
        events
            .filter { !$0.completed && isVisible($0) }
            .flatMap { occurrences(of: $0, from: start, to: end) }
            .sorted { a, b in
                if a.event.allDay != b.event.allDay { return a.event.allDay }
                return a.start < b.start
            }
    }

    func occurrences(of event: CalEvent, from rangeStart: Date, to rangeEnd: Date) -> [CalOccurrence] {
        func overlaps(_ start: Date, _ end: Date) -> Bool {
            (end > rangeStart || start >= rangeStart) && start < rangeEnd
        }
        let rule = event.repeatRule
        guard rule.repeats else {
            return overlaps(event.start, event.end) ? [CalOccurrence(event: event, start: event.start, end: event.end)] : []
        }
        let length = event.end.timeIntervalSince(event.start)
        let cal = CalDates.cal
        var found: [CalOccurrence] = []
        var counted = 0
        var step = 0
        var current = event.start
        while current < rangeEnd && step < 3000 {
            if rule.end == .afterCount && counted >= rule.count { break }
            if rule.end == .onDate && CalDates.day(current) > CalDates.day(rule.until) { break }
            let weekday = cal.component(.weekday, from: current)
            let weekend = weekday == 1 || weekday == 7
            if !(rule.weekdaysOnly && weekend) {
                counted += 1
                let end = current.addingTimeInterval(length)
                if overlaps(current, end) && !event.skips.contains(CalDates.key(current)) {
                    found.append(CalOccurrence(event: event, start: current, end: end))
                }
            }
            step += 1
            let interval = max(1, rule.interval)
            switch rule.freq {
            case .monthly:
                current = cal.date(byAdding: .month, value: interval * step, to: event.start) ?? rangeEnd
            case .weekly:
                current = cal.date(byAdding: .day, value: 7 * interval * step, to: event.start) ?? rangeEnd
            default:
                current = cal.date(byAdding: .day, value: interval * step, to: event.start) ?? rangeEnd
            }
        }
        return found
    }

    /// The next appearance of an event with this title, from today on.
    func nextOccurrence(titled title: String) -> CalOccurrence? {
        guard let event = events.first(where: { $0.title == title }) else { return nil }
        return occurrences(of: event, from: today, to: CalDates.add(60, to: today)).first
    }

    var archived: [CalEvent] {
        events.filter(\.completed).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    // Periods

    func shift(_ step: Int) {
        switch mode {
        case .day: selected = CalDates.add(step, to: selected)
        case .week: selected = CalDates.add(7 * step, to: selected)
        case .agenda: selected = CalDates.add(14 * step, to: selected)
        case .month:
            selected = CalDates.cal.date(byAdding: .month, value: step, to: CalDates.monthStart(selected)) ?? selected
        }
    }

    func goToday() { selected = today }

    var periodLabel: String {
        switch mode {
        case .month:
            return selected.formatted(.dateTime.month(.wide).year())
        case .day:
            return selected.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            let start = CalDates.weekStart(selected)
            return range(start, CalDates.add(6, to: start))
        case .agenda:
            return range(selected, CalDates.add(13, to: selected))
        }
    }

    var showsToday: Bool {
        switch mode {
        case .day: CalDates.same(selected, today)
        case .week: CalDates.same(CalDates.weekStart(selected), CalDates.weekStart(today))
        case .month: CalDates.same(CalDates.monthStart(selected), CalDates.monthStart(today))
        case .agenda: CalDates.same(selected, today)
        }
    }

    private func range(_ start: Date, _ end: Date) -> String {
        let cal = CalDates.cal
        let first = start.formatted(.dateTime.month(.abbreviated).day())
        if cal.component(.month, from: start) == cal.component(.month, from: end) {
            return "\(first) - \(cal.component(.day, from: end))"
        }
        return "\(first) - \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// The cells of the month grid, Monday first; nil is a day outside the month.
    func monthCells() -> [Date?] {
        let cal = CalDates.cal
        let first = CalDates.monthStart(selected)
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let weekday = cal.component(.weekday, from: first)
        let lead = (weekday + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<days { cells.append(CalDates.add(offset, to: first)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    // Changes

    func insert(_ event: CalEvent) { events.append(event) }

    func replace(_ event: CalEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) { events[index] = event }
    }

    func deleteSeries(_ id: String) { events.removeAll { $0.id == id } }

    func deleteOccurrence(_ occurrence: CalOccurrence) {
        if let index = events.firstIndex(where: { $0.id == occurrence.event.id }) {
            events[index].skips.insert(CalDates.key(occurrence.start))
        }
    }

    /// "This event": lift one occurrence out of its series as its own event.
    func detach(_ occurrence: CalOccurrence, as single: CalEvent) {
        deleteOccurrence(occurrence)
        events.append(single)
    }

    func complete(_ id: String) {
        if let index = events.firstIndex(where: { $0.id == id }) {
            events[index].completed = true
            events[index].completedAt = Date()
        }
    }

    func reopen(_ id: String) {
        if let index = events.firstIndex(where: { $0.id == id }) {
            events[index].completed = false
            events[index].completedAt = nil
        }
    }

    func toggleSource(_ source: CalSourceKind) {
        if hiddenSources.contains(source) { hiddenSources.remove(source) } else { hiddenSources.insert(source) }
    }

    func setVisible(_ calendarID: String, _ visible: Bool) {
        if let index = calendars.firstIndex(where: { $0.id == calendarID }) { calendars[index].visible = visible }
    }
}
