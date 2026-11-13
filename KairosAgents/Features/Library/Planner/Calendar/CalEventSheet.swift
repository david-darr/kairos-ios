import SwiftUI

// MARK: - Event details

/// An event seen whole: when, where, how it repeats, and what you can do with it.
struct CalDetailSheet: View {
    @Bindable var store: CalStore
    let item: CalOccurrence
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onComplete: () -> Void
    let onOpenSource: () -> Void

    var body: some View {
        let event = item.event
        FittedSheet(estimate: 520) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(store.tint(event))
                        .frame(width: 6, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(KFont.display(30))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Chip(text: store.sourceName(event), symbol: sourceSymbol(event.source))
                    }
                }
                .padding(.top, 34)

                VStack(spacing: 0) {
                    infoRow("calendar", dateText)
                    infoRow("clock", item.timeText)
                    if !event.allDay && event.timeZone != TimeZone.current.identifier {
                        infoRow("globe", CalDates.zoneLabel(event.timeZone))
                    }
                    if event.repeatRule.repeats { infoRow("arrow.triangle.2.circlepath", event.repeatRule.summary) }
                    if !event.location.isEmpty { infoRow("mappin.and.ellipse", event.location) }
                    if !event.notes.isEmpty { infoRow("text.alignleft", event.notes) }
                }
                .kCard(radius: 20)

                if let note = sourceNote(event) {
                    Text(note)
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                }

                VStack(spacing: 10) {
                    if store.canComplete(event) {
                        PlannerPill(title: "Mark complete", symbol: "checkmark", style: .gold, expand: true, action: onComplete)
                    }
                    if store.canEdit(event) {
                        HStack(spacing: 10) {
                            PlannerPill(title: "Edit", symbol: "pencil", style: .quiet, expand: true, action: onEdit)
                            PlannerPill(title: "Delete", symbol: "trash", style: .danger, expand: true, action: onDelete)
                        }
                    }
                    if event.source == .notes {
                        PlannerPill(title: "Open Notes", symbol: "note.text", style: .outline, expand: true, action: onOpenSource)
                    } else if event.source == .tab {
                        PlannerPill(title: "Open \(event.tabName ?? "the tab")", symbol: "square.grid.2x2", style: .outline, expand: true, action: onOpenSource)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var dateText: String {
        let event = item.event
        if event.allDay {
            let last = CalDates.add(-1, to: item.end)
            if !CalDates.same(item.start, last) && last > item.start {
                return "\(item.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) to \(last.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
            }
        }
        return CalDates.longDay(item.start)
    }

    private func sourceNote(_ event: CalEvent) -> String? {
        if let reason = event.live?.readOnlyReason { return reason }
        switch event.source {
        case .notes: return "This is a note with a due time. Change it in Notes."
        case .tab: return "This deadline comes from the \(event.tabName ?? "tab") tab."
        case .google where !(store.calendar(event.calendarID)?.writable ?? true): return "This calendar is read-only."
        default: return nil
        }
    }

    private func sourceSymbol(_ source: CalSourceKind) -> String {
        switch source {
        case .kairos: "sparkle"
        case .google: "calendar"
        case .notes: "note.text"
        case .tab: "square.grid.2x2"
        }
    }

    private func infoRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 22)
            Text(text)
                .font(KFont.ui(15.5))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 50) }
    }
}

// MARK: - New and edit

private struct CalDraft: Equatable {
    var title = ""
    var calendarID = "kairos"
    var allDay = false
    var start = Date()
    var end = Date()
    var rule = CalRepeat()
    var timeZone = TimeZone.current.identifier
    var location = ""
    var notes = ""

    init() {}

    init(_ event: CalEvent, start: Date, end: Date) {
        title = event.title
        calendarID = event.source == .google ? (event.calendarID ?? "kairos") : "kairos"
        allDay = event.allDay
        self.start = start
        self.end = end
        rule = event.repeatRule
        timeZone = event.timeZone
        location = event.location
        notes = event.notes
    }
}

/// "New event" and "Edit event": title, calendar, timing with repeat and time zone, and details.
struct CalEventEditor: View {
    @Bindable var store: CalStore
    /// nil for a new event.
    let item: CalOccurrence?
    let onSaved: (String) -> Void
    let onDelete: (CalOccurrence) -> Void

