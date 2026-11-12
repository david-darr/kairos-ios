import SwiftUI

struct NotificationsScreen: View {
    var body: some View { SettingsPage("NotificationsScreen") { NoteText(text: "Not built yet.") } }
}

struct ReachMeScreen: View {
    var body: some View { SettingsPage("ReachMeScreen") { NoteText(text: "Not built yet.") } }
}

enum NotifyDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
