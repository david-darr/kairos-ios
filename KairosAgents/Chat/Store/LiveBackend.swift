import Foundation

/// The person's own desktop, through its existing routes (docs/PHONE-API.md and the desktop source).
/// Everything here turns the desktop's shapes into what the screens show; nothing is cached on disk.
final class LiveBackend: ChatBackend {
    let isSample = false
    var onEvent: ((StoreEvent) -> Void)?

    private let connection: Connection
    private var agents: [AgentDTO] = []
    private var botConversations: [AgentConversationDTO] = []
    private var sessions: [ChatSessionRowDTO] = []
    private var pulseVersions = BotPulseVersionsDTO()
    private var sessionsDirty = true
    private var pollCount = 0
    private var choices: [ModelChoiceDTO] = []
    private var catalogs: [String: [ModelCatalogEntryDTO]] = [:]
    /// The last line of each model chat, by chat id, with the time it was read for.
    private var previews: [String: (updated: Double, text: String)] = [:]
    /// The settings each chat had when it was last read, so saving sends only what changed.
    private var savedSettings: [String: ChatSettings] = [:]
    /// Chats the person has looked at on this phone, with the update time they saw.
    private var seen: [String: Double]
    /// Which bot each bot conversation belongs to.
    private var threadBots: [String: String] = [:]
    /// Whether each bot conversation follows its bot's model (bot_threads.py: follows_bot_model).
    private var threadFollows: [String: Bool] = [:]
    private var running: Set<String> = []
    private var projects: [ChatProjectDTO] = []

    private static let seenKey = "chatSeenTimes"

    init(connection: Connection) {
        self.connection = connection
        seen = (UserDefaults.standard.dictionary(forKey: LiveBackend.seenKey) as? [String: Double]) ?? [:]
    }

    private func client() throws -> APIClient {
        guard let client = connection.client else { throw APIError.notPaired }
        return client
    }

    /// Run a desktop call and let the connection's state follow any failure.
    private func desk<T>(_ work: (APIClient) async throws -> T) async throws -> T {
        do {
            return try await work(try client())
        } catch {
            connection.note(error)
            throw error
        }
    }

    // MARK: Home

    func loadHome() async throws -> HomeData {
        try await desk { client in
            async let roster = client.agentRoster()
            async let conversations = client.agentConversations()
            async let rows = client.chatSessions()
            async let projectRows = try? await client.chatProjects()
            let (agents, botRows, sessions) = try await (roster, conversations, rows)
            self.agents = agents
            self.botConversations = botRows.agents ?? []
            self.sessions = sessions
            self.projects = await projectRows ?? self.projects
            self.sessionsDirty = false
            await self.fillPreviews(client)
            return self.composeHome()
        }
    }

    func pollHome() async throws -> HomeData? {
        try await desk { client in
            self.pollCount += 1
            let pulse = try await client.botPulse(
                agents: self.pulseVersions.agents, conversations: self.pulseVersions.conversations,
                team: self.pulseVersions.team, automations: self.pulseVersions.automations)
            var changed = false
            if let versions = pulse.versions { self.pulseVersions = versions }
            if let agents = pulse.agents {
                self.agents = agents
                changed = true
            }
            if let conversations = pulse.conversations?.agents {
                self.botConversations = conversations
                changed = true
            }
            if self.sessionsDirty || self.pollCount % 3 == 0 {
                let rows = try await client.chatSessions()
                if rows != self.sessions {
                    self.sessions = rows
                    changed = true
                }
                if let fresh = try? await client.chatProjects(), fresh != self.projects {
                    self.projects = fresh
                    changed = true
                }
                self.sessionsDirty = false
                await self.fillPreviews(client)
            }
            return changed ? self.composeHome() : nil
        }
    }

    func loadGlance() async throws -> Glance {
        try await desk { client in
            let home = try await client.phoneHome()
            var glance = Glance()
            glance.usage = (home.usage ?? []).compactMap { item -> GlanceUsage? in
                guard let provider = item.provider, !provider.isEmpty else { return nil }
                return GlanceUsage(provider: provider, percent: Int((item.percent ?? 0).rounded()), resetsAt: item.resetsAt?.date)
            }
            if let event = home.nextEvent, let title = event.title, !title.isEmpty {
                glance.nextEvent = ChatFormat.nextEvent(title: title, start: event.startsAt?.date, allDay: event.allDay ?? false)
                glance.nextEventTitle = title
                glance.nextEventStart = event.startsAt?.date
                glance.nextEventAllDay = event.allDay ?? false
            }
            glance.needsYou = home.needsYou ?? 0
            glance.running = home.running ?? 0
            return glance
        }
    }

