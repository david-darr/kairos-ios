import Foundation
import Observation

/// The one data store in front of Home and the chats. Screens read it and call it; it talks to
/// whichever backend is in use (the sample one until a desktop is paired, the live one after).
@Observable
final class ChatStore {
    static let shared = ChatStore()

    private(set) var isSample = true
    /// Goes up when the data source changes (paired, unpaired), so open screens can go back to Home.
    private(set) var generation = 0

    // Home
    private(set) var bots: [Bot] = []
    private(set) var pinnedIDs: [String] = []
    private(set) var conversations: [Conversation] = []
    private(set) var glance = Glance()
    private(set) var projects: [ChatProject] = []
    /// Teams the person pinned on Home. The desktop has no pin for a team, so these stay on this phone.
    private(set) var pinnedTeamIDs: [String]
    private(set) var homeLoaded = false
    /// Why Home could not be read, in plain words. nil when it could.
    private(set) var homeError: String?

    /// Every turn the desktop is running (and ones that just ended), by chat or bot conversation id.
    private(set) var runs: [String: RunState] = [:]

    @ObservationIgnored private var backend: ChatBackend
    private let connection: Connection
    @ObservationIgnored private var modelChats: [String: ModelChatState] = [:]
    @ObservationIgnored private var botChats: [String: BotChatState] = [:]
    @ObservationIgnored private var threadOwners: [String: String] = [:]
    @ObservationIgnored private var homeRefresh: Task<Void, Never>?
    @ObservationIgnored private var polls = 0
    @ObservationIgnored private var loadingHome = false

    private static let teamPinsKey = "homeTeamPins"
    private static let sampleTeamPins = ["content"]

    private init() {
        connection = Connection.shared
        backend = SampleBackend()
        pinnedTeamIDs = ChatStore.sampleTeamPins
        attach()
        connection.onChange = { [weak self] in self?.connectionChanged() }
        connection.onPacket = { [weak self] data in (self?.backend as? LiveBackend)?.handle(packet: data) }
        connection.onStreamOpen = { [weak self] in
            guard let self, !self.isSample else { return }
            Task { await self.refreshHome() }
        }
        connectionChanged()
    }

    private func attach() {
        backend.onEvent = { [weak self] event in self?.apply(event) }
    }

    /// The connection moved between sample data and a paired desktop (or the other way).
    private func connectionChanged() {
        let wantSample = connection.usesSampleData
        if wantSample != backend.isSample {
            backend.onEvent = nil
            backend = wantSample ? SampleBackend() : LiveBackend(connection: connection)
            isSample = wantSample
            attach()
            bots = []
            pinnedIDs = []
            conversations = []
            projects = []
            pinnedTeamIDs = wantSample ? ChatStore.sampleTeamPins : (UserDefaults.standard.stringArray(forKey: ChatStore.teamPinsKey) ?? [])
            glance = Glance()
            runs = [:]
            modelChats = [:]
            botChats = [:]
            threadOwners = [:]
            homeLoaded = false
            homeError = nil
            generation += 1
            publishNumbers()
        }
        if !wantSample {
            switch connection.state {
            case .connected:
                Task { await refreshHome() }
            case .signedOut:
                homeError = "This iPhone is no longer paired. Pair it again to see your chats."
            default:
                break
            }
        }
    }

    // MARK: Home

    func bot(_ id: String) -> Bot {
        if let bot = bots.first(where: { $0.id == id }) { return bot }
        return isSample ? SampleData.bot(id) : Bot(id: id, name: "Bot", role: "", colorHex: Palette.botSand, status: .offline)
    }

    /// Kip, the front desk: always first on Home.
    var kip: Bot? { bots.first(where: \.isKip) ?? (isSample ? SampleData.kip : nil) }

    /// The bots the person pinned, without Kip (Home always shows Kip first).
    var pinnedBots: [Bot] { pinnedIDs.filter { id in bots.contains { $0.id == id && !$0.isKip } }.map(bot) }

    /// Every single bot (not teams), Kip first, then the roster order.
    var singleBots: [Bot] {
        let all = bots.filter(\.members.isEmpty)
        return all.filter(\.isKip) + all.filter { !$0.isKip }
    }

    /// Model chats only, starred first, then newest.
    var chats: [Conversation] { conversations.filter { $0.kind == .model } }

    /// The newest conversation with each bot, by bot id.
    var botConversations: [String: Conversation] {
        var result: [String: Conversation] = [:]
        for conversation in conversations {
            if case .bot(let id) = conversation.kind, result[id] == nil { result[id] = conversation }
        }
        return result
    }

    func project(_ id: String) -> ChatProject? { projects.first { $0.id == id } }

    func chats(inProject id: String) -> [Conversation] { chats.filter { $0.projectID == id } }

    func isPinned(bot id: String) -> Bool { pinnedIDs.contains(id) }

    func isPinned(team id: String) -> Bool { pinnedTeamIDs.contains(id) }

