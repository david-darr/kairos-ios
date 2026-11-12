import SwiftUI
import UIKit

// Models: the added connections, adding one, and the step-by-step setup guide.
// The list lives in ModelConnectionsSample so every models screen shares it; the desktop replaces it later.

// MARK: - Sample data

nonisolated enum ModelConnectionKind: String, CaseIterable, Hashable, Sendable {
    case claudeCLI, codexCLI, antigravity, local, api

    var title: String {
        switch self {
        case .claudeCLI: "Claude Code CLI"
        case .codexCLI: "Codex CLI"
        case .antigravity: "Antigravity"
        case .local: "Local"
        case .api: "API"
        }
    }

    var short: String {
        switch self {
        case .claudeCLI: "Claude Code"
        case .codexCLI: "Codex"
        case .antigravity: "Antigravity"
        case .local: "Local"
        case .api: "API"
        }
    }

    var symbol: String {
        switch self {
        case .claudeCLI, .codexCLI: "terminal"
        case .antigravity: "sparkles"
        case .local: "cpu"
        case .api: "network"
        }
    }

    var isCLI: Bool { self == .claudeCLI || self == .codexCLI || self == .antigravity }
}

nonisolated struct ModelConnection: Identifiable, Hashable, Sendable {
    let id: String
    var kind: ModelConnectionKind
    var name: String
    /// Empty means the CLI's own default.
    var model: String = ""
    var baseURL: String = ""
    var hasKey = false
    var contextWindow: Int? = nil
    var acceptsImages = false
    /// Measured over the last 7 days.
    var speed: String? = nil
    /// What a test answers on sample data. Nil fails.
    var sampleLatency: Int? = 420
    /// Set when another account shares this connection with you.
    var sharedBy: String? = nil
    /// Account names this connection is shared with.
    var sharedWith: [String] = []

    var details: String {
        if sharedBy != nil { return model.isEmpty ? "CLI default" : model }
        if kind.isCLI { return "Model: \(model.isEmpty ? "CLI default" : model)" }
        var parts = [model, baseURL]
        if hasKey { parts.append("key saved") }
        if kind == .local, let contextWindow { parts.append("context \(contextWindow)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var isSmallWindow: Bool { kind == .local && (contextWindow ?? 16384) < 8192 }
}

nonisolated struct ModelProviderPreset: Hashable, Sendable {
    let label: String
    let url: String

    static let custom = "Custom URL"

    static let all: [ModelProviderPreset] = [
        ModelProviderPreset(label: ModelProviderPreset.custom, url: ""),
        ModelProviderPreset(label: "OpenAI", url: "https://api.openai.com/v1"),
        ModelProviderPreset(label: "Anthropic", url: "https://api.anthropic.com"),
        ModelProviderPreset(label: "OpenRouter", url: "https://openrouter.ai/api/v1"),
        ModelProviderPreset(label: "DeepSeek", url: "https://api.deepseek.com/v1"),
        ModelProviderPreset(label: "Groq", url: "https://api.groq.com/openai/v1"),
        ModelProviderPreset(label: "Mistral", url: "https://api.mistral.ai/v1"),
        ModelProviderPreset(label: "Together AI", url: "https://api.together.xyz/v1"),
        ModelProviderPreset(label: "Fireworks AI", url: "https://api.fireworks.ai/inference/v1"),
        ModelProviderPreset(label: "Google Gemini", url: "https://generativelanguage.googleapis.com/v1beta/openai"),
        ModelProviderPreset(label: "xAI Grok", url: "https://api.x.ai/v1"),
        ModelProviderPreset(label: "Z.AI", url: "https://api.z.ai/api/paas/v4"),
        ModelProviderPreset(label: "NVIDIA", url: "https://integrate.api.nvidia.com/v1"),
        ModelProviderPreset(label: "Ollama Cloud", url: "https://ollama.com/api"),
    ]

    static func url(for label: String) -> String {
        all.first { $0.label == label }?.url ?? ""
    }
}

/// The model connections every models screen shares, on sample data.
@Observable
final class ModelConnectionsSample {
    static let shared = ModelConnectionsSample()

    var connections: [ModelConnection] = ModelConnectionsSample.starting
    /// "auto", "off" or a connection id.
    var helperChoice = "auto"
    var autoCompact = true

    static let starting: [ModelConnection] = [
        ModelConnection(id: "m-claude", kind: .claudeCLI, name: "Claude",
                        speed: "Usually 2.1 s to the first word · all worked, last 7 days", sampleLatency: 412),
        ModelConnection(id: "m-codex", kind: .codexCLI, name: "Codex", model: "gpt-5-codex",
                        speed: "Usually 3.4 s · 98% worked, last 7 days", sampleLatency: 655),
        ModelConnection(id: "m-qwen", kind: .local, name: "Qwen local", model: "qwen3:8b", baseURL: "http://100.64.0.12:11434/v1",
                        contextWindow: 16384, speed: "Usually 0.9 s · all worked, last 7 days", sampleLatency: 188),
        ModelConnection(id: "m-tiny", kind: .local, name: "Tiny local", model: "llama3.2:1b", baseURL: "http://localhost:11434/v1",
                        contextWindow: 4096, sampleLatency: nil),
        ModelConnection(id: "m-router", kind: .api, name: "OpenRouter", model: "deepseek/deepseek-chat", baseURL: "https://openrouter.ai/api/v1",
                        hasKey: true, acceptsImages: true, speed: "Usually 1.6 s · 99% worked, last 7 days", sampleLatency: 734,
                        sharedWith: ["Bike shop"]),
        ModelConnection(id: "m-shop", kind: .api, name: "Shop OpenAI", model: "gpt-4.1-mini", sampleLatency: 520, sharedBy: "Bike shop"),
    ]

    var own: [ModelConnection] { connections.filter { $0.sharedBy == nil } }
    var sharedWithYou: [ModelConnection] { connections.filter { $0.sharedBy != nil } }
    var firstLocal: ModelConnection? { connections.first { $0.kind == .local } }

    func has(_ kind: ModelConnectionKind) -> Bool {
        own.contains { $0.kind == kind }
    }

    func add(_ connection: ModelConnection) {
        connections.append(connection)
    }

    func remove(_ id: String) {
        connections.removeAll { $0.id == id }
        if helperChoice == id { helperChoice = "auto" }
    }

    func update(_ id: String, _ change: (inout ModelConnection) -> Void) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        change(&connections[index])
    }
}

nonisolated private enum ModelTestState: Hashable, Sendable {
    case testing
    case ok(Int)
    case failed(String)
}

/// An inline error under a model form.
private struct ModelErrorLine: View {
    let text: String?

    var body: some View {
        if let text {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Palette.danger)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Added models

/// Every added connection, grouped by kind, with tests, image support, sharing and removal.
struct ModelsScreen: View {
    private let sample = ModelConnectionsSample.shared
    private let store = YouStore.shared
    @State private var tests: [String: ModelTestState] = [:]
    @State private var removing: ModelConnection? = nil
    @State private var sharing: ModelConnection? = nil
    @State private var started = false
    private let startTesting: Bool
    private let startEmpty: Bool
    private let startShareID: String?
    private let startRemoveID: String?

    init(startTesting: Bool = false, startEmpty: Bool = false, startShareID: String? = nil, startRemoveID: String? = nil) {
        self.startTesting = startTesting
        self.startEmpty = startEmpty
        self.startShareID = startShareID
        self.startRemoveID = startRemoveID
    }

    var body: some View {
        SettingsPage("Models", subtitle: "The models your chats and bots can use.", trailing: {
            if !sample.connections.isEmpty {
                PillButton(title: "Test all", symbol: "bolt") { testAll() }
            }
        }) {
            SettingsGroup {
                NavRow(title: "Add a model", detail: "A CLI, a local server or an API key.", symbol: "plus", to: .addModel)
                NavRow(title: "Help me set up a model", detail: "A step-by-step guide, with sign-in.", symbol: "wand.and.stars", to: .modelGuide)
            }
            .arrives(0)

            if sample.own.isEmpty {
                NoteText(text: "Nothing added yet. Add a model, or let the guide walk you through it.", symbol: "info.circle")
            }

            ForEach(Array(ModelConnectionKind.allCases.enumerated()), id: \.offset) { index, kind in
                let list = sample.own.filter { $0.kind == kind }
                SettingsGroup(kind.title) {
                    if list.isEmpty {
                        EmptyRow(text: "None added")
                    } else {
                        ForEach(list) { connection in
                            connectionRow(connection)
                        }
                    }
                }
                .arrives(index + 1)
            }

            if !sample.sharedWithYou.isEmpty {
                SettingsGroup("Shared with you", footer: "Connections other accounts on this Kairos let you use. Their key and address stay private.") {
                    ForEach(sample.sharedWithYou) { connection in
                        connectionRow(connection)
                    }
                }
            }

            SettingsGroup("Long chats", footer: "When a chat fills 85% of the model's context window, Kairos summarises its earlier part in the background. The whole chat stays, the last messages stay word for word, and nothing is deleted. Claude Code and Codex manage their own.") {
                ToggleRow(title: "Compact local and API chats automatically", isOn: Binding(
                    get: { sample.autoCompact },
                    set: { on in
                        sample.autoCompact = on
                        store.say(on ? "Long chats compact on their own" : "Long chats no longer compact")
                    }
                ))
            }

            SettingsGroup("Helpers", footer: "Any chat or task can hand up to 3 research jobs to helpers that work in parallel and report back. They run on this model, can only read, and stop after 10 minutes or 40,000 tokens each.") {
                PickRow(
                    title: "Model for helpers",
                    detail: helperDetail,
                    symbol: "person.2",
                    selection: Binding(
                        get: { sample.helperChoice },
                        set: { value in
                            sample.helperChoice = value
                            store.say("Helpers updated")
                        }
                    ),
                    options: helperOptions,
                    label: helperLabel
                )
            }
        }
        .animation(Motion.snappy, value: sample.connections)
        .animation(Motion.snappy, value: tests)
        .sheet(item: $sharing) { connection in
            ModelShareSheet(connection: connection)
        }
        .confirmationDialog(
            "Remove this model?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { connection in
            Button("Remove model", role: .destructive) {
                withAnimation(Motion.snappy) { sample.remove(connection.id) }
                tests[connection.id] = nil
                store.say("Model removed")
            }
            Button("Cancel", role: .cancel) {}
        } message: { connection in
            Text("\(connection.name) will be removed. Any chat still set to it will need a new model.")
        }
        .onAppear {
            guard !started else { return }
            started = true
            if startEmpty { sample.connections.removeAll() }
            if startTesting { testAll() }
            if let id = startShareID { sharing = sample.connections.first { $0.id == id } }
            if let id = startRemoveID { removing = sample.connections.first { $0.id == id } }
        }
    }

    // MARK: Helpers row

    private var helperOptions: [String] {
        ["auto"] + sample.connections.filter { $0.kind == .local || $0.kind == .api }.map(\.id) + ["off"]
    }

    private func helperLabel(_ option: String) -> String {
        switch option {
        case "auto": return sample.firstLocal.map { "Automatic: \($0.name)" } ?? "Automatic"
        case "off": return "Off"
        default: return sample.connections.first { $0.id == option }?.name ?? "Automatic"
        }
    }

    private var helperDetail: String {
        if let local = sample.firstLocal {
            return "Automatic uses \(local.name), the first local model."
        }
        return "Automatic needs a local model, and none is added yet."
    }

    // MARK: A connection

    private func connectionRow(_ connection: ModelConnection) -> some View {
        let own = connection.sharedBy == nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: connection.kind.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 26)
                Text(connection.name)
                    .font(KFont.ui(16.5, .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                testPill(connection.id)
            }
            .accessibilityElement(children: .combine)

            Text(connection.details)
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            if let sharedBy = connection.sharedBy {
                StatusPill(text: "Shared by \(sharedBy)", tone: .working)
            }

            if let speed = connection.speed {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 11, weight: .semibold))
                    Text(speed)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.inkDim)
            }

            if connection.isSmallWindow, let window = connection.contextWindow {
                VStack(alignment: .leading, spacing: 4) {
                    StatusPill(text: "Small window", tone: .warn)
                    Text("Kairos's own instructions and tools take about 2,100 of these \(window) tokens on every message, leaving little for the chat. 16,384 is the default for new local models.")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let failure = failure(connection.id) {
                Text(failure)
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if own && (connection.kind == .local || connection.kind == .api) {
                Toggle(isOn: imageBinding(connection)) {
                    Text("Accepts images")
                        .font(KFont.ui(15))
                        .foregroundStyle(Palette.ink)
                }
                .toggleStyle(.switch)
                .tint(Palette.gold)
                .frame(minHeight: 44)
            }

            HStack(spacing: 8) {
                PillButton(title: "Test", symbol: "bolt") { test(connection) }
                if canShare(connection) {
                    PillButton(title: connection.sharedWith.isEmpty ? "Share" : "Shared with \(connection.sharedWith.count)", symbol: "person.2") {
                        sharing = connection
                    }
                }
                if own {
                    PillButton(title: "Remove", danger: true) { removing = connection }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func testPill(_ id: String) -> some View {
        if let state = tests[id] {
            switch state {
            case .testing:
                StatusPill(text: "Testing...", tone: .working)
            case .ok(let ms):
                StatusPill(text: "OK · \(ms) ms", tone: .ok)
            case .failed:
                StatusPill(text: "Failed", tone: .bad)
            }
        }
    }

    private func failure(_ id: String) -> String? {
        if let state = tests[id], case .failed(let why) = state { return why }
        return nil
    }

    private func canShare(_ connection: ModelConnection) -> Bool {
        connection.sharedBy == nil && store.current.isAdmin && store.accounts.count > 1
    }

    private func imageBinding(_ connection: ModelConnection) -> Binding<Bool> {
        let id = connection.id
        let name = connection.name
        return Binding(
            get: { sample.connections.first { $0.id == id }?.acceptsImages ?? false },
            set: { on in
                Haptics.select()
                withAnimation(Motion.snappy) { sample.update(id) { $0.acceptsImages = on } }
                store.say(on ? "\(name) accepts images" : "\(name) no longer gets images")
            }
        )
    }

    // MARK: Tests

    private func test(_ connection: ModelConnection) {
        let id = connection.id
        let latency = connection.sampleLatency
        let address = connection.baseURL
        withAnimation(Motion.snappy) { tests[id] = .testing }
        Task {
            try? await Task.sleep(for: .milliseconds(600 + (latency ?? 900)))
            guard tests[id] == .testing else { return }
            withAnimation(Motion.snappy) {
                if let latency {
                    tests[id] = .ok(latency)
                } else {
                    tests[id] = .failed(address.isEmpty
                        ? "No answer. Check that it is running on your desktop."
                        : "No answer from \(address). Check that the server is running.")
                }
            }
            if latency == nil { Haptics.thud() } else { Haptics.success() }
        }
    }

    private func testAll() {
        for connection in sample.connections { test(connection) }
    }
}

/// Pick which other accounts on this Kairos may use one of your connections.
private struct ModelShareSheet: View {
    let connection: ModelConnection
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var loaded = false
    private let store = YouStore.shared
    private let sample = ModelConnectionsSample.shared

    var body: some View {
        let others = store.accounts.filter { $0.id != store.currentID }
        FittedSheet(estimate: 480) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 6) {
                    Text("Share \(connection.name)")
                        .font(KFont.ui(20, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    Text("They can pick this model for their chats and bots. Your key and address stay private, and what they use counts in their own account.")
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                SettingsGroup("Shared with") {
                    ForEach(others) { account in
                        Toggle(isOn: Binding(
                            get: { picked.contains(account.name) },
                            set: { on in
                                Haptics.select()
                                if on { picked.insert(account.name) } else { picked.remove(account.name) }
                            }
                        )) {
                            HStack(spacing: 12) {
                                AccountAvatar(account: account, size: 34)
                                RowLabel(title: account.isAdmin ? "\(account.name) (admin)" : account.name)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Palette.gold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minHeight: 56)
                    }
                }

                GoldButton(title: "Save") { save() }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.top, 30)
            .padding(.bottom, 20)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            picked = Set(connection.sharedWith)
        }
    }

    private func save() {
        let names = picked.sorted()
        sample.update(connection.id) { $0.sharedWith = names }
        Haptics.success()
        store.say(names.isEmpty ? "\(connection.name) is private again" : "\(connection.name) shared with \(names.joined(separator: ", "))")
        dismiss()
    }
}

// MARK: - Add a model

nonisolated private enum ModelAgyState: Hashable, Sendable {
    case checking, signedIn
}

/// Add a Claude Code, Codex, Antigravity, local or API connection.
struct AddModelScreen: View {
    @Environment(\.dismiss) private var dismiss
    private let sample = ModelConnectionsSample.shared
    private let store = YouStore.shared
    @State private var kind: ModelConnectionKind = .claudeCLI
    @State private var name = ""
    @State private var model = ""
    @State private var url = ""
    @State private var key = ""
    @State private var context = ""
    @State private var images = false
    @State private var provider = ModelProviderPreset.custom
    @State private var error: String? = nil
    @State private var agy: ModelAgyState = .signedIn

    init(startKind: ModelConnectionKind = .claudeCLI, startError: String? = nil) {
        _kind = State(initialValue: startKind)
        _error = State(initialValue: startError)
    }

    var body: some View {
        SettingsPage("Add a model", subtitle: "Connect a model your chats and bots can use.") {
            GlassSwitch(items: ModelConnectionKind.allCases, selection: $kind, title: { $0.short })

            switch kind {
            case .claudeCLI, .codexCLI: cliForm
            case .antigravity: agyForm
            case .local: localForm
            case .api: apiForm
            }

            ModelErrorLine(text: error)

            GoldButton(title: kind == .antigravity ? "Connect to Kairos" : "Add model") { add() }

            SettingsGroup {
                NavRow(title: "Help me set up a model", detail: "A step-by-step guide, with sign-in.", symbol: "wand.and.stars", to: .modelGuide)
            }
        }
        .animation(Motion.snappy, value: kind)
        .animation(Motion.snappy, value: error)
        .onChange(of: kind) {
            error = nil
            name = ""
            model = ""
            url = ""
            key = ""
            context = ""
            images = false
            provider = ModelProviderPreset.custom
        }
    }

    // MARK: Forms

    private var cliForm: some View {
        let cli = kind == .claudeCLI ? "claude" : "codex"
        return SettingsGroup(kind.title, footer: "Needs the \(cli) CLI installed and signed in on your desktop. Leave Model empty for the CLI's own default.") {
            FieldRow(title: "Name", text: $name, prompt: kind == .claudeCLI ? "Claude" : "Codex")
            FieldRow(title: "Model", text: $model, prompt: kind == .claudeCLI ? "claude-sonnet-4-5" : "gpt-5-codex")
        }
    }

    private var agyForm: some View {
        SettingsGroup("Antigravity (Gemini)", footer: "Sign in to Antigravity on your desktop first. Kairos never handles your credentials.") {
            HStack(spacing: 8) {
                RowLabel(
                    title: "Antigravity CLI",
                    detail: agy == .checking ? "Checking your desktop..." : "Version 1.4.2 · 6 Gemini models found",
                    symbol: "sparkles"
                )
                if agy == .checking {
                    StatusPill(text: "Checking...", tone: .working)
                } else {
                    StatusPill(text: "Signed in", tone: .ok)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            ActionRow(title: "Recheck", symbol: "arrow.clockwise") { recheck() }
        }
    }

    private var localForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsGroup("Local model server", footer: "Ollama, llama.cpp, vLLM or any server on your desktop or your network. The context window is how many tokens the model may hold, so a large model does not fill the memory.") {
                FieldRow(title: "Name", text: $name, prompt: "Local Ollama")
                FieldRow(title: "Server URL", text: $url, prompt: "http://localhost:11434/v1", keyboard: .URL)
                FieldRow(title: "Model id", text: $model, prompt: "qwen3:8b")
                FieldRow(title: "Context window", text: $context, prompt: "16384", keyboard: .numberPad)
                ToggleRow(title: "Accepts images", detail: "The model can read pictures you attach.", isOn: $images)
            }
        }
    }

    private var apiForm: some View {
        SettingsGroup("API provider", footer: "A cloud provider such as OpenAI, Anthropic or OpenRouter. The key is saved encrypted on your desktop and never shown again.") {
            PickRow(
                title: "Provider",
                symbol: "globe",
                selection: Binding(get: { provider }, set: { pick($0) }),
                options: ModelProviderPreset.all.map(\.label),
                label: { $0 }
            )
            FieldRow(title: "Name", text: $name, prompt: "OpenRouter")
            FieldRow(title: "Base URL", text: $url, prompt: "https://openrouter.ai/api/v1", keyboard: .URL)
            FieldRow(title: "Model id", text: $model, prompt: "Model id")
            FieldRow(title: "API key", text: $key, prompt: "API key", secure: true)
            ToggleRow(title: "Accepts images", detail: "The model can read pictures you attach.", isOn: $images)
        }
    }

    // MARK: Actions

    private func pick(_ label: String) {
        provider = label
        let address = ModelProviderPreset.url(for: label)
        guard !address.isEmpty else { return }
        url = address
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = label }
    }

    private func recheck() {
        guard agy != .checking else { return }
        withAnimation(Motion.snappy) { agy = .checking }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(Motion.snappy) { agy = .signedIn }
            store.say("Antigravity is signed in on your desktop")
        }
    }

    private func add() {
        error = nil
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let cleanURL = url.trimmingCharacters(in: .whitespaces)
        let cleanModel = model.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .claudeCLI, .codexCLI:
            guard !cleanName.isEmpty else { fail("Name is required."); return }
        case .antigravity:
            if sample.has(.antigravity) { fail("Antigravity is already connected."); return }
        case .local, .api:
            guard !cleanName.isEmpty, !cleanURL.isEmpty, !cleanModel.isEmpty else { fail("Name, URL, and model id are required."); return }
            guard cleanURL.hasPrefix("http://") || cleanURL.hasPrefix("https://") else {
                fail("Kairos could not reach that address. The URL must start with http:// or https://.")
                return
            }
        }
        let window = Int(context.trimmingCharacters(in: .whitespaces))
        let connection = ModelConnection(
            id: "m-\(UUID().uuidString.prefix(6))",
            kind: kind,
            name: kind == .antigravity ? "Antigravity" : cleanName,
            model: cleanModel,
            baseURL: kind.isCLI ? "" : cleanURL,
            hasKey: kind == .api && !key.isEmpty,
            contextWindow: kind == .local ? (window ?? 16384) : nil,
            acceptsImages: !kind.isCLI && images
        )
        withAnimation(Motion.snappy) { sample.add(connection) }
        Haptics.success()
        store.say("\(connection.name) added")
        dismiss()
    }

    private func fail(_ text: String) {
        withAnimation(Motion.snappy) { error = text }
        Haptics.thud()
    }
}

// MARK: - Setup guide

nonisolated enum ModelGuideChoice: String, CaseIterable, Hashable, Sendable {
    case claude, codex, antigravity, api, local

    var title: String {
        switch self {
        case .claude: "I pay for Claude"
        case .codex: "I pay for ChatGPT"
        case .antigravity: "Antigravity (Gemini)"
        case .api: "I have an API key"
        case .local: "Free, on this computer"
        }
    }

    var copy: String {
        switch self {
        case .claude: "For Claude Pro or Max. Claude Code is already inside Kairos, so you only need to sign in. Your subscription's limits apply."
        case .codex: "For ChatGPT Plus or Pro. Codex is OpenAI's agent app. Kairos can install it on your desktop, then help you sign in. Your subscription's limits apply."
        case .antigravity: "Use the Gemini models in your Antigravity account. Sign in in the Antigravity app or CLI; Kairos never handles your credentials."
        case .api: "Choose OpenAI, Anthropic, OpenRouter or Google. You pay the provider for what you use. Kairos tests and saves your key securely."
        case .local: "A small model downloaded through Cookbook onto your desktop. No account or usage bill. Private, but slower and less capable than a cloud model."
        }
    }

    var symbol: String {
        switch self {
        case .claude, .codex: "terminal"
        case .antigravity: "sparkles"
        case .api: "key"
        case .local: "cpu"
        }
    }

    var kind: ModelConnectionKind {
        switch self {
        case .claude: .claudeCLI
        case .codex: .codexCLI
        case .antigravity: .antigravity
        case .api: .api
        case .local: .local
        }
    }

    /// What the desktop reports before this is set up, on sample data.
    var readiness: String {
        switch self {
        case .claude: "No download needed"
        case .codex: "Installed (0.58)"
        case .antigravity: "Installed (1.4.2) | 6 models found"
        case .api: "Pay for what you use"
        case .local: "Needs disk space"
        }
    }

    var runsOnDesktop: Bool { self == .claude || self == .codex || self == .antigravity }
}

private let modelGuideWords: [(word: String, meaning: String)] = [
    ("CLI", "A small app that runs in a text window. Kairos uses it for you after you sign in."),
    ("Agent and harness", "An agent can use tools to help with a task. A harness is the app around the model that gives it those tools and keeps track of its work."),
    ("API key", "A private code that lets an app use a model on your behalf. Keep it secret, just like a password."),
    ("Subscription and pay-per-use", "A subscription is a regular payment with usage limits. An API key usually charges for what you use, separately from your Claude or ChatGPT subscription."),
    ("Local model", "A model downloaded onto your computer. It works without an account and keeps the conversation there, but may be slower or less capable."),
]

private let modelGuideProviders = ["OpenAI", "Anthropic", "OpenRouter", "Google"]

/// "Choose how Kairos thinks": five ways to connect a model, step by step.
struct ModelGuideScreen: View {
    private let sample = ModelConnectionsSample.shared
    private let store = YouStore.shared
    @State private var open: ModelGuideChoice? = nil
    @State private var checking = false
    @State private var finishedTitle: String? = nil
    @State private var finishedText = ""
    @State private var apiProvider = "OpenAI"
    @State private var apiOnKey = false
    @State private var apiKey = ""
    @State private var apiError: String? = nil
    @State private var testing = false
    @State private var localProgress: Double? = nil
    @State private var showWords = false

    init(startChoice: ModelGuideChoice? = nil, startWords: Bool = false) {
        _open = State(initialValue: startChoice)
        _showWords = State(initialValue: startWords)
    }

    var body: some View {
        SettingsPage("Choose how Kairos thinks", subtitle: "Choose the option that fits you. Kairos helps you connect it, and you can change it any time.") {
            if let finishedTitle {
                finishedCard(finishedTitle)
            } else if let open {
                detail(open)
            } else {
                ForEach(Array(ModelGuideChoice.allCases.enumerated()), id: \.offset) { index, choice in
                    card(choice).arrives(index)
                }
            }
            glossary
        }
        .animation(Motion.snappy, value: open)
        .animation(Motion.snappy, value: finishedTitle)
        .animation(Motion.snappy, value: apiOnKey)
        .animation(Motion.snappy, value: apiError)
    }

    // MARK: Choices

    private var machineAccess: Bool { store.current.isAdmin }

    private func isReady(_ choice: ModelGuideChoice) -> Bool { sample.has(choice.kind) }

    private func isBlocked(_ choice: ModelGuideChoice) -> Bool {
        choice.runsOnDesktop && !machineAccess
    }

    private func status(_ choice: ModelGuideChoice) -> String {
        if isBlocked(choice) {
            return choice == .claude ? "Signing in needs machine access. Ask an admin, or use an API key." : "Needs machine access. Ask an admin."
        }
        return isReady(choice) ? "Already set up" : choice.readiness
    }

    private func card(_ choice: ModelGuideChoice) -> some View {
        let ready = isReady(choice) && !isBlocked(choice)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 34, height: 34)
                    .background(Palette.ink.opacity(0.08), in: Circle())
                Text(choice.title)
                    .font(KFont.ui(17.5, .semibold))
                    .foregroundStyle(Palette.ink)
            }
            Text(choice.copy)
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(status(choice))
                    .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                    .foregroundStyle(ready ? Palette.success : Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if !isBlocked(choice) {
                    PillButton(title: ready ? "Review setup" : "Choose this", prominent: !ready) { choose(choice) }
                }
            }
        }
        .padding(16)
        .kCard(radius: 22)
    }

    private func choose(_ choice: ModelGuideChoice) {
        withAnimation(Motion.snappy) {
            open = choice
            checking = false
            apiOnKey = false
            apiKey = ""
            apiError = nil
            localProgress = nil
        }
    }

    private func backToChoices() {
        withAnimation(Motion.snappy) {
            open = nil
            finishedTitle = nil
            apiOnKey = false
            apiKey = ""
            apiError = nil
            localProgress = nil
        }
    }

    // MARK: One choice

    @ViewBuilder
    private func detail(_ choice: ModelGuideChoice) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                Text(detailTitle(choice))
                    .font(KFont.ui(21, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
            }
            switch choice {
            case .claude, .codex, .antigravity: cliDetail(choice)
            case .api: apiDetail
            case .local: localDetail
            }
            QuietButton(title: "Back to choices") { backToChoices() }
        }
        .transition(.opacity)
    }

    private func detailTitle(_ choice: ModelGuideChoice) -> String {
        switch choice {
        case .claude: "Sign in with Claude"
        case .codex: "ChatGPT with Codex"
        case .antigravity: "Antigravity (Gemini)"
        case .api: apiOnKey ? "Test your API key" : "Choose your API provider"
        case .local: "Cookbook's small model"
        }
    }

    private func cliDetail(_ choice: ModelGuideChoice) -> some View {
        let desktopState: String = switch choice {
        case .claude: "Signed in on your desktop"
        case .codex: "Installed (0.58) and signed in on your desktop"
        default: "Version 1.4.2 · 6 Gemini models found · signed in"
        }
        return VStack(alignment: .leading, spacing: 16) {
            NoteText(
                text: "Signing in opens the provider's own window on your desktop, so start it there and come back here. Your password stays with the provider.",
                symbol: "desktopcomputer"
            )
            SettingsGroup {
                HStack(spacing: 8) {
                    RowLabel(title: "On your desktop", detail: checking ? "Checking your desktop..." : desktopState, symbol: "desktopcomputer")
                    StatusPill(text: checking ? "Checking..." : "Ready", tone: checking ? .working : .ok)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
                ActionRow(title: "Recheck", symbol: "arrow.clockwise") { recheck() }
            }
            GoldButton(title: isReady(choice) ? "Review connection" : "Connect to Kairos") { connect(choice) }
        }
    }

    private var apiDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if apiOnKey {
                SettingsGroup(footer: "Kairos sends one tiny test, then saves a working key encrypted on your desktop. The test may cost a small amount.") {
                    ValueRow(title: "Provider", symbol: "globe", value: apiProvider)
                    FieldRow(title: "API key", text: $apiKey, prompt: "Paste your API key", secure: true)
                }
                ModelErrorLine(text: apiError)
                GoldButton(title: testing ? "Testing..." : "Test and save") { testAndSave() }
            } else {
                SettingsGroup(footer: "API use is billed separately from a Claude or ChatGPT subscription.") {
                    PickRow(title: "Provider", symbol: "globe", selection: $apiProvider, options: modelGuideProviders, label: { $0 })
                }
                GoldButton(title: "Continue") {
                    withAnimation(Motion.snappy) { apiOnKey = true }
                }
            }
        }
    }

    private var localDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoteText(text: "Cookbook downloads and prepares a small model on your desktop. You can leave this page while it works.", symbol: "desktopcomputer")
            SettingsGroup {
                if let localProgress {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Downloading Qwen 3 4B")
                                .font(KFont.ui(16))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(Int(localProgress * 100))%")
                                .font(KFont.ui(15, .medium))
                                .foregroundStyle(Palette.goldText)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        ProgressView(value: localProgress)
                            .tint(Palette.gold)
                    }
                    .padding(16)
                } else {
                    ValueRow(title: "Recommended for your desktop", detail: "Fits in its memory with room to spare.", symbol: "cpu", value: "Qwen 3 4B · 2.6 GB")
                }
            }
            if localProgress == nil {
                GoldButton(title: "Download and set up") { startLocal() }
            }
        }
    }

    private func finishedCard(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.onGold)
                    .frame(width: 44, height: 44)
                    .background(Palette.success, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(KFont.ui(21, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Text(finishedText)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 22, raised: true)
            GoldButton(title: "Done") { backToChoices() }
        }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var glossary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { showWords.toggle() }
            } label: {
                HStack(spacing: 8) {
                    RowLabel(title: "What do these words mean?", symbol: "questionmark.circle")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(showWords ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.985))
            .accessibilityAddTraits(showWords ? .isSelected : [])
            if showWords {
                ForEach(modelGuideWords.indices, id: \.self) { index in
                    let entry = modelGuideWords[index]
                    Palette.line.frame(height: 1).padding(.leading, 16)
                    RowLabel(title: entry.word, detail: entry.meaning)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        }
        .kCard(radius: 22)
    }

    // MARK: Actions

    private func recheck() {
        guard !checking else { return }
        withAnimation(Motion.snappy) { checking = true }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(Motion.snappy) { checking = false }
            store.say("Checked your desktop")
        }
    }

    private func connect(_ choice: ModelGuideChoice) {
        let name: String = switch choice {
        case .claude: "Claude"
        case .codex: "Codex"
        default: "Antigravity"
        }
        if !isReady(choice) {
            sample.add(ModelConnection(id: "m-\(UUID().uuidString.prefix(6))", kind: choice.kind, name: name))
        }
        Haptics.success()
        finish(title: "Connected", text: "\(name) is connected. Pick it from the model menu above the chat box when you start a conversation.")
    }

    private func testAndSave() {
        guard !testing else { return }
        let typed = apiKey.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { apiError = "Paste an API key first."; Haptics.thud(); return }
        apiError = nil
        testing = true
        Task {
            try? await Task.sleep(for: .milliseconds(1000))
            testing = false
            guard typed.count >= 12 else {
                apiError = "\(apiProvider) did not accept that key. Check it and try again."
                Haptics.thud()
                return
            }
            let preset: (url: String, model: String) = switch apiProvider {
            case "Anthropic": ("https://api.anthropic.com", "claude-sonnet-4-5")
            case "OpenRouter": ("https://openrouter.ai/api/v1", "openrouter/auto")
            case "Google": ("https://generativelanguage.googleapis.com/v1beta/openai", "gemini-2.5-flash")
            default: ("https://api.openai.com/v1", "gpt-4.1")
            }
            sample.add(ModelConnection(id: "m-\(UUID().uuidString.prefix(6))", kind: .api, name: apiProvider,
                                       model: preset.model, baseURL: preset.url, hasKey: true))
            apiKey = ""
            Haptics.success()
            finish(title: "API key saved", text: "\(apiProvider) is connected. Pick it from the model menu above the chat box when you start a conversation.")
        }
    }

    private func startLocal() {
        withAnimation(Motion.snappy) { localProgress = 0 }
        Task {
            for step in 1...20 {
                try? await Task.sleep(for: .milliseconds(180))
                guard open == .local, localProgress != nil else { return }
                withAnimation(Motion.gentle) { localProgress = Double(step) / 20 }
            }
            guard open == .local else { return }
            if !sample.own.contains(where: { $0.name == "Cookbook small model" }) {
                sample.add(ModelConnection(id: "m-\(UUID().uuidString.prefix(6))", kind: .local, name: "Cookbook small model",
                                           model: "qwen3:4b", baseURL: "http://localhost:11434/v1", contextWindow: 16384))
            }
            Haptics.success()
            finish(title: "Ready", text: "Cookbook small model is ready. Pick it from the model menu above the chat box when you start a conversation.")
        }
    }

    private func finish(title: String, text: String) {
        withAnimation(Motion.bouncy) {
            finishedText = text
            finishedTitle = title
            open = nil
            localProgress = nil
            apiOnKey = false
        }
    }
}