    /// The session list has no message text, so read the last line of the newest few chats once each.
    private func fillPreviews(_ client: APIClient) async {
        let wanted = sessions.filter { $0.isForge != true && $0.agentId == nil }
            .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            .prefix(12)
            .filter { row in previews[row.id]?.updated != (row.updatedAt ?? 0) }
        for row in wanted.prefix(6) {
            guard let chat = try? await client.chatSession(row.id) else { continue }
            let last = (chat.messages ?? []).last { !($0.content ?? "").isEmpty }
            let text = last.map { TranscriptParsing.body($0.content ?? "").text } ?? ""
            previews[row.id] = (row.updatedAt ?? 0, ChatFormat.oneLine(text))
        }
    }

    private func composeHome() -> HomeData {
        let visible = agents.filter { $0.hidden != true }
            .sorted { first, second in
                let a = first.order ?? Double.greatestFiniteMagnitude, b = second.order ?? Double.greatestFiniteMagnitude
                if a != b { return a < b }
                return (first.createdAt ?? 0) < (second.createdAt ?? 0)
            }
        let bots = visible.map { LiveBackend.bot($0) }
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Only the person's own pins, in roster order. Home puts Kip and All bots in front of them.
        let pins = Set(botConversations.filter { $0.pinned == true }.map(\.id))
        let pinned = visible.filter { pins.contains($0.id) && !$0.isFrontDesk }.map(\.id)

        var rows: [(time: Double, conversation: Conversation)] = []
        for row in botConversations {
            guard let agent = byID[row.id] else { continue }
            if let sessionID = row.sessionId { threadBots[sessionID] = row.id }
            let hasTalk = row.sessionId != nil && (row.messageCount ?? 0) > 0
            guard hasTalk || agent.isFrontDesk else { continue }
            let status = agent.botStatus
            var preview = ChatFormat.oneLine(row.preview ?? "")
            if status == .working, let detail = agent.statusDetail, !detail.isEmpty { preview = ChatFormat.oneLine(detail) }
            if preview.isEmpty { preview = agent.isFrontDesk ? "Here when you need me." : (agent.role ?? "") }
            let time = row.at ?? agent.createdAt ?? 0
            rows.append((time, Conversation(
                id: row.sessionId ?? "bot-\(row.id)", kind: .bot(row.id), title: agent.name ?? "Bot", preview: preview,
                time: ChatFormat.listTime(time > 0 ? Date(timeIntervalSince1970: time) : nil),
                unread: (row.unread ?? 0) > 0 || status == .needsYou, working: status == .working)))
        }
        var learned = false
        for row in sessions where row.isForge != true && row.agentId == nil {
            let updated = row.updatedAt ?? row.createdAt ?? 0
            if seen[row.id] == nil {
                // A chat first met on this phone starts as read; only later replies mark it.
                seen[row.id] = updated
                learned = true
            }
            let working = running.contains(row.id)
            let title = (row.title ?? "").isEmpty ? "Untitled conversation" : (row.title ?? "")
            rows.append((updated, Conversation(
                id: row.id, kind: .model, title: title,
                preview: working ? "Working on it" : (previews[row.id]?.text ?? ""),
                time: working ? "now" : ChatFormat.listTime(Date(timeIntervalSince1970: updated)),
                unread: !working && updated > (seen[row.id] ?? updated) + 0.5, working: working,
                starred: row.starred == true, projectID: row.projectId)))
        }
        if learned { UserDefaults.standard.set(seen, forKey: LiveBackend.seenKey) }
        // Starred first, then newest: the desktop's own order (session_manager.list_sessions).
        rows.sort { a, b in
            if a.conversation.starred != b.conversation.starred { return a.conversation.starred }
            return a.time > b.time
        }
        let known = projects.map {
            ChatProject(id: $0.id, name: ($0.name ?? "").isEmpty ? "Project" : ($0.name ?? ""),
                        instructions: $0.instructions ?? "", documentCount: $0.documentIds?.count ?? 0)
        }
        return HomeData(bots: bots, pinned: pinned, conversations: rows.map(\.conversation), projects: known)
    }

    func pinBot(_ id: String, pinned: Bool) async throws {
        _ = try await desk { client in try await client.agentOrganize(id, action: pinned ? "pin" : "unpin") }
        if let index = botConversations.firstIndex(where: { $0.id == id }) { botConversations[index].pinned = pinned }
    }

    func setChatProject(_ id: String, projectID: String?) async throws {
        try await desk { client in try await client.chatSetProject(id, projectId: projectID) }
        if let index = sessions.firstIndex(where: { $0.id == id }) { sessions[index].projectId = projectID }
        sessionsDirty = true
    }

