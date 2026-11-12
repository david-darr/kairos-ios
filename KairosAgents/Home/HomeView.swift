import SwiftUI

/// Home feels like Messages: a slim glance row, pinned bots as big round faces,
/// then one list of every conversation. A bot waiting on you is an unread conversation.
/// Everything here comes from `ChatStore`: sample data until a desktop is paired, the desktop after.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @Environment(\.scenePhase) private var scenePhase

    private var store: ChatStore { ChatStore.shared }
    private var connection: Connection { Connection.shared }

    @State private var showConnection = false
    @State private var renaming: Conversation?
    @State private var renameText = ""
    @State private var deleting: Conversation?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let banner = bannerText {
                    connectionBanner(banner).arrives(0)
                }
                if !store.glance.isEmpty {
                    glanceRow.arrives(0)
                }

                if !store.pinnedBots.isEmpty {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(store.pinnedBots.enumerated()), id: \.element.id) { index, bot in
                            Button {
                                Haptics.tap()
                                router.push(.bot(bot.id), on: .home)
                            } label: {
                                VStack(spacing: 7) {
                                    BotFace(bot: bot, size: 82, showStatus: true, blinks: true)
                                    Text(bot.name)
                                        .font(KFont.ui(13.5, relativeTo: .footnote))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PressStyle(scale: 0.92))
                            .accessibilityLabel("\(bot.name), \(statusWord(bot.status))")
                            .arrives(index + 1)
                        }
                    }
                    .padding(.top, 2)
                }

                if store.conversations.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.conversations.enumerated()), id: \.element.id) { index, conversation in
                            Button {
                                router.open(conversation)
                            } label: {
                                ConversationRow(conversation: conversation, bot: botFor(conversation))
                            }
                            .buttonStyle(PressStyle(scale: 0.985))
                            .contextMenu { menu(for: conversation) }
                            .arrives(min(index, 12) + 4)
                        }
                    }
                }

                if store.isSample && store.homeLoaded {
                    Button { showConnection = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "desktopcomputer").font(.system(size: 13, weight: .medium))
                            Text("This is sample data. Pair your desktop to see your own.")
                                .font(KFont.ui(13.5, relativeTo: .footnote))
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .animation(Motion.snappy, value: store.conversations)
            .animation(Motion.snappy, value: bannerText)
        }
        .scrollIndicators(.hidden)
        .shrinksBar(chrome)
        .refreshable {
            if !store.isSample { await connection.checkSession() }
            await store.refreshHome()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TabHeader(title: "Home") {
                GlassIconButton(symbol: "magnifyingglass", label: "Search") { router.sheet = .search }
                Button { router.sheet = .you } label: {
                    Text(initial)
                        .font(KFont.ui(16, .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .background(Palette.surface2, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.gold, lineWidth: 2))
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .accessibilityLabel("You, settings and accounts")
            }
        }
        .kScreen()
        .sheet(isPresented: $showConnection) {
            NavigationStack { ConnectionScreen() }
                .kSheet()
        }
        .alert("Rename chat", isPresented: renamingShown) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let chat = renaming { store.modelChat(chat.id).rename(renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete this chat?", isPresented: deletingShown, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let chat = deleting else { return }
                deleting = nil
                Task {
                    let state = store.modelChat(chat.id)
                    if await state.delete() {
                        chrome.say("Chat deleted")
                    } else if let why = state.notice {
                        chrome.say(why)
                    }
                }
            }
            Button("Keep it", role: .cancel) { deleting = nil }
        } message: {
            Text("The chat and its messages are removed from your desktop. This cannot be undone.")
        }
        .task {
            connection.start()
            if !store.homeLoaded { await store.refreshHome() }
            chrome.liveWork = store.liveWork
            // The slim poll: only while Home is on screen.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                await store.poll()
            }
        }
        .onChange(of: store.liveWork) { chrome.liveWork = store.liveWork }
        .onChange(of: store.generation) {
            // Paired or unpaired: what was open belongs to the other data.
            router.paths[.home] = []
            chrome.liveWork = store.liveWork
            Task { await store.refreshHome() }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            connection.wake()
            Task { await store.refreshHome() }
        }
    }

    private var renamingShown: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletingShown: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var initial: String {
        let name = connection.desktop?.username ?? ""
        return store.isSample || name.isEmpty ? "Y" : String(name.prefix(1)).uppercased()
    }

    private func botFor(_ conversation: Conversation) -> Bot? {
        if case .bot(let id) = conversation.kind { return store.bot(id) }
        return nil
    }

    // MARK: Connection

    /// One line when the desktop is not simply connected, or Home could not be read.
    private var bannerText: String? {
        if store.isSample { return nil }
        switch connection.state {
        case .connecting: return store.homeLoaded ? nil : "Connecting to your desktop"
        case .offline(let reason): return reason
        case .signedOut: return "This iPhone is no longer paired. Tap to pair it again."
        case .connected: return store.homeError
        case .sample: return nil
        }
    }

    private func connectionBanner(_ text: String) -> some View {
        Button { showConnection = true } label: {
            HStack(spacing: 10) {
                if connection.state == .connecting {
                    PulsingDot(color: Palette.working, size: 7).frame(width: 14)
                } else {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.goldText)
                }
                Text(text)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18, raised: true)
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .accessibilityHint("Opens your desktop connection")
    }

    @ViewBuilder
    private var emptyState: some View {
        if !store.isSample && !store.homeLoaded && store.homeError == nil {
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in SkeletonRow() }
            }
            .accessibilityLabel("Loading your conversations")
        } else if store.homeLoaded {
            VStack(spacing: 8) {
                Text("Your next conversation starts here.")
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.inkDim)
                Text("Tap + to start a chat, or tap a bot above.")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    @ViewBuilder
    private func menu(for conversation: Conversation) -> some View {
        if case .model = conversation.kind {
            Button("Open", systemImage: "bubble.left") { router.open(conversation) }
            Button("Rename", systemImage: "pencil") {
                renameText = conversation.title.replacingOccurrences(of: "★ ", with: "")
                renaming = conversation
            }
            Button(conversation.title.hasPrefix("★ ") ? "Remove star" : "Star", systemImage: "star") {
                let chat = store.modelChat(conversation.id)
                Task {
                    await chat.load()
                    chat.toggleStar()
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = conversation }
        } else {
            Button("Open", systemImage: "bubble.left") { router.open(conversation) }
        }
    }

    // MARK: Glance

    private var glanceRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if !store.glance.usage.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(store.glance.usage) { item in
                            HStack(spacing: 6) {
                                UsageRing(percent: item.percent)
                                Text(item.provider).foregroundStyle(Palette.ink)
                                Text("\(item.percent)%").foregroundStyle(Palette.inkFaint)
                            }
                        }
                    }
                    .glancePill()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Model usage: " + store.glance.usage.map { "\($0.provider) \($0.percent) percent" }.joined(separator: ", "))
                }

                if let event = store.glance.nextEvent {
                    Button { router.open(.calendar) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.goldText)
                            Text(event).foregroundStyle(Palette.ink)
                        }
                        .glancePill()
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Next event: \(event). Opens Calendar")
                }

                if !store.isSample && store.glance.needsYou > 0 {
                    HStack(spacing: 7) {
                        Circle().fill(Palette.gold).frame(width: 8, height: 8)
                        Text("\(store.glance.needsYou) need you").foregroundStyle(Palette.ink)
                    }
                    .glancePill()
                }
                if !store.isSample && store.glance.running > 0 {
                    HStack(spacing: 7) {
                        PulsingDot(color: Palette.working, size: 6).frame(width: 10)
                        Text("\(store.glance.running) running").foregroundStyle(Palette.ink)
                    }
                    .glancePill()
                }
            }
            .font(KFont.ui(13.5, relativeTo: .footnote))
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func statusWord(_ status: BotStatus) -> String {
        switch status {
        case .online: "ready"
        case .working: "working"
        case .needsYou: "waiting for you"
        case .offline: "asleep"
        }
    }
}

