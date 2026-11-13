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
        // Paired: only the desktop's room, never a sample one (BotsRoomsLive.swift).
        if BotRoomLiveStore.shared.active {
            BotRoomLiveScreen(roomID: roomID, openSheet: openSheet)
        } else {
            sampleBody
        }
    }

    @ViewBuilder
    private var sampleBody: some View {
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

// MARK: - Paired

/// A room on the paired desktop: its messages, who is working, the messages waiting their turn, and the composer.
/// It reads only `BotRoomLiveStore`, never the sample rooms, and polls while it is on screen and the app is in front.
struct BotRoomLiveScreen: View {
    let roomID: String
    var openSheet: RoomScreen.RoomSheet? = nil
    let live = BotRoomLiveStore.shared
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: RoomScreen.RoomSheet?
    @State private var finding = false
    @State private var query = ""
    @State private var hit = 0
    @State private var opened = false
    @FocusState private var typing: Bool

    var body: some View {
        content
            .task(id: "\(BotRoomLiveStore.connectionKey)|\(roomID)") {
                store.followConnection()
                live.followConnection()
                guard live.active else { return }
                // Its own task: the connection settling restarts this one, and that must not cut the reads short.
                await Task {
                    await live.open(roomID)
                    if store.rosterLoad != .loaded && store.rosterLoad != .loading { await store.loadRoster() }
                }.value
            }
            .task(id: "\(BotRoomLiveStore.connectionKey)|\(roomID)|\(scenePhase == .active)") {
                guard live.active, scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled, live.active, scenePhase == .active else { return }
                    await live.poll(roomID)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let room = live.room(roomID) {
            roomView(room)
        } else if live.isGone(roomID) {
            BotsPage("Room", live: true) { EmptyNote(text: "This room is not on your desktop.", symbol: "number") }
        } else {
            BotsPage("Room", live: true) {
                BotsLoadNote(state: live.roomState(roomID)) { Task { await live.open(roomID) } }
            }
        }
    }

    private func roomView(_ room: BotRoomDTO) -> some View {
        let rows = live.shownMessages(roomID)
        let mine = live.pending(roomID)
        let members = room.members ?? []
        let active = members.filter { $0.working == true || $0.waiting == true }
        let waiting = live.shownQueue(roomID)
        let matches = query.count < 2 ? [] : rows.filter { ($0.text ?? "").localizedCaseInsensitiveContains(query) }.map(\.id)
        let lastID = mine.last?.sendID ?? rows.last?.id
        let state = live.messageState(roomID)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if live.hasMore[roomID] == true {
                        Button {
                            Haptics.tap()
                            Task { await live.loadOlder(roomID) }
                        } label: {
                            Text(live.olderLoading.contains(roomID) ? "Reading earlier messages" : "Show earlier messages")
                                .font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.goldText)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(PressStyle())
                        .disabled(live.olderLoading.contains(roomID))
                    }
                    if state != .loaded {
                        BotsLoadNote(state: state, waiting: "Reading the messages on your desktop.") {
                            Task { await live.loadMessages(roomID) }
                        }
                    } else if rows.isEmpty && mine.isEmpty {
                        VStack(spacing: 10) {
                            FaceStack(ids: members.compactMap(\.botId), size: 56)
                            Text(room.name ?? "Room").font(KFont.display(30)).foregroundStyle(Palette.ink)
                            Text(live.whoAnswers(roomID)).font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                    if (live.skipped[roomID] ?? 0) > 0 {
                        HintLine(text: "Some messages on your desktop could not be read, so some may be missing here.", symbol: "info.circle")
                            .padding(.horizontal, 4)
                    }
                    ForEach(rows, id: \.id) { message in
                        BotRoomLiveBubble(message: message, roomID: roomID, pinned: room.pinnedMessageId == message.id,
                                          highlighted: matches.indices.contains(hit) && matches[hit] == message.id)
                            .id(message.id)
                            .contextMenu { menu(message, room: room) }
                    }
                    ForEach(mine) { item in
                        BotRoomLiveOutgoingBubble(item: item).id(item.sendID)
                    }
                    ForEach(active, id: \.self) { member in
                        workingRow(member)
                    }
                    ForEach(Array(waiting.enumerated()), id: \.element.id) { position, item in
                        queueRow(position, item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(Motion.snappy, value: rows.count + mine.count)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: hit) { _, value in
                if matches.indices.contains(value) { withAnimation(Motion.snappy) { proxy.scrollTo(matches[value], anchor: .center) } }
            }
            .onChange(of: lastID) { _, value in
                if let value { withAnimation(Motion.snappy) { proxy.scrollTo(value, anchor: .bottom) } }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header(room, matches: matches.count) }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer(room) }
        }
        .kScreen(glowAt: UnitPoint(x: 0.5, y: -0.05))
        .botsToast()
        .sheet(item: $sheet) { which in
            BotRoomLiveSheet(roomID: roomID, which: which)
        }
        .onAppear {
            guard !opened else { return }
            opened = true
            sheet = openSheet
        }
    }

    private func workingRow(_ member: BotRoomMemberDTO) -> some View {
        let id = member.botId ?? ""
        let name = live.name(roomID, id)
        let working = member.working == true
        return HStack(spacing: 8) {
            BotFace(bot: store.bot(id), size: 26, blinks: true)
            Text(working ? "\(name) is writing" : "\(name) is waiting").font(KFont.ui(13.5)).foregroundStyle(Palette.inkDim)
            PulsingDot(color: Palette.working, size: 6)
            Spacer()
            if working {
                PillButton(title: "Stop \(name)") { live.stop(roomID, botID: id) }
                    .disabled(live.busy.contains("stop|\(roomID)|\(id)"))
            }
        }
        .padding(10)
        .kCard(radius: 18)
    }

    private func queueRow(_ position: Int, _ item: BotRmQueueItemDTO) -> some View {
        HStack {
            Text("\(position + 1). \(item.text ?? "") (waiting)").font(KFont.ui(14)).foregroundStyle(Palette.inkDim).lineLimit(1)
            Spacer()
            if item.state == "pending" {
                PillButton(title: "Cancel") { live.cancelQueued(roomID, item) }
                    .disabled(live.busy.contains("queue|\(item.id)"))
            } else {
                Text("Starting").font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(10)
        .kCard(radius: 16)
    }

    @ViewBuilder
    private func menu(_ message: BotRmMessageDTO, room: BotRoomDTO) -> some View {
        if message.role != "system" {
            Button { live.pin(roomID, messageID: room.pinnedMessageId == message.id ? nil : message.id) } label: {
                Label(room.pinnedMessageId == message.id ? "Unpin" : "Pin", systemImage: "pin")
            }
            .disabled(live.busy.contains("pin|\(roomID)"))
        }
        Button {
            UIPasteboard.general.string = message.text ?? ""
            store.say("Copied")
        } label: { Label("Copy", systemImage: "doc.on.doc") }
        if message.role == "bot", let botID = message.botId {
            Button {
                // The mention goes in front; nothing already typed is lost.
                live.drafts[roomID] = "@\(live.name(roomID, botID)) " + (live.drafts[roomID] ?? "")
                typing = true
            } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        }
    }

    // MARK: Header

    private func header(_ room: BotRoomDTO, matches: Int) -> some View {
        let members = room.members ?? []
        let held = members.filter { $0.held == true }
        let running = room.working == true || members.contains { $0.working == true }
        let name = room.name ?? "Room"
        return VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                GlassIconButton(symbol: "chevron.left", label: "Back") { dismiss() }
                Spacer()
                Button {
                    Haptics.tap()
                    sheet = .settings
                } label: {
                    VStack(spacing: 4) {
                        FaceStack(ids: members.compactMap(\.botId), size: 34)
                        HStack(spacing: 4) {
                            Image(systemName: "number").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.goldText)
                            Text(name).font(KFont.ui(14.5, .medium)).lineLimit(1)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.inkFaint)
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .kGlass(Capsule())
                    }
                }
                .buttonStyle(PressStyle(scale: 0.95))
                .accessibilityLabel("\(name). Room settings")
                Spacer()
                Menu {
                    Button { sheet = .members } label: { Label("Members", systemImage: "person.2") }
                    Button { withAnimation(Motion.snappy) { finding.toggle() } } label: { Label("Find in room", systemImage: "magnifyingglass") }
                    Button { sheet = .conversations } label: { Label("Conversations", systemImage: "bubble.left.and.bubble.right") }
                    Button { sheet = .settings } label: { Label("Room settings", systemImage: "slider.horizontal.3") }
                    if running {
                        Button(role: .destructive) { live.stop(roomID, botID: nil) } label: { Label("Stop all", systemImage: "stop.circle") }
                            .disabled(live.busy.contains("stop|\(roomID)|*"))
                    }
                    ShareLink(item: exportText(room)) { Label("Export loaded messages", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("Room menu")
            }
            if finding { findBar(matches: matches) }
            if live.trouble.contains(roomID) {
                HintLine(text: "Your desktop is not answering. This room may be out of date.", symbol: "exclamationmark.triangle", color: Palette.goldText)
                    .padding(.horizontal, 4)
            }
            if room.archivedAt != nil {
                HintLine(text: "This room is archived on your desktop.", symbol: "archivebox")
                    .padding(.horizontal, 4)
            } else if room.setupState == "pending" {
                HintLine(text: "Finish setting up this room in Kairos on your desktop. Then you can write here.", symbol: "info.circle", color: Palette.goldText)
                    .padding(.horizontal, 4)
            }
            if !held.isEmpty {
                HStack {
                    Text("Held: \(held.map { live.name(roomID, $0.botId ?? "") }.joined(separator: ", "))").font(KFont.ui(14)).foregroundStyle(Palette.ink)
                    Spacer()
                    ForEach(held, id: \.self) { member in
                        resumeButton(member.botId ?? "")
                    }
                }
                .padding(10)
                .kCard(radius: 16, raised: true)
            }
            if let pinnedID = room.pinnedMessageId { pinnedBar(pinnedID) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background { HeaderFade() }
        .animation(Motion.snappy, value: finding)
    }

    private func findBar(matches: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.inkFaint)
            TextField("Find in loaded messages", text: $query).font(KFont.ui(16)).foregroundStyle(Palette.ink)
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

    private func pinnedBar(_ pinnedID: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill").font(.system(size: 12)).foregroundStyle(Palette.goldText)
            Text(live.shownMessages(roomID).first { $0.id == pinnedID }?.text ?? "A message further up is pinned.")
                .font(KFont.ui(13.5)).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer()
            Button { live.pin(roomID, messageID: nil) } label: {
                Text("Unpin").font(KFont.ui(13.5, .semibold)).foregroundStyle(Palette.goldText).frame(minHeight: 36)
            }
            .disabled(live.busy.contains("pin|\(roomID)"))
        }
        .padding(.horizontal, 12)
        .kGlass(Capsule())
    }

    private func resumeButton(_ id: String) -> some View {
        PillButton(title: "Resume \(live.name(roomID, id))") { live.resume(roomID, botID: id) }
            .disabled(live.busy.contains("hold|\(roomID)|\(id)"))
    }

    // MARK: Composer

    private var draft: Binding<String> {
        Binding(get: { live.drafts[roomID] ?? "" }, set: { live.drafts[roomID] = $0 })
    }

    private func composer(_ room: BotRoomDTO) -> some View {
        let typed = live.drafts[roomID] ?? ""
        let mention = currentMention(typed)
        let names = (room.members ?? []).compactMap(\.botId).map { live.name(roomID, $0) }
        let suggestions: [String] = mention.map { word in
            (["everyone"] + names).filter { word.isEmpty || $0.lowercased().hasPrefix(word.lowercased()) }
        } ?? []
        let ready = live.canSend(roomID)
        let running = room.working == true
        let has = ready && !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                TextField("Message the room, @ to mention", text: draft, axis: .vertical)
                    .font(KFont.ui(16.5)).foregroundStyle(Palette.ink)
                    .lineLimit(1...5).focused($typing)
                    .padding(.vertical, 12).padding(.leading, 16)
                Button {
                    if typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        typing = true
                    } else {
                        Haptics.tap()
                        live.send(roomID)
                    }
                } label: {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(has ? Palette.onGold : Palette.inkFaint)
                        .frame(width: 34, height: 34)
                        .background(has ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Circle())
                        .frame(width: 44, height: 46)
                }
                .buttonStyle(PressStyle(scale: 0.88))
                .disabled(!ready)
                .accessibilityLabel("Send")
                .padding(.trailing, 4)
            }
            .kGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
            Text(running ? "Messages wait their turn." : live.whoAnswers(roomID))
                .font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
        }
        .padding(.bottom, 8)
        .animation(Motion.snappy, value: suggestions)
    }

    private func currentMention(_ text: String) -> String? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last, last.hasPrefix("@") else { return nil }
        return String(last.dropFirst())
    }

    private func complete(_ name: String) {
        var words = (live.drafts[roomID] ?? "").split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if !words.isEmpty { words.removeLast() }
        words.append("@\(name) ")
        live.drafts[roomID] = words.joined(separator: " ")
    }

    /// What is loaded on this iPhone, as text.
    private func exportText(_ room: BotRoomDTO) -> String {
        let lines = live.shownMessages(roomID).map { message -> String in
            let who: String
            switch message.role ?? "" {
            case "person": who = "You"
            case "system": who = "Room"
            default: who = live.name(roomID, message.botId ?? "")
            }
            return "**\(who)** (\(BotRoomLiveBubble.time(message))): \(message.text ?? "")"
        }
        return (["# \(room.name ?? "Room")"] + lines).joined(separator: "\n\n")
    }
}

/// One desktop message: yours on the right in gold, each bot's with its face and name, a room line in the middle.
struct BotRoomLiveBubble: View {
    let message: BotRmMessageDTO
    let roomID: String
    var pinned = false
    var highlighted = false
    let store = BotsStore.shared
    let live = BotRoomLiveStore.shared

    static func time(_ message: BotRmMessageDTO) -> String { ChatFormat.listTime(message.createdAt?.date) }

    var body: some View {
        switch message.role ?? "" {
        case "person": person
        case "system": line
        default: bot
        }
    }

    private var person: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.text ?? "")
                .font(KFont.ui(16.5)).foregroundStyle(Palette.onGold)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Palette.gold, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.ink, lineWidth: highlighted ? 2 : 0))
        }
    }

    private var line: some View {
        Text(message.text ?? "")
            .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(highlighted ? Palette.ink : Palette.inkFaint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }

    private var bot: some View {
        let id = message.botId ?? ""
        let partial = message.meta?["partial"]?.bool == true
        return HStack(alignment: .bottom, spacing: 8) {
            BotFace(bot: store.bot(id), size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(live.name(roomID, id)).font(KFont.ui(12.5, .semibold)).foregroundStyle(Palette.inkDim)
                    if pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Palette.goldText) }
                    Text(Self.time(message)).font(KFont.ui(12)).foregroundStyle(Palette.inkFaint)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.text ?? "").font(KFont.ui(16.5)).foregroundStyle(Palette.ink)
                    if partial {
                        Text("Stopped part way").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(highlighted ? Palette.gold : Palette.line, lineWidth: highlighted ? 2 : 1))
            }
            Spacer(minLength: 40)
        }
    }
}