    func createProject(name: String, instructions: String) async throws -> ChatProject {
        let made = try await desk { client in try await client.chatProjectCreate(name: name, instructions: instructions) }
        projects.append(made)
        projects.sort { ($0.name ?? "").lowercased() < ($1.name ?? "").lowercased() }
        return ChatProject(id: made.id, name: made.name ?? name, instructions: made.instructions ?? instructions)
    }

    static func bot(_ agent: AgentDTO) -> Bot {
        Bot(
            id: agent.id, name: agent.name ?? "Bot", role: agent.role ?? agent.blurb ?? "",
            colorHex: agent.isFrontDesk ? 0xF2E8D8 : agent.bodyColorHex, status: agent.botStatus,
            shape: agent.mascotShape, accessory: agent.mascotAccessory, isKip: agent.isFrontDesk,
            model: agent.modelOverride ?? "Its own model", approval: approvalWord(agent.approvalMode), voice: agent.voiceId ?? "Kairos Voice")
    }

    static func approvalWord(_ mode: String?) -> String {
        switch mode {
        case "ask": return "Ask before acting"
        case "edits": return "Edits without asking"
        case "auto": return "Auto"
        case "full": return "Full access"
        case "custom": return "Custom rules"
        default: return "Ask before acting"
        }
    }

    private func markSeen(_ chatID: String, updated: Double?) {
        seen[chatID] = max(updated ?? 0, Date().timeIntervalSince1970)
        UserDefaults.standard.set(seen, forKey: LiveBackend.seenKey)
    }

    // MARK: Live events

    /// One event of the desktop's live stream, as JSON.
    func handle(packet data: Data) {
        guard let packet = try? KJSON.decode(ChatLivePacketDTO.self, from: data) else { return }
        switch packet.type {
        case "heartbeat":
            return
        case "snapshot":
            var runs: [String: RunState] = [:]
            for (chatID, dto) in packet.runs ?? [:] {
                if let run = TranscriptParsing.run(dto) { runs[chatID] = run }
            }
            running = Set(runs.filter { $0.value.isRunning }.keys)
            onEvent?(.snapshot(runs))
        case "started":
            guard let chatID = packet.sessionId, let dto = packet.run, let run = TranscriptParsing.run(dto) else { return }
            running.insert(chatID)
            sessionsDirty = true
            onEvent?(.started(chatID: chatID, run: run))
        case "chunk":
            guard let chatID = packet.sessionId, let turnID = packet.turnId, let text = packet.chunk else { return }
            onEvent?(.chunk(chatID: chatID, turnID: turnID, text: text))
        case "tool_step":
            guard let chatID = packet.sessionId, let turnID = packet.turnId, let step = packet.step else { return }
            let finished = step.phase == "finished"
            onEvent?(.step(chatID: chatID, turnID: turnID, id: step.id ?? UUID().uuidString,
                           text: TranscriptParsing.stepText(name: step.name, summary: step.summary),
                           finished: finished, failed: finished && step.ok == false))
        case "update":
            guard let chatID = packet.sessionId, let turnID = packet.turnId, let changes = packet.changes else { return }
            let change = TranscriptParsing.change(changes)
            if let status = change.status, status != .processing {
                running.remove(chatID)
                sessionsDirty = true
            }
            onEvent?(.changed(chatID: chatID, turnID: turnID, change: change))
        case "bg_tasks":
            guard let chatID = packet.sessionId else { return }
            onEvent?(.background(chatID: chatID, items: (packet.items ?? []).map(TranscriptParsing.background)))
        case "bg_followup":
            guard let chatID = packet.sessionId, let message = packet.message else { return }
            let parsed = TranscriptParsing.body(message.content ?? "")
            var entry = TranscriptEntry(id: "followup-\(message.ts ?? 0)", role: .assistant, text: parsed.text,
                                        time: message.ts.map { Date(timeIntervalSince1970: $0) })
            entry.files = parsed.files
            entry.sources = parsed.sources
            entry.designs = parsed.designs
            entry.caption = "After background work"
            onEvent?(.followup(chatID: chatID, entry: entry))
        case "design_changed":
            // A design was made or edited. The chats on screen read their design list again (rate limited there).
            onEvent?(.designChanged(chatID: packet.sessionId))
        default:
            guard packet.type.hasPrefix("bot"), let bot = try? KJSON.decode(BotLivePacketDTO.self, from: data),
                  let threadID = bot.sessionId else { return }
            handle(bot: bot, threadID: threadID)
        }
    }

