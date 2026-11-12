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
    var pinned: [String] = ["kip", "producer", "scout"]
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
        bots.first { $0.id == id } ?? archived.first { $0.id == id } ?? SampleData.bot(id)
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

    func needsCount(_ botID: String) -> Int {
        needs.filter { $0.botID == botID && $0.settled == nil }.count
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

    func togglePin(_ botID: String) {
        if pinned.contains(botID) {
            pinned.removeAll { $0 == botID }
            say("\(bot(botID).name) is unpinned")
        } else {
            pinned.append(botID)
            say("\(bot(botID).name) is pinned")
        }
    }

    func archive(_ botID: String) {
        guard let index = bots.firstIndex(where: { $0.id == botID }), !bots[index].isKip else { return }
        let bot = bots.remove(at: index)
        archived.insert(bot, at: 0)
        pinned.removeAll { $0 == botID }
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