    /// Pin or unpin a bot on Home. Saved on the desktop, so its Bots sidebar shows the same pins.
    func togglePin(bot id: String) async -> String? {
        let wanted = !pinnedIDs.contains(id)
        let before = pinnedIDs
        if wanted { pinnedIDs.append(id) } else { pinnedIDs.removeAll { $0 == id } }
        do {
            try await backend.pinBot(id, pinned: wanted)
            return nil
        } catch {
            pinnedIDs = before
            return error.plainWords
        }
    }

    /// Pin or unpin a team on Home. Kept on this phone: the desktop has no pin for a team.
    func togglePin(team id: String) {
        if pinnedTeamIDs.contains(id) { pinnedTeamIDs.removeAll { $0 == id } } else { pinnedTeamIDs.append(id) }
        if !isSample { UserDefaults.standard.set(pinnedTeamIDs, forKey: ChatStore.teamPinsKey) }
    }

    /// Put a chat in a project, or take it out (nil).
    func move(chat id: String, toProject projectID: String?) async -> String? {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return nil }
        let before = conversations[index].projectID
        conversations[index].projectID = projectID
        do {
            try await backend.setChatProject(id, projectID: projectID)
            refreshHomeSoon()
            return nil
        } catch {
            if let again = conversations.firstIndex(where: { $0.id == id }) { conversations[again].projectID = before }
            return error.plainWords
        }
    }

    func createProject(name: String, instructions: String) async throws -> ChatProject {
        let made = try await backend.createProject(name: name, instructions: instructions)
        if !projects.contains(where: { $0.id == made.id }) {
            projects.append(made)
            projects.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
        return made
    }

    /// A starred chat moves to the top at once; the desktop's list follows on the next read.
    fileprivate func starChanged(_ id: String, starred: Bool) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        var moved = conversations.remove(at: index)
        moved.starred = starred
        let models = conversations.filter { $0.kind == .model }
        let others = conversations.filter { $0.kind != .model }
        let stars = models.filter(\.starred)
        let rest = models.filter { !$0.starred }
        conversations = starred ? [moved] + stars + rest + others : stars + [moved] + rest + others
    }

    /// What the live-work pill above the tab bar says, or nil when nothing runs.
    var liveWork: LiveWork? {
        if isSample { return SampleData.liveWork }
        let active = runs.filter { $0.value.isRunning }
        guard let first = active.min(by: { ($0.value.startedAt ?? .distantPast) < ($1.value.startedAt ?? .distantPast) }) else { return nil }
        if let botID = threadOwners[first.key] {
            return LiveWork(botID: botID, text: "\(bot(botID).name) is working", others: active.count - 1)
        }
        let title = first.value.title.isEmpty ? "A chat" : first.value.title
        return LiveWork(botID: bots.first(where: \.isKip)?.id ?? "kip", text: "Working on \(title)", others: active.count - 1)
    }

    func refreshHome() async {
        guard !loadingHome else { return }
        loadingHome = true
        defer { loadingHome = false }
        let source = backend
        do {
            let home = try await source.loadHome()
            guard source === backend else { return }
            show(home)
            homeLoaded = true
            homeError = nil
        } catch {
            guard source === backend else { return }
            homeError = error.plainWords
        }
        await refreshGlance()
    }

    func refreshGlance() async {
        let source = backend
        if let fresh = try? await source.loadGlance(), source === backend {
            glance = fresh
            publishNumbers()
        }
    }

    /// The slim poll, while Home is on screen.
    func poll() async {
        guard !isSample, connection.isConnected else { return }
        polls += 1
        let source = backend
        if let home = try? await source.pollHome(), source === backend {
            show(home)
            homeError = nil
        }
        if polls % 3 == 0 { await refreshGlance() }
    }

    private func show(_ home: HomeData) {
        bots = home.bots
        pinnedIDs = home.pinned
        conversations = home.conversations
        projects = home.projects
        for conversation in home.conversations {
            if case .bot(let botID) = conversation.kind { threadOwners[conversation.id] = botID }
        }
        for chat in botChats.values { chat.botChanged() }
    }

    private func refreshHomeSoon() {
        homeRefresh?.cancel()
        homeRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await self?.refreshHome()
        }
    }

    // MARK: Chats

    /// The state for one model chat. nil makes a brand new one, created on the desktop at the first send.
    func modelChat(_ id: String?) -> ModelChatState {
        if let id, let known = modelChats[id] { return known }
        let state = ModelChatState(store: self, id: id)
        if let id { modelChats[id] = state }
        return state
    }

    /// A brand new model chat that joins this project at its first message.
    func newModelChat(inProject projectID: String) -> ModelChatState {
        let state = ModelChatState(store: self, id: nil)
        state.projectID = projectID
        return state
    }

    func botChat(_ botID: String) -> BotChatState {
        if let known = botChats[botID] { return known }
        let state = BotChatState(store: self, botID: botID)
        botChats[botID] = state
        return state
    }

    fileprivate var source: ChatBackend { backend }

    fileprivate func adopt(_ chat: ModelChatState, id: String) {
        modelChats[id] = chat
    }

    fileprivate func own(thread id: String, botID: String) {
        threadOwners[id] = botID
    }

    fileprivate func forgetRun(_ id: String, turnID: String) {
        if let run = runs[id], run.turnID == turnID, !run.isRunning { runs[id] = nil }
    }

    fileprivate func removed(chatID: String) {
        modelChats[chatID] = nil
        runs[chatID] = nil
        conversations.removeAll { $0.id == chatID }
        refreshHomeSoon()
    }

    fileprivate func touched() { refreshHomeSoon() }

    fileprivate func note(_ error: Error) { connection.note(error) }

    // MARK: Events

    func apply(_ event: StoreEvent) {
        switch event {
        case .snapshot(let fresh):
            let ended = runs.filter { $0.value.isRunning && fresh[$0.key] == nil }
            var next = fresh
            for (id, run) in ended {
                // It finished while this phone was away from the stream: the saved chat has the result.
                var done = run
                done.status = .done
                done.request = nil
                next[id] = done
            }
            runs = next
            for (id, run) in ended { runEnded(id, run: run) }
            for (id, run) in fresh where run.isRunning { ConnectionSeam.runChanged(info(id, run)) }
        case .started(let chatID, let run):
            runs[chatID] = run
            modelChats[chatID]?.runStarted()
            markWorking(chatID, true, preview: run.prompt)
            ConnectionSeam.runBegan(info(chatID, run))
        case .chunk(let chatID, let turnID, let text):
            guard var run = runs[chatID], run.turnID == turnID else { return }
            run.text += text
            runs[chatID] = run
        case .step(let chatID, let turnID, let id, let text, let finished, let failed):
            guard var run = runs[chatID], run.turnID == turnID else { return }
            TranscriptParsing.apply(id: id, text: text, finished: finished, failed: failed, to: &run.steps)
            runs[chatID] = run
            ConnectionSeam.runChanged(info(chatID, run))
        case .changed(let chatID, let turnID, let change):
            guard var run = runs[chatID], run.turnID == turnID else { return }
            let wasRunning = run.isRunning
            if let status = change.status { run.status = status }
            if let stopping = change.stopping { run.stopping = stopping }
            if change.requestChanged { run.request = change.request }
            if change.errorChanged { run.error = change.error }
            if change.providerDetailChanged { run.providerDetail = change.providerDetail }
            runs[chatID] = run
            if wasRunning && !run.isRunning {
                runEnded(chatID, run: run)
            } else {
                ConnectionSeam.runChanged(info(chatID, run))
            }
        case .background(let chatID, let items):
            modelChats[chatID]?.background = items
        case .followup(let chatID, let entry):
            modelChats[chatID]?.followup(entry)
        case .botQueue(let threadID, let items, let revision, let paused):
            botChat(forThread: threadID)?.queueChanged(items, revision: revision, paused: paused)
        case .botRequest(let threadID, let request, let open):
            botChat(forThread: threadID)?.requestChanged(request, open: open)
            refreshHomeSoon()
        case .botChanged(let threadID):
            botChat(forThread: threadID)?.refreshNewest()
        }
    }

    private func botChat(forThread id: String) -> BotChatState? {
        if let botID = threadOwners[id], let chat = botChats[botID] { return chat }
        return botChats.values.first { $0.threadID == id }
    }

    private func runEnded(_ id: String, run: RunState) {
        markWorking(id, false, preview: nil)
        modelChats[id]?.runEnded(run)
        botChat(forThread: id)?.runEnded(run)
        if modelChats[id] == nil && botChat(forThread: id) == nil {
            // Nobody is looking at it: there is nothing to reload, so let the finished turn go.
            runs[id] = nil
        }
        ConnectionSeam.runEnded(info(id, run))
        refreshHomeSoon()
    }

    private func markWorking(_ id: String, _ working: Bool, preview: String?) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].working = working
        if working {
            conversations[index].time = "now"
            if case .model = conversations[index].kind, let preview, !preview.isEmpty {
                conversations[index].preview = ChatFormat.oneLine(preview)
            }
        }
    }

    // MARK: The native seam

    private func info(_ id: String, _ run: RunState) -> ConnectionSeam.RunInfo {
        let botID = threadOwners[id]
        return ConnectionSeam.RunInfo(
            chatID: id, turnID: run.turnID, title: run.title, botID: botID, botName: botID.map { bot($0).name },
            step: run.steps.last(where: { !$0.done })?.text ?? run.steps.last?.text ?? "",
            status: run.status.rawValue, waitingOnPerson: run.request != nil, error: run.error)
    }

    private func publishNumbers() {
        guard !isSample else { return }
        ConnectionSeam.homeChanged(ConnectionSeam.HomeNumbers(
            needsYou: glance.needsYou, running: glance.running,
            usage: glance.usage.map { ConnectionSeam.Usage(provider: $0.provider, percent: $0.percent) },
            nextEvent: glance.nextEvent))
    }

    /// Stop the turn a Live Activity or a notification names (`NativeBridge.stop`).
    func stopRun(turnID: String) async {
        guard let entry = runs.first(where: { $0.value.turnID == turnID }) else { return }
        do {
            if let botID = threadOwners[entry.key] {
                _ = botID
                try await backend.interrupt(threadID: entry.key, turnID: turnID)
            } else {
                try await backend.stop(chatID: entry.key, turnID: turnID)
            }
        } catch {
            connection.note(error)
        }
    }
}

