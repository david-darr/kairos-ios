import SwiftUI
import UIKit

// Permissions, Agent tools, Computer use, Remote access (with paired phones) and Forge settings.
// Everything runs on made-up sample data until the desktop connection fills it in.

// MARK: - Sample data

nonisolated struct AccessGrant: Identifiable, Hashable, Sendable {
    let id: String
    var tool: String
    var content: String?
    var allowed: Bool
    var scope: String
    var who: String
    var date: String
}

nonisolated struct AccessDecision: Identifiable, Hashable, Sendable {
    let id: String
    var when: String
    var decision: String
    var tool: String
    var content: String?
    var by: String?

    var line: String {
        var parts = [when, decision]
        if let content {
            parts.append("\(tool) (\(content))")
        } else {
            parts.append(tool)
        }
        if let by { parts.append(by) }
        return parts.joined(separator: " · ")
    }
}

nonisolated struct AccessTerminal: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var words: String
    var paired: String
    var endsBy: String
}

nonisolated struct AccessToolSwitch: Identifiable, Hashable, Sendable {
    let id: String
    var about: String
    var on: Bool
}

nonisolated struct AccessProfile: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var owner: String
}

nonisolated struct AccessComputer: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var owner: String
    var url: String
    var desktop: Bool
}

nonisolated struct AccessSetupStep: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var doneHint: String
    var neededHint: String
    var done: Bool
}

/// A phone paired with the desktop (GET /api/phone/devices).
nonisolated struct AccessPairedDevice: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var model: String
    var symbol: String
    var paired: String
    var lastSeen: String
    var current: Bool
}

nonisolated enum AccessSample {
    static let grants: [AccessGrant] = [
        AccessGrant(id: "g1", tool: "Bash", content: "git status", allowed: true, scope: "Allowed everywhere", who: "granted by Sam", date: "Nov 10, 9:14"),
        AccessGrant(id: "g2", tool: "Read", content: nil, allowed: true, scope: "Allowed everywhere", who: "built in", date: "Oct 2"),
        AccessGrant(id: "g3", tool: "WebFetch", content: "example.com", allowed: true, scope: "Allowed in this chat only", who: "granted by Sam", date: "Today, 8:02"),
        AccessGrant(id: "g4", tool: "Bash", content: "rm -rf", allowed: false, scope: "Denied for admins only, everywhere", who: "built in", date: "Oct 2"),
    ]

    static let decisions: [AccessDecision] = [
        AccessDecision(id: "d1", when: "Today, 9:41", decision: "Allowed once", tool: "Bash", content: "npm test", by: "Sam"),
        AccessDecision(id: "d2", when: "Today, 8:02", decision: "Allowed in this chat", tool: "WebFetch", content: "example.com", by: "Sam"),
        AccessDecision(id: "d3", when: "Yesterday, 17:20", decision: "Denied", tool: "Write", content: "prices.xlsx", by: "Sam"),
        AccessDecision(id: "d4", when: "Nov 10, 9:14", decision: "Always allowed", tool: "Bash", content: "git status", by: "Sam"),
    ]

    static let terminals: [AccessTerminal] = [
        AccessTerminal(id: "t1", name: "Terminal 1", words: "amber otter river", paired: "today, 8:02", endsBy: "20:02"),
        AccessTerminal(id: "t2", name: "Terminal 2", words: "quiet maple stone", paired: "today, 9:30", endsBy: "21:30"),
    ]

    static let tools: [AccessToolSwitch] = [
        AccessToolSwitch(id: "Read", about: "Read files", on: true),
        AccessToolSwitch(id: "Write", about: "Create files", on: true),
        AccessToolSwitch(id: "Edit", about: "Change files", on: true),
        AccessToolSwitch(id: "Bash", about: "Run commands", on: true),
        AccessToolSwitch(id: "Glob", about: "Find files by name", on: true),
        AccessToolSwitch(id: "Grep", about: "Search inside files", on: true),
        AccessToolSwitch(id: "WebSearch", about: "Search the web", on: true),
        AccessToolSwitch(id: "WebFetch", about: "Open a web page", on: false),
        AccessToolSwitch(id: "TodoWrite", about: "Keep a task list", on: true),
    ]

    static let profiles: [AccessProfile] = [
        AccessProfile(id: "p1", name: "Scout", owner: "scout"),
        AccessProfile(id: "p2", name: "Shop orders", owner: "kip"),
    ]

    static let computers: [AccessComputer] = [
        AccessComputer(id: "c1", title: "Price check", owner: "scout", url: "https://example.com/parts", desktop: false),
        AccessComputer(id: "c2", title: "Invoice tidy", owner: "ledger", url: "https://example.com/invoices", desktop: true),
    ]

    static let setupSteps: [AccessSetupStep] = [
        AccessSetupStep(id: "installed", title: "Tailscale installed", doneHint: "Found on the desktop.",
                        neededHint: "Tailscale is a free private network for your own devices. Install it on the desktop, then refresh.", done: true),
        AccessSetupStep(id: "signedIn", title: "Signed in to Tailscale", doneHint: "Connected as kairos-desk.",
                        neededHint: "Open the Tailscale app on the desktop and sign in, then refresh.", done: true),
        AccessSetupStep(id: "firewall", title: "Allowed through Windows Firewall", doneHint: "Incoming connections to Kairos are allowed.",
                        neededHint: "Windows is blocking incoming connections, so no other device can reach Kairos. Allow it on the desktop; Windows asks first.", done: false),
        AccessSetupStep(id: "login", title: "Kairos login", doneHint: "A login is set up.", neededHint: "", done: false),
    ]

    static let devices: [AccessPairedDevice] = [
        AccessPairedDevice(id: "d_this", name: "iPhone", model: "iPhone", symbol: "iphone", paired: "Nov 3", lastSeen: "now", current: true),
        AccessPairedDevice(id: "d_old", name: "iPad", model: "iPad", symbol: "ipad", paired: "Sep 20", lastSeen: "12 days ago", current: false),
    ]

    static let host = "kairos-desk.tailnet-example.ts.net"
    static let forgeRoot = "C:\\Users\\sam\\Kairos\\Forge"
}

