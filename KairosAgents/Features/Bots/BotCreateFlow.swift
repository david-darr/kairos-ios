import SwiftUI

/// Making a bot: simple (name, job, look) or advanced (every section), then a ready state.
struct BotCreateSheet: View {
    var start = NewBotDraft()
    var advanced = false
    var onOpen: (String) -> Void = { _ in }

    enum Part: String, CaseIterable { case identity = "Identity", soul = "Soul", model = "Model", routines = "Routines", access = "Access", delivery = "Delivery" }

    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NewBotDraft()
    @State private var isAdvanced = false
    @State private var part: Part = .identity
    @State private var loaded = false
    @State private var created: Bot?
    @State private var discarding = false
    @State private var confirmFull = false

    var body: some View {
        NavigationStack {
            Group {
                if let created { ready(created) } else { form }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .kSheet()
        .interactiveDismissDisabled(created == nil && !draft.name.isEmpty)
        .botsToast()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = start
            isAdvanced = advanced
        }
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button("Cancel") { close() }
                        .font(KFont.ui(16)).foregroundStyle(Palette.inkDim).frame(minHeight: 44)
                    Spacer()
                    Text(isAdvanced ? "New bot" : "Make a bot").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Button(isAdvanced ? "Simple" : "More options") {
                        withAnimation(Motion.snappy) { isAdvanced.toggle() }
                    }
                    .font(KFont.ui(16, .medium)).foregroundStyle(Palette.goldText).frame(minHeight: 44)
                }
                .padding(.top, 24)

                if isAdvanced {
                    GlassSwitch(items: Part.allCases, selection: $part) { $0.rawValue }
                    advancedPart
                } else {
                    simple
                }

                GoldButton(title: "Create bot") { create() }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    HintLine(text: "Give the bot a name to create it.").frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { Ground(glowAt: UnitPoint(x: 0.5, y: 0)) }
        .sheet(isPresented: $discarding) {
            ConfirmSheet(title: "Discard this draft?", detail: "Nothing has been created yet.", confirm: "Discard draft") { dismiss() }
        }
        .sheet(isPresented: $confirmFull) {
            FittedSheet(estimate: 420) {
                VStack(spacing: 16) {
                    SheetTitle(title: "Full access", detail: "It acts without asking. You can stop it at any time from its page.")
                    SwipeToConfirm(title: "Swipe up to give full access") {
                        draft.fullAccess = true
                        Task { try? await Task.sleep(for: .seconds(0.5)); confirmFull = false }
                    }
                    QuietButton(title: "Keep asking first") { confirmFull = false }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
        }
    }

    private var simple: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldCard(title: "Name", text: $draft.name, placeholder: "e.g. Juniper", limit: 100)
            FieldCard(title: "Job", text: $draft.job, placeholder: "What is this bot for?", limit: 200)
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Look")
                Text("Every bot is a Kip. Pick its colour.").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                HStack(spacing: 14) {
                    Mascot(shape: draft.shape, colorHex: draft.colorHex, accessory: draft.accessory, size: 88, live: true)
                        .id("\(draft.shape.rawValue)\(draft.accessory.rawValue)\(draft.colorHex)")
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 3), spacing: 6) {
                            ForEach(BotLook.colors, id: \.hex) { colour in
                                Button {
                                    Haptics.select()
                                    withAnimation(Motion.bouncy) { draft.colorHex = colour.hex }
                                } label: {
                                    Circle().fill(Color(hex: colour.hex)).frame(width: 34, height: 34)
                                        .overlay(Circle().strokeBorder(draft.colorHex == colour.hex ? Palette.gold : Palette.line, lineWidth: draft.colorHex == colour.hex ? 2.5 : 1).padding(-3))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(PressStyle(scale: 0.88))
                                .accessibilityLabel(colour.name)
                            }
                        }
                        PillButton(title: "Shuffle", symbol: "shuffle") {
                            let next = BotLook.shuffled()
                            withAnimation(Motion.bouncy) { draft.colorHex = next.0; draft.shape = next.1; draft.accessory = next.2 }
                        }
                    }
                }
            }
            .padding(14)
            .kCard(radius: 22)
            HintLine(text: "It starts with your saved defaults. You can change anything later.", symbol: "info.circle")
        }
    }

    @ViewBuilder
    private var advancedPart: some View {
        switch part {
        case .identity:
            FieldCard(title: "Name", text: $draft.name, placeholder: "e.g. Juniper", limit: 100)
            FieldCard(title: "Job", text: $draft.job, placeholder: "What is this bot for?", limit: 200)
            FieldCard(title: "Introduction", text: $draft.introduction, placeholder: "A short line about who it is.", limit: 4_000, lines: 2...5)
            FieldCard(title: "Group (optional)", text: $draft.group, placeholder: "Bots in the same group sit together.", limit: 60)
            MascotPicker(colorHex: $draft.colorHex, shape: $draft.shape, accessory: $draft.accessory, previewSize: 120)
                .padding(14).kCard(radius: 22)
        case .soul:
            FieldCard(title: "Standing instructions", text: $draft.instructions, placeholder: "How it should always work", lines: 4...10)
            Text("\(draft.instructions.utf8.count) / 24,000 bytes").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
            notes
        case .model:
            HintLine(text: "Left alone, the bot uses your first Claude connection.")
            BotsSection {
                MenuRow(title: "Model", symbol: "cpu", options: BotsSample.models.map(\.name), selection: $draft.model)
            }
            SectionLabel(text: "Effort")
            GoldSegmented(items: Effort.allCases, selection: $draft.effort) { $0.title }
        case .routines:
            routinesPart
        case .access:
            BotsSection {
                ToggleRow(title: "Every connected tool server", symbol: "server.rack", isOn: $draft.everyToolServer)
                RowLine(inset: 54)
                ToggleRow(title: "Stay signed in", detail: "Keep the sites it logs into between runs.", symbol: "person.badge.key", isOn: $draft.staySignedIn)
                RowLine(inset: 54)
                ToggleRow(title: "Keep its own notes tidy", detail: "It reviews and cleans up what it remembers.", symbol: "sparkles", isOn: $draft.tidyNotes)
                RowLine(inset: 54)
                ToggleRow(title: "Full access", detail: "It acts without asking.", symbol: "bolt.shield", isOn: Binding(
                    get: { draft.fullAccess },
                    set: { on in if on { confirmFull = true } else { draft.fullAccess = false } }
                ))
            }
        case .delivery:
            BotsSection(footer: "Where its reports and questions reach you.") {
                MenuRow(title: "Tell me on", symbol: "paperplane", options: BotsSample.channels, selection: $draft.tellMeOn)
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Starting notes")
                Text("\(draft.notes.reduce(0) { $0 + $1.text.count }) / 8,000 characters").font(KFont.ui(12)).foregroundStyle(Palette.inkFaint)
            }
            if draft.notes.isEmpty {
                VStack(spacing: 4) {
                    Text("No starting notes").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                    Text("Notes it will remember from its very first chat.").font(KFont.ui(13.5)).foregroundStyle(Palette.inkFaint)
                }
                .frame(maxWidth: .infinity).padding(18).kCard(radius: 18)
            }
            ForEach($draft.notes) { $note in
                VStack(spacing: 0) {
                    HStack {
                        MenuRow(title: "Heading", options: ["About this work", "Preferences", "Corrections", "Notes"], selection: $note.heading)
                        Button {
                            withAnimation(Motion.snappy) { draft.notes.removeAll { $0.id == note.id } }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(Palette.danger).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Remove note")
                        .padding(.trailing, 4)
                    }
                    RowLine()
                    TextField("Something it should already know", text: $note.text, axis: .vertical)
                        .font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1...5).padding(14)
                }
                .kCard(radius: 18)
            }
            PillButton(title: "Add a note", symbol: "plus", wide: true) {
                withAnimation(Motion.snappy) { draft.notes.append(StartingNote()) }
            }
        }
    }

    private var routinesPart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HintLine(text: "Optional. A routine runs on a schedule and tells you what it found.")
            if draft.routines.isEmpty {
                EmptyNote(text: "No routines yet", symbol: "clock").kCard(radius: 18)
            }
            ForEach(Array(draft.routines.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Routine \(index + 1)").font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink)
                        Spacer()
                        PillButton(title: "Remove", look: .danger) { _ = withAnimation(Motion.snappy) { draft.routines.remove(at: index) } }
                    }
                    TextField("Name", text: $draft.routines[index].name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        .padding(12).background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    TextField("What to do", text: $draft.routines[index].instructions, axis: .vertical).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        .lineLimit(1...4)
                        .padding(12).background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    GoldSegmented(items: [RepeatMode.daily, RepeatMode.interval], selection: $draft.routines[index].mode) { $0 == .daily ? "Every day at" : "Every few hours" }
                    if draft.routines[index].mode == .daily {
                        HStack {
                            Text("Time").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                            Spacer()
                            TimeChip(hour: $draft.routines[index].hour, minute: $draft.routines[index].minute)
                        }
                    } else {
                        StepperRow(title: "Every", value: Binding(
                            get: { draft.routines[index].intervalMinutes / 60 },
                            set: { draft.routines[index].intervalMinutes = $0 * 60 }
                        ), range: 1...168, unit: "h")
                    }
                    GoldSegmented(items: [false, true], selection: $draft.routines[index].rememberLast) { $0 ? "Every time" : "Only when notable" }
                }
                .padding(14)
                .kCard(radius: 18)
            }
            PillButton(title: "Add a routine", symbol: "plus", wide: true) {
                guard draft.routines.count < 10 else { store.say("A bot can start with 10 routines at most."); return }
                var routine = Routine(botID: "", name: "", instructions: "", mode: .daily, hour: 8)
                routine.intervalMinutes = 360
                withAnimation(Motion.snappy) { draft.routines.append(routine) }
            }
        }
    }

    // MARK: Ready

    private func ready(_ bot: Bot) -> some View {
        let choices = ["Research a topic", "Watch for useful updates", "Organize mail and calendar", "Plan everyday errands", "Work with data and reports"]
        return ScrollView {
            VStack(spacing: 16) {
                BotFace(bot: bot, size: 140, blinks: true).padding(.top, 40)
                Text("\(bot.name) is ready").font(KFont.display(36)).foregroundStyle(Palette.ink)
                Text("What should this bot help with first?").font(KFont.ui(16)).foregroundStyle(Palette.inkDim)
                VStack(spacing: 8) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                        Button {
                            Haptics.success()
                            store.say("Sent /setup to \(bot.name)")
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(Character(UnicodeScalar(UInt8(65 + index)))))
                                    .font(KFont.ui(15, .semibold)).foregroundStyle(Palette.goldText)
                                    .frame(width: 32, height: 32).background(Palette.gold.opacity(0.15), in: Circle())
                                Text(choice).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                Spacer()
                            }
                            .padding(.horizontal, 12).frame(minHeight: 54)
                            .kCard(radius: 16)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                        .arrives(index)
                    }
                }
                GoldButton(title: "Open \(bot.name)") {
                    dismiss()
                    onOpen(bot.id)
                }
                QuietButton(title: "Done") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background { Ground(glowAt: UnitPoint(x: 0.5, y: 0.1)) }
    }

    private func close() {
        if draft.name.isEmpty && draft.job.isEmpty { dismiss() } else { discarding = true }
    }

    private func create() {
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { Haptics.thud(); return }
        if store.bots.contains(where: { $0.name.lowercased() == draft.name.lowercased() }) {
            store.say("A bot named \(draft.name) already exists.")
            return
        }
        let routines = draft.routines.filter { !$0.name.isEmpty && !$0.instructions.isEmpty }
        if routines.count < draft.routines.count {
            store.say("Routine \(routines.count + 1) needs a name and what to do.")
            return
        }
        Haptics.success()
        withAnimation(Motion.bouncy) { created = store.create(draft) }
    }
}
