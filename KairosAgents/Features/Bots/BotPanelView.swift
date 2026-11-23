import SwiftUI

/// A bot's own page: Inbox, Routines and Access. Opened by tapping the bot's face in its chat,
/// as a full-screen cover with its own navigation stack.
struct BotPanelView: View {
    enum Tab: String, CaseIterable {
        case inbox = "Inbox", routines = "Routines", access = "Access"
        var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The switch's choice.
    @State private var tab: BotPanelView.Tab = .inbox
    /// The section on screen. It follows the switch one step behind, so the section leaving knows
    /// which way to slide.
    @State private var shown: BotPanelView.Tab = .inbox
    @State private var cameFrom: BotPanelView.Tab = .inbox
    /// Sections already shown and left: their rows appear in place when shown again.
    @State private var seen: Set<BotPanelView.Tab> = []
    @State private var started = false
    @State private var goto: BotsRoute?
    @State private var confirmArchive = false
    /// The Routines section's "Bring it back", kept here so it survives switching sections.
    @State private var removedRoutine: Routine?

    var body: some View {
        let bot = store.bot(botID)
        ScrollView {
            VStack(spacing: 16) {
                hero(bot)
                GlassSwitch(items: BotPanelView.Tab.allCases, selection: $tab, minHeight: 44) { switchTitle($0) }
                    .fixedSize()
                Group {
                    switch shown {
                    case .inbox: section(.inbox) { BotInboxSection(botID: botID) }
                    case .routines: section(.routines) { RoutinesList(botID: botID, removedHolder: $removedRoutine) }
                    case .access: section(.access) { accessSection }
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
        .animation(Motion.snappy, value: shown)
        .onChange(of: tab) { _, new in
            guard new != shown else { return }
            cameFrom = shown
            seen.insert(shown)
            withAnimation(Motion.snappy) { shown = new }
        }
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
            shown = startTab
            cameFrom = startTab
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
            BotFace(bot: bot, size: 132, showStatus: true, blinks: true)
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
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
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

    /// "Inbox 2" while something waits on you.
    private func switchTitle(_ item: BotPanelView.Tab) -> String {
        let needs = store.needsCount(botID)
        return item == .inbox && needs > 0 ? "\(item.rawValue) \(needs)" : item.rawValue
    }

    /// One section, sliding in from the side of the switch it sits on. Its rows arrive only the first time.
    private func section<Content: View>(_ item: BotPanelView.Tab, @ViewBuilder _ content: () -> Content) -> some View {
        // Leaving: slide toward the section chosen. Arriving: come from the side of the one left.
        let other = item == tab ? cameFrom : tab
        let edge: Edge = item.order < other.order ? .leading : .trailing
        return content()
            .environment(\.arrivalsSettled, seen.contains(item))
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: edge)))
    }

    /// Access: how far it may go on its own, what it can reach, then every setting.
    private var accessSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            Group {
                ApprovalSettings(botID: botID)
                AccessSettings(botID: botID)
            }
            .environment(\.botsPageEmbedded, true)
            NavigationLink(value: BotsRoute.allSettings(botID)) {
                NavRow(title: "All settings", symbol: "gearshape")
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .kCard(radius: Radius.card)
        }
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
            if store.canPin(botID) {
                Button {
                    store.togglePin(botID)
                } label: {
                    Label(store.isPinned(botID) ? "Unpin from Home" : "Pin to Home", systemImage: store.isPinned(botID) ? "pin.slash" : "pin")
                }
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