private func accessCopy(_ text: String, _ message: String) {
    UIPasteboard.general.string = text
    Haptics.success()
    YouStore.shared.say(message)
}

/// A row that only explains something: an icon, a title and a line of detail.
private struct AccessInfoRow: View {
    let title: String
    let detail: String
    var symbol: String? = nil

    var body: some View {
        RowLabel(title: title, detail: detail, symbol: symbol)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
    }
}

/// A row with a title, a pill beside it, lines of detail and a control on the right.
private struct AccessItemRow<Trailing: View>: View {
    let title: String
    var pill: String? = nil
    var pillTone: StatusPill.Tone = .ok
    var mono: String? = nil
    var detail: String? = nil
    var symbol: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(KFont.ui(16, .medium))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pill { StatusPill(text: pill, tone: pillTone) }
                }
                if let mono {
                    Text(mono)
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(Palette.inkDim)
                        .lineLimit(2)
                }
                if let detail {
                    Text(detail)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
    }
}

// MARK: - Permissions

struct PermissionsScreen: View {
    @State private var grants: [AccessGrant]
    @State private var terminals: [AccessTerminal]
    @State private var showDecisions: Bool
    @State private var revoking: Set<String> = []
    @State private var problem: String?
    private let decisions = AccessSample.decisions

    init(startEmpty: Bool = false, showDecisions: Bool = false, startFailed: Bool = false) {
        _grants = State(initialValue: startEmpty ? [] : AccessSample.grants)
        _terminals = State(initialValue: startEmpty ? [] : AccessSample.terminals)
        _showDecisions = State(initialValue: showDecisions)
        _problem = State(initialValue: startFailed ? "Could not revoke that grant. The desktop did not answer. Try again." : nil)
    }

