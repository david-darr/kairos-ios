import Foundation

/// Made-up calendar items, placed around today so the calendar always looks lived in.
/// Nothing here is anyone's real data.
struct CalSampleProvider: CalendarProviding {
    static let notesHex: UInt32 = 0x8FA77E
    static let tabHex: UInt32 = 0x9C88B5

    var accountEmail: String { "you@example.com" }

    func loadCalendars() -> [CalCalendar] {
        [
            CalCalendar(id: "personal", name: "Personal", colorHex: 0x5B8DB8),
            CalCalendar(id: "team", name: "Team", colorHex: 0x6F9A5B),
            CalCalendar(id: "holidays", name: "Holidays", colorHex: 0xC27A5A, writable: false),
        ]
    }

    func loadEvents() -> [CalEvent] {
        let today = CalDates.day(Date())
        let week = CalDates.weekStart(today)
        func on(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date { CalDates.at(day, hour, minute) }
        func plus(_ days: Int) -> Date { CalDates.add(days, to: today) }
        let friday = CalDates.add(4, to: week)
        let tuesdayBefore = CalDates.add(-20, to: CalDates.add(1, to: week))

        var standupRule = CalRepeat(freq: .daily)
        standupRule.custom = "Every weekday"
        standupRule.weekdaysOnly = true

        let clubDay = plus(3)
        let clubStart = CalDates.cal.date(byAdding: .month, value: -2, to: clubDay) ?? clubDay

        return [
            CalEvent(id: "standup", title: "Team standup", start: on(CalDates.add(-21, to: week), 9, 30), end: on(CalDates.add(-21, to: week), 9, 45),
                     source: .google, calendarID: "team", location: "Video call", repeatRule: standupRule),
            CalEvent(id: "plants", title: "Water the plants", start: on(today, 8), end: on(today, 8), source: .notes),
            CalEvent(id: "stock", title: "Bike shop stock check", start: on(today, 11), end: on(today, 12), source: .kairos,
                     location: "Back room", notes: "Count tubes, chains and brake pads. Kip drafts the order after."),
            CalEvent(id: "supplier", title: "Supplier call", start: on(today, 11, 30), end: on(today, 12, 15), source: .google,
                     calendarID: "personal", notes: "Ask about the spring delivery dates."),
            CalEvent(id: "lunch", title: "Lunch with the design group", start: on(today, 13), end: on(today, 14), source: .google,
                     calendarID: "personal", location: "Corner cafe"),
            CalEvent(id: "review", title: "Design review", start: on(plus(1), 10), end: on(plus(1), 11), source: .google, calendarID: "team"),
            CalEvent(id: "dentist", title: "Dentist", start: on(plus(1), 15), end: on(plus(1), 16), source: .google,
                     calendarID: "personal", location: "Elm Street Dental"),
            CalEvent(id: "quote", title: "Send the Lakeside quote", start: on(plus(2), 10), end: on(plus(2), 10), source: .tab, tabName: "CRM"),
            CalEvent(id: "gym", title: "Gym", start: on(tuesdayBefore, 18), end: on(tuesdayBefore, 19), source: .kairos,
                     location: "Riverside gym", repeatRule: CalRepeat(freq: .weekly)),
            CalEvent(id: "club", title: "Book club", start: on(clubStart, 19), end: on(clubStart, 21), source: .kairos,
                     location: "Library reading room", repeatRule: CalRepeat(freq: .monthly)),
            CalEvent(id: "report", title: "Report due", start: on(friday, 17), end: on(friday, 17), source: .notes),
            CalEvent(id: "plan", title: "Plan next week", start: on(friday, 16), end: on(friday, 16, 30), source: .kairos),
            CalEvent(id: "trip", title: "Weekend trip", start: CalDates.add(5, to: week), end: CalDates.add(7, to: week), allDay: true,
                     source: .kairos, location: "Lake cabin"),
            CalEvent(id: "festival", title: "Harvest festival", start: plus(9), end: plus(10), allDay: true, source: .google, calendarID: "holidays"),
            CalEvent(id: "invoice", title: "Invoice the Hillside order", start: on(plus(6), 9), end: on(plus(6), 9), source: .tab, tabName: "CRM"),
            CalEvent(id: "insurance", title: "Renew bike insurance", start: on(plus(-2), 12), end: on(plus(-2), 12), source: .notes,
                     completed: true, completedAt: on(plus(-2), 12, 20)),
            CalEvent(id: "plumber", title: "Call the plumber", start: on(plus(-1), 10), end: on(plus(-1), 10, 30), source: .kairos,
                     completed: true, completedAt: on(plus(-1), 10, 40)),
        ]
    }
}