    @State private var draft: CalDraft
    @State private var scope: CalScope
    @State private var error: String?
    /// Paired: the save is on its way to the desktop, so Save sends nothing more.
    @State private var saving = false
    /// Paired: the whole series is being read, or could not be, so Save waits.
    @State private var seriesPending = false
    /// Paired: the values as read for the event being changed, so only what the person changed is sent. nil for a new event.
    @State private var baseline: CalDraft?
    /// Paired: a new event the desktop never confirmed and that was not found after. Add says "Add again".
    @State private var unconfirmed = false
    @Environment(\.dismiss) private var dismiss

    init(store: CalStore, newOn day: Date, onSaved: @escaping (String) -> Void) {
        _store = Bindable(store)
        item = nil
        self.onSaved = onSaved
        onDelete = { _ in }
        var draft = CalDraft()
        draft.calendarID = store.defaultCalendarID
        draft.start = CalDates.at(day, 9)
        draft.end = CalDates.at(day, 9, 30)
        _draft = State(initialValue: draft)
        _scope = State(initialValue: .series)
    }

    init(store: CalStore, editing item: CalOccurrence, scope: CalScope, onSaved: @escaping (String) -> Void, onDelete: @escaping (CalOccurrence) -> Void) {
        _store = Bindable(store)
        self.item = item
        self.onSaved = onSaved
        self.onDelete = onDelete
        let useScope: CalScope = item.isSeries ? scope : .series
        _scope = State(initialValue: useScope)
        let first = CalEventEditor.draft(for: item, scope: useScope, store: store)
        _draft = State(initialValue: first)
        _baseline = State(initialValue: first)
    }

    private static func draft(for item: CalOccurrence, scope: CalScope, store: CalStore) -> CalDraft {
        if scope == .series, item.isSeries, let master = store.master(item.event.id) {
            return CalDraft(master, start: master.start, end: master.end)
        }
        var draft = CalDraft(item.event, start: item.start, end: item.end)
        if scope == .this { draft.rule = CalRepeat() }
        return draft
    }

    private var editing: Bool { item != nil }
    private var showsRepeat: Bool { !(editing && item?.isSeries == true && scope == .this) }
    /// Paired, on a Google calendar: no repeat choice. The phone could not change or delete a repeating Google event after.
    private var googleTarget: Bool { !store.isSample && (draft.calendarID != "kairos" || item?.event.source == .google) }

    private var saveTitle: String {
        if saving { return "Saving..." }
        if editing { return "Save" }
        return unconfirmed ? "Add again" : "Add"
    }

    /// The All day switch. Only a tap by the person moves the times to whole days or to 9:00 to 9:30;
    /// a draft loaded from the desktop (a series, one event) keeps its own times.
    private var allDayBinding: Binding<Bool> {
        Binding(get: { draft.allDay }, set: { allDay in
            guard allDay != draft.allDay else { return }
            draft.allDay = allDay
            if allDay {
                draft.start = CalDates.day(draft.start)
                draft.end = max(CalDates.add(1, to: draft.start), CalDates.day(draft.end))
            } else {
                draft.start = CalDates.at(draft.start, 9)
                draft.end = CalDates.at(draft.start, 9, 30)
            }
        })
    }

