import SwiftUI

// The paired desktop behind the Local models screen and its setup sheet (Net/DeskModelsAPI.swift). Not paired,
// nothing here runs and the screens show their sample data from LocalModelsStore, exactly as before.
//
// These actions run on the person's real computer: they download gigabytes, fill its disk and use its memory
// and graphics card. So the phone does less, and is slow to say anything happened:
// - Admin only. A member account sees one line.
// - A pull or a download has no request id. Before the request leaves, the model's hold is set here, in the
//   shared store, keyed by desktop, account, engine and model. After a lost answer the pull status and the
//   installed list are read, and nothing is sent again. Leaving the screen, opening it again or unpairing never
//   clears a hold: only the desktop showing the pull (or the person, after the window ended with nothing seen).
// - Progress is whatever the desktop's pull or download status says. No timer moves a bar.
// - Use in chat makes a new connection on every call. It is off while sending; after a lost answer the models
//   list is read again, and the button comes back only when no connection for that model exists.
// - Model sign-in opens a window on the PC and stays there. No key, token or server address is read or shown.

// MARK: - What the screens read

extension ModelEngine {
    /// The word the store keys an engine by.
    nonisolated var key: String { self == .ollama ? "ollama" : "engine" }
}

nonisolated struct DeskModelsInstalled: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var bytes: Double
    var running = false
}

nonisolated struct DeskModelsEntry: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var label: String
    var params: String
    var about: String

    var title: String { params.isEmpty ? label : "\(label) (\(params))" }
}

/// A model Ollama holds in memory.
nonisolated struct DeskModelsLoaded: Hashable, Sendable {
    var name: String
    var bytes: Double
}

/// How far a pull or a download is, as the desktop's own status says.
nonisolated struct DeskModelsProgress: Hashable, Sendable {
    nonisolated enum Phase: Hashable, Sendable {
        /// Nothing running: the desktop has no pull for this name.
        case notStarted
        case running
        case done
        case cancelled
        case failed
        /// The status could not be read.
        case unread
    }

    var phase: Phase = .notStarted
    var completed: Double = 0
    var total: Double = 0

    init(phase: Phase = .notStarted, completed: Double = 0, total: Double = 0) {
        self.phase = phase
        self.completed = completed
        self.total = total
    }

    init(_ dto: DeskModelsProgressDTO) {
        completed = max(0, dto.completed ?? 0)
        total = max(0, dto.total ?? 0)
        let status = dto.status ?? ""
        if status.isEmpty || status == "not_started" {
            phase = .notStarted
        } else if dto.done == true {
            switch status {
            case "success": phase = .done
            case "cancelled": phase = .cancelled
            default: phase = .failed
            }
        } else {
            phase = .running
        }
    }

    /// nil while the desktop has not said how big the part it is on is.
    var fraction: Double? { total > 0 ? min(1, max(0, completed / total)) : nil }
}

nonisolated struct DeskModelsEngineState: Sendable {
    var load: DeskForgeLoad = .idle
    /// Ollama only: false when it does not answer on the PC.
    var reachable = true
    var installed: [DeskModelsInstalled] = []
    var catalog: [DeskModelsEntry] = []
    /// Ollama only: what it holds in memory.
    var loaded: [DeskModelsLoaded] = []
    /// Built-in engine only: the model it runs.
    var runningModel: String?
    var skipped = 0
    /// Set when the last read failed and what is shown may be out of date.
    var stale: String?

    var totalBytes: Double { installed.reduce(0) { $0 + $1.bytes } }
}

/// Where a pull, a download, a setup or a register whose answer is not known stands.
nonisolated enum DeskModelsHoldPhase: Hashable, Sendable {
    /// The request is on its way.
    case sending
    /// The answer is lost or not seen yet: the desktop is being read.
    case checking
    /// The window ended without the desktop showing it. `checked` is false when the last reads failed.
    case quiet(checked: Bool)
}

nonisolated struct DeskModelsHold: Hashable, Sendable {
    var phase: DeskModelsHoldPhase
    /// What the desktop's status said just before the request, so an old finished status is not read as the outcome.
    var before: DeskModelsProgress?
    var stageBefore: DeskModelsStage?
}

nonisolated enum DeskModelsRead<Value: Sendable>: Sendable {
    case fresh(Value)
    /// Overtaken, cancelled, or for a desktop that is no longer the paired one: it changes nothing.
    case stale
    case failed(String, status: Int?)
}

nonisolated enum DeskModelsSent<Value: Sendable>: Sendable {
    case ok(Value)
    case refused(String)
    case lost(String)
    /// The paired desktop changed while it was on its way.
    case moved
}

nonisolated enum DeskModelsSettle: Sendable {
    case released
    case pending(checked: Bool)
}

// MARK: - The setup sheet

/// The recommended model, as the desktop describes it.
nonisolated struct DeskModelsRecommendation: Hashable, Sendable {
    var name: String
    var title: String
    var about: String
    var downloadBytes: Double?
    var freeBytes: Double?
    var downloaded: Bool
}

