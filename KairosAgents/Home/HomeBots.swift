import SwiftUI

// Home's bots: the pinned row (Kip, All bots, then the person's pins) and the All bots page,
// which is laid out like Home but lists every bot and team. Bot pins are saved on the desktop;
// team pins stay on this phone, because the desktop has no pin for a team.

/// One face in a row of pinned faces.
enum HomeFace: Identifiable, Hashable {
    case bot(Bot)
    case allBots
    case team(BotTeam)

    var id: String {
        switch self {
        case .bot(let bot): "bot-" + bot.id
        case .allBots: "all-bots"
        case .team(let team): "team-" + team.id
        }
    }
}

/// The pinned row: big round faces, four across. A long hold pins or unpins.
struct PinnedFacesGrid: View {
    let faces: [HomeFace]
    /// Where tapping a face goes. The grid itself only draws and pins.
    let open: (HomeFace) -> Void
    var firstArrival = 1

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(faces.enumerated()), id: \.element.id) { index, face in
                Button {
                    Haptics.tap()
                    open(face)
                } label: {
                    VStack(spacing: 7) {
                        picture(face)
                        Text(name(face))
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressStyle(scale: 0.92))
                .contextMenu { menu(face) }
                .accessibilityLabel(label(face))
                .arrives(index + firstArrival)
            }
        }
    }

    @ViewBuilder
    private func picture(_ face: HomeFace) -> some View {
        switch face {
        case .bot(let bot): BotFace(bot: bot, size: 82, showStatus: true, blinks: true)
        case .allBots: AllBotsTile(size: 82)
        case .team(let team): TeamFace(team: team, size: 82)
        }
    }

    private func name(_ face: HomeFace) -> String {
        switch face {
        case .bot(let bot): bot.name
        case .allBots: "All bots"
        case .team(let team): team.name
        }
    }

    private func label(_ face: HomeFace) -> String {
        switch face {
        case .bot(let bot): "\(bot.name), \(HomeFaceWords.status(bot.status))"
        case .allBots: "All bots. Every bot and team"
        case .team(let team): "\(team.name), a team of \(team.members.count)"
        }
    }

    @ViewBuilder
    private func menu(_ face: HomeFace) -> some View {
        switch face {
        case .bot(let bot) where !bot.isKip:
            HomePinButton(face: face)
        case .team:
            HomePinButton(face: face)
        default:
            EmptyView()
        }
    }
}

/// "Pin to Home" or "Unpin from Home" for a bot or a team, in a long-hold menu.
struct HomePinButton: View {
    let face: HomeFace
    @Environment(ChromeState.self) private var chrome
    private var store: ChatStore { ChatStore.shared }

    var body: some View {
        switch face {
        case .bot(let bot):
            let pinned = store.isPinned(bot: bot.id)
            Button(pinned ? "Unpin from Home" : "Pin to Home", systemImage: pinned ? "pin.slash" : "pin") {
                Haptics.select()
                Task {
                    if let problem = await store.togglePin(bot: bot.id) {
                        chrome.say(problem)
                    } else {
                        chrome.say(pinned ? "\(bot.name) is unpinned" : "\(bot.name) is pinned")
                    }
                }
            }
        case .team(let team):
            let pinned = store.isPinned(team: team.id)
            Button(pinned ? "Unpin from Home" : "Pin to Home", systemImage: pinned ? "pin.slash" : "pin") {
                Haptics.select()
                withAnimation(Motion.snappy) { store.togglePin(team: team.id) }
                chrome.say(pinned ? "\(team.name) is unpinned" : "\(team.name) is pinned")
            }
        case .allBots:
            EmptyView()
        }
    }
}

enum HomeFaceWords {
    static func status(_ status: BotStatus) -> String {
        switch status {
        case .online: "ready"
        case .working: "working"
        case .needsYou: "waiting for you"
        case .offline: "asleep"
        }
    }
}

/// The All bots tile: a few small faces on one round tile.
struct AllBotsTile: View {
    let size: CGFloat
    private var store: ChatStore { ChatStore.shared }

    var body: some View {
        let shown = Array(store.singleBots.filter { !$0.isKip }.prefix(3))
        ZStack {
            Circle().fill(Palette.surfaceRaised)
            Circle().strokeBorder(Palette.lineStrong, lineWidth: 1)
            if shown.isEmpty {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: size * 0.26, weight: .medium))
                    .foregroundStyle(Palette.inkDim)
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, bot in
                    BotFace(bot: bot, size: size * 0.42)
                        .offset(x: [-size * 0.15, size * 0.15, 0][index], y: [-size * 0.1, -size * 0.1, size * 0.15][index])
                }
            }
        }
        .frame(width: size * 0.84, height: size * 0.84)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A team's face: two of its members on one round tile, drawn from the bots this phone knows.
struct TeamFace: View {
    let team: BotTeam
    let size: CGFloat
    private var store: ChatStore { ChatStore.shared }

