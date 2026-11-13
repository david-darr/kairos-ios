import SwiftUI

/// Where a desktop read stands, for one plain sentence on screen.
nonisolated enum CalLiveLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// The sample calendar, kept aside while the phone shows the paired desktop's.
struct CalSampleStash {
    var events: [CalEvent]
    var calendars: [CalCalendar]
    var googleConnected: Bool
    var accountEmail: String
}

/// What the editor sends for a new or changed event. Times are what the phone showed; all-day ends are exclusive.
nonisolated struct CalLiveDraft: Sendable {
    var title: String
    var allDay: Bool
    var start: Date
    var end: Date
    var timeZone: String
    var location: String
    var notes: String
    var rule: CalRepeat
    /// "kairos" or a Google calendar id.
    var calendarID: String
}

/// The paired desktop behind Calendar: the range (GET /api/calendar/events), Google's calendars
/// (GET /api/google/status, GET /api/google/calendar/calendars, PATCH /api/google/calendar/settings),
/// the Archive, and every create, edit, delete and check-off. Unpaired, nothing here runs.
///
/// Writes are sent once and never retried. The screen changes only after the desktop says yes,
/// except a check-off and a calendar switch, which show at once and go back if the desktop refuses.
extension CalStore {

    /// A key that changes when the phone is paired or unpaired, the desktop comes back, or another desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// The range shown: the selected month's grid (six weeks), stretched to two weeks past the selected day for Agenda.
    var liveWindow: (start: Date, end: Date) {
        let start = CalDates.weekStart(CalDates.monthStart(selected))
        let end = max(CalDates.add(42, to: start), CalDates.add(15, to: CalDates.day(selected)))
        return (start, end)
    }

    /// Today and the next two weeks, for Upcoming under the month.
    var liveTodayWindow: (start: Date, end: Date) {
        (CalDates.add(-1, to: today), CalDates.add(15, to: today))
    }

    /// Changes when the live calendar must be read again.
    var liveRangeKey: String {
        "\(Self.connectionKey)|\(CalDates.key(liveWindow.start))|\(CalDates.key(liveWindow.end))|\(CalDates.key(today))"
    }

