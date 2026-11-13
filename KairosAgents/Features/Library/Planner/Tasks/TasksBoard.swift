import SwiftUI

/// What a card can ask the page to do.
struct WorkCardActions {
    var open: (WorkCard) -> Void
    var delete: (WorkCard) -> Void
    var say: (String) -> Void
}

// MARK: - The board

/// The work board made for a phone: one column at a time. Chips with counts choose the column;
/// swiping the cards sideways moves to the next or previous column.
struct WorkBoardView: View {
    @Bindable var store: TasksStore
    let actions: WorkCardActions
    let onAdd: () -> Void
    @State private var forward = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Work board")
                    .font(KFont.ui(19, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Spacer()
                PlannerRoundButton(symbol: "plus", label: "Add a card", size: 40, action: onAdd)
            }
            Text("Ready cards run one at a time. Results wait in Review, and a card can wait for others.")
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            columnChips

            VStack(spacing: 10) {
                let cards = store.cards(in: store.column)
                if cards.isEmpty && !store.boardReady {
                    // Paired and not read yet, or the read failed: the line above says which.
                    EmptyView()
                } else if cards.isEmpty {
                    Text(store.column.emptyLine)
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity, minHeight: 90)
                        .kCard(radius: 20)
                } else {
                    ForEach(cards) { card in
                        WorkCardView(store: store, card: card, actions: actions)
                            .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.9).combined(with: .opacity)))
                    }
                }
            }
            .id(store.column)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .opacity))
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let dx = value.translation.width
                        guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 1.4 else { return }
                        step(dx < 0 ? 1 : -1)
                    }
            )
            .accessibilityAction(named: "Next column") { step(1) }
            .accessibilityAction(named: "Previous column") { step(-1) }

            pageDots
        }
        .animation(Motion.snappy, value: store.cards)
    }

    private var columnChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(WorkColumn.allCases, id: \.self) { column in
                        let on = column == store.column
                        Button {
                            choose(column)
                        } label: {
                            HStack(spacing: 6) {
                                Text(column.title)
                                    .font(KFont.ui(14.5, on ? .semibold : .regular, relativeTo: .subheadline))
                                Text("\(store.count(column))")
                                    .font(KFont.ui(13, .medium, relativeTo: .footnote))
                                    .foregroundStyle(on ? Palette.onGold : Palette.inkFaint)
                                    .padding(.horizontal, 7)
                                    .frame(minHeight: 22)
                                    .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Capsule())
                                    .contentTransition(.numericText())
                            }
                            .foregroundStyle(on ? Palette.ink : Palette.inkDim)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(on ? Palette.ink.opacity(0.13) : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? Color.clear : Palette.line, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .id(column)
                        .accessibilityLabel("\(column.title), \(store.count(column)) cards")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.column) { _, column in
                withAnimation(Motion.snappy) { proxy.scrollTo(column, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(store.column, anchor: .center) }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            Spacer()
            ForEach(WorkColumn.allCases, id: \.self) { column in
                Capsule()
                    .fill(column == store.column ? Palette.gold : Palette.ink.opacity(0.18))
                    .frame(width: column == store.column ? 16 : 6, height: 6)
            }
            Spacer()
        }
        .accessibilityHidden(true)
        .padding(.top, 2)
    }

    private func choose(_ column: WorkColumn) {
        guard column != store.column else { return }
        Haptics.select()
        let all = WorkColumn.allCases
        forward = (all.firstIndex(of: column) ?? 0) > (all.firstIndex(of: store.column) ?? 0)
        withAnimation(Motion.snappy) { store.column = column }
    }

    private func step(_ by: Int) {
        let all = WorkColumn.allCases
        guard let index = all.firstIndex(of: store.column) else { return }
        let next = index + by
        guard all.indices.contains(next) else { return }
        choose(all[next])
    }
}

// MARK: - One card

struct WorkCardView: View {
    @Bindable var store: TasksStore
    let card: WorkCard
    let actions: WorkCardActions
    var inSheet = false
    @State private var showResult: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                actions.open(card)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(card.name)
                            .font(KFont.ui(16.5, .medium))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if !inSheet {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.inkFaint)
                                .padding(.top, 5)
                        }
                    }
                    Text(store.meta(card))
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .disabled(inSheet)

            if card.column == .running {
                HStack(spacing: 8) {
                    PulsingDot(color: Palette.working)
                    Text("Working on it (started \(TasksDates.time(card.startedAt ?? Date())))...")
                        .font(KFont.ui(14, relativeTo: .subheadline))
                        .foregroundStyle(Palette.working)
                }
            }

            if card.result != nil || card.error != nil {
                resultBlock
            }

            WorkCardControls(store: store, card: card, actions: actions)
        }
        .padding(14)
        .kCard(radius: 20)
    }

    private var resultOpen: Bool {
        showResult ?? (card.column == .review || card.column == .blocked)
    }

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { showResult = !resultOpen }
            } label: {
                HStack(spacing: 6) {
                    Text(card.error != nil ? "Last error" : "Result")
                        .font(KFont.ui(14, .medium, relativeTo: .subheadline))
                        .foregroundStyle(card.error != nil ? Palette.danger : Palette.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(resultOpen ? 180 : 0))
                    Spacer()
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            if resultOpen {
                Text(card.error ?? card.result ?? "")
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(card.error != nil ? Palette.danger : Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .transition(.opacity)
            }
        }
    }
}

