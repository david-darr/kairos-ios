import SwiftUI

/// You: the account and its switcher, every setting, the Tool Store, your added tabs, the look, and help.
/// It is a sheet with its own navigation, so every setting opens as a page inside it.
struct YouView: View {
    @State private var path: [YouRoute] = []
    private let store = YouStore.shared

    var body: some View {
        NavigationStack(path: $path) {
            YouHome()
                .youDestinations()
        }
        .onAppear {
            if let route = store.pendingRoute {
                store.pendingRoute = nil
                path = [route]
            }
        }
        .kSheet()
    }
}

/// One entry in the You list, also what the settings search looks through.
nonisolated struct YouEntry: Identifiable, Hashable, Sendable {
    let title: String
    let symbol: String
    let route: YouRoute
    var keywords = ""
    var id: String { title }
}

nonisolated enum YouIndex {
    static let groups: [(title: String, entries: [YouEntry])] = [
        ("General", [
            YouEntry(title: "Appearance", symbol: "paintpalette", route: .look, keywords: "look night light theme kip icon background colour color effect"),
            YouEntry(title: "Layout", symbol: "square.grid.2x2", route: .layout, keywords: "tab bar shortcut home sidebar order pin"),
            YouEntry(title: "Notifications", symbol: "bell", route: .notifications, keywords: "push alerts lock screen live activities test"),
            YouEntry(title: "Reach me", symbol: "antenna.radiowaves.left.and.right", route: .reachMe, keywords: "quiet hours call order message order stop pause"),
        ]),
        ("Models and voice", [
            YouEntry(title: "Models and connections", symbol: "cpu", route: .models, keywords: "claude codex local api key test helpers antigravity"),
            YouEntry(title: "Speech and voice", symbol: "waveform", route: .voice, keywords: "voice kokoro elevenlabs gpt-live pronunciations dictation microphone gemini"),
            YouEntry(title: "Bot call voice", symbol: "phone", route: .botVoice, keywords: "live voice idle call"),
            YouEntry(title: "Image generation", symbol: "photo", route: .images, keywords: "images openai xai daily limit"),
        ]),
        ("Connections", [
            YouEntry(title: "Channels and connectors", symbol: "bubble.left.and.bubble.right", route: .channels, keywords: "discord telegram whatsapp slack signal email sms webhook"),
            YouEntry(title: "Integrations", symbol: "link", route: .integrations, keywords: "mcp caldav ical contacts github api service catalog"),
            YouEntry(title: "Google", symbol: "envelope", route: .google, keywords: "gmail calendar drive accounts"),
            YouEntry(title: "Remote access", symbol: "network", route: .remote, keywords: "tailscale address paired phones pair unpair"),
            YouEntry(title: "Phone lines", symbol: "phone.connection", route: .phone, keywords: "twilio telnyx number pin calls texts"),
        ]),
        ("Bots", [
            YouEntry(title: "Bot preferences", symbol: "slider.horizontal.3", route: .botPrefs, keywords: "interface chat width font threads tour setup"),
            YouEntry(title: "Connected apps", symbol: "puzzlepiece.extension", route: .connectedApps, keywords: "apps mcp servers bots access"),
            YouEntry(title: "Keys", symbol: "key", route: .botKeys, keywords: "api keys helper model tidy"),
            YouEntry(title: "Signed-in sites", symbol: "lock", route: .botLogins, keywords: "logins passwords 1password"),
            YouEntry(title: "About you", symbol: "person.text.rectangle", route: .aboutYou, keywords: "facts memory profile learned"),
            YouEntry(title: "Skill library", symbol: "bookmark", route: .skillLibrary, keywords: "skills review import"),
            YouEntry(title: "Usage and spend", symbol: "chart.bar", route: .botUsage, keywords: "cap budget cost"),
            YouEntry(title: "Housekeeping", symbol: "archivebox", route: .botHousekeeping, keywords: "trace retention cleanup"),
            YouEntry(title: "Templates", symbol: "square.and.arrow.down", route: .botTemplates, keywords: "teams import share personas"),
            YouEntry(title: "Bot computers", symbol: "desktopcomputer", route: .botComputers, keywords: "docker limits sleep"),
        ]),
        ("Your data", [
            YouEntry(title: "Vault", symbol: "archivebox", route: .vault, keywords: "folder notes sync priorities"),
            YouEntry(title: "Tool Store", symbol: "bag", route: .toolStore, keywords: "skills tools tabs add-ons community automations"),
            YouEntry(title: "Add a tab", symbol: "plus.square.dashed", route: .addTab, keywords: "custom tab build install"),
        ]),
        ("Access", [
            YouEntry(title: "Permissions", symbol: "checkmark.shield", route: .permissions, keywords: "grants revoke terminals"),
            YouEntry(title: "Agent tools", symbol: "hammer", route: .agentTools, keywords: "built-in tools allowed"),
            YouEntry(title: "Computer use", symbol: "cursorarrow.rays", route: .computerUse, keywords: "browser docker profiles"),
            YouEntry(title: "Forge", symbol: "terminal", route: .forge, keywords: "projects folder terminal"),
        ]),
        ("Administration", [
            YouEntry(title: "Users", symbol: "person.2", route: .users, keywords: "people admin member password"),
            YouEntry(title: "Logs", symbol: "list.bullet", route: .logs, keywords: "errors backend follow"),
            YouEntry(title: "Runs", symbol: "clock", route: .runs, keywords: "failed stopped steps"),
            YouEntry(title: "Sandbox changes", symbol: "tray", route: .sandbox, keywords: "diff apply discard"),
            YouEntry(title: "File checkpoints", symbol: "arrow.clockwise", route: .checkpoints, keywords: "restore files"),
            YouEntry(title: "Hooks", symbol: "bolt", route: .hooks, keywords: "webhook command events"),
            YouEntry(title: "Backups and system", symbol: "externaldrive", route: .system, keywords: "diagnostics backup restore export import wipe"),
            YouEntry(title: "Shortcuts", symbol: "command", route: .shortcuts, keywords: "keyboard keys"),
        ]),
    ]

    static let all: [YouEntry] = groups.flatMap(\.entries) + [
        YouEntry(title: "Your account", symbol: "person.crop.circle", route: .account, keywords: "profile colour color pin password two-step"),
        YouEntry(title: "Accounts on this phone", symbol: "person.2", route: .accounts, keywords: "switch sign out add account"),
        YouEntry(title: "Your desktop", symbol: "desktopcomputer", route: .connection, keywords: "connection pair desktop"),
        YouEntry(title: "Help and the tour", symbol: "questionmark.circle", route: .help, keywords: "welcome tour help version updates"),
    ]

    static func search(_ query: String) -> [YouEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        return all.filter { $0.title.lowercased().contains(needle) || $0.keywords.contains(needle) }
    }
}

