import SwiftUI

/// Where the Bots screens read and write. Today it holds made-up sample data;
/// a desktop-backed store can replace `BotsStore.shared` without changing the screens
/// (the desktop routes are /api/agents, /api/bot-attention, /api/bot-rooms, /api/bot-team).
protocol BotsProviding: AnyObject {
    var bots: [Bot] { get }
    func settings(_ botID: String) -> BotSettings
    func save(_ botID: String, _ settings: BotSettings)
}

@Observable
final class BotsStore: BotsProviding {
    static let shared = BotsStore()

    // Roster
    var bots: [Bot]
    var archived: [Bot]
    var chiefs: Set<String> = ["producer"]

    // Per bot
    var allSettings: [String: BotSettings] = [:]
    var routines: [Routine]
    var triggers: [BotTrigger]
    var needs: [NeedsCard]
    var work: [WorkItem]
    var notices: [BotNotice]

    // Shared by every bot
    var aboutYou = "I run a small bike shop. Keep replies short. Weekly report goes out on Fridays."
    var learned: [LearnedFact]
    var apps: [ConnectedApp]
    var profiles: [BrowserProfile]
    var logins: [SavedLogin]
    var planWindows: [PlanWindow]
    var skillLibrary: [SkillItem]

    // Teams
    var teams: [BotTeam]
    var rooms: [BotRoom]
    var handoffs: [Handoff]

    // Making bots
    var presets: [String] = ["Shop helper"]
    let readyBots: [ReadyBot]

    // A short message at the bottom of any Bots screen.
    var toast: String?
    private var toastTask: Task<Void, Never>?

    // The paired desktop (BotsLive.swift). While `liveMode` is on, the roster, teams, pins and
    // Needs you cards above hold the desktop's own; the sample ones wait in `sampleStash`.
    var liveMode = false
    var rosterLoad: BotsLiveLoad = .idle
    var liveNeedsYou: [String: Int] = [:]
    var details: [String: AgentDetailDTO] = [:]
    var detailLoad: [String: BotsLiveLoad] = [:]
    var cardsLoad: [String: BotsLiveLoad] = [:]
    @ObservationIgnored var sampleStash: BotsSampleStash?

    init() {
        bots = SampleData.allBots.filter { $0.members.isEmpty }
        archived = [
            Bot(id: "pip", name: "Pip", role: "Holiday cards", colorHex: Palette.botRose, status: .offline, shape: .scallop, accessory: .scarf),
            Bot(id: "otto", name: "Otto", role: "Old inbox triage", colorHex: Palette.botSage, status: .offline, shape: .squircle),
        ]
        routines = BotsSample.routines
        triggers = BotsSample.triggers
        needs = BotsSample.needs
        work = BotsSample.work
        notices = BotsSample.notices
        learned = BotsSample.learned
        apps = BotsSample.apps
        profiles = BotsSample.profiles
        logins = BotsSample.logins
        planWindows = BotsSample.planWindows
        skillLibrary = BotsSample.skills
        teams = BotsSample.teams
        rooms = BotsSample.rooms
        handoffs = BotsSample.handoffs
        readyBots = BotsSample.readyBots
    }

    // MARK: Lookups

    func bot(_ id: String) -> Bot {
        if let found = bots.first(where: { $0.id == id }) ?? archived.first(where: { $0.id == id }) { return found }
        if liveMode {
            if let agent = details[id]?.agent { return Self.liveBot(agent) }
            return Bot(id: id, name: "Bot", role: "", colorHex: BotAvatarRules.defaultColor(id), status: .offline, shape: BotAvatarRules.defaultShape(id))
        }
        return SampleData.bot(id)
    }

    func settings(_ botID: String) -> BotSettings {
        allSettings[botID] ?? BotsSample.settings(for: bot(botID))
    }

    func save(_ botID: String, _ settings: BotSettings) {
        allSettings[botID] = settings
    }

    /// A two-way handle on one bot's settings for the screens.
    func binding(_ botID: String) -> Binding<BotSettings> {
        Binding(
            get: { self.settings(botID) },
            set: { self.allSettings[botID] = $0 }
        )
    }

    func botBinding(_ botID: String) -> Binding<Bot> {
        Binding(
            get: { self.bot(botID) },
            set: { newValue in
                if let index = self.bots.firstIndex(where: { $0.id == botID }) { self.bots[index] = newValue }
            }
        )
    }

    func team(of botID: String) -> BotTeam? { teams.first { $0.members.contains(botID) } }

    /// How many things wait on the person for one bot: the one count every badge shows (Home's face, the chat
    /// header, All bots and the panel's Inbox). Paired, the bot's own inbox once it is read (it drops as each
    /// is answered), else the roster's count.
    func needsCount(_ botID: String) -> Int {
        if liveMode {
            if cardsLoad[botID] == .loaded && BotsInboxLive.shared.inboxLoad == .loaded {
                return BotInboxSection.livePending(botID)
            }
            return liveNeedsYou[botID] ?? 0
        }
        return needs.filter { $0.botID == botID && $0.settled == nil }.count
    }

    /// Everything waiting on the person across the bots, from the same counts. nil until the roster is read.
    var needsTotal: Int? {
        guard liveMode, rosterLoad == .loaded else { return nil }
        let ids = Set(bots.map(\.id) + archived.map(\.id) + liveNeedsYou.keys)
        return ids.reduce(0) { $0 + needsCount($1) }
    }