nonisolated enum DeskModelsStage: Hashable, Sendable {
    case idle, preparing
    case downloading(Double?)
    case starting, connected, failed

    var active: Bool {
        switch self {
        case .preparing, .downloading, .starting: return true
        case .idle, .connected, .failed: return false
        }
    }

    init(_ dto: DeskModelsProgressDTO) {
        switch dto.status ?? "" {
        case "preparing": self = .preparing
        case "downloading":
            let total = max(0, dto.total ?? 0)
            self = .downloading(total > 0 ? min(1, max(0, (dto.completed ?? 0) / total)) : nil)
        case "starting": self = .starting
        case "connected": self = .connected
        case "error": self = .failed
        default: self = .idle
        }
    }
}

nonisolated struct DeskModelsSetupState: Sendable {
    var load: DeskForgeLoad = .idle
    var choices: [SetupChoice] = []
    var recommendation: DeskModelsRecommendation?
    /// Why the recommendation is missing, when it is.
    var recommendationLine: String?
    var stage: DeskModelsStage = .idle
    var stageRead = false
}

// MARK: - The store

@Observable
final class DeskModelsLive {
    static let shared = DeskModelsLive()

    /// The desktop and account everything below was read for. Nothing else is ever shown.
    private var account = "sample"
    private var ollamaState = DeskModelsEngineState()
    private var builtInState = DeskModelsEngineState()
    private var connectionList: [ModelChoiceDTO] = []
    private var connectionsRead = false
    private var progressMap: [String: DeskModelsProgress] = [:]
    private var noteMap: [String: String] = [:]
    private var busyKeys: Set<String> = []
    /// Models a register answered for, so "In your models" shows even when the list cannot be read again.
    private var registeredNow: Set<String> = []
    private var setupState = DeskModelsSetupState()
    /// Pulls, downloads, setups and registers whose outcome is not known, keyed by desktop, account, kind, engine
    /// and model. Never cleared by a change of screen or of desktop: only the desktop (or the person) clears one.
    private var holds: [String: DeskModelsHold] = [:]

    @ObservationIgnored private var reads: [String: Int] = [:]
    @ObservationIgnored private var writeSerial = 0
    @ObservationIgnored private var inFlight = 0
    @ObservationIgnored private var watches: [String: Task<Void, Never>] = [:]

    private init() {}

    // MARK: Which desktop

    /// Paired (whether or not the desktop is answering right now): the screens show the desktop, never samples.
    var on: Bool { DeskForgeLive.shared.on }
    /// The cookbook answers an admin account only.
    var isAdmin: Bool { DeskForgeLive.shared.isAdmin }

    static let adminLine = "Local models need an admin account on your desktop."
    private static let desktopChanged = "Your paired desktop changed. Try again."

    private var current: Bool { on && account == DeskForgeLive.accountKey }

    private func stillLive(_ account: String) -> Bool {
        on && self.account == account && DeskForgeLive.accountKey == account
    }

    /// Before anything is read: drop whatever was read for another desktop, another account or sample mode.
    /// Holds stay: a pull sent to the old desktop may still be running there.
    private func follow() {
        let key = DeskForgeLive.accountKey
        guard account != key else { return }
        for task in watches.values { task.cancel() }
        watches = [:]
        for hold in holds.keys where holds[hold]?.phase == .checking {
            holds[hold]?.phase = .quiet(checked: false)
        }
        account = key
        ollamaState = DeskModelsEngineState()
        builtInState = DeskModelsEngineState()
        connectionList = []
        connectionsRead = false
        progressMap = [:]
        noteMap = [:]
        busyKeys = []
        registeredNow = []
        setupState = DeskModelsSetupState()
        reads = [:]
    }

    /// The account to read for, once the connection is ready, or nil when this is not a live admin phone.
    private func readyAccount() async -> String? {
        guard on, isAdmin else { return nil }
        follow()
        let account = self.account
        var waited = 0
        while Connection.shared.state == .connecting, waited < 80, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        return stillLive(account) ? account : nil
    }

    /// The account for a change, now (nothing is awaited), or nil when this is not a live admin phone.
    private func readyNow() -> String? {
        guard on, isAdmin else { return nil }
        follow()
        return account
    }

    // MARK: What was read

    func state(_ engine: ModelEngine) -> DeskModelsEngineState {
        guard current else { return DeskModelsEngineState() }
        return engine == .ollama ? ollamaState : builtInState
    }

    var setup: DeskModelsSetupState { current ? setupState : DeskModelsSetupState() }
    /// True once the list of the person's models was read, so "In your models" can be told from "not yet".
    var connectionsKnown: Bool { current && connectionsRead }

    func progress(_ engine: ModelEngine, _ name: String) -> DeskModelsProgress? {
        current ? progressMap[Self.progressKey(engine, name)] : nil
    }

    func note(_ key: String) -> String? { current ? noteMap[key] : nil }
    func clearNote(_ key: String) { noteMap[key] = nil }
    func isBusy(_ key: String) -> Bool { current && busyKeys.contains(key) }

    static func progressKey(_ engine: ModelEngine, _ name: String) -> String { engine.key + "|" + name }
    /// The key of the note a model's own actions write.
    static func noteKey(_ engine: ModelEngine, _ name: String) -> String { "note|" + progressKey(engine, name) }
    static let engineKey = "engine"