// MARK: - One model chat

/// Everything one model chat screen shows and does. Made by `ChatStore.modelChat(_:)`.
@Observable
final class ModelChatState {
    nonisolated enum Phase: Equatable, Sendable { case idle, loading, loaded, failed(String) }

    private unowned let store: ChatStore
    /// nil until the chat exists on the desktop (a new chat is made at the first send).
    private(set) var id: String?
    private(set) var title = "New chat"
    private(set) var entries: [TranscriptEntry] = []
    private(set) var settings: ChatSettings
    private(set) var starred = false
    private(set) var contextPercent: Double?
    fileprivate(set) var background: [BackgroundItem] = []
    private(set) var phase: Phase = .idle
    private(set) var queue: [QueuedMessage] = []
    private(set) var queuePaused = false
    private(set) var staged: [StagedAttachment] = []
    /// The message was sent and the desktop has not said "started" yet.
    private(set) var sending = false
    /// One plain line to show as a toast, then clear.
    var notice: String?
    /// Text to put back in the composer (a send that failed, a queued message taken back to edit).
    var restoredDraft: String?
    private(set) var deleted = false
    /// The project a new chat joins when it is made on the desktop.
    fileprivate(set) var projectID: String?

    @ObservationIgnored private var keptSteps: [StepLine] = []
    @ObservationIgnored private var loadedOnce = false

