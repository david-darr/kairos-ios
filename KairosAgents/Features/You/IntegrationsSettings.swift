import SwiftUI
import UIKit

// Integrations (calendars, contacts, feeds, services and tool servers), the tool server catalog,
// Google accounts and the image connection. All on made-up sample data shared through
// `IntegrationsSample.shared`, so the desktop data can replace it later.

// MARK: - Sample data

nonisolated enum IntegrationKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case api, caldav, ical, carddav, email, mcp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .api: "API service"
        case .caldav: "CalDAV calendar"
        case .ical: "iCal feed"
        case .carddav: "Contacts (CardDAV)"
        case .email: "Email (IMAP/SMTP)"
        case .mcp: "MCP tool server"
        }
    }

    var symbol: String {
        switch self {
        case .api: "network"
        case .caldav: "calendar"
        case .ical: "link"
        case .carddav: "person.2"
        case .email: "envelope"
        case .mcp: "puzzlepiece.extension"
        }
    }

    /// Calendars, contacts and feeds sync one way into Kairos.
    var syncs: Bool { self == .caldav || self == .carddav || self == .ical }
}

nonisolated struct IntegrationItem: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var kind: IntegrationKind
    var address: String
    var connected: Bool
    /// A tool server with its own browser sign-in.
    var signIn = false
    /// A tool server that runs as a command on the desktop.
    var local = false
    var lastSync: String? = nil
    var catalogID: String? = nil
    var isGitHub = false

    var stateText: String {
        connected ? (signIn ? "Signed in" : "Connected") : (signIn ? "Needs sign-in" : "Not connected")
    }
}

nonisolated struct IntegrationContact: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var email: String
    var phone: String
}

nonisolated struct IntegrationCatalogServer: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var about: String
    var signIn: Bool
    var docs: String
}

nonisolated struct IntegrationGoogleAccount: Identifiable, Hashable, Sendable {
    let id: String
    var alias: String
    var email: String
    var gmail: Bool
    var calendar: Bool
    var drive: Bool
    var needsReconnect: Bool

    var label: String { alias.isEmpty ? email : alias }
}

nonisolated enum IntegrationFilter: String, CaseIterable, Hashable, Sendable {
    case all, connected, notConnected

    var title: String {
        switch self {
        case .all: "All"
        case .connected: "Connected"
        case .notConnected: "Not connected"
        }
    }
}

nonisolated enum IntegrationSampleData {
    static let items: [IntegrationItem] = [
        IntegrationItem(id: "i-cal", name: "Shop calendar", kind: .caldav, address: "https://dav.example.com/calendars/shop/", connected: true, lastSync: "Today, 9:40"),
        IntegrationItem(id: "i-contacts", name: "Shop contacts", kind: .carddav, address: "https://dav.example.com/contacts/shop/", connected: true, lastSync: "Today, 9:40"),
        IntegrationItem(id: "i-holidays", name: "Public holidays", kind: .ical, address: "webcal://example.com/holidays.ics", connected: true, lastSync: "Yesterday"),
        IntegrationItem(id: "i-deliveries", name: "Supplier deliveries", kind: .ical, address: "https://example.com/deliveries.ics", connected: false),
        IntegrationItem(id: "i-weather", name: "Weather service", kind: .api, address: "https://api.example.com/weather", connected: true),
        IntegrationItem(id: "i-docs", name: "Docs lookup", kind: .mcp, address: "https://mcp.example.com/docs", connected: true, catalogID: "docs"),
        IntegrationItem(id: "i-tracker", name: "Project tracker", kind: .mcp, address: "https://mcp.example.com/tracker", connected: false, signIn: true, catalogID: "tracker"),
        IntegrationItem(id: "i-files", name: "File tools", kind: .mcp, address: "npx @example/file-tools", connected: true, local: true),
    ]

    static let contacts: [IntegrationContact] = [
        IntegrationContact(id: "k1", name: "Jordan Lee", email: "jordan@example.com", phone: "555-0142"),
        IntegrationContact(id: "k2", name: "Parts supplier", email: "orders@example.com", phone: "555-0187"),
        IntegrationContact(id: "k3", name: "Riley Park", email: "riley@example.com", phone: "555-0120"),
    ]

    static let catalog: [IntegrationCatalogServer] = [
        IntegrationCatalogServer(id: "docs", name: "Docs lookup", about: "Up-to-date documentation for code libraries.", signIn: false, docs: "https://example.com/docs/docs-lookup"),
        IntegrationCatalogServer(id: "fetch", name: "Fetch", about: "Read a web page as clean text.", signIn: false, docs: "https://example.com/docs/fetch"),
        IntegrationCatalogServer(id: "time", name: "Time", about: "The current time and time zone conversions.", signIn: false, docs: "https://example.com/docs/time"),
        IntegrationCatalogServer(id: "maps", name: "Maps", about: "Places, directions and travel times.", signIn: false, docs: "https://example.com/docs/maps"),
        IntegrationCatalogServer(id: "rea", name: "REA", about: "Pick it in each chat or Forge session. Codex reaches it through Kairos's bridge.", signIn: false, docs: "https://example.com/docs/rea"),
        IntegrationCatalogServer(id: "tracker", name: "Project tracker", about: "Issues and projects from your tracker.", signIn: true, docs: "https://example.com/docs/tracker"),
        IntegrationCatalogServer(id: "design", name: "Design files", about: "Read and comment on design files.", signIn: true, docs: "https://example.com/docs/design"),
        IntegrationCatalogServer(id: "chat", name: "Team chat", about: "Search and post in team chat channels.", signIn: true, docs: "https://example.com/docs/team-chat"),
    ]

    static let googleAccounts: [IntegrationGoogleAccount] = [
        IntegrationGoogleAccount(id: "g-work", alias: "Shop", email: "sam.shop@example.com", gmail: true, calendar: true, drive: true, needsReconnect: false),
        IntegrationGoogleAccount(id: "g-home", alias: "Home", email: "sam@example.com", gmail: true, calendar: true, drive: false, needsReconnect: true),
    ]
}

