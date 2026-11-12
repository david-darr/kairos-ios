import Foundation

/// A made-up desktop, so every screen works before one is paired ("Look around first").
/// It behaves like the real one: replies stream in, turns can be stopped, messages queue,
/// requests can be answered. Nothing here is real, and nothing leaves the phone.
final class SampleBackend: ChatBackend {
    let isSample = true
    var onEvent: ((StoreEvent) -> Void)?

    private struct Chat {
        var title: String
        var entries: [TranscriptEntry]
        var settings = SampleBackend.settings
        var starred = false
        var background: [BackgroundItem] = []
    }

    private struct BotThread {
        var entries: [BotEntry]
        var requests: [PendingRequest] = []
        var queue: [QueuedMessage] = []
        var queueRevision = 0
    }

    private var chats: [String: Chat] = [:]
    private var conversations = SampleData.conversations
    private var threads: [String: BotThread] = [:]
    private var runs: [String: RunState] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var announced = false
    private var made = 0

    static let reply = "This is sample data. Connect your desktop to get a real answer."
    static let botReply = "This is sample data. Connect your desktop and I will answer for real."

    static let settings = ChatSettings(
        modelID: "ep-claude", modelName: "Claude", source: "Claude subscription", versionID: "claude-opus", versionName: "Claude Opus",
        effort: "high", efforts: ["low", "medium", "high", "xhigh", "max"], fast: false,
        approval: "Ask first", approvals: ["Ask first", "Edits", "Auto", "Full access"])

    /// The connections, as the desktop's model choices list them.
    static let options = [
        ModelOption(id: "ep-claude", name: "Claude", source: "Claude subscription"),
        ModelOption(id: "ep-codex", name: "Codex", source: "Codex"),
        ModelOption(id: "ep-qwen", name: "Qwen local", source: "This PC", takesImages: false),
    ]

    /// Each connection's own models, as the desktop's catalog lists them. A local model has none.
    static let catalogs: [String: [ModelVersion]] = [
        "ep-claude": [
            ModelVersion(id: "claude-opus", name: "Claude Opus", efforts: ["low", "medium", "high", "xhigh", "max"]),
            ModelVersion(id: "claude-sonnet", name: "Claude Sonnet", efforts: ["low", "medium", "high"]),
            ModelVersion(id: "claude-haiku", name: "Claude Haiku", efforts: []),
        ],
        "ep-codex": [
            ModelVersion(id: "gpt-6.1-sol", name: "GPT-6.1 Sol", efforts: ["low", "medium", "high", "xhigh"]),
            ModelVersion(id: "gpt-6.1-sol-mini", name: "GPT-6.1 Sol mini", efforts: ["low", "medium", "high"]),
        ],
    ]

    static let projects = [
        ChatProject(id: "p-shop", name: "Bike shop", instructions: "Keep prices in dollars. The shop opens in March.", documentCount: 3),
        ChatProject(id: "p-home", name: "Home and garden", instructions: "Small budget. Do it ourselves where we can.", documentCount: 1),
    ]

    private var projects = SampleBackend.projects
    private var pinnedBots = ["producer", "scout"]
    private var botModels: [String: ChatSettings] = [:]
    private var waitingProjects: [String: String] = [:]

    init() {
        seedChats()
        let seeded = ["c-bike": "p-shop", "c-zip": "p-shop", "c-garden": "p-home"]
        for index in conversations.indices { conversations[index].projectID = seeded[conversations[index].id] }
    }

    // MARK: Seeds

