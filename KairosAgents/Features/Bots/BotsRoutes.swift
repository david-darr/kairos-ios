import SwiftUI

/// The pages of one bot's Settings.
enum BotSettingsPage: String, Hashable, CaseIterable {
    case overview, model, approval, voice, delivery, memory, aboutYou, skills, skillLibrary
    case access, connections, browser, usage, limits, conversations, look, instructions, history
}

/// Every page in the Bots area. Push with `NavigationLink(value: BotsRoute.x)`.
enum BotsRoute: Hashable {
    // One bot
    case botPage(String)
    case settings(String, BotSettingsPage)
    case report(String)
    case notifications(String)
    case activity(String)
    // Routines and automations
    case routines(String)
    case routineEditor(String, UUID?)
    case triggerEditor(String, UUID?, webhook: Bool)
    case calendar(String?)
    case automations
    // Teams and rooms
    case team(String)
    case teamReport(String)
    case teamMap
    case room(String)
    case departments
    // Roster and making bots
    case allBots
    case maker
    case readyMade
    case archived
    case packages
}

extension View {
    /// Registers every Bots page on the navigation stack this view sits in.
    func botsDestinations() -> some View {
        navigationDestination(for: BotsRoute.self) { route in
            BotsDestination(route: route)
        }
    }
}

struct BotsDestination: View {
    let route: BotsRoute

    var body: some View {
        switch route {
        case .botPage(let id): BotPanelRoot(botID: id, startTab: .inbox, presented: false)
        case .settings(let id, let page): BotSettingsScreen(botID: id, page: page)
        case .report(let id): BotReportScreen(botID: id)
        case .notifications(let id): BotNotificationsScreen(botID: id)
        case .activity(let id): BotActivityScreen(botID: id)
        case .routines(let id): RoutinesScreen(botID: id)
        case .routineEditor(let id, let routine): RoutineEditorScreen(botID: id, routineID: routine)
        case .triggerEditor(let id, let trigger, let webhook): TriggerEditorScreen(botID: id, triggerID: trigger, webhook: webhook)
        case .calendar(let id): AutomationCalendarScreen(botID: id)
        case .automations: AutomationsScreen()
        case .team(let id): TeamScreen(teamID: id)
        case .teamReport(let id): TeamReportScreen(teamID: id)
        case .teamMap: TeamMapScreen()
        case .room(let id): RoomScreen(roomID: id)
        case .departments: DepartmentsScreen()
        case .allBots: AllBotsScreen()
        case .maker: BotMakerScreen()
        case .readyMade: ReadyMadeScreen()
        case .archived: ArchivedBotsScreen()
        case .packages: PackagesScreen()
        }
    }
}
