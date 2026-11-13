import SwiftUI

/// Where a desktop read stands, for one plain sentence on screen.
nonisolated enum BotsLiveLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// The sample roster, kept aside while the phone shows the paired desktop's bots.
struct BotsSampleStash {
    var bots: [Bot]
    var pinned: [String]
    var archived: [Bot]
    var chiefs: Set<String>
    var teams: [BotTeam]
    var needs: [NeedsCard]
}

/// Which account the live roster, detail and cards were read for, and the counters that keep an older read
/// from replacing newer state. Kept here because `BotsStore` (another area's file) holds only the lists.
private enum BotsLiveSession {
    static var account = "sample"
    /// A counter per read ("roster", "detail|<bot>", "cards|<bot>").
    static var reads: [String: Int] = [:]
    /// Writes on their way, and a counter bumped when one is sent or answered.
    static var writing = 0
    static var writeSerial = 0
}

/// Where a desktop card stands after an answer that got no reply.
nonisolated enum BotsCardCheck: Equatable, Sendable {
    /// Reading the cards again: the card says "Not confirmed yet", its buttons off.
    case checking
    /// That read failed: the card says the phone could not check, with Try again.
    case failed
    /// The desktop is still waiting on it: its buttons are back, with a line saying no answer is confirmed.
    case notReceived
    /// The desktop refused the answer because it already settled the card: the card says what the desktop has
    /// (these words) for a moment, then goes.
    case desktopHas(String)
}

/// Desktop cards whose answer is not confirmed, by desktop card id. Such a card never shows Allowed, Rejected or
/// Answered until a read of the desktop's cards says what happened.
@Observable
final class BotsLiveCards {
    static let shared = BotsLiveCards()

    var checks: [String: BotsCardCheck] = [:]
    /// Which bot each checked card belongs to.
    @ObservationIgnored var owners: [String: String] = [:]
    /// Bots whose cards read was set aside while a write was on its way: read again once the last write ends.
    @ObservationIgnored var owed: Set<String> = []
    /// Cards whose answer the desktop refused (409): a look-up of the card, not the waiting list, says what it has.
    @ObservationIgnored var refused: Set<String> = []
    /// How many reads found a checked card still being delivered on the desktop.
    @ObservationIgnored var settlingReads: [String: Int] = [:]
    /// Refused cards being looked up now.
    @ObservationIgnored var lookingUp: Set<String> = []

    func check(_ card: NeedsCard) -> BotsCardCheck? {
        card.live.flatMap { checks[$0.id] }
    }

    /// A card of this bot is still being checked or could not be checked.
    func unsettled(_ botID: String) -> Bool {
        checks.contains { owners[$0.key] == botID && ($0.value == .checking || $0.value == .failed) }
    }

    func clear(_ id: String) {
        checks[id] = nil
        owners[id] = nil
        refused.remove(id)
        settlingReads[id] = nil
    }

    func reset() {
        checks = [:]
        owners = [:]
        owed = []
        refused = []
        settlingReads = [:]
        lookingUp = []
    }
}

extension NeedsCard {
    /// The key a list draws this card under: a desktop card keeps its view (and what was picked or typed on it)
    /// when a read brings it back unchanged.
    nonisolated var viewKey: String {
        guard let live else { return id.uuidString }
        return "\(live.id)|\(live.revision.map { String($0) } ?? "")"
    }
}

/// The paired desktop behind the Bots area: the roster (GET /api/agents, /api/bot-team/map,
/// /api/agents/conversations), one bot's detail (GET /api/agents/{id}) and its waiting cards
/// (GET /api/bot-cards, POST /api/bot-cards/{id}/respond). Unpaired, nothing here runs.
/// The rest of a bot's Inbox half is `BotsInboxLive`.
extension BotsStore {

    /// A key that changes when the phone is paired or unpaired, the desktop comes back,
    /// or a different desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// Which desktop and which account the live bots belong to. Live data is only ever shown under this key.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Still showing the live bots a request was sent for. Checked after every await before writing a result.
    private func stillLive(_ account: String) -> Bool {
        liveMode && BotsLiveSession.account == account && Self.accountKey == account
    }