    private func stillLive(_ account: String) -> Bool {
        !isSample && liveAccount == account && Self.accountKey == account
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    // MARK: Following the connection

    func followConnection() {
        let wantLive = !Connection.shared.usesSampleData
        if wantLive && !isSample && liveAccount != Self.accountKey { resetLive() }
        guard wantLive == isSample else { return }
        if wantLive {
            sampleStash = CalSampleStash(events: events, calendars: calendars, googleConnected: googleConnected, accountEmail: accountEmail)
            resetLive()
            isSample = false
        } else {
            isSample = true
            liveLoad = .idle
            liveArchived = []
            liveGoogleNote = nil
            liveBusy = []
            liveLoadedKey = ""
            if let stash = sampleStash {
                events = stash.events
                calendars = stash.calendars
                googleConnected = stash.googleConnected
                accountEmail = stash.accountEmail
            }
            sampleStash = nil
        }
    }

    /// Nothing read from another desktop or account stays on screen.
    private func resetLive() {
        events = []
        calendars = []
        googleConnected = false
        accountEmail = "Google account"
        liveArchived = []
        liveGoogleNote = nil
        liveBusy = []
        liveLoad = .idle
        liveLoadedKey = ""
        liveGeneration += 1
        liveAccount = Self.accountKey
    }

    // MARK: Reading

    /// Read the shown range, today's two weeks, Google's calendars and the Archive.
    func loadLive() async {
        guard !isSample else { return }
        let account = liveAccount
        let key = liveRangeKey
        liveGeneration += 1
        let generation = liveGeneration
        if liveLoad != .loaded || liveLoadedKey != key { liveLoad = .loading }
        func current() -> Bool { stillLive(account) && liveGeneration == generation }

        await loadGoogleLive(account: account)
        guard current() else { return }
        do {
            let client = try liveClient()
            let window = liveWindow
            let around = liveTodayWindow
            var found = try await client.calendarEvents(start: window.start, end: window.end)
            guard current() else { return }
            if around.start < window.start || around.end > window.end {
                found += try await client.calendarEvents(start: around.start, end: around.end)
                guard current() else { return }
            }
            var seen = Set<String>()
            events = found.compactMap(CalendarWire.event).filter { seen.insert($0.id).inserted }
            liveLoadedKey = key
            liveLoad = .loaded
        } catch {
            Connection.shared.note(error)
            guard current() else { return }
            // Leaving the page stops the read; it is read again on the way back.
            if error is CancellationError {
                if liveLoad == .loading { liveLoad = .idle }
                return
            }
            // Items of another range must not stand in for this one.
            if liveLoadedKey != key { events = [] }
            liveLoad = .failed("Your calendar could not be read. " + error.plainWords)
        }
        await loadArchiveLive()
    }

    /// Google's account line and calendars. Google events come with the range; these say which calendars there are.
    private func loadGoogleLive(account: String) async {
        guard Connection.shared.desktop?.isAdmin == true else {
            googleConnected = false
            calendars = []
            liveGoogleNote = "Google calendars are managed by an admin on this Kairos."
            return
        }
        if !googleConnected && liveGoogleNote == nil { liveGoogleNote = "Reading your Google calendars." }
        do {
            let client = try liveClient()
            let status = try await client.googleStatus()
            guard stillLive(account) else { return }
            accountEmail = status.email ?? "Google account"
            guard status.connected == true else {
                googleConnected = false
                calendars = []
                liveGoogleNote = nil
                return
            }
            guard status.calendarConnected == true else {
                googleConnected = false
                calendars = []
                liveGoogleNote = "Google is connected without Calendar. Reconnect it on your desktop to add Calendar."
                return
            }
            let list = try await client.googleCalendars()
            guard stillLive(account) else { return }
            let chosen: Set<String>? = status.calendarIds.map { Set($0) }
            let mapped = list.map { item in
                CalCalendar(id: item.id, name: item.name ?? item.id,
                            colorHex: CalendarWire.hex(item.color) ?? 0x5B8DB8,
                            visible: chosen?.contains(item.id) ?? (item.selected ?? true),
                            writable: item.accessRole == "owner" || item.accessRole == "writer")
            }
            // New events go to the main calendar first, as on the desktop.
            let primary = Set(list.filter { $0.primary == true }.map(\.id))
            calendars = mapped.filter { primary.contains($0.id) } + mapped.filter { !primary.contains($0.id) }
            googleConnected = true
            liveGoogleNote = nil
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), !(error is CancellationError) else { return }
            googleConnected = false
            calendars = []
            liveGoogleNote = "Your Google calendars could not be read. " + error.plainWords
        }
    }

    /// Checked-off Kairos events and notes. A failed read keeps what was there.
    func loadArchiveLive() async {
        guard !isSample else { return }
        let account = liveAccount
        guard let client = try? liveClient() else { return }
        do {
            let done = try await client.calendarArchived().compactMap(CalendarWire.event)
            guard stillLive(account) else { return }
            let notes = (try? await client.calendarNotes())?.compactMap(CalendarWire.archivedNote) ?? []
            guard stillLive(account) else { return }
            liveArchived = (done + notes).sorted { ($0.completedAt ?? $0.start) > ($1.completedAt ?? $1.start) }
        } catch {
            Connection.shared.note(error)
        }
    }

    /// The series one event belongs to, for "All events in this series" (a Kairos series only).
    func liveSeries(of item: CalOccurrence) async throws -> CalEvent {
        guard let live = item.event.live else { throw APIError.notPaired }
        let read = try await liveClient().calendarSeries(live.id)
        guard var series = CalendarWire.event(read) else { throw APIError.unreadable("series") }
        series.live?.id = live.id
        series.live?.seriesID = live.seriesID
        return series
    }

    // MARK: Writing

    /// One plain sentence for a write that did not go through. A write the desktop never answered may still
    /// have happened, so it says to look before trying again rather than sending it again.
    private func writeProblem(_ error: Error, what: String) -> String {
        if let error = error as? APIError, error.isOffline {
            return "Your desktop did not confirm the change. Check your calendar before you try again."
        }
        return "\(what) " + error.plainWords
    }