/// The buttons a card has in its column, exactly as on the desktop.
struct WorkCardControls: View {
    @Bindable var store: TasksStore
    let card: WorkCard
    let actions: WorkCardActions
    @State private var note = ""
    @State private var noteError = false
    @State private var confirmRun = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if card.column == .review {
                PlannerTextField(label: "What should change?", placeholder: "Say what to change, then Request changes",
                                 text: $note, multiline: true, error: noteError ? "Say what should change" : nil)
                    .onChange(of: note) { if noteError { noteError = false } }
            }
            HStack(spacing: 8) {
                switch card.column {
                case .backlog:
                    PlannerPill(title: "Ready", symbol: "arrow.right", style: .quiet) {
                        move(.ready, "Moved to Ready")
                    }
                    PlannerPill(title: "Run now", symbol: "play.fill", style: .gold) { run() }
                case .ready:
                    PlannerPill(title: "Hold", symbol: "pause", style: .quiet) {
                        move(.backlog, "Held in the backlog")
                    }
                    if !store.isWaiting(card) {
                        PlannerPill(title: "Run now", symbol: "play.fill", style: .gold) { run() }
                    } else {
                        Text("Waiting for \(store.waitNames(card))")
                            .font(KFont.ui(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .lineLimit(2)
                    }
                case .running:
                    PlannerPill(title: "Stop", symbol: "stop.fill", style: .danger) {
                        if store.isLive {
                            store.stopLive(card.id, say: actions.say)
                            return
                        }
                        withAnimation(Motion.snappy) { store.stopCard(card.id) }
                        actions.say("Stopped. The card is in Blocked.")
                    }
                case .review:
                    PlannerPill(title: "Request changes", style: .quiet) {
                        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else {
                            withAnimation(Motion.snappy) { noteError = true }
                            actions.say("Say what should change")
                            return
                        }
                        if store.isLive {
                            store.moveLive(card.id, to: .ready, note: text, done: "Sent back to Ready with your note", say: actions.say)
                            note = ""
                            return
                        }
                        withAnimation(Motion.snappy) { store.requestChanges(card.id, note: text) }
                        note = ""
                        actions.say("Sent back to Ready with your note")
                    }
                    PlannerPill(title: "Approve", symbol: "checkmark", style: .gold) {
                        Haptics.success()
                        move(.done, "Approved. The card is Done.")
                    }
                case .blocked:
                    PlannerPill(title: "Retry", symbol: "arrow.clockwise", style: .gold) {
                        if store.isLive {
                            store.moveLive(card.id, to: .ready, done: "Back in Ready for another try", say: actions.say)
                            return
                        }
                        withAnimation(Motion.snappy) { store.retryCard(card.id) }
                        actions.say("Back in Ready for another try")
                    }
                case .done:
                    PlannerPill(title: "Reopen", symbol: "arrow.uturn.backward", style: .quiet) {
                        move(.ready, "Reopened in Ready")
                    }
                }
                Spacer(minLength: 0)
                if card.column != .running {
                    PlannerRoundButton(symbol: "trash", label: "Delete card", size: 44, tint: Palette.danger) {
                        actions.delete(card)
                    }
                }
            }
            // Paired: a write for this card is on its way, so its buttons wait (Stop stays for a running card).
            .disabled(store.isLive && (store.busy.contains(card.id) || (store.starting.contains(card.id) && card.column != .running)))
            .opacity(store.isLive && store.waits(card.id) && card.column != .running ? 0.6 : 1)
        }
        .confirmationDialog("Run this card now?", isPresented: $confirmRun, titleVisibility: .visible) {
            Button("Run now") { startLiveRun() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(card.name) starts on your desktop now and can use its model and tools.")
        }
    }

    private func move(_ column: WorkColumn, _ message: String) {
        if store.isLive {
            store.moveLive(card.id, to: column, done: message, say: actions.say)
            return
        }
        withAnimation(Motion.snappy) { store.move(card.id, to: column) }
        actions.say(message)
    }

    private func run() {
        if store.isLive {
            // Real work on the desktop: ask first.
            confirmRun = true
            return
        }
        Haptics.thud()
        withAnimation(Motion.snappy) { store.runCard(card.id) }
        actions.say("Running \(card.name)")
    }

    private func startLiveRun() {
        Haptics.thud()
        store.runCardLive(card.id, say: actions.say)
    }
}

// MARK: - Card detail sheet

struct WorkCardSheet: View {
    @Bindable var store: TasksStore
    let cardID: String
    let onDelete: (WorkCard) -> Void
    @State private var notice: String?

