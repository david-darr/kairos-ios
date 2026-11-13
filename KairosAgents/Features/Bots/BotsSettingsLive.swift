import SwiftUI

// The paired desktop behind one bot's settings: the bot record (GET and PATCH /api/agents/{id}), its standing
// instructions file, overview, history, approval level, remembered commands, outside-message allowance, the
// model choices and voices. Unpaired, nothing here runs and the screens show BotsStore's samples exactly as before.
// Everything read here belongs to one desktop and one account; a result that lands for another is dropped.

/// How a change the screen waits on came back.
nonisolated enum BotSetOutcome: Equatable, Sendable {
    case done(String)
    case refused(String)
    /// The desktop had changed since this page read it (409). The page was read again.
    case changed(String)
    /// The answer was lost, so the desktop may have done it.
    case unsure(String)

    var text: String {
        switch self {
        case .done(let text), .refused(let text), .changed(let text), .unsure(let text): return text
        }
    }

    var isDone: Bool {
        if case .done = self { return true }
        return false
    }
}

/// A change to the bot record as the phone sends it: the desktop's own keys (agent_routes.py: AgentBody).
nonisolated enum BotSetChange {
    /// An optional text sent: the text, or nil for JSON null.
    static func text(_ value: Any?) -> String? {
        value as? String
    }

    /// The record as it will be once the desktop takes these changes, for showing a change at once.
    static func applying(_ changes: [String: Any], to agent: AgentDTO) -> AgentDTO {
        var out = agent
        for (key, value) in changes {
            switch key {
            case "name": out.name = text(value)
            case "role": out.role = text(value)
            case "blurb": out.blurb = text(value)
            case "soul": out.soul = text(value)
            case "reply_style": out.replyStyle = text(value)
            case "endpoint_id":
                out.endpointId = text(value)
                // A new connection starts on its own default version and effort (agent_service.py: update).
                if out.endpointId != agent.endpointId {
                    if changes["model_override"] == nil { out.modelOverride = nil }
                    if changes["model_effort"] == nil { out.modelEffort = nil }
                }
            case "model_override":
                out.modelOverride = text(value)
                if out.modelOverride != agent.modelOverride, changes["model_effort"] == nil { out.modelEffort = nil }
            case "model_effort": out.modelEffort = text(value)
            case "cache_keep_warm": out.cacheKeepWarm = text(value)
            case "fallback":
                let list = (value as? [[String: Any]]) ?? []
                out.fallback = .array(list.map { item -> JSONValue in
                    JSONValue.object(item.compactMapValues { value -> JSONValue? in
                        guard let text = value as? String else { return nil }
                        return JSONValue.string(text)
                    })
                })
            case "enabled": out.enabled = value as? Bool
            case "daily_run_cap": out.dailyRunCap = value as? Int
            case "deliver_to_channel": out.deliverToChannel = text(value)
            case "voice_id": out.voiceId = text(value)
            case "call_mode": out.callMode = text(value)
            case "speak_replies": out.speakReplies = value as? Bool
            case "notifications": out.notifications = value as? Bool
            case "outbound":
                if let policy = (value as? [String: Any])?["policy"] as? String {
                    var object = agent.outbound?.object ?? [:]
                    object["policy"] = .string(policy)
                    out.outbound = .object(object)
                }
            case "avatar":
                if let look = value as? [String: Any] {
                    out.avatar = AgentAvatarDTO(version: 3, character: "ajar", shape: look["shape"] as? String,
                                                color: look["color"] as? String, acc: look["acc"] as? String,
                                                finish: look["finish"] as? String)
                    out.color = (look["color"] as? String)?.lowercased()
                }
            default:
                break
            }
        }
        return out
    }

    /// Whether the record holds every value that was sent. Used after a lost answer, against what was sent.
    static func has(_ agent: AgentDTO?, _ changes: [String: Any]) -> Bool {
        guard let agent else { return false }
        for (key, value) in changes {
            let holds: Bool
            switch key {
            case "name": holds = same(agent.name, value)
            case "role": holds = same(agent.role, value)
            case "blurb": holds = same(agent.blurb, value)
            case "soul": holds = same(agent.soul, value)
            case "reply_style": holds = same(agent.replyStyle, value)
            case "endpoint_id": holds = same(agent.endpointId, value)
            case "model_override": holds = same(agent.modelOverride, value)
            case "model_effort": holds = same(agent.modelEffort, value)
            case "cache_keep_warm": holds = same(agent.cacheKeepWarm, value)
            case "deliver_to_channel": holds = same(agent.deliverToChannel, value)
            case "voice_id": holds = same(agent.voiceId, value)
            case "call_mode": holds = same(agent.callMode, value)
            case "enabled": holds = agent.enabled == (value as? Bool)
            case "speak_replies": holds = agent.speakReplies == (value as? Bool)
            case "notifications": holds = agent.notifications == (value as? Bool)
            case "daily_run_cap": holds = agent.dailyRunCap == (value as? Int)
            case "fallback":
                let sent = ((value as? [[String: Any]]) ?? []).compactMap { item in
                    (item["endpoint_id"] as? String).map { BotSetFallback(endpointID: $0, modelOverride: item["model_override"] as? String) }
                }
                holds = BotSetWire.fallbacks(agent.fallback) == sent
            case "outbound":
                holds = BotSetWire.outboundPolicy(agent.outbound) == ((value as? [String: Any])?["policy"] as? String)
            case "avatar":
                let look = (value as? [String: Any]) ?? [:]
                holds = agent.avatar?.shape == look["shape"] as? String
                    && agent.avatar?.color?.uppercased() == (look["color"] as? String)?.uppercased()
                    && (agent.avatar?.acc ?? "none") == ((look["acc"] as? String) ?? "none")
            default:
                holds = true
            }
            if !holds { return false }
        }
        return true
    }

    private static func same(_ stored: String?, _ sent: Any) -> Bool {
        let a = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let b = (text(sent) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return a == b
    }
}

@Observable
final class BotsSettingsLive {
    static let shared = BotsSettingsLive()

    /// Each bot's record as the desktop has it, by bot id.
    var records: [String: AgentDTO] = [:]
    var recordLoad: [String: BotsLiveLoad] = [:]
    /// Bots with a change on its way: their controls wait until it is known.
    var busy: Set<String> = []
    /// A change whose answer was lost and could not be checked, by bot.
    var unsure: [String: String] = [:]

    var souls: [String: BotSetSoulDTO] = [:]
    var soulLoad: [String: BotsLiveLoad] = [:]
    var overviews: [String: BotSetOverviewDTO] = [:]
    var overviewLoad: [String: BotsLiveLoad] = [:]
    var histories: [String: BotSetHistoryDTO] = [:]
    var historyLoad: [String: BotsLiveLoad] = [:]

    var policies: [String: BotApprovalPolicyDTO] = [:]
    var policyLoad: [String: BotsLiveLoad] = [:]
    var rules: [String: [BotSetCommandRuleDTO]] = [:]
    var rulesLoad: [String: BotsLiveLoad] = [:]
    var outbound: [String: BotSetOutboundDTO] = [:]
    /// Remembered commands with a removal on its way.
    var removing: Set<String> = []

    var choices: [ModelChoiceDTO] = []
    var choicesLoad: BotsLiveLoad = .idle
    /// The versions each connection offers, by connection id.
    var catalogs: [String: [ModelCatalogEntryDTO]] = [:]
    /// How many of a bot's conversations use another model than the bot's.
    var otherModel: [String: Int] = [:]
    /// Bots whose "Switch them too" is on its way.
    var following: Set<String> = []

    var voices: [BotSetVoiceDTO] = []
    var voicesNote: String?
    var voicesLoad: BotsLiveLoad = .idle
    var liveVoice: BotSetLiveVoiceDTO?

    var channels: [TaskChannelDTO] = []
    var channelsLoad: BotsLiveLoad = .idle

    @ObservationIgnored private var account = "sample"
    @ObservationIgnored private var seqs: [String: Int] = [:]
    @ObservationIgnored private var writing: [String: Int] = [:]
    @ObservationIgnored private var writeGeneration: [String: Int] = [:]

    // MARK: Which desktop

    /// Paired: the screens read from here, never from the samples.
    var active: Bool { !Connection.shared.usesSampleData }

    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Changes when the phone is paired or unpaired, the desktop starts answering, or another account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// What was read belongs to the desktop and account paired right now.
    var isCurrent: Bool { active && account == Self.accountKey }

    /// Match the connection: another desktop or account, or unpairing, drops everything read before.
    func followConnection() {
        let want = active ? Self.accountKey : "sample"
        guard want != account else { return }
        reset()
        account = want
    }

    private func reset() {
        records = [:]
        recordLoad = [:]
        busy = []
        unsure = [:]
        souls = [:]
        soulLoad = [:]
        overviews = [:]
        overviewLoad = [:]
        histories = [:]
        historyLoad = [:]
        policies = [:]
        policyLoad = [:]
        rules = [:]
        rulesLoad = [:]
        outbound = [:]
        removing = []
        choices = []
        choicesLoad = .idle
        catalogs = [:]
        otherModel = [:]
        following = []
        voices = []
        voicesNote = nil
        voicesLoad = .idle
        liveVoice = nil
        channels = []
        channelsLoad = .idle
        // New counters: an answer for the last account can never match them.
        seqs = seqs.mapValues { $0 + 1 }
        writing = [:]
        writeGeneration = writeGeneration.mapValues { $0 + 1 }
    }

    private func stillLive(_ account: String) -> Bool {
        active && self.account == account && Self.accountKey == account
    }

    private func client() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    private func beginWrite(_ botID: String) {
        writing[botID, default: 0] += 1
        writeGeneration[botID, default: 0] += 1
    }

    private func endWrite(_ botID: String) {
        writing[botID] = max(0, (writing[botID] ?? 1) - 1)
        writeGeneration[botID, default: 0] += 1
    }

    /// A write whose answer never came: the desktop may have done it. A request that never left this
    /// iPhone (no network, no such address, no secure connection) is not in doubt.
    private func unconfirmed(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        guard let api = error as? APIError else { return false }
        if case .unreadable = api { return true }
        if case .server(let status, _) = api, status >= 500 { return true }
        guard api.isOffline else { return false }
        let neverSent: [URLError.Code] = [.notConnectedToInternet, .cannotFindHost, .secureConnectionFailed,
                                          .appTransportSecurityRequiresSecureConnection]
        return !neverSent.contains { APIError.from(URLError($0)) == api }
    }

    private func status(_ error: Error) -> Int? {
        if case .server(let status, _)? = error as? APIError { return status }
        return nil
    }

    /// A load state for the screen: reading until this account's first read has landed.
    func shown(_ state: BotsLiveLoad?) -> BotsLiveLoad {
        guard isCurrent else { return .loading }
        let state = state ?? .idle
        return state == .idle ? .loading : state
    }

    func record(_ botID: String) -> AgentDTO? { isCurrent ? records[botID] : nil }

    // MARK: Reading

    /// One read. Its answer is used only while it is the newest read of its key for this account, and (unless
    /// `first`) only when no change to the bot was sent or answered while it was out: an older picture of the
    /// desktop never replaces a change on its way.
    @discardableResult
    private func run<T>(_ key: String, bot: String?, first: Bool,
                        _ fetch: (APIClient) async throws -> T,
                        apply: (T) -> Void,
                        failed: (Error) -> Void) async -> Bool {
        guard active else { return false }
        let account = self.account
        let seq = (seqs[key] ?? 0) + 1
        seqs[key] = seq
        await BotsStore.waitWhileConnecting()
        guard stillLive(account), seqs[key] == seq else { return false }
        let generation = bot.map { writeGeneration[$0] ?? 0 } ?? 0
        do {
            let value = try await fetch(client())
            guard stillLive(account), seqs[key] == seq else { return false }
            if let bot, !first, (writeGeneration[bot] ?? 0) != generation || (writing[bot] ?? 0) > 0 { return false }
            apply(value)
            return true
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), seqs[key] == seq else { return false }
            failed(error)
            return false
        }
    }

    /// A failed read as a load state. A cancelled read is not a failure: the next look reads again.
    private func failure(_ error: Error, _ what: String, was: BotsLiveLoad?) -> BotsLiveLoad {
        if error is CancellationError { return was == .loading ? .idle : (was ?? .idle) }
        return .failed(what + " " + error.plainWords)
    }

    private func prepare(_ state: inout [String: BotsLiveLoad], _ botID: String) {
        if state[botID] != .loaded { state[botID] = .loading }
    }

    /// The bot record. Answers whether the desktop's record was read and shown.
    @discardableResult
    func loadRecord(_ botID: String) async -> Bool {
        followConnection()
        guard active else { return false }
        prepare(&recordLoad, botID)
        let first = records[botID] == nil
        return await run("record|\(botID)", bot: botID, first: first, { try await $0.agentDetail(botID) }, apply: { detail in
            guard let agent = detail.agent else {
                self.recordLoad[botID] = .failed("This bot is not on your desktop.")
                return
            }
            self.records[botID] = agent
            self.recordLoad[botID] = .loaded
            self.unsure[botID] = nil
        }, failed: { error in
            self.recordLoad[botID] = self.failure(error, "This bot could not be read.", was: self.recordLoad[botID])
        })
    }

    func loadRecordIfNeeded(_ botID: String) async {
        followConnection()
        guard active, records[botID] == nil || recordLoad[botID] != .loaded else { return }
        await loadRecord(botID)
    }

    @discardableResult
    func loadSoul(_ botID: String) async -> Bool {
        followConnection()
        guard active else { return false }
        prepare(&soulLoad, botID)
        return await run("soul|\(botID)", bot: botID, first: souls[botID] == nil, { try await $0.botSettingsSoul(botID) }, apply: { soul in
            self.souls[botID] = soul
            self.soulLoad[botID] = .loaded
        }, failed: { error in
            self.soulLoad[botID] = self.failure(error, "The instructions could not be read.", was: self.soulLoad[botID])
        })
    }

    func loadOverview(_ botID: String) async {
        followConnection()
        guard active else { return }
        prepare(&overviewLoad, botID)
        await run("overview|\(botID)", bot: nil, first: true, { try await $0.botSettingsOverview(botID) }, apply: { overview in
            self.overviews[botID] = overview
            self.overviewLoad[botID] = .loaded
        }, failed: { error in
            self.overviewLoad[botID] = self.failure(error, "This bot's overview could not be read.", was: self.overviewLoad[botID])
        })
    }

    @discardableResult
    func loadHistory(_ botID: String) async -> Bool {
        followConnection()
        guard active else { return false }
        prepare(&historyLoad, botID)
        return await run("history|\(botID)", bot: botID, first: histories[botID] == nil, { try await $0.botSettingsHistory(botID) }, apply: { history in
            self.histories[botID] = history
            self.historyLoad[botID] = .loaded
        }, failed: { error in
            self.historyLoad[botID] = self.failure(error, "The history could not be read.", was: self.historyLoad[botID])
        })
    }

    @discardableResult
    func loadPolicy(_ botID: String) async -> Bool {
        followConnection()
        guard active else { return false }
        prepare(&policyLoad, botID)
        return await run("policy|\(botID)", bot: botID, first: policies[botID] == nil, { try await $0.botApprovalPolicy(botID) }, apply: { policy in
            self.policies[botID] = policy
            self.policyLoad[botID] = .loaded
        }, failed: { error in
            self.policyLoad[botID] = self.failure(error, "Approval could not be read.", was: self.policyLoad[botID])
        })
    }

    @discardableResult
    func loadRules(_ botID: String) async -> Bool {
        followConnection()
        guard active else { return false }
        prepare(&rulesLoad, botID)
        return await run("rules|\(botID)", bot: botID, first: rules[botID] == nil, { try await $0.botSettingsCommands(botID) }, apply: { list in
            self.rules[botID] = BotSetWire.items(list.rules).items
            self.rulesLoad[botID] = .loaded
        }, failed: { error in
            self.rulesLoad[botID] = self.failure(error, "The remembered commands could not be read.", was: self.rulesLoad[botID])
        })
    }

    func loadOutbound(_ botID: String) async {
        followConnection()
        guard active else { return }
        await run("outbound|\(botID)", bot: botID, first: outbound[botID] == nil, { try await $0.botSettingsOutbound(botID) }, apply: { usage in
            self.outbound[botID] = usage
        }, failed: { _ in })
    }

    func loadApproval(_ botID: String) async {
        await loadPolicy(botID)
        await loadRules(botID)
        await loadOutbound(botID)
    }

    func loadChoices() async {
        followConnection()
        guard active else { return }
        if choicesLoad != .loaded { choicesLoad = .loading }
        await run("choices", bot: nil, first: true, { try await $0.modelChoices() }, apply: { list in
            self.choices = list
            self.choicesLoad = .loaded
        }, failed: { error in
            self.choicesLoad = self.failure(error, "The models could not be read.", was: self.choicesLoad)
        })
    }

    func loadCatalog(_ endpointID: String) async {
        followConnection()
        guard active, !endpointID.isEmpty else { return }
        await run("catalog|\(endpointID)", bot: nil, first: true, { try await $0.modelCatalog(endpointId: endpointID) }, apply: { list in
            self.catalogs[endpointID] = list
        }, failed: { _ in })
    }

    /// How many of the bot's open conversations use another model than the bot's.
    @discardableResult
    func loadOtherModel(_ botID: String) async -> Bool {
        followConnection()
        guard active else { return false }
        return await run("threads|\(botID)", bot: nil, first: true, { try await $0.agentThreads(botID) }, apply: { list in
            self.otherModel[botID] = (list.threads ?? []).filter { $0.followsBotModel == false && $0.thread?.archivedAt == nil }.count
        }, failed: { _ in })
    }

    func loadModel(_ botID: String) async {
        await loadRecordIfNeeded(botID)
        await loadChoices()
        if let endpoint = records[botID]?.endpointId { await loadCatalog(endpoint) }
        await loadOtherModel(botID)
    }

    func loadVoices() async {
        followConnection()
        guard active else { return }
        if voicesLoad != .loaded { voicesLoad = .loading }
        await run("voices", bot: nil, first: true, { try await $0.botSettingsVoices() }, apply: { list in
            self.voices = BotSetWire.items(list.voices).items
            self.voicesNote = list.error
            self.voicesLoad = .loaded
        }, failed: { error in
            self.voicesLoad = self.failure(error, "The voices could not be read.", was: self.voicesLoad)
        })
        await run("liveVoice", bot: nil, first: true, { try await $0.botSettingsLiveVoice() }, apply: { settings in
            self.liveVoice = settings
        }, failed: { _ in })
    }

    func loadChannels() async {
        followConnection()
        guard active else { return }
        if channelsLoad != .loaded { channelsLoad = .loading }
        await run("channels", bot: nil, first: true, { try await $0.taskChannels() }, apply: { list in
            self.channels = list
            self.channelsLoad = .loaded
        }, failed: { error in
            self.channelsLoad = self.failure(error, "The channels could not be read.", was: self.channelsLoad)
        })
    }

    // MARK: Changing the bot

    /// Send only these fields, with the revision this page read. Shown at once; put back on a refusal; on a
    /// lost answer the desktop is read again and compared with what was sent, and nothing is sent twice.
    func patch(_ botID: String, _ changes: [String: Any], what: String, done: String) async -> BotSetOutcome {
        followConnection()
        guard isCurrent, let before = records[botID] else {
            return .refused("Still reading this bot from your desktop. Try again in a moment.")
        }
        guard !busy.contains(botID) else {
            return .refused("Another change to this bot is still on its way. Try again in a moment.")
        }
        let account = self.account
        var fields = changes
        if let revision = before.revision { fields["expected_revision"] = revision }
        records[botID] = BotSetChange.applying(changes, to: before)
        busy.insert(botID)
        unsure[botID] = nil
        beginWrite(botID)
        do {
            let saved = try await client().agentUpdate(botID, fields: fields)
            endWrite(botID)
            guard stillLive(account) else { return .refused("") }
            records[botID] = saved
            recordLoad[botID] = .loaded
            busy.remove(botID)
            Task { await BotsStore.shared.loadDetail(botID) }
            return .done(done)
        } catch {
            endWrite(botID)
            guard stillLive(account) else { return .refused("") }
            if unconfirmed(error) {
                let read = await loadRecord(botID)
                guard stillLive(account) else { return .refused("") }
                busy.remove(botID)
                if read {
                    Task { await BotsStore.shared.loadDetail(botID) }
                    return BotSetChange.has(records[botID], changes)
                        ? .done("Your desktop's answer was lost, but it has \(what) now.")
                        : .unsure("Your desktop did not answer, and it does not have \(what). Nothing was sent again. This page shows what it has.")
                }
                records[botID] = before
                let note = "Your desktop did not answer, so this iPhone could not confirm \(what). This page shows what your desktop had before. Read it again to check."
                unsure[botID] = note
                return .unsure(note)
            }
            if status(error) == 409 {
                let read = await loadRecord(botID)
                guard stillLive(account) else { return .refused("") }
                if !read { records[botID] = before }
                busy.remove(botID)
                Task { await BotsStore.shared.loadDetail(botID) }
                return .changed("This bot changed on your desktop, so \(what) was not saved. This page now shows what your desktop has.")
            }
            records[botID] = before
            busy.remove(botID)
            return .refused("That change was not saved. " + error.plainWords)
        }
    }

    /// Lower the bot's approval level. Raising is never sent from the phone: the desktop refuses it.
    func lower(_ botID: String, to level: ApprovalLevel) async -> BotSetOutcome {
        followConnection()
        guard isCurrent, let policy = policies[botID] else {
            return .refused("Still reading approval from your desktop. Try again in a moment.")
        }
        guard let current = Self.botLevel(policy), level.rank < current.rank else {
            return .refused("Raise it in Kairos on your desktop.")
        }
        guard !busy.contains(botID) else {
            return .refused("Another change to this bot is still on its way. Try again in a moment.")
        }
        let account = self.account
        busy.insert(botID)
        unsure[botID] = nil
        beginWrite(botID)
        do {
            let answer = try await client().botApprovalSetMode(botID, mode: level.rawValue, scope: "bot", expectedRevision: policy.revision)
            endWrite(botID)
            guard stillLive(account) else { return .refused("") }
            policies[botID] = answer
            busy.remove(botID)
            Task {
                await self.loadRecord(botID)
                await BotsStore.shared.loadDetail(botID)
            }
            return .done("Approval is now \(level.title).")
        } catch {
            endWrite(botID)
            guard stillLive(account) else { return .refused("") }
            if unconfirmed(error) {
                let read = await loadPolicy(botID)
                guard stillLive(account) else { return .refused("") }
                busy.remove(botID)
                if read {
                    Task { await BotsStore.shared.loadDetail(botID) }
                    let now = policies[botID].flatMap(Self.botLevel)
                    return now == level
                        ? .done("Your desktop's answer was lost, but approval is \(level.title) now.")
                        : .unsure("Your desktop did not answer, and approval is still \(now?.title ?? "as it was"). Nothing was sent again.")
                }
                let note = "Your desktop did not answer, so this iPhone could not confirm approval was lowered. Read it again to check."
                unsure[botID] = note
                return .unsure(note)
            }
            if status(error) == 409 {
                await loadPolicy(botID)
                busy.remove(botID)
                return .changed("Approval changed on your desktop, so it was not lowered. This page now shows what your desktop has.")
            }
            busy.remove(botID)
            return .refused("Approval was not changed. " + error.plainWords)
        }
    }

    /// The bot's own level, or nil for one the phone cannot show (Custom).
    static func botLevel(_ policy: BotApprovalPolicyDTO) -> ApprovalLevel? {
        ApprovalLevel(rawValue: policy.botMode ?? policy.mode ?? "")
    }

    /// Forget a remembered command: the bot asks again next time.
    func removeRule(_ botID: String, _ rule: BotSetCommandRuleDTO) async -> BotSetOutcome {
        followConnection()
        guard isCurrent, !removing.contains(rule.id) else { return .refused("") }
        let account = self.account
        removing.insert(rule.id)
        beginWrite(botID)
        defer { if stillLive(account) { removing.remove(rule.id) } }
        do {
            try await client().botSettingsRemoveCommand(botID, ruleID: rule.id)
            endWrite(botID)
            guard stillLive(account) else { return .refused("") }
            rules[botID]?.removeAll { $0.id == rule.id }
            Task { await self.loadPolicy(botID) }
            return .done("It asks again before running that command.")
        } catch {
            endWrite(botID)
            guard stillLive(account) else { return .refused("") }
            if unconfirmed(error) || status(error) == 404 {
                let read = await loadRules(botID)
                guard stillLive(account) else { return .refused("") }
                if read {
                    let gone = !(rules[botID] ?? []).contains { $0.id == rule.id }
                    return gone ? .done("That command is no longer remembered.")
                        : .unsure("Your desktop did not answer, and it still remembers that command. Nothing was sent again.")
                }
                return .unsure("Your desktop did not answer, so this iPhone could not confirm the command was removed.")
            }
            return .refused("The command was not removed. " + error.plainWords)
        }
    }

    /// Put every conversation of the bot back on the bot's own model.
    func followModel(_ botID: String) async -> BotSetOutcome {
        followConnection()
        guard isCurrent, !following.contains(botID) else { return .refused("") }
        let account = self.account
        following.insert(botID)
        defer { if stillLive(account) { following.remove(botID) } }
        do {
            let answer = try await client().botSettingsFollowModel(botID)
            guard stillLive(account) else { return .refused("") }
            await loadOtherModel(botID)
            let moved = answer.updated?.count ?? 0
            let kept = answer.busy?.count ?? 0
            let line = moved == 1 ? "1 conversation now uses this bot's model." : "\(moved) conversations now use this bot's model."
            return .done(kept > 0 ? line + " \(kept) still working kept theirs." : line)
        } catch {
            guard stillLive(account) else { return .refused("") }
            if unconfirmed(error) {
                await loadOtherModel(botID)
                return .unsure("Your desktop did not answer, so this iPhone could not confirm the conversations were switched. This page shows what your desktop has.")
            }
            return .refused("The conversations were not switched. " + error.plainWords)
        }
    }

    /// Put the standing instructions back as they were before this change.
    func rollback(_ botID: String, _ row: BotSetHistoryRowDTO) async -> BotSetOutcome {
        followConnection()
        guard isCurrent, !busy.contains(botID) else {
            return .refused("Another change to this bot is still on its way. Try again in a moment.")
        }
        let account = self.account
        busy.insert(botID)
        unsure[botID] = nil
        // The revision and file text the desktop checks: read now, never from an older page.
        guard await loadSoul(botID), stillLive(account), let soul = souls[botID], let revision = soul.revision else {
            if stillLive(account) { busy.remove(botID) }
            return .refused("The instructions could not be read, so nothing was changed. Try again.")
        }
        beginWrite(botID)
        do {
            let answer = try await client().botSettingsRollback(botID, rowID: row.id, expectedRevision: revision, expectedFileText: soul.fileText)
            endWrite(botID)
            guard stillLive(account) else { return .refused("") }
            if let agent = answer.agent { records[botID] = agent }
            if let file = answer.soulFile { souls[botID] = file }
            busy.remove(botID)
            Task {
                await self.loadHistory(botID)
                await BotsStore.shared.loadDetail(botID)
            }
            return .done("The earlier instructions are back.")
        } catch {
            endWrite(botID)
            guard stillLive(account) else { return .refused("") }
            if unconfirmed(error) {
                // Compare the desktop's instructions with the text this change would put back.
                let full = try? await client().botSettingsHistoryRow(botID, rowID: row.id)
                let read = await loadSoul(botID)
                guard stillLive(account) else { return .refused("") }
                busy.remove(botID)
                await loadHistory(botID)
                await loadRecord(botID)
                if read, let before = full?.before {
                    let back = (souls[botID]?.soul ?? "") == (before.string ?? "")
                    return back ? .done("Your desktop's answer was lost, but the earlier instructions are back.")
                        : .unsure("Your desktop did not answer, and it still has the newer instructions. Nothing was sent again.")
                }
                let note = "Your desktop did not answer, so this iPhone could not confirm the instructions were put back. Read it again to check."
                unsure[botID] = note
                return .unsure(note)
            }
            await loadSoul(botID)
            await loadHistory(botID)
            busy.remove(botID)
            if status(error) == 409 {
                return .changed("The instructions changed on your desktop, so nothing was put back. This page now shows what your desktop has.")
            }
            return .refused("The instructions were not put back. " + error.plainWords)
        }
    }
}

/// A change whose answer was lost and could not be checked: one line and Read again.
struct BotSetUnsureNote: View {
    let botID: String
    var live = BotsSettingsLive.shared

    var body: some View {
        if let note = live.unsure[botID], live.isCurrent {
            VStack(alignment: .leading, spacing: 10) {
                Text(note)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(title: "Read again", symbol: "arrow.clockwise", look: .filled) {
                    Haptics.tap()
                    Task {
                        await live.loadRecord(botID)
                        await live.loadPolicy(botID)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 20)
        }
    }
}
