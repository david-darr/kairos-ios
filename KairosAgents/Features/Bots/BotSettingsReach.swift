import SwiftUI
import UIKit

// Settings pages for what a bot can reach and use: access, connections, browser profiles,
// usage and plan, and its conversations.

// MARK: - Access and grants

struct AccessSettings: View {
    let botID: String
    let store = BotsStore.shared

    var body: some View {
        let binding = store.binding(botID)
        let s = binding.wrappedValue
        BotsPage("Access and grants", subtitle: "What it can reach") {
            ForEach(Array(s.grants.enumerated()), id: \.element.id) { index, grant in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: grant.symbol).font(.system(size: 17)).foregroundStyle(Palette.goldText)
                            .frame(width: 38, height: 38).background(Palette.ink.opacity(0.07), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(grant.app).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                            Text(grant.level == .off ? "Not allowed" : "\(grant.allowedTools) of \(grant.tools) tools allowed · \(grant.level == .read ? "Only looks" : "Can change things")")
                                .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                    }
                    GoldSegmented(items: AppGrant.Level.allCases, selection: Binding(
                        get: { grant.level },
                        set: { level in
                            binding.wrappedValue.grants[index].level = level
                            binding.wrappedValue.grants[index].allowedTools = level == .off ? 0 : (level == .read ? grant.tools / 2 : grant.tools)
                        }
                    )) { $0.rawValue }
                }
                .padding(14)
                .kCard(radius: 20)
                .arrives(index)
            }
            BotsSection(title: "Tool servers") {
                ToggleRow(title: "Every connected tool server", detail: "Off lets you pick servers one by one in Connections.", symbol: "server.rack", isOn: binding.everyToolServer)
                RowLine(inset: 54)
                ToggleRow(title: "Stay signed in", detail: "Keep the sites it logs into between runs.", symbol: "person.badge.key", isOn: binding.staySignedIn)
            }
            BotsSection(title: "Other bots", footer: "Widening who it can reach asks you to confirm.") {
                MenuRow(title: "Who it can reach", symbol: "person.2", options: ["All visible bots", "Only these bots", "No bots"], selection: Binding(
                    get: { s.reach },
                    set: { value in
                        binding.wrappedValue.reach = value
                        store.say(value == "All visible bots" ? "I allow this bot to contact more bots." : "Reach saved")
                    }
                ))
                RowLine(inset: 54)
                ToggleRow(title: "Ask before contacting bots below Full", isOn: binding.askBeforeContacting)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Where it works").padding(.horizontal, 4)
                GoldSegmented(items: ["Auto", "Computer", "Browser", "Off"], selection: binding.place) { $0 }
                Text(placeHint(s.place)).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).padding(.horizontal, 6)
            }
            NavigationLink(value: BotsRoute.settings(botID, .browser)) {
                NavRow(title: "Browser profiles and sign-ins", symbol: "globe").kCard(radius: 20)
            }
            .buttonStyle(PressStyle(scale: 0.98))
        }
    }

    private func placeHint(_ place: String) -> String {
        switch place {
        case "Computer": "It uses its own computer on your desktop."
        case "Browser": "It works only in its browser."
        case "Off": "It cannot use a computer or a browser."
        default: "It picks the computer or the browser for each job."
        }
    }
}

// MARK: - Connections

struct ConnectionsSettings: View {
    let store = BotsStore.shared
    @State private var search = ""
    @State private var show = "All"
    @State private var adding = false

    var body: some View {
        let items = store.apps.filter { app in
            (search.isEmpty || app.name.localizedCaseInsensitiveContains(search))
                && (show == "All" || (show == "Connected" && app.state == .connected) || (show == "Servers" && app.isServer))
        }
        BotsPage("Connections", subtitle: "\(store.apps.filter { $0.state == .connected }.count) connected", trailing: {
            GlassIconButton(symbol: "plus", label: "Add a tool server") { adding = true }
        }) {
            TextField("Search apps", text: $search)
                .font(KFont.ui(16)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 14).frame(minHeight: 48).kCard(radius: 16)
            GoldSegmented(items: ["All", "Connected", "Servers"], selection: $show) { $0 }
            if items.isEmpty {
                EmptyNote(text: "No apps match.", symbol: "magnifyingglass").kCard(radius: 20)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, app in
                appCard(app).arrives(index)
            }
            HintLine(text: "Signing in to an app finishes on your desktop the first time.", symbol: "desktopcomputer")
        }
        .sheet(isPresented: $adding) {
            AddServerSheet { name in
                withAnimation(Motion.snappy) {
                    store.apps.append(ConnectedApp(name: name, symbol: "server.rack", about: "A tool server you added.", state: .connected, usedBy: [], category: "Tool servers", isServer: true))
                }
                store.say("\(name) is connected.")
            }
        }
    }