    func routines(for botID: String) -> [Routine] { routines.filter { $0.botID == botID } }

    // MARK: Actions

    func say(_ text: String) {
        toastTask?.cancel()
        withAnimation(Motion.snappy) { toast = text }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled { withAnimation(Motion.gentle) { toast = nil } }
        }
    }

    func settle(_ cardID: UUID, _ result: Settled) {
        guard let index = needs.firstIndex(where: { $0.id == cardID }) else { return }
        withAnimation(Motion.bouncy) { needs[index].settled = result }
    }

    // Pins are Home's: one list, kept by `ChatStore` (saved on the desktop when paired), so a pin made here
    // shows on Home at once and the other way round.

    /// The pinned bots, Kip first (Home always shows Kip), then Home's pins in Home's order.
    var pinned: [String] {
        let kip = bots.first(where: \.isKip).map { [$0.id] } ?? []
        return kip + movablePins
    }

    /// Home's pinned bots that this roster has, without Kip: the ones that can be moved or unpinned.
    var movablePins: [String] {
        ChatStore.shared.pinnedIDs.filter { id in bots.contains { $0.id == id && !$0.isKip } }
    }

    /// Kip is always on Home; a bot Home does not know (one made only in this sample) cannot be pinned there.
    func canPin(_ botID: String) -> Bool {
        guard let found = bots.first(where: { $0.id == botID }), !found.isKip else { return false }
        return ChatStore.shared.bots.contains { $0.id == botID }
    }

    func isPinned(_ botID: String) -> Bool { ChatStore.shared.isPinned(bot: botID) }

    /// Pin or unpin a bot on Home, the same way Home's own menu does.
    func togglePin(_ botID: String) {
        guard canPin(botID) else { return }
        let name = bot(botID).name
        let was = isPinned(botID)
        Haptics.select()
        Task {
            if let problem = await ChatStore.shared.togglePin(bot: botID) {
                say(problem)
            } else {
                say(was ? "\(name) is unpinned" : "\(name) is pinned")
            }
        }
    }

    func archive(_ botID: String) {
        guard let index = bots.firstIndex(where: { $0.id == botID }), !bots[index].isKip else { return }
        let bot = bots.remove(at: index)
        archived.insert(bot, at: 0)
        // In the sample an archived bot leaves Home's pins too. Paired, the desktop keeps its own pins.
        if !liveMode && ChatStore.shared.isPinned(bot: botID) { Task { _ = await ChatStore.shared.togglePin(bot: botID) } }
        say("\(bot.name) is archived")
    }

    func restore(_ botID: String) {
        guard let index = archived.firstIndex(where: { $0.id == botID }) else { return }
        let bot = archived.remove(at: index)
        bots.append(bot)
        say("\(bot.name) is back")
    }

    func deleteArchived(_ botID: String) {
        guard let index = archived.firstIndex(where: { $0.id == botID }) else { return }
        let bot = archived.remove(at: index)
        say("\(bot.name) was deleted")
    }

    func duplicate(_ botID: String) -> String {
        var copy = bot(botID)
        let newID = "\(botID)-copy-\(Int.random(in: 100...999))"
        copy = Bot(id: newID, name: "\(copy.name) 2", role: copy.role, colorHex: copy.colorHex, status: .online, shape: copy.shape, accessory: copy.accessory)
        bots.append(copy)
        allSettings[newID] = settings(botID)
        say("\(copy.name) is ready")
        return newID
    }

    @discardableResult
    func create(_ draft: NewBotDraft) -> Bot {
        let name = draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Juniper" : draft.name
        let id = "bot-\(UUID().uuidString.prefix(6).lowercased())"
        let bot = Bot(id: id, name: name, role: draft.job.isEmpty ? "No job yet" : draft.job, colorHex: draft.colorHex, status: .online, shape: draft.shape, accessory: draft.accessory, model: draft.model)
        bots.append(bot)
        var settings = BotsSample.settings(for: bot)
        settings.model = draft.model
        settings.effort = draft.effort
        settings.approval = draft.fullAccess ? .full : .ask
        settings.standingInstructions = draft.instructions
        settings.introduction = draft.introduction
        settings.notes = draft.notes.filter { !$0.text.isEmpty }.map { MemoryNote(section: $0.heading, text: $0.text, addedBy: "you", when: "just now") }
        settings.reportTo = draft.tellMeOn
        allSettings[id] = settings
        for var routine in draft.routines {
            routine.botID = id
            routines.append(routine)
        }
        say("\(name) is ready")
        return bot
    }

    func moveBot(_ botID: String, toTeam teamID: String?) {
        for index in teams.indices { teams[index].members.removeAll { $0 == botID } }
        if let teamID, let index = teams.firstIndex(where: { $0.id == teamID }) {
            teams[index].members.append(botID)
        }
    }
}

/// A glass message that floats at the bottom of a Bots screen for a moment.
struct BotsToastHost: ViewModifier {
    let store = BotsStore.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let text = store.toast {
                Text(text)
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .kGlass(Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

extension View {
    func botsToast() -> some View { modifier(BotsToastHost()) }
}