    init(store: ChatStore, id: String?) {
        self.store = store
        self.id = id
        settings = store.isSample ? SampleBackend.settings : ChatSettings()
        if id == nil { phase = .loaded }
    }

    var isSample: Bool { store.isSample }
    var run: RunState? { id.flatMap { store.runs[$0] } }
    var isBusy: Bool { sending || run?.isRunning == true }
    var isStopping: Bool { run?.stopping == true }
    var request: PendingRequest? { run?.isRunning == true ? run?.request : nil }
    var runningCount: Int { background.filter(\.isRunning).count }
    var isEmpty: Bool { entries.isEmpty && run == nil && !sending }

    /// What the screen draws: the saved messages, then the turn that is running or just ended.
    var transcript: [TranscriptEntry] {
        var result = entries
        guard let run else { return result }
        let lastTalk = result.last { $0.isUser || $0.isAssistant }
        if !run.prompt.isEmpty, !(lastTalk?.isUser == true && lastTalk?.text == run.prompt) {
            // A turn started somewhere else: show its question too.
            if run.isRunning || lastTalk?.isUser == true || lastTalk == nil {
                result.append(TranscriptEntry(id: "live-user-\(run.turnID)", role: .user, text: run.prompt, time: run.startedAt))
            } else {
                // The saved chat already holds this finished turn.
                return result
            }
        }
        let parsed = TranscriptParsing.body(run.text)
        var live = TranscriptEntry(id: "live-\(run.turnID)", role: .assistant, text: parsed.text, time: run.startedAt)
        live.steps = run.steps
        live.files = parsed.files
        live.sources = parsed.sources
        live.streaming = run.isRunning
        switch run.status {
        case .failed: live.failure = run.error ?? "The reply failed. Check the model's connection, or pick another model."
        case .stopped: live.failure = run.text.isEmpty ? "Stopped before a response started." : "Stopped. The partial reply was saved."
        default: break
        }
        result.append(live)
        return result
    }

    /// The live line under the title while a turn runs.
    var activity: String? {
        guard let run, run.isRunning else { return sending ? "Sending" : nil }
        if run.stopping { return "Stopping" }
        if run.request != nil { return "Waiting for you" }
        if let detail = run.providerDetail, !detail.isEmpty { return detail }
        if run.text.isEmpty && run.steps.isEmpty { return "Waiting for \(run.provider.isEmpty ? "the model" : run.provider)" }
        return nil
    }

    // MARK: Loading

    func load() async {
        guard let id, phase != .loading else { return }
        if !loadedOnce { phase = .loading }
        do {
            let snapshot = try await store.source.openModelChat(id)
            show(snapshot)
            phase = .loaded
            loadedOnce = true
        } catch {
            if !loadedOnce { phase = .failed(error.plainWords) } else { notice = error.plainWords }
        }
    }

    private func show(_ snapshot: ModelChatSnapshot) {
        title = snapshot.title
        var fresh = snapshot.entries
        if !keptSteps.isEmpty, let index = fresh.lastIndex(where: { $0.isAssistant }), fresh[index].steps.isEmpty {
            fresh[index].steps = keptSteps
        }
        entries = fresh
        settings = snapshot.settings
        starred = snapshot.starred
        contextPercent = snapshot.contextPercent
        background = snapshot.background
    }

    // MARK: Sending, queueing, stopping

