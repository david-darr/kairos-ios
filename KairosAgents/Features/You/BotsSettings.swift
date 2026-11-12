import SwiftUI
import UniformTypeIdentifiers

// The Bots pages of Settings: preferences, keys, signed-in sites, about you, the skill library,
// usage and spend, housekeeping, templates, bot computers and connected apps. Sample data only.

// MARK: - Sample data

nonisolated struct BotKeyItem: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var hint: String
    var group: String
    var lastFour: String?
    var managedInModels = false
}

nonisolated struct BotLogin: Identifiable, Hashable, Sendable {
    let id: String
    var site: String
    var username: String
    var twoStep: Bool
    var exactSite: Bool
    var bots: [String]
    var lastUsed: String
}

nonisolated struct YouLearnedFact: Identifiable, Hashable, Sendable {
    let id: String
    var text: String
    var bot: String
    var when: String
}

nonisolated struct LibrarySkill: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var origin: String
    var summary: String
    var tags: [String]
    var on: Bool
    var everyBot: Bool
    var warning = false
    var body: String
}

nonisolated struct BotApp: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var category: String
    var detail: String
    var state: String
    var usedBy: [String]
    var accounts: [String]
}

nonisolated struct BotMCPServer: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var address: String
    var on: Bool
    var health: String
    var transport = "HTTP"
    var longestCall = 10
}

@Observable
final class BotsSettingsSample {
    static let shared = BotsSettingsSample()

    var keys: [BotKeyItem] = [
        BotKeyItem(id: "openai", label: "OpenAI", hint: "Images and GPT-Live", group: "Models", lastFour: "4f2a", managedInModels: true),
        BotKeyItem(id: "eleven", label: "ElevenLabs", hint: "Voices for calls", group: "Voice", lastFour: "9c10"),
        BotKeyItem(id: "brave", label: "Search API", hint: "Web search for Scout", group: "Research", lastFour: nil),
        BotKeyItem(id: "weather", label: "Weather service", hint: "Forecasts for Atlas", group: "Research", lastFour: "7781"),
    ]
    var helperModel = "The first local model"
    var tidyTime = Date.now
    var waitMinutes = 10
    var roomCapture = "Ask me first"

    var logins: [BotLogin] = [
        BotLogin(id: "l1", site: "shop.example.com", username: "orders@example.com", twoStep: true, exactSite: true, bots: [], lastUsed: "Yesterday"),
        BotLogin(id: "l2", site: "supplier.example.org", username: "bikeshop", twoStep: false, exactSite: false, bots: ["ledger"], lastUsed: "Monday"),
    ]
    var onePasswordConnected = false
    var vaults: [(name: String, allBots: Bool)] = [("Shop", true), ("Personal", false)]

    var aboutText = "I run a small bike shop. Keep replies short. Friday afternoons are for the weekly report."
    var learned: [YouLearnedFact] = [
        YouLearnedFact(id: "f1", text: "Prefers prices in a table", bot: "Scout", when: "Tuesday"),
        YouLearnedFact(id: "f2", text: "The shop is closed on Sundays", bot: "Kip", when: "last week"),
        YouLearnedFact(id: "f3", text: "Uses metric sizes for frames", bot: "Mason", when: "last week"),
    ]

    var skills: [LibrarySkill] = [
        LibrarySkill(id: "s1", name: "weekly-report", origin: "Written in Kairos", summary: "Drafts the Friday report from this week's notes", tags: ["writing"], on: true, everyBot: true,
                     body: "# Weekly report\n\n1. Read this week's daily notes.\n2. List what shipped, what slipped and what is next.\n3. Keep it under one page."),
        LibrarySkill(id: "s2", name: "price-check", origin: "Imported", summary: "Compares three shops for one item", tags: ["research", "shopping"], on: true, everyBot: false,
                     body: "# Price check\n\nSearch three shops, note price and stock, and return a table."),
        LibrarySkill(id: "s3", name: "receipt-filing", origin: "Imported", summary: "Files receipts by month", tags: ["money"], on: false, everyBot: false, warning: true,
                     body: "# Receipt filing\n\nRead each receipt, name it by date and shop, and move it to the month folder.\n\nRuns a shell command to move files."),
    ]
    var pendingShare: String? = "trip-budget"

    var monthlyCap = 40
    var spent = 31.6
    var traceDays = 30
    var traceMegabytes = 64

    var maxComputers = 2
    var idleMinutes = 30
    var computers: [(bot: String, state: String)] = [("scout", "Running"), ("quill", "Asleep"), ("mason", "You have the wheel")]

    var apps: [BotApp] = [
        BotApp(id: "gmail", name: "Gmail", category: "Google", detail: "Read and draft mail", state: "Connected", usedBy: ["Kip", "Quill"], accounts: ["Shop", "Personal"]),
        BotApp(id: "gcal", name: "Google Calendar", category: "Google", detail: "Events and reminders", state: "Reconnect", usedBy: ["Kip", "Posy"], accounts: ["Shop"]),
        BotApp(id: "notion", name: "Notes app", category: "Work", detail: "Pages and databases", state: "Connected", usedBy: ["Quill"], accounts: ["Workspace"]),
        BotApp(id: "store", name: "Shop backend", category: "Work", detail: "Orders and stock", state: "Problem", usedBy: ["Ledger"], accounts: ["Main"]),
    ]
    var servers: [BotMCPServer] = [
        BotMCPServer(id: "m1", name: "github", address: "https://mcp.example.com/github", on: true, health: "Working · 24 tools"),
        BotMCPServer(id: "m2", name: "files", address: "Local command on your desktop", on: true, health: "Working · 6 tools"),
        BotMCPServer(id: "m3", name: "maps", address: "https://maps.example.net/mcp", on: false, health: "Turned off"),
    ]
}

