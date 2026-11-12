import SwiftUI
import UIKit

// Routines and triggers for one bot, their editors, and the next-run wording.

enum RoutineTiming {
    static func weekday(of date: Date) -> Weekday {
        Weekday(rawValue: (Calendar.current.component(.weekday, from: date) + 5) % 7) ?? .mon
    }

    /// The next few times a routine runs, in plain words.
    static func nextTimes(_ routine: Routine, count: Int = 3, from now: Date = Date()) -> [String] {
        guard routine.on else { return [] }
        let calendar = Calendar.current
        var out: [String] = []
        switch routine.mode {
        case .limitReset:
            return [routine.afterEveryReset ? "After each \(routine.limitName) reset" : "After the next \(routine.limitName) reset"]
        case .custom:
            return ["On the custom schedule"]
        case .interval:
            var time = now
            let step = max(5, routine.intervalMinutes)
            for _ in 0..<200 where out.count < count {
                time = time.addingTimeInterval(Double(step) * 60)
                let hour = calendar.component(.hour, from: time)
                let inside = !routine.onlyBetween || inWindow(hour, routine.startHour, routine.endHour)
                if inside && routine.runs(on: weekday(of: time)) {
                    out.append(label(time, now: now))
                }
            }
            return out
        default:
            for offset in 0..<21 where out.count < count {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                      let time = calendar.date(bySettingHour: routine.hour, minute: routine.minute, second: 0, of: day) else { continue }
                if time > now && routine.runs(on: weekday(of: time)) {
                    out.append(label(time, now: now))
                    if routine.mode == .once { break }
                }
            }
            return out
        }
    }