    /// Send now, or wait in the queue when a reply is running.
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ready = staged.filter { $0.phase == .ready }
        guard !trimmed.isEmpty || !ready.isEmpty else { return }
        if staged.contains(where: { $0.phase == .uploading }) {
            notice = "Wait for the files to finish uploading."
            restoredDraft = text
            return
        }
        staged = []
        if isBusy {
            queue.append(QueuedMessage(id: UUID().uuidString, text: trimmed, attachments: ready))
            return
        }
        start(trimmed, attachments: ready)
    }

    private func start(_ text: String, attachments: [StagedAttachment]) {
        sending = true
        keptSteps = []
        let requestID = UUID().uuidString
        var mine = TranscriptEntry(id: "local-\(requestID)", role: .user, text: text.isEmpty ? "(attachment)" : text, time: Date())
        mine.files = attachments.map(\.file)
        entries.append(mine)
        Task {
            do {
                var chatID = id
                if chatID == nil {
                    let made = try await store.source.createModelChat()
                    id = made
                    chatID = made
                    store.adopt(self, id: made)
                    if title == "New chat" { title = String(text.prefix(48)) }
                    if settings.modelID != nil, !isSample { settings = (try? await store.source.saveSettings(chatID: made, settings: settings)) ?? settings }
                    if let projectID {
                        do {
                            try await store.source.setChatProject(made, projectID: projectID)
                        } catch {
                            notice = "The chat was made, but it could not join the project. " + error.plainWords
                        }
                    }
                }
                guard let chatID else { return }
                _ = try await store.source.sendModel(chatID: chatID, text: text, attachments: attachments, requestID: requestID)
                store.touched()
                // "started" usually arrives first on the stream; if the stream is down, do not stay stuck.
                try? await Task.sleep(for: .seconds(4))
                if sending, run == nil {
                    sending = false
                    await load()
                }
            } catch {
                sending = false
                entries.removeAll { $0.id == mine.id }
                restoredDraft = text
                notice = error.plainWords
            }
        }
    }

    fileprivate func runStarted() {
        sending = false
    }

    fileprivate func runEnded(_ run: RunState) {
        sending = false
        keptSteps = run.steps
        Task {
            await load()
            if phase == .loaded, let id { store.forgetRun(id, turnID: run.turnID) }
            if run.status == .done {
                sendNextQueued()
            } else if !queue.isEmpty {
                queuePaused = true
            }
        }
    }

    fileprivate func followup(_ entry: TranscriptEntry) {
        if !entries.contains(where: { $0.id == entry.id }) { entries.append(entry) }
    }

    func stop() {
        guard let id, let run, run.isRunning else { return }
        Task {
            do {
                try await store.source.stop(chatID: id, turnID: run.turnID)
            } catch {
                notice = error.plainWords
            }
        }
    }

    /// Send the first waiting message now (also un-pauses the queue).
    func sendNextQueued() {
        guard !isBusy, !queue.isEmpty else { return }
        queuePaused = false
        let next = queue.removeFirst()
        start(next.text, attachments: next.attachments)
    }

    func removeQueued(_ item: QueuedMessage) {
        queue.removeAll { $0.id == item.id }
        if queue.isEmpty { queuePaused = false }
    }

    /// Take a waiting message back into the composer.
    func editQueued(_ item: QueuedMessage) {
        removeQueued(item)
        restoredDraft = item.text
    }

    /// Send the last question again, after a reply that failed or was stopped.
    func retryLast() {
        guard !isBusy, let last = entries.last(where: { $0.isUser }) else { return }
        // The failed reply stays in the chat, as on the desktop when a model is switched and the turn continued.
        start(last.text, attachments: [])
    }

    // MARK: Requests

    func answer(_ request: PendingRequest, choice: PendingRequest.Choice) {
        Task {
            do {
                try await store.source.answer(request, choice: choice)
            } catch {
                notice = error.plainWords
            }
        }
    }

    func respond(_ request: PendingRequest, answers: [String: QuestionAnswer], skip: Bool) {
        Task {
            do {
                try await store.source.respond(request, answers: answers, skip: skip)
            } catch {
                notice = error.plainWords
            }
        }
    }

    // MARK: Settings

    func options() async -> [ModelOption] {
        (try? await store.source.modelOptions()) ?? []
    }

    func versions(of modelID: String) async -> [ModelVersion] {
        (try? await store.source.modelVersions(modelID: modelID)) ?? []
    }

    /// Change the model, level or approval. A turn in progress keeps what it started with.
    func apply(_ change: (inout ChatSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        let before = settings
        settings = next
        guard let id else { return }
        if run?.isRunning == true, next.modelID != before.modelID || next.versionID != before.versionID || next.effort != before.effort {
            settings = before
            notice = "Wait for the reply to finish before changing the model."
            return
        }
        Task {
            do {
                settings = try await store.source.saveSettings(chatID: id, settings: next)
            } catch {
                settings = before
                notice = error.plainWords
            }
        }
    }

    func details() async throws -> ChatDetails {
        guard let id else { throw ChatFailure("Details appear after the first message.") }
        return try await store.source.chatDetails(id)
    }

    func summary(refresh: Bool) async throws -> String {
        guard let id else { throw ChatFailure("There is nothing to summarise yet.") }
        return try await store.source.chatSummary(id, refresh: refresh)
    }

    func compact() async -> Bool {
        guard let id else { return false }
        do {
            try await store.source.compactChat(id)
            await load()
            return true
        } catch {
            notice = error.plainWords
            return false
        }
    }

    // MARK: The chat itself

    func rename(_ new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != title else { return }
        let before = title
        title = trimmed
        guard let id else { return }
        Task {
            do {
                try await store.source.renameChat(id, title: trimmed)
                store.touched()
            } catch {
                title = before
                notice = error.plainWords
            }
        }
    }

    func toggleStar() {
        starred.toggle()
        let wanted = starred
        guard let id else { return }
        store.starChanged(id, starred: wanted)
        Task {
            do {
                try await store.source.starChat(id, starred: wanted)
                store.touched()
            } catch {
                starred = !wanted
                store.starChanged(id, starred: !wanted)
                notice = error.plainWords
            }
        }
    }

    /// A new chat that ends at this message (the last one when nil). Answers the new chat's id.
    func fork(at entry: TranscriptEntry?) async -> String? {
        guard let id else { return nil }
        let index = entry?.index ?? entries.last(where: { $0.index != nil })?.index
        guard let index else {
            notice = "There is nothing to fork yet."
            return nil
        }
        do {
            let made = try await store.source.forkChat(id, throughIndex: index)
            store.touched()
            return made
        } catch {
            notice = error.plainWords
            return nil
        }
    }

    func delete() async -> Bool {
        guard let id else {
            deleted = true
            return true
        }
        do {
            try await store.source.deleteChat(id)
            deleted = true
            store.removed(chatID: id)
            return true
        } catch {
            notice = error.plainWords
            return false
        }
    }

    // MARK: Files

    /// Every file in the chat, in order, for the viewer.
    var files: [ChatFile] {
        var seen = Set<String>()
        return transcript.flatMap(\.files).filter { seen.insert($0.id).inserted }
    }

    func fileData(_ file: ChatFile) async throws -> Data {
        if let local = file.local { return local }
        guard let id else { throw ChatFailure("This file is not on the desktop yet.") }
        return try await store.source.fileData(chatID: id, file: file)
    }

    /// Stage a file from the photo library or Files and upload it to the desktop.
    func attach(name: String, data: Data) {
        guard staged.count < 10 else {
            notice = "A message can carry up to 10 files."
            return
        }
        guard data.count <= 25 * 1024 * 1024 else {
            notice = "\(name) is larger than 25 MB, which is the most a chat takes."
            return
        }
        let kind = ChatFile.kind(forName: name)
        let localID = "staged-" + UUID().uuidString
        let file = ChatFile(id: localID, name: name, kind: kind, size: data.count, local: kind == .image ? data : nil)
        staged.append(StagedAttachment(id: localID, file: file, remoteID: nil, phase: .uploading))
        Task {
            do {
                let remote = try await store.source.upload(OutgoingFile(name: name, mimeType: ChatFile.mimeType(forName: name), data: data))
                if let index = staged.firstIndex(where: { $0.id == localID }) {
                    staged[index].remoteID = remote
                    staged[index].phase = .ready
                }
            } catch {
                staged.removeAll { $0.id == localID }
                notice = "\(name) could not be attached. " + error.plainWords
            }
        }
    }

    func removeStaged(_ item: StagedAttachment) {
        staged.removeAll { $0.id == item.id }
    }
}