    private func appCard(_ app: ConnectedApp) -> some View {
        HStack(spacing: 12) {
            Image(systemName: app.symbol).font(.system(size: 17)).foregroundStyle(Palette.goldText)
                .frame(width: 40, height: 40).background(Palette.ink.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                // The state sits beside the name when both fit, and under it when they do not.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(app.name).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                        StateTag(text: app.state.rawValue, color: stateColor(app.state)).lineLimit(1).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                        StateTag(text: app.state.rawValue, color: stateColor(app.state)).lineLimit(1).fixedSize()
                    }
                }
                Text(app.usedBy.isEmpty ? "No bots use it yet" : "Used by \(app.usedBy.joined(separator: ", "))")
                    .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                if app.state != .connected {
                    Button(actionTitle(app.state)) { set(app, .connected); store.say("\(app.name) is connected.") }
                } else {
                    Button("Test") { store.say("Connected, 12 tools") }
                    Button("Turn off") { set(app, .off) }
                }
                if app.state != .notAdded {
                    Button("Disconnect", role: .destructive) { set(app, .notAdded); store.say("\(app.name) is disconnected") }
                }
            } label: {
                Text(app.state == .connected ? "Manage" : actionTitle(app.state))
                    .font(KFont.ui(14.5, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(app.state == .connected ? Palette.ink : Palette.onGold)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(app.state == .connected ? AnyShapeStyle(Palette.ink.opacity(0.1)) : AnyShapeStyle(Palette.gold), in: Capsule())
            }
        }
        .padding(14)
        .kCard(radius: 20)
    }

    private func actionTitle(_ state: ConnectedApp.State) -> String {
        switch state {
        case .connected: "Test"
        case .reconnect: "Reconnect"
        case .notAdded: "Connect"
        case .finish: "Finish setup"
        case .off: "Turn on"
        }
    }

    private func stateColor(_ state: ConnectedApp.State) -> Color {
        switch state {
        case .connected: Palette.success
        case .reconnect, .finish: Palette.goldText
        case .notAdded, .off: Palette.inkFaint
        }
    }

    private func set(_ app: ConnectedApp, _ state: ConnectedApp.State) {
        guard let index = store.apps.firstIndex(where: { $0.id == app.id }) else { return }
        Haptics.select()
        withAnimation(Motion.snappy) { store.apps[index].state = state }
    }
}

struct AddServerSheet: View {
    let add: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var paste = ""
    @State private var name = ""
    @State private var place = "Remote link"
    @State private var address = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "Add a tool server", detail: "Paste a link, a setup command or a config block, or fill it in.")
                FieldCard(title: "Paste", text: $paste, placeholder: "https://... or a setup command", lines: 2...4)
                PillButton(title: "Read it", symbol: "doc.text.magnifyingglass") {
                    let words = paste.split(whereSeparator: { $0 == "/" || $0 == " " || $0 == "." })
                    name = words.dropFirst().first.map { String($0).lowercased() } ?? ""
                    address = paste
                    if name.isEmpty { BotsStore.shared.say("Paste a link, a setup command or a config block.") }
                }
                FieldCard(title: "Name", text: $name, placeholder: "lowercase, up to 32", limit: 32)
                GoldSegmented(items: ["Remote link", "Local command"], selection: $place) { $0 }
                FieldCard(title: place == "Remote link" ? "Address" : "Command", text: $address, placeholder: place == "Remote link" ? "https://" : "npx some-server")
                GoldButton(title: "Save server") {
                    guard !name.isEmpty else { Haptics.thud(); return }
                    add(name)
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .kSheet()
    }
}

// MARK: - Browser profiles