    func hold(_ kind: String, _ engine: ModelEngine, _ name: String) -> DeskModelsHold? {
        on ? holds[holdKey(kind, engine, name)] : nil
    }

    private func holdKey(_ kind: String, _ engine: ModelEngine, _ name: String) -> String {
        [DeskForgeLive.accountKey, kind, engine.key, name].joined(separator: "|")
    }

    /// A connection for this model exists: one the list shows, or one a register just made.
    func connected(_ engine: ModelEngine, _ name: String) -> Bool {
        guard current else { return false }
        if registeredNow.contains(Self.progressKey(engine, name)) { return true }
        return connectionList.contains { $0.kind == "local" && $0.model == name }
    }

    func isInstalled(_ engine: ModelEngine, _ name: String) -> Bool {
        let list = state(engine).installed
        if engine == .ollama { return list.contains { $0.name == name || $0.name.hasPrefix(name + ":") } }
        return list.contains { $0.name == name }
    }

    /// The sentence for a hold, or nil.
    func holdLine(_ kind: String, _ engine: ModelEngine, _ name: String) -> String? {
        let what = kind == "register" ? "adding it to your models" : (kind == "setup" ? "the setup" : (engine == .ollama ? "the pull" : "the download"))
        switch hold(kind, engine, name)?.phase {
        case .sending?:
            return "Sending this to your desktop."
        case .checking?:
            return "Your desktop has not confirmed \(what) yet, and this phone is checking. It will not be sent again."
        case .quiet(let checked)?:
            return checked
                ? "This phone did not see \(what) on your desktop. It may still happen. Look at your desktop before you try again."
                : "This phone could not read your desktop to check \(what). Look at your desktop before you try again."
        case nil:
            return nil
        }
    }

    // MARK: Mapping

    nonisolated static func entries(_ list: DeskForgeList<DeskModelsCatalogDTO>) -> [DeskModelsEntry] {
        var result: [DeskModelsEntry] = []
        for row in list.items where !result.contains(where: { $0.name == row.name }) {
            result.append(DeskModelsEntry(name: row.name, label: (row.label ?? "").isEmpty ? row.name : (row.label ?? ""),
                                          params: row.params ?? "", about: row.description ?? ""))
        }
        return result
    }

    nonisolated static func installedRows(_ list: DeskForgeList<DeskModelsInstalledDTO>, running: Set<String>) -> [DeskModelsInstalled] {
        var result: [DeskModelsInstalled] = []
        for row in list.items where !result.contains(where: { $0.name == row.name }) {
            result.append(DeskModelsInstalled(name: row.name, bytes: max(0, row.size ?? 0), running: running.contains(row.name)))
        }
        return result
    }

    nonisolated static func loadedRows(_ list: DeskForgeList<DeskModelsRunningDTO>) -> [DeskModelsLoaded] {
        list.items.map { DeskModelsLoaded(name: $0.name, bytes: max(0, $0.size ?? 0)) }
    }

    // MARK: Reading the desktop

    /// One read. It answers `.fresh` only when it is still the newest read of its kind, for the desktop it was
    /// sent to, and no change was on its way or finished meanwhile (then it is read again). A cancelled read is
    /// not an error: it changes nothing.
    private func read<Value: Sendable>(_ key: String, _ account: String,
                                       _ fetch: (APIClient) async throws -> Value) async -> DeskModelsRead<Value> {
        let serial = (reads[key] ?? 0) + 1
        reads[key] = serial
        for _ in 0..<3 {
            let writes = writeSerial
            do {
                guard let client = Connection.shared.client else { throw APIError.notPaired }
                let value = try await fetch(client)
                guard stillLive(account), reads[key] == serial else { return .stale }
                guard writes == writeSerial, inFlight == 0 else { continue }
                return .fresh(value)
            } catch {
                if error is CancellationError || Task.isCancelled { return .stale }
                Connection.shared.note(error)
                guard stillLive(account), reads[key] == serial else { return .stale }
                var status: Int?
                if let api = error as? APIError, case .server(let code, _) = api { status = code }
                return .failed(error.plainWords, status: status)
            }
        }
        guard stillLive(account), reads[key] == serial else { return .stale }
        return .failed("Your desktop was busy with another change. Try again in a moment.", status: nil)
    }

    /// Everything one engine's screen shows.
    @discardableResult
    func load(_ engine: ModelEngine) async -> Bool {
        guard let account = await readyAccount() else { return false }
        return engine == .ollama ? await loadOllama(account) : await loadBuiltIn(account)
    }

    private func edit(_ engine: ModelEngine, _ change: (inout DeskModelsEngineState) -> Void) {
        if engine == .ollama { change(&ollamaState) } else { change(&builtInState) }
    }

    /// A failed read: the first one shows Try again, a later one keeps what is shown and says it may be out of date.
    private func failed(_ engine: ModelEngine, _ why: String) {
        edit(engine) { state in
            if state.load == .loaded {
                state.stale = "Your desktop could not be read just now, so this may be out of date. " + why
            } else {
                state.load = .failed(why)
            }
        }
    }