    var body: some View {
        SettingsPage("Permissions", subtitle: "What chats and bots may do without asking, and who decided.") {
            if let problem {
                NoteText(text: problem, symbol: "exclamationmark.triangle")
            }

            SettingsGroup("Standing grants", footer: "Revoke a grant and Kairos asks again the next time.") {
                if grants.isEmpty {
                    EmptyRow(text: "Nothing is granted yet.")
                } else {
                    ForEach(grants) { grant in
                        AccessItemRow(title: grant.tool, pill: grant.allowed ? "Allowed" : "Denied", pillTone: grant.allowed ? .ok : .bad,
                                      mono: grant.content, detail: "\(grant.scope) · \(grant.who) · \(grant.date)") {
                            if revoking.contains(grant.id) {
                                StatusPill(text: "Revoking...", tone: .muted)
                            } else {
                                YouPillButton(title: "Revoke", danger: true) { revoke(grant) }
                            }
                        }
                    }
                }
            }
            .arrives(0)

            SettingsGroup("Paired terminals", footer: "Kairos terminals paired from the desktop. Each one ends when its terminal closes, or after 12 hours.") {
                if terminals.isEmpty {
                    EmptyRow(text: "No terminal is paired. Run kairos in a terminal on the desktop to pair one.")
                } else {
                    ForEach(terminals) { terminal in
                        AccessItemRow(title: terminal.name, mono: terminal.words, detail: "Paired \(terminal.paired) · ends by \(terminal.endsBy)", symbol: "terminal") {
                            YouPillButton(title: "Revoke", danger: true) { revokeTerminal(terminal) }
                        }
                    }
                }
            }
            .arrives(1)

            if !decisions.isEmpty {
                SettingsGroup {
                    ActionRow(title: "Recent decisions", detail: "Newest first", symbol: "clock", trailing: showDecisions ? "Hide" : "Show") {
                        withAnimation(Motion.snappy) { showDecisions.toggle() }
                    }
                    if showDecisions {
                        ForEach(decisions) { decision in
                            Text(decision.line)
                                .font(KFont.ui(14, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkDim)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .transition(.opacity)
                        }
                    }
                }
                .arrives(2)
            }
        }
    }

    private func revoke(_ grant: AccessGrant) {
        guard !revoking.contains(grant.id) else { return }
        problem = nil
        revoking.insert(grant.id)
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(Motion.snappy) {
                grants.removeAll { $0.id == grant.id }
                revoking.remove(grant.id)
            }
            Haptics.success()
            YouStore.shared.say("Revoked. Kairos asks next time.")
        }
    }

    private func revokeTerminal(_ terminal: AccessTerminal) {
        withAnimation(Motion.snappy) { terminals.removeAll { $0.id == terminal.id } }
        Haptics.success()
        YouStore.shared.say("\(terminal.name) is no longer paired.")
    }
}

// MARK: - Agent tools

struct AgentToolsScreen: View {
    @State private var tools = AccessSample.tools
    @State private var extra = "mcp__design__create_page\nmcp__tracker__list_issues"

    var body: some View {
        SettingsPage("Agent tools", subtitle: "The tools every chat and bot may use.") {
            SettingsGroup("Built-in tools", footer: "Switch a tool off to keep it out of every chat.") {
                ForEach($tools) { $tool in
                    YouToggleRow(title: tool.id, detail: tool.about, isOn: $tool.on)
                }
            }
            .arrives(0)

            GoldButton(title: "Save") {
                Haptics.success()
                let off = tools.filter { !$0.on }.count
                YouStore.shared.say(off == 0 ? "Saved. Every tool is on." : "Saved. \(off) off.")
            }
            .arrives(1)

            SettingsGroup("Extra allowed tools", footer: "Exact tool server tool names beyond the built-in list, one per line. When a tool is blocked mid-chat, the error names it.") {
                TextEditor(text: $extra)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 120)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Extra allowed tools, one per line")
                RowButtons {
                    YouPillButton(title: "Save extra tools", prominent: true) { saveExtra() }
                }
            }
            .arrives(2)

            NoteText(text: "Open chats pick up changes on their next message.", symbol: "info.circle")
                .arrives(3)
        }
    }

    private func saveExtra() {
        let names = extra.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        extra = names.joined(separator: "\n")
        Haptics.success()
        YouStore.shared.say("Saved. Open chats pick it up on their next message.")
    }
}

