import SwiftUI

// The paired desktop behind teams (routes/bot_department_routes.py, routes/bot_team_routes.py, the team report in
// routes/bot_activity_routes.py). Unpaired, nothing here runs and the team screens show BotsStore's samples.
// Everything read here belongs to one desktop and one account; a result that lands for another is dropped.
//
// What the desktop does, read from services/bot_departments.py and core/bot_policy.py:
// - Pause team: every step of the team's bots that is not a read is refused until it is resumed. Asking the person
//   and reaching the person (message, ring, text) still work. Every approval the team's bots are waiting on is
//   cancelled at once. Routines keep their schedule; their steps are held like any other. The pause is found by
//   looking up each bot's team, so a bot in no team is never held.
// - Rename: every member's `section` moves to the new name. Refused while one of its bots is working.
// - Delete: the team goes and every member's `section` is cleared, hidden members too, so its bots are in no team
//   and a pause no longer holds them. Their conversations and routines stay. Refused while one of its bots is working.
// - Chief (set_chief): no revision check. With a bot it saves `also_manages` exactly as sent; with none it saves an
//   empty list. So the phone reads the team fresh right before it sends, and sends the list from that read.
//
// Which write touches what (a read that began before a write it overlaps is never shown over that write):
// "team|<id>" (pause, rename, chief, delete), "report|<id>" (rename, delete), "instructions|<id>", "memory|<id>".

/// How a team write the screen waits on came back.
nonisolated enum BotTmOutcome: Equatable, Sendable {
    case done(String)
    /// Nothing changed. What was typed stays and can be sent.
    case refused(String)
    /// It changed on the desktop (409): read again, what was typed stays.
    case changed(String)
    /// The answer was lost and a read did not settle it: look again before anything is sent again.
    case unsure(String)
}

/// A team read fresh for the Delete team confirm.
nonisolated enum BotTmTeamCheck: Equatable, Sendable {
    /// Every member (hidden ones too) and whether the team is paused.
    case read(members: Int, paused: Bool)
    case failed(String)
    /// Cancelled or overtaken: nothing to say.
    case dropped
}

