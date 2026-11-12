import SwiftUI

struct ChannelsScreen: View {
    var body: some View { SettingsPage("ChannelsScreen") { NoteText(text: "Not built yet.") } }
}

struct ChannelDetailScreen: View {
    let channelID: String
    var body: some View { SettingsPage("ChannelDetailScreen") { NoteText(text: "Not built yet.") } }
}

struct AddChannelScreen: View {
    let kind: String
    var body: some View { SettingsPage("AddChannelScreen") { NoteText(text: "Not built yet.") } }
}

struct DiscordBotScreen: View {
    let botID: String
    var body: some View { SettingsPage("DiscordBotScreen") { NoteText(text: "Not built yet.") } }
}

enum ChannelsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