// MARK: - One bot conversation

/// Everything one bot chat screen shows and does. Made by `ChatStore.botChat(_:)`.
@Observable
final class BotChatState {
    private unowned let store: ChatStore
    let botID: String
    private(set) var bot: Bot
    private(set) var threadID: String?
    private(set) var threads: [BotThreadSummary] = []
    private(set) var entries: [BotEntry] = []
    private(set) var hasOlder = false
    private(set) var loadingOlder = false
    private(set) var phase: ModelChatState.Phase = .idle
    private(set) var queue: [QueuedMessage] = []
    private(set) var queuePaused = false
    private(set) var cardRequests: [PendingRequest] = []
    private(set) var staged: [StagedAttachment] = []
    private(set) var sending = false
    private(set) var modelLine: String?
    /// This conversation's model, read when the model drawer first opens. nil until then.
    private(set) var model: ChatSettings?
    var notice: String?
    var restoredDraft: String?

    @ObservationIgnored private var firstID: String?
    @ObservationIgnored private var leafID: String?
    @ObservationIgnored private var lastID: String?
    @ObservationIgnored private var queueRevision = 0
    @ObservationIgnored private var loadedOnce = false

    init(store: ChatStore, botID: String) {
        self.store = store
        self.botID = botID
        bot = store.bot(botID)
    }

    var isSample: Bool { store.isSample }
    var run: RunState? { threadID.flatMap { store.runs[$0] } }
    var isBusy: Bool { run?.isRunning == true }

    /// Requests waiting on the person: the running turn's own, else the cards the bot left open.
    var requests: [PendingRequest] {
        if let run, run.isRunning, let request = run.request { return [request] }
        return cardRequests
    }

    /// The saved messages, then the reply being written.
    var transcript: [BotEntry] {
        var result = entries
        guard let run else { return result }
        if !run.prompt.isEmpty, run.isRunning, result.last(where: { $0.kind == .mine })?.text != run.prompt {
            result.append(BotEntry(id: "live-mine-\(run.turnID)", kind: .mine, text: run.prompt, time: run.startedAt))
        }
        let text = TranscriptParsing.body(run.text).text
        if !text.isEmpty, result.last(where: { $0.kind == .theirs })?.text != text {
            result.append(BotEntry(id: "live-\(run.turnID)", kind: .theirs, text: text, time: run.startedAt))
        }
        return result
    }