    var body: some View {
        let members = team.members.prefix(2).map { store.bot($0) }
        ZStack {
            Circle().fill(Palette.surfaceRaised)
            Circle().strokeBorder(Palette.lineStrong, lineWidth: 1)
            ForEach(Array(members.enumerated()), id: \.offset) { index, member in
                BotFace(bot: member, size: size * 0.56)
                    .offset(x: index == 0 ? -size * 0.14 : size * 0.15, y: index == 0 ? -size * 0.06 : size * 0.08)
            }
        }
        .frame(width: size * 0.84, height: size * 0.84)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Every bot and team, laid out like Home: pinned faces, then one row per bot and team.
struct AllBotsHomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @Environment(\.dismiss) private var dismiss
    @State private var openTeam: BotTeam?
    @State private var managing = false

    private var store: ChatStore { ChatStore.shared }
    private var bots: BotsStore { BotsStore.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let pinned = HomeFaces.pinned(store: store, bots: bots, withAllBots: false)
                if !pinned.isEmpty {
                    PinnedFacesGrid(faces: pinned, open: open)
                        .padding(.top, 2)
                }

                LazyVStack(spacing: 0) {
                    let conversations = store.botConversations
                    ForEach(Array(store.singleBots.enumerated()), id: \.element.id) { index, bot in
                        Button { router.push(.bot(bot.id), on: .home) } label: {
                            ConversationRow(conversation: row(for: bot, conversations: conversations), bot: bot)
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .contextMenu {
                            Button("Open", systemImage: "bubble.left") { router.push(.bot(bot.id), on: .home) }
                            if !bot.isKip { HomePinButton(face: .bot(bot)) }
                        }
                        .arrives(min(index, 12) + 3)
                    }
                    ForEach(bots.teams) { team in
                        Button { openTeam = team } label: { teamRow(team) }
                            .buttonStyle(PressStyle(scale: 0.985))
                            .contextMenu {
                                Button("Open", systemImage: "person.3") { openTeam = team }
                                HomePinButton(face: .team(team))
                            }
                    }
                }

                if !store.homeLoaded && !store.isSample {
                    ProgressView().tint(Palette.inkDim).frame(maxWidth: .infinity).padding(.top, 30)
                } else if store.singleBots.isEmpty {
                    Text("No bots yet. Make one in Kairos on your desktop.")
                        .font(KFont.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 30)
            .animation(Motion.snappy, value: store.pinnedIDs)
            .animation(Motion.snappy, value: store.pinnedTeamIDs)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await store.refreshHome()
            if bots.liveMode { await bots.loadRoster() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("All bots")
                    .font(KFont.ui(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                HStack {
                    GlassIconButton(symbol: "chevron.left", label: "Back to Home") { dismiss() }
                    Spacer()
                    Button { managing = true } label: {
                        Text("Manage")
                            .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .kGlass(Capsule(), interactive: true)
                    }
                    .accessibilityHint("Reorder, archive and arrange bots in teams")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .background { HeaderFade() }
        }
        .kScreen()
        .fullScreenCover(item: $openTeam) { team in
            NavigationStack { TeamScreen(teamID: team.id).botsDestinations() }
                .tint(Palette.gold)
        }
        .fullScreenCover(isPresented: $managing) {
            NavigationStack { AllBotsScreen().botsDestinations() }
                .tint(Palette.gold)
        }
        .task { await HomeFaces.loadTeams() }
        .onChange(of: store.generation) { dismiss() }
    }

    private func open(_ face: HomeFace) {
        switch face {
        case .bot(let bot): router.push(.bot(bot.id), on: .home)
        case .team(let team): openTeam = team
        case .allBots: break
        }
    }

    /// The bot's newest conversation, or a quiet row for a bot not talked to yet.
    private func row(for bot: Bot, conversations: [String: Conversation]) -> Conversation {
        if let conversation = conversations[bot.id] { return conversation }
        return Conversation(id: "bot-" + bot.id, kind: .bot(bot.id), title: bot.name,
                            preview: bot.isKip ? "Here when you need me." : bot.role, time: "")
    }

    private func teamRow(_ team: BotTeam) -> some View {
        HStack(spacing: 12) {
            TeamFace(team: team, size: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(KFont.ui(16.5, .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(team.members.map { store.bot($0).name }.joined(separator: ", "))
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if store.isPinned(team: team.id) {
                Image(systemName: "pin.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 74) }
        .accessibilityElement(children: .combine)
    }
}

enum HomeFaces {
    /// Kip first, then (on Home) the All bots tile, then the pinned bots and teams.
    static func pinned(store: ChatStore, bots: BotsStore, withAllBots: Bool) -> [HomeFace] {
        var faces: [HomeFace] = []
        if let kip = store.kip { faces.append(.bot(kip)) }
        if withAllBots { faces.append(.allBots) }
        faces += store.pinnedBots.map { HomeFace.bot($0) }
        faces += bots.teams.filter { store.isPinned(team: $0.id) }.map { HomeFace.team($0) }
        return faces
    }

    /// Teams come from the Bots area's store; read them from the desktop once when paired.
    static func loadTeams() async {
        let bots = BotsStore.shared
        bots.followConnection()
        if bots.liveMode && bots.rosterLoad != .loaded { await bots.loadRoster() }
    }
}