    private func seedChats() {
        chats["c-zip"] = Chat(title: "Check zip tie availability", entries: [
            TranscriptEntry(id: "zip-1", role: .user, text: "Find 8 inch black zip ties in stock near me today.", index: 0),
        ])
        runs["c-zip"] = RunState(
            turnID: "sample-zip", title: "Check zip tie availability",
            prompt: "Find 8 inch black zip ties in stock near me today.",
            text: "Two stores have them in stock within 5 miles. One has a 100 pack for $6.98, ready for pickup in 2 hours.",
            steps: SampleData.zipSteps.enumerated().map { StepLine(id: "zip-step-\($0.offset)", text: $0.element.text, done: $0.element.done) },
            startedAt: Date().addingTimeInterval(-120), provider: "Claude")

        var bike = Chat(title: "Bike shop launch", entries: [
            TranscriptEntry(id: "bike-1", role: .user, text: "Find three rivals' prices, design a booking page, and write a one-page plan.", index: 0),
            TranscriptEntry(id: "bike-2", role: .browser(site: "cyclerepair.example"), text: "Browsing"),
            TranscriptEntry(id: "bike-3", role: .backgroundTask(progress: 0.58), text: "Writing the one-page plan"),
            TranscriptEntry(
                id: "bike-4", role: .assistant, text: "I found three rival price lists and made the booking page. Sending both.",
                files: SampleData.documents.map(ChatFile.sample),
                sources: [SourceLink(site: "cyclerepair.example", title: "Tune-up prices, 2026", url: "https://cyclerepair.example/prices")],
                index: 1),
        ])
        bike.background = [
            BackgroundItem(id: "bike-browser", kind: "computer", label: "Browsing cyclerepair.example", status: "running",
                           activity: "Reading the price list", startedAt: Date().addingTimeInterval(-95), endedAt: nil),
            BackgroundItem(id: "bike-plan", kind: "subagent", label: "Writing the one-page plan", status: "running",
                           activity: "Drafting section 2", startedAt: Date().addingTimeInterval(-40), endedAt: nil),
        ]
        chats["c-bike"] = bike

        chats["c-inbox"] = pair("Summarise my inbox", "Summarise my inbox from this morning.",
                                "Four need a reply. One is from the landlord, about the lease renewal, and wants an answer by Friday. The other three are newsletters you can skip.")
        chats["c-trip"] = pair("Weekend trip plan", "Plan a weekend trip within four hours of home.",
                               "Two routes, both under four hours.\n\n1. **The lake loop**: 3 h 10 min, a short hike and a swim.\n2. **The old rail trail**: 3 h 40 min, flat, good for bikes.")
        chats["c-garden"] = pair("Raised bed layout", "Lay out a 4 by 8 raised bed for tomatoes and herbs.",
                                 "A 4 by 8 plan with spacing for tomatoes.\n\n- Tomatoes along the north edge, 24 inches apart\n- Basil between them\n- Thyme and chives at the south corners")

        // Two chats that exist to show a request waiting on the person.
        chats["c-approve"] = Chat(title: "Rebuild the shop site", entries: [
            TranscriptEntry(id: "approve-1", role: .user, text: "Rebuild the shop site and check that it still loads.", index: 0),
        ])
        runs["c-approve"] = RunState(
            turnID: "sample-approve", title: "Rebuild the shop site", prompt: "Rebuild the shop site and check that it still loads.",
            text: "I updated the image sizes. Next I need to run the build.",
            request: PendingRequest(
                id: "sample-approval", kind: .approval, channel: .sample, title: "Run a command",
                detail: "Kairos wants to run a command in the shop-site folder.", target: "npm run build",
                choices: [
                    PendingRequest.Choice(id: "once", label: "Allow once", allows: true),
                    PendingRequest.Choice(id: "session", label: "Allow for this chat", allows: true, scope: "session"),
                    PendingRequest.Choice(id: "reject", label: "Reject", allows: false),
                ],
                expiresAt: Date().addingTimeInterval(110)),
            steps: [StepLine(id: "approve-step-0", text: "Resized 14 images", done: true)],
            startedAt: Date().addingTimeInterval(-30), provider: "Claude")

        chats["c-question"] = Chat(title: "Plan the open day", entries: [
            TranscriptEntry(id: "question-1", role: .user, text: "Plan the shop's open day.", index: 0),
        ])
        runs["c-question"] = RunState(
            turnID: "sample-question", title: "Plan the open day", prompt: "Plan the shop's open day.",
            text: "I can plan this two ways. One thing first.",
            request: PendingRequest(
                id: "sample-question", kind: .question, channel: .sample, title: "Waiting for your answer", detail: "", target: nil,
                questions: [PendingRequest.Question(
                    id: "Which day works best?", text: "Which day works best?", header: "Day", multiple: false,
                    options: [
                        PendingRequest.Option(label: "Saturday", detail: "Busiest day, more walk-ins"),
                        PendingRequest.Option(label: "Sunday", detail: "Quieter, easier to staff"),
                    ])],
                expiresAt: Date().addingTimeInterval(1500)),
            startedAt: Date().addingTimeInterval(-20), provider: "Claude")
    }