    /// "Kip is reading your notes": what the bot is doing right now, or nil.
    var statusLine: String? {
        guard let run, run.isRunning else { return sending ? "Sending" : nil }
        if run.stopping { return "Stopping" }
        if run.request != nil { return "\(bot.name) is waiting for you" }
        if let step = run.steps.last(where: { !$0.done }) {
            let words = step.text.prefix(1).lowercased() + String(step.text.dropFirst())
            return "\(bot.name) is \(words)"
        }
        return run.text.isEmpty ? "\(bot.name) is thinking" : nil
    }

    fileprivate func botChanged() {
        bot = store.bot(botID)
    }

    // MARK: Loading

    func load(thread wanted: String? = nil) async {
        guard phase != .loading else { return }
        if !loadedOnce || wanted != nil { phase = .loading }
        do {
            let snapshot = try await store.source.openBotChat(botID: botID, threadID: wanted ?? threadID)
            threadID = snapshot.threadID
            store.own(thread: snapshot.threadID, botID: botID)
            threads = snapshot.threads
            entries = snapshot.entries
            hasOlder = snapshot.hasOlder
            firstID = snapshot.firstID
            leafID = snapshot.leafID
            lastID = snapshot.lastID
            queue = snapshot.queue
            queueRevision = snapshot.queueRevision
            queuePaused = snapshot.queuePaused
            cardRequests = snapshot.requests
            modelLine = snapshot.modelLine
            bot = store.bot(botID)
            phase = .loaded
            loadedOnce = true
            markRead()
        } catch {
            if !loadedOnce { phase = .failed(error.plainWords) } else { notice = error.plainWords }
        }
    }