    /// Move between sample data and the paired desktop to match the connection.
    func followConnection() {
        BotsInboxLive.shared.follow()
        let want = !Connection.shared.usesSampleData
        if want && liveMode && BotsLiveSession.account != Self.accountKey {
            // Another desktop or account: nothing read from the last one may stay on screen.
            resetLive()
        }
        guard want != liveMode else { return }
        if want {
            sampleStash = BotsSampleStash(bots: bots, pinned: pinned, archived: archived, chiefs: chiefs, teams: teams, needs: needs)
            resetLive()
            liveMode = true
        } else {
            if let stash = sampleStash {
                bots = stash.bots
                pinned = stash.pinned
                archived = stash.archived
                chiefs = stash.chiefs
                teams = stash.teams
                needs = stash.needs
            }
            sampleStash = nil
            liveNeedsYou = [:]
            details = [:]
            detailLoad = [:]
            cardsLoad = [:]
            rosterLoad = .idle
            BotsLiveSession.account = "sample"
            BotsLiveSession.reads = [:]
            BotsLiveCards.shared.reset()
            liveMode = false
        }
    }

    /// Every live bot, card and load state goes, ready to read the current account's.
    private func resetLive() {
        bots = []
        pinned = []
        archived = []
        chiefs = []
        teams = []
        needs = []
        liveNeedsYou = [:]
        details = [:]
        detailLoad = [:]
        cardsLoad = [:]
        rosterLoad = .idle
        BotsLiveSession.reads = [:]
        BotsLiveSession.account = Self.accountKey
        BotsLiveCards.shared.reset()
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    /// While the desktop is still being reached at launch, wait for that to settle (at most 20 seconds), so a
    /// read goes out once. Then the read runs whatever the state: an unreachable desktop ends in an error with
    /// Try again, never in a read that does not start. A connection that comes back changes the connection key,
    /// and the screens read again.
    static func waitWhileConnecting() async {
        var waited = 0
        while Connection.shared.state == .connecting, waited < 80, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
    }

    /// Start a read: its account, its serial, and the write counter when it goes out. A cancelled wait is
    /// caught by the read's own `Task.checkCancellation()`. A read whose account changed during the wait (the
    /// phone paired again) does not go out: the client taken right after this belongs to the account read for.
    private func beginRead(_ key: String) async -> (account: String, serial: Int, writes: Int)? {
        guard liveMode else { return nil }
        let account = BotsLiveSession.account
        let serial = (BotsLiveSession.reads[key] ?? 0) + 1
        BotsLiveSession.reads[key] = serial
        await Self.waitWhileConnecting()
        guard stillLive(account) else { return nil }
        return (account, serial, BotsLiveSession.writeSerial)
    }

    /// This read's answer may be shown: same account, no newer read of the same thing, and no write sent or
    /// answered meanwhile (its answer may picture the desktop before that write). `first` takes it anyway:
    /// nothing is on screen yet for it to put back.
    private func current(_ key: String, _ read: (account: String, serial: Int, writes: Int), first: Bool) -> Bool {
        guard stillLive(read.account), BotsLiveSession.reads[key] == read.serial else { return false }
        return first || (BotsLiveSession.writeSerial == read.writes && BotsLiveSession.writing == 0)
    }

    /// This read's error may be shown: same account and no newer read of the same thing.
    private func latest(_ key: String, _ read: (account: String, serial: Int, writes: Int)) -> Bool {
        stillLive(read.account) && BotsLiveSession.reads[key] == read.serial
    }

    private func beginWrite() {
        BotsLiveSession.writing += 1
        BotsLiveSession.writeSerial += 1
    }

    private func endWrite() {
        BotsLiveSession.writing = max(0, BotsLiveSession.writing - 1)
        BotsLiveSession.writeSerial += 1
        let checks = BotsLiveCards.shared
        guard BotsLiveSession.writing == 0, !checks.owed.isEmpty else { return }
        // A cards read was set aside while this write was on its way: read again now.
        let owed = checks.owed
        checks.owed = []
        for botID in owed {
            Task { await loadCards(botID) }
        }
    }

    /// A write whose answer never came: the desktop may have done it. An error that means the request never
    /// left this iPhone is not in doubt; an unreadable answer or a server error is.
    private func unconfirmed(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        guard let api = error as? APIError else { return true }
        switch api {
        case .unreadable: return true
        case .server(let status, _): return status >= 500
        case .offline:
            let neverSent: [URLError.Code] = [.notConnectedToInternet, .cannotFindHost, .secureConnectionFailed,
                                              .appTransportSecurityRequiresSecureConnection]
            return !neverSent.contains { APIError.from(URLError($0)) == api }
        default: return false
        }
    }

    // MARK: Roster

    func loadRoster() async {
        guard liveMode else { return }
        let first = rosterLoad != .loaded
        if first { rosterLoad = .loading }
        guard let read = await beginRead("roster") else { return }
        do {
            try Task.checkCancellation()
            let client = try liveClient()
            let roster = try await client.agentRoster()
            let map = try? await client.botTeamMap()
            let conversations = try? await client.agentConversations()
            guard current("roster", read, first: first) else { return }
            showRoster(roster, map: map, conversations: conversations)
            rosterLoad = .loaded
        } catch {
            guard latest("roster", read) else { return }
            if error is CancellationError {
                // Not read is not failed: the next look reads again.
                if rosterLoad == .loading { rosterLoad = .idle }
                return
            }
            Connection.shared.note(error)
            rosterLoad = .failed("Your bots could not be read. " + error.plainWords)
        }
    }

    private func showRoster(_ roster: [AgentDTO], map: BotTeamMapDTO?, conversations: AgentConversationsDTO?) {
        let sorted = roster.sorted { a, b in
            switch (a.order, b.order) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.createdAt ?? 0) < (b.createdAt ?? 0)
            }
        }
        let shown = sorted.filter { $0.hidden != true }
        bots = shown.map(Self.liveBot)
        archived = sorted.filter { $0.hidden == true }.map(Self.liveBot)
        var counts: [String: Int] = [:]
        for agent in sorted { counts[agent.id] = agent.needsYou ?? 0 }
        liveNeedsYou = counts