    private func pair(_ title: String, _ question: String, _ answer: String) -> Chat {
        Chat(title: title, entries: [
            TranscriptEntry(id: "\(title)-1", role: .user, text: question, index: 0),
            TranscriptEntry(id: "\(title)-2", role: .assistant, text: answer, index: 1),
        ])
    }

    private func thread(_ botID: String) -> BotThread {
        if let thread = threads[botID] { return thread }
        let bot = SampleData.bot(botID)
        var entries: [BotEntry] = []
        for (index, message) in SampleData.thread(for: bot).enumerated() {
            let id = "\(botID)-\(index)"
            switch message.kind {
            case .mine(let text): entries.append(BotEntry(id: id, kind: .mine, text: text))
            case .theirs(let text): entries.append(BotEntry(id: id, kind: .theirs, text: text))
            case .status(let text): entries.append(BotEntry(id: id, kind: .status, text: text))
            case .receipt(let text): entries.append(BotEntry(id: id, kind: .receipt, text: text))
            }
        }
        var thread = BotThread(entries: entries)
        if botID == "scout" {
            thread.requests = [PendingRequest(
                id: "sample-scout-topic", kind: .question, channel: .sample, title: "Scout is waiting for your answer", detail: "", target: nil,
                questions: [PendingRequest.Question(
                    id: "Which topic should I start with?", text: "Which topic should I start with?", header: "Topic", multiple: false,
                    options: [
                        PendingRequest.Option(label: "Repair cafes", detail: "Where neighbours fix bikes together"),
                        PendingRequest.Option(label: "E-bike batteries", detail: "How long they last and what they cost"),
                        PendingRequest.Option(label: "Bike lanes in small towns", detail: ""),
                    ])])]
        }
        threads[botID] = thread
        return thread
    }

    private func threadID(_ botID: String) -> String { "t-" + botID }
    private func botID(ofThread id: String) -> String { String(id.dropFirst(2)) }

    // MARK: Home

    func loadHome() async throws -> HomeData {
        announce()
        var list = conversations
        for index in list.indices where list[index].kind == .model {
            list[index].starred = chats[list[index].id]?.starred ?? false
        }
        // Starred chats first, then the list's own newest-first order.
        list = list.filter(\.starred) + list.filter { !$0.starred }
        return HomeData(bots: SampleData.allBots, pinned: pinnedBots, conversations: list, projects: projects)
    }

    func pinBot(_ id: String, pinned: Bool) async throws {
        pinnedBots.removeAll { $0 == id }
        if pinned { pinnedBots.append(id) }
    }

