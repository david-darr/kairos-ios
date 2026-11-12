import SwiftUI

/// A bot's own page: Inbox and Settings. Opened by tapping the bot's face in its chat,
/// as a full-screen cover with its own navigation stack.
struct BotPanelView: View {
    enum Tab: String, CaseIterable { case inbox = "Inbox", settings = "Settings" }

    let bot: Bot
    @State var tab: Tab

    var body: some View {
        NavigationStack {
            BotPanelRoot(botID: bot.id, startTab: tab, presented: true)
                .botsDestinations()
        }
        .tint(Palette.gold)
    }
}

/// The panel's content. Pushed from All bots too, where it has a back arrow instead of a close.
struct BotPanelRoot: View {
    let botID: String
    var startTab: BotPanelView.Tab = .inbox
    var presented = false

    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router: AppRouter?
    @State private var tab: BotPanelView.Tab = .inbox
    @State private var started = false
    @State private var goto: BotsRoute?
    @State private var confirmArchive = false

    var body: some View {
        let bot = store.bot(botID)
        ScrollView {
            VStack(spacing: 16) {
                hero(bot)
                GlassSwitch(items: BotPanelView.Tab.allCases, selection: $tab) { $0.rawValue }
                    .fixedSize()
                Group {
                    if tab == .inbox {
                        BotInboxSection(botID: botID)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    } else {
                        BotSettingsList(botID: botID)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { header(bot) }
        .background { Ground(glowAt: UnitPoint(x: 0.5, y: 0.12)) }
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.snappy, value: tab)
        .navigationDestination(item: $goto) { BotsDestination(route: $0) }
        .sheet(isPresented: $confirmArchive) {
            ConfirmSheet(title: "Archive \(bot.name)?", detail: "It is hidden from your bots. Its routines keep running, and you can bring it back from Archived bots.", confirm: "Archive") {
                store.archive(botID)
                dismiss()
            }
        }
        .botsToast()
        .onAppear {
            guard !started else { return }
            started = true
            tab = startTab
        }
        .task(id: BotsStore.connectionKey) {
            store.followConnection()
            guard store.liveMode else { return }
            await store.loadDetail(botID)
            await store.loadCards(botID)
            if store.rosterLoad != .loaded { await store.loadRoster() }
        }
    }

    private func hero(_ bot: Bot) -> some View {
        let settings = store.settings(botID)
        return VStack(spacing: 8) {
            BotFace(bot: bot, size: 132, blinks: true)
            Text(bot.name).font(KFont.display(40)).foregroundStyle(Palette.ink)
            Text(store.liveMode ? "\(bot.role) · \(bot.model) · \(bot.approval)" : "\(bot.role) · \(settings.model) · \(settings.approval.longTitle)")
                .font(KFont.ui(14, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                StateTag(text: bot.statusWord, color: bot.statusColor, pulsing: bot.status == .working)
                if let team = store.team(of: botID) {
                    Text("·").foregroundStyle(Palette.inkFaint)
                    Button {
                        Haptics.tap()
                        goto = .team(team.id)
                    } label: {
                        Text(team.name).font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.goldText)
                            .frame(minHeight: 30)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            if store.liveMode {
                BotsLoadNote(state: store.detailLoad[botID] ?? .idle, waiting: "Reading this bot from your desktop.") {
                    Task { await store.loadDetail(botID) }
                }
                .padding(.top, 6)
            }
        }
        .padding(.top, 4)
    }

    private func header(_ bot: Bot) -> some View {
        HStack(spacing: 10) {
            GlassIconButton(symbol: presented ? "chevron.down" : "chevron.left", label: presented ? "Back to the chat" : "Back") { dismiss() }
            Spacer()
            if !presented, let router {
                GlassIconButton(symbol: "bubble.left", label: "Message \(bot.name)") {
                    router.push(.bot(botID), on: .home)
                }
            }
            botMenu(bot)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background { HeaderFade() }
    }

    private func botMenu(_ bot: Bot) -> some View {
        Menu {
            Button {
                store.togglePin(botID)
            } label: {
                Label(store.pinned.contains(botID) ? "Unpin" : "Pin", systemImage: store.pinned.contains(botID) ? "pin.slash" : "pin")
            }
            Button { goto = .allBots } label: { Label("All bots", systemImage: "person.3") }
            if let team = store.team(of: botID) {
                Button { goto = .team(team.id) } label: { Label(team.name, systemImage: "person.2") }
            }
            Button { goto = .report(botID) } label: { Label("\(bot.name)'s report", systemImage: "chart.bar.doc.horizontal") }
            if !bot.isKip && !store.liveMode {
                Button {
                    let copy = store.duplicate(botID)
                    goto = .botPage(copy)
                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { confirmArchive = true } label: { Label("Archive", systemImage: "archivebox") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .kGlass(Circle(), interactive: true)
        .accessibilityLabel("Bot menu")
    }
}
