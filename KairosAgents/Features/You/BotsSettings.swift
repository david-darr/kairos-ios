import SwiftUI

struct BotPrefsScreen: View {
    var body: some View { SettingsPage("BotPrefsScreen") { NoteText(text: "Not built yet.") } }
}

struct BotKeysScreen: View {
    var body: some View { SettingsPage("BotKeysScreen") { NoteText(text: "Not built yet.") } }
}

struct BotLoginsScreen: View {
    var body: some View { SettingsPage("BotLoginsScreen") { NoteText(text: "Not built yet.") } }
}

struct AboutYouScreen: View {
    var body: some View { SettingsPage("AboutYouScreen") { NoteText(text: "Not built yet.") } }
}

struct SkillLibraryScreen: View {
    var body: some View { SettingsPage("SkillLibraryScreen") { NoteText(text: "Not built yet.") } }
}

struct BotUsageScreen: View {
    var body: some View { SettingsPage("BotUsageScreen") { NoteText(text: "Not built yet.") } }
}

struct BotHousekeepingScreen: View {
    var body: some View { SettingsPage("BotHousekeepingScreen") { NoteText(text: "Not built yet.") } }
}

struct BotTemplatesScreen: View {
    var body: some View { SettingsPage("BotTemplatesScreen") { NoteText(text: "Not built yet.") } }
}

struct BotComputersScreen: View {
    var body: some View { SettingsPage("BotComputersScreen") { NoteText(text: "Not built yet.") } }
}

struct ConnectedAppsScreen: View {
    var body: some View { SettingsPage("ConnectedAppsScreen") { NoteText(text: "Not built yet.") } }
}

enum BotsSettingsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