    /// Paired: a last date picked for "On a date" starts at the first event, since the desktop refuses one before it.
    private var repeatEndBinding: Binding<CalRepeatEnd> {
        Binding(get: { draft.rule.end }, set: { end in
            draft.rule.end = end
            if !store.isSample && end == .onDate && CalDates.day(draft.rule.until) < CalDates.day(draft.start) {
                draft.rule.until = draft.start
            }
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PlannerSheetTitle(title: editing ? "Edit event" : "New event") {
                    // Paired: while a save is on its way the sheet stays, so its result is always shown here.
                    Button("Cancel") { dismiss() }
                        .font(KFont.ui(16, .medium))
                        .foregroundStyle(Palette.inkDim)
                        .frame(minHeight: 44)
                        .disabled(saving)
                        .opacity(saving ? 0.4 : 1)
                } trailing: {
                    PlannerPill(title: saveTitle, style: .gold, action: save)
                        .disabled(saving || seriesPending)
                }

                PlannerTextField(label: "Title", placeholder: "e.g. Bike shop stock check", text: $draft.title,
                                 error: error == "Enter a title, start and end" ? error : nil)

                if editing, item?.isSeries == true {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Apply changes to")
                        PlannerMenuRow(title: "Change", options: CalScope.allCases, selection: $scope, label: \.title, last: true)
                            .kCard(radius: 18)
                            .disabled(saving)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "When")
                    VStack(spacing: 0) {
                        PlannerToggleRow(title: "All day", symbol: "sun.max", isOn: allDayBinding)
                        dateRow(draft.allDay ? "Starts" : "Starts", selection: $draft.start)
                        dateRow(draft.allDay ? "Ends (exclusive)" : "Ends", selection: $draft.end)
                        if showsRepeat {
                            if googleTarget { googleRepeatNote } else { repeatRows }
                        }
                        if !draft.allDay {
                            PlannerMenuRow(title: "Time zone", symbol: "globe", options: CalDates.commonZones,
                                           selection: $draft.timeZone, label: CalDates.zoneLabel, last: true)
                        }
                    }
                    .kCard(radius: 20)
                    if !showsRepeat {
                        Text("Only this event changes. The rest of the series stays as it is.")
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Details")
                    calendarRow.kCard(radius: 18)
                }
                PlannerTextField(label: "Location", placeholder: "Add a place", text: $draft.location)
                PlannerTextField(label: "Description", placeholder: "Notes for this event", text: $draft.notes, multiline: true)

                if let error, error != "Enter a title, start and end" {
                    Text(error)
                        .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.danger)
                        .transition(.opacity)
                } else if error != nil {
                    Text("Enter a title, start and end")
                        .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.danger)
                }

                if let item, editing {
                    PlannerPill(title: "Delete event", symbol: "trash", style: .danger, expand: true) { onDelete(item) }
                        .disabled(saving)
                        .opacity(saving ? 0.4 : 1)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .tint(Palette.gold)
        .animation(Motion.snappy, value: draft)
        .animation(Motion.snappy, value: error)
        .interactiveDismissDisabled(saving)
        .onChange(of: scope) { _, newScope in
            guard let item else { return }
            // Loads set the fields directly; the All day switch's own handler never runs for them.
            if store.isSample {
                draft = CalEventEditor.draft(for: item, scope: newScope, store: store)
            } else if newScope == .series && item.isSeries {
                loadSeries(item)
            } else {
                seriesPending = false
                let one = CalEventEditor.draft(for: item, scope: .this, store: store)
                draft = one
                baseline = one
            }
        }
        .onChange(of: draft.title) { if error != nil { error = nil } }
        .task {
            if !store.isSample, let item, item.isSeries, scope == .series { loadSeries(item) }
        }
    }

    /// Paired: read the whole series before "All events in this series" can be saved, as the desktop does.
    /// If it cannot be read, Save stays off: the fields of one event must never be saved over the series.
    private func loadSeries(_ item: CalOccurrence) {
        seriesPending = true
        error = nil
        Task {
            do {
                let series = try await store.liveSeries(of: item)
                guard scope == .series else { return }
                let whole = CalDraft(series, start: series.start, end: series.end)
                draft = whole
                baseline = whole
                seriesPending = false
            } catch let failure {
                guard scope == .series else { return }
                withAnimation(Motion.snappy) { error = "The series could not be read. " + failure.plainWords }
            }
        }
    }

    // Rows

    private func dateRow(_ title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: title.hasPrefix("Starts") ? "clock" : "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 26)
            Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
            Spacer(minLength: 6)
            DatePicker(title, selection: selection, displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 54) }
    }