    private func handle(bot packet: BotLivePacketDTO, threadID: String) {
        switch packet.type {
        case "bot_queue":
            onEvent?(.botQueue(threadID: threadID, items: TranscriptParsing.queued(packet.items),
                               revision: packet.revision ?? 0, paused: packet.paused ?? false))
        case "bot_card":
            guard let card = packet.card, let request = TranscriptParsing.request(card: card) else { return }
            let open = packet.event != "settled" && (card.waiting ?? (card.status == "pending"))
            onEvent?(.botRequest(threadID: threadID, request: request, open: open))
        default:
            // A new version chosen, a front desk card, a widget, a goal step: read the newest messages again.
            onEvent?(.botChanged(threadID: threadID))
        }
    }

    // MARK: Model chats

    func openModelChat(_ id: String) async throws -> ModelChatSnapshot {
        try await desk { client in
            async let chatRead = client.chatSession(id)
            async let workRead = try? await client.chatBackground(sessionId: id)
            if self.choices.isEmpty { self.choices = (try? await client.modelChoices()) ?? [] }
            let chat = try await chatRead
            let work = await workRead
            await self.loadCatalog(chat.modelEndpointId, client: client)
            let settings = self.settings(for: chat)
            self.savedSettings[id] = settings
            self.markSeen(id, updated: chat.updatedAt)
            return ModelChatSnapshot(
                title: (chat.title ?? "").isEmpty ? "New chat" : (chat.title ?? ""),
                entries: TranscriptParsing.entries(chat.messages ?? [], modelName: settings.versionName ?? settings.modelName),
                settings: settings, starred: chat.starred ?? false, contextPercent: chat.contextState?.percent,
                background: (work?.items ?? []).map(TranscriptParsing.background))
        }
    }

    private func settings(for chat: ChatSessionDTO) -> ChatSettings {
        var settings = ChatSettings()
        if let endpointID = chat.modelEndpointId, let choice = choices.first(where: { $0.id == endpointID }) {
            settings.modelID = endpointID
            settings.modelName = choice.name ?? "Model"
            settings.source = LiveBackend.sourceWord(choice)
        } else if let endpointID = chat.modelEndpointId {
            settings.modelID = endpointID
            settings.modelName = "Model"
        }
        if let override = chat.modelOverride, !override.isEmpty {
            settings.versionID = override
            let known = catalogs[settings.modelID ?? ""]?.first { $0.id == override }
            settings.versionName = known?.displayName ?? override
            settings.efforts = (known?.supportedEfforts ?? []).compactMap(\.effort)
        } else {
            settings.efforts = defaultEfforts(endpointID: settings.modelID)
        }
        settings.effort = chat.modelEffort
        if let effort = settings.effort, !settings.efforts.contains(effort) { settings.efforts.append(effort) }
        let admin = connection.desktop?.isAdmin ?? false
        settings.approvals = admin ? ["Ask first", "Full access"] : ["Ask first"]
        settings.approval = chat.permissionMode == "auto" && admin ? "Full access" : "Ask first"
        return settings
    }

    // No version chosen: the levels of the connection's own default version, once its catalog is known.
    private func defaultEfforts(endpointID: String?) -> [String] {
        guard let endpointID, let defaultVersion = choices.first(where: { $0.id == endpointID })?.model, !defaultVersion.isEmpty else { return [] }
        let known = catalogs[endpointID]?.first { $0.id == defaultVersion }
        return (known?.supportedEfforts ?? []).compactMap(\.effort)
    }

    private func loadCatalog(_ endpointID: String?, client: APIClient) async {
        guard let endpointID, !endpointID.isEmpty, catalogs[endpointID] == nil else { return }
        if let catalog = try? await client.modelCatalog(endpointId: endpointID) { catalogs[endpointID] = catalog }
    }

    static func sourceWord(_ choice: ModelChoiceDTO) -> String {
        switch choice.kind {
        case "claude_cli": return "Claude subscription"
        case "codex_cli": return "Codex"
        case "antigravity_cli": return "Antigravity"
        case "local": return (choice.model ?? "").isEmpty ? "This PC" : "This PC · \(choice.model ?? "")"
        default: return (choice.model ?? "").isEmpty ? "API" : "API · \(choice.model ?? "")"
        }
    }

    func createModelChat() async throws -> String {
        try await desk { client in
            let chat = try await client.chatCreate()
            self.sessionsDirty = true
            self.markSeen(chat.id, updated: chat.updatedAt)
            return chat.id
        }
    }

    func sendModel(chatID: String, text: String, attachments: [StagedAttachment], requestID: String) async throws -> String? {
        try await desk { client in
            let ids = attachments.compactMap(\.remoteID)
            do {
                return try await client.chatStart(sessionId: chatID, message: text, attachmentIds: ids, requestId: requestID).turnId
            } catch let error as APIError where error.isOffline {
                // The answer may have been lost on the way back. The same request id never starts a second turn.
                try? await Task.sleep(for: .seconds(1.2))
                return try await client.chatStart(sessionId: chatID, message: text, attachmentIds: ids, requestId: requestID).turnId
            }
        }
    }