/// One of this iPhone's messages the desktop's list does not show yet, with where it stands.
struct BotRoomLiveOutgoingBubble: View {
    let item: BotRmOutgoing
    let live = BotRoomLiveStore.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Spacer(minLength: 60)
                Text(item.text)
                    .font(KFont.ui(16.5)).foregroundStyle(Palette.onGold)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Palette.gold.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            Text(words)
                .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(problem ? Palette.goldText : Palette.inkFaint)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var words: String {
        switch item.state {
        case .sending: return "Sending"
        case .checking: return "Not confirmed yet. Checking your desktop."
        case .unchecked: return "Not confirmed yet. This iPhone could not reach your desktop to check."
        case .notSent(let reason), .refused(let reason): return "Not sent. " + reason
        }
    }

    private var problem: Bool {
        switch item.state {
        case .sending, .checking: return false
        default: return true
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch item.state {
        case .sending, .checking:
            EmptyView()
        case .unchecked:
            PillButton(title: "Check again", symbol: "arrow.clockwise") { live.sendAgain(item.sendID) }
        case .notSent:
            // Only Send again: it reuses the send id, so the desktop stores it once even if the first one lands late.
            // A copy pasted into the composer would be a new message.
            PillButton(title: "Send again", look: .filled) { live.sendAgain(item.sendID) }
        case .refused:
            HStack(spacing: 8) {
                PillButton(title: "Edit") { live.edit(item.sendID) }
                PillButton(title: "Send again", look: .filled) { live.sendAgain(item.sendID) }
            }
        }
    }
}

/// Room settings, members and conversations on the paired desktop. Only what changed is sent, with the room's
/// revision; the sheet stays up while a save is on its way.
struct BotRoomLiveSheet: View {
    let roomID: String
    let which: RoomScreen.RoomSheet
    let live = BotRoomLiveStore.shared
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var form: BotRoomLiveForm?
    @State private var base: BotRoomLiveForm?
    @State private var revision: Int?
    /// The form and its base as last sent, to compare with the desktop after a lost answer.
    @State private var sent: BotRoomLiveForm?
    @State private var sentBase: BotRoomLiveForm?
    @State private var saving = false
    @State private var mustCheck = false
    /// The room changed on the desktop and could not be read again: read it before the next save.
    @State private var needsRead = false
    /// The form the desktop refused: the same save would be refused again, so Save waits for a change.
    @State private var refusedForm: BotRoomLiveForm?
    @State private var note: String?
    @State private var newTitle = ""
    @State private var creating = false
    @State private var deleting: BotRmThreadDTO?
    @State private var renaming: BotRmThreadDTO?
    @State private var renameText = ""
    /// The conversation a too-long name was typed for: renaming it again starts from that text.
    @State private var renameKept: String?

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
        .interactiveDismissDisabled(saving || creating || mustCheck)
        .onAppear {
            if form == nil, let room = live.room(roomID) { take(room) }
        }
        .task {
            if which == .conversations { await live.loadThreads(roomID) }
        }
        .sheet(item: $deleting) { thread in
            ConfirmSheet(title: "Delete \(title(thread))?",
                         detail: "The conversation and every message in it are deleted from your desktop. This cannot be undone.",
                         confirm: "Delete conversation") {
                live.deleteThread(roomID, thread.id)
            }
        }
        .alert("Rename conversation", isPresented: renameShown) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let thread = renaming {
                    let clean = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if BotRoomLiveMap.length(clean) <= 100 {
                        renameKept = nil
                        live.renameThread(roomID, thread.id, title: renameText)
                    } else {
                        // Nothing is sent and nothing typed is lost: renaming this conversation again starts from it.
                        renameKept = thread.id
                        note = "A conversation name is at most 100 characters. Nothing was renamed; rename it again to shorten what you typed."
                    }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil; renameKept = nil }
        }
    }

    private var renameShown: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    // MARK: Form

    private func take(_ room: BotRoomDTO) {
        let read = BotRoomLiveForm(room)
        form = read
        base = read
        revision = room.revision
    }

    /// The desktop changed: what was typed stays, the rest is the desktop's, and the next save uses its revision.
    private func rebase(_ room: BotRoomDTO) {
        guard let form, let base else { take(room); return }
        let desk = BotRoomLiveForm(room)
        self.form = form.rebased(from: base, onto: desk)
        self.base = desk
        revision = room.revision
    }

    private func field<T>(_ path: WritableKeyPath<BotRoomLiveForm, T>) -> Binding<T> {
        Binding(get: { (form ?? BotRoomLiveForm.blank)[keyPath: path] }, set: { form?[keyPath: path] = $0 })
    }

    private func save() {
        guard let form, let base, !saving, !mustCheck, !needsRead else { return }
        saving = true
        note = nil
        refusedForm = nil
        sent = form
        sentBase = base
        Task {
            let (outcome, read) = await live.save(roomID, form: form, base: base, revision: revision)
            saving = false
            switch outcome {
            case .done(let text):
                Haptics.success()
                store.say(text)
                dismiss()
            case .refused(let text):
                // The desktop's own reason. Sending the same again gets the same answer, so Save waits for a change.
                refusedForm = form
                note = text
            case .busy(let text):
                // Nothing saved; the members stay locked until the room is idle, then the same save can go.
                note = text
            case .changed:
                // Rebase on the room the store just read, never on an older copy, so the next save has its revision.
                if let read {
                    rebase(read)
                    note = "This room changed on your desktop. What you typed is still here; check it and save again."
                } else {
                    needsRead = true
                    note = "This room changed on your desktop, and it could not be read again. What you typed is still here; read the room again before saving."
                }
            case .unsure(let text, let checked):
                if checked, let read { rebase(read) }
                mustCheck = !checked
                note = text
            }
        }
    }

    /// After a 409 for a stale revision that could not be followed by a read: read the room and rebase on it.
    private func readAgain() {
        guard !saving else { return }
        saving = true
        Task {
            let room = await live.loadRoom(roomID, force: true)
            saving = false
            guard let room else {
                note = "Your desktop did not answer. What you typed is still here; read the room again in a moment."
                return
            }
            needsRead = false
            rebase(room)
            note = "This room now shows what your desktop has. What you typed is still here; check it and save again."
        }
    }

    /// After a lost answer that could not be checked: read the room and compare it with what was sent.
    private func checkAgain() {
        guard !saving else { return }
        saving = true
        Task {
            let room = await live.loadRoom(roomID, force: true)
            saving = false
            guard let room else {
                note = "Your desktop still did not answer. Try again in a moment."
                return
            }
            mustCheck = false
            if let sent, let sentBase, sent.landed(in: room, from: sentBase) {
                if form == sent {
                    Haptics.success()
                    store.say("Saved")
                    dismiss()
                    return
                }
                rebase(room)
                note = "Your first changes were saved. Your newer ones are still here; save again to send them."
                return
            }
            rebase(room)
            note = "Your desktop does not have these changes. What you typed is still here; save again to send it."
        }
    }

    @ViewBuilder
    private func saveButton(_ title: String, disabled: Bool) -> some View {
        if mustCheck {
            GoldButton(title: saving ? "Checking" : "Check again") { checkAgain() }
                .disabled(saving)
        } else if needsRead {
            GoldButton(title: saving ? "Reading" : "Read the room again") { readAgain() }
                .disabled(saving)
        } else {
            let blocked = disabled || (refusedForm != nil && refusedForm == form)
            GoldButton(title: saving ? "Saving" : title) { save() }
                .disabled(saving || blocked)
                .opacity(blocked ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private var noteLine: some View {
        if let note {
            HintLine(text: note, symbol: "info.circle", color: Palette.goldText)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Settings

    private var options: [(label: String, responder: BotRmResponder)] {
        let fixed: [(label: String, responder: BotRmResponder)] = [
            (label: "Auto chooses who answers", responder: .auto(fallback: nil)),
            (label: "Everyone answers", responder: .everyone),
            (label: "Only mentioned bots answer", responder: .mentions),
        ]
        // Two members with the same name get a number each, so a pick always maps back to the right bot.
        var seen: [String: Int] = [:]
        let names = (base?.members ?? []).map { live.name(roomID, $0) }
        let members: [(label: String, responder: BotRmResponder)] = zip(base?.members ?? [], names).map { pair -> (label: String, responder: BotRmResponder) in
            let (id, name) = pair
            let shared = names.filter { $0 == name }.count > 1
            seen[name, default: 0] += 1
            let shown = shared ? "\(name) (\(seen[name] ?? 1))" : name
            return (label: "\(shown) answers", responder: BotRmResponder.member(id))
        }
        return fixed + members
    }

    private var responderLabel: Binding<String> {
        Binding(
            get: {
                let current = form?.responder ?? .mentions
                if let found = options.first(where: { $0.responder.sameChoice(current) }) { return found.label }
                return BotRoomLiveMap.whoAnswers(current) { live.name(roomID, $0) }
            },
            set: { label in
                guard let pick = options.first(where: { $0.label == label })?.responder, let current = form?.responder,
                      !pick.sameChoice(current) else { return }
                form?.responder = pick
            }
        )
    }

    @ViewBuilder
    private var settings: some View {
        SheetTitle(title: "Room settings")
        if let form {
            Group {
                FieldCard(title: "Room name", text: field(\.name), placeholder: "Room name", limit: 100)
                BotsSection {
                    MenuRow(title: "Who answers by default", options: options.map(\.label), selection: responderLabel)
                    RowLine()
                    StepperRow(title: "Turn limit", value: field(\.turnLimit), range: 1...1440, step: 5, unit: "min")
                }
                FieldCard(title: "Room instructions", text: field(\.bulletin), placeholder: "What this room is for", limit: 12_000, lines: 3...8)
            }
            .disabled(saving)
            noteLine
            saveButton("Save", disabled: settingsInvalid(form))
        } else {
            BotsLoadNote(state: live.roomState(roomID)) { reload() }
        }
    }

    private func settingsInvalid(_ form: BotRoomLiveForm) -> Bool {
        // Counted as the desktop counts (code points), on what is sent (trimmed).
        let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let bulletin = form.bulletin.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || BotRoomLiveMap.length(name) > 100 || BotRoomLiveMap.length(bulletin) > 12_000
    }

    private func reload() {
        Task {
            if let room = await live.loadRoom(roomID) { take(room) }
        }
    }

    // MARK: Members

    /// The roster, and any member the roster does not list (the desktop keeps a member that was hidden since).
    private var candidates: [String] {
        let roster = store.bots.map(\.id)
        return roster + (base?.members ?? []).filter { !roster.contains($0) }
    }

    private func toggle(_ id: String) {
        guard var form else { return }
        Haptics.select()
        if let index = form.members.firstIndex(of: id) {
            form.members.remove(at: index)
        } else if form.members.count < 20 {
            form.members.append(id)
        } else {
            note = "A room holds at most 20 bots."
            return
        }
        self.form = form
    }

    @ViewBuilder
    private var memberList: some View {
        SheetTitle(title: "Members", detail: "A room needs at least one bot. Up to 20 can join.")
        if live.locked(roomID) {
            HintLine(text: "This room is working. Change members when it is idle.", symbol: "hourglass", color: Palette.goldText)
        }
        if let form {
            VStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element) { row, id in
                    if row > 0 { RowLine(inset: 62) }
                    memberRow(id, chosen: form.members.contains(id))
                }
            }
            .kCard(radius: 20)
            noteLine
            saveButton("Save with \(form.members.count) bot\(form.members.count == 1 ? "" : "s")",
                       disabled: live.locked(roomID) || form.members.isEmpty)
        } else {
            BotsLoadNote(state: live.roomState(roomID)) { reload() }
        }
    }

    private func memberRow(_ id: String, chosen: Bool) -> some View {
        Button { toggle(id) } label: {
            HStack(spacing: 12) {
                BotFace(bot: store.bot(id), size: 36)
                Text(live.name(roomID, id)).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21)).foregroundStyle(chosen ? Palette.goldText : Palette.inkFaint)
            }
            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .disabled(live.locked(roomID) || saving)
        .accessibilityLabel("\(live.name(roomID, id)), \(chosen ? "in the room" : "not in the room")")
    }

    // MARK: Conversations

    private func title(_ thread: BotRmThreadDTO) -> String {
        if let title = thread.title, !title.isEmpty { return title }
        return live.shownThreads(roomID).first?.id == thread.id ? "Main" : "Untitled"
    }

    private func create() {
        guard !creating else { return }
        let typed = newTitle
        guard BotRoomLiveMap.length(typed.trimmingCharacters(in: .whitespacesAndNewlines)) <= 100 else {
            note = "A conversation name is at most 100 characters."
            return
        }
        creating = true
        note = nil
        Task {
            let outcome = await live.createThread(roomID, title: typed)
            creating = false
            switch outcome {
            case .done(let text):
                newTitle = ""
                store.say(text)
            case .refused(let text), .changed(let text), .busy(let text), .unsure(let text, _):
                note = text
            }
        }
    }

    @ViewBuilder
    private var conversationList: some View {
        SheetTitle(title: "Room conversations")
        if live.shownThreads(roomID).isEmpty {
            BotsLoadNote(state: live.threadsLoad[roomID] ?? .loading) { Task { await live.loadThreads(roomID) } }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(live.shownThreads(roomID).enumerated()), id: \.element.id) { row, thread in
                    if row > 0 { RowLine() }
                    threadRow(thread)
                }
            }
            .kCard(radius: 20)
        }
        HStack {
            TextField("New conversation", text: $newTitle).font(KFont.ui(16)).foregroundStyle(Palette.ink)
            PillButton(title: creating ? "Creating" : "Create conversation") { create() }
                .disabled(creating)
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(minHeight: 56).kCard(radius: 20)
        noteLine
    }

    private func threadRow(_ thread: BotRmThreadDTO) -> some View {
        let list = live.shownThreads(roomID)
        let shown = live.threadOf[roomID] ?? list.first?.id
        return HStack {
            Button {
                Haptics.tap()
                live.openThread(roomID, thread.id)
                dismiss()
            } label: {
                Text(title(thread)).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            // Opening a conversation closes the sheet: not while a create is on its way, so its outcome is seen.
            .disabled(creating)
            if thread.id == shown {
                Text("Open here").font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
            }
            if thread.working == true {
                StateTag(text: "Working", color: Palette.working, pulsing: true)
            } else if list.count > 1 {
                PillButton(title: "Delete", look: .danger) { deleting = thread }
                    .disabled(live.busy.contains("thread|\(thread.id)"))
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 54)
        .contextMenu {
            Button {
                if renameKept != thread.id { renameText = thread.title ?? "" }
                renaming = thread
            } label: { Label("Rename", systemImage: "pencil") }
        }
    }
}