        if let conversations {
            let pins = Set((conversations.agents ?? []).filter { $0.pinned == true }.map(\.id))
            pinned = shown.map(\.id).filter { pins.contains($0) }
        }

        if let map {
            let ids = Set(shown.map(\.id))
            let people = map.members ?? map.bots ?? []
            let departments = (map.departments ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }
            teams = departments.map { department in
                let name = department.name ?? "Team"
                var members = people.filter { $0.departmentId == department.id }.map(\.id)
                if members.isEmpty {
                    members = shown.filter { $0.section == name }.map(\.id)
                }
                return BotTeam(
                    id: department.id,
                    name: name,
                    department: "",
                    members: members.filter { ids.contains($0) },
                    chief: department.chiefBotId,
                    instructions: ""
                )
            }
            chiefs = Set(departments.compactMap(\.chiefBotId))
        }
    }

    /// A desktop bot in the Bots area's own shape.
    static func liveBot(_ agent: AgentDTO) -> Bot {
        let role = [agent.role, agent.blurb].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        return Bot(
            id: agent.id,
            name: (agent.name?.isEmpty == false ? agent.name : nil) ?? "Bot",
            role: role ?? "No job yet",
            colorHex: agent.bodyColorHex,
            status: agent.botStatus,
            shape: agent.mascotShape,
            accessory: agent.mascotAccessory,
            isKip: agent.isFrontDesk,
            model: liveModel(agent),
            approval: liveApproval(agent)?.longTitle ?? "Its own approval rules"
        )
    }

    static func liveModel(_ agent: AgentDTO) -> String {
        let name = agent.modelOverride?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Default model" : name
    }

    static func liveApproval(_ agent: AgentDTO) -> ApprovalLevel? {
        ApprovalLevel(rawValue: agent.approvalMode ?? "ask")
    }

    /// Pin or unpin a bot. Shown at once; put back if the desktop refuses; re-read when the answer is lost.
    func pinLive(_ botID: String) {
        guard liveMode else { return }
        guard BotsLiveSession.account == Self.accountKey else {
            say("Still reading your desktop. Try again in a moment.")
            return
        }
        let account = BotsLiveSession.account
        // The client of the pairing this was tapped under, taken now: a later pairing never gets this request.
        guard let client = Connection.shared.client else {
            say(APIError.notPaired.plain)
            return
        }
        let wasPinned = pinned.contains(botID)
        let name = bot(botID).name
        if wasPinned { pinned.removeAll { $0 == botID } } else { pinned.append(botID) }
        beginWrite()
        Task {
            do {
                _ = try await client.agentOrganize(botID, action: wasPinned ? "unpin" : "pin")
                endWrite()
                guard stillLive(account) else { return }
                say(wasPinned ? "\(name) is unpinned" : "\(name) is pinned")
            } catch {
                endWrite()
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say("Your desktop did not answer, so this iPhone could not confirm \(name) was \(wasPinned ? "unpinned" : "pinned"). This list shows what your desktop has.")
                    await loadRoster()
                    return
                }
                Connection.shared.note(error)
                if wasPinned { if !pinned.contains(botID) { pinned.append(botID) } } else { pinned.removeAll { $0 == botID } }
                say(error.plainWords)
            }
        }
    }

    // MARK: One bot

    func loadDetail(_ botID: String) async {
        guard liveMode else { return }
        let first = details[botID] == nil
        if first { detailLoad[botID] = .loading }
        let key = "detail|\(botID)"
        guard let read = await beginRead(key) else { return }
        do {
            try Task.checkCancellation()
            let detail = try await liveClient().agentDetail(botID)
            guard current(key, read, first: first) else { return }
            details[botID] = detail
            detailLoad[botID] = .loaded
            if let agent = detail.agent {
                let fresh = Self.liveBot(agent)
                if let index = bots.firstIndex(where: { $0.id == botID }) { bots[index] = fresh }
                liveNeedsYou[botID] = agent.needsYou ?? liveNeedsYou[botID] ?? 0
            }
        } catch {
            guard latest(key, read) else { return }
            if error is CancellationError {
                if detailLoad[botID] == .loading { detailLoad[botID] = .idle }
                return
            }
            Connection.shared.note(error)
            detailLoad[botID] = .failed("This bot could not be read. " + error.plainWords)
        }
    }

    // MARK: Needs you cards

    func loadCards(_ botID: String) async {
        guard liveMode else { return }
        let first = cardsLoad[botID] != .loaded
        if first { cardsLoad[botID] = .loading }
        let key = "cards|\(botID)"
        guard let read = await beginRead(key) else { return }
        do {
            try Task.checkCancellation()
            let list = try await liveClient().botCards(botId: botID, status: "pending")
            guard current(key, read, first: first) else {
                readCardsLater(botID, key: key, read: read)
                return
            }
            let fresh = (list.cards ?? [])
                .filter { ($0.waiting ?? true) && ($0.kind == "approval" || $0.kind == "question") }
                .compactMap { Self.needsCard($0, botID: botID) }
            let freshIDs = Set(fresh.compactMap { $0.live?.id })
            let settlingIDs = Set((list.cards ?? []).filter { $0.status == "settling" }.map(\.id))
            let (gone, holding, lookUps) = settleChecks(botID, waiting: freshIDs, settling: settlingIDs)
            // A checked card whose answer the desktop is still delivering keeps its "Not confirmed yet" line.
            let kept = Set(needs.filter { $0.botID == botID && $0.settled != nil }.compactMap { $0.live?.id })
                .intersection(holding)
            withAnimation(Motion.snappy) {
                needs.removeAll { card in
                    guard card.botID == botID else { return false }
                    let id = card.live?.id ?? ""
                    if kept.contains(id) { return false }
                    return card.settled == nil || freshIDs.contains(id) || gone.contains(id)
                }
                needs.append(contentsOf: kept.isEmpty ? fresh : fresh.filter { !kept.contains($0.live?.id ?? "") })
            }
            cardsLoad[botID] = .loaded
            if !gone.isEmpty {
                say(gone.count == 1 ? "Your desktop is no longer waiting on that request."
                                    : "Your desktop is no longer waiting on those requests.")
            }
            for id in lookUps {
                Task { await lookUpRefused(id, botID: botID, account: read.account, refusal: "") }
            }
            if !holding.isEmpty {
                // Read again shortly (a read only) until the desktop says how the delivery ended.
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    let checks = BotsLiveCards.shared
                    guard stillLive(read.account),
                          checks.checks.contains(where: { checks.owners[$0.key] == botID && $0.value == .checking })
                    else { return }
                    await loadCards(botID)
                }
            }
        } catch {
            guard latest(key, read) else { return }
            if error is CancellationError {
                if cardsLoad[botID] == .loading { cardsLoad[botID] = .idle }
                // A card still being checked must not wait for a read that never comes: hand the check on.
                readCardsLater(botID, key: key, read: read)
                return
            }
            Connection.shared.note(error)
            let checks = BotsLiveCards.shared
            for (id, state) in checks.checks where state == .checking && checks.owners[id] == botID {
                checks.checks[id] = .failed
            }
            cardsLoad[botID] = .failed("What needs you could not be read. " + error.plainWords)
        }
    }

    /// A read of the desktop's cards landed: each unconfirmed card of this bot learns what happened. Still being
    /// delivered on the desktop ("settling"), it stays "Not confirmed yet" and is read again shortly; still waiting,
    /// its buttons come back (with a line saying no answer is confirmed); no longer waiting, it goes. A card the
    /// desktop refused and no longer waiting is looked up, to say what the desktop has. Returns the desktop ids of
    /// the cards that go, of those still being delivered, and of those to look up.
    private func settleChecks(_ botID: String, waiting: Set<String>, settling: Set<String>)
        -> (gone: Set<String>, holding: Set<String>, lookUps: Set<String>) {
        let checks = BotsLiveCards.shared
        var gone: Set<String> = []
        var holding: Set<String> = []
        var lookUps: Set<String> = []
        for (id, state) in checks.checks where checks.owners[id] == botID {
            if case .desktopHas = state { continue }
            if waiting.contains(id) {
                if settling.contains(id), state != .notReceived {
                    let reads = (checks.settlingReads[id] ?? 0) + 1
                    checks.settlingReads[id] = reads
                    if reads > 15 {
                        // About half a minute and still delivering: stop reading by itself, offer Try again
                        // (which starts the count again).
                        if state != .failed { checks.checks[id] = .failed }
                    } else {
                        if state != .checking { checks.checks[id] = .checking }
                    }
                    holding.insert(id)
                } else {
                    checks.refused.remove(id)
                    checks.settlingReads[id] = nil
                    if state != .notReceived { checks.checks[id] = .notReceived }
                }
            } else if checks.refused.contains(id) {
                if state == .checking, !checks.lookingUp.contains(id) { lookUps.insert(id) }
            } else {
                if state != .notReceived { gone.insert(id) }
                checks.clear(id)
            }
        }
        return (gone, holding, lookUps)
    }

    /// A cards read set aside because a write was sent or answered meanwhile. While a card of this bot is not
    /// confirmed, read again: now when no write is on its way, or once the last one ends.
    private func readCardsLater(_ botID: String, key: String, read: (account: String, serial: Int, writes: Int)) {
        guard latest(key, read), BotsLiveCards.shared.unsettled(botID) else { return }
        if BotsLiveSession.writing == 0 {
            Task { await loadCards(botID) }
        } else {
            BotsLiveCards.shared.owed.insert(botID)
        }
    }

    /// Try again on a card that could not be checked: read the desktop's cards again. Nothing is sent.
    func recheckCard(_ card: NeedsCard) {
        guard liveMode, let id = card.live?.id, BotsLiveCards.shared.checks[id] == .failed else { return }
        let checks = BotsLiveCards.shared
        checks.checks[id] = .checking
        checks.settlingReads[id] = nil
        if checks.refused.contains(id) {
            let account = BotsLiveSession.account
            Task { await lookUpRefused(id, botID: card.botID, account: account, refusal: "") }
        } else {
            Task { await loadCards(card.botID) }
        }
    }

    /// The desktop refused an answer (409): the card was already settled, another answer was being delivered, or
    /// its details changed. The refusal's body names the card, but this app's client keeps only its sentence, so
    /// the card is read again (a read only, nothing is sent). Settled on the desktop, the card says what the
    /// desktop has, then goes. Still being delivered, it stays "Not confirmed yet" and is read until that ends.
    /// Open again, its buttons come back with the desktop's sentence. A failed read offers Try again.
    private func lookUpRefused(_ id: String, botID: String, account: String, refusal: String) async {
        let checks = BotsLiveCards.shared
        guard !checks.lookingUp.contains(id) else { return }
        checks.lookingUp.insert(id)
        defer { checks.lookingUp.remove(id) }
        let found: BotCardDTO?
        do {
            await Self.waitWhileConnecting()
            try Task.checkCancellation()
            guard stillLive(account) else { return }
            let client = try liveClient()
            let list = try await client.botCards(botId: botID)
            guard stillLive(account), checks.refused.contains(id) else { return }
            found = (list.cards ?? []).first { $0.id == id }
        } catch {
            guard stillLive(account), checks.refused.contains(id) else { return }
            if !(error is CancellationError) { Connection.shared.note(error) }
            withAnimation(Motion.snappy) { checks.checks[id] = .failed }
            return
        }
        switch found?.status ?? "" {
        case "pending":
            checks.clear(id)
            if let back = needs.firstIndex(where: { $0.live?.id == id }) {
                withAnimation(Motion.snappy) { needs[back].settled = nil }
            }
            say(refusal.isEmpty ? "Your desktop is waiting on this again." : refusal)
            await loadCards(botID)
        case "settling":
            // An answer is still being delivered: the ordinary check follows it from here.
            checks.refused.remove(id)
            await loadCards(botID)
        default:
            withAnimation(Motion.snappy) { checks.checks[id] = .desktopHas(Self.desktopHas(found)) }
            try? await Task.sleep(for: .seconds(6))
            guard stillLive(account), case .desktopHas? = checks.checks[id] else { return }
            checks.clear(id)
            // A card that came back with its buttons in the meantime is a fresh request: it stays.
            withAnimation(Motion.snappy) { needs.removeAll { $0.live?.id == id && $0.settled != nil } }
        }
    }

    /// What the desktop has for a card it settled, in one sentence.
    static func desktopHas(_ card: BotCardDTO?) -> String {
        guard let card else { return "Your desktop no longer has this request." }
        let label = card.outcome?.label?.trimmingCharacters(in: .whitespaces) ?? ""
        switch card.status ?? "" {
        case "allowed":
            return label.isEmpty ? "Your desktop already has this as Allowed."
                                 : "Your desktop already has this as Allowed (\(label))."
        case "denied": return "Your desktop already has this as Rejected. The action did not run."
        case "answered": return "Your desktop already has this as Answered."
        case "skipped": return "Your desktop already has this as Skipped."
        case "expired": return "Your desktop already closed this. It ran out of time."
        default: return "Your desktop already closed this. It is no longer waiting."
        }
    }

    static func needsCard(_ card: BotCardDTO, botID: String) -> NeedsCard? {
        let age = card.createdAt.map { ChatFormat.listTime(Date(timeIntervalSince1970: $0)) } ?? ""
        var ref = LiveCardRef(id: card.id, revision: card.revision)
        for choice in card.choices ?? [] {
            guard let id = choice.id else { continue }
            if choice.behavior == "deny" {
                if ref.denyChoice == nil { ref.denyChoice = id }
            } else if let scope = choice.scope, ref.allowScopes[scope] == nil {
                ref.allowScopes[scope] = id
            }
        }
        let kind: NeedsCard.Kind
        if card.kind == "question" {
            let questions = (card.questions ?? []).enumerated().compactMap { index, question -> BotQuestion? in
                guard let key = question.id, let prompt = question.question else { return nil }
                let header = question.header?.trimmingCharacters(in: .whitespaces) ?? ""
                return BotQuestion(
                    tab: header.isEmpty ? "Question \(index + 1)" : header,
                    prompt: prompt,
                    options: (question.options ?? []).compactMap { option in
                        option.label.map { QuestionOption(title: $0, detail: option.description ?? "") }
                    },
                    multi: question.multiSelect ?? false,
                    key: key,
                    allowsOther: question.allowCustom ?? true
                )
            }
            guard !questions.isEmpty else { return nil }
            kind = .question(questions)
        } else {
            let details = card.details
            let lines = (details?.lines ?? []).compactMap { line -> String? in
                switch (line.label, line.value) {
                case let (label?, value?): return "\(label): \(value)"
                case let (nil, value?): return value
                case let (label?, nil): return label
                default: return nil
                }
            }
            kind = .approval(
                title: card.title ?? "A request",
                summary: details?.summary ?? "",
                covers: details?.target ?? details?.tool ?? "this request",
                details: lines
            )
        }
        return NeedsCard(botID: card.botId ?? botID, kind: kind, age: age, live: ref)
    }

    /// Whether a desktop approval card offers this way to allow.
    func offers(_ card: NeedsCard, _ result: Settled) -> Bool {
        guard let ref = card.live else { return true }
        switch result {
        case .allowedOnce, .denied: return true
        case .allowedChat: return ref.allowScopes["session"] != nil
        case .allowedTeam: return ref.allowScopes["team"] != nil
        default: return false
        }
    }

    /// Answer a desktop card. The card shows the answer at once (its buttons go away). A refusal puts it back
    /// and says why. A lost answer never shows as done: the card says it is not confirmed yet, its buttons stay
    /// off, and the cards are read again. Then the card goes when the desktop is no longer waiting on it, or its
    /// buttons come back when it still is. Nothing is sent again by itself.
    /// `answers` is keyed by question id, each a text or a list of texts.
    func respondLive(_ card: NeedsCard, _ result: Settled, answers: [String: Any]? = nil) {
        guard liveMode, let ref = card.live, let index = needs.firstIndex(where: { $0.id == card.id }),
              needs[index].settled == nil else { return }
        guard BotsLiveSession.account == Self.accountKey else {
            say("Still reading your desktop. Try again in a moment.")
            return
        }
        var action = ""
        var choice: String?
        switch result {
        case .denied: action = "deny"; choice = ref.denyChoice
        case .allowedOnce: action = "allow"; choice = ref.allowScopes["once"]
        case .allowedChat: action = "allow"; choice = ref.allowScopes["session"]
        case .allowedTeam: action = "allow"; choice = ref.allowScopes["team"]
        case .answered: action = "answer"
        case .skipped: action = "skip"
        default:
            say("Answer this one on your desktop.")
            return
        }
        if action == "allow", result != .allowedOnce, choice == nil {
            say("That way to allow is not offered for this request.")
            return
        }
        let account = BotsLiveSession.account
        // The client of the pairing this was tapped under, taken now: a later pairing never gets this answer.
        guard let client = Connection.shared.client else {
            say(APIError.notPaired.plain)
            return
        }
        BotsLiveCards.shared.clear(ref.id)
        withAnimation(Motion.bouncy) { needs[index].settled = result }
        let botID = card.botID
        beginWrite()
        Task {
            do {
                let answer = try await client.botCardRespond(
                    ref.id, action: action, choiceId: choice, answers: answers, reviewedRevision: ref.revision
                )
                endWrite()
                guard stillLive(account) else { return }
                if answer.ok == false {
                    say(answer.message ?? "This was already settled.")
                    await loadCards(botID)
                } else {
                    liveNeedsYou[botID] = max(0, (liveNeedsYou[botID] ?? 1) - 1)
                }
            } catch {
                endWrite()
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    if let api = error as? APIError, api != APIError.from(URLError(.timedOut)) { Connection.shared.note(api) }
                    // Not shown as done: the card says it is checking until a read of the cards says what happened.
                    let checks = BotsLiveCards.shared
                    withAnimation(Motion.snappy) { checks.checks[ref.id] = .checking }
                    checks.owners[ref.id] = botID
                    await loadCards(botID)
                    return
                }
                Connection.shared.note(error)
                if case .server(status: 409, _) = error as? APIError {
                    // Refused because of where the card stands on the desktop: its buttons stay off and the card
                    // says what the desktop has once it is read, never just "already settled" and gone.
                    let checks = BotsLiveCards.shared
                    checks.refused.insert(ref.id)
                    checks.owners[ref.id] = botID
                    withAnimation(Motion.snappy) { checks.checks[ref.id] = .checking }
                    await lookUpRefused(ref.id, botID: botID, account: account, refusal: error.plainWords)
                    return
                }
                if let back = needs.firstIndex(where: { $0.id == card.id }) {
                    withAnimation(Motion.snappy) { needs[back].settled = nil }
                }
                say(error.plainWords)
                await loadCards(botID)
            }
        }
    }
}

// MARK: - Shared pieces

/// A desktop read that is on its way or failed: one plain sentence, and Try again when it failed.
struct BotsLoadNote: View {
    let state: BotsLiveLoad
    var waiting = "Reading your desktop."
    let retry: () -> Void

    var body: some View {
        switch state {
        case .loading:
            HintLine(text: waiting, symbol: "arrow.down.circle")
                .padding(.horizontal, 4)
        case .failed(let text):
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(title: "Try again", symbol: "arrow.clockwise", look: .filled) {
                    Haptics.tap()
                    retry()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 20)
        case .idle, .loaded:
            EmptyView()
        }
    }
}

/// The quiet line on a Bots screen that still shows sample data while the phone is paired.
struct BotsSampleNote: View {
    var body: some View {
        if !Connection.shared.usesSampleData {
            HintLine(text: "This part is not connected to your desktop yet. It shows sample data.", symbol: "info.circle")
                .padding(.horizontal, 4)
        }
    }
}