/// Plain mapping from the desktop's words to the phone's.
nonisolated enum BotTmMap {
    /// A live hand-off in the Bots area's own shape, with the room it happens in.
    static func handoff(_ edge: BotTmHandoffDTO) -> Handoff? {
        guard let from = edge.sourceBotId, let to = edge.targetBotId else { return nil }
        let reason = (edge.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Handoff(from: from, to: to, verb: "Delegated", reason: reason.isEmpty ? "Delegated work" : reason,
                       status: status(edge.status))
    }

    static func status(_ word: String?) -> String {
        switch word ?? "" {
        case "running": "Working"
        case "needs_input": "Waiting for you"
        case "waiting": "Waiting"
        case "queued", "resume": "Queued"
        default: "In progress"
        }
    }

    /// The memory kinds, in the order the sheet shows them.
    static let kinds = ["person", "place", "decision", "term"]

    static func kindTitle(_ kind: String?) -> String {
        switch kind ?? "" {
        case "person": "People"
        case "place": "Places"
        case "decision": "Decisions"
        case "term": "Terms"
        default: "Other"
        }
    }

    static func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The Pause team confirm, in what the desktop really does.
    static let pauseDetail = "Its bots can still read and ask you things. Every other step they try is refused until you resume the team, and anything they are waiting on you to approve is cancelled now."

    /// The chief's other teams are stored in a shape this app cannot read: the chief is not changed from here.
    static let chiefListUnreadable = "Change the chief in Kairos on your desktop. Your desktop keeps the other teams this chief manages in a form this app cannot read, so changing the chief here could lose them."

    /// The Delete team confirm, in what the desktop really does (bot_departments.py: delete; bot_policy.py: the pause
    /// is looked up through each bot's team).
    static func deleteDetail(members: Int, paused: Bool) -> String {
        let who: String
        switch members {
        case 0: who = "The team goes."
        case 1: who = "Its bot leaves the team and is in no team."
        default: who = "Its \(members) bots leave the team and are in no team."
        }
        var text = who + " They keep their conversations and routines. The team's instructions and memory stop being used."
        if paused {
            text += " The team is paused: once it is deleted, its bots are no longer held by the pause and can act again."
        }
        return text + " Your desktop refuses while one of its bots is working."
    }
}

/// A memory entry sent whose answer was lost: what to look for before anything is added again.
nonisolated struct BotTmAddCheck: Equatable, Sendable {
    var kind: String
    var name: String
    var detail: String
    var before: Set<String>
}

@Observable
final class BotsTeamsLive {
    static let shared = BotsTeamsLive()

    /// Every team record of this account, by id, with its pause switch and revision.
    var departments: [String: BotTmDepartmentDTO] = [:]
    var rooms: [BotRoomDTO] = []
    var handoffs: [BotTmHandoffDTO] = []
    var mapLoad: BotsLiveLoad = .idle
    /// Teams with a write on its way: their controls wait.
    var busy: Set<String> = []

    var instructions: [String: BotTmInstructionsDTO] = [:]
    var instructionsLoad: [String: BotsLiveLoad] = [:]
    var memory: [String: [BotTmMemoryEntryDTO]] = [:]
    var memoryLoad: [String: BotsLiveLoad] = [:]
    var skippedMemory: [String: Int] = [:]
    /// Memory entries being deleted.
    var deleting: Set<String> = []
    /// A memory add whose answer was lost, by team.
    var addChecks: [String: BotTmAddCheck] = [:]

    /// Team reports by "team id|days".
    var reports: [String: BotTmReportDTO] = [:]
    var reportLoad: [String: BotsLiveLoad] = [:]

    @ObservationIgnored private var account = "sample"
    /// Bumped when a write that touches the key is sent and again when it is answered.
    @ObservationIgnored private var touched: [String: Int] = [:]
    /// Writes on their way, by the key they touch.
    @ObservationIgnored private var inFlight: [String: Int] = [:]
    @ObservationIgnored private var mapSeq = 0
    @ObservationIgnored private var mapKey = ""
    @ObservationIgnored private var mapReading = 0
    @ObservationIgnored private var readSeq: [String: Int] = [:]

    // MARK: Which desktop

    var active: Bool { !Connection.shared.usesSampleData }

    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// Match the connection: another desktop or account, or unpairing, drops everything read before.
    func followConnection() {
        let want = active ? Self.accountKey : "sample"
        guard want != account else { return }
        reset()
        account = want
    }

    private func reset() {
        departments = [:]
        rooms = []
        handoffs = []
        mapLoad = .idle
        busy = []
        instructions = [:]
        instructionsLoad = [:]
        memory = [:]
        memoryLoad = [:]
        skippedMemory = [:]
        deleting = []
        addChecks = [:]
        reports = [:]
        reportLoad = [:]
        touched = [:]
        inFlight = [:]
        mapSeq += 1
        mapKey = ""
        mapReading = 0
        readSeq = [:]
    }

    private func stillLive(_ account: String) -> Bool {
        active && self.account == account && Self.accountKey == account
    }

    private func client() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    private func teamKeys(_ teamID: String) -> [String] { ["team|\(teamID)", "report|\(teamID)"] }

    private func beginWrite(_ keys: [String]) {
        for key in keys {
            touched[key, default: 0] += 1
            inFlight[key, default: 0] += 1
        }
    }

    private func endWrite(_ keys: [String]) {
        for key in keys {
            touched[key, default: 0] += 1
            inFlight[key] = max(0, (inFlight[key] ?? 0) - 1)
        }
    }

    /// No write touched this key since a read stamped it, and none is on its way.
    private func untouched(_ key: String, since stamp: Int) -> Bool {
        (touched[key] ?? 0) == stamp && (inFlight[key] ?? 0) == 0
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

    private func words(_ error: Error) -> String { (error as? APIError)?.plain ?? error.plainWords }

    private func nextSeq(_ key: String) -> Int {
        let seq = (readSeq[key] ?? 0) + 1
        readSeq[key] = seq
        return seq
    }

    // MARK: What the screens ask

    /// What was read belongs to the desktop and account paired right now.
    var isCurrent: Bool { active && account == Self.accountKey }

    func department(_ teamID: String) -> BotTmDepartmentDTO? { isCurrent ? departments[teamID] : nil }

    func paused(_ teamID: String) -> Bool { department(teamID)?.paused ?? false }

    /// The chief as the desktop's team record has it.
    func chief(_ teamID: String) -> String? { department(teamID)?.chiefBotId }

    func waits(_ teamID: String) -> Bool { busy.contains(teamID) || department(teamID) == nil }

    var shownRooms: [BotRoomDTO] { isCurrent ? rooms : [] }

    var shownHandoffs: [BotTmHandoffDTO] { isCurrent ? handoffs : [] }

    func shown(_ state: BotsLiveLoad?) -> BotsLiveLoad {
        guard isCurrent, let state else { return .loading }
        return state == .idle ? .loading : state
    }

    var mapReady: Bool { isCurrent && (mapLoad == .loaded || !departments.isEmpty) }

    /// The line a team screen shows about the map: reading, failed (also when older teams stay shown), or nothing.
    var mapNote: BotsLiveLoad {
        guard isCurrent else { return .loading }
        if case .failed = mapLoad { return mapLoad }
        return mapReady ? .loaded : shown(mapLoad)
    }

    /// The name of another team, for the chief confirm.
    func teamName(_ teamID: String) -> String? { department(teamID)?.name }

    // MARK: Reading

    /// Read the map again: each time a team screen or sheet appears, and when the connection becomes ready. What is
    /// shown stays while it reads. A read for this same connection already on its way is not started twice.
    func refreshMap() async {
        followConnection()
        guard active else { return }
        if mapReading > 0 && mapKey == Self.connectionKey { return }
        // Its own task: the connection settling restarts the screen's task, and that must not cut this read short.
        await Task { await self.loadMap() }.value
    }

    /// Read every team, room and hand-off. Answers whether the desktop's map was read and shown. A team that a write
    /// touched while this read was on its way keeps what the write left; every other team is replaced.
    @discardableResult
    func loadMap() async -> Bool {
        guard active else { return false }
        let account = self.account
        mapSeq += 1
        let seq = mapSeq
        mapKey = Self.connectionKey
        let stamps = touched
        mapReading += 1
        defer { if stillLive(account) { mapReading = max(0, mapReading - 1) } }
        if mapLoad != .loaded && departments.isEmpty { mapLoad = .loading }
        do {
            let map = try await client().botTeamLiveMap()
            guard stillLive(account), seq == mapSeq else { return false }
            var found: [String: BotTmDepartmentDTO] = [:]
            for team in BotLossyList(map.departments).items { found[team.id] = team }
            var next = departments
            for id in Set(next.keys).union(found.keys) {
                let key = "team|\(id)"
                guard untouched(key, since: stamps[key] ?? 0) else { continue }
                next[id] = found[id]
            }
            departments = next
            rooms = BotLossyList(map.rooms).items.filter { $0.archivedAt == nil }
            handoffs = BotLossyList(map.handoffs).items
            mapLoad = .loaded
            return true
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), seq == mapSeq else { return false }
            if error is CancellationError {
                if mapLoad == .loading { mapLoad = .idle }
            } else if departments.isEmpty {
                mapLoad = .failed("Your teams could not be read. " + error.plainWords)
            } else {
                mapLoad = .failed("Your teams could not be read just now, so what shows here may be out of date. " + error.plainWords)
            }
            return false
        }
    }

    /// After a change the desktop confirmed: the team map here and the roster the other screens read. Answers
    /// whether the map was read.
    @discardableResult
    private func afterChange(_ account: String) async -> Bool {
        guard stillLive(account) else { return false }
        let read = await loadMap()
        guard stillLive(account) else { return false }
        await BotsStore.shared.loadRoster()
        return read
    }

    /// The team's instructions. `.loaded` when this read is now shown, `.failed` with the words to show,
    /// `.idle` when it was cancelled, overtaken, or began before a save it overlapped.
    @discardableResult
    func loadInstructions(_ teamID: String) async -> BotsLiveLoad {
        guard active else { return .idle }
        let account = self.account
        let key = "instructions|\(teamID)"
        let seq = nextSeq(key)
        let stamp = touched[key] ?? 0
        if instructionsLoad[teamID] != .loaded { instructionsLoad[teamID] = .loading }
        do {
            let fresh = try await client().botTeamInstructions(teamID)
            guard stillLive(account), readSeq[key] == seq else { return .idle }
            guard untouched(key, since: stamp) else {
                if instructionsLoad[teamID] == .loading { instructionsLoad[teamID] = .idle }
                return .idle
            }
            instructions[teamID] = fresh
            instructionsLoad[teamID] = .loaded
            return .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), readSeq[key] == seq else { return .idle }
            if error is CancellationError {
                if instructionsLoad[teamID] == .loading { instructionsLoad[teamID] = .idle }
                return .idle
            }
            let words = status(error) == 404 ? "This team is not on your desktop any more."
                                             : "The team's instructions could not be read. " + error.plainWords
            if instructionsLoad[teamID] != .loaded { instructionsLoad[teamID] = .failed(words) }
            return .failed(words)
        }
    }

    /// The team's memory, answered like `loadInstructions`.
    @discardableResult
    func loadMemory(_ teamID: String) async -> BotsLiveLoad {
        guard active else { return .idle }
        let account = self.account
        let key = "memory|\(teamID)"
        let seq = nextSeq(key)
        let stamp = touched[key] ?? 0
        if memoryLoad[teamID] != .loaded { memoryLoad[teamID] = .loading }
        do {
            let list = try await client().botTeamMemory(teamID)
            guard stillLive(account), readSeq[key] == seq else { return .idle }
            guard untouched(key, since: stamp) else {
                if memoryLoad[teamID] == .loading { memoryLoad[teamID] = .idle }
                return .idle
            }
            let read = BotLossyList(list.entries)
            memory[teamID] = read.items
            skippedMemory[teamID] = read.skipped
            memoryLoad[teamID] = .loaded
            return .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), readSeq[key] == seq else { return .idle }
            if error is CancellationError {
                if memoryLoad[teamID] == .loading { memoryLoad[teamID] = .idle }
                return .idle
            }
            let words = status(error) == 404 ? "This team is not on your desktop any more."
                                             : "The team's memory could not be read. " + error.plainWords
            if memoryLoad[teamID] != .loaded { memoryLoad[teamID] = .failed(words) }
            return .failed(words)
        }
    }

    func loadReport(_ teamID: String, days: Int) async {
        guard active else { return }
        let account = self.account
        let key = "\(teamID)|\(days)"
        let gate = "report|\(teamID)"
        let seq = nextSeq("report|" + key)
        let stamp = touched[gate] ?? 0
        if reportLoad[key] != .loaded { reportLoad[key] = .loading }
        do {
            let report = try await client().botTeamReport(teamID, days: days)
            guard stillLive(account), readSeq["report|" + key] == seq else { return }
            // A rename or delete overlapped this read: keep what is shown; with nothing shown yet, show it.
            guard untouched(gate, since: stamp) || reports[key] == nil else { return }
            reports[key] = report
            reportLoad[key] = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), readSeq["report|" + key] == seq else { return }
            if error is CancellationError {
                if reportLoad[key] == .loading { reportLoad[key] = .idle }
            } else {
                reportLoad[key] = .failed(status(error) == 404 ? "This team is not on your desktop any more."
                                                               : "The team report could not be read. " + error.plainWords)
            }
        }
    }

    /// One team read fresh (GET /api/bot-departments/{id}), with every member, hidden ones too. The record is shown
    /// unless a write to this team overlapped the read.
    func readTeam(_ teamID: String) async -> BotTmTeamCheck {
        guard active else { return .dropped }
        let account = self.account
        let key = "team|\(teamID)"
        let stamp = touched[key] ?? 0
        do {
            let read = try await client().botTeamRead(teamID)
            guard stillLive(account) else { return .dropped }
            if untouched(key, since: stamp) { departments[teamID] = read.department }
            return .read(members: BotLossyList(read.members).items.count, paused: read.paused ?? false)
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .dropped }
            if error is CancellationError { return .dropped }
            if status(error) == 404 {
                if untouched(key, since: stamp) { departments[teamID] = nil }
                return .failed("This team is not on your desktop any more.")
            }
            return .failed("This team could not be read from your desktop. " + error.plainWords)
        }
    }

    // MARK: Pause

    /// Pause or resume the team. Asked first on screen when pausing. Shown once the desktop answers.
    func setPaused(_ teamID: String, name: String, _ paused: Bool, say: @escaping (String) -> Void) {
        guard active, isCurrent, departments[teamID] != nil, !busy.contains(teamID) else { return }
        let account = self.account
        let keys = teamKeys(teamID)
        busy.insert(teamID)
        beginWrite(keys)
        Task {
            defer { if stillLive(account) { busy.remove(teamID) } }
            do {
                let saved = try await client().botTeamSetPaused(teamID, paused)
                endWrite(keys)
                guard stillLive(account) else { return }
                departments[saved.id] = saved
                // The desktop answers with the record it kept, which can differ (the Content Studio team's switch).
                if (saved.paused ?? false) == paused {
                    say(paused ? "\(name) is paused." : "\(name) is back at work.")
                } else {
                    say(paused ? "Your desktop answered, but \(name) is still working. It was not paused."
                               : "Your desktop answered, but \(name) is still paused. It was not resumed.")
                }
                await afterChange(account)
            } catch {
                endWrite(keys)
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    let read = await loadMap()
                    guard stillLive(account) else { return }
                    if read, let now = departments[teamID] {
                        say((now.paused ?? false) == paused ? (paused ? "\(name) is paused." : "\(name) is back at work.")
                                                            : "Your desktop did not answer, and it still has \(name) \(paused ? "working" : "paused"). Nothing changed.")
                    } else {
                        say("Your desktop did not answer, so this iPhone could not confirm \(name) was \(paused ? "paused" : "resumed"). Look again in a moment.")
                    }
                    return
                }
                if status(error) == 404 {
                    say("\(name) is not on your desktop any more.")
                    await afterChange(account)
                    return
                }
                say((paused ? "\(name) was not paused. " : "\(name) was not resumed. ") + words(error))
            }
        }
    }

    // MARK: Rename

    /// Rename with the revision the team was read at. A stale revision is read again; the typed name stays.
    func rename(_ teamID: String, to name: String) async -> BotTmOutcome {
        guard active, isCurrent else { return .refused("Your desktop is not connected.") }
        guard let revision = departments[teamID]?.revision else { return .refused("Still reading this team from your desktop. Try again in a moment.") }
        guard !busy.contains(teamID) else { return .refused("Another change to this team is still on its way. Try again in a moment.") }
        let account = self.account
        let keys = teamKeys(teamID)
        busy.insert(teamID)
        beginWrite(keys)
        defer { if stillLive(account) { busy.remove(teamID) } }
        do {
            let saved = try await client().botTeamRename(teamID, name: name, expectedRevision: revision)
            endWrite(keys)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            departments[saved.id] = saved
            await afterChange(account)
            return .done("The team is now \(saved.name ?? name).")
        } catch {
            endWrite(keys)
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if unconfirmed(error) { return await confirmRename(teamID, sent: name) }
            if status(error) == 404 { await afterChange(account); return .refused("This team is not on your desktop any more.") }
            if status(error) == 409, words(error).hasPrefix("The team changed") {
                await loadMap()
                return .changed("This team changed on your desktop, so nothing was saved. Your new name is kept here. Check it and save again.")
            }
            return .refused("It was not renamed. " + words(error))
        }
    }

    /// After a rename whose answer was lost: read the team again and compare it with the name that was sent,
    /// exactly (the desktop only trims spaces, so a change of case is a rename).
    func confirmRename(_ teamID: String, sent: String) async -> BotTmOutcome {
        guard active else { return .refused("Your desktop is not connected.") }
        let account = self.account
        guard await loadMap(), stillLive(account) else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm the team was renamed. Look again before saving a second time.")
        }
        guard let now = departments[teamID] else { return .refused("This team is not on your desktop any more.") }
        if BotTmMap.clean(now.name ?? "") == sent {
            await BotsStore.shared.loadRoster()
            return .done("The team is now \(now.name ?? sent).")
        }
        return .refused("Your desktop did not answer, and it still has the team as \(now.name ?? "before"). It was not renamed, so you can save again.")
    }

    // MARK: Chief

    /// Make a member the chief, or none, after the person confirmed what the sheet said would happen to the other
    /// teams the chief manages (`shownChief` and `shownManaged` are what that sheet was built from).
    ///
    /// The desktop's chief write has no revision check and saves the list as sent, so the team is read fresh just
    /// before the write and the list is sent from that read. If the read fails, nothing is sent. If the chief or the
    /// list changed since the sheet was shown, nothing is sent and the screen shows what the desktop has.
    func setChief(_ teamID: String, botID: String?, shownChief: String?, shownManaged: [String]) async -> BotTmOutcome {
        guard active, isCurrent else { return .refused("Your desktop is not connected.") }
        guard departments[teamID] != nil else { return .refused("Still reading this team from your desktop. Try again in a moment.") }
        guard !busy.contains(teamID) else { return .refused("Another change to this team is still on its way. Try again in a moment.") }
        let account = self.account
        let keys = teamKeys(teamID)
        busy.insert(teamID)
        beginWrite(keys)
        defer { if stillLive(account) { busy.remove(teamID) } }

        let fresh: BotTmDepartmentDTO
        do {
            fresh = try await client().botTeamRead(teamID).department
        } catch {
            endWrite(keys)
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if status(error) == 404 { await afterChange(account); return .refused("This team is not on your desktop any more.") }
            return .refused("This team could not be read from your desktop just now, so nothing was sent and the chief is as it was. " + words(error))
        }
        guard stillLive(account) else { endWrite(keys); return .refused("Your desktop changed while this was being saved.") }
        departments[teamID] = fresh
        guard let managed = fresh.managed else {
            endWrite(keys)
            return .refused(BotTmMap.chiefListUnreadable)
        }
        if fresh.chiefBotId != shownChief || managed != shownManaged {
            endWrite(keys)
            await BotsStore.shared.loadRoster()
            return .changed("The chief or the other teams it manages changed on your desktop, so nothing was sent. This now shows what your desktop has. Choose again if you still want to.")
        }

        do {
            let saved = try await client().botTeamSetChief(teamID, botID: botID, alsoManages: botID == nil ? [] : managed)
            endWrite(keys)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            departments[saved.id] = saved
            await afterChange(account)
            let now = departments[teamID]?.chiefBotId
            if now != botID {
                return .refused("Your desktop answered, but it now has \(now.map { BotsStore.shared.bot($0).name } ?? "no chief") as the chief.")
            }
            return .done(botID == nil ? "The team has no chief now." : "\(BotsStore.shared.bot(botID ?? "").name) is Chief of Staff.")
        } catch {
            endWrite(keys)
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if unconfirmed(error) { return await confirmChief(teamID, sent: botID) }
            if status(error) == 404 {
                // The desktop also answers 404 when a team in the chief's list was deleted (its id stays in the list).
                let read = await afterChange(account)
                if read, departments[teamID] != nil {
                    return .refused("Your desktop refused: one of the other teams this chief manages was deleted, and your desktop will not save a list that names it. Removing the chief still works, and it clears that list.")
                }
                return .refused(read ? "This team is not on your desktop any more." : "Your desktop refused the change. " + words(error))
            }
            return .refused("The chief was not changed. " + words(error))
        }
    }

    func confirmChief(_ teamID: String, sent: String?) async -> BotTmOutcome {
        guard active else { return .refused("Your desktop is not connected.") }
        let account = self.account
        guard await loadMap(), stillLive(account) else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm the chief changed. Look again before choosing a second time.")
        }
        guard let now = departments[teamID] else { return .refused("This team is not on your desktop any more.") }
        await BotsStore.shared.loadRoster()
        if now.chiefBotId == sent {
            return .done(sent == nil ? "The team has no chief now." : "\(BotsStore.shared.bot(sent ?? "").name) is Chief of Staff.")
        }
        return .refused("Your desktop did not answer, and it does not have this chief. This shows what it has now.")
    }

    // MARK: Delete

    /// Delete the team on the desktop. Off the screen only once the desktop has done it.
    func deleteTeam(_ teamID: String) async -> BotTmOutcome {
        guard active, isCurrent else { return .refused("Your desktop is not connected.") }
        guard !busy.contains(teamID) else { return .refused("Another change to this team is still on its way. Try again in a moment.") }
        let account = self.account
        let keys = teamKeys(teamID)
        busy.insert(teamID)
        beginWrite(keys)
        defer { if stillLive(account) { busy.remove(teamID) } }
        do {
            try await client().botTeamDelete(teamID)
            endWrite(keys)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being deleted.") }
            departments[teamID] = nil
            // Read again after the sheet has closed, so the team never vanishes under its own confirm sheet.
            Task { await self.afterChange(account) }
            return .done("The team was deleted. Its bots are in no team now.")
        } catch {
            endWrite(keys)
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being deleted.") }
            if unconfirmed(error) { return await confirmDelete(teamID) }
            if status(error) == 404 {
                Task { await self.afterChange(account) }
                return .done("This team was already gone from your desktop.")
            }
            return .refused("It was not deleted. " + words(error))
        }
    }

    func confirmDelete(_ teamID: String) async -> BotTmOutcome {
        guard active else { return .refused("Your desktop is not connected.") }
        let account = self.account
        guard await loadMap(), stillLive(account) else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm the team was deleted. Look again before deleting a second time.")
        }
        if departments[teamID] == nil {
            Task { await BotsStore.shared.loadRoster() }
            return .done("The team was deleted. Its bots are in no team now.")
        }
        return .refused("Your desktop did not answer, and it still has this team. Nothing was deleted.")
    }

    // MARK: Instructions

    /// Save the text with the hash the form was filled from (409 when the desktop's text changed since). On done,
    /// `instructions[teamID]` holds what the desktop answered: the saved text and its hash.
    func saveInstructions(_ teamID: String, text: String, expectedHash: String) async -> BotTmOutcome {
        guard active, isCurrent else { return .refused("Your desktop is not connected.") }
        guard !busy.contains(teamID) else { return .refused("Another change to this team is still on its way. Try again in a moment.") }
        let account = self.account
        let keys = ["instructions|\(teamID)"]
        busy.insert(teamID)
        beginWrite(keys)
        defer { if stillLive(account) { busy.remove(teamID) } }
        do {
            let saved = try await client().botTeamSetInstructions(teamID, text: text, expectedHash: expectedHash)
            endWrite(keys)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            instructions[teamID] = saved
            instructionsLoad[teamID] = .loaded
            return .done("Instructions saved.")
        } catch {
            endWrite(keys)
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if unconfirmed(error) { return await confirmInstructions(teamID, sent: text, expectedHash: expectedHash) }
            if status(error) == 409 {
                await loadInstructions(teamID)
                return .changed("The instructions changed on your desktop, so nothing was saved. Your text is kept here.")
            }
            return .refused("The instructions were not saved. " + words(error))
        }
    }

    /// After a save whose answer was lost: read the desktop again and compare it with the text that was SENT.
    func confirmInstructions(_ teamID: String, sent: String, expectedHash: String) async -> BotTmOutcome {
        guard active else { return .refused("Your desktop is not connected.") }
        let account = self.account
        guard await loadInstructions(teamID) == .loaded, stillLive(account), let now = instructions[teamID] else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm the instructions were saved. Look again before saving a second time.")
        }
        if now.text == sent { return .done("Instructions saved.") }
        if now.hash == expectedHash {
            return .refused("Your desktop did not answer, and it still has the text this form was filled from. Yours was not saved, so you can save again.")
        }
        return .changed("Your desktop did not answer, and it now has other instructions. Yours were not saved and are kept here.")
    }

    // MARK: Memory

    /// Add an entry (accepted at once). A lost answer is looked for, never sent again blind.
    func addMemory(_ teamID: String, kind: String, name: String, detail: String) async -> BotTmOutcome {
        guard active, isCurrent else { return .refused("Your desktop is not connected.") }
        if let check = addChecks[teamID], check.kind == kind, check.name == name {
            // This same entry was sent before and its answer was lost: look for it first.
            return await confirmAdd(teamID)
        }
        guard memoryLoad[teamID] == .loaded else { return .refused("Still reading the team's memory. Try again in a moment.") }
        guard !busy.contains(teamID) else { return .refused("Another change to this team is still on its way. Try again in a moment.") }
        let account = self.account
        let keys = ["memory|\(teamID)"]
        let before = Set((memory[teamID] ?? []).map(\.id))
        busy.insert(teamID)
        beginWrite(keys)
        defer { if stillLive(account) { busy.remove(teamID) } }
        do {
            let made = try await client().botTeamAddMemory(teamID, kind: kind, name: name, detail: detail)
            endWrite(keys)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if !(memory[teamID] ?? []).contains(where: { $0.id == made.id }) { memory[teamID, default: []].append(made) }
            return .done("Remembered.")
        } catch {
            endWrite(keys)
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if unconfirmed(error) {
                addChecks[teamID] = BotTmAddCheck(kind: kind, name: name, detail: detail, before: before)
                return await confirmAdd(teamID)
            }
            return .refused("It was not added. " + words(error))
        }
    }

    /// After an add whose answer was lost: read the memory again and look for the new entry, by its name or its
    /// detail (the desktop may clean either). The desktop saves it as a suggestion first, then accepts it.
    func confirmAdd(_ teamID: String) async -> BotTmOutcome {
        guard active else { return .refused("Your desktop is not connected.") }
        let account = self.account
        guard let check = addChecks[teamID] else {
            await loadMemory(teamID)
            return .refused("There is no earlier entry to look for. Check the list before adding it.")
        }
        guard await loadMemory(teamID) == .loaded, stillLive(account) else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm it was added. Look again before adding it a second time.")
        }
        addChecks[teamID] = nil
        let same = { (a: String?, b: String) in BotTmMap.clean(a ?? "").caseInsensitiveCompare(b) == .orderedSame }
        let found = (memory[teamID] ?? []).first {
            !check.before.contains($0.id) && $0.kind == check.kind && (same($0.name, check.name) || same($0.detail, check.detail))
        }
        guard let found else { return .refused("It was not added. Your desktop has no such entry, so you can add it again.") }
        if found.status == "accepted" { return .done("Remembered.") }
        return .done("Your desktop saved it as a suggestion only, so the team does not use it yet. Accept it in Kairos on your desktop.")
    }

    /// Delete an entry with the revision it was read at. Asked first on screen.
    func deleteMemory(_ teamID: String, _ entry: BotTmMemoryEntryDTO, say: @escaping (String) -> Void) {
        guard active, isCurrent, let revision = entry.revision, !deleting.contains(entry.id) else { return }
        let account = self.account
        let name = entry.name ?? "The entry"
        let keys = ["memory|\(teamID)"]
        deleting.insert(entry.id)
        beginWrite(keys)
        Task {
            defer { if stillLive(account) { deleting.remove(entry.id) } }
            do {
                try await client().botTeamDeleteMemory(teamID, entryID: entry.id, expectedRevision: revision)
                endWrite(keys)
                guard stillLive(account) else { return }
                withAnimation(Motion.snappy) { memory[teamID]?.removeAll { $0.id == entry.id } }
                say("\(name) was deleted.")
            } catch {
                endWrite(keys)
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    let read = await loadMemory(teamID)
                    guard stillLive(account) else { return }
                    if read != .loaded {
                        say("Your desktop did not answer, so this iPhone could not confirm \(name) was deleted. Look again in a moment.")
                    } else if (memory[teamID] ?? []).contains(where: { $0.id == entry.id }) {
                        say("Your desktop did not answer, and it still has \(name). Nothing was deleted.")
                    } else {
                        say("\(name) was deleted.")
                    }
                    return
                }
                if status(error) == 404 {
                    say("\(name) was already gone from your desktop.")
                } else if status(error) == 409 {
                    say("\(name) changed on your desktop, so it was not deleted. This shows what your desktop has now.")
                } else {
                    say("\(name) was not deleted. " + words(error))
                }
                await loadMemory(teamID)
            }
        }
    }
}