// MARK: - Computer use

struct ComputerUseScreen: View {
    @State private var enabled = true
    @State private var allowNonAdmins = false
    @State private var agentDesktop = false
    @State private var reactions = false
    @State private var keepDays = 7
    @State private var dockerReady: Bool
    @State private var profiles = AccessSample.profiles
    @State private var computers = AccessSample.computers
    @State private var deleteTarget: AccessProfile?

    init(dockerReady: Bool = true) {
        _dockerReady = State(initialValue: dockerReady)
    }

    var body: some View {
        SettingsPage("Computer use", subtitle: "Contained browsers and desktops that chats and bots can open.") {
            SettingsGroup("Access") {
                YouToggleRow(title: "Computer use", detail: "Allow chats and agents to open contained browsers.", isOn: $enabled)
                YouToggleRow(title: "Allow non-admins", detail: "Let other signed-in people use computers in their own chats.", isOn: $allowNonAdmins)
                YouToggleRow(title: "Agent desktop", detail: "A file manager, editor, PDF viewer and LibreOffice beside the browser, for admins. A larger first download. Applies when a computer next starts.", isOn: $agentDesktop)
                YouToggleRow(title: "Let the computer like, follow and react for you", detail: "Off: it stops before Like, Follow and similar buttons and asks you. Buying, sending and posting always stay with you.", isOn: $reactions)
            }
            .arrives(0)

            SettingsGroup("Steps", footer: "Before and after screenshots of each step, for the Steps view. Private fields are never kept.") {
                PickRow(title: "Keep computer steps", selection: $keepDays, options: [7, 1, 30, 0]) { days in
                    switch days {
                    case 0: return "Do not keep"
                    case 1: return "1 day"
                    default: return "\(days) days"
                    }
                }
            }
            .arrives(1)

            SettingsGroup("Docker") {
                if dockerReady {
                    StatusRow(title: "Docker", detail: "The computer image is ready. The desktop image is prepared on first use.", symbol: "cube", status: "Ready")
                } else {
                    StatusRow(title: "Docker", detail: "Docker is not running on the desktop. Start it there to use contained browsers.", symbol: "cube", status: "Unavailable", tone: .bad)
                    ActionRow(title: "Check again", symbol: "arrow.clockwise", tone: .gold) {
                        withAnimation(Motion.snappy) { dockerReady = true }
                        YouStore.shared.say("Docker is ready.")
                    }
                }
            }
            .arrives(2)

            SettingsGroup("Kept browser profiles", footer: "Saved logins for a bot's browser. A profile in use cannot be deleted until its computer stops.") {
                if profiles.isEmpty {
                    EmptyRow(text: "No kept profiles.")
                } else {
                    ForEach(profiles) { profile in
                        AccessItemRow(title: profile.name, detail: "Saved browser logins", symbol: "person.crop.circle") {
                            if isRunning(profile) {
                                StatusPill(text: "In use", tone: .working)
                            } else {
                                YouPillButton(title: "Delete", danger: true) { deleteTarget = profile }
                            }
                        }
                    }
                }
            }
            .arrives(3)

            SettingsGroup("Running computers") {
                if computers.isEmpty {
                    EmptyRow(text: "No computers running.")
                } else {
                    ForEach(computers) { computer in
                        AccessItemRow(title: computer.title, mono: computer.url,
                                      detail: "\(SampleData.bot(computer.owner).name) · \(computer.desktop ? "Desktop" : "Browser")",
                                      symbol: computer.desktop ? "desktopcomputer" : "globe") {
                            YouPillButton(title: "Stop", danger: true) { stop(computer) }
                        }
                    }
                }
            }
            .arrives(4)
        }
        .onChange(of: enabled) { saved() }
        .onChange(of: allowNonAdmins) { saved() }
        .onChange(of: agentDesktop) { saved() }
        .onChange(of: reactions) { saved() }
        .onChange(of: keepDays) { YouStore.shared.say("Computer steps updated.") }
        .confirmationDialog(deleteTarget.map { "Delete \($0.name)'s saved logins?" } ?? "Delete saved logins?",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible, presenting: deleteTarget) { profile in
            Button("Delete", role: .destructive) { delete(profile) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The bot's browser forgets these logins and has to sign in again.")
        }
    }

    private func isRunning(_ profile: AccessProfile) -> Bool {
        computers.contains { $0.owner == profile.owner }
    }

    private func saved() {
        YouStore.shared.say("Saved.")
    }

    private func delete(_ profile: AccessProfile) {
        withAnimation(Motion.snappy) { profiles.removeAll { $0.id == profile.id } }
        Haptics.success()
        YouStore.shared.say("\(profile.name)'s logins deleted.")
    }

    private func stop(_ computer: AccessComputer) {
        withAnimation(Motion.snappy) { computers.removeAll { $0.id == computer.id } }
        Haptics.success()
        YouStore.shared.say("\(computer.title) stopped.")
    }
}

// MARK: - Remote access

private enum AccessRemoteMode { case setup, live, unavailable }
private enum AccessRemoteHealth { case live, reconnecting, expired }

struct RemoteAccessScreen: View {
    @State private var steps: [AccessSetupStep]
    @State private var mode: AccessRemoteMode
    @State private var health: AccessRemoteHealth
    @State private var hasAccount: Bool
    @State private var refreshing = false
    @State private var loginWorking = false
    @State private var enabling = false
    @State private var username = ""
    @State private var password = ""
    @State private var portText = "8422"
    @State private var savedPort = 8422
    @State private var portStatus = ""
    @State private var confirmTurnOff = false
    @State private var devices = AccessSample.devices
    @State private var unpairTarget: AccessPairedDevice?
    @FocusState private var portFocused: Bool