// MARK: - Preferences

struct BotPrefsScreen: View {
    var startChecklist = false
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var interface = "Simple"
    @State private var width = "Default"
    @State private var font = "Inter"
    @State private var colourBubbles = true
    @State private var threads = true
    @State private var circles = true
    @State private var runCard = true
    @State private var universalPins = false
    @State private var toolCalls = false
    @State private var density = "Comfortable"
    @State private var concurrency = 3
    @State private var defaultsOpen = false
    @State private var checklistOpen = false

    var body: some View {
        SettingsPage("Bot preferences", subtitle: "How bots look and behave in chats. Saved for this account.") {
            SettingsGroup("Interface") {
                PickRow(title: "Interface", detail: "Advanced shows threads and runs", selection: $interface, options: ["Simple", "Advanced"]) { $0 }
                PickRow(title: "Chat width", detail: "On your desktop", selection: $width, options: ["Default", "Wide", "Full"]) { $0 }
                PickRow(title: "Chat font", selection: $font, options: ["Inter", "System", "Serif"]) { $0 }
                YouToggleRow(title: "Colour your bubbles", isOn: $colourBubbles)
                YouToggleRow(title: "Show threads", isOn: $threads)
                YouToggleRow(title: "Pinned circles", detail: "Pinned bots as faces above the list", isOn: $circles)
                YouToggleRow(title: "Run card", detail: "A live card while a bot works", isOn: $runCard)
                YouToggleRow(title: "Universal pins", detail: "In Advanced, pinned bots from every team stay on top", isOn: $universalPins)
                YouToggleRow(title: "Show tool calls", isOn: $toolCalls)
                PickRow(title: "Sidebar density", detail: "On your desktop", selection: $density, options: ["Comfortable", "Compact", "Icons only"]) { $0 }
            }
            SettingsGroup("New bots", footer: "How many threads one bot may run at once.") {
                ActionRow(title: "New bot defaults", detail: "Model, approval and voice for new bots", symbol: "slider.horizontal.3") { defaultsOpen = true }
                YouStepperRow(title: "Thread concurrency", value: $concurrency, range: 1...16)
            }
            SettingsGroup("Get started") {
                ActionRow(title: "Replay the tour", symbol: "hand.point.up.left") {
                    router.sheet = nil
                    router.paths[.home] = []
                    router.select(.home)
                    TourPresenter.start(after: 0.6)
                }
                ActionRow(title: "Replay the welcome", symbol: "play.circle") {
                    router.sheet = nil
                    app.replayOnboarding()
                }
                ActionRow(title: "Check setup", detail: "What is ready and what is left", symbol: "checklist") { checklistOpen = true }
            }
            NoteText(text: "The send key is a desktop keyboard setting. On the phone, tap Send.")
        }
        .sheet(isPresented: $defaultsOpen) { BotDefaultsSheet() }
        .sheet(isPresented: $checklistOpen) { SetupChecklistSheet() }
        .onAppear { if startChecklist { checklistOpen = true } }
    }
}

