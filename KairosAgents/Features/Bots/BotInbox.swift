import SwiftUI

/// The Inbox half of a bot's panel: what needs you, what is working, what is done,
/// then notifications, activity and the reports.
struct BotInboxSection: View {
    let botID: String
    let store = BotsStore.shared
    let live = BotsInboxLive.shared
    @State private var showAllDone = false

    var body: some View {
        let cards = store.needs.filter { $0.botID == botID }
        let working = store.work.filter { $0.botID == botID && ($0.state == .working || $0.state == .failed) }
        let done = store.work.filter { $0.botID == botID && ($0.state == .done || $0.state == .review) }
        let unread = store.notices.filter { $0.botID == botID && $0.unread }.count
        let pending = cards.filter { $0.settled == nil }

        VStack(alignment: .leading, spacing: 18) {
            if store.liveMode {
                liveNeedsYou(cards)
                liveWork
            } else {
            VStack(alignment: .leading, spacing: 10) {
                labelRow("Needs you", count: pending.count)
                if cards.isEmpty {
                    EmptyNote(text: "Nothing is waiting on you.", symbol: "checkmark.circle").kCard(radius: 20)
                } else {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        NeedsCardView(card: card)
                            .arrives(index)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                labelRow("Working", count: working.count)
                if working.isEmpty {
                    EmptyNote(text: "Nothing is running right now.", symbol: "moon.zzz").kCard(radius: 20)
                } else {
                    ForEach(Array(working.enumerated()), id: \.element.id) { index, item in
                        WorkRow(item: item).arrives(index + cards.count)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                labelRow("Done", count: done.count)
                if done.isEmpty {
                    EmptyNote(text: "Nothing is done yet.", symbol: "tray").kCard(radius: 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(done.prefix(showAllDone ? 20 : 3).enumerated()), id: \.element.id) { index, item in
                            if index > 0 { RowLine(inset: 54) }
                            DoneRow(item: item)
                        }
                        if done.count > 3 {
                            RowLine()
                            Button {
                                withAnimation(Motion.snappy) { showAllDone.toggle() }
                            } label: {
                                Text(showAllDone ? "Show fewer" : "Show all \(done.count)")
                                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                                    .foregroundStyle(Palette.goldText)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .kCard(radius: 20)
                }
            }
            }

            VStack(spacing: 0) {
                NavigationLink(value: BotsRoute.notifications(botID)) {
                    NavRow(title: "Notifications", symbol: "bell", badge: store.liveMode ? live.unread(botID) : unread)
                }
                RowLine(inset: 54)
                NavigationLink(value: BotsRoute.activity(botID)) {
                    NavRow(title: "Activity", symbol: "list.bullet.rectangle", detail: "Everything it did, newest first")
                }
                RowLine(inset: 54)
                NavigationLink(value: BotsRoute.report(botID)) {
                    NavRow(title: "\(store.bot(botID).name)'s report", symbol: "chart.bar.doc.horizontal")
                }
                if let team = store.team(of: botID) {
                    RowLine(inset: 54)
                    NavigationLink(value: BotsRoute.teamReport(team.id)) {
                        NavRow(title: "Team report", symbol: "person.3", detail: team.name)
                    }
                }
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .kCard(radius: 20)

            if store.liveMode, live.inboxSkipped + live.workSkipped > 0 {
                HintLine(text: "Some items from your desktop could not be read and are left out.", symbol: "info.circle")
                    .padding(.horizontal, 4)
            }
        }
        .animation(Motion.bouncy, value: store.needs)
        .task(id: BotsStore.connectionKey) {
            store.followConnection()
            guard store.liveMode else { return }
            // Its own task: the connection settling restarts this one, and that must not cut the reads short.
            await Task {
                await live.loadInbox()
                await live.loadWork()
                await live.loadNotices()
            }.value
        }
        .task(id: "\(BotsStore.connectionKey)-\(live.watching(botID))") {
            // While something of this bot's runs or waits its turn, read Working and Needs you again now and then.
            guard store.liveMode, live.watching(botID) else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, store.liveMode else { return }
                await live.loadWork()
                await live.loadInbox()
            }
        }
    }

    // MARK: Paired

    /// The desktop's waiting cards (approvals and questions in a conversation), then its questions and
    /// results to review. Empty, still reading and could not be read are three different lines.
    @ViewBuilder
    private func liveNeedsYou(_ cards: [NeedsCard]) -> some View {
        let rows = live.needsRows(botID)
        let pending = cards.filter { $0.settled == nil }.count + rows.filter { live.answered[$0.id] == nil }.count
        let cardState = store.cardsLoad[botID] ?? .idle
        let rowState = live.inboxLoad
        VStack(alignment: .leading, spacing: 10) {
            labelRow("Needs you", count: pending)
            if cards.isEmpty && rows.isEmpty {
                if case .failed = cardState {
                    BotsLoadNote(state: cardState) { reloadNeeds() }
                } else if case .failed = rowState {
                    BotsLoadNote(state: rowState) { reloadNeeds() }
                } else if cardState != .loaded || rowState != .loaded {
                    BotsLoadNote(state: .loading, waiting: "Reading what needs you from your desktop.") {}
                } else {
                    EmptyNote(text: "Nothing is waiting on you.", symbol: "checkmark.circle").kCard(radius: 20)
                }
            } else {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    NeedsCardView(card: card)
                        .arrives(min(index, 12))
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    InboxRowCard(row: row)
                        .arrives(min(index + cards.count, 12))
                }
                if case .failed = cardState {
                    BotsLoadNote(state: cardState) { reloadNeeds() }
                } else if case .failed = rowState {
                    BotsLoadNote(state: rowState) { reloadNeeds() }
                } else if cardState != .loaded || rowState != .loaded {
                    BotsLoadNote(state: .loading, waiting: "Reading the rest from your desktop.") {}
                }
            }
        }
    }

    private func reloadNeeds() {
        Task {
            await store.loadCards(botID)
            await live.loadInbox()
        }
    }

    /// Working and Done: this bot's cards and running routines on the desktop.
    @ViewBuilder
    private var liveWork: some View {
        let rows = live.workRows(botID)
        let state = live.workLoad
        let ready = state == .loaded || !live.work.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            labelRow("Working", count: ready ? rows.working.count : 0)
            if !ready {
                BotsLoadNote(state: state == .idle ? .loading : state, waiting: "Reading what it is working on.") {
                    Task { await live.loadWork() }
                }
            } else {
                if rows.working.isEmpty {
                    EmptyNote(text: "Nothing is running right now.", symbol: "moon.zzz").kCard(radius: 20)
                } else {
                    ForEach(Array(rows.working.enumerated()), id: \.element.id) { index, item in
                        LiveWorkRow(item: item).arrives(min(index, 12))
                    }
                }
                if case .failed = state {
                    BotsLoadNote(state: state) { Task { await live.loadWork() } }
                }
            }
        }

        if ready {
            VStack(alignment: .leading, spacing: 10) {
                labelRow("Done", count: rows.done.count)
                if rows.done.isEmpty {
                    EmptyNote(text: "Nothing is done yet.", symbol: "tray").kCard(radius: 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.done.prefix(showAllDone ? 20 : 3).enumerated()), id: \.element.id) { index, item in
                            if index > 0 { RowLine(inset: 54) }
                            LiveDoneRow(item: item)
                        }
                        if rows.done.count > 3 {
                            RowLine()
                            Button {
                                withAnimation(Motion.snappy) { showAllDone.toggle() }
                            } label: {
                                Text(showAllDone ? "Show fewer" : "Show \(min(rows.done.count, 20)) most recent")
                                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                                    .foregroundStyle(Palette.goldText)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .kCard(radius: 20)
                }
            }
        }
    }

    private func labelRow(_ text: String, count: Int) -> some View {
        HStack(spacing: 8) {
            SectionLabel(text: text).fixedSize()
            if count > 0 {
                Text("\(count)")
                    .font(KFont.ui(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(Palette.inkDim)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Needs you

/// One approval, question or review waiting on the person.
struct NeedsCardView: View {
    let card: NeedsCard
    let store = BotsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(kindLabel).font(KFont.ui(13, .medium, relativeTo: .footnote))
                Spacer()
                Text(card.age).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            }
            .foregroundStyle(card.settled == nil ? Palette.goldText : Palette.inkFaint)

            switch card.kind {
            case .approval(let title, let summary, let covers, let details):
                ApprovalBody(card: card, title: title, summary: summary, covers: covers, details: details)
            case .question(let questions):
                QuestionBody(card: card, questions: questions)
            case .review(let title, let summary):
                ReviewBody(card: card, title: title, summary: summary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(radius: 22, raised: card.settled == nil)
        .overlay {
            if card.settled == nil {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.gold.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private var kindLabel: String {
        switch card.kind {
        case .approval: "Needs your OK"
        case .question: "Needs your answer"
        case .review: "Ready for review"
        }
    }

    private var symbol: String {
        switch card.kind {
        case .approval: "checkmark.shield"
        case .question: "questionmark.bubble"
        case .review: "eye"
        }
    }
}

/// The settled line that replaces a card's buttons.
struct SettledLine: View {
    let settled: Settled
    var body: some View {
        Label(settled.text, systemImage: settled.good ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
            .foregroundStyle(settled.good ? Palette.success : Palette.danger)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

private struct ApprovalBody: View {
    let card: NeedsCard
    let title: String
    let summary: String
    let covers: String
    let details: [String]
    let store = BotsStore.shared
    @State private var replying = false
    @State private var reply = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
            Text(summary).font(KFont.ui(15, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            VStack(alignment: .leading, spacing: 4) {
                Label("Covers \(covers)", systemImage: "scope")
                ForEach(details, id: \.self) { Text($0) }
            }
            .font(KFont.ui(13.5, relativeTo: .footnote))
            .foregroundStyle(Palette.inkFaint)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let settled = card.settled {
                SettledLine(settled: settled)
            } else if replying {
                replyBox
            } else {
                HStack(spacing: 8) {
                    PillButton(title: "Reject", look: .plain, wide: true) { settle(.denied) }
                    PillButton(title: "Allow", look: .filled, wide: true) { settle(.allowedOnce) }
                }
                HStack(spacing: 8) {
                    if card.live == nil {
                        PillButton(title: "Reply", symbol: "arrowshape.turn.up.left", wide: true) {
                            withAnimation(Motion.snappy) { replying = true }
                            focused = true
                        }
                    }
                    if card.live == nil || store.offers(card, .allowedChat) || store.offers(card, .allowedTeam) {
                    Menu {
                        Button("Allow once") { settle(.allowedOnce) }
                        if store.offers(card, .allowedChat) {
                            Button("Allow for this chat") { settle(.allowedChat) }
                        }
                        if teamAllow {
                            Button("Allow for the team") { settle(.allowedTeam) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("More ways to allow").font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Palette.ink.opacity(0.1), in: Capsule())
                    }
                    }
                }
                if teamAllow {
                    PillButton(title: "Allow for the team", symbol: "person.3", wide: true) { settle(.allowedTeam) }
                }
            }
        }
    }

    private var replyBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Tell it what to do instead", text: $reply, axis: .vertical)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .lineLimit(1...4)
                .focused($focused)
                .padding(12)
                .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 8) {
                PillButton(title: "Cancel", wide: true) { withAnimation(Motion.snappy) { replying = false } }
                PillButton(title: "Send reply", look: .filled, wide: true) {
                    guard !reply.trimmingCharacters(in: .whitespaces).isEmpty else {
                        store.say("Write a reply first.")
                        return
                    }
                    settle(.replied(reply))
                }
            }
        }
    }

    /// A desktop card offers team allow only when its choices do; a sample card when the bot has a team.
    private var teamAllow: Bool {
        card.live == nil ? store.team(of: card.botID) != nil : store.offers(card, .allowedTeam)
    }

    private func settle(_ result: Settled) {
        Haptics.success()
        if card.live != nil {
            store.respondLive(card, result)
        } else {
            store.settle(card.id, result)
        }
    }
}

/// Questions: one tab per question that stays in view, big tap-to-answer choices.
private struct QuestionBody: View {
    let card: NeedsCard
    let questions: [BotQuestion]
    let store = BotsStore.shared
    @State private var current = 0
    @State private var picks: [Int: Set<Int>] = [:]
    @State private var custom: [Int: String] = [:]
    @State private var warn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let settled = card.settled {
                Text(questions.first?.prompt ?? "").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                Text(summary).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                SettledLine(settled: settled)
            } else {
                if questions.count > 1 { tabs }
                questionView(questions[current])
                    .id(current)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                if warn {
                    HintLine(text: "Answer every question first.", symbol: "exclamationmark.circle", color: Palette.danger)
                }
                controls
            }
        }
        .animation(Motion.snappy, value: current)
    }

    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(questions.indices, id: \.self) { index in
                        let on = index == current
                        let answered = isAnswered(index)
                        Button {
                            Haptics.select()
                            current = index
                        } label: {
                            HStack(spacing: 5) {
                                if answered { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                                Text("\(index + 1). \(questions[index].tab)")
                                    .font(KFont.ui(14, on ? .semibold : .regular, relativeTo: .footnote))
                            }
                            .foregroundStyle(on ? Palette.onGold : Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .id(index)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: current) { _, value in
                withAnimation(Motion.snappy) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }

    private func questionView(_ question: BotQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.prompt).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
            if question.multi {
                Text("Pick all that apply.").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            ForEach(question.options.indices, id: \.self) { option in
                choice(question, option)
            }
            if question.allowsOther || question.options.isEmpty {
            TextField("Something else", text: Binding(
                get: { custom[current] ?? "" },
                set: { custom[current] = $0 }
            ))
            .font(KFont.ui(16))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func choice(_ question: BotQuestion, _ option: Int) -> some View {
        let on = picks[current, default: []].contains(option)
        let item = question.options[option]
        return Button {
            Haptics.select()
            var set = picks[current, default: []]
            if question.multi {
                if set.contains(option) { set.remove(option) } else { set.insert(option) }
            } else {
                set = [option]
            }
            withAnimation(Motion.snappy) { picks[current] = set; warn = false }
            if !question.multi, current < questions.count - 1 {
                Task {
                    try? await Task.sleep(for: .milliseconds(280))
                    withAnimation(Motion.snappy) { current += 1 }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: question.multi ? (on ? "checkmark.square.fill" : "square") : (on ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(on ? Palette.goldText : Palette.inkFaint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(KFont.ui(16.5, on ? .semibold : .regular)).foregroundStyle(Palette.ink)
                    if !item.detail.isEmpty {
                        Text(item.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(on ? Palette.gold.opacity(0.16) : Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Palette.gold : Color.clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if current > 0 {
                PillButton(title: "Back", wide: true) { current -= 1 }
            } else {
                PillButton(title: "Skip", wide: true) {
                    Haptics.tap()
                    if card.live != nil {
                        store.respondLive(card, .skipped)
                    } else {
                        store.settle(card.id, .skipped)
                    }
                }
            }
            if current < questions.count - 1 {
                PillButton(title: "Next", look: .filled, wide: true) { current += 1 }
            } else {
                PillButton(title: questions.count > 1 ? "Send answers" : "Send answer", look: .filled, wide: true) {
                    if questions.indices.allSatisfy(isAnswered) {
                        Haptics.success()
                        if card.live != nil {
                            store.respondLive(card, .answered, answers: liveAnswers)
                        } else {
                            store.settle(card.id, .answered)
                        }
                    } else {
                        Haptics.thud()
                        withAnimation(Motion.snappy) {
                            warn = true
                            current = questions.indices.first { !isAnswered($0) } ?? current
                        }
                    }
                }
            }
        }
    }

    /// The answers for the desktop, keyed by question id: a text, or a list of texts when it allows several.
    private var liveAnswers: [String: Any] {
        var out: [String: Any] = [:]
        for index in questions.indices {
            let question = questions[index]
            let chosen = (picks[index] ?? []).sorted().map { question.options[$0].title }
            let typed = (custom[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if question.multi {
                out[question.key] = chosen + (typed.isEmpty ? [] : [typed])
            } else {
                out[question.key] = typed.isEmpty ? (chosen.first ?? "") : typed
            }
        }
        return out
    }

    private func isAnswered(_ index: Int) -> Bool {
        !(picks[index] ?? []).isEmpty || !(custom[index] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var summary: String {
        questions.indices.map { index in
            let chosen = (picks[index] ?? []).sorted().map { questions[index].options[$0].title }
            let extra = custom[index].map { [$0] } ?? []
            let all = (chosen + extra).filter { !$0.isEmpty }
            return "\(questions[index].tab): \(all.isEmpty ? "no answer" : all.joined(separator: ", "))"
        }
        .joined(separator: " · ")
    }
}

private struct ReviewBody: View {
    let card: NeedsCard
    let title: String
    let summary: String
    let store = BotsStore.shared
    @State private var changes = ""
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
            Text(summary).font(KFont.ui(15, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            if let settled = card.settled {
                SettledLine(settled: settled)
            } else if asking {
                TextField("What should change?", text: $changes, axis: .vertical)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(spacing: 8) {
                    PillButton(title: "Cancel", wide: true) { withAnimation(Motion.snappy) { asking = false } }
                    PillButton(title: "Request changes", look: .filled, wide: true) {
                        guard !changes.isEmpty else { store.say("Write what should change first."); return }
                        store.settle(card.id, .replied(changes))
                    }
                }
            } else {
                HStack(spacing: 8) {
                    PillButton(title: "Request changes", wide: true) { withAnimation(Motion.snappy) { asking = true } }
                    PillButton(title: "Approve", look: .filled, wide: true) {
                        Haptics.success()
                        store.settle(card.id, .allowedOnce)
                    }
                }
            }
        }
    }
}

// MARK: - Working and done

struct WorkRow: View {
    let item: WorkItem
    let store = BotsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if item.state == .failed {
                    StateTag(text: "Could not finish", color: Palette.danger)
                } else {
                    StateTag(text: "Working", color: Palette.working, pulsing: true)
                }
                Spacer()
                Text(item.updated).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            }
            Text(item.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
            Text(item.detail).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            if item.state == .working {
                MeterBar(fraction: item.progress, height: 6)
                HStack {
                    Spacer()
                    PillButton(title: "Stop", symbol: "stop.fill") {
                        Haptics.thud()
                        update { $0.state = .failed; $0.detail = "You stopped this."; $0.updated = "just now" }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    PillButton(title: "Try again", symbol: "arrow.clockwise", look: .filled) {
                        Haptics.tap()
                        update { $0.state = .working; $0.progress = 0.05; $0.detail = "Starting again"; $0.updated = "just now" }
                        store.say("Started again")
                    }
                }
            }
        }
        .padding(14)
        .kCard(radius: 20)
    }

    private func update(_ change: (inout WorkItem) -> Void) {
        guard let index = store.work.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(Motion.snappy) { change(&store.work[index]) }
    }
}

struct DoneRow: View {
    let item: WorkItem
    let store = BotsStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.state == .review ? "eye.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(item.state == .review ? Palette.goldText : Palette.success)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink).lineLimit(2)
                Text(item.state == .review ? "Ready for review · \(item.updated)" : "\(item.detail) · \(item.updated)")
                    .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.state == .review {
                PillButton(title: "Mark done") {
                    guard let index = store.work.firstIndex(where: { $0.id == item.id }) else { return }
                    Haptics.success()
                    withAnimation(Motion.snappy) { store.work[index].state = .done }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }
}

// MARK: - Paired: questions, reviews and work

/// A bot's question ("item:") or a result to review ("review:") from the desktop's inbox. Its buttons are
/// the row's own actions. While the answer is on its way the buttons are off; a lost answer keeps what was typed.
struct InboxRowCard: View {
    let row: BotInboxRowDTO
    let live = BotsInboxLive.shared
    let store = BotsStore.shared
    @State private var text = ""
    @State private var replying = false
    @State private var writing = false
    @State private var confirm: Pending?
    @FocusState private var focused: Bool

    enum Pending: String, Identifiable {
        case reply, close
        var id: String { rawValue }
    }

    private var review: Bool { BotsInboxWire.lane(row.id) == "review" }
    private var actions: [String] { row.actions ?? [] }
    private var busy: Bool { live.busyRows.contains(row.id) }
    private var settled: String? { live.answered[row.id]?.text }
    private var botName: String { row.sender?.name ?? store.bot(row.sender?.id ?? "").name }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: review ? "eye" : "questionmark.bubble").font(.system(size: 13, weight: .semibold))
                Text(review ? "Ready for review" : "Needs your answer").font(KFont.ui(13, .medium, relativeTo: .footnote))
                Spacer()
                Text(ChatFormat.listTime(row.at.map { Date(timeIntervalSince1970: $0) }))
                    .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            }
            .foregroundStyle(settled == nil ? Palette.goldText : Palette.inkFaint)

            Text(row.subject ?? "Waiting for you").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
            let detail = (row.body ?? row.snippet ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty {
                Text(detail)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(8)
            }

            if let settled {
                Label(settled, systemImage: "checkmark.circle.fill")
                    .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.success)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else if row.revision == nil || actions.filter({ $0 != "open" }).isEmpty {
                HintLine(text: "Answer this one on your desktop.", symbol: "desktopcomputer")
            } else if replying || writing {
                replyBox
            } else {
                HStack(spacing: 8) {
                    if review {
                        if actions.contains("reply") {
                            PillButton(title: "Request changes", wide: true) { startReply() }
                        }
                        if actions.contains("approve") {
                            PillButton(title: "Approve", look: .filled, wide: true) { send("approve") }
                        }
                    } else {
                        if actions.contains("close") {
                            PillButton(title: "Close", wide: true) { confirm = .close }
                        }
                        if actions.contains("reply") {
                            PillButton(title: "Reply", symbol: "arrowshape.turn.up.left", look: .filled, wide: true) { startReply() }
                        }
                    }
                }
                .disabled(busy)
                .opacity(busy ? 0.5 : 1)
            }
            if busy {
                HintLine(text: "Sending to your desktop.", symbol: "arrow.up.circle")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(radius: 22, raised: settled == nil)
        .overlay {
            if settled == nil {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.gold.opacity(0.35), lineWidth: 1)
            }
        }
        .animation(Motion.snappy, value: replying)
        .sheet(item: $confirm) { pending in
            switch pending {
            case .reply:
                ConfirmSheet(title: "Send this reply?", detail: "\(botName) gets your reply: \(trimmed)", confirm: "Send reply", danger: false) {
                    send("reply")
                }
            case .close:
                ConfirmSheet(title: "Close this question?", detail: "\(botName) gets no answer, and the question cannot be answered after this.", confirm: "Close question") {
                    send("close")
                }
            }
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var replyBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(review ? "What should change?" : "Your reply", text: $text, axis: .vertical)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .lineLimit(1...4)
                .focused($focused)
                .padding(12)
                .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 8) {
                PillButton(title: "Cancel", wide: true) {
                    text = ""
                    focused = false
                    replying = false
                }
                PillButton(title: review ? "Request changes" : "Send reply", look: .filled, wide: true) {
                    guard !trimmed.isEmpty else {
                        store.say(review ? "Write what should change first." : "Write a reply first.")
                        return
                    }
                    if review {
                        guard !BotsInboxWire.isApprovalWord(trimmed) else {
                            store.say("Say what should change. A word like ok would approve it instead.")
                            return
                        }
                        send("reply")
                    } else {
                        confirm = .reply
                    }
                }
            }
        }
        .disabled(busy || writing)
        .opacity(busy || writing ? 0.5 : 1)
    }

    private func send(_ action: String) {
        guard !busy, !writing else { return }
        Haptics.tap()
        writing = true
        let sent = action == "reply" ? trimmed : ""
        Task {
            let outcome = await live.respond(row, action: action, text: sent)
            writing = false
            if outcome == .done {
                text = ""
                focused = false
                replying = false
            }
        }
    }

    private func startReply() {
        replying = true
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            focused = true
        }
    }
}

/// A running, waiting or stuck card or routine on the desktop.
struct LiveWorkRow: View {
    let item: BotWorkRow
    let live = BotsInboxLive.shared

    var body: some View {
        let busy = live.busyWork.contains(item.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                switch item.state {
                case .failed: StateTag(text: "Could not finish", color: Palette.danger)
                case .waiting: StateTag(text: "Waiting", color: Palette.inkDim)
                default: StateTag(text: "Working", color: Palette.working, pulsing: true)
                }
                Spacer()
                Text(item.updated).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            }
            Text(item.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
            Text(item.detail).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim).lineLimit(4)
            if item.state == .running && item.canStop {
                HStack {
                    Spacer()
                    PillButton(title: busy ? "Stopping" : "Stop", symbol: "stop.fill") {
                        Haptics.thud()
                        live.stop(item)
                    }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                }
            } else if item.state == .failed {
                HStack {
                    Spacer()
                    PillButton(title: busy ? "Sending" : "Try again", symbol: "arrow.clockwise", look: .filled) {
                        Haptics.tap()
                        live.tryAgain(item)
                    }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                }
            }
        }
        .padding(14)
        .kCard(radius: 20)
    }
}

/// A finished card on the desktop.
struct LiveDoneRow: View {
    let item: BotWorkRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Palette.success)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink).lineLimit(2)
                Text(item.updated.isEmpty ? item.detail : "\(item.detail) · \(item.updated)")
                    .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }
}

// MARK: - Notifications

struct BotNotificationsScreen: View {
    let botID: String
    let store = BotsStore.shared
    let live = BotsInboxLive.shared
    @State private var filter = "All"
    @State private var calling = false

    private let filters = ["All", "Unread", "Needs you", "Problems"]

    var body: some View {
        Group {
            if store.liveMode { liveBody } else { sampleBody }
        }
        .task(id: BotsStore.connectionKey) {
            store.followConnection()
            guard store.liveMode else { return }
            await Task { await live.loadNotices() }.value
        }
    }

    // MARK: Paired

    /// This bot's notifications on the desktop. Reading one, pinning one and Mark all read are the desktop's
    /// own; there is no route to mark one unread, so that is not offered here.
    @ViewBuilder
    private var liveBody: some View {
        let rows = liveFiltered
        let unread = live.unread(botID)
        let ready = live.noticesLoad == .loaded || !live.notices.isEmpty
        let marking = live.markingAll.contains(botID)
        BotsPage("Notifications", subtitle: !ready ? store.bot(botID).name : (unread == 0 ? "All caught up" : "\(unread) unread"), live: true) {
            GoldSegmented(items: filters, selection: $filter) { $0 }
            if !ready {
                BotsLoadNote(state: live.noticesLoad == .idle ? .loading : live.noticesLoad, waiting: "Reading notifications from your desktop.") {
                    Task { await live.loadNotices() }
                }
            } else {
                if case .failed = live.noticesLoad {
                    BotsLoadNote(state: live.noticesLoad) { Task { await live.loadNotices() } }
                }
                if unread > 0 {
                    HStack {
                        Spacer()
                        PillButton(title: marking ? "Marking read" : "Mark all read", symbol: "checkmark") {
                            live.markAllRead(botID)
                        }
                        .disabled(marking)
                        .opacity(marking ? 0.5 : 1)
                    }
                }
                if rows.isEmpty {
                    EmptyNote(text: filter == "All" ? "No notifications from this bot." : "No notifications here.", symbol: "bell.slash")
                        .kCard(radius: 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, notice in
                            if index > 0 { RowLine(inset: 62) }
                            liveRow(notice).arrives(min(index, 12))
                        }
                    }
                    .kCard(radius: 20)
                }
                if live.noticesSkipped > 0 {
                    HintLine(text: "Some notifications from your desktop could not be read and are left out.", symbol: "info.circle")
                        .padding(.horizontal, 4)
                }
            }
        }
        .fullScreenCover(isPresented: $calling) { CallView(bot: store.bot(botID)) }
    }

    private var liveFiltered: [BotNotificationDTO] {
        let mine = live.noticeRows(botID)
        switch filter {
        case "Unread": return mine.filter { $0.read != true }
        case "Needs you": return mine.filter { BotsInboxWire.noticeLook($0.kind).needsYou }
        case "Problems": return mine.filter { BotsInboxWire.noticeLook($0.kind).problem }
        default: return mine
        }
    }

    private func liveRow(_ notice: BotNotificationDTO) -> some View {
        let look = BotsInboxWire.noticeLook(notice.kind)
        let unread = notice.read != true
        let pinned = notice.pinned == true
        let title = (notice.title?.isEmpty == false ? notice.title : nil) ?? look.label
        let detail = (notice.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let missedCall = notice.kind == "missed-call"
        return Button {
            Haptics.tap()
            live.markRead(notice)
            if missedCall { calling = true }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: look.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(look.problem ? Palette.danger : Palette.goldText)
                    .frame(width: 36, height: 36)
                    .background(Palette.ink.opacity(0.07), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(look.label).font(KFont.ui(12.5, .medium, relativeTo: .caption)).foregroundStyle(look.problem ? Palette.danger : Palette.inkFaint)
                        if pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Palette.goldText) }
                        Spacer()
                        Text(ChatFormat.listTime(notice.at.map { Date(timeIntervalSince1970: $0) }))
                            .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                    }
                    Text(title).font(KFont.ui(16, unread ? .semibold : .regular)).foregroundStyle(Palette.ink)
                    if !detail.isEmpty && detail != title {
                        Text(detail).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim).lineLimit(4)
                    }
                    if missedCall {
                        Label("Tap to call back", systemImage: "phone.fill")
                            .font(KFont.ui(14, .semibold, relativeTo: .footnote))
                            .foregroundStyle(Palette.goldText)
                            .padding(.top, 4)
                    }
                }
                if unread {
                    Circle().fill(Palette.gold).frame(width: 9, height: 9).padding(.top, 24)
                        .accessibilityLabel("Unread")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .disabled(live.busyNotices.contains(notice.id) && !missedCall)
        .contextMenu {
            Button { live.setPinned(notice, !pinned) } label: { Label(pinned ? "Unpin" : "Pin", systemImage: "pin") }
            if unread {
                Button { live.markRead(notice) } label: { Label("Mark read", systemImage: "envelope.open") }
            }
        }
    }

    // MARK: Sample

    @ViewBuilder
    private var sampleBody: some View {
        let items = filtered
        let unread = store.notices.filter { $0.botID == botID && $0.unread }.count
        BotsPage("Notifications", subtitle: unread == 0 ? "All caught up" : "\(unread) unread") {
            GoldSegmented(items: filters, selection: $filter) { $0 }
            if unread > 0 {
                HStack {
                    Spacer()
                    PillButton(title: "Mark all read", symbol: "checkmark") {
                        Haptics.success()
                        withAnimation(Motion.snappy) {
                            for index in store.notices.indices where store.notices[index].botID == botID {
                                store.notices[index].unread = false
                            }
                        }
                    }
                }
            }
            if items.isEmpty {
                EmptyNote(text: "No notifications here.", symbol: "bell.slash").kCard(radius: 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, notice in
                        if index > 0 { RowLine(inset: 62) }
                        row(notice).arrives(index)
                    }
                }
                .kCard(radius: 20)
            }
        }
        .fullScreenCover(isPresented: $calling) { CallView(bot: store.bot(botID)) }
    }

    private var filtered: [BotNotice] {
        let mine = store.notices.filter { $0.botID == botID }
        let chosen: [BotNotice]
        switch filter {
        case "Unread": chosen = mine.filter(\.unread)
        case "Needs you": chosen = mine.filter { $0.kind == "Approval" || $0.kind == "Question" }
        case "Problems": chosen = mine.filter(\.problem)
        default: chosen = mine
        }
        return chosen.sorted { $0.pinned && !$1.pinned }
    }

    private func row(_ notice: BotNotice) -> some View {
        Button {
            Haptics.tap()
            mark(notice) { $0.unread = false }
            if notice.kind == "Missed call" { calling = true }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notice.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(notice.problem ? Palette.danger : Palette.goldText)
                    .frame(width: 36, height: 36)
                    .background(Palette.ink.opacity(0.07), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(notice.kind).font(KFont.ui(12.5, .medium, relativeTo: .caption)).foregroundStyle(notice.problem ? Palette.danger : Palette.inkFaint)
                        if notice.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Palette.goldText) }
                        Spacer()
                        Text(notice.age).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                    }
                    Text(notice.title).font(KFont.ui(16, notice.unread ? .semibold : .regular)).foregroundStyle(Palette.ink)
                    Text(notice.detail).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    if notice.kind == "Missed call" {
                        Label("Tap to call back", systemImage: "phone.fill")
                            .font(KFont.ui(14, .semibold, relativeTo: .footnote))
                            .foregroundStyle(Palette.goldText)
                            .padding(.top, 4)
                    }
                }
                if notice.unread {
                    Circle().fill(Palette.gold).frame(width: 9, height: 9).padding(.top, 24)
                        .accessibilityLabel("Unread")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .contextMenu {
            Button { mark(notice) { $0.pinned.toggle() } } label: { Label(notice.pinned ? "Unpin" : "Pin", systemImage: "pin") }
            Button { mark(notice) { $0.unread.toggle() } } label: { Label(notice.unread ? "Mark read" : "Mark unread", systemImage: "envelope.badge") }
        }
    }

    private func mark(_ notice: BotNotice, _ change: (inout BotNotice) -> Void) {
        guard let index = store.notices.firstIndex(where: { $0.id == notice.id }) else { return }
        withAnimation(Motion.snappy) { change(&store.notices[index]) }
    }
}

// MARK: - Activity

struct BotActivityScreen: View {
    let botID: String
    let store = BotsStore.shared
    let live = BotsInboxLive.shared
    @State private var problemsOnly = false

    var body: some View {
        Group {
            if store.liveMode { liveBody } else { sampleBody }
        }
        .task(id: BotsStore.connectionKey) {
            store.followConnection()
            guard store.liveMode else { return }
            await Task { await live.loadActivity(botID) }.value
        }
    }

    // MARK: Paired

    /// What the desktop recorded for this bot (its runtime events and run steps), grouped by day, newest first.
    @ViewBuilder
    private var liveBody: some View {
        let state = live.activityLoad[botID] ?? .idle
        BotsPage("Activity", subtitle: store.bot(botID).name, live: true) {
            HintLine(text: "What Kairos recorded for this bot, newest first. Older events are removed after 30 days.")
            if let entries = live.activity[botID] {
                if case .failed = state {
                    BotsLoadNote(state: state) { Task { await live.loadActivity(botID) } }
                }
                if entries.isEmpty {
                    EmptyNote(text: "Nothing was recorded for this bot in the last 30 days.", symbol: "list.bullet.rectangle")
                        .kCard(radius: 20)
                } else {
                    let days = Self.days(entries)
                    ForEach(Array(days.enumerated()), id: \.element.day) { dayIndex, group in
                        BotsSection(title: group.day) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { RowLine(inset: 90) }
                                liveRow(entry)
                                    .arrives(min(dayIndex * 4 + index, 12))
                            }
                        }
                    }
                }
                if (live.activitySkipped[botID] ?? 0) > 0 {
                    HintLine(text: "Some events from your desktop could not be read and are left out.", symbol: "info.circle")
                        .padding(.horizontal, 4)
                }
            } else {
                BotsLoadNote(state: state == .idle ? .loading : state, waiting: "Reading activity from your desktop.") {
                    Task { await live.loadActivity(botID) }
                }
            }
        }
    }

    private func liveRow(_ entry: BotActivityEntryDTO) -> some View {
        let line = BotsInboxWire.activityLine(entry)
        let time = entry.at.map { Date(timeIntervalSince1970: $0).formatted(date: .omitted, time: .shortened) } ?? ""
        return HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(KFont.ui(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .monospacedDigit()
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink).lineLimit(2)
                if !line.detail.isEmpty {
                    Text(line.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim).lineLimit(4)
                }
                Text(line.source).font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Entries in day groups, keeping the desktop's newest-first order.
    private static func days(_ entries: [BotActivityEntryDTO]) -> [(day: String, entries: [BotActivityEntryDTO])] {
        var groups: [(day: String, entries: [BotActivityEntryDTO])] = []
        let calendar = Calendar.current
        for entry in entries {
            let date = Date(timeIntervalSince1970: entry.at ?? 0)
            let day: String
            if entry.at == nil {
                day = "Undated"
            } else if calendar.isDateInToday(date) {
                day = "Today"
            } else if calendar.isDateInYesterday(date) {
                day = "Yesterday"
            } else {
                day = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            }
            if let last = groups.indices.last, groups[last].day == day {
                groups[last].entries.append(entry)
            } else if let index = groups.firstIndex(where: { $0.day == day }) {
                groups[index].entries.append(entry)
            } else {
                groups.append((day, [entry]))
            }
        }
        return groups
    }

    // MARK: Sample

    @ViewBuilder
    private var sampleBody: some View {
        let events = BotsSample.activity(for: store.bot(botID))
        let days = events.map(\.day).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        BotsPage("Activity", subtitle: store.bot(botID).name) {
            HintLine(text: "What Kairos recorded for this bot, newest first. Older events are removed after 30 days.")
            ForEach(Array(days.enumerated()), id: \.element) { dayIndex, day in
                BotsSection(title: day) {
                    let rows = events.filter { $0.day == day }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { RowLine(inset: 70) }
                        HStack(alignment: .top, spacing: 12) {
                            Text(event.time)
                                .font(KFont.ui(13, .medium, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkFaint)
                                .monospacedDigit()
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink)
                                Text(event.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                                Text(event.source).font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .arrives(dayIndex * 4 + index)
                    }
                }
            }
        }
    }
}

// MARK: - Report

struct BotReportScreen: View {
    let botID: String
    let store = BotsStore.shared
    let live = BotsInboxLive.shared
    @State private var window = "Last 7 days"
    @State private var refreshing = false

    var body: some View {
        Group {
            if store.liveMode { liveBody } else { sampleBody }
        }
        .task(id: "\(BotsStore.connectionKey)-\(window)") {
            store.followConnection()
            guard store.liveMode else { return }
            await Task { await live.loadReport(botID, days: days) }.value
        }
    }

    private var days: Int { window == "Last 30 days" ? 30 : 7 }

    // MARK: Paired

    /// The desktop's report for this bot over 7 or 30 days: totals, what it made, recent runs, approvals,
    /// and errors with their fixes. Read only.
    @ViewBuilder
    private var liveBody: some View {
        let bot = store.bot(botID)
        let key = BotsInboxLive.reportKey(botID, days: days)
        let state = live.reportLoad[key] ?? .idle
        BotsPage("\(bot.name)'s report", subtitle: window, live: true) {
            GoldSegmented(items: ["Last 7 days", "Last 30 days"], selection: $window) { $0 }
            if let report = live.reports[key] {
                if case .failed = state {
                    BotsLoadNote(state: state) { refresh() }
                }
                reportBody(report)
                PillButton(title: refreshing ? "Refreshing" : "Refresh", symbol: "arrow.clockwise", wide: true) { refresh() }
                    .disabled(refreshing)
                    .opacity(refreshing ? 0.5 : 1)
            } else {
                BotsLoadNote(state: state == .idle ? .loading : state, waiting: "Reading the report from your desktop.") {
                    refresh()
                }
            }
        }
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let span = days
        Task {
            await live.loadReport(botID, days: span)
            refreshing = false
            if live.reportLoad[BotsInboxLive.reportKey(botID, days: span)] == .loaded {
                store.say("Report is up to date")
            }
        }
    }

    @ViewBuilder
    private func reportBody(_ report: BotReportDTO) -> some View {
        let totals = report.totals
        let made = BotLossyList(report.produced).items
        let runs = BotLossyList(report.runs).items
        let errors = BotLossyList(report.errors).items
        let approvals = report.approvals?.summary
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("Runs", "\(totals?.runs ?? 0)")
            tile("Failed", "\(totals?.failed ?? 0)")
            tile("Tokens", BotsInboxWire.tokens(totals?.tokens ?? 0))
            tile("Spend", totals?.costUsd.map(BotsInboxWire.money) ?? "Not known")
        }
        if totals?.costUsd != nil && totals?.costComplete == false {
            HintLine(text: "Some runs have no price, so the spend may be higher.", symbol: "info.circle")
                .padding(.horizontal, 4)
        }
        BotsSection(title: "What it made") {
            if made.isEmpty {
                quietRow("Nothing recorded in this window.")
            } else {
                ForEach(Array(made.enumerated()), id: \.offset) { index, item in
                    if index > 0 { RowLine(inset: 54) }
                    let names = (item.items ?? []).filter { !$0.isEmpty }
                    madeRow("\(item.label ?? "Other") (\(item.count ?? names.count))", names.isEmpty ? "" : names.joined(separator: ", "))
                }
            }
        }
        BotsSection(title: "Recent runs") {
            if runs.isEmpty {
                quietRow("No runs in this window.")
            } else {
                ForEach(Array(runs.prefix(10).enumerated()), id: \.element.id) { index, run in
                    if index > 0 { RowLine() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.what ?? "A run").font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink).lineLimit(2)
                            Text(Self.runLine(run)).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                        }
                        Spacer()
                        StateTag(text: Self.outcomeWord(run), color: Self.outcomeColor(run.outcome), pulsing: run.outcome == "running")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(minHeight: 56)
                }
            }
        }
        BotsSection(title: "Approvals") {
            HStack {
                Text("Asked you \(approvals?.asked ?? 0) \((approvals?.asked ?? 0) == 1 ? "time" : "times")").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer()
                Text("\(approvals?.allowed ?? 0) allowed").font(KFont.ui(14)).foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
        BotsSection(title: "Errors and fixes") {
            if errors.isEmpty {
                quietRow("No errors in this window.")
            } else {
                ForEach(Array(errors.prefix(10).enumerated()), id: \.offset) { index, error in
                    if index > 0 { RowLine() }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error.what ?? "Something went wrong.").font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink)
                        if let fix = error.fix, !fix.isEmpty {
                            Text("Fix: \(fix)").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            }
        }
    }

    private func quietRow(_ text: String) -> some View {
        Text(text)
            .font(KFont.ui(15, relativeTo: .subheadline))
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 16)
    }

    /// "a-model · 42 s · $0.12", leaving out what the desktop did not record.
    private static func runLine(_ run: BotReportRunDTO) -> String {
        var parts: [String] = []
        if let model = run.model, !model.isEmpty { parts.append(model) }
        if let start = run.startedAt, let end = run.endedAt, end >= start {
            let seconds = Int(end - start)
            parts.append(seconds < 60 ? "\(seconds) s" : (seconds < 3600 ? "\(seconds / 60) min" : "\(seconds / 3600) h \(seconds % 3600 / 60) min"))
        } else if let start = run.startedAt {
            parts.append(ChatFormat.listTime(Date(timeIntervalSince1970: start)))
        }
        if let cost = run.costUsd { parts.append(BotsInboxWire.money(cost)) }
        return parts.isEmpty ? "No details recorded" : parts.joined(separator: " · ")
    }

    private static func outcomeWord(_ run: BotReportRunDTO) -> String {
        switch run.outcome {
        case "finished": "Finished"
        case "failed": "Failed"
        case "stopped": "Stopped"
        case "running": "Running"
        default: BotsInboxWire.words(run.result ?? run.outcome) ?? "Unknown"
        }
    }

    private static func outcomeColor(_ outcome: String?) -> Color {
        switch outcome {
        case "finished": Palette.success
        case "failed": Palette.danger
        case "running": Palette.working
        default: Palette.inkDim
        }
    }

    // MARK: Sample

    @ViewBuilder
    private var sampleBody: some View {
        let bot = store.bot(botID)
        let wide = window == "Last 30 days"
        let runs = BotsSample.runs(for: bot)
        BotsPage("\(bot.name)'s report", subtitle: window) {
            GoldSegmented(items: ["Last 7 days", "Last 30 days"], selection: $window) { $0 }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("Runs", wide ? "112" : "31")
                tile("Failed", wide ? "6" : "2")
                tile("Tokens", wide ? "2.4M" : "610K")
                tile("Spend", wide ? "$6.40" : "$1.72")
            }
            BotsSection(title: "What it made") {
                madeRow("Weekly report draft", "Document · today")
                RowLine(inset: 54)
                madeRow("Rival prices", "Sheet · Tuesday")
                RowLine(inset: 54)
                madeRow("Supplier email", "Draft · Monday")
            }
            BotsSection(title: "Recent runs") {
                ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                    if index > 0 { RowLine() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.title).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink)
                            Text("\(run.model) · \(run.duration) · \(run.cost)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        StateTag(text: run.outcome, color: run.outcome == "Failed" ? Palette.danger : (run.outcome == "Running" ? Palette.working : Palette.success), pulsing: run.outcome == "Running")
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                }
            }
            BotsSection(title: "Approvals") {
                HStack {
                    Text("Asked you \(wide ? 14 : 4) times").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(wide ? 12 : 3) allowed").font(KFont.ui(14)).foregroundStyle(Palette.inkFaint)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            }
            BotsSection(title: "Errors and fixes") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Could not sign in to the second shop").font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink)
                    Text("Fix: sign in again under Browser profiles.").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    NavigationLink(value: BotsRoute.settings(botID, .browser)) {
                        Text("Open Browser profiles").font(KFont.ui(14.5, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.goldText)
                            .frame(minHeight: 40)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            PillButton(title: refreshing ? "Refreshing" : "Refresh", symbol: "arrow.clockwise", wide: true) {
                refreshing = true
                Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    refreshing = false
                    store.say("Report is up to date")
                }
            }
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(KFont.label).tracking(1.2).foregroundStyle(Palette.inkFaint)
            Text(value).font(KFont.ui(26, .semibold, relativeTo: .title2)).foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(radius: 18)
        .animation(Motion.snappy, value: window)
    }

    private func madeRow(_ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").font(.system(size: 16)).foregroundStyle(Palette.goldText).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}