/// The top of the You sheet.
struct YouHome: View {
    var startQuery = ""
    var startPin = false
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    private let store = YouStore.shared
    @State private var query = ""
    @State private var pinFor: DeviceAccount?
    @State private var confirmSignOut = false
    @State private var signInFor: DeviceAccount?
    @State private var confirmUnpair = false
    @State private var goPair = false
    private let live = YouAccessLive.shared

    /// Paired with a desktop: the header is the paired account and Sign out is Unpair this phone.
    private var paired: Bool { YouAccessLive.isPaired }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header.arrives(0)
                if paired { pairedSwitcher.arrives(1) } else { switcher.arrives(1) }
                SearchField(prompt: "Search settings", text: $query).arrives(2)

                if !query.isEmpty {
                    results
                } else {
                    SettingsGroup {
                        YouNavRow(title: "Your account", detail: paired ? "Who this phone is paired as" : "Colour, PIN, password and two-step sign-in", symbol: "person.crop.circle", to: .account)
                        YouNavRow(title: "Your desktop", detail: paired ? Connection.shared.statusLine : "Connected on sample data", symbol: "desktopcomputer", to: .connection)
                    }
                    .arrives(3)

                    ForEach(Array(YouIndex.groups.enumerated()), id: \.offset) { index, group in
                        SettingsGroup(group.title) {
                            ForEach(group.entries) { entry in
                                YouNavRow(title: entry.title, symbol: entry.symbol, value: value(for: entry.route), to: entry.route)
                            }
                        }
                        .arrives(index + 4)
                    }

                    if !paired {
                        SettingsGroup("Your tabs") {
                            ForEach(SampleData.addedTabs) { tab in
                                YouNavRow(title: tab.title, symbol: tab.symbol, to: .addedTab(tab.title))
                            }
                        }
                    }

                    SettingsGroup("Help") {
                        ActionRow(title: "Replay the welcome", symbol: "play.circle") {
                            dismiss()
                            app.replayOnboarding()
                        }
                        ActionRow(title: "Take the tour", detail: "A short walk past the real controls", symbol: "hand.point.up.left") {
                            router.sheet = nil
                            router.paths[.home] = []
                            router.select(.home)
                            TourPresenter.start(after: 0.6)
                        }
                        YouNavRow(title: "Help", detail: "What each part does, the version and updates", symbol: "questionmark.circle", to: .help)
                    }

                    if paired {
                        if let note = live.thisPhoneNotice {
                            NoteText(text: note, symbol: "exclamationmark.triangle")
                        }
                        SettingsGroup {
                            ActionRow(title: live.unpairingThisPhone ? "Unpairing..." : "Unpair this phone",
                                      detail: "Ends this phone's access to your desktop. Your chats and bots stay there.",
                                      symbol: "rectangle.portrait.and.arrow.right", tone: .danger) {
                                if !live.unpairingThisPhone { confirmUnpair = true }
                            }
                        }
                    } else {
                        SettingsGroup {
                            ActionRow(title: store.accounts.count > 1 ? "Sign out of \(store.current.name)" : "Sign out", symbol: "rectangle.portrait.and.arrow.right", tone: .danger) {
                                confirmSignOut = true
                            }
                        }
                    }

                    Text(paired ? "Kairos Agents \(APIClient.appVersion)" : "Kairos Agents 0.1 · sample data")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) { YouToastHost() }
        .kScreen()
        .sheet(item: $pinFor) { account in
            PinSheet(account: account)
        }
        .navigationDestination(item: $signInFor) { _ in
            SignInScreen()
        }
        .confirmationDialog("Sign out of \(store.current.name)?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { signOutCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(signOutMessage)
        }
        .sheet(isPresented: $confirmUnpair) {
            ConfirmSheet(title: "Unpair this phone?",
                         detail: "This phone's access to your desktop ends at once, and it goes back to sample data. Your chats and bots stay on your desktop. To use it again, pair it with a new code from your desktop.",
                         confirm: "Unpair this phone") {
                unpairThisPhone()
            }
        }
        .navigationDestination(isPresented: $goPair) {
            ConnectionScreen()
        }
        .onAppear {
            if !startQuery.isEmpty { query = startQuery }
            if startPin && !paired { pinFor = store.accounts.first { $0.pin != nil } }
        }
    }

    private func unpairThisPhone() {
        Task {
            if await live.unpairThisPhone() {
                Haptics.success()
                goPair = true
            }
        }
    }

    // MARK: Pieces

    private var signOutMessage: String {
        if store.accounts.count > 1 {
            let next = store.accounts.first { $0.id != store.currentID }?.name ?? "another account"
            return "Its chats stay on your desktop. This phone switches to \(next)."
        }
        return "This phone forgets the desktop. You can pair it again any time."
    }

    private var header: some View {
        let account = YouAccessLive.pairedAccount ?? store.current
        return VStack(spacing: 8) {
            AccountAvatar(account: account, size: 92, ring: 3)
                .id(account.id)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            Text(account.name)
                .font(KFont.display(36))
                .foregroundStyle(Palette.ink)
            Text(paired ? "\(account.role) · this phone is paired as this account" : "\(account.role) · on your desktop")
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.bouncy, value: store.currentID)
    }

    private var switcher: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionLabel(text: "Accounts on this phone")
                NavigationLink(value: YouRoute.accounts) {
                    Text("Manage").font(KFont.ui(14, .medium, relativeTo: .footnote)).foregroundStyle(Palette.goldText)
                        .frame(minHeight: 44)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.leading, 6)
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(store.accounts) { account in
                        accountChip(account)
                    }
                    if store.accounts.count < 9 {
                        NavigationLink(value: YouRoute.signIn) {
                            VStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Palette.inkDim)
                                    .frame(width: 56, height: 56)
                                    .background(Palette.ink.opacity(0.06), in: Circle())
                                    .overlay(Circle().strokeBorder(Palette.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])))
                                Text("Add").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                                Text(" ").font(KFont.ui(11.5, relativeTo: .caption2))
                            }
                            .frame(minWidth: 64)
                        }
                        .buttonStyle(PressStyle(scale: 0.92))
                        .accessibilityLabel("Add another account")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    /// Paired, the phone is one account: its chip, and Manage explains where accounts are changed.
    private var pairedSwitcher: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionLabel(text: "Account on this phone")
                NavigationLink(value: YouRoute.accounts) {
                    Text("Manage").font(KFont.ui(14, .medium, relativeTo: .footnote)).foregroundStyle(Palette.goldText)
                        .frame(minHeight: 44)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.leading, 6)
            if let account = YouAccessLive.pairedAccount {
                VStack(spacing: 6) {
                    AccountAvatar(account: account, size: 56, ring: 3)
                        .overlay { Circle().strokeBorder(Palette.ink.opacity(0.45), lineWidth: 1).padding(-5) }
                    Text(account.name).font(KFont.ui(13, .semibold, relativeTo: .footnote)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text("Paired").font(KFont.ui(11.5, relativeTo: .caption2)).foregroundStyle(Palette.goldText)
                }
                .frame(minWidth: 64)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(account.name), the account this phone is paired as")
            }
        }
    }

    private func accountChip(_ account: DeviceAccount) -> some View {
        let open = account.id == store.currentID
        return Button {
            Haptics.select()
            if !open { choose(account) }
        } label: {
            VStack(spacing: 6) {
                AccountAvatar(account: account, size: 56, ring: open ? 3 : 2)
                    .opacity(account.expired ? 0.55 : 1)
                    .overlay {
                        if open {
                            Circle().strokeBorder(Palette.ink.opacity(0.45), lineWidth: 1).padding(-5)
                        }
                    }
                Text(account.name).font(KFont.ui(13, open ? .semibold : .regular, relativeTo: .footnote)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(open ? "Open now" : account.expired ? "Sign in again" : account.pin != nil ? "PIN" : "One tap")
                    .font(KFont.ui(11.5, relativeTo: .caption2))
                    .foregroundStyle(open ? Palette.goldText : Palette.inkFaint)
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .contextMenu {
            if !open {
                Button("Switch to \(account.name)", systemImage: "arrow.left.arrow.right") { choose(account) }
            }
            Button("Sign out of \(account.name)", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                if account.id == store.currentID { confirmSignOut = true } else { store.signOut(account.id) }
            }
        }
        .accessibilityLabel("\(account.name), \(open ? "open now" : account.expired ? "sign in again" : account.pin != nil ? "asks a PIN" : "switch")")
    }

    private func choose(_ account: DeviceAccount) {
        if account.expired {
            signInFor = account
        } else if account.pin != nil {
            pinFor = account
        } else {
            store.switchTo(account.id)
        }
    }

    private var results: some View {
        let hits = YouIndex.search(query)
        return Group {
            if hits.isEmpty {
                Text("No setting matches \"\(query)\".")
                    .font(KFont.ui(15.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            } else {
                SettingsGroup("Settings") {
                    ForEach(hits) { entry in
                        YouNavRow(title: entry.title, symbol: entry.symbol, to: entry.route)
                    }
                }
            }
        }
    }

    private func value(for route: YouRoute) -> String? {
        switch route {
        case .look: app.appearance.title
        case .layout: router.pinned.first.map { "\($0.title) on the bar" }
        default: nil
        }
    }

    private func signOutCurrent() {
        if store.accounts.count > 1 {
            store.signOut(store.currentID)
        } else {
            dismiss()
            app.replayOnboarding()
        }
    }
}

/// Switching into an account that asks its PIN on this phone.
struct PinSheet: View {
    let account: DeviceAccount
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var triesLeft = 3
    @State private var note: String?
    @FocusState private var focused: Bool
    private let store = YouStore.shared

    var body: some View {
        FittedSheet(estimate: 440) {
            VStack(spacing: 18) {
                AccountAvatar(account: account, size: 64, ring: 3)
                    .padding(.top, 34)
                VStack(spacing: 6) {
                    Text("Switch to \(account.name)")
                        .font(KFont.ui(21, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    Text("This account asks its PIN on this phone.")
                        .font(KFont.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                }
                SecureField("4 to 8 digits", text: $pin)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .font(KFont.ui(22, .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink)
                    .frame(height: 56)
                    .kCard(radius: 18, raised: true)
                    .onChange(of: pin) { pin = String(pin.filter(\.isNumber).prefix(8)) }
                    .disabled(triesLeft == 0)
                if let note {
                    Text(note)
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(triesLeft == 0 ? Palette.danger : Palette.goldText)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                VStack(spacing: 4) {
                    GoldButton(title: "Switch") { submit() }
                    QuietButton(title: "Cancel") { dismiss() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .animation(Motion.snappy, value: note)
        }
    }

    private func submit() {
        // Paired, no PIN is ever typed, kept or compared on the phone.
        guard !YouAccessLive.isPaired else {
            note = "Passwords, PINs and accounts are managed in Kairos on your desktop."
            return
        }
        guard triesLeft > 0 else { return }
        guard pin.count >= 4 else {
            note = "Enter the 4 to 8 digit PIN."
            return
        }
        if pin == account.pin {
            Haptics.success()
            store.switchTo(account.id)
            dismiss()
        } else {
            Haptics.thud()
            triesLeft -= 1
            pin = ""
            note = triesLeft == 0
                ? "Too many wrong tries. Wait a minute, then try again."
                : "That PIN is not right. \(triesLeft) \(triesLeft == 1 ? "try" : "tries") left."
        }
    }
}

/// Help: replay the welcome, take the tour, what each part does, the version and updates.
struct HelpScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router

    private let parts: [(symbol: String, title: String, body: String)] = [
        ("house", "Home", "Your bots as faces, then every chat. A bot waiting for you is an unread chat."),
        ("wand.and.stars", "Make", "Describe a video, design, document, deck or image. Studio runs your channels."),
        ("books.vertical", "Library", "Files with the vault first, then Notes, Calendar, Mail and Tasks."),
        ("laptopcomputer", "Desktop", "Your PC's state, Forge coding sessions, Computer and Browse."),
        ("magnifyingglass", "Search", "Find chats, bots, files, notes and settings, or run an action."),
        ("square.grid.2x2", "Jump to", "Hold the tab bar to see every area. Drag one onto the bar to keep it there."),
        ("person.crop.circle", "You", "Accounts, every setting, the Tool Store and your added tabs."),
    ]

    /// The paired desktop's own name and version, as /api/phone/session gave them.
    private var desktopVersion: String {
        guard let desktop = Connection.shared.desktop else { return "Not known yet" }
        let name = desktop.serverName.isEmpty ? "Kairos" : desktop.serverName
        return desktop.serverVersion.isEmpty ? "\(name), version not known" : "\(name) \(desktop.serverVersion)"
    }

    var body: some View {
        SettingsPage("Help", subtitle: "How Kairos is laid out on your phone.") {
            SettingsGroup {
                ActionRow(title: "Take the tour", detail: "Points at the real controls, one at a time", symbol: "hand.point.up.left", tone: .gold) {
                    router.sheet = nil
                    router.paths[.home] = []
                    router.select(.home)
                    TourPresenter.start(after: 0.6)
                }
                ActionRow(title: "Replay the welcome", detail: "The first pages and the permission moments", symbol: "play.circle") {
                    router.sheet = nil
                    app.replayOnboarding()
                }
            }

            SettingsGroup("The parts") {
                ForEach(parts, id: \.title) { part in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: part.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Palette.goldText)
                            .frame(width: 26)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                            Text(part.body).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
            }

            SettingsGroup("In a chat", footer: "Commands work the same as on your desktop.") {
                ValueRow(title: "Every command", value: "/help")
                ValueRow(title: "A short list", value: "/help compact")
                ValueRow(title: "Mention a bot", value: "@")
            }

            SettingsGroup("About", footer: "Kairos Agents is free and open source. It connects to your own Kairos desktop; nothing is bought here.") {
                if YouAccessLive.isPaired {
                    ValueRow(title: "This app", value: APIClient.appVersion)
                    ValueRow(title: "Your desktop", value: desktopVersion)
                } else {
                    ValueRow(title: "This app", value: "0.1.0")
                    ValueRow(title: "Your desktop", value: "Kairos 2.3.0")
                }
                RowLabel(title: "Updates", detail: "Your desktop updates itself the next time you quit it. This app updates through the App Store.", symbol: nil)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }
}

enum YouHomeDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "home": return AnyView(YouHome())
        case "home-pin": return AnyView(YouHome(startPin: true))
        case "home-search": return AnyView(YouHome(startQuery: "voice"))
        case "help": return AnyView(HelpScreen())
        case "welcome-notify": return AnyView(OnboardingFlow(startPermission: 0).kScreen())
        case "welcome-mic": return AnyView(OnboardingFlow(startPermission: 1).kScreen())
        case "welcome-camera": return AnyView(OnboardingFlow(startPermission: 2).kScreen())
        case "tour-start": return AnyView(TourDebugView(step: 0))
        case "tour-bar": return AnyView(TourDebugView(step: 1))
        case "tour-hold": return AnyView(TourDebugView(step: 2))
        case "tour-action": return AnyView(TourDebugView(step: 3))
        case "tour-face": return AnyView(TourDebugView(step: 4))
        case "tour-you": return AnyView(TourDebugView(step: 6))
        default: return nil
        }
    }
}
