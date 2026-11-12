import SwiftUI

struct LookScreen: View {
    var body: some View { SettingsPage("LookScreen") { NoteText(text: "Not built yet.") } }
}

struct LayoutScreen: View {
    var body: some View { SettingsPage("LayoutScreen") { NoteText(text: "Not built yet.") } }
}

enum LookDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