    /// Create or change an event on the desktop. Returns nil when it is saved, else what went wrong.
    /// `editing` is the item being changed (nil for a new event); `scope` matters only for one event of a Kairos series.
    func saveLive(_ draft: CalLiveDraft, editing: CalOccurrence?, scope: CalScope) async -> String? {
        guard !isSample else { return "This calendar is a sample." }
        let busyKey = editing?.event.id ?? "new"
        guard !liveBusy.contains(busyKey) else { return "Wait a moment for the last change to save." }
        let account = liveAccount
        liveBusy.insert(busyKey)
        defer { if liveAccount == account { liveBusy.remove(busyKey) } }
        do {
            let client = try liveClient()
            let google = editing.map { $0.event.source == .google } ?? (draft.calendarID != "kairos")
            if google {
                let action: String = editing == nil ? "create" : "update"
                var body: [String: Any] = ["action": action]
                var event: [String: Any] = [
                    "summary": draft.title, "location": draft.location, "description": draft.notes,
                    "start": CalendarWire.googleBoundary(allDay: draft.allDay, draft.start, zone: draft.timeZone),
                    "end": CalendarWire.googleBoundary(allDay: draft.allDay, draft.end, zone: draft.timeZone),
                ]
                if let rule = CalendarWire.ruleJSON(draft.rule) { event["repeat"] = rule }
                body["event"] = event
                if let live = editing?.event.live {
                    guard live.readOnlyReason == nil, live.editable, let calendarID = live.calendarID else {
                        return "This event cannot be changed from your phone."
                    }
                    body["calendar_id"] = calendarID
                    body["event_id"] = live.id
                } else {
                    body["calendar_id"] = draft.calendarID
                }
                try await client.googleCalendarAction(body)
            } else {
                let sent = CalendarWire.boundaries(allDay: draft.allDay, start: draft.start, end: draft.end, zone: draft.timeZone)
                var body: [String: Any] = [
                    "title": draft.title, "start": sent.start, "end": sent.end, "all_day": draft.allDay,
                    "location": draft.location, "description": draft.notes, "time_zone": draft.timeZone,
                ]
                if let live = editing?.event.live {
                    let oneOfSeries = live.seriesID != nil
                    let justThis = oneOfSeries && scope == .this
                    let scopeText: String = justThis ? "occurrence" : "series"
                    body["scope"] = scopeText
                    // One event of a series keeps the series' rule; anything else sends its rule, or null to clear it.
                    // A rule the phone cannot show is never sent back (it would be cleared).
                    if !justThis && draft.rule.custom == nil {
                        if let rule = CalendarWire.ruleJSON(draft.rule) {
                            body["recurrence"] = rule
                        } else {
                            body["recurrence"] = NSNull()
                        }
                    }
                    try await client.calendarUpdate(live.id, body)
                } else {
                    if let rule = CalendarWire.ruleJSON(draft.rule) { body["recurrence"] = rule }
                    try await client.calendarCreate(body)
                }
            }
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return "Your calendar changed while this was saving." }
            let problem = writeProblem(error, what: "This event was not saved.")
            await loadLive()
            return problem
        }
        guard stillLive(account) else { return nil }
        await loadLive()
        return nil
    }

    /// Delete on the desktop, after the person confirmed in the delete sheet. nil when it is gone.
    func deleteLive(_ item: CalOccurrence, scope: CalScope) async -> String? {
        guard !isSample, let live = item.event.live else { return "This calendar is a sample." }
        guard !liveBusy.contains(item.event.id) else { return "Wait a moment for the last change to save." }
        guard live.readOnlyReason == nil, live.editable else { return "This event cannot be deleted from your phone." }
        let account = liveAccount
        liveBusy.insert(item.event.id)
        defer { if liveAccount == account { liveBusy.remove(item.event.id) } }
        do {
            let client = try liveClient()
            switch item.event.source {
            case .google:
                guard let calendarID = live.calendarID else { return "This event cannot be deleted from your phone." }
                try await client.googleCalendarAction(["action": "delete", "calendar_id": calendarID, "event_id": live.id])
            case .kairos:
                let oneOfSeries = live.seriesID != nil
                try await client.calendarDelete(live.id, scope: oneOfSeries && scope == .this ? "occurrence" : "series")
            case .notes, .tab:
                return "Delete this in the place it comes from."
            }
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return "Your calendar changed while this was deleting." }
            let problem = writeProblem(error, what: "This event was not deleted.")
            await loadLive()
            return problem
        }
        guard stillLive(account) else { return nil }
        withAnimation(Motion.snappy) {
            if item.isSeries && scope == .series, let series = live.seriesID {
                events.removeAll { $0.live?.seriesID == series }
            } else {
                events.removeAll { $0.id == item.event.id }
            }
        }
        await loadLive()
        return nil
    }

    /// Check off a Kairos event, a note or a tab item. It leaves at once and comes back if the desktop refuses.
    func completeLive(_ item: CalOccurrence, say: @escaping (String) -> Void) {
        guard !isSample, let live = item.event.live, canComplete(item.event), !liveBusy.contains(item.event.id) else { return }
        let path: String
        switch item.event.source {
        case .kairos: path = "/api/calendar/events/\(live.id)"
        case .notes: path = "/api/notes/\(live.id)"
        case .tab:
            guard let url = live.toggleURL else { return }
            path = url
        case .google: return
        }
        let account = liveAccount
        let id = item.event.id
        liveBusy.insert(id)
        guard let index = events.firstIndex(where: { $0.id == id }) else { liveBusy.remove(id); return }
        withAnimation(Motion.snappy) { events[index].completed = true }
        say("Done. It is in the Archive now.")
        Task {
            defer { if liveAccount == account { liveBusy.remove(id) } }
            do {
                try await liveClient().calendarSetCompleted(path: path, true)
                guard stillLive(account) else { return }
                await loadArchiveLive()
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if let back = events.firstIndex(where: { $0.id == id }) {
                    withAnimation(Motion.snappy) { events[back].completed = false }
                }
                say(writeProblem(error, what: "It was not checked off."))
            }
        }
    }

    /// Bring a checked-off event or note back. Returns nil when it is back, else what went wrong.
    func reopenLive(_ event: CalEvent) async -> String? {
        guard !isSample, let live = event.live else { return "This calendar is a sample." }
        guard !liveBusy.contains(event.id) else { return "Wait a moment for the last change to save." }
        let account = liveAccount
        liveBusy.insert(event.id)
        defer { if liveAccount == account { liveBusy.remove(event.id) } }
        let path = event.source == .notes ? "/api/notes/\(live.id)" : "/api/calendar/events/\(live.id)"
        do {
            try await liveClient().calendarSetCompleted(path: path, false)
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return nil }
            return writeProblem(error, what: "It was not reopened.")
        }
        guard stillLive(account) else { return nil }
        withAnimation(Motion.snappy) { liveArchived.removeAll { $0.id == event.id } }
        await loadLive()
        return nil
    }

    /// Show or hide one Google calendar. The switch moves at once and goes back if the desktop refuses.
    func setVisibleLive(_ calendarID: String, _ visible: Bool, notice: @escaping (String) -> Void) {
        guard !isSample, googleConnected, !liveBusy.contains("google-calendars") else { return }
        let account = liveAccount
        let before = calendars
        setVisible(calendarID, visible)
        let chosen = calendars.filter(\.visible).map(\.id)
        liveBusy.insert("google-calendars")
        Task {
            defer { if liveAccount == account { liveBusy.remove("google-calendars") } }
            do {
                _ = try await liveClient().googleCalendarSettings(chosen)
                guard stillLive(account) else { return }
                await loadLive()
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                withAnimation(Motion.snappy) { calendars = before }
                notice(writeProblem(error, what: "That calendar was not changed."))
            }
        }
    }
}

// MARK: - Shared pieces

/// One quiet line on the Calendar page while paired: reading, or what failed with Try again.
struct CalLiveLine: View {
    let text: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button {
                    Haptics.tap()
                    retry()
                } label: {
                    Text("Try again")
                        .font(KFont.ui(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.goldText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(minHeight: 48)
        .kCard(radius: 16)
    }
}