/// The integrations every screen here shares. The desktop connection fills this in later.
@Observable
final class IntegrationsSample {
    static let shared = IntegrationsSample()

    var items: [IntegrationItem] = IntegrationSampleData.items
    var contacts: [IntegrationContact] = IntegrationSampleData.contacts
    var catalog: [IntegrationCatalogServer] = IntegrationSampleData.catalog
    var googleAccounts: [IntegrationGoogleAccount] = IntegrationSampleData.googleAccounts
    /// The list's search and filter stay put while you come and go.
    var query = ""
    var filter: IntegrationFilter = .all

    var githubAdded: Bool { items.contains { $0.isGitHub } }

    func item(_ id: String) -> IntegrationItem? { items.first { $0.id == id } }

    func isAdded(_ server: IntegrationCatalogServer) -> Bool { items.contains { $0.catalogID == server.id } }

    func newID() -> String { "i-\(UUID().uuidString.prefix(6))" }

    func add(_ item: IntegrationItem) {
        withAnimation(Motion.snappy) { items.append(item) }
    }

    func remove(_ id: String) {
        withAnimation(Motion.snappy) { items.removeAll { $0.id == id } }
    }

    func update(_ id: String, _ change: (inout IntegrationItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.snappy) { change(&items[index]) }
    }

    func updateGoogle(_ id: String, _ change: (inout IntegrationGoogleAccount) -> Void) {
        guard let index = googleAccounts.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.snappy) { change(&googleAccounts[index]) }
    }
}

// MARK: - Small pieces

/// A problem with a form, in the danger colour.
private struct IntegrationErrorLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(KFont.ui(14.5, .medium, relativeTo: .footnote))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.danger)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}

/// A spinner and a short line, for things that are under way.
private struct IntegrationBusyLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Palette.goldText)
            Text(text)
                .font(KFont.ui(14, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .lineLimit(1)
        }
        .frame(minHeight: 44)
    }
}

/// One integration in the list: its name, kind and state, opening its page.
private struct IntegrationListRow: View {
    let item: IntegrationItem

