import SwiftUI

// Home's bots: the pinned row (Kip, All bots, then the person's pins). The All bots tile opens
// `AllBotsScreen`. Bot pins are saved on the desktop; team pins stay on this phone, because the
// desktop has no pin for a team.

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

/// Lays out up to `columns` cells in one row, each a full-row cell wide, the row centered.
/// (The available width is read from the proposal, so no GeometryReader is needed.)
private struct FaceRowLayout: Layout {
    let spacing: CGFloat
    let columns: Int

    private func cellWidth(_ width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let cell = cellWidth(width)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = cellWidth(bounds.width)
        let used = cell * CGFloat(subviews.count) + spacing * CGFloat(max(0, subviews.count - 1))
        var x = bounds.minX + (bounds.width - used) / 2
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: cell, height: bounds.height))
            x += cell + spacing
        }
    }
}

/// The pinned row: big round faces, four across, each bot with its needs-you count. A long hold pins or unpins.
struct PinnedFacesGrid: View {
    let faces: [HomeFace]
    /// Where tapping a face goes. The grid itself only draws and pins.
    let open: (HomeFace) -> Void
    var firstArrival = 1

    var body: some View {
        let rows = stride(from: 0, to: faces.count, by: 4).map { Array(faces[$0..<min($0 + 4, faces.count)]) }
        VStack(spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                FaceRowLayout(spacing: 8, columns: 4) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { column, face in
                        cell(face, index: rowIndex * 4 + column)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func cell(_ face: HomeFace, index: Int) -> some View {
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

    @ViewBuilder
    private func picture(_ face: HomeFace) -> some View {
        switch face {
        case .bot(let bot):
            BotFace(bot: bot, size: 82, showStatus: true, blinks: true)
                .overlay(alignment: .topTrailing) {
                    let count = BotsStore.shared.needsCount(bot.id)
                    if count > 0 { CountBadge(count: count).offset(x: 4, y: -2) }
                }
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
        case .bot(let bot):
            HomeFaceWords.label(bot.name, status: HomeFaceWords.status(bot.status), needs: BotsStore.shared.needsCount(bot.id))
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
        case .needsYou: "needs you"
        case .offline: "asleep"
        }
    }

    /// "3 need you", or "1 needs you": the same words as the glance pill and the bot's Needs you.
    static func needYou(_ count: Int) -> String {
        count == 1 ? "1 needs you" : "\(count) need you"
    }

    /// A bot face's spoken name: its name, its status, and how many things need the person.
    static func label(_ name: String, status: String, needs: Int) -> String {
        needs > 0 ? "\(name), \(status), \(needYou(needs))" : "\(name), \(status)"
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