    /// startState: setup, ready, create, live, reconnecting, expired, unavailable.
    init(startState: String = "setup") {
        var steps = AccessSample.setupSteps
        var mode = AccessRemoteMode.setup
        var health = AccessRemoteHealth.live
        var hasAccount = true
        switch startState {
        case "ready", "live", "reconnecting", "expired":
            for index in steps.indices { steps[index].done = true }
            if startState == "live" { mode = .live }
            if startState == "reconnecting" { mode = .live; health = .reconnecting }
            if startState == "expired" { mode = .live; health = .expired }
        case "create":
            hasAccount = false
        case "unavailable":
            mode = .unavailable
        default:
            break
        }
        _steps = State(initialValue: steps)
        _mode = State(initialValue: mode)
        _health = State(initialValue: health)
        _hasAccount = State(initialValue: hasAccount)
    }

    private var loginDone: Bool { steps.first { $0.id == "login" }?.done ?? false }

    private var allReady: Bool {
        steps.filter { ["installed", "signedIn", "login"].contains($0.id) }.allSatisfy { $0.done }
    }

    private var previewAddress: String { "https://\(AccessSample.host):\(Int(portText) ?? savedPort)" }
    private var liveAddress: String { "https://\(AccessSample.host):\(savedPort)" }

    var body: some View {
        SettingsPage("Remote access", subtitle: "Reach Kairos from your own devices, wherever you are.") {
            NoteText(text: "Remote access uses Tailscale, a private network between your own devices. Kairos is never open to the public internet.", symbol: "lock")
                .arrives(0)

            switch mode {
            case .setup: setupContent
            case .live: liveContent
            case .unavailable: unavailableContent
            }

            phonesGroup
                .arrives(6)
        }
        .onChange(of: portFocused) { _, focused in
            if !focused { savePort() }
        }
        .confirmationDialog(unpairTarget.map { $0.current ? "Unpair this \($0.name)?" : "Unpair \($0.name)?" } ?? "Unpair?",
                            isPresented: Binding(get: { unpairTarget != nil }, set: { if !$0 { unpairTarget = nil } }),
                            titleVisibility: .visible, presenting: unpairTarget) { device in
            Button(device.current ? "Unpair this phone" : "Unpair", role: .destructive) { unpair(device) }
            Button("Cancel", role: .cancel) {}
        } message: { device in
            Text(device.current
                 ? "This phone disconnects from your desktop at once. To use it again, pair it with a new code from the desktop."
                 : "Its connection stops at once. It can be paired again with a new code from the desktop.")
        }
    }