    /// In place of the repeat rows for a Google calendar while paired.
    private var googleRepeatNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.inkFaint)
                .frame(width: 26)
            Text("Events on a Google calendar cannot repeat from your phone. Make a repeating one on your desktop.")
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 54) }
    }

    @ViewBuilder private var repeatRows: some View {
        if let custom = draft.rule.custom {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeats: \(custom)").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    Text("This custom rule was made in Google. It is kept as it is.")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 54) }
        } else {
            PlannerMenuRow(title: "Repeat", symbol: "arrow.triangle.2.circlepath", options: CalRepeatFreq.allCases,
                           selection: $draft.rule.freq, label: \.title)
            if draft.rule.freq != .none {
                stepperRow(text: "Every \(draft.rule.interval) \(draft.rule.freq.unit(draft.rule.interval))",
                           value: $draft.rule.interval, range: 1...365)
                PlannerMenuRow(title: "Ends", symbol: "flag.checkered", options: CalRepeatEnd.allCases,
                               selection: repeatEndBinding, label: \.title)
                if draft.rule.end == .onDate {
                    HStack {
                        Text("Last date").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        Spacer()
                        DatePicker("Last date", selection: $draft.rule.until, in: draft.start..., displayedComponents: [.date])
                            .labelsHidden()
                    }
                    .padding(.leading, 54)
                    .padding(.trailing, 16)
                    .frame(minHeight: 54)
                    .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 54) }
                }
                if draft.rule.end == .afterCount {
                    stepperRow(text: "After \(draft.rule.count) \(draft.rule.count == 1 ? "event" : "events")",
                               value: $draft.rule.count, range: 1...10_000)
                }
                if draft.rule.freq == .monthly {
                    Text("Repeats on day \(CalDates.cal.component(.day, from: draft.start)) of each month. In shorter months it moves to the last day.")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.leading, 54)
                        .padding(.trailing, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 54) }
                }
            }
        }
    }

    private func stepperRow(text: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            Text(text).font(KFont.ui(16)).foregroundStyle(Palette.ink).contentTransition(.numericText())
        }
        .padding(.leading, 54)
        .padding(.trailing, 16)
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 54) }
    }

    private struct CalOption: Identifiable {
        let id: String
        let name: String
        let color: Color
    }

    private var calendarOptions: [CalOption] {
        var options = [CalOption(id: "kairos", name: "Kairos", color: Palette.gold)]
        for calendar in store.writableCalendars {
            options.append(CalOption(id: calendar.id, name: calendar.name, color: Color(hex: calendar.colorHex)))
        }
        return options
    }

    private var calendarRow: some View {
        let current = calendarOptions.first { $0.id == draft.calendarID } ?? calendarOptions[0]
        return Menu {
            ForEach(calendarOptions) { option in
                Button {
                    Haptics.select()
                    draft.calendarID = option.id
                } label: {
                    if option.id == draft.calendarID {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Circle().fill(current.color).frame(width: 12, height: 12).frame(width: 26)
                Text("Calendar").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(current.name).font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                Image(systemName: editing ? "lock" : "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .disabled(editing)
        .accessibilityLabel("Calendar: \(current.name)")
        .accessibilityHint(editing ? "The calendar cannot change after an event is made" : "")
    }

    // Save

    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            Haptics.thud()
            withAnimation(Motion.snappy) { error = "Enter a title, start and end" }
            return
        }
        let valid = draft.allDay ? CalDates.day(draft.end) > CalDates.day(draft.start) : draft.end > draft.start
        guard valid else {
            Haptics.thud()
            withAnimation(Motion.snappy) { error = "End must be after start" }
            return
        }
        let start = draft.allDay ? CalDates.day(draft.start) : draft.start
        let end = draft.allDay ? CalDates.day(draft.end) : draft.end
        let google = draft.calendarID != "kairos"

        if !store.isSample {
            saveLive()
            return
        }

        if let item {
            if item.isSeries && scope == .this {
                let single = CalEvent(id: UUID().uuidString, title: title, start: start, end: end, allDay: draft.allDay,
                                  source: item.event.source, calendarID: item.event.calendarID, tabName: item.event.tabName,
                                  location: draft.location, notes: draft.notes, timeZone: draft.timeZone)
                store.detach(item, as: single)
            } else if var master = store.master(item.event.id) {
                master.title = title
                master.start = start
                master.end = end
                master.allDay = draft.allDay
                master.repeatRule = draft.rule
                master.timeZone = draft.timeZone
                master.location = draft.location
                master.notes = draft.notes
                store.replace(master)
            }
            Haptics.success()
            onSaved("Event saved")
        } else {
            store.insert(CalEvent(id: UUID().uuidString, title: title, start: start, end: end, allDay: draft.allDay,
                                  source: google ? .google : .kairos, calendarID: google ? draft.calendarID : nil,
                                  location: draft.location, notes: draft.notes, timeZone: draft.timeZone, repeatRule: draft.rule))
            store.selected = CalDates.day(start)
            Haptics.success()
            onSaved("Event created")
        }
        dismiss()
    }

    /// What the phone would send for these values: trimmed title, whole days for all day, and no rule where none can go.
    private func liveDraft(_ values: CalDraft) -> CalLiveDraft {
        let keepsRule = showsRepeat && !googleTarget
        return CalLiveDraft(title: values.title.trimmingCharacters(in: .whitespacesAndNewlines), allDay: values.allDay,
                            start: values.allDay ? CalDates.day(values.start) : values.start,
                            end: values.allDay ? CalDates.day(values.end) : values.end,
                            timeZone: values.timeZone, location: values.location, notes: values.notes,
                            rule: keepsRule ? values.rule : CalRepeat(), calendarID: values.calendarID)
    }

    /// Paired: Save is the confirmation. It is sent once and never again by itself; the sheet stays until the desktop
    /// answers, and the answer (saved, refused, or not confirmed) is always shown.
    private func saveLive() {
        guard !saving, !seriesPending else { return }
        let live = liveDraft(draft)
        let before = baseline.map { liveDraft($0) }
        saving = true
        error = nil
        Task {
            let outcome = await store.saveLive(live, baseline: before, editing: item, scope: scope)
            saving = false
            switch outcome {
            case .failed(let problem):
                Haptics.thud()
                withAnimation(Motion.snappy) { error = problem }
                return
            case .unconfirmed(let problem):
                // Not found after a create nobody confirmed. What was typed stays; Add says it would send it again.
                Haptics.thud()
                unconfirmed = true
                withAnimation(Motion.snappy) { error = problem }
                return
            case .unchanged:
                onSaved("Nothing changed.")
                dismiss()
                return
            case .saved, .savedUnconfirmed:
                break
            }
            if item == nil { store.selected = CalDates.day(live.start) }
            Haptics.success()
            if outcome == .savedUnconfirmed {
                onSaved("Event created. Your desktop was slow to confirm it, but it is on your calendar.")
            } else {
                onSaved(item == nil ? "Event created" : "Event saved")
            }
            dismiss()
        }
    }
}

// MARK: - Delete

/// "Delete this event?" with the choice of one or the whole series for repeating events.
struct CalDeleteSheet: View {
    @Bindable var store: CalStore
    let item: CalOccurrence
    let onDeleted: (String) -> Void

    @State private var scope: CalScope = .this
    @State private var deleting = false
    /// Paired: why the desktop did not delete it.
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 420) {
            VStack(spacing: 16) {
                Image(systemName: "trash")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.danger)
                    .frame(width: 56, height: 56)
                    .background(Palette.danger.opacity(0.12), in: Circle())
                    .padding(.top, 34)
                Text("Delete this event?")
                    .font(KFont.ui(21, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Text("\u{201C}\(item.event.title)\u{201D} will be permanently removed from your calendar.")
                    .font(KFont.ui(15.5))
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if item.isSeries {
                    PlannerMenuRow(title: "Delete", options: CalScope.allCases, selection: $scope, label: \.title, last: true)
                        .kCard(radius: 18)
                        .disabled(sending)
                }
                if let problem {
                    Text(problem)
                        .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                VStack(spacing: 4) {
                    PlannerPill(title: deleting ? "Deleting..." : "Delete event", symbol: "trash", style: .danger, expand: true, action: delete)
                        .disabled(deleting)
                    // Paired: while the delete is on its way the sheet stays, so its result is always shown here.
                    QuietButton(title: "Cancel") { dismiss() }
                        .disabled(sending)
                        .opacity(sending ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .interactiveDismissDisabled(sending)
    }

    /// Paired and the delete is on its way to the desktop.
    private var sending: Bool { deleting && !store.isSample }

    private func delete() {
        guard !deleting else { return }
        deleting = true
        if !store.isSample {
            // Paired: this sheet is the confirmation. Sent once; the sheet closes only when the desktop has deleted it.
            problem = nil
            Task {
                if let why = await store.deleteLive(item, scope: scope) {
                    Haptics.thud()
                    withAnimation(Motion.snappy) { problem = why }
                    deleting = false
                    return
                }
                Haptics.success()
                onDeleted("Event deleted")
                dismiss()
            }
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(Motion.snappy) {
                if item.isSeries && scope == .this {
                    store.deleteOccurrence(item)
                } else {
                    store.deleteSeries(item.event.id)
                }
            }
            Haptics.success()
            onDeleted("Event deleted")
            dismiss()
        }
    }
}
