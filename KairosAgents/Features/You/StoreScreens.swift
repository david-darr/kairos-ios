import SwiftUI

struct StoreItemScreen: View {
    let itemID: String
    var body: some View { SettingsPage("StoreItemScreen") { NoteText(text: "Not built yet.") } }
}

struct BuildTabScreen: View {
    var body: some View { SettingsPage("BuildTabScreen") { NoteText(text: "Not built yet.") } }
}

enum StoreDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