    // MARK: Setup

    @ViewBuilder private var setupContent: some View {
        SettingsGroup("Setup", footer: "These steps happen on your desktop. Refresh setup checks them again.") {
            ForEach(steps) { step in
                StatusRow(title: step.title, detail: hint(for: step), status: step.done ? "Done" : "Needed", tone: step.done ? .ok : .warn)
            }
            ActionRow(title: refreshing ? "Checking..." : "Refresh setup", symbol: "arrow.clockwise", tone: .gold) { refreshSetup() }
        }
        .arrives(1)

        if !loginDone {
            loginGroup.arrives(2)
        }

        SettingsGroup("Address", footer: "The port is part of the address you type. A new port saves when you leave the field.") {
            AccessItemRow(title: "Where Kairos will be reachable", pill: "Not live yet", pillTone: .muted, mono: previewAddress) {
                YouPillButton(title: "Copy") { accessCopy(previewAddress, "Address copied.") }
            }
            HStack(spacing: 10) {
                RowLabel(title: "Port", detail: portStatus.isEmpty ? nil : portStatus)
                TextField("8422", text: $portText)
                    .font(KFont.ui(16, .medium))
                    .foregroundStyle(Palette.goldText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($portFocused)
                    .frame(width: 80)
                    .accessibilityLabel("Port")
                if portText != String(savedPort) {
                    YouPillButton(title: "Save", prominent: true) {
                        if portFocused { portFocused = false } else { savePort() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
        }
        .arrives(3)

        SettingsGroup {
            if allReady {
                AccessInfoRow(title: "Last step: turn it on", detail: "Nothing is reachable until you do. It stays on across restarts.", symbol: "power")
                GoldButton(title: enabling ? "Setting up..." : "Turn on remote access") { turnOn() }
                    .padding(16)
            } else {
                AccessInfoRow(title: "Finish the setup steps first", detail: "Turning it on unlocks once Tailscale is signed in and you have a login.", symbol: "power")
            }
        }
        .arrives(4)

        NoteText(text: "The first time, Kairos asks Tailscale for an HTTPS certificate so browsers trust the connection. If your tailnet has HTTPS certificates off, the desktop says where to turn them on.")
            .arrives(5)
    }

    @ViewBuilder private var loginGroup: some View {
        if hasAccount {
            SettingsGroup("Turn on account login", footer: "An account already exists on the desktop, but logins are off. This turns them on. It does not create an account or change a password.") {
                ActionRow(title: loginWorking ? "Working..." : "Turn on account login", symbol: "lock", tone: .gold) { turnOnLogin() }
            }
        } else {
            SettingsGroup("Create your login", footer: "This turns on accounts for Kairos everywhere, the desktop included, so you sign in there too.") {
                FieldRow(title: "Username", text: $username, prompt: "Username")
                FieldRow(title: "Password", text: $password, prompt: "8 or more characters", secure: true)
                RowButtons {
                    YouPillButton(title: loginWorking ? "Creating..." : "Create account", prominent: true) { createLogin() }
                }
            }
        }
    }

    private func hint(for step: AccessSetupStep) -> String {
        if step.done { return step.doneHint }
        if step.id == "login" {
            return hasAccount
                ? "An account exists, but login is off. Turn it on below."
                : "Remote access needs a real login. Without one, anyone who reaches the desktop gets straight in."
        }
        return step.neededHint
    }

    private func refreshSetup() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            for index in steps.indices where !steps[index].done {
                try? await Task.sleep(for: .seconds(0.4))
                withAnimation(Motion.bouncy) { steps[index].done = true }
                Haptics.select()
            }
            refreshing = false
            Haptics.success()
            YouStore.shared.say("Setup checked. Every step is done.")
        }
    }

    private func setLoginDone() {
        if let index = steps.firstIndex(where: { $0.id == "login" }) {
            withAnimation(Motion.bouncy) { steps[index].done = true }
        }
    }

    private func turnOnLogin() {
        guard !loginWorking else { return }
        loginWorking = true
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            loginWorking = false
            setLoginDone()
            Haptics.success()
            YouStore.shared.say("Login is on. Sign in with your existing account.")
        }
    }

    private func createLogin() {
        guard !loginWorking else { return }
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !password.isEmpty else {
            Haptics.thud()
            YouStore.shared.say("Enter a username and password.")
            return
        }
        guard password.count >= 8 else {
            Haptics.thud()
            YouStore.shared.say("Use 8 or more characters for the password.")
            return
        }
        loginWorking = true
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            loginWorking = false
            password = ""
            setLoginDone()
            Haptics.success()
            YouStore.shared.say("Account created. You sign in with it from now on.")
        }
    }

    private func savePort() {
        guard let value = Int(portText.trimmingCharacters(in: .whitespaces)), (1...65535).contains(value) else {
            portText = String(savedPort)
            portStatus = ""
            YouStore.shared.say("Enter a port from 1 to 65535.")
            return
        }
        guard value != savedPort else { return }
        portStatus = "Saving..."
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            savedPort = value
            portText = String(value)
            portStatus = "Saved"
            YouStore.shared.say("Port set to \(value).")
        }
    }

