import SwiftUI

// The automation calendar (a day at a time, with a month jump) and the all-bots Automations page.

private struct CalendarEntry: Identifiable {
    let id: String
    let routine: Routine
    let hour: Int
    let minute: Int
    /// Where it sits on the grid, in hours. A paired run before the first hour or after the last is drawn at the edge
    /// with its own time on it.
    var slot: Double? = nil

    var place: Double { slot ?? Double(hour) + Double(minute) / 60 }
}

/// One day of scheduled runs. Week strip on top, an hour grid below, a month sheet behind the title.
struct CalendarDayView: View {
    let botID: String?
    var onEdit: (Routine) -> Void = { _ in }
    let store = BotsStore.shared
    let live = BotsRoutinesLive.shared
    @State private var day = Date()
    @State private var monthOpen = false
    @State private var picked: Routine?
    @State private var newAt: Int?
    @State private var newName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let firstHour = 6
    private let lastHour = 23
    private let hourHeight: CGFloat = 64

    private var isLive: Bool { !Connection.shared.usesSampleData }

    /// The Monday that starts the shown week, at midnight.
    private var week: Date {
        let calendar = Calendar.current
        let offset = RoutineTiming.weekday(of: day).rawValue
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: day) ?? day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
            weekStrip
            if isLive {
                BotsLoadNote(state: live.shown(live.calendarLoad), waiting: "Reading the week from your desktop.") {
                    Task { await live.loadCalendar(week: week) }
                }
            }
            grid
        }
        .sheet(isPresented: $monthOpen) { monthSheet }
        .sheet(item: $picked) { routine in
            AutomationDetailSheet(routine: routine) { onEdit(routine) }
        }
        .sheet(isPresented: Binding(get: { newAt != nil }, set: { if !$0 { newAt = nil } })) { newSheet }
        .task(id: "\(BotsRoutinesLive.connectionKey)|\(week.timeIntervalSince1970)") {
            live.followConnection()
            guard isLive else { return }
            await live.loadIfNeeded()
            await live.loadCalendar(week: week)
            if live.limitsLoad != .loaded { await live.loadLimits() }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tap()
                monthOpen = true
            } label: {
                HStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkFaint)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Opens the month to jump to any day")
            Spacer()
            if !Calendar.current.isDateInToday(day) {
                PillButton(title: "Today") { move(to: Date()) }
            }
            roundButton("chevron.left", "Previous day") { shift(-1) }
            roundButton("chevron.right", "Next day") { shift(1) }
        }
    }

    private func roundButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.ink.opacity(0.08), in: Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    private var weekStrip: some View {
        let calendar = Calendar.current
        let offset = RoutineTiming.weekday(of: day).rawValue
        let monday = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                let date = calendar.date(byAdding: .day, value: index, to: monday) ?? monday
                let on = calendar.isDate(date, inSameDayAs: day)
                let has = !entries(for: date).isEmpty
                Button {
                    Haptics.select()
                    move(to: date)
                } label: {
                    VStack(spacing: 3) {
                        Text(Weekday(rawValue: index)?.letter ?? "").font(KFont.ui(12, relativeTo: .caption))
                            .foregroundStyle(on ? Palette.onGold : Palette.inkFaint)
                        Text("\(calendar.component(.day, from: date))").font(KFont.ui(16, .semibold))
                            .foregroundStyle(on ? Palette.onGold : Palette.ink)
                        Circle().fill(has ? (on ? Palette.onGold : Palette.gold) : Color.clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressStyle(scale: 0.92))
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day()))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .kCard(radius: 20)
    }

    // MARK: Grid

    private var grid: some View {
        let list = entries(for: day)
        let places = placements(list)
        let hours = Array(firstHour...lastHour)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { hour in
                    if isLive {
                        // Paired, a new routine is made in the full editor (Add a routine), never from a sample shortcut.
                        hourLine(hour).accessibilityElement(children: .combine)
                    } else {
                        Button {
                            Haptics.tap()
                            newName = ""
                            newAt = hour
                        } label: {
                            hourLine(hour)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New routine at \(clockText(hour, 0))")
                    }
                }
            }
            if isLive { liveResetMarker } else { resetMarker }
            if Calendar.current.isDateInToday(day) { nowLine }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                block(entry, lane: places[entry.id]?.lane ?? 0, lanes: places[entry.id]?.lanes ?? 1)
            }
            if list.isEmpty && (!isLive || (live.calendarLoad == .loaded && live.calendarWeek == week)) {
                Text(isLive ? "Nothing is scheduled on this day." : "Nothing is scheduled on this day. Tap an hour to add a routine.")
                    .font(KFont.ui(14.5)).foregroundStyle(Palette.inkFaint)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .kCard(radius: 16)
                    .padding(.leading, 52)
                    .padding(.top, hourHeight * 3)
                    .allowsHitTesting(false)
            }
        }
        .padding(.top, 8)
        .animation(reduceMotion ? nil : Motion.snappy, value: day)
    }

    private func hourLine(_ hour: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(hourLabel(hour)).font(KFont.ui(11.5, relativeTo: .caption2)).foregroundStyle(Palette.inkFaint)
                .frame(width: 44, alignment: .trailing)
                .offset(y: -7)
            VStack { Palette.line.frame(height: 1); Spacer(minLength: 0) }
        }
        .frame(height: hourHeight)
        .contentShape(Rectangle())
    }

    private func block(_ entry: CalendarEntry, lane: Int, lanes: Int) -> some View {
        let bot = store.bot(entry.routine.botID)
        let top = (CGFloat(entry.place) - CGFloat(firstHour)) * hourHeight
        let length = entry.routine.showAsCall ? CGFloat(entry.routine.blockMinutes) / 60 * hourHeight : 44
        return GeometryReader { geometry in
            let width = (geometry.size.width - 52) / CGFloat(lanes)
            Button {
                Haptics.tap()
                picked = entry.routine
            } label: {
                HStack(spacing: 6) {
                    BotFace(bot: bot, size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.routine.name).font(KFont.ui(13.5, .semibold, relativeTo: .footnote)).foregroundStyle(Palette.night).lineLimit(1)
                        Text("\(clockText(entry.hour, entry.minute)) · \(entry.routine.on ? (entry.routine.showAsCall ? "Call" : "Scheduled") : "Paused")")
                            .font(KFont.ui(11.5, relativeTo: .caption2)).foregroundStyle(Palette.night.opacity(0.7)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(width: max(40, width - 4), height: max(44, length), alignment: .topLeading)
                .padding(.top, 0)
                .background(Color(hex: bot.isKip ? Palette.botGold : bot.colorHex).opacity(entry.routine.on ? 0.92 : 0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.night.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(PressStyle(scale: 0.96))
            .offset(x: 52 + CGFloat(lane) * width, y: top)
            .accessibilityLabel("\(entry.routine.name), \(bot.name), \(clockText(entry.hour, entry.minute))")
        }
        .frame(height: CGFloat(lastHour - firstHour + 1) * hourHeight)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var nowLine: some View {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let y = (CGFloat(hour - firstHour) + CGFloat(minute) / 60) * hourHeight
        return HStack(spacing: 0) {
            Circle().fill(Palette.gold).frame(width: 9, height: 9)
            Palette.gold.frame(height: 2)
        }
        .padding(.leading, 44)
        .offset(y: max(0, y) - 4)
        .opacity(hour >= firstHour && hour <= lastHour ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var resetMarker: some View {
        let y = CGFloat(14 - firstHour) * hourHeight
        return HStack(spacing: 6) {
            Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .bold))
            Text("Claude resets 2:00 PM").font(KFont.ui(11.5, .medium, relativeTo: .caption2))
        }
        .foregroundStyle(Palette.working)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Palette.working.opacity(0.14), in: Capsule())
        .offset(x: 52, y: y - 10)
        .allowsHitTesting(false)
    }

    /// Paired: when the first usage limit that resets on this day does, from the desktop.
    @ViewBuilder
    private var liveResetMarker: some View {
        let calendar = Calendar.current
        if let limit = live.shownLimits.first(where: { limit in
               guard let date = limit.resetsAt?.date else { return false }
               return calendar.isDate(date, inSameDayAs: day)
           }),
           let at = limit.resetsAt?.date {
            let hour = calendar.component(.hour, from: at)
            let minute = calendar.component(.minute, from: at)
            let place = min(Double(lastHour) + 0.75, max(Double(firstHour), Double(hour) + Double(minute) / 60))
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .bold))
                Text("\(limit.name ?? "Usage limit") resets \(clockText(hour, minute))").font(KFont.ui(11.5, .medium, relativeTo: .caption2))
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.working)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Palette.working.opacity(0.14), in: Capsule())
            .offset(x: 52, y: (CGFloat(place) - CGFloat(firstHour)) * hourHeight - 10)
            .allowsHitTesting(false)
        }
    }

    // MARK: Data

    private func entries(for date: Date) -> [CalendarEntry] {
        if isLive { return liveEntries(for: date) }
        let weekday = RoutineTiming.weekday(of: date)
        let routines = store.routines.filter { botID == nil || $0.botID == botID }
        var out: [CalendarEntry] = []
        for routine in routines where routine.runs(on: weekday) {
            switch routine.mode {
            case .interval:
                let start = routine.onlyBetween ? routine.startHour : firstHour
                let step = max(60, routine.intervalMinutes) / 60
                var hour = start
                var count = 0
                while hour <= lastHour && count < 8 {
                    if !routine.onlyBetween || RoutineTiming.inWindow(hour, routine.startHour, routine.endHour) {
                        out.append(CalendarEntry(id: "\(routine.id)-\(hour)", routine: routine, hour: hour, minute: 0))
                        count += 1
                    }
                    hour += step
                }
            case .custom, .limitReset:
                out.append(CalendarEntry(id: "\(routine.id)", routine: routine, hour: routine.mode == .limitReset ? 14 : routine.hour, minute: 0))
            default:
                if routine.hour >= firstHour && routine.hour <= lastHour {
                    out.append(CalendarEntry(id: "\(routine.id)", routine: routine, hour: routine.hour, minute: routine.minute))
                }
            }
        }
        return out.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    /// Paired: the desktop's own run times for the shown week. A routine shows at most 8 runs a day, as on sample data.
    private func liveEntries(for date: Date) -> [CalendarEntry] {
        let calendar = Calendar.current
        var out: [CalendarEntry] = []
        for routine in live.shownRoutines where botID == nil || routine.botID == botID {
            guard let id = live.desktopID(routine) else { continue }
            let times = (live.occurrences[id] ?? []).filter { calendar.isDate($0, inSameDayAs: date) }
            for time in times.prefix(8) {
                let hour = calendar.component(.hour, from: time)
                let minute = calendar.component(.minute, from: time)
                let place = min(Double(lastHour) + 0.25, max(Double(firstHour), Double(hour) + Double(minute) / 60))
                out.append(CalendarEntry(id: "\(id)-\(time.timeIntervalSince1970)", routine: routine, hour: hour, minute: minute, slot: place))
            }
        }
        return out.sorted { $0.place < $1.place }
    }

    /// Where each block sits. A block is at least 44 points tall, so two routines half an hour apart
    /// would cover each other: blocks that touch share the width side by side instead.
    /// `list` is in time order.
    private func placements(_ list: [CalendarEntry]) -> [String: (lane: Int, lanes: Int)] {
        var result: [String: (lane: Int, lanes: Int)] = [:]
        var columns: [CGFloat] = []
        var members: [(id: String, lane: Int)] = []
        var groupEnd = -CGFloat.infinity
        for entry in list {
            let top = (CGFloat(entry.place) - CGFloat(firstHour)) * hourHeight
            let length = entry.routine.showAsCall ? CGFloat(entry.routine.blockMinutes) / 60 * hourHeight : 44
            let bottom = top + max(44, length)
            if top >= groupEnd {
                for member in members { result[member.id] = (member.lane, columns.count) }
                columns = []
                members = []
            }
            let lane = columns.firstIndex { $0 <= top } ?? columns.count
            if lane == columns.count { columns.append(bottom) } else { columns[lane] = bottom }
            members.append((entry.id, lane))
            groupEnd = max(groupEnd, bottom)
        }
        for member in members { result[member.id] = (member.lane, columns.count) }
        return result
    }

    private func hourLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12) \(hour < 12 ? "AM" : "PM")"
    }

    private func shift(_ days: Int) {
        Haptics.select()
        move(to: Calendar.current.date(byAdding: .day, value: days, to: day) ?? day)
    }

    private func move(to date: Date) {
        withAnimation(Motion.snappy) { day = date }
    }

    // MARK: Sheets

    private var monthSheet: some View {
        FittedSheet(estimate: 520) {
            VStack(spacing: 12) {
                SheetTitle(title: "Jump to a day")
                DatePicker("Day", selection: Binding(get: { day }, set: { value in
                    move(to: value)
                    monthOpen = false
                }), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Palette.gold)
                QuietButton(title: "Close") { monthOpen = false }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var newSheet: some View {
        let hour = newAt ?? 9
        return FittedSheet(estimate: 340) {
            VStack(spacing: 14) {
                SheetTitle(title: "New routine at \(clockText(hour, 0))", detail: day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                FieldCard(title: "Name", text: $newName, placeholder: "Morning summary", limit: 80)
                GoldButton(title: "Schedule") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { Haptics.thud(); return }
                    var routine = Routine(botID: botID ?? "kip", name: name, instructions: "Do this once at this time.", mode: .weekly, days: [RoutineTiming.weekday(of: day)], hour: hour)
                    routine.lastRun = "Has not run yet"
                    withAnimation(Motion.snappy) { store.routines.append(routine) }
                    Haptics.success()
                    store.say("Scheduled \(name)")
                    newAt = nil
                }
                QuietButton(title: "Cancel") { newAt = nil }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

/// The calendar as a page for one bot.
struct AutomationCalendarScreen: View {
    let botID: String?
    @State private var goto: BotsRoute?

    var body: some View {
        BotsPage("Automation calendar", subtitle: botID.map { BotsStore.shared.bot($0).name } ?? "All bots", live: !Connection.shared.usesSampleData) {
            CalendarDayView(botID: botID) { routine in
                goto = .routineEditor(routine.botID, routine.id)
            }
        }
        .navigationDestination(item: $goto) { BotsDestination(route: $0) }
    }
}

/// One automation's details: trouble, next times, instructions, recent runs and actions.
struct AutomationDetailSheet: View {
    let routine: Routine
    var edit: () -> Void = {}
    let store = BotsStore.shared
    let desk = BotsRoutinesLive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var running = false
    /// The last write's result, shown in the sheet (the screen's own message is behind it).
    @State private var note: String?

    private var isLive: Bool { !Connection.shared.usesSampleData }

    var body: some View {
        if isLive { liveBody } else { sampleBody }
    }

    // MARK: Paired

    private var liveBody: some View {
        let current = desk.shownRoutines.first { $0.id == routine.id } ?? routine
        let bot = store.bot(current.botID)
        let id = desk.desktopID(current) ?? ""
        let waits = desk.waits(current)
        let gone = desk.routinesLoad == .loaded && !desk.shownRoutines.contains { $0.id == routine.id }
        let times = (desk.nextTimes[id] ?? []).map { RoutineTiming.label($0, now: Date()) }
        let runs = (desk.details[id]?.recentRuns ?? []).compactMap(\.value)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    BotFace(bot: bot, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.name).font(KFont.ui(20, .semibold)).foregroundStyle(Palette.ink)
                        Text("\(bot.name) · \(desk.sentence(current))").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                    }
                }
                .padding(.top, 30)
                if let note {
                    HintLine(text: note, symbol: "info.circle", color: Palette.inkDim)
                }
                if gone {
                    HintLine(text: "This routine is not on your desktop any more.", symbol: "info.circle")
                } else {
                    if let trouble = current.needsYou {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.goldText)
                            Text(trouble).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                            Spacer()
                            if desk.seenRunID(current) != nil {
                                PillButton(title: "Mark seen", look: .filled) { desk.markSeen(current, say: show) }
                                    .disabled(waits)
                            }
                        }
                        .padding(12)
                        .background(Palette.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    BotsSection(title: "Next times") {
                        if desk.detailLoad[id] == .loaded || !times.isEmpty {
                            if times.isEmpty {
                                Text(current.on ? "Nothing is scheduled." : "Paused.").font(KFont.ui(15)).foregroundStyle(Palette.inkDim).padding(14)
                            }
                            ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                                if index > 0 { RowLine() }
                                Text(time).font(KFont.ui(15.5)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading).padding(.horizontal, 14)
                            }
                        } else {
                            Text("Reading your desktop.").font(KFont.ui(15)).foregroundStyle(Palette.inkDim).padding(14)
                        }
                    }
                    BotsSection(title: "Instructions") {
                        Text(current.instructions).font(KFont.ui(15)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Recent runs").padding(.horizontal, 4)
                        if desk.detailLoad[id] == .loaded && runs.isEmpty {
                            Text("It has not run yet.").font(KFont.ui(15)).foregroundStyle(Palette.inkDim).padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .kCard(radius: 20)
                        } else if !runs.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(runs.prefix(5).enumerated()), id: \.element.id) { index, run in
                                    if index > 0 { RowLine() }
                                    let word = BotRoutineText.runWord(run.status)
                                    let when = run.finishedAt?.date ?? run.startedAt?.date ?? TasksWire.date(run.scheduledFor)
                                    runRow(when.map(sentenceCase) ?? "A run",
                                           word.word,
                                           color: word.bad ? Palette.danger : (word.quiet ? Palette.inkFaint : Palette.success))
                                }
                            }
                            .kCard(radius: 20)
                        }
                        BotsLoadNote(state: desk.detailLoad[id] ?? .idle, waiting: "Reading its runs from your desktop.") {
                            Task { await desk.loadDetail(current) }
                        }
                    }
                    HStack(spacing: 8) {
                        PillButton(title: "Run now", symbol: "bolt.fill", look: .filled, wide: true) { running = true }
                        PillButton(title: current.on ? "Pause" : "Resume", wide: true) {
                            Haptics.tap()
                            desk.setOn(current, !current.on, say: show)
                        }
                    }
                    .disabled(waits)
                    HStack(spacing: 8) {
                        PillButton(title: "Edit", symbol: "pencil", wide: true) {
                            dismiss()
                            edit()
                        }
                        PillButton(title: "Delete", look: .danger, wide: true) { deleting = true }
                    }
                    .disabled(waits)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .kSheet([.medium, .large])
        // A write on its way keeps the sheet up, so its result always shows.
        .interactiveDismissDisabled(waits)
        .task { await desk.loadDetail(current) }
        .sheet(isPresented: $running) {
            ConfirmSheet(title: "Run \"\(current.name)\" now?", detail: "It starts a run on your desktop now, outside its schedule.", confirm: "Run now", danger: false) {
                desk.runNow(current, say: show)
            }
        }
        .sheet(isPresented: $deleting) {
            ConfirmSheet(title: "Delete this routine?", detail: "\"\(current.name)\" will stop. Your desktop keeps it for 7 days, so it can be restored there.", confirm: "Delete routine") {
                desk.delete(current, onDeleted: { gone in
                    store.say("Deleted \"\(gone.name)\"")
                    dismiss()
                }, say: show)
            }
        }
    }

    private func show(_ text: String) {
        withAnimation(Motion.snappy) { note = text }
        store.say(text)
    }

    /// "today at 9:00 AM" as "Today at 9:00 AM".
    private func sentenceCase(_ date: Date) -> String {
        let text = BotRoutineText.past(date)
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    // MARK: Sample

    private var sampleBody: some View {
        let live = store.routines.first { $0.id == routine.id } ?? routine
        let bot = store.bot(live.botID)
        let times = RoutineTiming.nextTimes(live)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    BotFace(bot: bot, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(live.name).font(KFont.ui(20, .semibold)).foregroundStyle(Palette.ink)
                        Text("\(bot.name) · \(live.sentence)").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                    }
                }
                .padding(.top, 30)
                if let trouble = live.needsYou {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.goldText)
                        Text(trouble).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                        Spacer()
                        PillButton(title: "Fix", look: .filled) {
                            update { $0.needsYou = nil; $0.failedInARow = 0 }
                            store.say("Fixed. It will run next time.")
                        }
                    }
                    .padding(12)
                    .background(Palette.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                BotsSection(title: "Next times") {
                    if times.isEmpty {
                        Text(live.on ? "Nothing is scheduled." : "Paused.").font(KFont.ui(15)).foregroundStyle(Palette.inkDim).padding(14)
                    }
                    ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                        if index > 0 { RowLine() }
                        Text(time).font(KFont.ui(15.5)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading).padding(.horizontal, 14)
                    }
                }
                BotsSection(title: "Instructions") {
                    Text(live.instructions).font(KFont.ui(15)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                BotsSection(title: "Recent runs") {
                    runRow(live.lastRun, live.failedInARow > 0 ? "Failed" : "Done")
                    RowLine()
                    runRow("Yesterday", "Done")
                    RowLine()
                    runRow("2 days ago", "Missed")
                }
                HStack(spacing: 8) {
                    PillButton(title: "Run now", symbol: "bolt.fill", look: .filled, wide: true) {
                        update { $0.lastRun = "Running now" }
                        store.say("Started")
                    }
                    PillButton(title: live.on ? "Pause" : "Resume", wide: true) { update { $0.on.toggle() } }
                }
                HStack(spacing: 8) {
                    PillButton(title: "Edit", symbol: "pencil", wide: true) {
                        dismiss()
                        edit()
                    }
                    PillButton(title: "Delete", look: .danger, wide: true) { deleting = true }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .kSheet([.medium, .large])
        .sheet(isPresented: $deleting) {
            ConfirmSheet(title: "Delete this routine?", detail: "\"\(live.name)\" will stop.", confirm: "Delete routine") {
                store.routines.removeAll { $0.id == routine.id }
                store.say("Deleted \"\(live.name)\"")
                dismiss()
            }
        }
    }

    private func runRow(_ when: String, _ word: String, color: Color? = nil) -> some View {
        HStack {
            Text(when).font(KFont.ui(15)).foregroundStyle(Palette.ink)
            Spacer()
            StateTag(text: word, color: color ?? (word == "Failed" ? Palette.danger : (word == "Missed" ? Palette.inkFaint : Palette.success)))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    private func update(_ change: (inout Routine) -> Void) {
        guard let index = store.routines.firstIndex(where: { $0.id == routine.id }) else { return }
        Haptics.tap()
        withAnimation(Motion.snappy) { change(&store.routines[index]) }
    }
}

// MARK: - Automations (every bot)

struct AutomationsScreen: View {
    let store = BotsStore.shared
    let desk = BotsRoutinesLive.shared
    @State private var view = "List"
    @State private var filter = "All bots"
    @State private var ask = ""
    @State private var askBot = "Kip"
    @State private var picked: Routine?
    @State private var goto: BotsRoute?
    @State private var movedLate: Set<UUID> = []

    /// Paired: every routine and trigger here is the desktop's, never a sample.
    private var isLive: Bool { !Connection.shared.usesSampleData }
    private var allRoutines: [Routine] { isLive ? desk.shownRoutines : store.routines }
    private var allTriggers: [BotTrigger] { isLive ? desk.shownTriggers : store.triggers }

    var body: some View {
        let routines = allRoutines.filter { filter == "All bots" || store.bot($0.botID).name == filter }
        let needs = routines.filter { $0.needsYou != nil }
        BotsPage("Automations", subtitle: "\(allRoutines.count + allTriggers.count) automations, \(allRoutines.filter { $0.needsYou != nil }.count) need you", live: isLive, trailing: {
            newMenu
        }) {
            if isLive {
                HintLine(text: "To ask a bot for a new automation, write to it in its chat.", symbol: "info.circle")
                    .padding(.horizontal, 4)
            } else {
                composer
            }
            limitWarning
            ChipPicker(items: ["All bots"] + botNames, isOn: { $0 == filter }, title: { $0 }) { filter = $0 }
            GoldSegmented(items: ["List", "Calendar"], selection: $view) { $0 }
            if view == "Calendar" {
                CalendarDayView(botID: nil) { routine in goto = .routineEditor(routine.botID, routine.id) }
            } else if isLive && !desk.routinesReady {
                BotsLoadNote(state: desk.routinesLoad, waiting: "Reading automations from your desktop.") {
                    Task { await desk.loadAll() }
                }
            } else {
                if isLive {
                    BotsLoadNote(state: desk.routinesLoad, waiting: "Reading automations from your desktop.") {
                        Task { await desk.refreshRoutines(force: false) }
                    }
                }
                if !needs.isEmpty { group("Needs you", needs) }
                group("On", routines.filter { $0.on && $0.needsYou == nil })
                group("Paused", routines.filter { !$0.on && $0.needsYou == nil })
                if isLive && desk.skippedRoutines > 0 {
                    HintLine(text: desk.skippedRoutines == 1 ? "1 routine could not be read by this app." : "\(desk.skippedRoutines) routines could not be read by this app.", symbol: "info.circle")
                        .padding(.horizontal, 4)
                }
                triggersGroup
            }
        }
        .navigationDestination(item: $goto) { BotsDestination(route: $0) }
        .sheet(item: $picked) { routine in
            AutomationDetailSheet(routine: routine) { goto = .routineEditor(routine.botID, routine.id) }
        }
        .task(id: BotsRoutinesLive.connectionKey) {
            desk.followConnection()
            guard isLive else { return }
            await desk.loadIfNeeded()
            await desk.loadLimits()
        }
    }

    private var botNames: [String] {
        let ids = Set(allRoutines.map(\.botID) + allTriggers.map(\.botID))
        return store.bots.filter { ids.contains($0.id) }.map(\.name)
    }

    /// Paired, new routines go to Kip (or the first bot); triggers are made on the desktop.
    private var liveNewBot: String? { (store.bots.first { $0.isKip } ?? store.bots.first)?.id }

    @ViewBuilder
    private var newMenu: some View {
        if isLive {
            if let bot = liveNewBot {
                Button {
                    goto = .routineEditor(bot, nil)
                } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("New routine")
            }
        } else {
            Menu {
                Button { goto = .routineEditor("kip", nil) } label: { Label("On a schedule", systemImage: "clock") }
                Button { goto = .triggerEditor("kip", nil, webhook: false) } label: { Label("When something happens in an app", systemImage: "app.badge") }
                Button { goto = .triggerEditor("kip", nil, webhook: true) } label: { Label("When another app calls", systemImage: "arrow.down.left.circle") }
            } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .kGlass(Circle(), interactive: true)
            .accessibilityLabel("New automation")
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Say what should happen").font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink)
            TextField("Every weekday at 9, summarise my inbox", text: $ask, axis: .vertical)
                .font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1...3)
                .padding(12)
                .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 8) {
                Menu {
                    ForEach(store.bots) { bot in Button(bot.name) { askBot = bot.name } }
                } label: {
                    HStack(spacing: 6) {
                        Text(askBot).font(KFont.ui(15, .medium))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Palette.ink.opacity(0.08), in: Capsule())
                }
                .accessibilityLabel("Which bot, \(askBot)")
                Spacer()
                PillButton(title: "Send", symbol: "arrow.up", look: .filled) {
                    guard !ask.trimmingCharacters(in: .whitespaces).isEmpty else { store.say("Say what should happen first."); return }
                    Haptics.success()
                    store.say("Sent to \(askBot). It will set it up in chat.")
                    ask = ""
                }
            }
        }
        .padding(14)
        .kCard(radius: 20, raised: true)
    }

    @ViewBuilder
    private var limitWarning: some View {
        if isLive {
            liveLimitWarning
        } else if let window = store.planWindows.first(where: { $0.percent >= 60 }) {
            let due = store.routines.filter { $0.on && $0.hour < 14 && $0.mode != .limitReset }.prefix(3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(Palette.goldText)
                    Text("\(window.provider): \(window.percent)% used, resets 2:00 PM").font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                }
                Text("These are due first.").font(KFont.ui(13.5)).foregroundStyle(Palette.inkDim)
                ForEach(Array(due)) { routine in
                    HStack {
                        Text(routine.name).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                        Spacer()
                        if movedLate.contains(routine.id) {
                            Text("Moved").font(KFont.ui(13.5, .medium)).foregroundStyle(Palette.success)
                        } else {
                            PillButton(title: "Move to after reset") {
                                movedLate.insert(routine.id)
                                store.say("Moved to after the reset")
                            }
                        }
                    }
                }
            }
            .padding(14)
            .kCard(radius: 20)
        }
    }

    /// Paired: a usage limit near its end on the desktop, and the routines due before it resets.
    @ViewBuilder
    private var liveLimitWarning: some View {
        if let limit = desk.shownLimits.first(where: { ($0.nearLimit == true || $0.blocked == true) && $0.resetsAt?.date != nil }),
           let resets = limit.resetsAt?.date {
            let used = Int((limit.windows ?? []).compactMap { $0.value?.usedPercent }.max() ?? 0)
            let calendar = Calendar.current
            let clock = clockText(calendar.component(.hour, from: resets), calendar.component(.minute, from: resets))
            let when = calendar.isDateInToday(resets) ? clock
                : (calendar.isDateInTomorrow(resets) ? "tomorrow \(clock)" : RoutineTiming.label(resets, now: Date()))
            let due = desk.shownRoutines.filter { routine in
                guard routine.on, let next = TasksWire.date(desk.record(routine)?.nextRunAt) else { return false }
                return next < resets
            }
            .sorted { (TasksWire.date(desk.record($0)?.nextRunAt) ?? .distantFuture) < (TasksWire.date(desk.record($1)?.nextRunAt) ?? .distantFuture) }
            .prefix(3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(Palette.goldText)
                    Text("\(limit.name ?? "Usage limit"): \(used)% used, resets \(when)")
                        .font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                }
                if due.isEmpty {
                    Text("Nothing is due before it resets.").font(KFont.ui(13.5)).foregroundStyle(Palette.inkDim)
                } else {
                    Text("These are due first.").font(KFont.ui(13.5)).foregroundStyle(Palette.inkDim)
                }
                ForEach(Array(due)) { routine in
                    HStack {
                        Text(routine.name).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                        Spacer()
                        if let next = desk.nextLabel(routine) {
                            Text(next).font(KFont.ui(13.5)).foregroundStyle(Palette.inkDim)
                        }
                    }
                }
                if !due.isEmpty {
                    // The desktop moves a routine to its own account's reset, which may not be this one, and the
                    // phone cannot tell which account a routine uses: the move is made on the desktop.
                    HintLine(text: "To move a run until after a reset, use Kairos on your desktop. It moves each routine to the reset of the account it runs on.", symbol: "desktopcomputer")
                }
            }
            .padding(14)
            .kCard(radius: 20)
        }
    }

    private func group(_ title: String, _ items: [Routine]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "\(title) \(items.count)").padding(.horizontal, 4)
            if items.isEmpty {
                EmptyNote(text: "Nothing here.", symbol: "tray").kCard(radius: 20)
            }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, routine in
                    if index > 0 { RowLine(inset: 66) }
                    automationRow(routine)
                }
            }
            .kCard(radius: 20)
            .opacity(items.isEmpty ? 0 : 1)
            .frame(height: items.isEmpty ? 0 : nil)
        }
    }

    private func automationRow(_ routine: Routine) -> some View {
        let bot = store.bot(routine.botID)
        let sentence = isLive ? desk.sentence(routine) : routine.sentence
        let next = isLive ? desk.nextLabel(routine) : RoutineTiming.nextTimes(routine, count: 1).first
        return HStack(spacing: 12) {
            Button {
                Haptics.tap()
                picked = routine
            } label: {
                HStack(spacing: 12) {
                    BotFace(bot: bot, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.name).font(KFont.ui(16, .medium)).foregroundStyle(routine.on ? Palette.ink : Palette.inkFaint)
                        Text("\(bot.name) · \(sentence)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim).lineLimit(1)
                        if let needs = routine.needsYou {
                            Text(needs).font(KFont.ui(12.5, .medium, relativeTo: .caption)).foregroundStyle(Palette.goldText).lineLimit(1)
                        } else {
                            Text(routine.on ? (next.map { "Next \($0)" } ?? routine.lastRun) : "Paused")
                                .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            Toggle("", isOn: Binding(get: { routine.on }, set: { value in
                if isLive {
                    Haptics.select()
                    desk.setOn(routine, value, say: store.say)
                    return
                }
                guard let index = store.routines.firstIndex(where: { $0.id == routine.id }) else { return }
                Haptics.select()
                withAnimation(Motion.snappy) { store.routines[index].on = value }
            }))
            .labelsHidden()
            .tint(Palette.gold)
            .accessibilityLabel("\(routine.name) on")
            .disabled(isLive && desk.waits(routine))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var triggersGroup: some View {
        let triggers = allTriggers.filter { filter == "All bots" || store.bot($0.botID).name == filter }
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Triggers \(triggers.count)").padding(.horizontal, 4)
            if isLive {
                BotsLoadNote(state: desk.shown(desk.triggersLoad), waiting: "Reading triggers from your desktop.") {
                    Task { await desk.loadTriggers() }
                }
            }
            if !isLive || desk.triggersReady {
                VStack(spacing: 0) {
                    ForEach(Array(triggers.enumerated()), id: \.element.id) { index, trigger in
                        if index > 0 { RowLine(inset: 54) }
                        TriggerRow(trigger: trigger)
                    }
                    if triggers.isEmpty { EmptyNote(text: "No triggers for this bot.", symbol: "bolt") }
                }
                .kCard(radius: 20)
            }
            if isLive && desk.skippedTriggers > 0 {
                HintLine(text: desk.skippedTriggers == 1 ? "1 trigger could not be read by this app." : "\(desk.skippedTriggers) triggers could not be read by this app.", symbol: "info.circle")
                    .padding(.horizontal, 4)
            }
        }
    }
}