    var body: some View {
        NavigationLink(value: YouRoute.integration(item.id)) {
            HStack(spacing: 8) {
                RowLabel(title: item.name, detail: item.kind.label, symbol: item.kind.symbol)
                StatusPill(text: item.stateText, tone: item.connected ? .ok : .muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
    }
}

// MARK: - Integrations

struct IntegrationsScreen: View {
    private let store = IntegrationsSample.shared
    @State private var addKind: IntegrationKind?
    @State private var githubOpen: Bool
    @State private var githubToken = ""
    @State private var githubError: String?
    @State private var githubSaving = false
    private let startEmpty: Bool
    private let startQuery: String

    init(startEmpty: Bool = false, startQuery: String = "", githubOpen: Bool = false) {
        self.startEmpty = startEmpty
        self.startQuery = startQuery
        _githubOpen = State(initialValue: githubOpen)
    }

    private var filtered: [IntegrationItem] {
        let query = store.query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.items.filter { item in
            if !query.isEmpty && !item.name.lowercased().contains(query) { return false }
            switch store.filter {
            case .all: return true
            case .connected: return item.connected
            case .notConnected: return !item.connected
            }
        }
    }

    var body: some View {
        SettingsPage("Integrations", subtitle: "Calendars, contacts, services and tool servers your chats can use.") {
            addMenu
        } content: {
            if !store.githubAdded {
                githubGroup.arrives(0)
            }

            VStack(alignment: .leading, spacing: 10) {
                SearchField(prompt: "Search integrations", text: Binding(get: { store.query }, set: { store.query = $0 }))
                ChipPicker(items: IntegrationFilter.allCases, selection: Binding(get: { store.filter }, set: { store.filter = $0 })) { $0.title }
            }
            .arrives(1)

            SettingsGroup("Your integrations", footer: "Add one with the plus button at the top.") {
                if store.items.isEmpty {
                    EmptyRow(text: "No integrations yet. Add one, or pick a server from the catalog.")
                } else if filtered.isEmpty {
                    EmptyRow(text: "No integrations match.")
                } else {
                    ForEach(filtered) { item in
                        IntegrationListRow(item: item)
                    }
                }
            }
            .arrives(2)

            SettingsGroup("More") {
                NavRow(title: "MCP catalog", detail: "Known tool servers, added in one step", symbol: "square.grid.2x2", value: "\(store.catalog.count)", to: .mcpCatalog)
                NavRow(title: "Google accounts", detail: "Gmail, Calendar and Drive", symbol: "person.crop.circle", value: "\(store.googleAccounts.count)", to: .google)
                NavRow(title: "Image generation", detail: "Your own image key for designs", symbol: "photo", to: .images)
            }
            .arrives(3)
        }
        .navigationDestination(item: $addKind) { kind in
            AddIntegrationScreen(kind: kind.rawValue)
        }
        .onAppear {
            if startEmpty { store.items.removeAll() }
            if !startQuery.isEmpty { store.query = startQuery }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(IntegrationKind.allCases) { kind in
                Button {
                    Haptics.tap()
                    addKind = kind
                } label: {
                    Label(kind.label, systemImage: kind.symbol)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .kGlass(Circle(), interactive: true)
        .accessibilityLabel("Add integration")
    }

    private var githubGroup: some View {
        SettingsGroup("Popular") {
            HStack(spacing: 8) {
                RowLabel(title: "GitHub", detail: "GitHub's remote tool server. It needs a personal access token: GitHub Settings, Developer settings, Personal access tokens.", symbol: "puzzlepiece.extension")
                if !githubOpen {
                    PillButton(title: "Connect", prominent: true) {
                        withAnimation(Motion.snappy) { githubOpen = true }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            if githubOpen {
                FieldRow(title: "Personal access token", text: $githubToken, prompt: "Paste the token", secure: true)
                if let githubError {
                    IntegrationErrorLine(text: githubError)
                }
                RowButtons {
                    PillButton(title: "Cancel") {
                        withAnimation(Motion.snappy) {
                            githubOpen = false
                            githubToken = ""
                            githubError = nil
                        }
                    }
                    if githubSaving {
                        IntegrationBusyLabel(text: "Saving...")
                    } else {
                        PillButton(title: "Save", prominent: true) { saveGitHub() }
                    }
                }
            }
        }
    }

    private func saveGitHub() {
        guard !githubSaving else { return }
        guard !githubToken.trimmingCharacters(in: .whitespaces).isEmpty else {
            Haptics.thud()
            withAnimation(Motion.snappy) { githubError = "A token is required." }
            return
        }
        githubError = nil
        githubSaving = true
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            store.add(IntegrationItem(id: store.newID(), name: "GitHub", kind: .mcp, address: "GitHub's remote tool server", connected: true, isGitHub: true))
            githubSaving = false
            githubToken = ""
            githubOpen = false
            Haptics.success()
            YouStore.shared.say("GitHub added.")
        }
    }
}

// MARK: - One integration

struct IntegrationDetailScreen: View {
    let integrationID: String
    private let store = IntegrationsSample.shared
    @Environment(\.dismiss) private var dismiss
    @State private var signingIn: Bool
    @State private var syncing = false
    @State private var confirmRemove = false

    init(integrationID: String, startSigningIn: Bool = false) {
        self.integrationID = integrationID
        _signingIn = State(initialValue: startSigningIn)
    }

    var body: some View {
        if let item = store.item(integrationID) {
            page(item)
        } else {
            SettingsPage("Integration") {
                SettingsGroup {
                    EmptyRow(text: "This integration was removed.")
                }
            }
        }
    }

    private func page(_ item: IntegrationItem) -> some View {
        SettingsPage(item.name, subtitle: item.kind.label) {
            SettingsGroup("Details") {
                StatusRow(title: "State", symbol: item.kind.symbol, status: item.stateText, tone: item.connected ? .ok : .muted)
                ValueRow(title: item.local ? "Command" : "Address", value: item.address)
                if item.kind == .mcp {
                    ValueRow(title: "Runs", value: item.local ? "On the desktop" : "Remote")
                }
                if item.kind.syncs {
                    ValueRow(title: "Last sync", value: item.lastSync ?? "Not yet")
                }
            }
            .arrives(0)

            if item.signIn {
                SettingsGroup("Sign-in", footer: "Sign-in opens in the browser on your desktop, so finish it there. Kairos waits up to five minutes.") {
                    if signingIn {
                        HStack(spacing: 8) {
                            IntegrationBusyLabel(text: "Waiting for sign-in...")
                            Spacer(minLength: 0)
                            PillButton(title: "Cancel") {
                                withAnimation(Motion.snappy) { signingIn = false }
                                YouStore.shared.say("Sign-in did not finish.")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    } else {
                        ActionRow(title: item.connected ? "Sign in again" : "Sign in", symbol: "person.crop.circle", tone: .gold) { signIn(item) }
                        if item.connected {
                            ActionRow(title: "Sign out", symbol: "xmark") { signOut(item) }
                        }
                    }
                }
                .arrives(1)
            }

            if item.kind.syncs {
                SettingsGroup("Sync", footer: "One-way read sync into Kairos. Nothing is written back.") {
                    ActionRow(title: syncing ? "Syncing..." : "Sync now", symbol: "arrow.clockwise", tone: .gold) { sync(item) }
                }
                .arrives(2)
            }

            if item.kind == .carddav {
                SettingsGroup("Synced contacts", footer: "There is no Contacts tab yet, so they are listed here.") {
                    if store.contacts.isEmpty {
                        EmptyRow(text: "No contacts synced yet.")
                    } else {
                        ForEach(store.contacts) { contact in
                            RowLabel(title: contact.name, detail: "\(contact.email) · \(contact.phone)", symbol: "person.crop.circle")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(minHeight: 52)
                                .accessibilityElement(children: .combine)
                        }
                    }
                }
                .arrives(3)
            }

            SettingsGroup(footer: "Removing it disconnects it and deletes its stored credentials.") {
                ActionRow(title: "Remove integration", symbol: "trash", tone: .danger) { confirmRemove = true }
            }
            .arrives(4)
        }
        .confirmationDialog("Remove this integration?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove integration", role: .destructive) { remove(item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(item.name)\" will be disconnected and its stored credentials deleted.")
        }
    }

    private func signIn(_ item: IntegrationItem) {
        guard !signingIn else { return }
        withAnimation(Motion.snappy) { signingIn = true }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard signingIn else { return }
            store.update(item.id) { $0.connected = true }
            withAnimation(Motion.snappy) { signingIn = false }
            Haptics.success()
            YouStore.shared.say("Signed in to \(item.name).")
        }
    }

    private func signOut(_ item: IntegrationItem) {
        store.update(item.id) { $0.connected = false }
        Haptics.success()
        YouStore.shared.say("Signed out of \(item.name).")
    }

    private func sync(_ item: IntegrationItem) {
        guard !syncing else { return }
        syncing = true
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            store.update(item.id) {
                $0.lastSync = "Just now"
                $0.connected = true
            }
            syncing = false
            Haptics.success()
            YouStore.shared.say("\(item.name) synced.")
        }
    }

    private func remove(_ item: IntegrationItem) {
        store.remove(item.id)
        Haptics.success()
        YouStore.shared.say("Integration removed.")
        dismiss()
    }
}

// MARK: - Adding one

nonisolated enum IntegrationMCPType: String, CaseIterable, Hashable, Sendable {
    case local, remote

    var title: String {
        switch self {
        case .local: "Local command"
        case .remote: "Remote URL"
        }
    }
}

struct AddIntegrationScreen: View {
    let kind: String
    private let store = IntegrationsSample.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var key = ""
    @State private var command = ""
    @State private var mcpType: IntegrationMCPType
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var smtpHost = ""
    @State private var smtpPort = "465"
    @State private var problem: String?
    @State private var submitting = false

    init(kind: String, remote: Bool = false, showProblem: Bool = false) {
        self.kind = kind
        _mcpType = State(initialValue: remote ? .remote : .local)
        _problem = State(initialValue: showProblem ? Self.emptyProblem(IntegrationKind(rawValue: kind) ?? .api) : nil)
    }

    private var resolved: IntegrationKind { IntegrationKind(rawValue: kind) ?? .api }

    private var title: String {
        switch resolved {
        case .api: "Add an API service"
        case .caldav: "Add a CalDAV calendar"
        case .ical: "Add an iCal feed"
        case .carddav: "Add contacts (CardDAV)"
        case .email: "Add an email account"
        case .mcp: "Add an MCP tool server"
        }
    }

    private var subtitle: String {
        switch resolved {
        case .api: "A web service your chats can call."
        case .caldav: "A calendar that syncs into Kairos."
        case .ical: "A single .ics subscription address."
        case .carddav: "An address book that syncs into Kairos."
        case .email: "A mailbox Kairos can read and send from."
        case .mcp: "A tool server that widens what the models can do."
        }
    }

    private var footer: String {
        switch resolved {
        case .api:
            return "The key is optional, saved encrypted and never shown again."
        case .caldav, .carddav:
            return "One-way read sync into Kairos, nothing written back. Use a specific collection address, not the server root."
        case .ical:
            return "For example a calendar's secret iCal address or a shared calendar link. One-way read sync."
        case .email:
            return "The account also shows in Mail. The password is saved encrypted and never shown again."
        case .mcp:
            return mcpType == .local
                ? "A local command runs on your desktop, not on this phone. Open chats pick up a change on their next message."
                : "Open chats pick up a change on their next message. If the server needs a sign-in, start it from its page after adding."
        }
    }

    private var submitLabel: String { resolved.syncs ? "Add and sync" : "Add" }

    var body: some View {
        SettingsPage(title, subtitle: subtitle) {
            SettingsGroup(footer: footer) {
                fields
            }
            .arrives(0)

            if let problem {
                IntegrationErrorLine(text: problem)
                    .padding(.horizontal, -12)
            }

            VStack(spacing: 6) {
                GoldButton(title: submitting ? (resolved.syncs ? "Syncing..." : "Adding...") : submitLabel) { submit() }
                    .opacity(submitting ? 0.7 : 1)
                QuietButton(title: "Cancel") { dismiss() }
            }
            .arrives(1)
        }
    }

    @ViewBuilder private var fields: some View {
        switch resolved {
        case .api:
            FieldRow(title: "Name", text: $name, prompt: "Weather service")
            FieldRow(title: "Base URL", text: $url, prompt: "https://api.example.com", keyboard: .URL)
            FieldRow(title: "API key", text: $key, prompt: "Optional", secure: true)
        case .caldav, .carddav:
            FieldRow(title: "Name", text: $name, prompt: resolved == .caldav ? "Shop calendar" : "Shop contacts")
            FieldRow(title: "URL", text: $url, prompt: resolved == .caldav ? "Calendar collection URL" : "Address book collection URL", keyboard: .URL)
            FieldRow(title: "Username", text: $username, prompt: "Username")
            FieldRow(title: "Password", text: $password, prompt: "Password", secure: true)
        case .ical:
            FieldRow(title: "Name", text: $name, prompt: "Public holidays")
            FieldRow(title: "Feed URL", text: $url, prompt: "https://... or webcal://... .ics address", keyboard: .URL)
            FieldRow(title: "Username", text: $username, prompt: "Only if the feed needs it")
            FieldRow(title: "Password", text: $password, prompt: "Optional", secure: true)
        case .email:
            FieldRow(title: "Email address", text: $name, prompt: "shop@example.com", keyboard: .emailAddress)
            FieldRow(title: "Password", text: $password, prompt: "Password or app password", secure: true)
            FieldRow(title: "IMAP server", text: $imapHost, prompt: "imap.example.com", keyboard: .URL)
            FieldRow(title: "IMAP port", text: $imapPort, prompt: "993", keyboard: .numberPad)
            FieldRow(title: "SMTP server", text: $smtpHost, prompt: "smtp.example.com", keyboard: .URL)
            FieldRow(title: "SMTP port", text: $smtpPort, prompt: "465", keyboard: .numberPad)
        case .mcp:
            FieldRow(title: "Name", text: $name, prompt: "File tools")
            PickRow(title: "Type", selection: $mcpType, options: IntegrationMCPType.allCases) { $0.title }
            if mcpType == .local {
                FieldRow(title: "Command", text: $command, prompt: "npx @scope/server")
            } else {
                FieldRow(title: "URL", text: $url, prompt: "https://example.com/mcp", keyboard: .URL)
            }
            FieldRow(title: "Auth token", text: $key, prompt: "Optional", secure: true)
        }
    }

    private static func emptyProblem(_ kind: IntegrationKind) -> String {
        switch kind {
        case .api, .ical: "Name and URL are required."
        case .caldav, .carddav: "All fields are required."
        case .email: "Enter the email address and password."
        case .mcp: "Name is required."
        }
    }

    private func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    private func validate() -> String? {
        switch resolved {
        case .api, .ical:
            return blank(name) || blank(url) ? "Name and URL are required." : nil
        case .caldav, .carddav:
            return blank(name) || blank(url) || blank(username) || password.isEmpty ? "All fields are required." : nil
        case .email:
            if blank(name) || password.isEmpty { return "Enter the email address and password." }
            if blank(imapHost) || blank(smtpHost) { return "Enter the IMAP and SMTP servers." }
            if Int(imapPort) == nil || Int(smtpPort) == nil { return "Ports are numbers, like 993 and 465." }
            return nil
        case .mcp:
            if blank(name) { return "Name is required." }
            if mcpType == .local && blank(command) { return "A command is required for a local server." }
            if mcpType == .remote && blank(url) { return "A URL is required for a remote server." }
            return nil
        }
    }

    private func makeItem() -> IntegrationItem {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let address: String
        switch resolved {
        case .email: address = imapHost.trimmingCharacters(in: .whitespaces)
        case .mcp: address = mcpType == .local ? command.trimmingCharacters(in: .whitespaces) : url.trimmingCharacters(in: .whitespaces)
        default: address = url.trimmingCharacters(in: .whitespaces)
        }
        return IntegrationItem(id: store.newID(), name: trimmed, kind: resolved, address: address, connected: true,
                               local: resolved == .mcp && mcpType == .local,
                               lastSync: resolved.syncs ? "Just now" : nil)
    }

    private func submit() {
        guard !submitting else { return }
        if let message = validate() {
            Haptics.thud()
            withAnimation(Motion.snappy) { problem = message }
            return
        }
        withAnimation(Motion.snappy) { problem = nil }
        submitting = true
        Task {
            try? await Task.sleep(for: .seconds(resolved.syncs ? 1.4 : 0.8))
            let item = makeItem()
            store.add(item)
            submitting = false
            Haptics.success()
            YouStore.shared.say(resolved.syncs ? "\(item.name) added and synced." : "\(item.name) added.")
            dismiss()
        }
    }
}

// MARK: - Catalog

struct MCPCatalogScreen: View {
    private let store = IntegrationsSample.shared
    @Environment(\.openURL) private var openURL
    @State private var query: String
    @State private var pending: Set<String> = []
    @State private var waiting: Set<String> = []

    init(startQuery: String = "") {
        _query = State(initialValue: startQuery)
    }

    private var shown: [IntegrationCatalogServer] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.catalog
            .filter { text.isEmpty || "\($0.name) \($0.about)".lowercased().contains(text) }
            .sorted { first, second in
                if first.signIn != second.signIn { return !first.signIn }
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
    }

    var body: some View {
        SettingsPage("MCP catalog", subtitle: "\(store.catalog.count) known tool servers. The ones without a sign-in come first.") {
            SearchField(prompt: "Search servers", text: $query)
                .arrives(0)

            NoteText(text: "Added tool servers work in chats. Claude uses them directly, and local and API models use them through Kairos. Codex can use REA through Kairos's bridge; pick REA in each chat or Forge session. Tool calls follow the chat's permission mode.", symbol: "info.circle")
                .arrives(1)

            SettingsGroup("Servers", footer: "Docs opens a server's documentation. A sign-in, when a server needs one, opens in the browser on your desktop.") {
                if shown.isEmpty {
                    EmptyRow(text: "No server matches.")
                } else {
                    ForEach(shown) { server in
                        serverRow(server)
                    }
                }
            }
            .arrives(2)
        }
    }

    private func serverRow(_ server: IntegrationCatalogServer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(server.name)
                    .font(KFont.ui(16, .medium))
                    .foregroundStyle(Palette.ink)
                StatusPill(text: server.signIn ? "Needs sign-in" : "No sign-in", tone: .muted)
            }
            Text(server.about)
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                PillButton(title: "Docs", symbol: "doc.text") {
                    if let link = URL(string: server.docs) { openURL(link) }
                }
                Spacer(minLength: 0)
                action(for: server)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private func action(for server: IntegrationCatalogServer) -> some View {
        if waiting.contains(server.id) {
            IntegrationBusyLabel(text: "Waiting for sign-in...")
        } else if pending.contains(server.id) {
            IntegrationBusyLabel(text: "Adding...")
        } else if store.isAdded(server) {
            StatusPill(text: "Added", tone: .ok)
        } else {
            PillButton(title: server.signIn ? "Add and sign in" : "Add", prominent: true) { add(server) }
        }
    }

    private func add(_ server: IntegrationCatalogServer) {
        guard !pending.contains(server.id) else { return }
        pending.insert(server.id)
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            let id = store.newID()
            store.add(IntegrationItem(id: id, name: server.name, kind: .mcp, address: "https://mcp.example.com/\(server.id)",
                                      connected: !server.signIn, signIn: server.signIn, catalogID: server.id))
            pending.remove(server.id)
            guard server.signIn else {
                Haptics.success()
                YouStore.shared.say("\(server.name) added.")
                return
            }
            waiting.insert(server.id)
            try? await Task.sleep(for: .seconds(2.6))
            store.update(id) { $0.connected = true }
            withAnimation(Motion.snappy) { _ = waiting.remove(server.id) }
            Haptics.success()
            YouStore.shared.say("Signed in to \(server.name).")
        }
    }
}

// MARK: - Google

struct GoogleScreen: View {
    private let store = IntegrationsSample.shared
    @State private var aliasDrafts: [String: String] = [:]
    @State private var reconnecting: Set<String> = []
    @State private var disconnectTarget: IntegrationGoogleAccount?
    @State private var adding: Bool
    private let startWaiting: Bool

    init(startAdding: Bool = false, startWaiting: Bool = false) {
        _adding = State(initialValue: startAdding || startWaiting)
        self.startWaiting = startWaiting
    }

    var body: some View {
        SettingsPage("Integrations and Google", subtitle: "Google accounts your bots can use for Gmail, Calendar and Drive.") {
            if store.googleAccounts.isEmpty {
                SettingsGroup {
                    EmptyRow(text: "No Google account is connected.")
                }
            }

            ForEach(Array(store.googleAccounts.enumerated()), id: \.element.id) { index, account in
                accountGroup(account)
                    .arrives(index)
            }

            SettingsGroup(footer: "Give each account an alias so a bot can tell them apart. Each bot gets only the accounts you choose in its Access settings.") {
                ActionRow(title: "Add another account", symbol: "plus", tone: .gold) { adding = true }
            }
            .arrives(store.googleAccounts.count)
        }
        .sheet(isPresented: $adding) {
            GoogleAddAccountSheet(holdWaiting: startWaiting)
        }
        .confirmationDialog(disconnectTarget.map { "Disconnect \($0.label)?" } ?? "Disconnect?",
                            isPresented: Binding(get: { disconnectTarget != nil }, set: { if !$0 { disconnectTarget = nil } }),
                            titleVisibility: .visible, presenting: disconnectTarget) { account in
            Button("Disconnect", role: .destructive) { disconnect(account) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Bots lose access to this account. You can connect it again later.")
        }
    }

    private func accountGroup(_ account: IntegrationGoogleAccount) -> some View {
        SettingsGroup(account.label) {
            StatusRow(title: account.email, detail: "Google account", symbol: "person.crop.circle",
                      status: account.needsReconnect ? "Reconnect" : "Connected", tone: account.needsReconnect ? .warn : .ok)
            HStack(spacing: 4) {
                FieldRow(title: "Alias", text: Binding(get: { aliasDrafts[account.id] ?? account.alias }, set: { aliasDrafts[account.id] = $0 }), prompt: "Shop, Home ...")
                PillButton(title: "Save") { saveAlias(account) }
                    .padding(.trailing, 12)
            }
            StatusRow(title: "Gmail", symbol: "envelope", status: serviceText(account.gmail, account), tone: serviceTone(account.gmail, account))
            StatusRow(title: "Calendar", symbol: "calendar", status: serviceText(account.calendar, account), tone: serviceTone(account.calendar, account))
            StatusRow(title: "Drive", symbol: "externaldrive", status: serviceText(account.drive, account), tone: serviceTone(account.drive, account))
            RowButtons {
                if reconnecting.contains(account.id) {
                    IntegrationBusyLabel(text: "Finish on your desktop...")
                } else if account.needsReconnect {
                    PillButton(title: "Reconnect", symbol: "arrow.clockwise", prominent: true) { reconnect(account) }
                }
                PillButton(title: "Disconnect", danger: true) { disconnectTarget = account }
            }
        }
    }

    private func serviceText(_ on: Bool, _ account: IntegrationGoogleAccount) -> String {
        if !on { return "Not allowed" }
        return account.needsReconnect ? "Paused" : "On"
    }

    private func serviceTone(_ on: Bool, _ account: IntegrationGoogleAccount) -> StatusPill.Tone {
        if !on { return .muted }
        return account.needsReconnect ? .warn : .ok
    }

    private func saveAlias(_ account: IntegrationGoogleAccount) {
        let alias = (aliasDrafts[account.id] ?? account.alias).trimmingCharacters(in: .whitespaces)
        guard !alias.isEmpty else {
            Haptics.thud()
            YouStore.shared.say("Type an alias first.")
            return
        }
        store.updateGoogle(account.id) { $0.alias = alias }
        aliasDrafts[account.id] = nil
        Haptics.success()
        YouStore.shared.say("Alias saved.")
    }

    private func reconnect(_ account: IntegrationGoogleAccount) {
        guard !reconnecting.contains(account.id) else { return }
        reconnecting.insert(account.id)
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            store.updateGoogle(account.id) {
                $0.needsReconnect = false
                $0.drive = true
            }
            reconnecting.remove(account.id)
            Haptics.success()
            YouStore.shared.say("\(account.label) reconnected.")
        }
    }

    private func disconnect(_ account: IntegrationGoogleAccount) {
        withAnimation(Motion.snappy) { store.googleAccounts.removeAll { $0.id == account.id } }
        Haptics.success()
        YouStore.shared.say("Disconnected.")
    }
}

/// Add another Google account: an alias first, then the sign-in finishes in the desktop's browser.
private struct GoogleAddAccountSheet: View {
    let holdWaiting: Bool
    private let store = IntegrationsSample.shared
    @Environment(\.dismiss) private var dismiss
    @State private var alias: String
    @State private var waiting: Bool
    @State private var problem: String?

    init(holdWaiting: Bool) {
        self.holdWaiting = holdWaiting
        _alias = State(initialValue: holdWaiting ? "Bike club" : "")
        _waiting = State(initialValue: holdWaiting)
    }

    var body: some View {
        FittedSheet(estimate: 420) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add another account")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)

                if waiting {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Palette.goldText)
                        Text("Finish signing in on your desktop")
                            .font(KFont.ui(18, .semibold, relativeTo: .headline))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.center)
                        Text("Google's sign-in page opened in the browser on your desktop. This finishes on its own once you are done there.")
                            .font(KFont.ui(15, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkDim)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                    QuietButton(title: "Cancel") { dismiss() }
                } else {
                    Text("Give it an alias first, so a bot can tell your accounts apart.")
                        .font(KFont.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 0) {
                        FieldRow(title: "Alias", text: $alias, prompt: "Bike club")
                    }
                    .kCard(radius: 22)
                    if let problem {
                        IntegrationErrorLine(text: problem)
                    }
                    GoldButton(title: "Continue") { start() }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .task(id: waiting) {
            guard waiting, !holdWaiting else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func start() {
        guard !alias.trimmingCharacters(in: .whitespaces).isEmpty else {
            Haptics.thud()
            withAnimation(Motion.snappy) { problem = "Type an alias first." }
            return
        }
        problem = nil
        Haptics.tap()
        withAnimation(Motion.snappy) { waiting = true }
    }

    private func finish() {
        let name = alias.trimmingCharacters(in: .whitespaces)
        let handle = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let account = IntegrationGoogleAccount(id: "g-\(UUID().uuidString.prefix(6))", alias: name,
                                               email: "\(handle.isEmpty ? "account" : handle)@example.com",
                                               gmail: true, calendar: true, drive: true, needsReconnect: false)
        withAnimation(Motion.snappy) { store.googleAccounts.append(account) }
        Haptics.success()
        YouStore.shared.say("\(name) connected.")
        dismiss()
    }
}

// MARK: - Image generation

nonisolated enum IntegrationImageProvider: String, CaseIterable, Hashable, Sendable {
    case openai, xai, compatible

    var title: String {
        switch self {
        case .openai: "OpenAI"
        case .xai: "xAI"
        case .compatible: "Compatible server"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: "gpt-image-1"
        case .xai: "grok-2-image"
        case .compatible: ""
        }
    }
}

struct ImageGenerationScreen: View {
    @State private var configured: Bool
    @State private var savedProvider: IntegrationImageProvider
    @State private var savedModel: String
    @State private var savedAddress: String
    @State private var savedLimit = 50
    @State private var provider: IntegrationImageProvider
    @State private var key = ""
    @State private var address: String
    @State private var model: String
    @State private var limit = 50
    @State private var usedToday = 12
    @State private var result: String?
    @State private var saving = false
    @State private var testing = false
    @State private var confirmRemove = false

    init(connected: Bool = true, compatible: Bool = false) {
        let start: IntegrationImageProvider = compatible ? .compatible : .openai
        let startModel = compatible ? "flux-schnell" : start.defaultModel
        let startAddress = compatible ? "https://images.example.com/v1" : ""
        _configured = State(initialValue: connected)
        _savedProvider = State(initialValue: start)
        _savedModel = State(initialValue: startModel)
        _savedAddress = State(initialValue: startAddress)
        _provider = State(initialValue: start)
        _model = State(initialValue: startModel)
        _address = State(initialValue: startAddress)
    }

    private var statusLine: String {
        guard configured else {
            return "Not connected. Designs use openly licensed photos, your own photos and patterns instead."
        }
        let usage = savedLimit > 0 ? "\(usedToday) of \(savedLimit) images today." : "\(usedToday) images today. No daily limit."
        return "Connected: \(savedProvider.title), \(savedModel). \(usage)"
    }

    var body: some View {
        SettingsPage("Image generation", subtitle: "Your own image key, so designs can make new pictures.") {
            SettingsGroup {
                StatusRow(title: configured ? "Connected" : "Not connected", detail: statusLine, symbol: "photo",
                          status: configured ? "On" : "Off", tone: configured ? .ok : .muted)
            }
            .arrives(0)

            SettingsGroup("Image connection", footer: "A daily limit of 0 turns the limit off.") {
                PickRow(title: "Provider", selection: $provider, options: IntegrationImageProvider.allCases) { $0.title }
                FieldRow(title: "Key", text: $key, prompt: configured ? "Saved. Paste a new key to replace it" : "Paste the key", secure: true)
                if provider == .compatible {
                    FieldRow(title: "Address", text: $address, prompt: "https://images.example.com/v1", keyboard: .URL)
                }
                FieldRow(title: "Model", text: $model, prompt: provider.defaultModel.isEmpty ? "Model name" : provider.defaultModel)
                StepperRow(title: "Daily limit", detail: limit == 0 ? "No limit" : "Images a day", value: $limit, range: 0...500, step: 10)
            }
            .arrives(1)

            if let result {
                NoteText(text: result, symbol: "info.circle")
            }

            GoldButton(title: saving ? "Saving..." : "Save") { save() }
                .opacity(saving ? 0.7 : 1)
                .arrives(2)

            if configured {
                SettingsGroup {
                    ActionRow(title: testing ? "Testing..." : "Test connection", symbol: "bolt", tone: .gold) { test() }
                    ActionRow(title: "Remove", symbol: "trash", tone: .danger) { confirmRemove = true }
                }
                .arrives(3)
            }

            NoteText(text: "Images are made with your own key and billed by the provider. Kairos never shows the key again.", symbol: "key")
                .arrives(4)
        }
        .onChange(of: provider) {
            model = provider.defaultModel
        }
        .alert("Remove image connection?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Designs will use photos and patterns instead.")
        }
    }

    private func save() {
        guard !saving else { return }
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        let unchanged = configured && provider == savedProvider && trimmedModel == savedModel
            && (provider != .compatible || trimmedAddress == savedAddress)
        if provider == .compatible && (trimmedAddress.isEmpty || trimmedModel.isEmpty) {
            Haptics.thud()
            withAnimation(Motion.snappy) { result = "Enter the address and model of the compatible server." }
            return
        }
        if (!configured || !unchanged) && trimmedKey.isEmpty {
            Haptics.thud()
            withAnimation(Motion.snappy) { result = "Paste the connection key." }
            return
        }
        result = nil
        saving = true
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            configured = true
            savedProvider = provider
            savedModel = trimmedModel.isEmpty ? provider.defaultModel : trimmedModel
            savedAddress = trimmedAddress
            savedLimit = limit
            key = ""
            saving = false
            withAnimation(Motion.snappy) { result = "Connection saved." }
            Haptics.success()
            YouStore.shared.say("Image connection saved.")
        }
    }

    private func test() {
        guard !testing else { return }
        result = nil
        testing = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            testing = false
            withAnimation(Motion.snappy) { result = "Works. The provider made a test image." }
            Haptics.success()
        }
    }

    private func remove() {
        withAnimation(Motion.snappy) {
            configured = false
            key = ""
            result = "Connection removed."
        }
        Haptics.success()
        YouStore.shared.say("Image connection removed.")
    }
}

// MARK: - Debug pictures

enum IntegrationsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "integrations": return AnyView(IntegrationsScreen())
        case "integrations-github": return AnyView(IntegrationsScreen(githubOpen: true))
        case "integrations-empty": return AnyView(IntegrationsScreen(startEmpty: true))
        case "integrations-no-match": return AnyView(IntegrationsScreen(startQuery: "zebra"))
        case "integrations-detail-calendar": return AnyView(IntegrationDetailScreen(integrationID: "i-cal"))
        case "integrations-detail-contacts": return AnyView(IntegrationDetailScreen(integrationID: "i-contacts"))
        case "integrations-detail-mcp": return AnyView(IntegrationDetailScreen(integrationID: "i-tracker"))
        case "integrations-detail-signing": return AnyView(IntegrationDetailScreen(integrationID: "i-tracker", startSigningIn: true))
        case "integrations-add-api": return AnyView(AddIntegrationScreen(kind: "api"))
        case "integrations-add-caldav": return AnyView(AddIntegrationScreen(kind: "caldav"))
        case "integrations-add-ical": return AnyView(AddIntegrationScreen(kind: "ical"))
        case "integrations-add-carddav": return AnyView(AddIntegrationScreen(kind: "carddav"))
        case "integrations-add-email": return AnyView(AddIntegrationScreen(kind: "email"))
        case "integrations-add-mcp": return AnyView(AddIntegrationScreen(kind: "mcp"))
        case "integrations-add-mcp-remote": return AnyView(AddIntegrationScreen(kind: "mcp", remote: true))
        case "integrations-add-mcp-error": return AnyView(AddIntegrationScreen(kind: "mcp", showProblem: true))
        case "integrations-catalog": return AnyView(MCPCatalogScreen())
        case "integrations-catalog-no-match": return AnyView(MCPCatalogScreen(startQuery: "zebra"))
        case "integrations-google": return AnyView(GoogleScreen())
        case "integrations-google-add": return AnyView(GoogleScreen(startAdding: true))
        case "integrations-google-waiting": return AnyView(GoogleScreen(startWaiting: true))
        case "integrations-images": return AnyView(ImageGenerationScreen())
        case "integrations-images-off": return AnyView(ImageGenerationScreen(connected: false))
        case "integrations-images-compatible": return AnyView(ImageGenerationScreen(compatible: true))
        default: return nil
        }
    }
}