    static func inWindow(_ hour: Int, _ start: Int, _ end: Int) -> Bool {
        start <= end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    static func label(_ time: Date, now: Date) -> String {
        let calendar = Calendar.current
        let clock = clockText(calendar.component(.hour, from: time), calendar.component(.minute, from: time))
        if calendar.isDate(time, inSameDayAs: now) { return "Today \(clock)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(time, inSameDayAs: tomorrow) { return "Tomorrow \(clock)" }
        return "\(weekday(of: time).short) \(clock)"
    }
}

// MARK: - Routines list

struct RoutinesScreen: View {
    let botID: String
    let store = BotsStore.shared
    @State private var deleting: Routine?
    @State private var removed: Routine?
    @State private var watching = true
    @State private var morningBrief = true
    @State private var briefHour = 8
    @State private var briefMinute = 0
    @State private var goto: BotsRoute?

    var body: some View {
        let routines = store.routines(for: botID).sorted { ($0.on ? 0 : 1, $0.hour) < ($1.on ? 0 : 1, $1.hour) }
        let triggers = store.triggers.filter { $0.botID == botID }
        BotsPage("Routines and triggers", subtitle: store.bot(botID).name, trailing: {
            Menu {
                Button { goto = .routineEditor(botID, nil) } label: { Label("On a schedule", systemImage: "clock") }
                Button { goto = .triggerEditor(botID, nil, webhook: false) } label: { Label("When something happens in an app", systemImage: "app.badge") }
                Button { goto = .triggerEditor(botID, nil, webhook: true) } label: { Label("When another app calls", systemImage: "arrow.down.left.circle") }
            } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .kGlass(Circle(), interactive: true)
            .accessibilityLabel("New routine or trigger")
        }) {
            if store.bot(botID).isKip { watchCard }

            if let removed {
                HStack {
                    Text("Deleted \"\(removed.name)\".").font(KFont.ui(15)).foregroundStyle(Palette.ink)
                    Spacer()
                    PillButton(title: "Bring it back", look: .filled) {
                        withAnimation(Motion.snappy) {
                            store.routines.append(removed)
                            self.removed = nil
                        }
                    }
                }
                .padding(12)
                .kCard(radius: 18, raised: true)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Routines").padding(.horizontal, 4)
                if routines.isEmpty {
                    EmptyNote(text: "No routines yet. Add one and this bot works on its own, on a schedule.", symbol: "clock").kCard(radius: 20)
                }
                ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                    RoutineRow(routine: routine, showFace: false) { deleting = routine }
                        .arrives(index)
                }
                PillButton(title: "Add a routine", symbol: "plus", wide: true) { goto = .routineEditor(botID, nil) }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Triggers").padding(.horizontal, 4)
                VStack(spacing: 0) {
                    if triggers.isEmpty {
                        EmptyNote(text: "No triggers. A trigger starts the bot when an app sends something.", symbol: "bolt")
                    }
                    ForEach(Array(triggers.enumerated()), id: \.element.id) { index, trigger in
                        if index > 0 { RowLine(inset: 54) }
                        TriggerRow(trigger: trigger)
                    }
                }
                .kCard(radius: 20)
            }

            VStack(spacing: 0) {
                NavigationLink(value: BotsRoute.calendar(botID)) {
                    NavRow(title: "Automation calendar", symbol: "calendar.day.timeline.left", detail: "See every run by day")
                }
                RowLine(inset: 54)
                NavigationLink(value: BotsRoute.automations) {
                    NavRow(title: "See all automations", symbol: "square.stack.3d.up", detail: "Every bot's routines and triggers")
                }
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .kCard(radius: 20)
        }
        .navigationDestination(item: $goto) { BotsDestination(route: $0) }
        .sheet(item: $deleting) { routine in
            ConfirmSheet(title: "Delete this routine?", detail: "\"\(routine.name)\" will stop. You can bring it back for a little while.", confirm: "Delete routine") {
                withAnimation(Motion.snappy) {
                    store.routines.removeAll { $0.id == routine.id }
                    removed = routine
                }
                Task {
                    try? await Task.sleep(for: .seconds(8))
                    withAnimation(Motion.gentle) { if removed?.id == routine.id { removed = nil } }
                }
            }
        }
    }

    private var watchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StateTag(text: watching ? "Watching your day" : "Paused", color: watching ? Palette.success : Palette.inkFaint, pulsing: watching)
                Spacer()
                PillButton(title: watching ? "Pause" : "Resume") {
                    Haptics.tap()
                    withAnimation(Motion.snappy) { watching.toggle() }
                }
            }
            Text("Keep an eye on my day").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
            Text("Kip watches Calendar and Mail and tells you what matters.").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
            Toggle(isOn: $morningBrief) {
                Text("Morning brief").font(KFont.ui(16)).foregroundStyle(Palette.ink)
            }
            .tint(Palette.gold)
            .frame(minHeight: 44)
            if morningBrief {
                HStack {
                    Text("Morning time").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    Spacer()
                    TimeChip(hour: $briefHour, minute: $briefMinute, label: "Morning time")
                }
            }
        }
        .padding(14)
        .kCard(radius: 20, raised: true)
    }
}

/// One routine: switch, name, schedule, last run and anything that needs you.
struct RoutineRow: View {
    let routine: Routine
    var showFace = false
    var onDelete: () -> Void = {}
    let store = BotsStore.shared