    func stop(chatID: String, turnID: String?) async throws {
        try await desk { client in _ = try await client.chatStop(sessionId: chatID, turnId: turnID) }
    }

    func renameChat(_ id: String, title: String) async throws {
        try await desk { client in try await client.chatRename(id, title: title) }
        sessionsDirty = true
    }

    func starChat(_ id: String, starred: Bool) async throws {
        try await desk { client in try await client.chatStar(id, starred: starred) }
        sessionsDirty = true
    }

    func deleteChat(_ id: String) async throws {
        try await desk { client in try await client.chatDelete(id) }
        sessions.removeAll { $0.id == id }
        previews[id] = nil
        sessionsDirty = true
    }

    func forkChat(_ id: String, throughIndex: Int) async throws -> String {
        let fork = try await desk { client in try await client.chatFork(id, throughIndex: throughIndex) }
        sessionsDirty = true
        return fork.id
    }

    func compactChat(_ id: String) async throws {
        try await desk { client in try await client.chatCompact(sessionId: id) }
    }

    func chatSummary(_ id: String, refresh: Bool) async throws -> String {
        try await desk { client in
            if !refresh {
                let saved = try await client.chatSummary(sessionId: id)
                if let text = saved.summary, !text.isEmpty, saved.stale != true { return text }
            }
            let made = try await client.chatMakeSummary(sessionId: id, force: refresh)
            guard let text = made.summary, !text.isEmpty else { throw ChatFailure("There is nothing to summarise yet.") }
            return text
        }
    }

    func chatFiles(_ id: String) async throws -> [ChatFile] {
        try await desk { client in
            try await client.chatFiles(sessionId: id).compactMap { row -> ChatFile? in
                guard let url = row.url else { return nil }
                let name = ChatFile.cleanName(row.name ?? "File")
                var file = ChatFile(id: url, name: name, kind: ChatFile.kind(forName: name), size: row.size.map { Int($0) })
                file.missing = row.exists == false
                return file
            }
        }
    }

    func chatDetails(_ id: String) async throws -> ChatDetails {
        try await desk { client in
            let usage = try await client.chatUsage(id)
            return LiveBackend.details(usage)
        }
    }

    static func details(_ usage: ChatUsageDTO) -> ChatDetails {
        var details = ChatDetails()
        let context = usage.context
        details.usedTokens = context?.usedTokens.map { Int($0) }
        details.windowTokens = (context?.capacityTokens ?? usage.model?.contextWindow).map { Int($0) }
        details.percent = context?.percent
        details.windowEstimated = context?.estimatedCapacity ?? usage.model?.contextWindowEstimated ?? false
        details.parts = (context?.parts ?? []).compactMap { part -> ChatDetails.Part? in
            guard let tokens = part.tokens, tokens > 0 else { return nil }
            return ChatDetails.Part(id: part.key ?? part.label ?? "part", label: part.label ?? part.key ?? "Part",
                                    tokens: Int(tokens), estimated: part.estimated ?? false)
        }
        details.model = usage.model?.model
        details.provider = usage.model?.provider

        func count(_ value: Double?) -> String { value.map { ChatDetails.tokens(Int($0)) } ?? "n/a" }
        func whole(_ value: Int?) -> String { value.map(String.init) ?? "n/a" }
        var rows: [ChatDetails.Row] = []
        rows.append(.init(id: "Model", value: usage.model?.model ?? "n/a"))
        rows.append(.init(id: "Provider", value: usage.model?.provider ?? "n/a"))
        if let window = details.windowTokens {
            rows.append(.init(id: "Context window", value: ChatDetails.tokens(window) + (details.windowEstimated ? " (estimated)" : "")))
        } else {
            rows.append(.init(id: "Context window", value: "unknown"))
        }
        rows.append(.init(id: "Calls", value: whole(usage.runs)))
        rows.append(.init(id: "Turns", value: whole(usage.turns)))
        rows.append(.init(id: "Input", value: count(usage.inputTokens)))
        rows.append(.init(id: "Output", value: count(usage.outputTokens)))
        rows.append(.init(id: "Cache read", value: count(usage.cacheReadTokens)))
        rows.append(.init(id: "Cache write", value: count(usage.cacheWriteTokens)))
        rows.append(.init(id: "Cache hit", value: usage.cacheHitPercent.map { "\(Int($0.rounded()))%" } ?? "n/a"))
        rows.append(.init(id: "Tool calls", value: usage.toolCalls.map { String(Int($0)) } ?? "n/a"))
        rows.append(.init(id: "Compactions", value: whole(usage.compactions)))
        rows.append(.init(id: "Helper runs", value: whole(usage.helperRuns)))
        rows.append(.init(id: "Side calls", value: whole(usage.sideRuns)))
        rows.append(.init(id: "First output", value: usage.lastReply?.ttftSeconds.map { String(format: "%.1f s", $0) } ?? "n/a"))
        rows.append(.init(id: "Speed", value: usage.lastReply?.tokensPerSecond.map { "\(Int($0.rounded())) tok/s" } ?? "n/a"))
        if let cost = usage.cost, let amount = cost["amount"]?.double {
            let kind = cost["kind"]?.string ?? "estimated"
            rows.append(.init(id: "Cost", value: String(format: "$%.4f ", amount) + kind))
        } else {
            rows.append(.init(id: "Cost", value: "unknown"))
        }
        details.rows = rows
        if (usage.runs ?? 0) == 0 {
            details.note = "No recorded runs yet. Figures appear after the first reply."
        } else if let reported = usage.reportedRuns, let runs = usage.runs, reported < runs {
            details.note = reported == 0
                ? "The provider reported no token counts for this chat."
                : "Token counts cover \(reported) of \(runs) recorded runs; the others reported none."
        }
        return details
    }

