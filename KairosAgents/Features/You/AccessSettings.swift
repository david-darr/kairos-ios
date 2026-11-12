import SwiftUI

struct PermissionsScreen: View {
    var body: some View { SettingsPage("PermissionsScreen") { NoteText(text: "Not built yet.") } }
}

struct AgentToolsScreen: View {
    var body: some View { SettingsPage("AgentToolsScreen") { NoteText(text: "Not built yet.") } }
}

struct ComputerUseScreen: View {
    var body: some View { SettingsPage("ComputerUseScreen") { NoteText(text: "Not built yet.") } }
}

struct RemoteAccessScreen: View {
    var body: some View { SettingsPage("RemoteAccessScreen") { NoteText(text: "Not built yet.") } }
}

struct ForgeSettingsScreen: View {
    var body: some View { SettingsPage("ForgeSettingsScreen") { NoteText(text: "Not built yet.") } }
}

enum AccessDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