// MARK: - Debug pictures

enum ModelsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "models": return AnyView(ModelsScreen())
        case "models-testing": return AnyView(ModelsScreen(startTesting: true))
        case "models-empty": return AnyView(ModelsScreen(startEmpty: true))
        case "models-share": return AnyView(ModelsScreen(startShareID: "m-router"))
        case "models-remove": return AnyView(ModelsScreen(startRemoveID: "m-tiny"))
        case "models-add": return AnyView(AddModelScreen())
        case "models-add-local": return AnyView(AddModelScreen(startKind: .local))
        case "models-add-api": return AnyView(AddModelScreen(startKind: .api))
        case "models-add-error": return AnyView(AddModelScreen(startKind: .api, startError: "Name, URL, and model id are required."))
        case "models-add-agy": return AnyView(AddModelScreen(startKind: .antigravity))
        case "models-guide": return AnyView(ModelGuideScreen())
        case "models-guide-words": return AnyView(ModelGuideScreen(startWords: true))
        case "models-guide-claude": return AnyView(ModelGuideScreen(startChoice: .claude))
        case "models-guide-api": return AnyView(ModelGuideScreen(startChoice: .api))
        case "models-guide-local": return AnyView(ModelGuideScreen(startChoice: .local))
        default: return nil
        }
    }
}