struct BrowserSettings: View {
    let botID: String
    let store = BotsStore.shared
    @State private var newProfile = ""
    @State private var renaming: BrowserProfile?
    @State private var renameText = ""

    var body: some View {
        let binding = store.binding(botID)
        let s = binding.wrappedValue
        let botName = store.bot(botID).name
        BotsPage("Browser profiles") {
            BotsSection {
                ToggleRow(title: "Browser enabled", symbol: "globe", isOn: binding.browserEnabled)
                if s.browserEnabled {
                    RowLine(inset: 54)
                    MenuRow(title: "Browser profile", symbol: "person.crop.rectangle", options: ["Own profile", "Guest, no saved sign-ins"] + store.profiles.map(\.name), selection: Binding(
                        get: { s.browserProfile },
                        set: { value in
                            binding.wrappedValue.browserProfile = value
                            for i in store.profiles.indices {
                                store.profiles[i].usedBy.removeAll { $0 == botName }
                                if store.profiles[i].name == value { store.profiles[i].usedBy.append(botName) }
                            }
                        }
                    ))
                }
            }

            BotsSection(title: "Shared profiles", footer: "Up to 20. A profile keeps its sign-ins for every bot that uses it.") {
                if store.profiles.isEmpty { EmptyNote(text: "No shared profiles", symbol: "person.crop.rectangle.stack") }
                ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { RowLine() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                            Text(profile.usedBy.isEmpty ? "No bots use this profile" : "Used by \(profile.usedBy.joined(separator: ", "))")
                                .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        Menu {
                            Button("Rename") { renameText = profile.name; renaming = profile }
                            Button("Delete", role: .destructive) {
                                withAnimation(Motion.snappy) { store.profiles.removeAll { $0.id == profile.id } }
                                store.say("Profile deleted")
                            }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(Palette.ink).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Options for \(profile.name)")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 4)
                    .padding(.vertical, 4)
                }
                RowLine()
                HStack {
                    TextField("New profile name", text: $newProfile).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    PillButton(title: "Create profile") {
                        let name = String(newProfile.trimmingCharacters(in: .whitespaces).prefix(60))
                        guard !name.isEmpty, store.profiles.count < 20 else { store.say("Give the profile a name."); return }
                        withAnimation(Motion.snappy) { store.profiles.append(BrowserProfile(name: name, usedBy: [])) }
                        newProfile = ""
                    }
                }
                .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 56)
            }

            BotsSection(title: "Saved logins (\(store.logins.count))", footer: "Passwords are typed on your desktop and never shown here.") {
                ForEach(Array(store.logins.enumerated()), id: \.element.id) { index, login in
                    if index > 0 { RowLine() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(login.site).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                                if login.twoFactor {
                                    Text("2FA").font(KFont.ui(11, .semibold, relativeTo: .caption2)).foregroundStyle(Palette.goldText)
                                        .padding(.horizontal, 6).padding(.vertical, 2).background(Palette.gold.opacity(0.15), in: Capsule())
                                }
                            }
                            Text("\(login.username) · \(login.allBots ? "All bots" : "Only chosen bots") · \(login.lastUsed)")
                                .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        PillButton(title: "Sign out", look: .danger) {
                            withAnimation(Motion.snappy) { store.logins.removeAll { $0.id == login.id } }
                            store.say("Signed out of \(login.site)")
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }
                if store.logins.isEmpty { EmptyNote(text: "No saved sites", symbol: "key") }
            }
        }
        .alert("Rename profile", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Profile name", text: $renameText)
            Button("Save") {
                if let profile = renaming, let i = store.profiles.firstIndex(where: { $0.id == profile.id }) {
                    store.profiles[i].name = String(renameText.prefix(60))
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}

// MARK: - Usage and plan

struct UsageSettings: View {
    let botID: String
    let store = BotsStore.shared
    @State private var period = "This month"
    @State private var refreshing = false

    var body: some View {
        let bot = store.bot(botID)
        let s = store.settings(botID)
        let scale: Double = period == "Today" ? 0.05 : (period == "This week" ? 0.3 : 1)
        BotsPage("Usage and plan", subtitle: bot.name) {
            GoldSegmented(items: ["Today", "This week", "This month"], selection: $period) { $0 }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                stat("Runs", "\(Int(112 * scale))")
                stat("Cost", String(format: "$%.2f", 6.4 * scale))
                stat("Tokens", "\(Int(2400 * scale))K")
                stat("Steps", "\(Int(840 * scale))")
                stat("Tools", "\(Int(310 * scale))")
                stat("Errors", "\(Int(6 * scale))")
            }
            BotsSection(title: "Today") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(s.runsToday) of \(s.runsPerDay) daily runs used. \(s.runsPerDay - s.runsToday) left today.")
                        .font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
                    MeterBar(fraction: Double(s.runsToday) / Double(max(1, s.runsPerDay)))
                }
                .padding(14)
            }
            BotsSection(title: "Where it went") {
                bar(s.model, 0.72)
                RowLine()
                bar("Claude Haiku", 0.2)
                RowLine()
                bar("GPT-6.1 Sol", 0.08)
            }
            BotsSection(title: "Plan usage", footer: "List-price equivalent, not billed.") {
                ForEach(Array(store.planWindows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 { RowLine() }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(window.provider): \(window.name)").font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(window.percent)%").font(KFont.ui(15, .semibold)).foregroundStyle(window.percent > 90 ? Palette.danger : Palette.ink)
                                .contentTransition(.numericText())
                        }
                        MeterBar(fraction: Double(window.percent) / 100)
                        Text(window.resets).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                    }
                    .padding(14)
                }
                RowLine()
                Button {
                    refreshing = true
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        withAnimation(Motion.snappy) {
                            for i in store.planWindows.indices { store.planWindows[i].percent = min(100, store.planWindows[i].percent + 1) }
                        }
                        refreshing = false
                    }
                } label: {
                    Label(refreshing ? "Refreshing" : "Refresh plan", systemImage: "arrow.clockwise")
                        .font(KFont.ui(15, .medium)).foregroundStyle(Palette.goldText)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(PressStyle())
            }
            BotsSection(title: "Runs") {
                ForEach(Array(BotsSample.runs(for: bot).enumerated()), id: \.element.id) { index, run in
                    if index > 0 { RowLine() }
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(run.title).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                            Text("\(run.model) · \(run.duration) · \(run.cost)").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        Text(run.when).font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 54)
                }
            }
            HStack(spacing: 10) {
                NavigationLink(value: BotsRoute.report(botID)) {
                    Text("Open report").font(KFont.ui(15, .semibold)).foregroundStyle(Palette.onGold)
                        .frame(maxWidth: .infinity, minHeight: 44).background(Palette.gold, in: Capsule())
                }
                NavigationLink(value: BotsRoute.settings(botID, .limits)) {
                    Text("Limits").font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44).background(Palette.ink.opacity(0.1), in: Capsule())
                }
            }
            .buttonStyle(PressStyle())
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(KFont.label).tracking(1.1).foregroundStyle(Palette.inkFaint)
            Text(value).font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .kCard(radius: 16)
        .animation(Motion.snappy, value: period)
    }

    private func bar(_ name: String, _ share: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                Spacer()
                Text("\(Int(share * 100))%").font(KFont.ui(14)).foregroundStyle(Palette.inkFaint)
            }
            MeterBar(fraction: share, height: 6)
        }
        .padding(14)
    }
}

