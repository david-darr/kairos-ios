import SwiftUI

// The pieces of the Calendar page: the view switch, the period row, the week strip,
// the day timeline, the month grid and the agenda cards.

// MARK: - View switch

struct CalModeBar: View {
    @Bindable var store: CalStore
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalMode.allCases, id: \.self) { mode in
                let on = mode == store.mode
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { store.mode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(KFont.ui(14.5, on ? .semibold : .regular, relativeTo: .subheadline))
                        .foregroundStyle(on ? Palette.ink : Palette.inkDim)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if on { Capsule().fill(Palette.ink.opacity(0.14)).matchedGeometryEffect(id: "calmode", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .kCard(radius: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar view")
    }
}

// MARK: - Period row

struct CalNavRow: View {
    @Bindable var store: CalStore
    let onSources: () -> Void
    let onNew: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                Haptics.select()
                withAnimation(Motion.snappy) { store.goToday() }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.periodLabel)
                        .font(KFont.ui(20, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.numericText())
                    Text(store.showsToday ? "This period" : "Tap for today")
                        .font(KFont.ui(12.5, relativeTo: .caption))
                        .foregroundStyle(store.showsToday ? Palette.inkFaint : Palette.goldText)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .accessibilityLabel("Today")
            .accessibilityValue(store.periodLabel)
            .accessibilityHint("Go to today")

            PlannerRoundButton(symbol: "chevron.left", label: "Previous period") {
                withAnimation(Motion.snappy) { store.shift(-1) }
            }
            PlannerRoundButton(symbol: "chevron.right", label: "Next period") {
                withAnimation(Motion.snappy) { store.shift(1) }
            }
            PlannerRoundButton(symbol: "list.bullet", label: "Your calendars", action: onSources)
            PlannerRoundButton(symbol: "plus", label: "New event", tint: Palette.goldText, action: onNew)
        }
    }
}

// MARK: - Week strip

/// Seven days in a row with dots for what is on them. Tap a day; swipe sideways for the next or last week.
struct CalWeekStrip: View {
    @Bindable var store: CalStore
    @State private var forward = true

    var body: some View {
        let start = CalDates.weekStart(store.selected)
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { offset in
                dayButton(CalDates.add(offset, to: start))
            }
        }
        .padding(6)
        .id(CalDates.key(start))
        .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity), removal: .opacity))
        .kCard(radius: 24)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let width = value.translation.width
                    guard abs(width) > abs(value.translation.height), abs(width) > 50 else { return }
                    Haptics.select()
                    forward = width < 0
                    withAnimation(Motion.snappy) { store.shift(width < 0 ? 1 : -1) }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose a day")
        .accessibilityAction(named: "Next week") { store.shift(1) }
        .accessibilityAction(named: "Previous week") { store.shift(-1) }
    }

    private func dayButton(_ day: Date) -> some View {
        let selected = CalDates.same(day, store.selected)
        let today = CalDates.same(day, store.today)
        let items = store.items(on: day)
        return Button {
            Haptics.select()
            withAnimation(Motion.snappy) { store.selected = day }
        } label: {
            VStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(KFont.ui(12, .medium, relativeTo: .caption))
                    .foregroundStyle(today ? Palette.goldText : Palette.inkFaint)
                Text("\(CalDates.cal.component(.day, from: day))")
                    .font(KFont.ui(17, selected || today ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.onGold : (today ? Palette.goldText : Palette.ink))
                    .frame(width: 36, height: 36)
                    .background {
                        if selected {
                            Circle().fill(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                        } else if today {
                            Circle().strokeBorder(Palette.gold, lineWidth: 1.5)
                        }
                    }
                HStack(spacing: 3) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                        Circle().fill(store.tint(item.event)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityLabel("\(CalDates.longDay(day)), \(CalDates.countHeading(items.count))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Day timeline

/// One day as a timeline: an all-day row, hour lines, events side by side when they overlap,
/// and the current-time line on today. Starts at 7 AM unless early hours are shown.
struct CalTimeline: View {
    @Bindable var store: CalStore
    let day: Date
    let onOpen: (CalOccurrence) -> Void

    private let hourHeight: CGFloat = 54
    private let gutter: CGFloat = 52

    var body: some View {
        let items = store.items(on: day)
        let allDay = items.filter { isAllDay($0) }
        let timed = items.filter { !isAllDay($0) }
        let firstHour = store.showEarly ? 0 : 7
        let early = timed.filter { CalDates.cal.component(.hour, from: clampStart($0)) < 7 && clampEnd($0) <= CalDates.at(day, 7) }

        VStack(alignment: .leading, spacing: 10) {
            if !allDay.isEmpty {
                VStack(spacing: 6) {
                    ForEach(allDay) { item in
                        Button { onOpen(item) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(store.tint(item.event)).frame(width: 8, height: 8)
                                Text(item.event.title).font(KFont.ui(14.5, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(spanText(item)).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(store.tint(item.event).opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                        .accessibilityLabel("\(item.event.title), all day, \(store.sourceName(item.event))")
                    }
                }
            }

            if !early.isEmpty || store.showEarly {
                Button {
                    Haptics.tap()
                    withAnimation(Motion.snappy) { store.showEarly.toggle() }
                } label: {
                    Label(store.showEarly ? "Hide early hours" : earlyText(early.count),
                          systemImage: store.showEarly ? "chevron.up" : "chevron.down")
                        .font(KFont.ui(14, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.goldText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(firstHour..<24, id: \.self) { hour in
                            HStack(alignment: .top, spacing: 6) {
                                Text(CalDates.at(day, hour).formatted(.dateTime.hour()))
                                    .font(KFont.ui(11.5, relativeTo: .caption2))
                                    .foregroundStyle(Palette.inkFaint)
                                    .frame(width: gutter - 6, alignment: .trailing)
                                    .offset(y: -7)
                                Palette.line.frame(height: 1)
                            }
                            .frame(height: hourHeight, alignment: .top)
                        }
                    }
                    .accessibilityHidden(true)

                    GeometryReader { geometry in
                        let width = geometry.size.width - gutter - 4
                        ForEach(layout(timed, firstHour: firstHour)) { slot in
                            let laneWidth = width / CGFloat(slot.lanes)
                            block(slot)
                                .frame(width: max(20, laneWidth - 3), height: slot.height)
                                .offset(x: gutter + laneWidth * CGFloat(slot.lane), y: slot.top)
                        }
                        if CalDates.same(day, context.date) {
                            let minutes = minutesFrom(firstHour, to: context.date)
                            if minutes >= 0 {
                                HStack(spacing: 0) {
                                    Circle().fill(Palette.danger).frame(width: 9, height: 9)
                                    Palette.danger.frame(height: 1.5)
                                }
                                .frame(width: geometry.size.width - gutter + 8)
                                .offset(x: gutter - 8, y: CGFloat(minutes) / 60 * hourHeight - 4.5)
                                .accessibilityElement()
                                .accessibilityLabel("Current time")
                            }
                        }
                    }
                }
                .frame(height: CGFloat(24 - firstHour) * hourHeight)
            }
            .padding(.top, 8)
        }
    }

    // Layout

    private struct Slot: Identifiable {
        let item: CalOccurrence
        let lane: Int
        let lanes: Int
        let top: CGFloat
        let height: CGFloat
        var id: String { item.id }
    }

    private func isAllDay(_ item: CalOccurrence) -> Bool {
        if item.event.allDay { return true }
        let start = CalDates.day(day)
        return item.start <= start && item.end >= CalDates.add(1, to: start)
    }

    private func clampStart(_ item: CalOccurrence) -> Date { max(item.start, CalDates.day(day)) }
    private func clampEnd(_ item: CalOccurrence) -> Date {
        let end = item.end <= item.start ? item.start.addingTimeInterval(30 * 60) : item.end
        return min(end, CalDates.add(1, to: CalDates.day(day)))
    }

    private func minutesFrom(_ hour: Int, to date: Date) -> Double {
        date.timeIntervalSince(CalDates.at(day, hour)) / 60
    }

    private func layout(_ items: [CalOccurrence], firstHour: Int) -> [Slot] {
        let windowStart = CalDates.at(day, firstHour)
        let visible = items
            .filter { clampEnd($0) > windowStart }
            .sorted { clampStart($0) < clampStart($1) }
        var slots: [Slot] = []
        var cluster: [(CalOccurrence, Int)] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let lanes = max(1, laneEnds.count)
            for (item, lane) in cluster {
                let start = max(clampStart(item), windowStart)
                let top = CGFloat(start.timeIntervalSince(windowStart) / 3600) * hourHeight
                let length = CGFloat(clampEnd(item).timeIntervalSince(start) / 3600) * hourHeight
                slots.append(Slot(item: item, lane: lane, lanes: lanes, top: top, height: max(28, length - 2)))
            }
            cluster = []
            laneEnds = []
        }

        for item in visible {
            let start = max(clampStart(item), windowStart)
            let end = max(clampEnd(item), start.addingTimeInterval(28 * 60))
            if start >= clusterEnd { flush() }
            if let free = laneEnds.firstIndex(where: { $0 <= start }) {
                laneEnds[free] = end
                cluster.append((item, free))
            } else {
                laneEnds.append(end)
                cluster.append((item, laneEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, end)
        }
        flush()
        return slots
    }

    private func block(_ slot: Slot) -> some View {
        let tint = store.tint(slot.item.event)
        return Button { onOpen(slot.item) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.item.event.title)
                    .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(slot.height > 50 ? 2 : 1)
                if slot.height >= 44 {
                    Text(slot.item.timeText)
                        .font(KFont.ui(11.5, relativeTo: .caption2))
                        .foregroundStyle(Palette.inkDim)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tint.opacity(0.24))
            .overlay(alignment: .leading) { tint.frame(width: 3.5) }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .accessibilityLabel("\(slot.item.event.title), \(slot.item.timeText), \(store.sourceName(slot.item.event))")
    }

    private func spanText(_ item: CalOccurrence) -> String {
        guard item.event.allDay else { return "All day" }
        let days = CalDates.cal.dateComponents([.day], from: CalDates.day(item.start), to: CalDates.day(item.end)).day ?? 1
        guard days > 1 else { return "All day" }
        let index = (CalDates.cal.dateComponents([.day], from: CalDates.day(item.start), to: CalDates.day(day)).day ?? 0) + 1
        return "Day \(index) of \(days)"
    }

    private func earlyText(_ count: Int) -> String {
        count == 0 ? "Show early hours" : (count == 1 ? "Show early hours (1 before 7 AM)" : "Show early hours (\(count) before 7 AM)")
    }
}

// MARK: - Month grid

struct CalMonthGrid: View {
    @Bindable var store: CalStore
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let cells = store.monthCells()
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(KFont.ui(12, .medium, relativeTo: .caption))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    if let day = cell {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 54).accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(10)
        .kCard(radius: 24)
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = CalDates.same(day, store.selected)
        let today = CalDates.same(day, store.today)
        let items = store.items(on: day)
        return Button {
            Haptics.select()
            withAnimation(Motion.snappy) { store.selected = day }
        } label: {
            VStack(spacing: 4) {
                Text("\(CalDates.cal.component(.day, from: day))")
                    .font(KFont.ui(16, selected || today ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.onGold : (today ? Palette.goldText : Palette.ink))
                    .frame(width: 34, height: 34)
                    .background {
                        if selected {
                            Circle().fill(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                        } else if today {
                            Circle().strokeBorder(Palette.gold, lineWidth: 1.5)
                        }
                    }
                HStack(spacing: 3) {
                    ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { _, item in
                        Circle().fill(store.tint(item.event)).frame(width: 5, height: 5)
                    }
                    if items.count > 2 {
                        Text("+\(items.count - 2)")
                            .font(KFont.ui(9.5, .medium, relativeTo: .caption2))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel("\(CalDates.longDay(day)), \(CalDates.countHeading(items.count))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Agenda cards

/// One item as a card: a check for things you can finish, the colour, title, time and source,
/// and a menu with Edit and Delete for events you can change. Tap it to see it whole.
struct CalCard: View {
    @Bindable var store: CalStore
    let item: CalOccurrence
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onComplete: () -> Void

    var body: some View {
        let event = item.event
        HStack(spacing: 10) {
            if store.canComplete(event) {
                Button {
                    Haptics.success()
                    onComplete()
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.85))
                .accessibilityLabel("Mark complete: \(event.title)")
            }
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(store.tint(event))
                        .frame(width: 4, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(KFont.ui(16, .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(item.timeText)
                            Text("·")
                            Text(store.sourceName(event))
                            if item.isSeries {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10, weight: .semibold))
                                    .accessibilityLabel("Repeats")
                            }
                        }
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, store.canComplete(event) ? 0 : 14)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            if store.canEdit(event) {
                Menu {
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Delete event", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.inkDim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Event actions")
            }
        }
        .padding(.trailing, 6)
        .kCard(radius: 18)
    }
}

/// A day's heading and its cards, or the empty state.
struct CalDayPanel: View {
    @Bindable var store: CalStore
    let day: Date
    let actions: CalActions

    var body: some View {
        let items = store.items(on: day)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(CalDates.longDay(day))
                    .font(KFont.ui(19, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Text(store.showsEmpty || !items.isEmpty ? CalDates.countHeading(items.count) : "")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .contentTransition(.numericText())
            }
            if items.isEmpty {
                if store.showsEmpty {
                    PlannerEmpty(title: "Nothing on this day.", hint: "Make room for something new.", pose: .idle,
                                 actionTitle: "Add an event") { actions.new(day) }
                }
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    actions.card(store, item).arrives(index)
                }
            }
        }
    }
}

/// What a card can ask the page to do. The page owns the sheets.
struct CalActions {
    let open: (CalOccurrence) -> Void
    let edit: (CalOccurrence) -> Void
    let delete: (CalOccurrence) -> Void
    let complete: (CalOccurrence) -> Void
    let new: (Date) -> Void

    func card(_ store: CalStore, _ item: CalOccurrence) -> CalCard {
        CalCard(store: store, item: item,
                onOpen: { open(item) }, onEdit: { edit(item) },
                onDelete: { delete(item) }, onComplete: { complete(item) })
    }
}

/// Days with their items, grouped under a date heading. Used by Agenda and by Upcoming.
struct CalGroupedList: View {
    @Bindable var store: CalStore
    let from: Date
    let days: Int
    let actions: CalActions

    var body: some View {
        let groups = (0..<days).compactMap { offset -> (Date, [CalOccurrence])? in
            let day = CalDates.add(offset, to: from)
            let items = store.items(on: day)
            return items.isEmpty ? nil : (day, items)
        }
        VStack(alignment: .leading, spacing: 16) {
            if groups.isEmpty && store.showsEmpty {
                PlannerEmpty(title: "Nothing coming up.", hint: "Make room for something new.", pose: .idle,
                             actionTitle: "Add an event") { actions.new(from) }
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: CalDates.dayTitle(group.0))
                    ForEach(group.1) { item in actions.card(store, item) }
                }
                .arrives(index)
            }
        }
    }
}

/// The calendars present this week, with their colours.
struct CalLegend: View {
    @Bindable var store: CalStore

    var body: some View {
        let start = CalDates.weekStart(store.selected)
        let items = store.items(from: start, to: CalDates.add(7, to: start))
        var seen = Set<String>()
        let names: [(String, Color)] = items.compactMap { item in
            let name = store.sourceName(item.event)
            guard !seen.contains(name) else { return nil }
            seen.insert(name)
            return (name, store.tint(item.event))
        }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(names, id: \.0) { entry in
                    HStack(spacing: 6) {
                        Circle().fill(entry.1).frame(width: 8, height: 8)
                        Text(entry.0).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(Palette.ink.opacity(0.07), in: Capsule())
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calendars this week: " + names.map(\.0).joined(separator: ", "))
    }
}