    private func turnOn() {
        guard !enabling else { return }
        enabling = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            enabling = false
            health = .live
            withAnimation(Motion.sheet) { mode = .live }
            Haptics.success()
            YouStore.shared.say("Remote access is on.")
        }
    }

    // MARK: Live

    private var healthPill: (String, StatusPill.Tone) {
        switch health {
        case .live: ("Live", .ok)
        case .reconnecting: ("Reconnecting", .warn)
        case .expired: ("Certificate expired", .bad)
        }
    }

    private var healthLines: [String] {
        switch health {
        case .live:
            return ["Open this exact address from any device signed in to your Tailscale account. Include the port.",
                    "Answered a check at 9:41."]
        case .reconnecting:
            return ["Not answering since 9:12: the connection was reset.",
                    "Kairos checks every 30 seconds and reconnects on its own.",
                    "Reconnected 2 times since it was turned on."]
        case .expired:
            return ["Browsers refuse this address until Tailscale issues a new certificate. Kairos keeps trying.",
                    "Check that HTTPS certificates are still on in your Tailscale admin settings."]
        }
    }

    @ViewBuilder private var liveContent: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Remote access is on")
                        .font(KFont.ui(17, .semibold))
                        .foregroundStyle(Palette.ink)
                    if health == .live {
                        PulsingDot(color: Palette.success)
                    }
                    StatusPill(text: healthPill.0, tone: healthPill.1)
                }
                Text(liveAddress)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.goldText)
                    .textSelection(.enabled)
                ForEach(healthLines, id: \.self) { line in
                    Text(line)
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    YouPillButton(title: "Copy link", symbol: "link", prominent: true) { accessCopy(liveAddress, "Link copied.") }
                    YouPillButton(title: "Turn off", danger: true) { confirmTurnOff = true }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .arrives(1)
        .confirmationDialog("Turn off remote access?", isPresented: $confirmTurnOff, titleVisibility: .visible) {
            Button("Turn off", role: .destructive) { turnOff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing reaches the desktop from your other devices until it is turned on again, this phone included.")
        }
    }

    private func turnOff() {
        withAnimation(Motion.sheet) { mode = .setup }
        Haptics.success()
        YouStore.shared.say("Remote access turned off.")
    }

    // MARK: Unavailable

    @ViewBuilder private var unavailableContent: some View {
        SettingsGroup {
            StatusRow(title: "Status", detail: "Couldn't read status: the desktop did not answer.", symbol: "exclamationmark.triangle", status: "Unknown", tone: .bad)
            ActionRow(title: "Try again", symbol: "arrow.clockwise", tone: .gold) {
                withAnimation(Motion.snappy) { mode = .setup }
            }
        }
        .arrives(1)
    }

    // MARK: Paired phones

    private var phonesGroup: some View {
        SettingsGroup("Paired phones", footer: "Unpairing stops that phone's connection at once.") {
            if devices.isEmpty {
                EmptyRow(text: "No phones are paired.")
            }
            ForEach(devices) { device in
                AccessItemRow(title: device.name, pill: device.current ? "This phone" : nil, pillTone: .working,
                              detail: "Paired \(device.paired) · last seen \(device.lastSeen)", symbol: device.symbol) {
                    YouPillButton(title: "Unpair", danger: true) { unpairTarget = device }
                }
            }
            AccessInfoRow(title: "Pair another phone",
                          detail: "On the desktop, open Settings, Remote access, Pair the iPhone app. Enter the six-digit code it shows on the new phone. A code works once, for 10 minutes.",
                          symbol: "plus")
        }
    }

    private func unpair(_ device: AccessPairedDevice) {
        withAnimation(Motion.snappy) { devices.removeAll { $0.id == device.id } }
        Haptics.success()
        YouStore.shared.say(device.current ? "This phone is unpaired." : "\(device.name) is unpaired.")
    }
}