private struct BotDefaultsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = "Claude Sonnet"
    @State private var approval = "Ask before acting"
    @State private var voice = "Iris"

    var body: some View {
        FittedSheet(estimate: 420) {
            VStack(alignment: .leading, spacing: 18) {
                Text("New bot defaults").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity).padding(.top, 30)
                SettingsGroup {
                    PickRow(title: "Model", selection: $model, options: ["Claude Sonnet", "Claude Opus", "GPT-6.1 Sol", "Qwen local"]) { $0 }
                    PickRow(title: "Approval", selection: $approval, options: ["Ask before acting", "Ask for risky steps", "Act freely"]) { $0 }
                    PickRow(title: "Voice", selection: $voice, options: ["Iris", "Ryan", "Aiden"]) { $0 }
                }
                GoldButton(title: "Save defaults") {
                    YouStore.shared.say("New bots start with \(model)")
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

private struct SetupChecklistSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let items: [(String, String, Bool)] = [
        ("A model is added", "Claude Code CLI and a local model", true),
        ("Kip is set up", "Your front desk bot is ready", true),
        ("A way to reach you", "Add a channel so bots can message you", false),
        ("Notifications on this phone", "So a bot can tap you", false),
    ]

    var body: some View {
        FittedSheet(estimate: 460) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Check setup").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity).padding(.top, 30)
                SettingsGroup {
                    ForEach(items, id: \.0) { item in
                        StatusRow(title: item.0, detail: item.1, symbol: item.2 ? "checkmark.circle.fill" : "circle", status: item.2 ? "Done" : "To do", tone: item.2 ? .ok : .warn)
                    }
                }
                Text("Two steps left. Channels and Notifications are in You.")
                    .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                QuietButton(title: "Close") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Keys

struct BotKeysScreen: View {
    @Bindable private var sample = BotsSettingsSample.shared
    @State private var drafts: [String: String] = [:]
    @State private var testing: String?
    @State private var results: [String: String] = [:]

    private var groups: [String] { Array(Set(sample.keys.map(\.group))).sorted() }

    var body: some View {
        SettingsPage("Keys", subtitle: "Keys are saved encrypted and never shown again. Testing a key shows only whether the provider accepted it.") {
            ForEach(groups, id: \.self) { group in
                SettingsGroup(group) {
                    ForEach(sample.keys.filter { $0.group == group }) { key in
                        keyRow(key)
                    }
                }
            }
            SettingsGroup("Helpers and quiet-time work", footer: "Claude and Codex cannot be helpers.") {
                PickRow(title: "Helper model", selection: $sample.helperModel, options: ["The first local model", "Off", "Qwen local", "Groq Llama"]) { $0 }
                DatePicker(selection: $sample.tidyTime, displayedComponents: .hourAndMinute) {
                    RowLabel(title: "Daily tidy time", detail: "When bots tidy their memory")
                }
                .tint(Palette.gold)
                .padding(.horizontal, 16).frame(minHeight: 56)
                YouStepperRow(title: "Wait before saving memories", value: $sample.waitMinutes, range: 1...60, unit: "min")
                PickRow(title: "Remember what is said in rooms", selection: $sample.roomCapture, options: ["Never", "Ask me first", "Always"]) { $0 }
                ActionRow(title: "Save", symbol: "checkmark", tone: .gold) { YouStore.shared.say("Saved.") }
            }
        }
    }

    private func keyRow(_ key: BotKeyItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RowLabel(title: key.label, detail: key.lastFour.map { "Saved, ends \($0) · \(key.hint)" } ?? "Not set · \(key.hint)")
                if let result = results[key.id] {
                    StatusPill(text: result, tone: result == "Accepted" ? .ok : .bad)
                } else if testing == key.id {
                    StatusPill(text: "Testing...", tone: .working)
                }
            }
            if key.managedInModels {
                Text("Change it in Settings, Models.").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                HStack { YouPillButton(title: "Test") { test(key) } }
            } else {
                SecureField(key.lastFour == nil ? "Paste the key" : "Saved. Type to replace.", text: Binding(get: { drafts[key.id] ?? "" }, set: { drafts[key.id] = $0 }))
                    .font(KFont.ui(15))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 6) {
                    YouPillButton(title: "Save", prominent: true) { save(key) }
                    if key.lastFour != nil {
                        YouPillButton(title: "Test") { test(key) }
                        YouPillButton(title: "Clear", danger: true) { clear(key) }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func save(_ key: BotKeyItem) {
        let text = (drafts[key.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            YouStore.shared.say("Type the key first.")
            return
        }
        if let index = sample.keys.firstIndex(where: { $0.id == key.id }) {
            withAnimation(Motion.snappy) { sample.keys[index].lastFour = String(text.suffix(4)) }
        }
        drafts[key.id] = ""
        results[key.id] = nil
        YouStore.shared.say("Saved.")
    }

    private func clear(_ key: BotKeyItem) {
        if let index = sample.keys.firstIndex(where: { $0.id == key.id }) {
            withAnimation(Motion.snappy) { sample.keys[index].lastFour = nil }
        }
        results[key.id] = nil
        YouStore.shared.say("\(key.label) key cleared")
    }

    private func test(_ key: BotKeyItem) {
        results[key.id] = nil
        testing = key.id
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(Motion.snappy) {
                testing = nil
                results[key.id] = key.id == "weather" ? "Rejected" : "Accepted"
            }
        }
    }
}

// MARK: - Signed-in sites

struct BotLoginsScreen: View {
    var startEditing = false
    @Bindable private var sample = BotsSettingsSample.shared
    @State private var editing: BotLogin?
    @State private var deleting: BotLogin?
    @State private var token = ""

    var body: some View {
        SettingsPage("Signed-in sites", subtitle: "Logins a bot's computer can fill in for you. A bot never sees the password, and filling never presses the sign-in button.") {
            SettingsGroup("Saved logins (\(sample.logins.count))") {
                if sample.logins.isEmpty {
                    EmptyRow(text: "No saved logins. Add one so a bot can sign in to a site for you.")
                }
                ForEach(sample.logins) { login in
                    HStack(spacing: 8) {
                        RowLabel(title: login.site, detail: "\(login.username) · \(login.bots.isEmpty ? "All bots" : SampleData.bots(login.bots).map(\.name).joined(separator: ", ")) · used \(login.lastUsed)", symbol: "lock")
                        if login.twoStep { StatusPill(text: "2FA", tone: .muted) }
                        Menu {
                            Button("Change", systemImage: "pencil") { editing = login }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = login }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkDim)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Actions for \(login.site)")
                    }
                    .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
                }
                ActionRow(title: "Add a login", symbol: "plus", tone: .gold) {
                    editing = BotLogin(id: "new", site: "", username: "", twoStep: false, exactSite: true, bots: [], lastUsed: "never")
                }
            }
            SettingsGroup("1Password", footer: "A service-account token lets bots fill from the vaults you choose. It stays on your desktop.") {
                if sample.onePasswordConnected {
                    ForEach(Array(sample.vaults.enumerated()), id: \.offset) { index, vault in
                        YouToggleRow(title: vault.name, detail: vault.allBots ? "All bots" : "No bots", isOn: Binding(get: { sample.vaults[index].allBots }, set: { sample.vaults[index].allBots = $0 }))
                    }
                    ActionRow(title: "Refresh vaults", symbol: "arrow.clockwise") { YouStore.shared.say("Vaults are up to date") }
                    ActionRow(title: "Disconnect", symbol: "xmark", tone: .danger) {
                        withAnimation(Motion.snappy) { sample.onePasswordConnected = false }
                    }
                } else {
                    FieldRow(title: "Service-account token", text: $token, prompt: "Paste the token", secure: true)
                    ActionRow(title: "Connect", symbol: "link", tone: .gold) {
                        guard !token.isEmpty else {
                            YouStore.shared.say("Paste the token first.")
                            return
                        }
                        token = ""
                        withAnimation(Motion.snappy) { sample.onePasswordConnected = true }
                        YouStore.shared.say("1Password connected")
                    }
                }
            }
        }
        .sheet(item: $editing) { login in
            LoginEditSheet(login: login)
        }
        .confirmationDialog("Delete the login for \(deleting?.site ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = deleting?.id { withAnimation(Motion.snappy) { sample.logins.removeAll { $0.id == id } } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
        .onAppear {
            if startEditing { editing = BotLogin(id: "new", site: "", username: "", twoStep: false, exactSite: true, bots: [], lastUsed: "never") }
        }
    }
}

private struct LoginEditSheet: View {
    @State var login: BotLogin
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var seed = ""
    @State private var onlyThese = false
    @State private var note: String?
    private let sample = BotsSettingsSample.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(login.id == "new" ? "Add a login" : "Change login").font(KFont.ui(22, .semibold, relativeTo: .title2)).foregroundStyle(Palette.ink)
                        .padding(.top, 30)
                    SettingsGroup {
                        FieldRow(title: "Site", text: $login.site, prompt: "example.com", keyboard: .URL)
                        FieldRow(title: "Username", text: $login.username, prompt: "name or email")
                        FieldRow(title: "Password", text: $password, prompt: login.id == "new" ? "Password" : "Saved. Leave blank to keep it.", secure: true)
                        FieldRow(title: "One-time-code seed (optional)", text: $seed, prompt: "Secret or otpauth link", secure: true)
                        YouToggleRow(title: "This exact site only", detail: "Off lets it fill on subdomains too", isOn: $login.exactSite)
                    }
                    SettingsGroup("Which bots may use it") {
                        YouToggleRow(title: "Only these bots", detail: onlyThese ? nil : "All bots may use it", isOn: $onlyThese)
                        if onlyThese {
                            ForEach(SampleData.allBots.filter { $0.members.isEmpty }) { bot in
                                YouToggleRow(title: bot.name, isOn: Binding(get: { login.bots.contains(bot.id) }, set: { on in
                                    if on { login.bots.append(bot.id) } else { login.bots.removeAll { $0 == bot.id } }
                                }))
                            }
                        }
                    }
                    if let note {
                        Text(note).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.danger)
                    }
                    GoldButton(title: login.id == "new" ? "Save login" : "Save changes") { save() }
                    QuietButton(title: "Cancel") { dismiss() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
        }
        .kSheet()
        .onAppear { onlyThese = !login.bots.isEmpty }
    }

    private func save() {
        guard !login.site.isEmpty, !login.username.isEmpty else {
            note = "Add the site and the username."
            return
        }
        guard login.id != "new" || !password.isEmpty else {
            note = "Add the password."
            return
        }
        if !onlyThese { login.bots = [] }
        login.twoStep = login.twoStep || !seed.isEmpty
        if login.id == "new" {
            var added = login
            added = BotLogin(id: UUID().uuidString, site: login.site, username: login.username, twoStep: login.twoStep, exactSite: login.exactSite, bots: login.bots, lastUsed: "never")
            sample.logins.append(added)
        } else if let index = sample.logins.firstIndex(where: { $0.id == login.id }) {
            sample.logins[index] = login
        }
        YouStore.shared.say("Login saved. The password is encrypted and will not be shown again.")
        dismiss()
    }
}

// MARK: - About you

struct AboutYouScreen: View {
    @Bindable private var sample = BotsSettingsSample.shared
    @State private var status = "Saved"
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        SettingsPage("About you", subtitle: "What every bot knows about you. It saves as you type.") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: "About you").padding(.leading, 6)
                    Text(status).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(status == "Saved" ? Palette.success : Palette.inkFaint)
                }
                TextEditor(text: $sample.aboutText)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .padding(12)
                    .kCard(radius: 22)
                    .overlay(alignment: .topLeading) {
                        if sample.aboutText.isEmpty {
                            Text("Anything every bot should know about you: your name, your work, how you like things done.")
                                .font(KFont.ui(16)).foregroundStyle(Palette.inkFaint).padding(18).allowsHitTesting(false)
                        }
                    }
                Text("\(sample.aboutText.count) of 4,000 characters")
                    .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).padding(.leading, 8)
            }
            SettingsGroup("Learned by your bots", footer: "Facts your bots pick up from chats. Remove any of them.") {
                if sample.learned.isEmpty {
                    EmptyRow(text: "Nothing learned yet.")
                }
                ForEach(sample.learned) { fact in
                    HStack(spacing: 8) {
                        RowLabel(title: fact.text, detail: "Learned by \(fact.bot), \(fact.when)")
                        YouPillButton(title: "Remove", danger: true) {
                            withAnimation(Motion.snappy) { sample.learned.removeAll { $0.id == fact.id } }
                            YouStore.shared.say("Removed. Bots will not learn that again.")
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
        }
        .onChange(of: sample.aboutText) {
            status = "Saving..."
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .seconds(0.8))
                if !Task.isCancelled { withAnimation(Motion.snappy) { status = "Saved" } }
            }
        }
    }
}

