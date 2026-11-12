import SwiftUI

/// Debug views for the Bots area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView bots.<name>` (see docs/DEV-GUIDE.md).
enum BotsDebug {
    static func view(_ name: String) -> AnyView? {
        let store = BotsStore.shared
        switch name {
        case "inbox": return page(BotPanelRoot(botID: "kip", startTab: .inbox, presented: true))
        case "inbox-scout": return page(BotPanelRoot(botID: "scout", startTab: .inbox, presented: true))
        case "settings": return page(BotPanelRoot(botID: "scout", startTab: .settings, presented: true))
        case "notifications": return page(BotNotificationsScreen(botID: "kip"))
        case "activity": return page(BotActivityScreen(botID: "kip"))
        case "report": return page(BotReportScreen(botID: "kip"))
        case "raise-full": return page(ApprovalSettings(botID: "scout").sheet(isPresented: .constant(true)) {
            RaiseLevelSheet(botName: "Scout", from: .ask, to: .full) {}
        })
        case "routines": return page(RoutinesScreen(botID: "scout"))
        case "routines-kip": return page(RoutinesScreen(botID: "kip"))
        case "routine-new": return page(RoutineEditorScreen(botID: "kip", routineID: nil))
        case "routine-interval": return page(RoutineEditorScreen(botID: "scout", routineID: store.routines.first { $0.mode == .interval }?.id))
        case "trigger-webhook": return page(TriggerEditorScreen(botID: "ledger", triggerID: nil, webhook: true))
        case "trigger-app": return page(TriggerEditorScreen(botID: "kip", triggerID: store.triggers.first { $0.kind == .appEvent }?.id, webhook: false))
        case "calendar": return page(AutomationCalendarScreen(botID: nil))
        case "automations": return page(AutomationsScreen())
        case "team": return page(TeamScreen(teamID: "content"))
        case "team-settings": return page(TeamScreen(teamID: "content", openSheet: .settings))
        case "team-memory": return page(TeamScreen(teamID: "content", openSheet: .memory))
        case "team-report": return page(TeamReportScreen(teamID: "content"))
        case "team-map": return page(TeamMapScreen())
        case "departments": return page(DepartmentsScreen())
        case "maker": return page(BotMakerScreen())
        case "create-simple": return page(BotMakerScreen(openCreate: DraftBox(draft: NewBotDraft())))
        case "create-advanced": return page(BotMakerScreen(openCreate: DraftBox(draft: store.readyBots[2].draft, advanced: true)))
        case "ready-made": return page(ReadyMadeScreen())
        case "archived": return page(ArchivedBotsScreen())
        case "packages": return page(PackagesScreen())
        case "package-preview": return page(PackagesScreen(preview: true))
        case "package-share": return page(PackagesScreen(startTab: "Share"))
        case "all-bots": return page(AllBotsScreen())
        case "all-bots-reorder": return page(AllBotsScreen(startEditing: true))
        case "room": return page(RoomScreen(roomID: "launch"))
        case "room-settings": return page(RoomScreen(roomID: "launch", openSheet: .settings))
        default:
            if name.hasPrefix("set-") {
                let raw = String(name.dropFirst(4))
                if let settingsPage = BotSettingsPage(rawValue: raw) {
                    return page(BotSettingsScreen(botID: raw == "look" ? "scout" : "kip", page: settingsPage))
                }
            }
            return nil
        }
    }

    private static func page<V: View>(_ view: V) -> AnyView {
        AnyView(view.botsDestinations())
    }
}
