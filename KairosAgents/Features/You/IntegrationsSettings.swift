import SwiftUI

struct IntegrationsScreen: View {
    var body: some View { SettingsPage("IntegrationsScreen") { NoteText(text: "Not built yet.") } }
}

struct IntegrationDetailScreen: View {
    let integrationID: String
    var body: some View { SettingsPage("IntegrationDetailScreen") { NoteText(text: "Not built yet.") } }
}

struct AddIntegrationScreen: View {
    let kind: String
    var body: some View { SettingsPage("AddIntegrationScreen") { NoteText(text: "Not built yet.") } }
}

struct MCPCatalogScreen: View {
    var body: some View { SettingsPage("MCPCatalogScreen") { NoteText(text: "Not built yet.") } }
}

struct GoogleScreen: View {
    var body: some View { SettingsPage("GoogleScreen") { NoteText(text: "Not built yet.") } }
}

struct ImageGenerationScreen: View {
    var body: some View { SettingsPage("ImageGenerationScreen") { NoteText(text: "Not built yet.") } }
}

enum IntegrationsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