    var body: some View {
        let next = RoutineTiming.nextTimes(routine, count: 1).first
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if showFace { BotFace(bot: store.bot(routine.botID), size: 40) }
                NavigationLink(value: BotsRoute.routineEditor(routine.botID, routine.id)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(routine.name).font(KFont.ui(16.5, .medium)).foregroundStyle(routine.on ? Palette.ink : Palette.inkFaint)
                        Text(routine.on ? "\(routine.sentence)\(next.map { " · next \($0)" } ?? "")" : "\(routine.sentence) · paused")
                            .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        Text(routine.failedInARow > 0 ? "\(routine.lastRun) · failed \(routine.failedInARow) in a row" : routine.lastRun)
                            .font(KFont.ui(12.5, relativeTo: .caption))
                            .foregroundStyle(routine.failedInARow > 0 ? Palette.danger : Palette.inkFaint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.98))
                Toggle("", isOn: Binding(get: { routine.on }, set: { value in
                    Haptics.select()
                    update { $0.on = value }
                }))
                .labelsHidden()
                .tint(Palette.gold)
                .accessibilityLabel("\(routine.name) on")
                menu
            }
            if let needs = routine.needsYou {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.goldText)
                    Text(needs).font(KFont.ui(14)).foregroundStyle(Palette.ink)
                    Spacer()
                    PillButton(title: "Fix", look: .filled) {
                        update { $0.needsYou = nil; $0.failedInARow = 0; $0.lastRun = "Ready to run again" }
                        store.say("Signed in again. It will run next time.")
                    }
                }
                .padding(10)
                .background(Palette.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(14)
        .kCard(radius: 20)
        .contextMenu { menuItems }
    }

    private var menu: some View {
        Menu { menuItems } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkDim)
                .frame(width: 36, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Options for \(routine.name)")
    }

    @ViewBuilder
    private var menuItems: some View {
        Button {
            update { $0.lastRun = "Running now" }
            store.say("Started")
        } label: { Label("Run now", systemImage: "play") }
        Button {
            update { $0.on.toggle() }
        } label: { Label(routine.on ? "Pause" : "Resume", systemImage: routine.on ? "pause" : "play.circle") }
        Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
    }

    private func update(_ change: (inout Routine) -> Void) {
        guard let index = store.routines.firstIndex(where: { $0.id == routine.id }) else { return }
        withAnimation(Motion.snappy) { change(&store.routines[index]) }
    }
}

struct TriggerRow: View {
    let trigger: BotTrigger
    let store = BotsStore.shared

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: BotsRoute.triggerEditor(trigger.botID, trigger.id, webhook: trigger.kind == .webhook)) {
                HStack(spacing: 12) {
                    Image(systemName: trigger.kind == .webhook ? "arrow.down.left.circle" : "app.badge")
                        .font(.system(size: 17)).foregroundStyle(Palette.goldText).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trigger.name).font(KFont.ui(16, .medium)).foregroundStyle(trigger.on ? Palette.ink : Palette.inkFaint)
                        Text("\(trigger.app): \(trigger.event) · \(trigger.on ? trigger.lastEvent : "Paused")")
                            .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            Toggle("", isOn: Binding(get: { trigger.on }, set: { value in
                guard let index = store.triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
                Haptics.select()
                withAnimation(Motion.snappy) { store.triggers[index].on = value }
            }))
            .labelsHidden()
            .tint(Palette.gold)
            .accessibilityLabel("\(trigger.name) on")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
    }
}

// MARK: - Routine editor

struct RoutineEditorScreen: View {
    let botID: String
    let routineID: UUID?
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Routine(botID: "kip", name: "", instructions: "")
    @State private var loaded = false
    @State private var moreOptions = false
    @State private var tried = false
    @State private var onceDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var stopAfter = false
    @State private var stopDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    var body: some View {
        BotsPage(routineID == nil ? "New routine" : "Edit routine", subtitle: store.bot(draft.botID).name) {
            preview
            FieldCard(title: "Name", text: $draft.name, placeholder: "Morning summary", limit: 80)
            if tried && draft.name.trimmingCharacters(in: .whitespaces).isEmpty { problem("Give it a name.") }
            BotsSection {
                MenuRow(title: "Bot", symbol: "person.crop.circle", options: store.bots.map(\.name), selection: Binding(
                    get: { store.bot(draft.botID).name },
                    set: { name in draft.botID = store.bots.first { $0.name == name }?.id ?? draft.botID }
                ))
            }
            repeatSection
            whenSection
            FieldCard(title: "Instructions", text: $draft.instructions, placeholder: "What should the bot do each time?", limit: 20_000, lines: 3...10)
            if tried && draft.instructions.trimmingCharacters(in: .whitespaces).isEmpty { problem("Say what the bot should do.") }
            runSection
            GoldButton(title: routineID == nil ? "Schedule" : "Save") { save() }
                .padding(.top, 4)
        }
        .onAppear(perform: load)
    }

