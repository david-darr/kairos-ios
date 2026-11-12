import SwiftUI

struct VaultSettingsScreen: View {
    var body: some View { SettingsPage("VaultSettingsScreen") { NoteText(text: "Not built yet.") } }
}

struct PhoneLineScreen: View {
    var body: some View { SettingsPage("PhoneLineScreen") { NoteText(text: "Not built yet.") } }
}

enum VaultPhoneDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