    var body: some View {
        ScrollView {
            if let card = store.card(cardID) {
                VStack(alignment: .leading, spacing: 18) {
                    PlannerSheetTitle(title: card.column.title, subtitle: "Card")
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "What to do")
                        Text(card.instructions)
                            .font(KFont.ui(15.5))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .kCard(radius: 18)
                    }
                    WorkCardView(store: store, card: card, actions: WorkCardActions(
                        open: { _ in },
                        delete: onDelete,
                        say: { notice = $0 }
                    ), inSheet: true)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Run history (\(card.runs.count))")
                        if store.isLive, card.runs.isEmpty, let state = store.cardRunsLoad[cardID], state != .loaded {
                            TasksLoadLine(state: state, waiting: "Reading the run history.") {
                                Task { await store.loadCardRuns(cardID) }
                            }
                        } else if store.isLive {
                            RunHistoryList(runs: card.runs, onSendAgain: { store.sendAgainLive(run: $0) },
                                           loadSteps: { try await store.loadSteps($0) })
                        } else {
                            RunHistoryList(runs: card.runs, onSendAgain: { store.sendAgain(run: $0) })
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            } else {
                PlannerEmpty(title: "This card is gone", hint: "It was deleted.", pose: .idle)
                    .padding(18)
                    .padding(.top, 30)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .plannerNotice($notice)
        .task {
            if store.isLive { await store.loadCardRuns(cardID) }
        }
    }
}

// MARK: - Add a card

struct WorkAddCardSheet: View {
    @Bindable var store: TasksStore
    let onAdded: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var what = ""
    @State private var model = TasksOptions.defaultModel
    @State private var waitsFor = "none"
    @State private var notice: String?
    @State private var endpointID = ""
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlannerSheetTitle(title: "Add a card")
                PlannerTextField(label: "Name", placeholder: "Compare three rental quotes", text: $name)
                PlannerTextField(label: "What to do", placeholder: "Say what the card should do and what done looks like",
                                 text: $what, multiline: true)
                VStack(spacing: 0) {
                    if store.isLive {
                        PlannerMenuRow(title: "Model", symbol: "sparkle", options: store.modelIDs, selection: $endpointID,
                                       label: { store.modelLabel($0) })
                    } else {
                        PlannerMenuRow(title: "Model", symbol: "sparkle", options: TasksOptions.models, selection: $model, label: { $0 })
                    }
                    PlannerMenuRow(title: "Waits for", symbol: "link", options: ["none"] + waitable.map(\.id),
                                   selection: $waitsFor, label: { id in id == "none" ? "Nothing" : (store.card(id)?.name ?? "Nothing") },
                                   last: true)
                }
                .kCard(radius: 18)
                GoldButton(title: "Add to Ready") { add(ready: true) }
                    .padding(.top, 6)
                    .disabled(adding)
                QuietButton(title: "Add to Backlog") { add(ready: false) }
                    .disabled(adding)
                if adding {
                    TasksLiveLine(text: "Adding the card on your desktop.")
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .plannerNotice($notice)
    }

    private var waitable: [WorkCard] { store.cards.filter { $0.column != .done } }

    private func add(ready: Bool) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = what.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !w.isEmpty else {
            Haptics.thud()
            notice = "A card needs a name and what to do"
            return
        }
        if store.isLive {
            guard !adding else { return }
            adding = true
            let waits = waitsFor == "none" ? nil : waitsFor
            Task {
                let problem = await store.addCardLive(name: n, instructions: w, endpointID: endpointID, waitsFor: waits, ready: ready)
                adding = false
                if let problem {
                    Haptics.thud()
                    notice = problem
                    return
                }
                Haptics.success()
                onAdded(ready ? "Card added; Kairos will pick it up" : "Card added to the backlog")
                dismiss()
            }
            return
        }
        Haptics.success()
        withAnimation(Motion.snappy) {
            store.addCard(name: n, instructions: w, model: model, waitsFor: waitsFor == "none" ? nil : waitsFor, ready: ready)
        }
        onAdded(ready ? "Card added; Kairos will pick it up" : "Card added to the backlog")
        dismiss()
    }
}