    func loadOlder() async {
        guard let threadID, let firstID, hasOlder, !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await store.source.olderBotMessages(threadID: threadID, before: firstID)
            let known = Set(entries.map(\.id))
            entries.insert(contentsOf: page.entries.filter { !known.contains($0.id) }, at: 0)
            hasOlder = page.hasOlder
            self.firstID = page.firstID ?? firstID
        } catch {
            notice = error.plainWords
        }
    }

    fileprivate func refreshNewest() {
        guard let threadID else { return }
        Task {
            guard let page = try? await store.source.newestBotMessages(threadID: threadID) else { return }
            merge(page)
        }
    }

    /// Put the newest page in place of the same stretch of messages, keeping older pages already loaded.
    private func merge(_ page: BotMessagePage) {
        if let first = page.entries.first, let cut = entries.firstIndex(where: { $0.id == first.id }) {
            entries = Array(entries[..<cut]) + page.entries
        } else if !page.entries.isEmpty || !hasOlder {
            entries = page.entries
            hasOlder = page.hasOlder
            firstID = page.firstID
        }
        if let leaf = page.leafID { leafID = leaf }
        lastID = page.lastID ?? lastID
    }

    private func markRead() {
        guard let threadID else { return }
        let newest = lastID
        Task { try? await store.source.markRead(threadID: threadID, messageID: newest) }
    }

    // MARK: Sending, the queue, stopping

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ready = staged.filter { $0.phase == .ready }
        guard !trimmed.isEmpty || !ready.isEmpty, let threadID else { return }
        if staged.contains(where: { $0.phase == .uploading }) {
            notice = "Wait for the files to finish uploading."
            restoredDraft = text
            return
        }
        staged = []
        let sendID = UUID().uuidString
        let wasBusy = isBusy
        let localID = "local-" + sendID
        if wasBusy {
            queue.append(QueuedMessage(id: localID, text: trimmed, attachments: ready))
        } else {
            sending = true
            entries.removeAll { $0.kind == .status }
            entries.append(BotEntry(id: localID, kind: .mine, text: trimmed, time: Date(), files: ready.map(\.file)))
        }
        Task {
            do {
                let outcome = try await store.source.sendBot(threadID: threadID, text: trimmed, attachments: ready, sendID: sendID, leafID: leafID)
                if let leaf = outcome.leafID { leafID = leaf }
                sending = false
                if outcome.queued && !wasBusy {
                    // The bot was busy after all (another conversation, a routine): it waits in the queue.
                    entries.removeAll { $0.id == localID }
                    if !queue.contains(where: { $0.text == trimmed }) { queue.append(QueuedMessage(id: localID, text: trimmed, attachments: ready)) }
                }
                store.touched()
            } catch {
                sending = false
                entries.removeAll { $0.id == localID }
                queue.removeAll { $0.id == localID }
                restoredDraft = text
                notice = error.plainWords
            }
        }
    }

    fileprivate func queueChanged(_ items: [QueuedMessage], revision: Int, paused: Bool) {
        queue = items
        queueRevision = revision
        queuePaused = paused
    }

    fileprivate func requestChanged(_ request: PendingRequest, open: Bool) {
        cardRequests.removeAll { $0.id == request.id }
        if open { cardRequests.append(request) }
    }

    fileprivate func runEnded(_ run: RunState) {
        sending = false
        guard let threadID else { return }
        Task {
            if let page = try? await store.source.newestBotMessages(threadID: threadID) {
                merge(page)
                store.forgetRun(threadID, turnID: run.turnID)
                markRead()
            }
            if run.status == .failed, let error = run.error { notice = error }
        }
    }

    /// Stop the reply that is running.
    func interrupt() {
        guard let threadID, let run, run.isRunning else { return }
        Task {
            do {
                try await store.source.interrupt(threadID: threadID, turnID: run.turnID)
            } catch {
                notice = error.plainWords
            }
        }
    }

    /// Send a waiting message now: the running reply stops first.
    func steer(_ item: QueuedMessage) {
        guard let threadID else { return }
        let turnID = run?.isRunning == true ? run?.turnID : nil
        Task {
            do {
                try await store.source.steer(threadID: threadID, queueID: item.id, turnID: turnID, revision: queueRevision)
            } catch {
                notice = error.plainWords
            }
        }
    }

    func resumeQueue() {
        guard let threadID else { return }
        Task {
            do {
                try await store.source.resumeQueue(threadID: threadID)
                queuePaused = false
            } catch {
                notice = error.plainWords
            }
        }
    }

    func removeQueued(_ item: QueuedMessage) {
        guard let threadID else { return }
        queue.removeAll { $0.id == item.id }
        Task {
            do {
                try await store.source.removeQueued(threadID: threadID, queueID: item.id)
            } catch {
                notice = error.plainWords
            }
        }
    }

    func editQueued(_ item: QueuedMessage) {
        guard let threadID else { return }
        queue.removeAll { $0.id == item.id }
        Task {
            do {
                let text = try await store.source.editQueued(threadID: threadID, queueID: item.id)
                restoredDraft = text.isEmpty ? item.text : text
            } catch {
                notice = error.plainWords
            }
        }
    }

    // MARK: Requests

    func answer(_ request: PendingRequest, choice: PendingRequest.Choice) {
        Task {
            do {
                try await store.source.answer(request, choice: choice)
                cardRequests.removeAll { $0.id == request.id }
            } catch {
                notice = error.plainWords
            }
        }
    }

    func respond(_ request: PendingRequest, answers: [String: QuestionAnswer], skip: Bool) {
        Task {
            do {
                try await store.source.respond(request, answers: answers, skip: skip)
                cardRequests.removeAll { $0.id == request.id }
            } catch {
                notice = error.plainWords
            }
        }
    }

    // MARK: Model

    func options() async -> [ModelOption] {
        (try? await store.source.modelOptions()) ?? []
    }

    func versions(of modelID: String) async -> [ModelVersion] {
        (try? await store.source.modelVersions(modelID: modelID)) ?? []
    }

    func loadModel() async {
        guard let threadID else { return }
        do {
            model = try await store.source.botModel(threadID: threadID)
        } catch {
            notice = error.plainWords
        }
    }

    /// Choose this conversation's model. A nil `modelID` follows the bot's own model again.
    func applyModel(_ change: (inout ChatSettings) -> Void) {
        guard let threadID, var next = model else { return }
        change(&next)
        guard next != model else { return }
        if isBusy {
            notice = "Wait for the reply to finish before changing the model."
            return
        }
        let before = model
        model = next
        Task {
            do {
                let saved = try await store.source.saveBotModel(threadID: threadID, settings: next)
                model = saved
                modelLine = saved.versionName ?? saved.modelName
            } catch {
                model = before
                notice = error.plainWords
            }
        }
    }

    // MARK: Files

    var files: [ChatFile] {
        var seen = Set<String>()
        return transcript.flatMap(\.files).filter { seen.insert($0.id).inserted }
    }

    func fileData(_ file: ChatFile) async throws -> Data {
        if let local = file.local { return local }
        guard let threadID else { throw ChatFailure("This file is not on the desktop yet.") }
        return try await store.source.fileData(chatID: threadID, file: file)
    }

    func attach(name: String, data: Data) {
        guard staged.count < 10 else {
            notice = "A message can carry up to 10 files."
            return
        }
        guard data.count <= 25 * 1024 * 1024 else {
            notice = "\(name) is larger than 25 MB, which is the most a chat takes."
            return
        }
        let kind = ChatFile.kind(forName: name)
        let localID = "staged-" + UUID().uuidString
        let file = ChatFile(id: localID, name: name, kind: kind, size: data.count, local: kind == .image ? data : nil)
        staged.append(StagedAttachment(id: localID, file: file, remoteID: nil, phase: .uploading))
        Task {
            do {
                let remote = try await store.source.upload(OutgoingFile(name: name, mimeType: ChatFile.mimeType(forName: name), data: data))
                if let index = staged.firstIndex(where: { $0.id == localID }) {
                    staged[index].remoteID = remote
                    staged[index].phase = .ready
                }
            } catch {
                staged.removeAll { $0.id == localID }
                notice = "\(name) could not be attached. " + error.plainWords
            }
        }
    }

    func removeStaged(_ item: StagedAttachment) {
        staged.removeAll { $0.id == item.id }
    }
}
