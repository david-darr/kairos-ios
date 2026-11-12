import SwiftUI

struct ModelsScreen: View {
    var body: some View { SettingsPage("ModelsScreen") { NoteText(text: "Not built yet.") } }
}

struct AddModelScreen: View {
    var body: some View { SettingsPage("AddModelScreen") { NoteText(text: "Not built yet.") } }
}

struct ModelGuideScreen: View {
    var body: some View { SettingsPage("ModelGuideScreen") { NoteText(text: "Not built yet.") } }
}

enum ModelsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