// MARK: - Forge

struct ForgeSettingsScreen: View {
    @State private var terminalRemote = false

    var body: some View {
        SettingsPage("Forge", subtitle: "Where coding projects live, and who may use their terminals.") {
            SettingsGroup("Forge root folder", footer: "New and cloned projects get their own folder here. Change it on the desktop, in Settings, Forge.") {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 26)
                    Text(AccessSample.forgeRoot)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Forge root folder, \(AccessSample.forgeRoot)")
            }
            .arrives(0)

            SettingsGroup("Terminal") {
                YouToggleRow(title: "Allow the terminal over Remote Access", detail: "Let signed-in admins use session terminals from your other devices. Off by default.", symbol: "terminal", isOn: $terminalRemote)
            }
            .arrives(1)
        }
        .onChange(of: terminalRemote) {
            YouStore.shared.say(terminalRemote ? "Terminals work over Remote Access now." : "Terminals stay on the desktop now.")
        }
    }
}

// MARK: - Debug pictures

enum AccessDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "access-permissions": return AnyView(PermissionsScreen())
        case "access-permissions-empty": return AnyView(PermissionsScreen(startEmpty: true))
        case "access-permissions-decisions": return AnyView(PermissionsScreen(showDecisions: true))
        case "access-permissions-failed": return AnyView(PermissionsScreen(startFailed: true))
        case "access-agent-tools": return AnyView(AgentToolsScreen())
        case "access-computer-use": return AnyView(ComputerUseScreen())
        case "access-computer-use-docker-off": return AnyView(ComputerUseScreen(dockerReady: false))
        case "access-remote": return AnyView(RemoteAccessScreen())
        case "access-remote-ready": return AnyView(RemoteAccessScreen(startState: "ready"))
        case "access-remote-create-login": return AnyView(RemoteAccessScreen(startState: "create"))
        case "access-remote-live": return AnyView(RemoteAccessScreen(startState: "live"))
        case "access-remote-reconnecting": return AnyView(RemoteAccessScreen(startState: "reconnecting"))
        case "access-remote-expired": return AnyView(RemoteAccessScreen(startState: "expired"))
        case "access-remote-unavailable": return AnyView(RemoteAccessScreen(startState: "unavailable"))
        case "access-forge": return AnyView(ForgeSettingsScreen())
        default: return nil
        }
    }
}
