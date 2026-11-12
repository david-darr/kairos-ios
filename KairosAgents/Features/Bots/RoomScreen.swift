import SwiftUI

/// A room: a group chat between you and several bots.
struct RoomScreen: View {
    let roomID: String
    var openSheet: RoomSheet? = nil
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var sheet: RoomSheet?
    @State private var finding = false
    @State private var query = ""
    @State private var hit = 0
    @State private var queued: [String] = []
    @State private var opened = false
    @FocusState private var typing: Bool

    enum RoomSheet: String, Identifiable { case settings, members, conversations; var id: String { rawValue } }

    var body: some View {
        if let index = store.rooms.firstIndex(where: { $0.id == roomID }) {
            room(store.rooms[index], index: index)
        } else {
            BotsPage("Room") { EmptyNote(text: "This room was deleted.", symbol: "number") }
        }
    }

    private func room(_ room: BotRoom, index: Int) -> some View {
        let matches = query.count < 2 ? [] : room.messages.filter { $0.text.localizedCaseInsensitiveContains(query) }.map(\.id)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if room.messages.isEmpty {
                        VStack(spacing: 10) {
                            FaceStack(ids: room.members, size: 56)
                            Text(room.name).font(KFont.display(30)).foregroundStyle(Palette.ink)
                            Text(room.whoAnswers).font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                    ForEach(room.messages) { message in
                        RoomBubble(message: message, highlighted: matches.indices.contains(hit) && matches[hit] == message.id)
                            .id(message.id)
                            .contextMenu {
                                Button { pin(message, in: index) } label: { Label(message.pinned ? "Unpin" : "Pin", systemImage: "pin") }
                                Button {
                                    UIPasteboard.general.string = message.text
                                    store.say("Copied")
                                } label: { Label("Copy", systemImage: "doc.on.doc") }
                                Button {
                                    draft = message.from == "you" ? draft : "@\(store.bot(message.from).name) "
                                    typing = true
                                } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                            }
                    }
                    ForEach(room.working, id: \.self) { id in
                        HStack(spacing: 8) {
                            BotFace(bot: store.bot(id), size: 26, blinks: true)
                            Text("\(store.bot(id).name) is writing").font(KFont.ui(13.5)).foregroundStyle(Palette.inkDim)
                            PulsingDot(color: Palette.working, size: 6)
                            Spacer()
                            PillButton(title: "Stop \(store.bot(id).name)") { stop([id], in: index) }
                        }
                        .padding(10)
                        .kCard(radius: 18)
                    }
                    ForEach(Array(queued.enumerated()), id: \.offset) { position, text in
                        HStack {
                            Text("\(position + 1). \(text) (waiting)").font(KFont.ui(14)).foregroundStyle(Palette.inkDim).lineLimit(1)
                            Spacer()
                            PillButton(title: "Cancel") { _ = withAnimation(Motion.snappy) { queued.remove(at: position) } }
                        }
                        .padding(10)
                        .kCard(radius: 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(Motion.snappy, value: room.messages.count)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: hit) { _, value in
                if matches.indices.contains(value) { withAnimation(Motion.snappy) { proxy.scrollTo(matches[value], anchor: .center) } }
            }
            .onChange(of: room.messages.count) {
                if let last = store.rooms.first(where: { $0.id == roomID })?.messages.last {
                    withAnimation(Motion.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header(room, index: index, matches: matches.count) }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer(room, index: index) }
        }
        .kScreen(glowAt: UnitPoint(x: 0.5, y: -0.05))
        .botsToast()
        .sheet(item: $sheet) { which in
            RoomSettingsSheet(roomID: roomID, which: which)
        }
        .onAppear {
            guard !opened else { return }
            opened = true
            sheet = openSheet
            if let i = store.rooms.firstIndex(where: { $0.id == roomID }) { store.rooms[i].unread = 0 }
        }
    }

    // MARK: Header

    private func header(_ room: BotRoom, index: Int, matches: Int) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                GlassIconButton(symbol: "chevron.left", label: "Back") { dismiss() }
                Spacer()
                Button {
                    Haptics.tap()
                    sheet = .settings
                } label: {
                    VStack(spacing: 4) {
                        FaceStack(ids: room.members, size: 34)
                        HStack(spacing: 4) {
                            Image(systemName: "number").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.goldText)
                            Text(room.name).font(KFont.ui(14.5, .medium))
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.inkFaint)
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .kGlass(Capsule())
                    }
                }
                .buttonStyle(PressStyle(scale: 0.95))
                .accessibilityLabel("\(room.name). Room settings")
                Spacer()
                Menu {
                    Button { sheet = .members } label: { Label("Members", systemImage: "person.2") }
                    Button { withAnimation(Motion.snappy) { finding.toggle() } } label: { Label("Find in room", systemImage: "magnifyingglass") }
                    Button { sheet = .conversations } label: { Label("Conversations", systemImage: "bubble.left.and.bubble.right") }
                    Button { sheet = .settings } label: { Label("Room settings", systemImage: "slider.horizontal.3") }
                    if !room.working.isEmpty {
                        Button(role: .destructive) { stop(room.working, in: index) } label: { Label("Stop all", systemImage: "stop.circle") }
                    }
                    ShareLink(item: exportText(room)) { Label("Export", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("Room menu")
            }
            if finding {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.inkFaint)
                    TextField("Find in room", text: $query).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        .onChange(of: query) { hit = 0 }
                    Text(query.count < 2 ? "" : (matches == 0 ? "No matches" : "\(hit + 1) of \(matches)"))
                        .font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
                    Button {
                        if matches > 0 { hit = (hit + 1) % matches }
                    } label: {
                        Text("Next").font(KFont.ui(14.5, .semibold)).foregroundStyle(Palette.goldText).frame(minWidth: 44, minHeight: 44)
                    }
                    Button {
                        withAnimation(Motion.snappy) { finding = false; query = "" }
                    } label: {
                        Image(systemName: "xmark").foregroundStyle(Palette.inkDim).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close find")
                }
                .padding(.leading, 14)
                .kGlass(Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !room.held.isEmpty {
                HStack {
                    Text("Held: \(room.held.map { store.bot($0).name }.joined(separator: ", "))").font(KFont.ui(14)).foregroundStyle(Palette.ink)
                    Spacer()
                    ForEach(room.held, id: \.self) { id in
                        PillButton(title: "Resume \(store.bot(id).name)") { store.rooms[index].held.removeAll { $0 == id } }
                    }
                }
                .padding(10)
                .kCard(radius: 16, raised: true)
            }
            if let pinned = room.messages.last(where: \.pinned) {
                HStack(spacing: 8) {
                    Image(systemName: "pin.fill").font(.system(size: 12)).foregroundStyle(Palette.goldText)
                    Text(pinned.text).font(KFont.ui(13.5)).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer()
                    Button { pin(pinned, in: index) } label: {
                        Text("Unpin").font(KFont.ui(13.5, .semibold)).foregroundStyle(Palette.goldText).frame(minHeight: 36)
                    }
                }
                .padding(.horizontal, 12)
                .kGlass(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background { HeaderFade() }
        .animation(Motion.snappy, value: finding)
    }

    // MARK: Composer

    private func composer(_ room: BotRoom, index: Int) -> some View {
        let mention = currentMention
        let suggestions = mention == nil ? [] : (["everyone"] + room.members.map { store.bot($0).name }).filter { mention!.isEmpty || $0.lowercased().hasPrefix(mention!.lowercased()) }
        return VStack(spacing: 8) {
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { name in
                            Button {
                                Haptics.select()
                                complete(name)
                            } label: {
                                Text("@\(name)").font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.ink)
                                    .padding(.horizontal, 14).frame(minHeight: 44).kGlass(Capsule())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message the room, @ to mention", text: $draft, axis: .vertical)
                    .font(KFont.ui(16.5)).foregroundStyle(Palette.ink)
                    .lineLimit(1...5).focused($typing)
                    .padding(.vertical, 12).padding(.leading, 16)
                Button { send(room, index: index) } label: {
                    let has = !draft.trimmingCharacters(in: .whitespaces).isEmpty
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(has ? Palette.onGold : Palette.inkFaint)
                        .frame(width: 34, height: 34)
                        .background(has ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Circle())
                        .frame(width: 44, height: 46)
                }
                .buttonStyle(PressStyle(scale: 0.88))
                .accessibilityLabel("Send")
                .padding(.trailing, 4)
            }
            .kGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
            Text(room.working.isEmpty ? room.whoAnswers : "Messages wait their turn.")
                .font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
        }
        .padding(.bottom, 8)
        .animation(Motion.snappy, value: suggestions)
    }

    private var currentMention: String? {
        guard let last = draft.split(separator: " ", omittingEmptySubsequences: false).last, last.hasPrefix("@") else { return nil }
        return String(last.dropFirst())
    }

    private func complete(_ name: String) {
        var words = draft.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if !words.isEmpty { words.removeLast() }
        words.append("@\(name) ")
        draft = words.joined(separator: " ")
    }

    private func send(_ room: BotRoom, index: Int) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { typing = true; return }
        Haptics.tap()
        draft = ""
        if !room.working.isEmpty {
            withAnimation(Motion.snappy) { queued.append(text) }
            return
        }
        withAnimation(Motion.snappy) {
            store.rooms[index].messages.append(RoomMessage(from: "you", text: text, time: "now"))
        }
        let mentioned = room.members.filter { text.localizedCaseInsensitiveContains("@\(store.bot($0).name)") }
        let everyone = text.localizedCaseInsensitiveContains("@everyone")
        let answering = everyone ? room.members : (mentioned.isEmpty ? [room.members.first].compactMap { $0 } : mentioned)
        guard !answering.isEmpty else { return }
        withAnimation(Motion.snappy) { store.rooms[index].working = answering }
        Task {
            for id in answering {
                try? await Task.sleep(for: .seconds(1.2))
                guard let i = store.rooms.firstIndex(where: { $0.id == roomID }), store.rooms[i].working.contains(id) else { continue }
                withAnimation(Motion.snappy) {
                    store.rooms[i].messages.append(RoomMessage(from: id, text: reply(for: id), time: "now"))
                    store.rooms[i].working.removeAll { $0 == id }
                }
            }
        }
    }

    private func reply(for id: String) -> String {
        switch id {
        case "scout": "I'll look into it and bring two sources back here."
        case "quill": "Got it. I'll draft that and post it here."
        case "producer": "Noted. I'll fold it into today's plan."
        case "ledger": "I'll check the books and reply with the totals."
        default: "On it. I'll report back in this room."
        }
    }

    private func stop(_ ids: [String], in index: Int) {
        Haptics.thud()
        withAnimation(Motion.snappy) { store.rooms[index].working.removeAll { ids.contains($0) } }
        store.say(ids.count > 1 ? "Stopped everyone" : "Stopped \(store.bot(ids[0]).name)")
    }

    private func pin(_ message: RoomMessage, in index: Int) {
        guard let m = store.rooms[index].messages.firstIndex(where: { $0.id == message.id }) else { return }
        withAnimation(Motion.snappy) { store.rooms[index].messages[m].pinned.toggle() }
    }

    private func exportText(_ room: BotRoom) -> String {
        (["# \(room.name)"] + room.messages.map { "**\($0.from == "you" ? "You" : store.bot($0.from).name)** (\($0.time)): \($0.text)" })
            .joined(separator: "\n\n")
    }
}

/// One message in a room: yours on the right in gold, each bot's with its face and name.
struct RoomBubble: View {
    let message: RoomMessage
    var highlighted = false
    let store = BotsStore.shared

    var body: some View {
        if message.from == "you" {
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(KFont.ui(16.5)).foregroundStyle(Palette.onGold)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Palette.gold, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.ink, lineWidth: highlighted ? 2 : 0))
            }
        } else {
            let bot = store.bot(message.from)
            HStack(alignment: .bottom, spacing: 8) {
                BotFace(bot: bot, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(bot.name).font(KFont.ui(12.5, .semibold)).foregroundStyle(Palette.inkDim)
                        if message.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Palette.goldText) }
                        Text(message.time).font(KFont.ui(12)).foregroundStyle(Palette.inkFaint)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message.text).font(KFont.ui(16.5)).foregroundStyle(Palette.ink)
                        if let handoff = message.handoff { HandoffChip(handoff: handoff) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(highlighted ? Palette.gold : Palette.line, lineWidth: highlighted ? 2 : 1))
                }
                Spacer(minLength: 40)
            }
        }
    }
}

