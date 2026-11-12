import SwiftUI

/// Debug views for the Desktop area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView desktop.<name>` (see docs/DEV-GUIDE.md).
enum DesktopDebug {
    static func view(_ name: String) -> AnyView? {
        if let view = forge(name) ?? BrowseDebug.view(name) ?? MachineDebug.view(name) {
            return AnyView(view.desktopDestinations())
        }
        return nil
    }

    private static func forge(_ name: String) -> AnyView? {
        switch name {
        case "home": return AnyView(DesktopView())
        case "home-asleep": return AnyView(DesktopView(asleep: true))
        case "forge": return AnyView(ForgeHomeScreen())
        case "forge-customize": return AnyView(ForgeHomeScreen(start: .customize))
        case "new-session": return AnyView(ForgeHomeScreen(start: .compose))
        case "chart": return AnyView(ForgeHomeScreen(inspectDay: 8))
        case "projects": return AnyView(ForgeProjectsScreen())
        case "add-project": return AnyView(ForgeProjectsScreen(start: .add))
        case "project": return AnyView(ForgeProjectScreen(projectID: "p-shop"))
        case "repo": return AnyView(ForgeRepoScreen(projectID: "p-shop"))
        case "session": return AnyView(ForgeSessionScreen(sessionID: "s-layout"))
        case "session-working": return AnyView(ForgeSessionScreen(sessionID: "s-alerts"))
        case "session-review": return AnyView(ForgeSessionScreen(sessionID: "s-images"))
        case "session-actions": return AnyView(ForgeSessionScreen(sessionID: "s-layout", start: .actions))
        case "full-access": return AnyView(ForgeSessionScreen(sessionID: "s-layout", start: .fullAccess))
        case "model": return AnyView(ForgeSessionScreen(sessionID: "s-layout", start: .model))
        case "end": return AnyView(ForgeSessionScreen(sessionID: "s-layout", start: .end))
        case "git": return AnyView(ForgeSessionScreen(sessionID: "s-layout", start: .git))
        case "run-app": return AnyView(ForgeSessionScreen(sessionID: "s-images", start: .runApp))
        case "changes": return AnyView(ForgeChangesScreen(sessionID: "s-layout"))
        case "diff": return AnyView(ForgeDiffScreen(sessionID: "s-layout", path: "src/styles/layout.css"))
        case "explorer": return AnyView(ForgeExplorerScreen(sessionID: "s-layout"))
        case "file": return AnyView(ForgeFileScreen(sessionID: "s-layout", path: "src/components/NavBar.tsx"))
        case "terminal": return AnyView(ForgeTerminalScreen(sessionID: "s-layout"))
        case "preview": return AnyView(ForgePreviewScreen(sessionID: "s-layout"))
        case "preview-logs": return AnyView(ForgePreviewScreen(sessionID: "s-layout", showLogs: true))
        default: return nil
        }
    }
}
