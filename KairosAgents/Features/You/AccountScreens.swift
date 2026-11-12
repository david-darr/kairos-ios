import SwiftUI

struct AccountScreen: View {
    var body: some View { SettingsPage("AccountScreen") { NoteText(text: "Not built yet.") } }
}

struct DeviceAccountsScreen: View {
    var body: some View { SettingsPage("DeviceAccountsScreen") { NoteText(text: "Not built yet.") } }
}

struct SignInScreen: View {
    var body: some View { SettingsPage("SignInScreen") { NoteText(text: "Not built yet.") } }
}

enum AccountDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