    private var preview: some View {
        let times = RoutineTiming.nextTimes(draft)
        return VStack(alignment: .leading, spacing: 6) {
            Text(draft.sentence).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                .contentTransition(.opacity)
            Text(times.isEmpty ? "Nothing is scheduled." : "Next: " + times.joined(separator: ", "))
                .font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(radius: 20, raised: true)
        .animation(Motion.snappy, value: draft)
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Repeat").padding(.horizontal, 4)
            ChipPicker(items: moreOptions ? RepeatMode.allCases : RepeatMode.basic, isOn: { $0 == draft.mode }, title: { $0.title }) { mode in
                draft.mode = mode
            }
            Button {
                withAnimation(Motion.snappy) { moreOptions.toggle() }
            } label: {
                Label(moreOptions ? "Fewer options" : "More options", systemImage: moreOptions ? "chevron.up" : "chevron.down")
                    .font(KFont.ui(15, .medium)).foregroundStyle(Palette.goldText).frame(minHeight: 44)
            }
            .buttonStyle(PressStyle())
        }
        .onAppear { if RepeatMode.more.contains(draft.mode) { moreOptions = true } }
    }

    @ViewBuilder
    private var whenSection: some View {
        switch draft.mode {
        case .once:
            BotsSection(title: "When") {
                DatePicker("Date", selection: $onceDate, in: Date()..., displayedComponents: .date)
                    .font(KFont.ui(16)).foregroundStyle(Palette.ink).tint(Palette.gold)
                    .padding(.horizontal, 16).frame(minHeight: 56)
                RowLine()
                timeRow("Time")
            }
        case .daily, .weekdays:
            BotsSection(title: "When") { timeRow("Time") }
        case .weekly:
            BotsSection(title: "When") {
                dayCircles.padding(12)
                RowLine()
                timeRow("Time")
            }
            if tried && draft.days.isEmpty { problem("Pick the days.") }
        case .interval:
            BotsSection(title: "How often") {
                StepperRow(title: "Every", value: $draft.intervalMinutes, range: 5...1440, step: 5, unit: "min")
                RowLine()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Only on these days").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    dayCircles
                }
                .padding(12)
                RowLine()
                ToggleRow(title: "Only between certain hours", isOn: $draft.onlyBetween)
                if draft.onlyBetween {
                    HStack(spacing: 10) {
                        TimeChip(hour: $draft.startHour, minute: .constant(0), label: "Start")
                        Text("to").font(KFont.ui(15)).foregroundStyle(Palette.inkFaint)
                        TimeChip(hour: $draft.endHour, minute: .constant(0), label: "End")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                RowLine()
                ToggleRow(title: "Stop after a date", isOn: $stopAfter)
                if stopAfter {
                    DatePicker("Stop after", selection: $stopDate, in: Date()..., displayedComponents: .date)
                        .font(KFont.ui(16)).foregroundStyle(Palette.ink).tint(Palette.gold)
                        .padding(.horizontal, 16).frame(minHeight: 56)
                }
            }
            if tried && draft.days.isEmpty { problem("Pick the days.") }
        case .custom:
            BotsSection(title: "Custom schedule", footer: "Five fields: minute, hour, day of month, month, weekday.") {
                TextField("0 9 * * 1-5", text: $draft.cron)
                    .font(.system(size: 17, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16).frame(minHeight: 52)
                RowLine()
                ChipPicker(items: ["0 * * * *", "0 9 * * 1-5", "0 9 1 * *", "0 9 L * *"], isOn: { $0 == draft.cron }, title: presetName) { draft.cron = $0 }
                    .padding(12)
                RowLine()
                MenuRow(title: "Time zone", options: ["Your time zone", "UTC", "Eastern Time", "Central European Time"], selection: .constant("Your time zone"))
            }
        case .limitReset:
            BotsSection(title: "After a limit reset") {
                MenuRow(title: "Which limit", options: ["Claude", "Codex"], selection: $draft.limitName)
                RowLine()
                GoldSegmented(items: [false, true], selection: $draft.afterEveryReset) { $0 ? "After every reset" : "Once, after the next" }
                    .padding(8)
            }
        }
    }

    private var runSection: some View {
        BotsSection(title: "Each run") {
            StepperRow(title: "Run limit", detail: "Time spent waiting for you does not count.", value: $draft.runLimit, range: 5...240, step: 5, unit: "min")
            RowLine()
            MenuRow(title: "If the last run is still going", options: ["Skip the new run", "Queue one for after"], selection: Binding(
                get: { draft.queueIfRunning ? "Queue one for after" : "Skip the new run" },
                set: { draft.queueIfRunning = $0 == "Queue one for after" }
            ))
            RowLine()
            MenuRow(title: "Post results to", options: ["Its own conversation each time", "Main", "Friday report"], selection: $draft.postTo)
            RowLine()
            ToggleRow(title: "Also run when Kairos starts", isOn: $draft.runOnStart)
            RowLine()
            ToggleRow(title: "Remember the last report", isOn: $draft.rememberLast)
            RowLine()
            ToggleRow(title: "Read and draft only", detail: "It cannot send or change anything.", isOn: $draft.readOnly)
            RowLine()
            ToggleRow(title: "Show as a call on the calendar", isOn: $draft.showAsCall)
            if draft.showAsCall {
                RowLine()
                StepperRow(title: "Block length", value: $draft.blockMinutes, range: 5...240, step: 5, unit: "min")
            }
        }
    }

    private var dayCircles: some View {
        HStack(spacing: 4) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let on = draft.days.contains(day)
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) {
                        if on { draft.days.remove(day) } else { draft.days.insert(day) }
                    }
                } label: {
                    Text(day.letter)
                        .font(KFont.ui(15, on ? .semibold : .regular))
                        .foregroundStyle(on ? Palette.onGold : Palette.ink)
                        .frame(width: 44, height: 44)
                        .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Circle())
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .frame(maxWidth: .infinity)
                .accessibilityLabel(day.short)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func timeRow(_ title: String) -> some View {
        HStack {
            Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
            Spacer()
            TimeChip(hour: $draft.hour, minute: $draft.minute, label: title)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
    }

    private func presetName(_ cron: String) -> String {
        switch cron {
        case "0 * * * *": "Every hour"
        case "0 9 * * 1-5": "Weekdays at 9:00 AM"
        case "0 9 1 * *": "First of the month"
        default: "Last day of the month"
        }
    }

    private func problem(_ text: String) -> some View {
        HintLine(text: text, symbol: "exclamationmark.circle", color: Palette.danger)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let routineID, let existing = store.routines.first(where: { $0.id == routineID }) {
            draft = existing
        } else {
            draft = Routine(botID: botID, name: "", instructions: "", mode: .weekdays)
        }
    }

    private func save() {
        tried = true
        let needsDays = draft.mode == .weekly || draft.mode == .interval
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty,
              !draft.instructions.trimmingCharacters(in: .whitespaces).isEmpty,
              !(needsDays && draft.days.isEmpty) else {
            Haptics.thud()
            return
        }
        if let index = store.routines.firstIndex(where: { $0.id == draft.id }) {
            store.routines[index] = draft
            store.say("Saved")
        } else {
            draft.lastRun = "Has not run yet"
            store.routines.append(draft)
            store.say("Scheduled. \(draft.sentence).")
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Trigger editor

struct TriggerEditorScreen: View {
    let botID: String
    let triggerID: UUID?
    let webhook: Bool
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var instructions = ""
    @State private var bot = "kip"
    @State private var app = "Mail"
    @State private var event = "A new message arrives"
    @State private var summary = ""
    @State private var events: [String] = []
    @State private var newEvent = ""
    @State private var mostAtOnce = 3
    @State private var straightAway = false
    @State private var saved = false
    @State private var secretShown = true
    @State private var replacing = false
    @State private var address = "https://your-desktop.example/hooks/7f3a9c"
    @State private var expanded: Int?
    @State private var loaded = false

    private let apps: [String: [String]] = [
        "Mail": ["A new message arrives", "A message is starred"],
        "Calendar": ["An event is added", "An event starts soon"],
        "Shop orders": ["A new order arrives", "An order is refunded"],
    ]
    private let calls: [(String, String, String)] = [
        ("Started a run", "2 h ago", "{ \"order\": 1042, \"total\": 64.00 }"),
        ("Filtered out", "5 h ago", "{ \"event\": \"ping\" }"),
        ("Turned away", "Yesterday", "Wrong secret"),
    ]

    var body: some View {
        BotsPage(webhook ? (triggerID == nil ? "When another app calls" : "Webhook") : (triggerID == nil ? "When something happens" : "App trigger"), subtitle: store.bot(bot).name) {
            if saved && webhook {
                connectStep
            } else {
                FieldCard(title: webhook ? "Name" : "Name (optional)", text: $name, placeholder: webhook ? "New orders" : "Mail from suppliers", limit: 80)
                BotsSection {
                    MenuRow(title: "Bot", symbol: "person.crop.circle", options: store.bots.map(\.name), selection: Binding(
                        get: { store.bot(bot).name },
                        set: { value in bot = store.bots.first { $0.name == value }?.id ?? bot }
                    ))
                    if !webhook {
                        RowLine(inset: 54)
                        MenuRow(title: "App", symbol: "app", options: apps.keys.sorted(), selection: Binding(
                            get: { app },
                            set: { value in app = value; event = apps[value]?.first ?? event }
                        ))
                        RowLine(inset: 54)
                        MenuRow(title: "When this happens", symbol: "bolt", options: apps[app] ?? [], selection: $event)
                    }
                }
                FieldCard(title: "Instructions", text: $instructions, placeholder: "What should the bot do each time?", limit: 20_000, lines: 3...8)
                if webhook { webhookOptions } else { appOptions }
                GoldButton(title: "Save") { save() }
                if triggerID != nil { recentCalls }
            }
        }
        .sheet(isPresented: $replacing) {
            ConfirmSheet(title: "Replace the address?", detail: "Apps using the old address stop working until you give them the new one.", confirm: "Replace address") {
                address = "https://your-desktop.example/hooks/\(UUID().uuidString.prefix(6).lowercased())"
                secretShown = true
                saved = true
            }
        }
        .onAppear(perform: load)
    }

    private var webhookOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            BotsSection(title: "Only these events (optional)") {
                if !events.isEmpty {
                    ChipPicker(items: events, isOn: { _ in true }, title: { $0 }) { tapped in events.removeAll { $0 == tapped } }
                        .padding(12)
                    RowLine()
                }
                HStack {
                    TextField("order.created", text: $newEvent)
                        .font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    PillButton(title: "Add") {
                        let value = newEvent.trimmingCharacters(in: .whitespaces)
                        guard !value.isEmpty, events.count < 20 else { return }
                        withAnimation(Motion.snappy) { events.append(value) }
                        newEvent = ""
                    }
                }
                .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 56)
            }
            BotsSection {
                StepperRow(title: "Most unfinished runs at once", value: $mostAtOnce, range: 1...50)
                RowLine()
                ToggleRow(title: "Run straight away", detail: "Start without waiting for a check.", isOn: $straightAway)
            }
            if straightAway {
                HintLine(text: "Anyone with the address and secret can start this bot. Keep them private.", symbol: "exclamationmark.triangle", color: Palette.goldText)
            }
            if triggerID != nil {
                HStack(spacing: 10) {
                    PillButton(title: "Send a test", symbol: "paperplane", wide: true) { store.say("Test sent. It started a run.") }
                    PillButton(title: "Replace address", wide: true) { replacing = true }
                }
            }
        }
    }

    private var appOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldCard(title: "Only when the summary equals", text: $summary, placeholder: "Optional", limit: 200)
            HintLine(text: "It checks regularly, every 5 minutes.", symbol: "clock")
            if triggerID != nil {
                HStack(spacing: 10) {
                    PillButton(title: "Send a test", symbol: "paperplane", wide: true) { store.say("Test sent. It started a run.") }
                    PillButton(title: "Check now", symbol: "arrow.clockwise", wide: true) { store.say("Checked, nothing new") }
                }
            }
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect it").font(KFont.ui(20, .semibold)).foregroundStyle(Palette.ink)
                Text("Give these to the app that will call. The secret shows only once.").font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
            }
            BotsSection {
                copyRow("Address", address, shown: true)
                RowLine()
                copyRow("Secret", "whsec_3b91e0c4a7", shown: secretShown)
            }
            GoldButton(title: "Done") {
                secretShown = false
                dismiss()
            }
        }
    }

    private func copyRow(_ title: String, _ value: String, shown: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                Text(shown ? value : "Hidden").font(.system(size: 14, design: .monospaced)).foregroundStyle(Palette.ink).lineLimit(1)
            }
            Spacer()
            PillButton(title: "Copy", symbol: "doc.on.doc") {
                UIPasteboard.general.string = value
                store.say("Copied")
            }
            .disabled(!shown)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var recentCalls: some View {
        BotsSection(title: webhook ? "Recent calls" : "Latest arrivals") {
            ForEach(calls.indices, id: \.self) { index in
                if index > 0 { RowLine() }
                Button {
                    withAnimation(Motion.snappy) { expanded = expanded == index ? nil : index }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            StateTag(text: calls[index].0, color: index == 0 ? Palette.success : Palette.inkDim)
                            Spacer()
                            Text(calls[index].1).font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
                            Image(systemName: expanded == index ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                        }
                        if expanded == index {
                            Text(calls[index].2).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.inkDim)
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.99))
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        bot = botID
        if let triggerID, let trigger = store.triggers.first(where: { $0.id == triggerID }) {
            name = trigger.name
            instructions = trigger.instructions
            bot = trigger.botID
            mostAtOnce = trigger.mostAtOnce
            straightAway = trigger.runStraightAway
            if trigger.kind == .appEvent {
                app = trigger.app
                event = trigger.event
            }
        }
    }

    private func save() {
        if webhook && name.trimmingCharacters(in: .whitespaces).isEmpty { store.say("Give it a name."); Haptics.thud(); return }
        if instructions.trimmingCharacters(in: .whitespaces).isEmpty { store.say("Say what the bot should do."); Haptics.thud(); return }
        let title = name.isEmpty ? "\(app): \(event)" : name
        if let triggerID, let index = store.triggers.firstIndex(where: { $0.id == triggerID }) {
            store.triggers[index].name = title
            store.triggers[index].instructions = instructions
            store.triggers[index].botID = bot
            store.triggers[index].mostAtOnce = mostAtOnce
            store.triggers[index].runStraightAway = straightAway
            if !webhook { store.triggers[index].app = app; store.triggers[index].event = event }
            store.say("Saved")
            dismiss()
            return
        }
        var trigger = BotTrigger(botID: bot, kind: webhook ? .webhook : .appEvent, name: title, app: webhook ? "Webhook" : app, event: webhook ? "Any call" : event, lastEvent: "Nothing has arrived yet", instructions: instructions)
        trigger.mostAtOnce = mostAtOnce
        trigger.runStraightAway = straightAway
        store.triggers.append(trigger)
        Haptics.success()
        if webhook {
            withAnimation(Motion.snappy) { saved = true }
        } else {
            store.say("Saved. It checks every 5 minutes.")
            dismiss()
        }
    }
}