    // MARK: Model, effort, approval

    func modelOptions() async throws -> [ModelOption] {
        try await desk { client in
            self.choices = try await client.modelChoices()
            return self.choices.map {
                ModelOption(id: $0.id, name: $0.name ?? "Model", source: LiveBackend.sourceWord($0), takesImages: $0.supportsImages ?? true)
            }
        }
    }

    func modelVersions(modelID: String) async throws -> [ModelVersion] {
        try await desk { client in
            let catalog = try await client.modelCatalog(endpointId: modelID)
            self.catalogs[modelID] = catalog
            return catalog.map {
                ModelVersion(id: $0.id, name: $0.displayName ?? $0.id, efforts: ($0.supportedEfforts ?? []).compactMap(\.effort))
            }
        }
    }

    func botModel(threadID: String) async throws -> ChatSettings {
        try await desk { client in
            if self.choices.isEmpty { self.choices = (try? await client.modelChoices()) ?? [] }
            let state = try await client.botChatState(threadID)
            await self.loadCatalog(state.model?.endpointId, client: client)
            return self.botSettings(state.model, threadID: threadID)
        }
    }

    private func botSettings(_ model: BotModelDTO?, threadID: String) -> ChatSettings {
        var settings = ChatSettings()
        settings.followsBot = threadFollows[threadID] ?? true
        settings.approvals = []
        guard let model, let endpointID = model.endpointId else { return settings }
        let choice = choices.first { $0.id == endpointID }
        settings.modelID = endpointID
        settings.modelName = model.name ?? choice?.name ?? "Model"
        settings.source = choice.map(LiveBackend.sourceWord) ?? ""
        if let version = model.model, !version.isEmpty {
            settings.versionID = version
            let known = catalogs[endpointID]?.first { $0.id == version }
            settings.versionName = known?.displayName ?? version
            settings.efforts = (known?.supportedEfforts ?? []).compactMap(\.effort)
        } else {
            settings.efforts = defaultEfforts(endpointID: endpointID)
        }
        settings.effort = model.effort
        if let effort = settings.effort, !settings.efforts.contains(effort) { settings.efforts.append(effort) }
        return settings
    }

    func saveBotModel(threadID: String, settings: ChatSettings) async throws -> ChatSettings {
        try await desk { client in
            var endpoint = settings.modelID
            var version = settings.versionID
            var effort = settings.effort
            if endpoint == nil {
                // Follow the bot again: its own connection, version and level, as static/js/botsPanel.js does.
                let agent = self.threadBots[threadID].flatMap { id in self.agents.first { $0.id == id } }
                endpoint = agent?.endpointId ?? self.choices.first { $0.kind == "claude_cli" }?.id
                version = agent?.modelOverride
                effort = agent?.modelEffort
            }
            _ = try await client.chatSetModel(threadID, endpointId: endpoint, override: version, effort: effort)
            if let botID = self.threadBots[threadID], let list = try? await client.agentThreads(botID) {
                for thread in list.threads ?? [] { self.threadFollows[thread.id] = thread.followsBotModel }
            }
            let state = try await client.botChatState(threadID)
            await self.loadCatalog(state.model?.endpointId, client: client)
            return self.botSettings(state.model, threadID: threadID)
        }
    }