    private func loadOllama(_ account: String) async -> Bool {
        if ollamaState.load != .loaded { ollamaState.load = .loading }
        let reach: DeskModelsReachDTO
        switch await read("ollama.status", account, { try await $0.deskModelsOllamaStatus() }) {
        case .stale: return false
        case .failed(let why, _): failed(.ollama, why); return false
        case .fresh(let value): reach = value
        }
        guard let reachable = reach.reachable else {
            failed(.ollama, "Your desktop's answer could not be read.")
            return false
        }
        let catalog: DeskForgeList<DeskModelsCatalogDTO>
        switch await read("ollama.catalog", account, { try await $0.deskModelsOllamaCatalog() }) {
        case .stale: return false
        case .failed(let why, _): failed(.ollama, why); return false
        case .fresh(let value): catalog = value
        }
        var installed: DeskForgeList<DeskModelsInstalledDTO>?
        var memory: DeskForgeList<DeskModelsRunningDTO>?
        var down = !reachable
        if reachable {
            switch await read("ollama.installed", account, { try await $0.deskModelsOllamaInstalled() }) {
            case .stale: return false
            case .failed(let why, let status):
                if status == 503 { down = true } else { failed(.ollama, why); return false }
            case .fresh(let value): installed = value
            }
        }
        if !down {
            switch await read("ollama.running", account, { try await $0.deskModelsOllamaRunning() }) {
            case .stale: return false
            case .failed(let why, let status):
                if status == 503 { down = true } else { failed(.ollama, why); return false }
            case .fresh(let value): memory = value
            }
        }
        let loaded = memory.map(Self.loadedRows) ?? []
        ollamaState.catalog = Self.entries(catalog)
        ollamaState.reachable = !down
        var rows: [DeskModelsInstalled] = []
        var skipped = 0
        if !down, let installed {
            rows = Self.installedRows(installed, running: Set(loaded.map(\.name)))
            skipped = installed.skipped
        }
        ollamaState.loaded = down ? [] : loaded
        ollamaState.installed = rows
        ollamaState.skipped = skipped
        ollamaState.stale = nil
        ollamaState.load = .loaded
        await readProgress(.ollama, account)
        return true
    }

    private func loadBuiltIn(_ account: String) async -> Bool {
        if builtInState.load != .loaded { builtInState.load = .loading }
        let catalog: DeskForgeList<DeskModelsCatalogDTO>
        switch await read("engine.catalog", account, { try await $0.deskModelsEngineCatalog() }) {
        case .stale: return false
        case .failed(let why, _): failed(.builtIn, why); return false
        case .fresh(let value): catalog = value
        }
        let downloaded: DeskForgeList<DeskModelsInstalledDTO>
        switch await read("engine.downloaded", account, { try await $0.deskModelsEngineDownloaded() }) {
        case .stale: return false
        case .failed(let why, _): failed(.builtIn, why); return false
        case .fresh(let value): downloaded = value
        }
        let status: DeskModelsEngineStatusDTO
        switch await read("engine.status", account, { try await $0.deskModelsEngineStatus() }) {
        case .stale: return false
        case .failed(let why, _): failed(.builtIn, why); return false
        case .fresh(let value): status = value
        }
        let running = status.running == true ? status.model : nil
        builtInState.catalog = Self.entries(catalog)
        builtInState.runningModel = running
        builtInState.installed = Self.installedRows(downloaded, running: running.map { [$0] } ?? [])
        builtInState.skipped = downloaded.skipped
        builtInState.stale = nil
        builtInState.load = .loaded
        await readProgress(.builtIn, account)
        return true
    }

    /// The status of every catalog model that is not installed, so a pull that is already running shows as running.
    private func readProgress(_ engine: ModelEngine, _ account: String) async {
        for entry in state(engine).catalog where !isInstalled(engine, entry.name) && DeskModelsWire.pathOK(entry.name) {
            guard stillLive(account) else { return }
            await refreshProgress(engine, entry.name, account)
        }
    }

    @discardableResult
    func refreshProgress(_ engine: ModelEngine, _ name: String, _ account: String) async -> Bool {
        let key = Self.progressKey(engine, name)
        switch await read("progress:" + key, account, { try await $0.deskModelsPullStatus(engine, name) }) {
        case .fresh(let dto):
            progressMap[key] = DeskModelsProgress(dto)
            return true
        case .failed:
            if progressMap[key] == nil { progressMap[key] = DeskModelsProgress(phase: .unread) }
            return false
        case .stale:
            return false
        }
    }

    /// Read one model's status again, from a screen (the "Check again" on a card).
    func recheckProgress(_ engine: ModelEngine, _ name: String) async {
        guard let account = await readyAccount(), DeskModelsWire.pathOK(name) else { return }
        await refreshProgress(engine, name, account)
    }