// MARK: - Skill library

struct SkillLibraryScreen: View {
    @Bindable private var sample = BotsSettingsSample.shared
    @State private var query = ""
    @State private var tag = "All"
    @State private var reviewing: LibrarySkill?
    @State private var link = ""
    @State private var pasted = ""
    @State private var removing: LibrarySkill?

    private var tags: [String] { ["All"] + Array(Set(sample.skills.flatMap(\.tags))).sorted() }

    private var shown: [LibrarySkill] {
        sample.skills.filter { skill in
            (tag == "All" || skill.tags.contains(tag))
                && (query.isEmpty || skill.name.contains(query.lowercased()) || skill.summary.lowercased().contains(query.lowercased()))
        }
    }

    var body: some View {
        SettingsPage("Skill library", subtitle: "Skills any bot can be given. Each one is read in full before it is switched on.") {
            if let share = sample.pendingShare {
                SettingsGroup("Waiting for you") {
                    VStack(alignment: .leading, spacing: 8) {
                        RowLabel(title: "Share /\(share)?", detail: "Atlas wants to add it to the library.", symbol: "bookmark")
                        HStack {
                            YouPillButton(title: "Share", prominent: true) {
                                withAnimation(Motion.snappy) {
                                    sample.skills.append(LibrarySkill(id: UUID().uuidString, name: share, origin: "Shared by Atlas", summary: "Keeps a trip under budget", tags: ["travel"], on: false, everyBot: false, body: "# Trip budget\n\nAdd up costs and flag anything over the limit."))
                                    sample.pendingShare = nil
                                }
                            }
                            YouPillButton(title: "Not now") { withAnimation(Motion.snappy) { sample.pendingShare = nil } }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            SearchField(prompt: "Search skills", text: $query)
            YouChipPicker(items: tags, selection: $tag) { $0 == "All" ? "All" : "#\($0)" }
            SettingsGroup(shown.count == sample.skills.count ? "Library (\(sample.skills.count))" : "Library (\(shown.count) of \(sample.skills.count))") {
                if shown.isEmpty {
                    EmptyRow(text: sample.skills.isEmpty ? "The library is empty." : "No skills match.")
                }
                ForEach(shown) { skill in
                    skillRow(skill)
                }
            }
            SettingsGroup("Add to the library", footer: "Imports stay off until you review them.") {
                FieldRow(title: "Import from a link", text: $link, prompt: "GitHub link or owner/repo", keyboard: .URL)
                ActionRow(title: "Import", symbol: "square.and.arrow.down") {
                    guard !link.isEmpty else { YouStore.shared.say("Paste a link first."); return }
                    let name = link.split(separator: "/").last.map(String.init) ?? "imported-skill"
                    withAnimation(Motion.snappy) {
                        sample.skills.append(LibrarySkill(id: UUID().uuidString, name: name.lowercased(), origin: "Imported", summary: "Imported from a link", tags: ["imported"], on: false, everyBot: false, body: "# \(name)\n\nImported. Read it before turning it on."))
                    }
                    link = ""
                    YouStore.shared.say("Imported 1 skill. It is off until you review it.")
                }
                FieldRow(title: "Paste a SKILL.md", text: $pasted, prompt: "# My skill ...")
                ActionRow(title: "Add pasted skill", symbol: "plus") {
                    guard !pasted.isEmpty else { YouStore.shared.say("Paste the skill first."); return }
                    withAnimation(Motion.snappy) {
                        sample.skills.append(LibrarySkill(id: UUID().uuidString, name: "pasted-skill", origin: "Pasted", summary: String(pasted.prefix(60)), tags: [], on: false, everyBot: false, body: pasted))
                    }
                    pasted = ""
                }
            }
        }
        .sheet(item: $reviewing) { skill in
            YouSkillReviewSheet(skill: skill)
        }
        .confirmationDialog("Remove /\(removing?.name ?? "") from the library?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let id = removing?.id { withAnimation(Motion.snappy) { sample.skills.removeAll { $0.id == id } } }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        }
    }

    private func skillRow(_ skill: LibrarySkill) -> some View {
        let index = sample.skills.firstIndex { $0.id == skill.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RowLabel(title: "/\(skill.name)", detail: "\(skill.origin) · \(skill.summary)\(skill.tags.isEmpty ? "" : " · " + skill.tags.map { "#\($0)" }.joined(separator: " "))")
                if skill.warning { StatusPill(text: "Warning", tone: .bad) }
                StatusPill(text: skill.on ? "On" : "Off", tone: skill.on ? .ok : .muted)
            }
            HStack(spacing: 6) {
                if skill.on {
                    YouPillButton(title: "Turn off") {
                        if let index { withAnimation(Motion.snappy) { sample.skills[index].on = false } }
                    }
                } else {
                    YouPillButton(title: "Review and turn on", prominent: true) { reviewing = skill }
                }
                YouPillButton(title: "Read") { reviewing = skill }
                YouPillButton(title: "Remove", danger: true) { removing = skill }
            }
            if skill.on, let index {
                Toggle("Every bot", isOn: Binding(get: { sample.skills[index].everyBot }, set: { sample.skills[index].everyBot = $0 }))
                    .font(KFont.ui(15)).foregroundStyle(Palette.ink).tint(Palette.gold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct YouSkillReviewSheet: View {
    let skill: LibrarySkill
    @Environment(\.dismiss) private var dismiss
    private let sample = BotsSettingsSample.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("/\(skill.name)").font(KFont.ui(22, .semibold, relativeTo: .title2)).foregroundStyle(Palette.ink).padding(.top, 30)
                Text("Source: \(skill.origin) · 2 saved versions").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                if skill.warning {
                    NoteText(text: "This skill runs a shell command. Read it in full before you turn it on.", symbol: "exclamationmark.triangle")
                }
                Text(skill.body)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kCard(radius: 18)
                if !skill.on {
                    GoldButton(title: "Enable reviewed skill") {
                        if let index = sample.skills.firstIndex(where: { $0.id == skill.id }) {
                            sample.skills[index].on = true
                        }
                        YouStore.shared.say("/\(skill.name) is on")
                        dismiss()
                    }
                }
                QuietButton(title: "Close") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .kSheet()
    }
}

// MARK: - Usage and spend, housekeeping

struct BotUsageScreen: View {
    @Bindable private var sample = BotsSettingsSample.shared
    @State private var capText = ""

    private let perBot: [(String, Double)] = [("scout", 12.4), ("producer", 9.1), ("kip", 6.3), ("quill", 3.8)]

    var body: some View {
        SettingsPage("Usage and spend", subtitle: "What your bots used this month, at list prices.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "$%.2f", sample.spent)).font(KFont.ui(34, .semibold)).foregroundStyle(Palette.ink)
                    Text("this month").font(KFont.ui(15)).foregroundStyle(Palette.inkFaint)
                    Spacer()
                }
                if sample.monthlyCap > 0 {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.ink.opacity(0.1))
                            Capsule().fill(ratio > 0.8 ? Palette.danger : Palette.gold)
                                .frame(width: proxy.size.width * min(1, ratio))
                        }
                    }
                    .frame(height: 10)
                    Text(ratio >= 1 ? "Monthly spend cap reached. Raise it below." : ratio > 0.8 ? "Bot usage is near the monthly spend cap." : "\(Int(ratio * 100))% of your $\(sample.monthlyCap) cap")
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(ratio > 0.8 ? Palette.danger : Palette.inkDim)
                }
            }
            .padding(16)
            .kCard(radius: 22)

            SettingsGroup("Monthly spend cap", footer: "List-price equivalent, not billed. Unknown costs are excluded. Prices as of October 2026.") {
                FieldRow(title: "Cap in US dollars", text: $capText, prompt: "No cap", keyboard: .numberPad)
                ActionRow(title: "Save cap", symbol: "checkmark", tone: .gold) {
                    let value = Int(capText) ?? 0
                    withAnimation(Motion.snappy) { sample.monthlyCap = value }
                    YouStore.shared.say(value == 0 ? "No cap" : "Cap saved: $\(value) a month")
                }
            }
            SettingsGroup("By bot") {
                ForEach(perBot, id: \.0) { item in
                    let bot = SampleData.bot(item.0)
                    HStack(spacing: 12) {
                        BotFace(bot: bot, size: 36)
                        Text(bot.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(String(format: "$%.2f", item.1)).font(KFont.ui(15, .medium)).foregroundStyle(Palette.inkDim).monospacedDigit()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                }
            }
            YouNavRow(title: "Housekeeping", detail: "How long run details are kept", symbol: "archivebox", to: .botHousekeeping)
                .kCard(radius: 22)
        }
        .onAppear { capText = sample.monthlyCap == 0 ? "" : "\(sample.monthlyCap)" }
    }

    private var ratio: Double { sample.monthlyCap > 0 ? sample.spent / Double(sample.monthlyCap) : 0 }
}

struct BotHousekeepingScreen: View {
    @Bindable private var sample = BotsSettingsSample.shared

    var body: some View {
        SettingsPage("Housekeeping", subtitle: "Remove old trace details. Run totals and usage history are kept.") {
            SettingsGroup {
                YouStepperRow(title: "Keep trace details", value: $sample.traceDays, range: 1...3650, unit: "days")
                YouStepperRow(title: "Trace size cap", value: $sample.traceMegabytes, range: 1...4096, step: 16, unit: "MB")
                ActionRow(title: "Save housekeeping", symbol: "checkmark", tone: .gold) {
                    YouStore.shared.say("Saved. Applies on the next daily cleanup.")
                }
            }
        }
    }
}

// MARK: - Templates

struct BotTemplatesScreen: View {
    var startMode = "Explore"
    @State private var mode = "Explore"
    @State private var importing = false
    @State private var chosen: Set<String> = ["scout", "quill"]
    @State private var routines = true
    @State private var teams = true
    @State private var rooms = true
    @State private var previewOpen = false
    @State private var added: Set<String> = []

    private let teamsOffered: [(String, String, Int)] = [
        ("Content team", "A producer, a researcher and a writer who post on a schedule", 3),
        ("Shop helpers", "Orders, stock and receipts for a small shop", 2),
        ("Study group", "A tutor and a quiz maker for one subject", 2),
    ]

    var body: some View {
        SettingsPage("Templates", subtitle: "Ready-made teams, and bot personas to import or share.") {
            GlassSwitch(items: ["Explore", "Import", "Share"], selection: $mode) { $0 }
            switch mode {
            case "Import":
                SettingsGroup(footer: "A JSON or Markdown package, up to 4 MB.") {
                    ActionRow(title: "Choose a package", symbol: "doc.badge.plus", tone: .gold) { importing = true }
                }
                NoteText(text: "Bringing bots in from a folder works on your desktop.")
            case "Share":
                SettingsGroup("Share bot personas", footer: "Preview what travels. Keys, models, access and chats stay here.") {
                    ForEach(SampleData.allBots.filter { !$0.isKip && $0.members.isEmpty }) { bot in
                        YouToggleRow(title: bot.name, detail: bot.role, isOn: Binding(get: { chosen.contains(bot.id) }, set: { on in
                            if on { chosen.insert(bot.id) } else { chosen.remove(bot.id) }
                        }))
                    }
                }
                SettingsGroup {
                    YouToggleRow(title: "Include paused routines", isOn: $routines)
                    YouToggleRow(title: "Include their teams", isOn: $teams)
                    YouToggleRow(title: "Include their rooms", isOn: $rooms)
                    ActionRow(title: "Preview export", symbol: "eye") { previewOpen = true }
                    ShareLink(item: packageText, preview: SharePreview("bots.kairos.json")) {
                        RowLabel(title: "Share the package", symbol: "square.and.arrow.up", tint: Palette.goldText, titleColor: Palette.goldText)
                            .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .disabled(chosen.isEmpty)
                }
            default:
                Text("A team for your work").font(KFont.display(28)).foregroundStyle(Palette.ink).padding(.horizontal, 4)
                ForEach(teamsOffered, id: \.0) { team in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: -10) {
                            ForEach(Array(SampleData.allBots.filter { !$0.isKip && $0.members.isEmpty }.prefix(team.2).enumerated()), id: \.offset) { _, bot in
                                BotFace(bot: bot, size: 42)
                            }
                        }
                        Text(team.0).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                        Text(team.1).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                        HStack {
                            if added.contains(team.0) {
                                StatusPill(text: "Added \(team.2) bots", tone: .ok)
                            } else {
                                YouPillButton(title: "Add", prominent: true) {
                                    withAnimation(Motion.snappy) { _ = added.insert(team.0) }
                                    YouStore.shared.say("Added \(team.2) bots.")
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kCard(radius: 22)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, UTType(filenameExtension: "md") ?? .plainText]) { result in
            if case .success(let url) = result {
                YouStore.shared.say("Read \(url.lastPathComponent). Review it in Bots.")
            }
        }
        .sheet(isPresented: $previewOpen) {
            FittedSheet(estimate: 420) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What travels").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink).padding(.top, 30)
                    Text(packageText).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14).kCard(radius: 16)
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .onAppear { mode = startMode }
    }

    private var packageText: String {
        let names = SampleData.bots(Array(chosen).sorted()).map { "\"\($0.name)\"" }.joined(separator: ", ")
        return "{\n  \"bots\": [\(names)],\n  \"routines\": \(routines),\n  \"teams\": \(teams),\n  \"rooms\": \(rooms)\n}"
    }
}

// MARK: - Bot computers

struct BotComputersScreen: View {
    @Bindable private var sample = BotsSettingsSample.shared
    @State private var checking = false

    var body: some View {
        SettingsPage("Bot computers", subtitle: "Contained computers on your desktop that bots use to browse and work.") {
            Button {
                checking = true
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    checking = false
                    YouStore.shared.say("Docker is ready")
                }
            } label: {
                Text(checking ? "Checking..." : "Check again").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16).frame(height: 44)
            }
            .buttonStyle(PressStyle())
            .kGlass(Capsule(), interactive: true)
        } content: {
            SettingsGroup("Computer runtime") {
                StatusRow(title: "Docker", detail: "Runs each computer in its own box", symbol: "shippingbox", status: "Ready")
            }
            SettingsGroup("Limits") {
                YouStepperRow(title: "Running computers", value: $sample.maxComputers, range: 1...8)
                YouStepperRow(title: "Idle minutes", detail: "Sleep after this long", value: $sample.idleMinutes, range: 5...1440, step: 5)
                ActionRow(title: "Save limits", symbol: "checkmark", tone: .gold) { YouStore.shared.say("Limits saved") }
            }
            SettingsGroup("Computers") {
                if sample.computers.isEmpty { EmptyRow(text: "No bot computers") }
                ForEach(Array(sample.computers.enumerated()), id: \.offset) { index, computer in
                    let bot = SampleData.bot(computer.bot)
                    HStack(spacing: 12) {
                        BotFace(bot: bot, size: 38)
                        RowLabel(title: bot.name, detail: computer.state)
                        if computer.state != "Asleep" {
                            YouPillButton(title: "Sleep") {
                                withAnimation(Motion.snappy) { sample.computers[index].state = "Asleep" }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6).frame(minHeight: 56)
                }
            }
        }
    }
}

// MARK: - Connected apps

struct ConnectedAppsScreen: View {
    @Bindable private var sample = BotsSettingsSample.shared
    @State private var query = ""
    @State private var show = "All"
    @State private var open: String?
    @State private var editing: BotMCPServer?
    @State private var aliases: [String: String] = [:]

    private var apps: [BotApp] {
        sample.apps.filter { app in
            (show == "All" || (show == "Connected" && app.state == "Connected"))
                && (query.isEmpty || app.name.lowercased().contains(query.lowercased()))
        }
    }

    var body: some View {
        SettingsPage("Connected apps", subtitle: "The apps and tool servers your bots can use. Each bot gets only the ones you choose in its Access settings.") {
            NoteText(text: "Ledger has no apps. Allow some in its Access settings.", symbol: "exclamationmark.triangle")
            SearchField(prompt: "Search apps", text: $query)
            YouChipPicker(items: ["All", "Connected", "MCP"], selection: $show) { $0 }

            if show != "MCP" {
                ForEach(Array(Set(apps.map(\.category))).sorted(), id: \.self) { category in
                    SettingsGroup(category) {
                        ForEach(apps.filter { $0.category == category }) { app in
                            appRow(app)
                        }
                    }
                }
                if apps.isEmpty { EmptyRow(text: "No apps match.").kCard(radius: 22) }
            }

            SettingsGroup("MCP servers (\(sample.servers.count) of 20)", footer: "Servers that run a command on your desktop are added there. Bringing them in from your other tools also happens on the desktop.") {
                ForEach(sample.servers) { server in
                    serverRow(server)
                }
                ActionRow(title: "Add an MCP server", symbol: "plus", tone: .gold) {
                    editing = BotMCPServer(id: "new", name: "", address: "", on: true, health: "Not checked yet")
                }
            }
        }
        .sheet(item: $editing) { server in
            MCPServerEditSheet(server: server)
        }
    }

    private func appRow(_ app: BotApp) -> some View {
        let expanded = open == app.id
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.select()
                withAnimation(Motion.snappy) { open = expanded ? nil : app.id }
            } label: {
                HStack(spacing: 10) {
                    Text(String(app.name.prefix(1)))
                        .font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink)
                        .frame(width: 34, height: 34).background(Palette.ink.opacity(0.1), in: Circle())
                    RowLabel(title: app.name, detail: app.detail)
                    StatusPill(text: app.state, tone: app.state == "Connected" ? .ok : app.state == "Problem" ? .bad : .warn)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Used by \(app.usedBy.joined(separator: ", "))").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    ForEach(app.accounts, id: \.self) { account in
                        HStack {
                            TextField("Alias", text: Binding(get: { aliases["\(app.id)-\(account)"] ?? account }, set: { aliases["\(app.id)-\(account)"] = $0 }))
                                .font(KFont.ui(15)).foregroundStyle(Palette.ink)
                            StatusPill(text: app.state == "Connected" ? "Connected" : "Reconnect", tone: app.state == "Connected" ? .ok : .warn)
                        }
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    HStack(spacing: 6) {
                        YouPillButton(title: "Save alias") { YouStore.shared.say("Alias saved") }
                        if app.state != "Connected" {
                            YouPillButton(title: "Reconnect", prominent: true) { reconnect(app) }
                        }
                        YouPillButton(title: "Disconnect", danger: true) {
                            if let index = sample.apps.firstIndex(where: { $0.id == app.id }) {
                                withAnimation(Motion.snappy) { sample.apps[index].state = "Not connected" }
                            }
                        }
                    }
                    if app.category == "Google" {
                        Text("To add another Google account, finish signing in on your desktop.").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func reconnect(_ app: BotApp) {
        guard let index = sample.apps.firstIndex(where: { $0.id == app.id }) else { return }
        sample.apps[index].state = "Waiting"
        YouStore.shared.say("Finish signing in on your desktop")
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(Motion.snappy) { sample.apps[index].state = "Connected" }
        }
    }

    private func serverRow(_ server: BotMCPServer) -> some View {
        let index = sample.servers.firstIndex { $0.id == server.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                RowLabel(title: server.name, detail: server.address)
                if let index {
                    Toggle("Turn \(server.name) on", isOn: Binding(get: { sample.servers[index].on }, set: { on in
                        sample.servers[index].on = on
                        sample.servers[index].health = on ? "Not checked yet" : "Turned off"
                    }))
                    .labelsHidden().tint(Palette.gold)
                }
            }
            HStack(spacing: 6) {
                StatusPill(text: server.health, tone: server.health.hasPrefix("Working") ? .ok : .muted)
                Spacer()
                YouPillButton(title: "Test") {
                    guard let index, sample.servers[index].on else { return }
                    sample.servers[index].health = "Checking..."
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        withAnimation(Motion.snappy) { sample.servers[index].health = "Working · 12 tools" }
                    }
                }
                YouPillButton(title: "Edit") { editing = server }
                YouPillButton(title: "Remove", danger: true) {
                    withAnimation(Motion.snappy) { sample.servers.removeAll { $0.id == server.id } }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct MCPServerEditSheet: View {
    @State var server: BotMCPServer
    @Environment(\.dismiss) private var dismiss
    @State private var note: String?
    private let sample = BotsSettingsSample.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(server.id == "new" ? "Add an MCP server" : "Edit \(server.name)").font(KFont.ui(22, .semibold, relativeTo: .title2)).foregroundStyle(Palette.ink)
                        .padding(.top, 30)
                    SettingsGroup(footer: "Lowercase, up to 32 characters. It cannot change once added.") {
                        FieldRow(title: "Name", text: $server.name, prompt: "my-server")
                    }
                    SettingsGroup("Remote link", footer: "Local commands run on your desktop, so they are added there.") {
                        FieldRow(title: "Address", text: $server.address, prompt: "https://", keyboard: .URL)
                        PickRow(title: "Connection type", selection: $server.transport, options: ["HTTP", "Stream (SSE)"]) { $0 }
                    }
                    SettingsGroup("Limits") {
                        YouStepperRow(title: "Longest call", value: $server.longestCall, range: 1...60, unit: "min")
                    }
                    if let note {
                        Text(note).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.danger)
                    }
                    GoldButton(title: server.id == "new" ? "Add server" : "Save changes") { save() }
                    QuietButton(title: "Cancel") { dismiss() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .kSheet()
    }

    private func save() {
        let name = server.name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= 32 else {
            note = "Give it a name of up to 32 letters."
            return
        }
        guard server.address.hasPrefix("http://") || server.address.hasPrefix("https://") else {
            note = "The address must start with http or https."
            return
        }
        server.name = name
        if server.id == "new" {
            guard sample.servers.count < 20 else {
                note = "Twenty servers is the most. Remove one first."
                return
            }
            sample.servers.append(BotMCPServer(id: UUID().uuidString, name: name, address: server.address, on: true, health: "Not checked yet", transport: server.transport, longestCall: server.longestCall))
        } else if let index = sample.servers.firstIndex(where: { $0.id == server.id }) {
            sample.servers[index] = server
        }
        YouStore.shared.say("Saved \(name)")
        dismiss()
    }
}

enum BotsSettingsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "bots-prefs": return AnyView(BotPrefsScreen())
        case "bots-checklist": return AnyView(BotPrefsScreen(startChecklist: true))
        case "bots-keys": return AnyView(BotKeysScreen())
        case "bots-logins": return AnyView(BotLoginsScreen())
        case "bots-login-add": return AnyView(BotLoginsScreen(startEditing: true))
        case "bots-about": return AnyView(AboutYouScreen())
        case "bots-skills": return AnyView(SkillLibraryScreen())
        case "bots-usage": return AnyView(BotUsageScreen())
        case "bots-housekeeping": return AnyView(BotHousekeepingScreen())
        case "bots-templates": return AnyView(BotTemplatesScreen())
        case "bots-templates-share": return AnyView(BotTemplatesScreen(startMode: "Share"))
        case "bots-computers": return AnyView(BotComputersScreen())
        case "bots-apps": return AnyView(ConnectedAppsScreen())
        default: return nil
        }
    }
}