    func saveSettings(chatID: String, settings: ChatSettings) async throws -> ChatSettings {
        try await desk { client in
            let before = self.savedSettings[chatID] ?? ChatSettings()
            var after = settings
            if before.modelID != settings.modelID || before.versionID != settings.versionID || before.effort != settings.effort {
                _ = try await client.chatSetModel(chatID, endpointId: settings.modelID, override: settings.versionID, effort: settings.effort)
            }
            if before.approval != settings.approval {
                let mode = settings.approval == "Full access" ? "auto" : "base"
                let answer = try await client.chatSetPermissionMode(chatID, mode: mode)
                after.approval = answer.mode == "auto" ? "Full access" : "Ask first"
            }
            self.savedSettings[chatID] = after
            return after
        }
    }

    // MARK: Approvals and questions

    func answer(_ request: PendingRequest, choice: PendingRequest.Choice) async throws {
        try await desk { client in
            switch request.channel {
            case .permission:
                _ = try await client.permissionAnswer(request.id, choice: choice.id)
            case .botCard(let revision):
                if choice.id.hasPrefix("resume:") {
                    let result = try await client.botCardResume(request.id, outcome: String(choice.id.dropFirst(7)))
                    if result.ok == false { throw ChatFailure(result.message ?? "That request is no longer waiting.") }
                } else {
                    let remember = choice.scope == "once" ? "once" : (choice.scope == "session" ? "session" : "always")
                    let result = try await client.botCardRespond(
                        request.id, action: choice.allows ? "allow" : "deny", choiceId: choice.id,
                        remember: choice.allows ? remember : nil, reviewedRevision: revision)
                    if result.ok == false { throw ChatFailure(result.message ?? "That request is no longer waiting.") }
                }
            case .sample:
                break
            }
        }
    }

    func respond(_ request: PendingRequest, answers: [String: QuestionAnswer], skip: Bool) async throws {
        try await desk { client in
            var body: [String: Any] = [:]
            for question in request.questions {
                if let answer = answers[question.id], !answer.isEmpty { body[question.id] = answer.value(multiple: question.multiple) }
            }
            switch request.channel {
            case .permission:
                _ = try await client.permissionRespond(request.id, answers: skip ? nil : body, skip: skip)
            case .botCard(let revision):
                let result = try await client.botCardRespond(
                    request.id, action: skip ? "skip" : "answer", answers: skip ? nil : body, reviewedRevision: revision)
                if result.ok == false { throw ChatFailure(result.message ?? "That question is no longer waiting.") }
            case .sample:
                break
            }
        }
    }

    // MARK: Files

    func upload(_ file: OutgoingFile) async throws -> String {
        try await desk { client in try await client.chatUpload(file).id }
    }

    func fileData(chatID: String, file: ChatFile) async throws -> Data {
        if let local = file.local { return local }
        return try await desk { client in
            try await client.chatArtifactBytes(sessionId: chatID, url: file.id, download: file.kind != .image && file.kind != .pdf && file.kind != .text)
        }
    }

    // MARK: Bot conversations

    func openBotChat(botID: String, threadID: String?) async throws -> BotChatSnapshot {
        try await desk { client in
            let list = try await client.agentThreads(botID)
            let threads = (list.threads ?? []).filter { $0.thread?.archivedAt == nil }
            var chosen = threadID
            if chosen == nil {
                chosen = threads.max { ($0.updatedAt ?? 0) < ($1.updatedAt ?? 0) }?.id ?? list.mainId
            }
            if chosen == nil {
                chosen = try await client.agentCreateThread(botID).id
            }
            guard let id = chosen else { throw ChatFailure("This bot has no conversation yet.") }
            self.threadBots[id] = botID
            for thread in threads { self.threadFollows[thread.id] = thread.followsBotModel }
            let name = self.agents.first { $0.id == botID }?.name ?? "The bot"

            async let stateRead = client.botChatState(id)
            async let pageRead = client.botChatMessages(id, limit: 50)
            async let cardsRead = try? await client.botCards(threadId: id, status: "pending")
            let (state, page) = try await (stateRead, pageRead)
            let cards = await cardsRead

            let summaries = threads.map { thread in
                BotThreadSummary(
                    id: thread.id, title: (thread.title ?? "").isEmpty ? "Conversation" : (thread.title ?? ""),
                    preview: ChatFormat.oneLine(thread.preview ?? ""),
                    time: ChatFormat.listTime(thread.updatedAt.map { Date(timeIntervalSince1970: $0) }),
                    unread: thread.thread?.unread ?? false, working: thread.status == "working",
                    isMain: thread.id == list.mainId || thread.thread?.main == true)
            }
            return BotChatSnapshot(
                threadID: id, threads: summaries,
                entries: TranscriptParsing.botEntries(page.messages ?? [], botName: name),
                hasOlder: page.hasBefore ?? false, firstID: page.firstId,
                leafID: state.activeLeafId ?? page.activeLeafId,
                queue: TranscriptParsing.queued(state.queue?.items), queueRevision: state.queue?.revision ?? 0,
                queuePaused: state.queue?.paused ?? false,
                requests: (cards?.cards ?? []).filter { $0.waiting ?? ($0.status == "pending") }.compactMap(TranscriptParsing.request(card:)),
                modelLine: state.model?.label, lastID: page.lastId)
        }
    }