// MARK: - Conversations and folders

struct ConversationsSettings: View {
    let botID: String
    let store = BotsStore.shared
    @Environment(AppRouter.self) private var router: AppRouter?
    @State private var showArchived = false
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var renaming: BotConversation?
    @State private var renameText = ""
    @State private var naming = false
    @State private var folderName = ""
    @State private var renamingFolder: String?

    var body: some View {
        let binding = store.binding(botID)
        let s = binding.wrappedValue
        let live = s.conversations.filter { showArchived || !$0.archived }
        let groups: [String?] = [nil] + s.folders.map { Optional($0) }
        BotsPage("Conversations", subtitle: "\(s.conversations.filter { !$0.archived }.count) conversations", trailing: {
            Button {
                withAnimation(Motion.snappy) { selecting.toggle(); selected = [] }
            } label: {
                Text(selecting ? "Done" : "Select").font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14).frame(minHeight: 44)
            }
            .kGlass(Capsule(), interactive: true)
        }) {
            HStack(spacing: 10) {
                PillButton(title: "New conversation", symbol: "plus", look: .filled, wide: true) {
                    withAnimation(Motion.snappy) { binding.wrappedValue.conversations.insert(BotConversation(title: "New conversation", updated: "now"), at: 1) }
                    store.say("New conversation started")
                }
                PillButton(title: "New folder", symbol: "folder.badge.plus", wide: true) { folderName = ""; naming = true }
            }
            ForEach(groups, id: \.self) { folder in
                folderSection(folder, live.filter { $0.folder == folder })
            }
            ToggleRow(title: "Show archived", isOn: $showArchived).kCard(radius: 20)
            if selecting {
                HStack(spacing: 10) {
                    Text("\(selected.count) selected").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                    Spacer()
                    PillButton(title: "Archive") { bulk(archive: true) }.disabled(selected.isEmpty)
                    PillButton(title: "Delete", look: .danger) { bulk(archive: false) }.disabled(selected.isEmpty)
                }
                .padding(12)
                .kGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Rename conversation", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Conversation name", text: $renameText)
            Button("Save") {
                if let item = renaming { change(item) { $0.title = renameText.isEmpty ? $0.title : renameText } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("New folder", isPresented: $naming) {
            TextField("Folder name", text: $folderName)
            Button("Create") {
                let name = folderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !binding.wrappedValue.folders.contains(name) { binding.wrappedValue.folders.append(name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename folder", isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
            TextField("Folder name", text: $folderName)
            Button("Save") {
                if let old = renamingFolder, !folderName.isEmpty { renameFolder(old, to: folderName) }
                renamingFolder = nil
            }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
    }

    @ViewBuilder
    private func folderSection(_ folder: String?, _ rows: [BotConversation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: folder ?? "Conversations")
                if let folder { folderMenu(folder) }
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                if rows.isEmpty {
                    EmptyNote(text: folder == nil ? "No conversations yet. Start one and it will appear here." : "Nothing in this folder yet. Move a conversation here from its menu.", symbol: "bubble.left")
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowLine(inset: selecting ? 54 : 16) }
                    row(item)
                }
            }
            .kCard(radius: 20)
        }
    }

    private func folderMenu(_ folder: String) -> some View {
        let folders = store.settings(botID).folders
        let index = folders.firstIndex(of: folder) ?? 0
        return Menu {
            Button("Rename") { folderName = folder; renamingFolder = folder }
            Button("Move up") { moveFolder(folder, by: -1) }.disabled(index == 0)
            Button("Move down") { moveFolder(folder, by: 1) }.disabled(index == folders.count - 1)
            Button("Delete folder", role: .destructive) {
                let binding = store.binding(botID)
                for i in binding.wrappedValue.conversations.indices where binding.wrappedValue.conversations[i].folder == folder {
                    binding.wrappedValue.conversations[i].folder = nil
                }
                binding.wrappedValue.folders.removeAll { $0 == folder }
                store.say("Folder deleted. Its conversations stay, outside any folder.")
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.inkDim)
                .frame(width: 44, height: 32)
        }
        .accessibilityLabel("Options for \(folder)")
    }

    private func row(_ item: BotConversation) -> some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21)).foregroundStyle(selected.contains(item.id) ? Palette.goldText : Palette.inkFaint)
                    .frame(width: 26)
            }
            Button {
                if selecting {
                    Haptics.select()
                    if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                } else if let router {
                    router.push(.bot(botID), on: .home)
                } else {
                    change(item) { $0.unread = false }
                    store.say("Opens in the chat")
                }
            } label: {
                HStack(spacing: 8) {
                    if item.working { PulsingDot(color: Palette.working, size: 6) }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(item.title).font(KFont.ui(16, item.unread ? .semibold : .regular)).foregroundStyle(item.archived ? Palette.inkFaint : Palette.ink).lineLimit(1)
                            if item.main { Text("Main").font(KFont.ui(11.5, .medium, relativeTo: .caption2)).foregroundStyle(Palette.goldText) }
                            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Palette.goldText) }
                            if item.snoozed { Image(systemName: "moon.zzz").font(.system(size: 11)).foregroundStyle(Palette.inkFaint) }
                        }
                        Text(item.archived ? "Archived · \(item.updated)" : item.updated).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer(minLength: 0)
                    if item.unread { Circle().fill(Palette.gold).frame(width: 9, height: 9).accessibilityLabel("Unread") }
                }
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            if !selecting { menu(item) }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
    }

    private func menu(_ item: BotConversation) -> some View {
        let folders = store.settings(botID).folders
        return Menu {
            Button("Rename") { renameText = item.title; renaming = item }
            Button(item.pinned ? "Unpin" : "Pin") { change(item) { $0.pinned.toggle() } }
            Button(item.unread ? "Mark as read" : "Mark as unread") { change(item) { $0.unread.toggle() } }
            Menu("Move to folder") {
                Button("No folder") { change(item) { $0.folder = nil } }
                ForEach(folders, id: \.self) { folder in
                    Button(folder) { change(item) { $0.folder = folder } }
                }
            }
            Menu("Snooze") {
                Button("Until something new") { snooze(item) }
                Button("Tonight") { snooze(item) }
                Button("Tomorrow morning") { snooze(item) }
            }
            if item.snoozed { Button("Stop snoozing") { change(item) { $0.snoozed = false } } }
            Button("Copy link") {
                UIPasteboard.general.string = "kairos://bot/\(botID)/conversation"
                store.say("Link copied")
            }
            if !item.main {
                Button("Make main conversation") { makeMain(item) }
                Button(item.archived ? "Unarchive" : "Archive") { change(item) { $0.archived.toggle() } }
                Button("Delete", role: .destructive) { delete([item.id]) }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkDim)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Options for \(item.title)")
    }

    private func change(_ item: BotConversation, _ edit: (inout BotConversation) -> Void) {
        let binding = store.binding(botID)
        guard let index = binding.wrappedValue.conversations.firstIndex(where: { $0.id == item.id }) else { return }
        Haptics.select()
        withAnimation(Motion.snappy) { edit(&binding.wrappedValue.conversations[index]) }
    }

    private func snooze(_ item: BotConversation) {
        change(item) { $0.snoozed = true }
        store.say("Snoozed")
    }

    private func makeMain(_ item: BotConversation) {
        let binding = store.binding(botID)
        withAnimation(Motion.snappy) {
            for i in binding.wrappedValue.conversations.indices {
                binding.wrappedValue.conversations[i].main = binding.wrappedValue.conversations[i].id == item.id
            }
        }
        store.say("\(item.title) is the main conversation")
    }

    private func delete(_ ids: Set<UUID>) {
        let binding = store.binding(botID)
        let keep = binding.wrappedValue.conversations.filter { ids.contains($0.id) && ($0.main || $0.working) }
        withAnimation(Motion.snappy) {
            binding.wrappedValue.conversations.removeAll { ids.contains($0.id) && !$0.main && !$0.working }
        }
        store.say(keep.isEmpty ? "Deleted" : "Deleted. The main conversation, and one that is working, stay.")
    }

    private func bulk(archive: Bool) {
        if archive {
            let binding = store.binding(botID)
            withAnimation(Motion.snappy) {
                for i in binding.wrappedValue.conversations.indices where selected.contains(binding.wrappedValue.conversations[i].id) && !binding.wrappedValue.conversations[i].main {
                    binding.wrappedValue.conversations[i].archived = true
                }
            }
            store.say("\(selected.count) archived")
        } else {
            delete(selected)
        }
        selected = []
        selecting = false
    }

    private func moveFolder(_ folder: String, by offset: Int) {
        let binding = store.binding(botID)
        guard let index = binding.wrappedValue.folders.firstIndex(of: folder) else { return }
        let target = index + offset
        guard binding.wrappedValue.folders.indices.contains(target) else { return }
        withAnimation(Motion.snappy) { binding.wrappedValue.folders.swapAt(index, target) }
    }

    private func renameFolder(_ old: String, to new: String) {
        let binding = store.binding(botID)
        guard let index = binding.wrappedValue.folders.firstIndex(of: old) else { return }
        binding.wrappedValue.folders[index] = new
        for i in binding.wrappedValue.conversations.indices where binding.wrappedValue.conversations[i].folder == old {
            binding.wrappedValue.conversations[i].folder = new
        }
    }
}
