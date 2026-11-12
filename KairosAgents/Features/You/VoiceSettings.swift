import SwiftUI

struct VoiceScreen: View {
    var body: some View { SettingsPage("VoiceScreen") { NoteText(text: "Not built yet.") } }
}

struct BotVoiceScreen: View {
    var body: some View { SettingsPage("BotVoiceScreen") { NoteText(text: "Not built yet.") } }
}

enum VoiceDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