    /// The installed list (and what runs) again. True when it was read.
    @discardableResult
    private func refreshInstalled(_ engine: ModelEngine, _ account: String) async -> Bool {
        if engine == .ollama {
            switch await read("ollama.installed", account, { try await $0.deskModelsOllamaInstalled() }) {
            case .fresh(let list):
                ollamaState.installed = Self.installedRows(list, running: Set(ollamaState.loaded.map(\.name)))
                ollamaState.skipped = list.skipped
                return true
            default:
                return false
            }
        }
        switch await read("engine.downloaded", account, { try await $0.deskModelsEngineDownloaded() }) {
        case .fresh(let list):
            builtInState.installed = Self.installedRows(list, running: builtInState.runningModel.map { [$0] } ?? [])
            builtInState.skipped = list.skipped
            return true
        default:
            return false
        }
    }

    /// The built-in engine's status again. True when it was read.
    @discardableResult
    private func refreshEngineStatus(_ account: String) async -> Bool {
        switch await read("engine.status", account, { try await $0.deskModelsEngineStatus() }) {
        case .fresh(let status):
            setRunning(status.running == true ? status.model : nil)
            return true
        default:
            return false
        }
    }

    private func setRunning(_ model: String?) {
        builtInState.runningModel = model
        for index in builtInState.installed.indices {
            builtInState.installed[index].running = builtInState.installed[index].name == model
        }
    }

    /// The person's models, for "In your models". The model list is read without the connection addresses.
    func loadConnections() async {
        guard let account = await readyAccount() else { return }
        await readConnections(account)
    }

    @discardableResult
    private func readConnections(_ account: String) async -> Bool {
        switch await read("connections", account, { try await $0.modelChoices() }) {
        case .fresh(let list):
            connectionList = list
            connectionsRead = true
            return true
        default:
            return false
        }
    }

    /// A short poll while something runs: the status of each pull or download the desktop says is running, and
    /// the installed list when one of them ended.
    func tick(_ engine: ModelEngine) async {
        guard let account = await readyAccount() else { return }
        let prefix = engine.key + "|"
        let names = progressMap.compactMap { entry -> String? in
            entry.value.phase == .running && entry.key.hasPrefix(prefix) ? String(entry.key.dropFirst(prefix.count)) : nil
        }
        var ended = false
        for name in names where DeskModelsWire.pathOK(name) {
            if await refreshProgress(engine, name, account), progressMap[Self.progressKey(engine, name)]?.phase != .running {
                ended = true
            }
        }
        if ended { await refreshInstalled(engine, account) }
    }

    /// True while a status is worth reading again soon: something runs, or is being checked.
    func active(_ engine: ModelEngine) -> Bool {
        guard current else { return false }
        let prefix = engine.key + "|"
        if progressMap.contains(where: { $0.value.phase == .running && $0.key.hasPrefix(prefix) }) { return true }
        return busyKeys.contains(Self.engineKey)
    }

    // MARK: Changing the desktop

