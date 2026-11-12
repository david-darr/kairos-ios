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

/// The paired desktop behind the Bots area: the roster (GET /api/agents, /api/bot-team/map,
/// /api/agents/conversations), one bot's detail (GET /api/agents/{id}) and its waiting cards
/// (GET /api/bot-cards, POST /api/bot-cards/{id}/respond). Unpaired, nothing here runs.
extension BotsStore {

    /// A key that changes when the phone is paired or unpaired, or the desktop comes back.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)"
    }

    /// Move between sample data and the paired desktop to match the connection.
    func followConnection() {
        let want = !Connection.shared.usesSampleData
        guard want != liveMode else { return }
        if want {
            sampleStash = BotsSampleStash(bots: bots, pinned: pinned, archived: archived, chiefs: chiefs, teams: teams, needs: needs)
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
            liveMode = false
        }
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    // MARK: Roster

    func loadRoster() async {
        guard liveMode else { return }
        if rosterLoad != .loaded { rosterLoad = .loading }
        do {
            let client = try liveClient()
            let roster = try await client.agentRoster()
            let map = try? await client.botTeamMap()
            let conversations = try? await client.agentConversations()
            guard liveMode else { return }
            showRoster(roster, map: map, conversations: conversations)
            rosterLoad = .loaded
        } catch {
            Connection.shared.note(error)
            guard liveMode else { return }
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

    func pinLive(_ botID: String) {
        let wasPinned = pinned.contains(botID)
        if wasPinned { pinned.removeAll { $0 == botID } } else { pinned.append(botID) }
        Task {
            do {
                _ = try await liveClient().agentOrganize(botID, action: wasPinned ? "unpin" : "pin")
                say(wasPinned ? "\(bot(botID).name) is unpinned" : "\(bot(botID).name) is pinned")
            } catch {
                Connection.shared.note(error)
                if wasPinned { if !pinned.contains(botID) { pinned.append(botID) } } else { pinned.removeAll { $0 == botID } }
                say(error.plainWords)
            }
        }
    }

    // MARK: One bot

    func loadDetail(_ botID: String) async {
        guard liveMode else { return }
        if details[botID] == nil { detailLoad[botID] = .loading }
        do {
            let detail = try await liveClient().agentDetail(botID)
            guard liveMode else { return }
            details[botID] = detail
            detailLoad[botID] = .loaded
            if let agent = detail.agent {
                let fresh = Self.liveBot(agent)
                if let index = bots.firstIndex(where: { $0.id == botID }) { bots[index] = fresh }
                liveNeedsYou[botID] = agent.needsYou ?? liveNeedsYou[botID] ?? 0
            }
        } catch {
            Connection.shared.note(error)
            guard liveMode else { return }
            detailLoad[botID] = .failed("This bot could not be read. " + error.plainWords)
        }
    }

    // MARK: Needs you cards

    func loadCards(_ botID: String) async {
        guard liveMode else { return }
        if cardsLoad[botID] != .loaded { cardsLoad[botID] = .loading }
        do {
            let list = try await liveClient().botCards(botId: botID, status: "pending")
            guard liveMode else { return }
            let fresh = (list.cards ?? [])
                .filter { ($0.waiting ?? true) && ($0.kind == "approval" || $0.kind == "question") }
                .compactMap { Self.needsCard($0, botID: botID) }
            let freshIDs = Set(fresh.compactMap { $0.live?.id })
            withAnimation(Motion.snappy) {
                needs.removeAll { $0.botID == botID && ($0.settled == nil || freshIDs.contains($0.live?.id ?? "")) }
                needs.append(contentsOf: fresh)
            }
            cardsLoad[botID] = .loaded
        } catch {
            Connection.shared.note(error)
            guard liveMode else { return }
            cardsLoad[botID] = .failed("What needs you could not be read. " + error.plainWords)
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

    /// Answer a desktop card. The card shows the answer at once and goes back if the desktop refuses.
    /// `answers` is keyed by question id, each a text or a list of texts.
    func respondLive(_ card: NeedsCard, _ result: Settled, answers: [String: Any]? = nil) {
        guard let ref = card.live, let index = needs.firstIndex(where: { $0.id == card.id }) else { return }
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
        withAnimation(Motion.bouncy) { needs[index].settled = result }
        let botID = card.botID
        Task {
            do {
                let answer = try await liveClient().botCardRespond(
                    ref.id, action: action, choiceId: choice, answers: answers, reviewedRevision: ref.revision
                )
                if answer.ok == false {
                    say(answer.message ?? "This was already settled.")
                    await loadCards(botID)
                } else {
                    liveNeedsYou[botID] = max(0, (liveNeedsYou[botID] ?? 1) - 1)
                }
            } catch {
                Connection.shared.note(error)
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
