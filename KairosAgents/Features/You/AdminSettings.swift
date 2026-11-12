import SwiftUI

struct UsersScreen: View {
    var body: some View { SettingsPage("UsersScreen") { NoteText(text: "Not built yet.") } }
}

struct LogsScreen: View {
    var body: some View { SettingsPage("LogsScreen") { NoteText(text: "Not built yet.") } }
}

struct RunsScreen: View {
    var body: some View { SettingsPage("RunsScreen") { NoteText(text: "Not built yet.") } }
}

struct SandboxScreen: View {
    var body: some View { SettingsPage("SandboxScreen") { NoteText(text: "Not built yet.") } }
}

struct CheckpointsScreen: View {
    var body: some View { SettingsPage("CheckpointsScreen") { NoteText(text: "Not built yet.") } }
}

struct HooksScreen: View {
    var body: some View { SettingsPage("HooksScreen") { NoteText(text: "Not built yet.") } }
}

struct HookDetailScreen: View {
    let hookID: String
    var body: some View { SettingsPage("HookDetailScreen") { NoteText(text: "Not built yet.") } }
}

struct HookEditScreen: View {
    let hookID: String
    var body: some View { SettingsPage("HookEditScreen") { NoteText(text: "Not built yet.") } }
}

struct SystemScreen: View {
    var body: some View { SettingsPage("SystemScreen") { NoteText(text: "Not built yet.") } }
}

struct ShortcutsScreen: View {
    var body: some View { SettingsPage("ShortcutsScreen") { NoteText(text: "Not built yet.") } }
}

enum AdminDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