    private func page(_ page: BotMessagesPageDTO, threadID: String) -> BotMessagePage {
        let botID = threadBots[threadID]
        let name = agents.first { $0.id == botID }?.name ?? "The bot"
        return BotMessagePage(entries: TranscriptParsing.botEntries(page.messages ?? [], botName: name),
                              hasOlder: page.hasBefore ?? false, firstID: page.firstId, leafID: page.activeLeafId, lastID: page.lastId)
    }

    func olderBotMessages(threadID: String, before: String) async throws -> BotMessagePage {
        try await desk { client in self.page(try await client.botChatMessages(threadID, limit: 50, before: before), threadID: threadID) }
    }

    func newestBotMessages(threadID: String) async throws -> BotMessagePage {
        try await desk { client in self.page(try await client.botChatMessages(threadID, limit: 50), threadID: threadID) }
    }

    func sendBot(threadID: String, text: String, attachments: [StagedAttachment], sendID: String, leafID: String?) async throws -> BotSendOutcome {
        try await desk { client in
            let ids = attachments.compactMap(\.remoteID)
            do {
                let result = try await client.botChatSend(threadID, sendId: sendID, text: text, expectedLeafId: leafID, attachmentIds: ids)
                return BotSendOutcome(queued: result.queued ?? false, turnID: result.turnId, leafID: result.activeLeafId)
            } catch APIError.server(let status, _) where status == 409 {
                // The conversation moved on since it was read (a reply landed, a version changed): send against where it is now.
                let state = try await client.botChatState(threadID)
                let result = try await client.botChatSend(threadID, sendId: UUID().uuidString, text: text, expectedLeafId: state.activeLeafId, attachmentIds: ids)
                return BotSendOutcome(queued: result.queued ?? false, turnID: result.turnId, leafID: result.activeLeafId)
            }
        }
    }

    func editQueued(threadID: String, queueID: String) async throws -> String {
        try await desk { client in
            try await client.botChatQueueEdit(threadID, queueId: queueID).draft?.text ?? ""
        }
    }

    func removeQueued(threadID: String, queueID: String) async throws {
        try await desk { client in _ = try await client.botChatQueueRemove(threadID, queueId: queueID) }
    }

    func steer(threadID: String, queueID: String, turnID: String?, revision: Int) async throws {
        try await desk { client in
            let result = try await client.botChatSteer(threadID, queueId: queueID, turnId: turnID, queueRevision: revision)
            if result.steered == false {
                throw ChatFailure(LiveBackend.steerRefusal(result.blocked))
            }
        }
    }

    static func steerRefusal(_ reason: String?) -> String {
        switch reason {
        case "not-first": return "Only the first waiting message can be sent now."
        case "turn-changed", "changed": return "The conversation changed. Try again."
        case "stop-timeout": return "The reply did not stop in time. Try again in a moment."
        case "capacity": return "This bot is at its limit of conversations running at once."
        case "busy": return "The bot is busy. The message stays in the queue."
        default: return "That message could not be sent now. It stays in the queue."
        }
    }

    func resumeQueue(threadID: String) async throws {
        try await desk { client in _ = try await client.botChatQueueResume(threadID) }
    }

    func interrupt(threadID: String, turnID: String) async throws {
        try await desk { client in _ = try await client.botChatInterrupt(threadID, turnId: turnID) }
    }

    func markRead(threadID: String, messageID: String?) async throws {
        let botID = threadBots[threadID]
        // Each call stands alone: a desktop that refuses one (say, an older one without the read action) never
        // keeps the other from going, and the unread mark here clears either way.
        try? await desk { client in _ = try await client.botChatMarkRead(threadID, messageId: messageID) }
        // Home and All bots read the bot's conversation list, which keeps its own read mark apart from the thread's.
        if let botID { try? await desk { client in _ = try await client.agentOrganize(botID, action: "read") } }
        if let botID, let index = botConversations.firstIndex(where: { $0.id == botID }) { botConversations[index].unread = 0 }
    }

    func markChatSeen(_ chatID: String) {
        markSeen(chatID, updated: nil)
    }
}
