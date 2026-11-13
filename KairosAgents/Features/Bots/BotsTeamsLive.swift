import SwiftUI

// The paired desktop behind teams (routes/bot_department_routes.py, routes/bot_team_routes.py, the team report in
// routes/bot_activity_routes.py). Unpaired, nothing here runs and the team screens show BotsStore's samples.
// Everything read here belongs to one desktop and one account; a result that lands for another is dropped.
//
// What the desktop does, read from services/bot_departments.py and core/bot_policy.py:
// - Pause team: every step of the team's bots that is not a read is refused until it is resumed. Asking the person
//   and reaching the person (message, ring, text) still work. Every approval the team's bots are waiting on is
//   cancelled at once. Routines keep their schedule; their steps are held like any other.
// - Rename: every member's `section` moves to the new name. Refused while one of its bots is working.
// - Delete: the team goes and every member's `section` is cleared, so its bots are in no team. Their conversations
//   and routines stay. Refused while one of its bots is working.

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
}

/// A memory entry sent whose answer was lost: what to look for before anything is added again.
nonisolated struct BotTmAddCheck: Equatable, Sendable {
    var kind: String
    var name: String
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
    @ObservationIgnored private var writing = 0
    @ObservationIgnored private var writeGeneration = 0
    @ObservationIgnored private var mapSeq = 0
    @ObservationIgnored private var mapKey = ""
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
        writing = 0
        writeGeneration += 1
        mapSeq += 1
        mapKey = ""
        readSeq = [:]
    }

    private func stillLive(_ account: String) -> Bool {
        active && self.account == account && Self.accountKey == account
    }

    private func client() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    private func beginWrite() {
        writing += 1
        writeGeneration += 1
    }

    private func endWrite() {
        writing = max(0, writing - 1)
        writeGeneration += 1
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

    func waits(_ teamID: String) -> Bool { busy.contains(teamID) || department(teamID) == nil }

    var shownRooms: [BotRoomDTO] { isCurrent ? rooms : [] }

    var shownHandoffs: [BotTmHandoffDTO] { isCurrent ? handoffs : [] }

    func shown(_ state: BotsLiveLoad?) -> BotsLiveLoad {
        guard isCurrent, let state else { return .loading }
        return state == .idle ? .loading : state
    }

    var mapReady: Bool { isCurrent && (mapLoad == .loaded || !departments.isEmpty) }

    // MARK: Reading

    /// Read the map once, or again when the connection settled since the last read began.
    func loadIfNeeded() async {
        followConnection()
        guard active else { return }
        switch mapLoad {
        case .loaded: break
        case .loading where mapKey == Self.connectionKey: break
        default:
            // Its own task: the connection settling restarts the screen's task, and that must not cut this read short.
            await Task { await self.loadMap(force: false) }.value
        }
    }

    /// Read every team, room and hand-off. Answers whether the desktop's map was read and shown. A read that began
    /// before a write finished is dropped unless `force` (a look after a lost answer) or nothing is shown yet.
    @discardableResult
    func loadMap(force: Bool) async -> Bool {
        guard active else { return false }
        let account = self.account
        mapSeq += 1
        let seq = mapSeq
        mapKey = Self.connectionKey
        let first = mapLoad != .loaded
        if first { mapLoad = .loading }
        do {
            let generation = writeGeneration
            let map = try await client().botTeamLiveMap()
            guard stillLive(account), seq == mapSeq else { return false }
            guard force || first || (writeGeneration == generation && writing == 0) else { return false }
            var found: [String: BotTmDepartmentDTO] = [:]
            for team in BotLossyList(map.departments).items { found[team.id] = team }
            departments = found
            rooms = BotLossyList(map.rooms).items.filter { $0.archivedAt == nil }
            handoffs = BotLossyList(map.handoffs).items
            mapLoad = .loaded
            return true
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), seq == mapSeq else { return false }
            if error is CancellationError {
                if mapLoad == .loading { mapLoad = .idle }
            } else if first {
                mapLoad = .failed("Your teams could not be read. " + error.plainWords)
            }
            return false
        }
    }

    /// After a change the desktop confirmed: the team map here and the roster the other screens read.
    private func afterChange(_ account: String) async {
        guard stillLive(account) else { return }
        await loadMap(force: false)
        guard stillLive(account) else { return }
        await BotsStore.shared.loadRoster()
    }

    @discardableResult
    func loadInstructions(_ teamID: String) async -> Bool {
        guard active else { return false }
        let account = self.account
        let key = "instructions|\(teamID)"
        let seq = nextSeq(key)
        if instructionsLoad[teamID] != .loaded { instructionsLoad[teamID] = .loading }
        do {
            let fresh = try await client().botTeamInstructions(teamID)
            guard stillLive(account), readSeq[key] == seq else { return false }
            instructions[teamID] = fresh
            instructionsLoad[teamID] = .loaded
            return true
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), readSeq[key] == seq else { return false }
            if error is CancellationError {
                if instructionsLoad[teamID] == .loading { instructionsLoad[teamID] = .idle }
            } else if instructionsLoad[teamID] != .loaded {
                instructionsLoad[teamID] = .failed(status(error) == 404 ? "This team is not on your desktop any more."
                                                                        : "The team's instructions could not be read. " + error.plainWords)
            }
            return false
        }
    }

    @discardableResult
    func loadMemory(_ teamID: String) async -> Bool {
        guard active else { return false }
        let account = self.account
        let key = "memory|\(teamID)"
        let seq = nextSeq(key)
        if memoryLoad[teamID] != .loaded { memoryLoad[teamID] = .loading }
        do {
            let list = try await client().botTeamMemory(teamID)
            guard stillLive(account), readSeq[key] == seq else { return false }
            let read = BotLossyList(list.entries)
            memory[teamID] = read.items
            skippedMemory[teamID] = read.skipped
            memoryLoad[teamID] = .loaded
            return true
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), readSeq[key] == seq else { return false }
            if error is CancellationError {
                if memoryLoad[teamID] == .loading { memoryLoad[teamID] = .idle }
            } else if memoryLoad[teamID] != .loaded {
                memoryLoad[teamID] = .failed(status(error) == 404 ? "This team is not on your desktop any more."
                                                                  : "The team's memory could not be read. " + error.plainWords)
            }
            return false
        }
    }

    func loadReport(_ teamID: String, days: Int) async {
        guard active else { return }
        let account = self.account
        let key = "\(teamID)|\(days)"
        let seq = nextSeq("report|" + key)
        if reportLoad[key] != .loaded { reportLoad[key] = .loading }
        do {
            let report = try await client().botTeamReport(teamID, days: days)
            guard stillLive(account), readSeq["report|" + key] == seq else { return }
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

    // MARK: Pause

    /// Pause or resume the team. Asked first on screen when pausing. Shown once the desktop answers.
    func setPaused(_ teamID: String, name: String, _ paused: Bool, say: @escaping (String) -> Void) {
        guard active, isCurrent, departments[teamID] != nil, !busy.contains(teamID) else { return }
        let account = self.account
        busy.insert(teamID)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(teamID) } }
            do {
                let saved = try await client().botTeamSetPaused(teamID, paused)
                endWrite()
                guard stillLive(account) else { return }
                departments[saved.id] = saved
                say(paused ? "\(name) is paused." : "\(name) is back at work.")
                await afterChange(account)
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    let read = await loadMap(force: true)
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
        busy.insert(teamID)
        beginWrite()
        defer { if stillLive(account) { busy.remove(teamID) } }
        do {
            let saved = try await client().botTeamRename(teamID, name: name, expectedRevision: revision)
            endWrite()
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            departments[saved.id] = saved
            await afterChange(account)
            return .done("The team is now \(saved.name ?? name).")
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if unconfirmed(error) { return await confirmRename(teamID, sent: name) }
            if status(error) == 404 { await afterChange(account); return .refused("This team is not on your desktop any more.") }
            if status(error) == 409, words(error).hasPrefix("The team changed") {
                await loadMap(force: true)
                return .changed("This team changed on your desktop, so nothing was saved. Your new name is kept here. Check it and save again.")
            }
            return .refused("It was not renamed. " + words(error))
        }
    }

    /// After a rename whose answer was lost: read the team again and compare it with the name that was sent.
    func confirmRename(_ teamID: String, sent: String) async -> BotTmOutcome {
        guard active else { return .refused("Your desktop is not connected.") }
        let account = self.account
        guard await loadMap(force: true), stillLive(account) else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm the team was renamed. Look again before saving a second time.")
        }
        guard let now = departments[teamID] else { return .refused("This team is not on your desktop any more.") }
        if BotTmMap.clean(now.name ?? "").caseInsensitiveCompare(sent) == .orderedSame {
            await BotsStore.shared.loadRoster()
            return .done("The team is now \(now.name ?? sent).")
        }
        return .refused("Your desktop did not answer, and it still has the team as \(now.name ?? "before"). It was not renamed, so you can save again.")
    }

    // MARK: Chief

    /// Make a member the chief, or none. The other teams the chief manages are sent as the desktop has them.
    func setChief(_ teamID: String, botID: String?) async -> BotTmOutcome {
        guard active, isCurrent else { return .refused("Your desktop is not connected.") }
        guard let team = departments[teamID], let managed = team.managed else {
            return .refused("Still reading this team from your desktop. Try again in a moment.")
        }
        guard !busy.contains(teamID) else { return .refused("Another change to this team is still on its way. Try again in a moment.") }
        let account = self.account
        busy.insert(teamID)
        beginWrite()
        defer { if stillLive(account) { busy.remove(teamID) } }
        do {
            let saved = try await client().botTeamSetChief(teamID, botID: botID, alsoManages: botID == nil ? [] : managed)
            endWrite()
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            departments[saved.id] = saved
            await afterChange(account)
            return .done(botID == nil ? "The team has no chief now." : "\(BotsStore.shared.bot(botID ?? "").name) is Chief of Staff.")
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if unconfirmed(error) { return await confirmChief(teamID, sent: botID) }
            if status(error) == 404 { await afterChange(account); return .refused("This team is not on your desktop any more.") }
            return .refused("The chief was not changed. " + words(error))
        }
    }

    func confirmChief(_ teamID: String, sent: String?) async -> BotTmOutcome {
        guard active else { return .refused("Your desktop is not connected.") }
        let account = self.account
        guard await loadMap(force: true), stillLive(account) else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm the chief changed. Look again before choosing a second time.")
        }
        guard let now = departments[teamID] else { return .refused("This team is not on your desktop any more.") }
        await BotsStore.shared.loadRoster()
        if now.chiefBotId == sent {
            return .done(sent == nil ? "The team has no chief now." : "\(BotsStore.shared.bot(sent ?? "").name) is Chief of Staff.")
        }
        return .refused("Your desktop did not answer, and it still has the chief as before. Nothing changed, so you can choose again.")
    }

    // MARK: Delete

    /// Delete the team on the desktop. Off the screen only once the desktop has done it.
    func deleteTeam(_ teamID: String) async -> BotTmOutcome {
        guard active, isCurrent else { return .refused("Your desktop is not connected.") }
        guard !busy.contains(teamID) else { return .refused("Another change to this team is still on its way. Try again in a moment.") }
        let account = self.account
        busy.insert(teamID)
        beginWrite()
        defer { if stillLive(account) { busy.remove(teamID) } }
        do {
            try await client().botTeamDelete(teamID)
            endWrite()
            guard stillLive(account) else { return .refused("Your desktop changed while this was being deleted.") }
            departments[teamID] = nil
            // Read again after the sheet has closed, so the team never vanishes under its own confirm sheet.
            Task { await self.afterChange(account) }
            return .done("The team was deleted. Its bots are in no team now.")
        } catch {
            endWrite()
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
        guard await loadMap(force: true), stillLive(account) else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm the team was deleted. Look again before deleting a second time.")
        }
        if departments[teamID] == nil {
            Task { await BotsStore.shared.loadRoster() }
            return .done("The team was deleted. Its bots are in no team now.")
        }
        return .refused("Your desktop did not answer, and it still has this team. Nothing was deleted.")
    }

    // MARK: Instructions

    /// Save the text with the hash it was read at. A lost answer reads again and compares with what was sent.
    func saveInstructions(_ teamID: String, text: String) async -> BotTmOutcome {
        guard active, isCurrent else { return .refused("Your desktop is not connected.") }
        guard let hash = instructions[teamID]?.hash else { return .refused("Still reading the instructions from your desktop. Try again in a moment.") }
        guard !busy.contains(teamID) else { return .refused("Another change to this team is still on its way. Try again in a moment.") }
        let account = self.account
        busy.insert(teamID)
        beginWrite()
        defer { if stillLive(account) { busy.remove(teamID) } }
        do {
            let saved = try await client().botTeamSetInstructions(teamID, text: text, expectedHash: hash)
            endWrite()
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            instructions[teamID] = saved
            instructionsLoad[teamID] = .loaded
            return .done("Instructions saved.")
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if unconfirmed(error) { return await confirmInstructions(teamID, sent: text) }
            if status(error) == 409 {
                await loadInstructions(teamID)
                return .changed("The instructions changed on your desktop, so nothing was saved. Your text is kept here. Saving now replaces what your desktop has.")
            }
            return .refused("The instructions were not saved. " + words(error))
        }
    }

    func confirmInstructions(_ teamID: String, sent: String) async -> BotTmOutcome {
        guard active else { return .refused("Your desktop is not connected.") }
        let account = self.account
        guard await loadInstructions(teamID), stillLive(account) else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm the instructions were saved. Look again before saving a second time.")
        }
        if instructions[teamID]?.text == sent { return .done("Instructions saved.") }
        return .refused("Your desktop did not answer, and it does not have this text. It was not saved, so you can save again.")
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
        let before = Set((memory[teamID] ?? []).map(\.id))
        busy.insert(teamID)
        beginWrite()
        defer { if stillLive(account) { busy.remove(teamID) } }
        do {
            let made = try await client().botTeamAddMemory(teamID, kind: kind, name: name, detail: detail)
            endWrite()
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if !(memory[teamID] ?? []).contains(where: { $0.id == made.id }) { memory[teamID, default: []].append(made) }
            return .done("Remembered.")
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while this was being saved.") }
            if unconfirmed(error) {
                addChecks[teamID] = BotTmAddCheck(kind: kind, name: name, before: before)
                return await confirmAdd(teamID)
            }
            return .refused("It was not added. " + words(error))
        }
    }

    /// After an add whose answer was lost: read the memory again and look for the new entry.
    func confirmAdd(_ teamID: String) async -> BotTmOutcome {
        guard active, let check = addChecks[teamID] else { return .refused("Your desktop is not connected.") }
        let account = self.account
        guard await loadMemory(teamID), stillLive(account) else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm it was added. Look again before adding it a second time.")
        }
        addChecks[teamID] = nil
        let found = (memory[teamID] ?? []).contains {
            !check.before.contains($0.id) && $0.kind == check.kind
                && BotTmMap.clean($0.name ?? "").caseInsensitiveCompare(check.name) == .orderedSame
        }
        return found ? .done("Remembered.") : .refused("It was not added. Your desktop has no such entry, so you can add it again.")
    }

    /// Delete an entry with the revision it was read at. Asked first on screen.
    func deleteMemory(_ teamID: String, _ entry: BotTmMemoryEntryDTO, say: @escaping (String) -> Void) {
        guard active, isCurrent, let revision = entry.revision, !deleting.contains(entry.id) else { return }
        let account = self.account
        let name = entry.name ?? "The entry"
        deleting.insert(entry.id)
        beginWrite()
        Task {
            defer { if stillLive(account) { deleting.remove(entry.id) } }
            do {
                try await client().botTeamDeleteMemory(teamID, entryID: entry.id, expectedRevision: revision)
                endWrite()
                guard stillLive(account) else { return }
                withAnimation(Motion.snappy) { memory[teamID]?.removeAll { $0.id == entry.id } }
                say("\(name) was deleted.")
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    let read = await loadMemory(teamID)
                    guard stillLive(account) else { return }
                    if !read {
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