private extension View {
    func glancePill() -> some View {
        padding(.horizontal, 13)
            .frame(height: 36)
            .kGlass(Capsule())
    }
}

struct UsageRing: View {
    let percent: Int

    var body: some View {
        ZStack {
            Circle().stroke(Palette.ink.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, percent))) / 100)
                .stroke(percent > 80 ? Palette.danger : Palette.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

/// A grey stand-in for a conversation row while the first read is on its way.
private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Palette.surfaceRaised).frame(width: 46, height: 46).frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Palette.surfaceRaised).frame(width: 130, height: 12)
                Capsule().fill(Palette.surface).frame(width: 210, height: 10)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    /// The bot's face for a bot conversation. nil draws the model mark.
    var bot: Bot? = nil

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.title)
                        .font(KFont.ui(16.5, conversation.unread ? .semibold : .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(conversation.time)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(conversation.unread ? Palette.goldText : Palette.inkFaint)
                }
                HStack(spacing: 6) {
                    if conversation.working { PulsingDot(color: Palette.working, size: 6) .padding(.horizontal, 2) }
                    Text(conversation.preview.isEmpty ? " " : conversation.preview)
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(conversation.unread ? Palette.ink.opacity(0.9) : Palette.inkFaint)
                        .lineLimit(1)
                }
            }
            if conversation.unread {
                Circle().fill(Palette.gold).frame(width: 10, height: 10)
                    .accessibilityLabel("Waiting for you")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 74) }
    }

    @ViewBuilder
    private var avatar: some View {
        if let bot {
            BotFace(bot: bot, size: 58)
        } else {
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.inkDim)
                .frame(width: 46, height: 46)
                .background(Palette.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
                .frame(width: 58, height: 58)
        }
    }
}