    /// The status the desktop refused the request with, or nil when it may have come after the change was made.
    private static func refusal(_ error: Error) -> Int? {
        guard let api = error as? APIError else { return nil }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return 0
        case .server(let status, _): return (400..<500).contains(status) ? status : nil
        case .offline, .unreadable: return nil
        }
    }

    private func begin(_ key: String) -> String? {
        guard let account = readyNow(), !busyKeys.contains(key) else { return nil }
        busyKeys.insert(key)
        return account
    }

    private func finish(_ key: String, _ account: String) {
        if self.account == account { busyKeys.remove(key) }
    }

    /// Send one change, once. Reads that overlap it are read again.
    private func attempt<Value: Sendable>(_ account: String,
                                          _ send: (APIClient) async throws -> Value) async -> DeskModelsSent<Value> {
        inFlight += 1
        do {
            guard let client = Connection.shared.client else { throw APIError.notPaired }
            let value = try await send(client)
            inFlight -= 1
            writeSerial += 1
            return stillLive(account) ? .ok(value) : .moved
        } catch {
            inFlight -= 1
            writeSerial += 1
            Connection.shared.note(error)
            guard stillLive(account) else { return .moved }
            if Self.refusal(error) != nil { return .refused(error.plainWords) }
            return .lost(error.plainWords)
        }
    }

    private static func unchecked(_ what: String, _ why: String) -> String {
        "Your desktop did not confirm \(what), and it could not be read to check. Look again in a moment before trying again. " + why
    }

    // MARK: Pull and download

    /// Start a pull (Ollama) or a download (built-in) of one catalog model. The hold is set here, before the
    /// request leaves; the name must be one the desktop's own catalog returned; a model with a hold, a status that
    /// says it runs, or an installed copy is never sent.
    func startPull(_ engine: ModelEngine, _ entry: DeskModelsEntry) {
        guard let account = readyNow(), DeskModelsWire.pathOK(entry.name),
              state(engine).catalog.contains(where: { $0.name == entry.name }) else { return }
        let key = Self.progressKey(engine, entry.name)
        let hold = holdKey("pull", engine, entry.name)
        guard holds[hold] == nil, !isInstalled(engine, entry.name),
              let before = progressMap[key], before.phase != .running, before.phase != .unread else { return }
        holds[hold] = DeskModelsHold(phase: .sending, before: before)
        noteMap[Self.noteKey(engine, entry.name)] = nil
        Task { await self.sendPull(engine, entry.name, account, hold, before) }
    }

    private func sendPull(_ engine: ModelEngine, _ name: String, _ account: String, _ hold: String, _ before: DeskModelsProgress) async {
        let note = Self.noteKey(engine, name)
        switch await attempt(account, { try await $0.deskModelsPull(engine, name) }) {
        case .moved:
            holds[hold]?.phase = .quiet(checked: false)
        case .refused(let why):
            holds[hold] = nil
            noteMap[note] = "Nothing was downloaded. " + why
        case .ok:
            holds[hold]?.phase = .checking
            watchPull(hold, engine, name, account, before)
        case .lost(let why):
            holds[hold]?.phase = .checking
            noteMap[note] = "Your desktop did not confirm it. " + why
            watchPull(hold, engine, name, account, before)
        }
    }

    /// Read the pull status and the installed list for about a minute, here in the store, until the desktop shows
    /// the pull. Nothing is sent. Without a sign, the hold goes quiet and stays until the person says they looked.
    private func watchPull(_ hold: String, _ engine: ModelEngine, _ name: String, _ account: String, _ before: DeskModelsProgress) {
        watches[hold]?.cancel()
        watches[hold] = Task { [weak self] in
            guard let self else { return }
            var checked = false
            for round in 0..<20 {
                if round > 0 { try? await Task.sleep(for: .seconds(3)) }
                if Task.isCancelled { return }
                guard self.stillLive(account) else {
                    self.holds[hold]?.phase = .quiet(checked: false)
                    self.watches[hold] = nil
                    return
                }
                switch await self.settlePull(engine, name, account, before) {
                case .released:
                    self.holds[hold] = nil
                    self.watches[hold] = nil
                    self.noteMap[Self.noteKey(engine, name)] = nil
                    return
                case .pending(let ok):
                    checked = checked || ok
                }
            }
            if Task.isCancelled { return }
            self.holds[hold]?.phase = .quiet(checked: checked)
            self.watches[hold] = nil
        }
    }

    private func settlePull(_ engine: ModelEngine, _ name: String, _ account: String, _ before: DeskModelsProgress) async -> DeskModelsSettle {
        let key = Self.progressKey(engine, name)
        guard await refreshProgress(engine, name, account), let now = progressMap[key] else { return .pending(checked: false) }
        if now.phase == .running { return .released }
        if now.phase != .notStarted, now != before {
            await refreshInstalled(engine, account)
            return .released
        }
        if await refreshInstalled(engine, account), isInstalled(engine, name) { return .released }
        return .pending(checked: true)
    }

    // MARK: Delete

    /// Delete one installed model. The screen draws its confirm first. A lost answer reads the installed list.
    func delete(_ engine: ModelEngine, _ name: String) async -> DeskForgeOutcome {
        guard on, isAdmin, DeskModelsWire.pathOK(name) else {
            return .refused("This model's name cannot be sent from your phone. Delete it in Kairos on your desktop.")
        }
        let key = "delete|" + Self.progressKey(engine, name)
        guard let account = begin(key) else { return .busy }
        defer { finish(key, account) }
        switch await attempt(account, { try await $0.deskModelsDelete(engine, name) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            // The desktop forgets the pull of a deleted model.
            progressMap[Self.progressKey(engine, name)] = DeskModelsProgress()
            await refreshInstalled(engine, account)
            if engine == .builtIn { await refreshEngineStatus(account) }
            return .done
        case .refused(let why):
            return .refused("Nothing was deleted. " + why)
        case .lost(let why):
            guard await refreshInstalled(engine, account) else { return .unconfirmed(Self.unchecked("the delete", why)) }
            if engine == .builtIn { await refreshEngineStatus(account) }
            if !state(engine).installed.contains(where: { $0.name == name }) { return .done }
            return .unconfirmed("Your desktop did not confirm the delete. This model is still installed there. " + why)
        }
    }

    // MARK: The built-in engine

    /// Start the engine on one downloaded model. The desktop waits up to a minute for it, so a lost answer is
    /// followed by reading the engine's status for about 80 seconds. Nothing is sent a second time.
    func startEngine(_ name: String) async -> DeskForgeOutcome {
        guard on, isAdmin, DeskModelsWire.pathOK(name) else { return .refused("This model cannot be started from your phone.") }
        guard let account = begin(Self.engineKey) else { return .busy }
        defer { finish(Self.engineKey, account) }
        noteMap[Self.engineKey] = "Starting \(name). Your desktop can take a minute."
        defer { if self.account == account { noteMap[Self.engineKey] = nil } }
        switch await attempt(account, { try await $0.deskModelsEngineStart(name) }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok(let status):
            setRunning(status.running == true ? status.model : nil)
            return status.running == true && status.model == name ? .done : .refused("Your desktop did not start it.")
        case .refused(let why):
            return .refused("It was not started. " + why)
        case .lost(let why):
            var checked = false
            for _ in 0..<20 {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                guard stillLive(account) else { return .unconfirmed(Self.desktopChanged) }
                if await refreshEngineStatus(account) {
                    checked = true
                    if builtInState.runningModel == name { return .done }
                }
            }
            return .unconfirmed(checked
                ? "Your desktop did not confirm the start, and it is not running \(name) now. " + why
                : Self.unchecked("the start", why))
        }
    }

    /// Stop whatever the built-in engine runs. A lost answer reads the status.
    func stopEngine() async -> DeskForgeOutcome {
        guard on, isAdmin else { return .refused(Self.adminLine) }
        guard let account = begin(Self.engineKey) else { return .busy }
        defer { finish(Self.engineKey, account) }
        switch await attempt(account, { try await $0.deskModelsEngineStop() }) {
        case .moved:
            return .refused(Self.desktopChanged)
        case .ok:
            setRunning(nil)
            await refreshEngineStatus(account)
            return .done
        case .refused(let why):
            return .refused("It was not stopped. " + why)
        case .lost(let why):
            guard await refreshEngineStatus(account) else { return .unconfirmed(Self.unchecked("the stop", why)) }
            if builtInState.runningModel == nil { return .done }
            return .unconfirmed("Your desktop did not confirm the stop. A model is still running there. " + why)
        }
    }

    // MARK: Use in chat

    /// Make a connection for one installed model. It makes a NEW one on every call, so it is sent only when the
    /// models list was read and shows none for this model, and never while one is on its way or being checked.
    func startRegister(_ engine: ModelEngine, _ name: String) {
        guard let account = readyNow(), connectionsRead, !connected(engine, name) else { return }
        let hold = holdKey("register", engine, name)
        guard holds[hold] == nil else { return }
        holds[hold] = DeskModelsHold(phase: .sending)
        noteMap[Self.noteKey(engine, name)] = nil
        Task { await self.sendRegister(engine, name, account, hold) }
    }

    private func sendRegister(_ engine: ModelEngine, _ name: String, _ account: String, _ hold: String) async {
        let note = Self.noteKey(engine, name)
        switch await attempt(account, { try await $0.deskModelsRegister(engine, name) }) {
        case .moved:
            holds[hold]?.phase = .quiet(checked: false)
        case .refused(let why):
            holds[hold] = nil
            noteMap[note] = "Nothing was added. " + why
        case .ok:
            registeredNow.insert(Self.progressKey(engine, name))
            holds[hold] = nil
            await readConnections(account)
        case .lost(let why):
            holds[hold]?.phase = .checking
            noteMap[note] = "Your desktop did not confirm it. " + why
            watchRegister(hold, engine, name, account)
        }
    }

    private func watchRegister(_ hold: String, _ engine: ModelEngine, _ name: String, _ account: String) {
        watches[hold]?.cancel()
        watches[hold] = Task { [weak self] in
            guard let self else { return }
            var checked = false
            for round in 0..<5 {
                if round > 0 { try? await Task.sleep(for: .seconds(3)) }
                if Task.isCancelled { return }
                guard self.stillLive(account) else {
                    self.holds[hold]?.phase = .quiet(checked: false)
                    self.watches[hold] = nil
                    return
                }
                if await self.readConnections(account) {
                    checked = true
                    if self.connected(engine, name) {
                        self.holds[hold] = nil
                        self.watches[hold] = nil
                        self.noteMap[Self.noteKey(engine, name)] = nil
                        return
                    }
                }
            }
            if Task.isCancelled { return }
            if checked {
                // The desktop was read and has no connection for this model: it is safe to offer the button again.
                self.holds[hold] = nil
                self.noteMap[Self.noteKey(engine, name)] = "Your desktop did not add it. You can try again."
            } else {
                self.holds[hold]?.phase = .quiet(checked: false)
            }
            self.watches[hold] = nil
        }
    }

    // MARK: Holds the person looks at

    /// Read the desktop again for a hold that went quiet. Nothing is sent.
    func recheck(_ kind: String, _ engine: ModelEngine, _ name: String) {
        guard let account = readyNow() else { return }
        let hold = holdKey(kind, engine, name)
        guard let held = holds[hold], case .quiet = held.phase else { return }
        holds[hold]?.phase = .checking
        switch kind {
        case "register": watchRegister(hold, engine, name, account)
        case "setup": watchSetup(hold, name, account, held.stageBefore ?? .idle)
        default: watchPull(hold, engine, name, account, held.before ?? DeskModelsProgress())
        }
    }

    /// The person looked at their desktop and says nothing is running there: the button may come back. Only a
    /// hold that went quiet can be let go.
    func release(_ kind: String, _ engine: ModelEngine, _ name: String) {
        let hold = holdKey(kind, engine, name)
        guard let held = holds[hold], case .quiet = held.phase else { return }
        holds[hold] = nil
        noteMap[Self.noteKey(engine, name)] = nil
    }

    // MARK: The setup sheet

    /// The five choices, the recommended model and where its setup stands.
    func loadSetup() async {
        guard let account = await readyAccount() else { return }
        if setupState.load != .loaded { setupState.load = .loading }
        let status: DeskModelsSetupStatusDTO
        switch await read("setup.status", account, { try await $0.deskModelsSetupStatus() }) {
        case .stale: return
        case .failed(let why, _):
            if setupState.load != .loaded { setupState.load = .failed(why) }
            return
        case .fresh(let value): status = value
        }
        setupState.choices = Self.choices(status)
        setupState.load = .loaded
        switch await read("setup.recommendation", account, { try await $0.deskModelsRecommendation() }) {
        case .stale:
            return
        case .failed(let why, _):
            setupState.recommendation = nil
            setupState.recommendationLine = why
        case .fresh(let dto):
            setupState.recommendationLine = nil
            setupState.recommendation = DeskModelsRecommendation(
                name: dto.name, title: Self.recommendationTitle(dto), about: dto.description ?? "",
                downloadBytes: dto.estimatedDownloadBytes, freeBytes: dto.diskFreeBytes, downloaded: dto.downloaded ?? false)
            await refreshStage(account)
        }
    }

    private nonisolated static func recommendationTitle(_ dto: DeskModelsRecommendationDTO) -> String {
        let label = (dto.label ?? "").isEmpty ? dto.name : (dto.label ?? "")
        return (dto.params ?? "").isEmpty ? label : "\(label) (\(dto.params ?? ""))"
    }

    private nonisolated static func choices(_ status: DeskModelsSetupStatusDTO) -> [SetupChoice] {
        func state(_ sign: DeskModelsSignInDTO?) -> SetupChoiceState {
            guard let sign, sign.present else { return .notInstalled }
            return sign.signedIn == true ? .ready : .notSet
        }
        return LocalModelsSample.choices.map { base in
            var choice = base
            switch base.id {
            case "claude": choice.state = state(status.claude)
            case "chatgpt": choice.state = state(status.codex)
            case "gemini": choice.state = state(status.antigravity)
            case "key": choice.state = (status.connections?.api?.items.count ?? 0) > 0 ? .ready : .notSet
            default: choice.state = (status.connections?.local?.items.count ?? 0) > 0 ? .ready : .notSet
            }
            return choice
        }
    }

    @discardableResult
    private func refreshStage(_ account: String) async -> Bool {
        guard let name = setupState.recommendation?.name, DeskModelsWire.pathOK(name) else { return false }
        switch await read("setup.stage", account, { try await $0.deskModelsSetupProgress(name) }) {
        case .fresh(let dto):
            setupState.stage = DeskModelsStage(dto)
            setupState.stageRead = true
            return true
        default:
            return false
        }
    }

    /// While the recommended model is being set up: its status, and the choices again once it connects.
    func tickSetup() async {
        guard let account = await readyAccount(), setupState.stage.active else { return }
        if await refreshStage(account), setupState.stage == .connected {
            await readConnections(account)
            if case .fresh(let status) = await read("setup.status", account, { try await $0.deskModelsSetupStatus() }) {
                setupState.choices = Self.choices(status)
            }
        }
    }

    /// Download (when needed), start and connect the recommended model. The hold is set before the request leaves;
    /// the name is the one the desktop's own recommendation returned.
    func startSetup() {
        guard let account = readyNow(), let rec = setupState.recommendation, DeskModelsWire.pathOK(rec.name),
              setupState.stageRead, !setupState.stage.active, setupState.stage != .connected else { return }
        let hold = holdKey("setup", .builtIn, rec.name)
        guard holds[hold] == nil else { return }
        let before = setupState.stage
        holds[hold] = DeskModelsHold(phase: .sending, stageBefore: before)
        noteMap[Self.noteKey(.builtIn, rec.name)] = nil
        Task { await self.sendSetup(rec.name, account, hold, before) }
    }

    private func sendSetup(_ name: String, _ account: String, _ hold: String, _ before: DeskModelsStage) async {
        let note = Self.noteKey(.builtIn, name)
        switch await attempt(account, { try await $0.deskModelsSetup(name) }) {
        case .moved:
            holds[hold]?.phase = .quiet(checked: false)
        case .refused(let why):
            holds[hold] = nil
            noteMap[note] = "Nothing was started. " + why
        case .ok:
            holds[hold]?.phase = .checking
            watchSetup(hold, name, account, before)
        case .lost(let why):
            holds[hold]?.phase = .checking
            noteMap[note] = "Your desktop did not confirm it. " + why
            watchSetup(hold, name, account, before)
        }
    }

    private func watchSetup(_ hold: String, _ name: String, _ account: String, _ before: DeskModelsStage) {
        watches[hold]?.cancel()
        watches[hold] = Task { [weak self] in
            guard let self else { return }
            var checked = false
            for round in 0..<20 {
                if round > 0 { try? await Task.sleep(for: .seconds(3)) }
                if Task.isCancelled { return }
                guard self.stillLive(account) else {
                    self.holds[hold]?.phase = .quiet(checked: false)
                    self.watches[hold] = nil
                    return
                }
                if await self.refreshStage(account) {
                    checked = true
                    let now = self.setupState.stage
                    if now.active || (now != .idle && now != before) {
                        self.holds[hold] = nil
                        self.watches[hold] = nil
                        self.noteMap[Self.noteKey(.builtIn, name)] = nil
                        return
                    }
                }
            }
            if Task.isCancelled { return }
            self.holds[hold]?.phase = .quiet(checked: checked)
            self.watches[hold] = nil
        }
    }
}
