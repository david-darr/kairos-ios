import SwiftUI

/// Debug views for the Bots area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView bots.<name>` (see docs/DEV-GUIDE.md).
enum BotsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "inbox": return AnyView(BotPanelRoot(botID: "kip", startTab: .inbox, presented: true).botsDestinations())
        case "inbox-scout": return AnyView(BotPanelRoot(botID: "scout", startTab: .inbox, presented: true).botsDestinations())
        case "settings": return AnyView(BotPanelRoot(botID: "scout", startTab: .settings, presented: true).botsDestinations())
        default:
            if name.hasPrefix("set-") {
                let raw = String(name.dropFirst(4))
                if let page = BotSettingsPage(rawValue: raw) {
                    return AnyView(BotSettingsScreen(botID: raw == "look" ? "scout" : "kip", page: page).botsDestinations())
                }
            }
            return nil
        }
    }
}
