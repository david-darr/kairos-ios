import SwiftUI

/// Every bot: search, pins, teams, reorder and the bot menu. The desktop hides the menu
/// behind right-click; here each row has a visible menu button and a long press.
struct AllBotsScreen: View {
    var startEditing = false
    let store = BotsStore.shared
    @Environment(AppRouter.self) private var router: AppRouter?
    @State private var search = ""
    @State private var editing = false
    @State private var goto: BotsRoute?
    @State private var archiving: Bot?
    @State private var deleting: Bot?
    @State private var undoBot: String?
    @State private var creating: DraftBox?
    @State private var newRoom = false
    @State private var started = false

    var body: some View {
        BotsPage("All bots", subtitle: subtitle, live: true, trailing: { headerButtons }) {
            searchField
            if store.liveMode, store.rosterLoad != .loaded {
                BotsLoadNote(state: store.rosterLoad, waiting: "Reading your bots from your desktop.") {
                    Task { await store.loadRoster() }
                }
            } else if search.count >= 2 {
                results
            } else if editing {
                reorderList
            } else {
                pinnedRow
                attention
                ForEach(store.teams) { team in
                    section(team.name, team.members.compactMap { id in store.bots.first { $0.id == id } }, team: team)
                }
                section("Other bots", store.bots.filter { store.team(of: $0.id) == nil }, team: nil)
                if store.liveMode && BotRoomLiveStore.shared.active {
                    // Paired: the desktop's rooms (BotsRoomsLive.swift). Not paired, nothing here changes.
                    BotRoomLiveList { id in goto = .room(id) }
                }
                if !store.liveMode {
                    NavigationLink(value: BotsRoute.maker) {
                        NavRow(title: "Make a bot", symbol: "plus.circle").kCard(radius: 20)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
            if let undoBot {
                HStack {
                    Text("\(store.bot(undoBot).name) is archived").font(KFont.ui(15)).foregroundStyle(Palette.ink)
                    Spacer()
                    PillButton(title: "Undo", look: .filled) {
                        withAnimation(Motion.snappy) { store.restore(undoBot); self.undoBot = nil }
                    }
                }
                .padding(12)
                .kGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationDestination(item: $goto) { BotsDestination(route: $0) }
        .sheet(item: $archiving) { bot in
            ConfirmSheet(title: "Archive \(bot.name)?", detail: "It is hidden. Its routines keep running.", confirm: "Archive") {
                withAnimation(Motion.snappy) { store.archive(bot.id); undoBot = bot.id }
                Task {
                    try? await Task.sleep(for: .seconds(8))
                    withAnimation(Motion.gentle) { if undoBot == bot.id { undoBot = nil } }
                }
            }
        }
        .sheet(item: $deleting) { bot in
            ConfirmSheet(title: "Delete \(bot.name)?", detail: "This removes its routines and notes. Its conversations stay in Chats.", confirm: "Delete bot") {
                withAnimation(Motion.snappy) {
                    store.archive(bot.id)
                    store.deleteArchived(bot.id)
                }
            }
        }
        .sheet(item: $creating) { box in
            BotCreateSheet(start: box.draft) { id in open(id) }
        }
        .sheet(isPresented: $newRoom) { NewRoomSheet { id in goto = .room(id) } }
        .onAppear {
            guard !started else { return }
            started = true
            editing = startEditing && !store.liveMode
        }
        .task(id: BotsStore.connectionKey) {
            store.followConnection()
            if store.liveMode { editing = false }
            await store.loadRoster()
        }
    }

    private var subtitle: String {
        if store.liveMode && store.rosterLoad != .loaded { return "Your desktop" }
        return store.bots.count == 1 ? "1 bot" : "\(store.bots.count) bots"
    }

    // MARK: Header

    private var headerButtons: some View {
        HStack(spacing: 8) {
            if !store.liveMode { editButton }
            moreMenu
        }
    }

    private var editButton: some View {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { editing.toggle() }
            } label: {
                Text(editing ? "Done" : "Edit").font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14).frame(minHeight: 44)
            }
            .kGlass(Capsule(), interactive: true)
            .accessibilityLabel(editing ? "Done reordering" : "Reorder bots")
    }

    private var moreMenu: some View {
            Menu {
                if !store.liveMode {
                    Button { creating = DraftBox(draft: NewBotDraft()) } label: { Label("New bot", systemImage: "plus") }
                    Button { goto = .readyMade } label: { Label("Ready-made bots", systemImage: "sparkles") }
                    Button { newRoom = true } label: { Label("New room", systemImage: "number") }
                    Divider()
                }
                Button { goto = .teamMap } label: { Label("Team map", systemImage: "map") }
                Button { goto = .automations } label: { Label("Automations", systemImage: "clock.arrow.circlepath") }
                Button { goto = .departments } label: { Label("Departments", systemImage: "building.2") }
                if !store.archived.isEmpty && !store.liveMode {
                    Button { goto = .archived } label: { Label("Archived (\(store.archived.count))", systemImage: "archivebox") }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .kGlass(Circle(), interactive: true)
            .accessibilityLabel("New and more")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.inkFaint)
            TextField("Search bots and conversations", text: $search).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkFaint).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 48)
        .kCard(radius: 16)
    }

    // MARK: Sections

    private var results: some View {
        let bots = store.bots.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.role.localizedCaseInsensitiveContains(search) }
        let chats = store.liveMode ? [] : store.bots.flatMap { bot in store.settings(bot.id).conversations.filter { $0.title.localizedCaseInsensitiveContains(search) }.map { (bot, $0) } }
        return VStack(alignment: .leading, spacing: 14) {
            if bots.isEmpty && chats.isEmpty {
                EmptyNote(text: "Nothing found.", symbol: "magnifyingglass").kCard(radius: 20)
            }
            if !bots.isEmpty { section("Bots found", bots, team: nil) }
            if !chats.isEmpty {
                BotsSection(title: "Conversations found") {
                    ForEach(Array(chats.prefix(50).enumerated()), id: \.offset) { index, item in
                        if index > 0 { RowLine(inset: 62) }
                        Button { open(item.0.id) } label: {
                            HStack(spacing: 12) {
                                BotFace(bot: item.0, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.1.title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                    Text("\(item.0.name) · \(item.1.updated)").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
            }
        }
    }

    private var pinnedRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Pinned").padding(.horizontal, 4)
            if store.pinned.isEmpty {
                HintLine(text: "Pin a bot from its menu to keep it here.")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(store.pinned, id: \.self) { id in
                        let bot = store.bot(id)
                        Button { open(id) } label: {
                            VStack(spacing: 6) {
                                BotFace(bot: bot, size: 70, showStatus: true, blinks: true)
                                    .overlay(alignment: .topTrailing) {
                                        let count = store.needsCount(id)
                                        if count > 0 { CountBadge(count: count).offset(x: 4, y: -2) }
                                    }
                                Text(bot.name).font(KFont.ui(13.5)).foregroundStyle(Palette.ink)
                            }
                            .frame(width: 78)
                        }
                        .buttonStyle(PressStyle(scale: 0.92))
                        .contextMenu { menuItems(bot) }
                        .accessibilityLabel("\(bot.name), \(bot.statusWord)")
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private var attention: some View {
        let bots = store.bots.filter { $0.status == .needsYou || $0.status == .working || store.needsCount($0.id) > 0 }
            .sorted { store.needsCount($0.id) > store.needsCount($1.id) }
        if !bots.isEmpty { section("Needs attention", bots, team: nil) }
    }

    private func section(_ title: String, _ bots: [Bot], team: BotTeam?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: title)
                if let team {
                    NavigationLink(value: BotsRoute.team(team.id)) {
                        Text(team.paused ? "Paused" : "Team").font(KFont.ui(13, .medium)).foregroundStyle(Palette.goldText).frame(minHeight: 32)
                    }
                }
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                if bots.isEmpty { EmptyNote(text: "No bots here.", symbol: "person") }
                ForEach(Array(bots.enumerated()), id: \.element.id) { index, bot in
                    if index > 0 { RowLine(inset: 74) }
                    row(bot).arrives(index)
                }
            }
            .kCard(radius: 20)
        }
    }

    private func row(_ bot: Bot) -> some View {
        HStack(spacing: 12) {
            Button { open(bot.id) } label: {
                HStack(spacing: 12) {
                    BotFace(bot: bot, size: 48, showStatus: true)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(bot.name).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                            if store.chiefs.contains(bot.id) {
                                Image(systemName: "crown.fill").font(.system(size: 11)).foregroundStyle(Palette.goldText).accessibilityLabel("Chief of Staff")
                            }
                            if store.pinned.contains(bot.id) {
                                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Palette.inkFaint).accessibilityLabel("Pinned")
                            }
                        }
                        Text(bot.role).font(KFont.ui(13.5)).foregroundStyle(Palette.inkDim).lineLimit(1)
                        Text(bot.statusWord).font(KFont.ui(12.5)).foregroundStyle(bot.statusColor)
                    }
                    Spacer(minLength: 4)
                    if store.needsCount(bot.id) > 0 { CountBadge(count: store.needsCount(bot.id)) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .contextMenu { menuItems(bot) }
            Menu { menuItems(bot) } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.inkDim)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("More for \(bot.name)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 68)
    }

    @ViewBuilder
    private func menuItems(_ bot: Bot) -> some View {
        Button { open(bot.id) } label: { Label("Open", systemImage: "bubble.left") }
        Button { goto = .botPage(bot.id) } label: { Label("Inbox and settings", systemImage: "tray") }
        Button { store.togglePin(bot.id) } label: {
            Label(store.pinned.contains(bot.id) ? "Unpin" : "Pin", systemImage: store.pinned.contains(bot.id) ? "pin.slash" : "pin")
        }
        if !store.liveMode { sampleMenuItems(bot) }
    }

    /// Menu items that only change the sample roster. Hidden while the phone shows the desktop's bots.
    @ViewBuilder
    private func sampleMenuItems(_ bot: Bot) -> some View {
        Button {
            var s = store.settings(bot.id)
            s.conversations.insert(BotConversation(title: "New conversation", updated: "now"), at: 1)
            store.save(bot.id, s)
            store.say("New conversation with \(bot.name)")
        } label: { Label("New conversation", systemImage: "square.and.pencil") }
        Button { goto = .settings(bot.id, .conversations) } label: { Label("New folder", systemImage: "folder.badge.plus") }
        if let team = store.team(of: bot.id) {
            Button { toggleChief(bot, team) } label: {
                Label(store.chiefs.contains(bot.id) ? "Remove chief" : "Make chief", systemImage: "crown")
            }
        } else {
            Button {} label: { Label("Make chief: choose a team first", systemImage: "crown") }.disabled(true)
        }
        if !bot.isKip {
            Button {
                let id = store.duplicate(bot.id)
                goto = .botPage(id)
            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button {
                store.presets.append(bot.name)
                store.say("Saved. Find it under Starting role in a new bot.")
            } label: { Label("Save as preset", systemImage: "square.on.square") }
            Divider()
            Button { archiving = bot } label: { Label("Archive", systemImage: "archivebox") }
            Button(role: .destructive) { deleting = bot } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: Reorder

    private var reorderList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HintLine(text: "Move pinned bots and the list up or down. The order is kept.", symbol: "arrow.up.arrow.down")
            BotsSection(title: "Pinned") {
                ForEach(Array(store.pinned.enumerated()), id: \.element) { index, id in
                    if index > 0 { RowLine(inset: 62) }
                    reorderRow(store.bot(id), index: index, count: store.pinned.count) { from, to in
                        withAnimation(Motion.snappy) { store.pinned.swapAt(from, to) }
                    }
                }
            }
            BotsSection(title: "All bots") {
                ForEach(Array(store.bots.enumerated()), id: \.element.id) { index, bot in
                    if index > 0 { RowLine(inset: 62) }
                    reorderRow(bot, index: index, count: store.bots.count) { from, to in
                        withAnimation(Motion.snappy) { store.bots.swapAt(from, to) }
                    }
                }
            }
        }
    }

    private func reorderRow(_ bot: Bot, index: Int, count: Int, swap: @escaping (Int, Int) -> Void) -> some View {
        HStack(spacing: 12) {
            BotFace(bot: bot, size: 36)
            Text(bot.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
            Spacer()
            moveButton("chevron.up", "Move \(bot.name) up", enabled: index > 0) { Haptics.select(); swap(index, index - 1) }
            moveButton("chevron.down", "Move \(bot.name) down", enabled: index < count - 1) { Haptics.select(); swap(index, index + 1) }
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(minHeight: 56)
    }

    private func moveButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(enabled ? Palette.ink : Palette.inkFaint.opacity(0.5))
                .frame(width: 44, height: 44).background(Palette.ink.opacity(enabled ? 0.08 : 0.03), in: Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Actions

    private func open(_ id: String) {
        Haptics.tap()
        if let router { router.push(.bot(id), on: .home) } else { goto = .botPage(id) }
    }

    private func toggleChief(_ bot: Bot, _ team: BotTeam) {
        guard let index = store.teamIndex(team.id) else { return }
        if store.chiefs.contains(bot.id) {
            store.chiefs.remove(bot.id)
            store.teams[index].chief = nil
            store.say("\(bot.name) is no longer chief")
        } else {
            if let old = team.chief { store.chiefs.remove(old) }
            store.chiefs.insert(bot.id)
            store.teams[index].chief = bot.id
            store.say("\(bot.name) is Chief of Staff for \(team.name)")
        }
    }
}