/// "Delegated to Quill", its status and when it counts as done.
struct HandoffChip: View {
    let handoff: Handoff
    let store = BotsStore.shared

    var body: some View {
        NavigationLink(value: BotsRoute.botPage(handoff.to)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.goldText)
                    Text("\(handoff.verb) to \(store.bot(handoff.to).name)").font(KFont.ui(14, .semibold)).foregroundStyle(Palette.ink)
                    StateTag(text: handoff.status, color: handoff.status == "Done" ? Palette.success : Palette.working, pulsing: handoff.status == "Working")
                }
                Text(handoff.reason).font(KFont.ui(13.5)).foregroundStyle(Palette.inkDim)
                if !handoff.doneWhen.isEmpty {
                    Text("Done when: \(handoff.doneWhen)").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }
}

/// Room settings, members and conversations.
struct RoomSettingsSheet: View {
    let roomID: String
    let which: RoomScreen.RoomSheet
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var who = ""
    @State private var limit = 30
    @State private var instructions = ""
    @State private var members: Set<String> = []
    @State private var conversations = ["Main", "Captions round 2"]
    @State private var newConversation = ""
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch which {
                case .settings: settings
                case .members: memberList
                case .conversations: conversationList
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .onAppear {
            guard !loaded, let room = store.rooms.first(where: { $0.id == roomID }) else { return }
            loaded = true
            name = room.name
            who = room.whoAnswers
            limit = room.turnLimit
            instructions = room.instructions
            members = Set(room.members)
        }
    }