    func setChatProject(_ id: String, projectID: String?) async throws {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].projectID = projectID
        } else {
            // A brand new chat joins the list at its first message.
            waitingProjects[id] = projectID
        }
    }

    func createProject(name: String, instructions: String) async throws -> ChatProject {
        made += 1
        let project = ChatProject(id: "p-new-\(made)", name: name, instructions: instructions)
        projects.append(project)
        projects.sort { $0.name.lowercased() < $1.name.lowercased() }
        return project
    }

    /// The first read of anything tells the store what is running, as the live stream does when it opens.
    private func announce() {
        guard !announced else { return }
        announced = true
        onEvent?(.snapshot(runs))
    }

    func pollHome() async throws -> HomeData? { nil }

    func loadGlance() async throws -> Glance {
        Glance(usage: SampleData.usage.map { GlanceUsage(provider: $0.provider, percent: $0.percent) },
               nextEvent: SampleData.nextEvent, needsYou: 1, running: 2)
    }

    // MARK: Model chats

    func openModelChat(_ id: String) async throws -> ModelChatSnapshot {
        announce()
        guard let chat = chats[id] else { throw ChatFailure("That chat is not in the sample data.") }
        if let index = conversations.firstIndex(where: { $0.id == id }) { conversations[index].unread = false }
        return ModelChatSnapshot(title: chat.title, entries: chat.entries, settings: chat.settings, starred: chat.starred,
                                 contextPercent: 15.8, background: chat.background)
    }

    func createModelChat() async throws -> String {
        made += 1
        let id = "c-new-\(made)"
        chats[id] = Chat(title: "New chat", entries: [])
        return id
    }

    func sendModel(chatID: String, text: String, attachments: [StagedAttachment], requestID: String) async throws -> String? {
        guard var chat = chats[chatID] else { throw ChatFailure("That chat is not in the sample data.") }
        if runs[chatID]?.isRunning == true { throw ChatFailure("A reply is still running. Wait for it, or press Stop.") }
        var entry = TranscriptEntry(id: "sent-\(requestID)", role: .user, text: text, time: Date())
        entry.files = attachments.map(\.file)
        entry.index = chat.entries.filter { $0.isUser || $0.isAssistant }.count
        chat.entries.append(entry)
        if chat.title == "New chat" {
            chat.title = String(text.prefix(40))
            conversations.insert(Conversation(id: chatID, kind: .model, title: chat.title, preview: "Working on it", time: "now", working: true,
                                              projectID: waitingProjects[chatID]), at: 0)
        }
        chats[chatID] = chat
        let turnID = "sample-" + requestID
        let run = RunState(turnID: turnID, title: chat.title, prompt: text, startedAt: Date(), provider: "Claude")
        runs[chatID] = run
        onEvent?(.started(chatID: chatID, run: run))
        play(chatID: chatID, turnID: turnID, steps: ["Reading your message"], reply: SampleBackend.reply, delay: 0.5)
        return turnID
    }

    /// Stream a reply the way the desktop does: a step, then the words, then the end.
    private func play(chatID: String, turnID: String, steps: [String], reply: String, delay: Double) {
        tasks[chatID]?.cancel()
        tasks[chatID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            for (index, step) in steps.enumerated() {
                guard !Task.isCancelled, let self else { return }
                let id = "\(turnID)-step-\(index)"
                self.emitStep(chatID: chatID, turnID: turnID, id: id, text: step, finished: false)
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                self.emitStep(chatID: chatID, turnID: turnID, id: id, text: step, finished: true)
            }
            var first = true
            for word in reply.split(separator: " ") {
                try? await Task.sleep(for: .seconds(0.07))
                guard !Task.isCancelled, let self else { return }
                let piece = (first ? "" : " ") + String(word)
                first = false
                self.runs[chatID]?.text += piece
                self.onEvent?(.chunk(chatID: chatID, turnID: turnID, text: piece))
            }
            try? await Task.sleep(for: .seconds(0.25))
            guard !Task.isCancelled, let self else { return }
            self.finish(chatID: chatID, status: .done)
        }
    }

    private func emitStep(chatID: String, turnID: String, id: String, text: String, finished: Bool) {
        if var run = runs[chatID] {
            TranscriptParsing.apply(id: id, text: text, finished: finished, failed: false, to: &run.steps)
            runs[chatID] = run
        }
        onEvent?(.step(chatID: chatID, turnID: turnID, id: id, text: text, finished: finished, failed: false))
    }

    /// End the turn and save what it wrote, as the desktop would.
    private func finish(chatID: String, status: RunState.Status) {
        guard var run = runs[chatID], run.isRunning else { return }
        tasks[chatID]?.cancel()
        tasks[chatID] = nil
        run.status = status
        run.request = nil
        run.stopping = false
        runs[chatID] = run
        if chatID.hasPrefix("t-") {
            saveBotReply(threadID: chatID, run: run)
        } else if var chat = chats[chatID] {
            var entry = TranscriptEntry(id: "reply-\(run.turnID)", role: .assistant, text: run.text, time: Date())
            entry.index = chat.entries.filter { $0.isUser || $0.isAssistant }.count
            if status == .stopped {
                entry.failure = run.text.isEmpty ? "Stopped before a response started." : "Stopped. The partial reply was saved."
            }
            chat.entries.append(entry)
            chats[chatID] = chat
            if let index = conversations.firstIndex(where: { $0.id == chatID }) {
                conversations[index].working = false
                conversations[index].preview = ChatFormat.oneLine(run.text.isEmpty ? "Stopped" : run.text)
            }
        }
        var change = RunChange()
        change.status = status
        change.stopping = false
        change.requestChanged = true
        onEvent?(.changed(chatID: chatID, turnID: run.turnID, change: change))
        if chatID.hasPrefix("t-"), status == .done { sendNextQueued(threadID: chatID) }
    }

    func stop(chatID: String, turnID: String?) async throws {
        guard let run = runs[chatID], run.isRunning, turnID == nil || turnID == run.turnID else { return }
        var change = RunChange()
        change.stopping = true
        onEvent?(.changed(chatID: chatID, turnID: run.turnID, change: change))
        try? await Task.sleep(for: .seconds(0.3))
        finish(chatID: chatID, status: .stopped)
    }

    func renameChat(_ id: String, title: String) async throws {
        chats[id]?.title = title
        if let index = conversations.firstIndex(where: { $0.id == id }) { conversations[index].title = title }
    }

    func starChat(_ id: String, starred: Bool) async throws {
        chats[id]?.starred = starred
    }

    func deleteChat(_ id: String) async throws {
        tasks[id]?.cancel()
        runs[id] = nil
        chats[id] = nil
        conversations.removeAll { $0.id == id }
    }

    func forkChat(_ id: String, throughIndex: Int) async throws -> String {
        guard let chat = chats[id] else { throw ChatFailure("That chat is not in the sample data.") }
        made += 1
        let forkID = "c-fork-\(made)"
        let kept = chat.entries.filter { ($0.index ?? Int.max) <= throughIndex }
        chats[forkID] = Chat(title: chat.title + " (fork)", entries: kept, settings: chat.settings)
        conversations.insert(Conversation(id: forkID, kind: .model, title: chat.title + " (fork)",
                                          preview: ChatFormat.oneLine(kept.last?.text ?? ""), time: "now"), at: 0)
        return forkID
    }

    func compactChat(_ id: String) async throws {
        try? await Task.sleep(for: .seconds(0.6))
    }

    func chatDetails(_ id: String) async throws -> ChatDetails {
        var details = ChatDetails()
        details.usedTokens = 79_000
        details.windowTokens = 500_000
        details.percent = 15.8
        details.windowEstimated = true
        details.parts = [
            ChatDetails.Part(id: "system", label: "Instructions", tokens: 10_000, estimated: true),
            ChatDetails.Part(id: "tools", label: "Tools", tokens: 15_000, estimated: true),
            ChatDetails.Part(id: "files", label: "Files", tokens: 5_000, estimated: true),
            ChatDetails.Part(id: "messages", label: "Messages", tokens: 49_000, estimated: true),
        ]
        details.model = "Claude Opus"
        details.provider = "Claude subscription"
        details.rows = [
            .init(id: "Model", value: "Claude Opus"), .init(id: "Provider", value: "Claude subscription"),
            .init(id: "Context window", value: "500K (estimated)"), .init(id: "Calls", value: "5"), .init(id: "Turns", value: "3"),
            .init(id: "Input", value: "182K"), .init(id: "Output", value: "6.4K"), .init(id: "Cache read", value: "150K"),
            .init(id: "Cache write", value: "21K"), .init(id: "Cache hit", value: "82%"), .init(id: "Tool calls", value: "7"),
            .init(id: "Compactions", value: "0"), .init(id: "First output", value: "0.6 s"), .init(id: "Speed", value: "48 tok/s"),
            .init(id: "Cost", value: "included (subscription)"),
        ]
        details.note = "Sample figures. Connect your desktop to see this chat's own."
        return details
    }

    func chatSummary(_ id: String, refresh: Bool) async throws -> String {
        try? await Task.sleep(for: .seconds(0.5))
        guard let chat = chats[id], let last = chat.entries.last(where: { $0.isAssistant }) else {
            throw ChatFailure("There is nothing to summarise yet.")
        }
        return "\(chat.title): " + ChatFormat.oneLine(last.text)
    }

    func chatFiles(_ id: String) async throws -> [ChatFile] {
        (chats[id]?.entries ?? []).flatMap(\.files)
    }

    // MARK: Model, effort, approval

    func modelOptions() async throws -> [ModelOption] { SampleBackend.options }

    func modelVersions(modelID: String) async throws -> [ModelVersion] {
        SampleBackend.catalogs[modelID] ?? []
    }

    func saveSettings(chatID: String, settings: ChatSettings) async throws -> ChatSettings {
        chats[chatID]?.settings = settings
        return settings
    }

    func botModel(threadID: String) async throws -> ChatSettings {
        if let saved = botModels[threadID] { return saved }
        var settings = SampleBackend.settings
        settings.versionID = "claude-sonnet"
        settings.versionName = "Claude Sonnet"
        settings.efforts = ["low", "medium", "high"]
        settings.effort = nil
        settings.approvals = []
        settings.followsBot = true
        return settings
    }

    func saveBotModel(threadID: String, settings: ChatSettings) async throws -> ChatSettings {
        guard settings.modelID != nil else {
            botModels[threadID] = nil
            return try await botModel(threadID: threadID)
        }
        var saved = settings
        saved.followsBot = false
        botModels[threadID] = saved
        return saved
    }

    // MARK: Approvals and questions

    func answer(_ request: PendingRequest, choice: PendingRequest.Choice) async throws {
        guard let chatID = runs.first(where: { $0.value.request?.id == request.id })?.key, let run = runs[chatID] else { return }
        runs[chatID]?.request = nil
        var change = RunChange()
        change.requestChanged = true
        onEvent?(.changed(chatID: chatID, turnID: run.turnID, change: change))
        let rest = choice.allows ? " The build ran and the site loads." : " I left the build alone, as you asked."
        play(chatID: chatID, turnID: run.turnID, steps: choice.allows ? ["Running the build"] : [], reply: rest + " " + SampleBackend.reply, delay: 0.3)
    }

    func respond(_ request: PendingRequest, answers: [String: QuestionAnswer], skip: Bool) async throws {
        let said = request.questions.compactMap { question -> String? in
            guard let answer = answers[question.id], !answer.isEmpty else { return nil }
            return (answer.picked.sorted() + [answer.typed.trimmingCharacters(in: .whitespacesAndNewlines)]).filter { !$0.isEmpty }.joined(separator: ", ")
        }.joined(separator: "; ")

        if let botID = threads.first(where: { $0.value.requests.contains { $0.id == request.id } })?.key {
            threads[botID]?.requests.removeAll { $0.id == request.id }
            onEvent?(.botRequest(threadID: threadID(botID), request: request, open: false))
            if !skip, !said.isEmpty {
                _ = try await sendBot(threadID: threadID(botID), text: said, attachments: [], sendID: UUID().uuidString, leafID: nil,
                                      reply: "Starting with \(said). I will text you when the outline is ready.")
            }
            return
        }
        guard let chatID = runs.first(where: { $0.value.request?.id == request.id })?.key, let run = runs[chatID] else { return }
        runs[chatID]?.request = nil
        var change = RunChange()
        change.requestChanged = true
        onEvent?(.changed(chatID: chatID, turnID: run.turnID, change: change))
        let rest = skip || said.isEmpty ? " I will pick a day myself." : " \(said) it is."
        play(chatID: chatID, turnID: run.turnID, steps: [], reply: rest + " " + SampleBackend.reply, delay: 0.3)
    }

    // MARK: Files

    func upload(_ file: OutgoingFile) async throws -> String {
        try? await Task.sleep(for: .seconds(0.4))
        return "sample-" + UUID().uuidString
    }

    func fileData(chatID: String, file: ChatFile) async throws -> Data {
        if let local = file.local { return local }
        throw ChatFailure("Sample files are drawings. Connect your desktop to open real ones.")
    }

    // MARK: Bot conversations

    func openBotChat(botID: String, threadID: String?) async throws -> BotChatSnapshot {
        announce()
        let thread = self.thread(botID)
        if let index = conversations.firstIndex(where: { $0.kind == .bot(botID) }) { conversations[index].unread = false }
        let bot = SampleData.bot(botID)
        return BotChatSnapshot(
            threadID: self.threadID(botID),
            threads: [BotThreadSummary(id: self.threadID(botID), title: "Main conversation", preview: ChatFormat.oneLine(thread.entries.last?.text ?? ""),
                                       time: "now", unread: false, working: false, isMain: true)],
            entries: thread.entries, hasOlder: false, firstID: thread.entries.first?.id, leafID: thread.entries.last?.id,
            queue: thread.queue, queueRevision: thread.queueRevision, queuePaused: false, requests: thread.requests,
            modelLine: bot.model, lastID: thread.entries.last?.id)
    }

    func olderBotMessages(threadID: String, before: String) async throws -> BotMessagePage {
        BotMessagePage(entries: [], hasOlder: false, firstID: nil, leafID: nil, lastID: nil)
    }

    func newestBotMessages(threadID: String) async throws -> BotMessagePage {
        let thread = self.thread(botID(ofThread: threadID))
        return BotMessagePage(entries: thread.entries, hasOlder: false, firstID: thread.entries.first?.id,
                              leafID: thread.entries.last?.id, lastID: thread.entries.last?.id)
    }

    func sendBot(threadID: String, text: String, attachments: [StagedAttachment], sendID: String, leafID: String?) async throws -> BotSendOutcome {
        try await sendBot(threadID: threadID, text: text, attachments: attachments, sendID: sendID, leafID: leafID, reply: SampleBackend.botReply)
    }

    private func sendBot(threadID: String, text: String, attachments: [StagedAttachment], sendID: String, leafID: String?, reply: String) async throws -> BotSendOutcome {
        let botID = self.botID(ofThread: threadID)
        var thread = self.thread(botID)
        if runs[threadID]?.isRunning == true {
            thread.queue.append(QueuedMessage(id: "q-" + sendID, text: text, attachments: attachments))
            thread.queueRevision += 1
            threads[botID] = thread
            onEvent?(.botQueue(threadID: threadID, items: thread.queue, revision: thread.queueRevision, paused: false))
            return BotSendOutcome(queued: true, turnID: nil, leafID: thread.entries.last?.id)
        }
        // A reply that follows the person's message replaces any old "is working" chip.
        thread.entries.removeAll { $0.kind == .status }
        thread.entries.append(BotEntry(id: "sent-" + sendID, kind: .mine, text: text, time: Date(), files: attachments.map(\.file)))
        threads[botID] = thread
        let turnID = "sample-" + sendID
        let run = RunState(turnID: turnID, title: SampleData.bot(botID).name, prompt: text, startedAt: Date(), provider: "Claude")
        runs[threadID] = run
        onEvent?(.started(chatID: threadID, run: run))
        play(chatID: threadID, turnID: turnID, steps: ["thinking"], reply: reply, delay: 0.5)
        return BotSendOutcome(queued: false, turnID: turnID, leafID: thread.entries.last?.id)
    }

    private func saveBotReply(threadID: String, run: RunState) {
        let botID = self.botID(ofThread: threadID)
        var thread = self.thread(botID)
        if !run.text.isEmpty {
            thread.entries.append(BotEntry(id: "reply-" + run.turnID, kind: .theirs, text: run.text, time: Date()))
        }
        if run.status == .stopped {
            thread.entries.append(BotEntry(id: "stopped-" + run.turnID, kind: .note, text: "Stopped"))
        }
        threads[botID] = thread
    }

    private func sendNextQueued(threadID: String) {
        let botID = self.botID(ofThread: threadID)
        guard var thread = threads[botID], !thread.queue.isEmpty else { return }
        let next = thread.queue.removeFirst()
        thread.queueRevision += 1
        threads[botID] = thread
        onEvent?(.botQueue(threadID: threadID, items: thread.queue, revision: thread.queueRevision, paused: false))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.4))
            _ = try? await self?.sendBot(threadID: threadID, text: next.text, attachments: next.attachments, sendID: UUID().uuidString, leafID: nil)
        }
    }

    func editQueued(threadID: String, queueID: String) async throws -> String {
        let botID = self.botID(ofThread: threadID)
        guard var thread = threads[botID], let index = thread.queue.firstIndex(where: { $0.id == queueID }) else { return "" }
        let item = thread.queue.remove(at: index)
        thread.queueRevision += 1
        threads[botID] = thread
        onEvent?(.botQueue(threadID: threadID, items: thread.queue, revision: thread.queueRevision, paused: false))
        return item.text
    }

    func removeQueued(threadID: String, queueID: String) async throws {
        _ = try await editQueued(threadID: threadID, queueID: queueID)
    }

    func steer(threadID: String, queueID: String, turnID: String?, revision: Int) async throws {
        if runs[threadID]?.isRunning == true {
            // Stopping for a steer does not pause the queue: the waiting message goes next.
            guard var run = runs[threadID] else { return }
            tasks[threadID]?.cancel()
            tasks[threadID] = nil
            run.status = .stopped
            runs[threadID] = run
            saveBotReply(threadID: threadID, run: run)
            var change = RunChange()
            change.status = .stopped
            onEvent?(.changed(chatID: threadID, turnID: run.turnID, change: change))
        }
        sendNextQueued(threadID: threadID)
    }

    func resumeQueue(threadID: String) async throws {
        sendNextQueued(threadID: threadID)
    }

    func interrupt(threadID: String, turnID: String) async throws {
        try await stop(chatID: threadID, turnID: turnID)
    }

    func markRead(threadID: String, messageID: String?) async throws {
        let botID = self.botID(ofThread: threadID)
        if let index = conversations.firstIndex(where: { $0.kind == .bot(botID) }) { conversations[index].unread = false }
    }
}
