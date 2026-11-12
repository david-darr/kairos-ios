import SwiftUI

/// Debug views for Browse. Each opens the screen in one state so the build can take its picture.
enum BrowseDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "browse": return AnyView(BrowseScreen())
        case "browse-home":
            BrowseStore.shared.activeID = "t-blank"
            return AnyView(BrowseScreen())
        case "browse-call":
            BrowseStore.shared.activeID = "t-call"
            return AnyView(BrowseScreen())
        case "browse-find": return AnyView(BrowseScreen(startFinding: true))
        case "browse-tabs": return AnyView(BrowseScreen(start: .tabs))
        case "browse-site": return AnyView(BrowseScreen(start: .site))
        case "browse-history": return AnyView(BrowseScreen(start: .history))
        case "browse-downloads": return AnyView(BrowseScreen(start: .downloads))
        case "browse-passwords": return AnyView(BrowseScreen(start: .passwords))
        case "browse-ask": return AnyView(BrowseScreen(start: .ask))
        case "browse-settings": return AnyView(BrowseScreen(start: .settings))
        default: return nil
        }
    }
}