    private var index: Int? { store.rooms.firstIndex { $0.id == roomID } }

    private var settings: some View {
        let options = ["Auto chooses who answers", "Everyone answers", "Only mentioned bots answer"] + (index.map { store.rooms[$0].members.map { "\(store.bot($0).name) answers" } } ?? [])
        return Group {
            SheetTitle(title: "Room settings")
            FieldCard(title: "Room name", text: $name, placeholder: "Room name", limit: 100)
            BotsSection {
                MenuRow(title: "Who answers by default", options: options, selection: $who)
                RowLine()
                StepperRow(title: "Turn limit", value: $limit, range: 1...1440, step: 5, unit: "min")
            }
            FieldCard(title: "Room instructions", text: $instructions, placeholder: "What this room is for", limit: 12_000, lines: 3...8)
            GoldButton(title: "Save") {
                guard let index else { return }
                store.rooms[index].name = name.isEmpty ? store.rooms[index].name : name
                store.rooms[index].whoAnswers = who
                store.rooms[index].turnLimit = limit
                store.rooms[index].instructions = instructions
                Haptics.success()
                dismiss()
            }
        }
    }

    private var memberList: some View {
        let busy = index.map { !store.rooms[$0].working.isEmpty } ?? false
        return Group {
            SheetTitle(title: "Members", detail: "A room needs at least one bot. Up to 20 can join.")
            if busy {
                HintLine(text: "This room is working. Change members when it is idle.", symbol: "hourglass", color: Palette.goldText)
            }
            VStack(spacing: 0) {
                ForEach(Array(store.bots.enumerated()), id: \.element.id) { row, bot in
                    if row > 0 { RowLine(inset: 62) }
                    Button {
                        Haptics.select()
                        if members.contains(bot.id) { members.remove(bot.id) } else if members.count < 20 { members.insert(bot.id) }
                    } label: {
                        HStack(spacing: 12) {
                            BotFace(bot: bot, size: 36)
                            Text(bot.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: members.contains(bot.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 21)).foregroundStyle(members.contains(bot.id) ? Palette.goldText : Palette.inkFaint)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    .disabled(busy)
                }
            }
            .kCard(radius: 20)
            GoldButton(title: "Save with \(members.count) bot\(members.count == 1 ? "" : "s")") {
                guard let index, !members.isEmpty else { Haptics.thud(); return }
                store.rooms[index].members = store.bots.map(\.id).filter { members.contains($0) }
                dismiss()
            }
            .disabled(busy)
        }
    }

    private var conversationList: some View {
        Group {
            SheetTitle(title: "Room conversations")
            VStack(spacing: 0) {
                ForEach(Array(conversations.enumerated()), id: \.offset) { row, title in
                    if row > 0 { RowLine() }
                    HStack {
                        Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        Spacer()
                        if row == 0 {
                            Text("Open here").font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
                        } else {
                            PillButton(title: "Delete", look: .danger) { _ = withAnimation(Motion.snappy) { conversations.remove(at: row) } }
                        }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 54)
                }
            }
            .kCard(radius: 20)
            HStack {
                TextField("New conversation", text: $newConversation).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                PillButton(title: "Create conversation") {
                    let t = newConversation.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    withAnimation(Motion.snappy) { conversations.append(t) }
                    newConversation = ""
                }
            }
            .padding(.leading, 14).padding(.trailing, 6).frame(minHeight: 56).kCard(radius: 20)
        }
    }
}
