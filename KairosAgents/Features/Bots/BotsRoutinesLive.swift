import SwiftUI
import CryptoKit

// The paired desktop behind routines, triggers, the automation calendar and Kip's watch
// (routes/bot_routine_routes.py, routes/bot_event_routes.py, routes/front_desk_watch_routes.py).
// Unpaired, nothing here runs and the screens show BotsStore's samples exactly as before.
// Everything read here belongs to one desktop and one account; a result that lands for another is dropped.

/// How a write the screen waits on came back.
nonisolated enum BotRoutineOutcome: Equatable, Sendable {
    case done(String)
    case refused(String)
    /// The answer was lost, so the desktop may have done it. The form stays.
    case unsure(String)
}

/// What the routine editor holds: the routine and the parts of its schedule the Routine model has no place for.
nonisolated struct BotRoutineForm: Equatable, Sendable {
    var draft: Routine
    var onceDate: Date
    var stopAfter: Bool
    var stopDate: Date
    /// The model connection a limit reset routine follows.
    var endpointID: String
    /// The schedule's own time zone, when it names one that is not this iPhone's.
    var zone: String?
    /// Whether the run limit is set on the desktop (nil there means its own default).
    var limitSet: Bool
    /// The desktop's revision this form was read at.
    var revision: String?
    /// The desktop and account it was read from.
    var account = ""
}

/// The editor's schedule line while paired: what the desktop says the schedule means.
nonisolated enum BotRoutinePreview: Equatable, Sendable {
    case checking
    case shown(sentence: String, next: [Date])
    case refused(String)
    case unknown(String)
}

/// A Schedule whose answer was lost: what to look for in the next read.
nonisolated struct BotRoutineCreateCheck: Equatable, Sendable {
    var botID: String
    var name: String
    var before: Set<String>
}

/// Which desktop trigger a row on screen is.
nonisolated struct BotTriggerRef: Equatable, Sendable {
    enum Kind: String, Sendable { case webhook, app }
    var kind: Kind
    var id: String
    var revision: Int?
}

@Observable
final class BotsRoutinesLive {
    static let shared = BotsRoutinesLive()

    // Routines and triggers of every bot on this account.
    var routines: [Routine] = []
    var triggers: [BotTrigger] = []
    var routinesLoad: BotsLiveLoad = .idle
    var triggersLoad: BotsLiveLoad = .idle
    /// Items of the last read this app could not read, left out of the lists.
    var skippedRoutines = 0
    var skippedTriggers = 0
    /// The desktop's record behind each routine, by its desktop id.
    var records: [String: BotRoutineDTO] = [:]
    /// One routine read with its last 20 runs, for the detail sheet.
    var details: [String: BotRoutineDTO] = [:]
    var detailLoad: [String: BotsLiveLoad] = [:]
    var nextTimes: [String: [Date]] = [:]
    /// Routines and triggers (desktop ids) with a write on its way: their controls wait.
    var busy: Set<String> = []
    /// Routines moved to after a limit reset from this phone.
    var moved: Set<String> = []

    // The calendar: one week of occurrences.
    var calendarWeek: Date?
    var calendarLoad: BotsLiveLoad = .idle
    var occurrences: [String: [Date]] = [:]

    var limits: [BotLimitDTO] = []
    var limitsLoad: BotsLiveLoad = .idle

    var watch: BotWatchDTO?
    var watchLoad: BotsLiveLoad = .idle
    var watchBusy = false

    /// A Schedule whose answer was lost, checked before anything is sent again.
    var createCheck: BotRoutineCreateCheck?
    /// Routines whose last save got no answer and has not been read again.
    var recheck: Set<String> = []

    @ObservationIgnored private var account = "sample"
    @ObservationIgnored private var desktopIDs: [UUID: String] = [:]
    @ObservationIgnored private var triggerRefs: [UUID: BotTriggerRef] = [:]
    @ObservationIgnored private var triggerIDs: [String: UUID] = [:]
    @ObservationIgnored private var writing = 0
    @ObservationIgnored private var writeGeneration = 0
    @ObservationIgnored private var listSeq = 0
    @ObservationIgnored private var listKey = ""
    @ObservationIgnored private var triggerSeq = 0
    @ObservationIgnored private var calendarSeq = 0
    @ObservationIgnored private var watchSeq = 0
    @ObservationIgnored private var detailSeq: [String: Int] = [:]
    @ObservationIgnored private var runRequests: [String: (id: String, at: Date)] = [:]

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

    /// Match the connection: another desktop or account, or unpairing, drops everything read before.
    func followConnection() {
        let want = active ? Self.accountKey : "sample"
        guard want != account else { return }
        reset()
        account = want
    }

    private func reset() {
        routines = []
        triggers = []
        routinesLoad = .idle
        triggersLoad = .idle
        skippedRoutines = 0
        skippedTriggers = 0
        records = [:]
        details = [:]
        detailLoad = [:]
        nextTimes = [:]
        busy = []
        moved = []
        calendarWeek = nil
        calendarLoad = .idle
        occurrences = [:]
        limits = []
        limitsLoad = .idle
        watch = nil
        watchLoad = .idle
        watchBusy = false
        createCheck = nil
        recheck = []
        desktopIDs = [:]
        triggerRefs = [:]
        triggerIDs = [:]
        writing = 0
        writeGeneration += 1
        listSeq += 1
        triggerSeq += 1
        calendarSeq += 1
        watchSeq += 1
        listKey = ""
        runRequests = [:]
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

    private func unsure(_ what: String) -> String {
        "Your desktop did not answer, so this iPhone could not confirm \(what). This list shows what your desktop has."
    }

    // MARK: What the screens ask

    func desktopID(_ routine: Routine) -> String? { desktopIDs[routine.id] }

    func record(_ routine: Routine) -> BotRoutineDTO? { desktopIDs[routine.id].flatMap { records[$0] } }

    func waits(_ routine: Routine) -> Bool { desktopIDs[routine.id].map { busy.contains($0) } ?? true }

    func waits(_ trigger: BotTrigger) -> Bool { triggerRefs[trigger.id].map { busy.contains($0.kind.rawValue + ":" + $0.id) } ?? true }

    /// What was read belongs to the desktop and account paired right now. Until the screen's task has caught up
    /// with a new pairing, nothing read for the last one is shown.
    var isCurrent: Bool { active && account == Self.accountKey }
    var shownRoutines: [Routine] { isCurrent ? routines : [] }
    var shownTriggers: [BotTrigger] { isCurrent ? triggers : [] }
    var shownWatch: BotWatchDTO? { isCurrent ? watch : nil }
    var shownLimits: [BotLimitDTO] { isCurrent ? limits : [] }

    /// A load state for the screen: reading until this account's first read has landed.
    func shown(_ state: BotsLiveLoad) -> BotsLiveLoad {
        guard isCurrent else { return .loading }
        return state == .idle ? .loading : state
    }

    func routines(for botID: String) -> [Routine] { shownRoutines.filter { $0.botID == botID } }

    /// The desktop's own sentence for the schedule.
    func sentence(_ routine: Routine) -> String { record(routine)?.sentence ?? routine.sentence }

    /// When it runs next, by the desktop's own reckoning.
    func nextLabel(_ routine: Routine) -> String? {
        guard routine.on, let date = TasksWire.date(record(routine)?.nextRunAt) else { return nil }
        return RoutineTiming.label(date, now: Date())
    }

    /// The run to mark seen when a routine asks for a look (not one waiting for an answer).
    func seenRunID(_ routine: Routine) -> String? {
        guard let record = record(routine), record.state == "needs_you", record.waiting != true else { return nil }
        guard let last = record.lastRun?.value, last.attention.map({ !$0.isNull }) == true, last.seen != true else { return nil }
        return last.id
    }

    var routinesReady: Bool { isCurrent && (routinesLoad == .loaded || !routines.isEmpty) }
    var triggersReady: Bool { isCurrent && (triggersLoad == .loaded || !triggers.isEmpty) }

    // MARK: Reading

    /// Read once, or again when the connection settled since the last read began.
    func loadIfNeeded() async {
        followConnection()
        guard active else { return }
        switch routinesLoad {
        case .loaded:
            if triggersLoad == .idle { await Task { await self.loadTriggers() }.value }
        case .loading where listKey == Self.connectionKey:
            break
        default:
            // Its own task: the connection settling restarts the screen's task, and that must not cut this read short.
            await Task { await self.loadAll() }.value
        }
    }

    func loadAll() async {
        await refreshRoutines(force: false)
        await loadTriggers()
    }

    /// Read every routine. Answers whether the desktop's list was read and shown. A read that began before
    /// a write finished is dropped (read once more), and so is one a newer read overtook.
    @discardableResult
    func refreshRoutines(force: Bool) async -> Bool {
        guard active else { return false }
        let account = self.account
        listSeq += 1
        let seq = listSeq
        listKey = Self.connectionKey
        if routinesLoad != .loaded { routinesLoad = .loading }
        do {
            for _ in 0..<2 {
                let generation = writeGeneration
                let list = try await client().botRoutines()
                guard stillLive(account), seq == listSeq else { return false }
                let empty = routines.isEmpty && routinesLoad != .loaded
                if force || empty || (writeGeneration == generation && writing == 0) {
                    let (items, skipped) = BotRoutineWire.items(list.routines)
                    showRoutines(items)
                    skippedRoutines = skipped
                    routinesLoad = .loaded
                    return true
                }
                if writing > 0 { return false }
            }
            return false
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), seq == listSeq else { return false }
            if error is CancellationError {
                // Not read is not failed: the next look reads again.
                if routinesLoad == .loading { routinesLoad = .idle }
            } else {
                routinesLoad = .failed("Routines could not be read. " + error.plainWords)
            }
            return false
        }
    }

    private func showRoutines(_ items: [BotRoutineDTO]) {
        var fresh: [String: BotRoutineDTO] = [:]
        for item in items {
            fresh[item.id] = item
            desktopIDs[Self.uuid(item.id)] = item.id
        }
        records = fresh
        routines = items.map(Self.routine)
    }

    /// Put one routine the desktop answered with on screen.
    private func replace(_ item: BotRoutineDTO) {
        records[item.id] = item
        desktopIDs[Self.uuid(item.id)] = item.id
        let fresh = Self.routine(item)
        if let index = routines.firstIndex(where: { $0.id == fresh.id }) {
            routines[index] = fresh
        } else {
            routines.insert(fresh, at: 0)
        }
        if details[item.id] != nil {
            var detail = item
            detail.recentRuns = details[item.id]?.recentRuns
            details[item.id] = detail
        }
    }

    func loadTriggers() async {
        guard active else { return }
        let account = self.account
        triggerSeq += 1
        let seq = triggerSeq
        if triggersLoad != .loaded { triggersLoad = .loading }
        do {
            let generation = writeGeneration
            let hooks = try await client().botWebhooks()
            guard stillLive(account), seq == triggerSeq else { return }
            let apps = try await client().botAppTriggers()
            guard stillLive(account), seq == triggerSeq else { return }
            if triggersLoad == .loaded && (writeGeneration != generation || writing > 0) { return }
            let webhooks = BotRoutineWire.items(hooks.webhooks)
            let appTriggers = BotRoutineWire.items(apps.triggers)
            showTriggers(webhooks: webhooks.items, apps: appTriggers.items)
            skippedTriggers = webhooks.skipped + appTriggers.skipped
            triggersLoad = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), seq == triggerSeq else { return }
            if error is CancellationError {
                if triggersLoad == .loading { triggersLoad = .idle }
            } else {
                triggersLoad = .failed("Triggers could not be read. " + error.plainWords)
            }
        }
    }

    private func showTriggers(webhooks: [BotEventTriggerDTO], apps: [BotEventTriggerDTO]) {
        let old = Dictionary(triggers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [BotTrigger] = []
        var refs: [UUID: BotTriggerRef] = [:]
        var ids: [String: UUID] = [:]
        let all = webhooks.map { ($0, BotTriggerRef.Kind.webhook) } + apps.map { ($0, BotTriggerRef.Kind.app) }
        for (item, kind) in all {
            guard let botID = item.agentId, !botID.isEmpty else { continue }
            let key = kind.rawValue + ":" + item.id
            // The same trigger keeps its place (and its identity on screen) from one read to the next.
            var trigger = triggerIDs[key].flatMap { old[$0] }
                ?? BotTrigger(botID: botID, kind: kind == .webhook ? .webhook : .appEvent, name: "", app: "", event: "",
                              lastEvent: "", instructions: "")
            Self.fill(&trigger, item, kind: kind)
            refs[trigger.id] = BotTriggerRef(kind: kind, id: item.id, revision: item.revision)
            ids[key] = trigger.id
            out.append(trigger)
        }
        triggers = out
        triggerRefs = refs
        triggerIDs = ids
    }

    private func replaceTrigger(_ item: BotEventTriggerDTO, kind: BotTriggerRef.Kind) {
        guard let uuid = triggerIDs[kind.rawValue + ":" + item.id],
              let index = triggers.firstIndex(where: { $0.id == uuid }) else { return }
        Self.fill(&triggers[index], item, kind: kind)
        triggerRefs[uuid] = BotTriggerRef(kind: kind, id: item.id, revision: item.revision)
    }

    /// One routine with its last 20 runs and its next three times, for the detail sheet.
    func loadDetail(_ routine: Routine) async {
        guard active, let id = desktopID(routine) else { return }
        let account = self.account
        let seq = (detailSeq[id] ?? 0) + 1
        detailSeq[id] = seq
        if detailLoad[id] != .loaded { detailLoad[id] = .loading }
        do {
            let generation = writeGeneration
            let detail = try await client().botRoutine(id)
            guard stillLive(account), detailSeq[id] == seq else { return }
            details[id] = detail
            detailLoad[id] = .loaded
            if writeGeneration == generation && writing == 0 && records[id] != nil { replace(detail) }
            if detail.enabled == true, let schedule = detail.schedule,
               let plain = BotRoutineWire.plain(schedule) as? [String: Any] {
                let preview = try? await client().botRoutinePreview(plain, count: 3)
                guard stillLive(account), detailSeq[id] == seq else { return }
                nextTimes[id] = (preview?.next ?? []).compactMap { TasksWire.date($0) }
            } else {
                nextTimes[id] = []
            }
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), detailSeq[id] == seq else { return }
            if error is CancellationError {
                if detailLoad[id] == .loading { detailLoad[id] = .idle }
            } else if status(error) == 404 {
                detailLoad[id] = .failed("This routine is not on your desktop any more.")
            } else {
                detailLoad[id] = .failed("Its runs could not be read. " + error.plainWords)
            }
        }
    }

    /// One week of occurrences for the calendar, starting on `week` (a Monday at midnight).
    func loadCalendar(week: Date) async {
        guard active else { return }
        let account = self.account
        calendarSeq += 1
        let seq = calendarSeq
        if calendarWeek != week {
            calendarWeek = week
            occurrences = [:]
            calendarLoad = .loading
        } else if calendarLoad != .loaded {
            calendarLoad = .loading
        }
        let end = week.addingTimeInterval(7 * 86_400)
        do {
            let list = try await client().botRoutines(start: week, end: end)
            guard stillLive(account), seq == calendarSeq else { return }
            var found: [String: [Date]] = [:]
            for item in BotRoutineWire.items(list.routines).items {
                found[item.id] = (item.occurrences ?? []).compactMap { TasksWire.date($0) }
            }
            occurrences = found
            calendarLoad = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), seq == calendarSeq else { return }
            if error is CancellationError {
                if calendarLoad == .loading { calendarLoad = .idle }
            } else {
                calendarLoad = .failed("The calendar could not be read. " + error.plainWords)
            }
        }
    }

    func loadLimits() async {
        guard active else { return }
        let account = self.account
        if limitsLoad != .loaded { limitsLoad = .loading }
        do {
            let list = try await client().botLimitResets()
            guard stillLive(account) else { return }
            limits = BotRoutineWire.items(list.limits).items
            limitsLoad = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            if error is CancellationError {
                if limitsLoad == .loading { limitsLoad = .idle }
            } else {
                limitsLoad = .failed("Usage limits could not be read. " + error.plainWords)
            }
        }
    }

    func loadWatch() async {
        guard active else { return }
        let account = self.account
        watchSeq += 1
        let seq = watchSeq
        if watchLoad != .loaded { watchLoad = .loading }
        do {
            let fresh = try await client().botWatch()
            guard stillLive(account), seq == watchSeq else { return }
            watch = fresh
            watchLoad = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), seq == watchSeq else { return }
            if error is CancellationError {
                if watchLoad == .loading { watchLoad = .idle }
            } else if status(error) == 404 || status(error) == 503 {
                watchLoad = .failed("Kip's watch is not set up on your desktop for this account.")
            } else {
                watchLoad = .failed("Kip's watch could not be read. " + error.plainWords)
            }
        }
    }

    // MARK: Routine writes

    /// Turn a routine on or off: shown at once, put back if the desktop refuses.
    func setOn(_ routine: Routine, _ on: Bool, say: @escaping (String) -> Void) {
        guard active, let id = desktopID(routine), !busy.contains(id),
              let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        let account = self.account
        let name = routine.name
        let before = routines[index].on
        routines[index].on = on
        var fields: [String: Any] = ["enabled": on]
        if let revision = records[id]?.revision { fields["expected_revision"] = revision }
        busy.insert(id)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                let saved = try await client().botRoutineUpdate(id, fields)
                endWrite()
                guard stillLive(account) else { return }
                replace(saved)
                say(on ? "\(name) is on." : "\(name) is paused.")
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say(unsure(on ? "\(name) was turned on" : "\(name) was paused"))
                    await refreshRoutines(force: false)
                    return
                }
                if status(error) == 409 || status(error) == 404 {
                    say("\(name) changed on your desktop. This list now shows what your desktop has.")
                    await refreshRoutines(force: false)
                    return
                }
                // Put back only what this tap changed, not newer state a read brought in meanwhile.
                if let now = routines.firstIndex(where: { $0.id == routine.id }), routines[now].on == on { routines[now].on = before }
                say((on ? "\(name) was not turned on. " : "\(name) was not paused. ") + error.plainWords)
            }
        }
    }

    /// Start a run now. Asked first on screen. A repeat after a lost answer sends the same request id,
    /// so the desktop starts it once.
    func runNow(_ routine: Routine, say: @escaping (String) -> Void) {
        guard active, let id = desktopID(routine), !busy.contains(id) else { return }
        let account = self.account
        let name = routine.name
        let kept = runRequests[id].flatMap { Date().timeIntervalSince($0.at) < 270 ? $0.id : nil }
        let request = kept ?? UUID().uuidString
        runRequests[id] = (id: request, at: kept == nil ? Date() : (runRequests[id]?.at ?? Date()))
        busy.insert(id)
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                let answer = try await client().botRoutineRun(id, requestID: request)
                guard stillLive(account) else { return }
                runRequests[id] = nil
                say(answer.duplicate == true ? "\(name) was already started from this iPhone." : "\(name) started on your desktop.")
                if let index = routines.firstIndex(where: { $0.id == routine.id }) { routines[index].lastRun = "Running now" }
                try? await Task.sleep(for: .seconds(2))
                guard stillLive(account) else { return }
                await refreshRoutines(force: false)
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    // It may have started; the same request id is kept so a second tap cannot start it twice.
                    say("Your desktop did not say whether \(name) started. It may be running; this list shows what your desktop has.")
                    await refreshRoutines(force: false)
                    return
                }
                runRequests[id] = nil
                if status(error) == 409 {
                    say("\(name) is already running.")
                    await refreshRoutines(force: false)
                } else {
                    say("\(name) did not start. " + error.plainWords)
                }
            }
        }
    }

    /// Delete on the desktop (kept there seven days). Off the screen only once the desktop has done it.
    func delete(_ routine: Routine, onDeleted: @escaping (Routine) -> Void, say: @escaping (String) -> Void) {
        guard active, let id = desktopID(routine), !busy.contains(id) else { return }
        let account = self.account
        let name = routine.name
        let revision = records[id]?.revision
        busy.insert(id)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                try await client().botRoutineDelete(id, expectedRevision: revision)
                endWrite()
                guard stillLive(account) else { return }
                withAnimation(Motion.snappy) {
                    routines.removeAll { $0.id == routine.id }
                    records[id] = nil
                }
                onDeleted(routine)
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say(unsure("\(name) was deleted"))
                } else if status(error) == 404 {
                    say("\(name) was already gone from your desktop.")
                } else if status(error) == 409 {
                    say("\(name) changed on your desktop, so it was not deleted. Look at it again first.")
                } else {
                    say("\(name) was not deleted. " + error.plainWords)
                }
                await refreshRoutines(force: false)
            }
        }
    }

    /// Bring back a routine deleted from this phone. The desktop keeps it seven days.
    func restore(_ routine: Routine, done: @escaping (Bool) -> Void, say: @escaping (String) -> Void) {
        guard active, let id = desktopID(routine), !busy.contains(id) else { return }
        let account = self.account
        let name = routine.name
        busy.insert(id)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                let back = try await client().botRoutineRestore(id)
                endWrite()
                guard stillLive(account) else { return }
                withAnimation(Motion.snappy) { replace(back) }
                say("\(name) is back.")
                done(true)
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say(unsure("\(name) came back"))
                    done(true)
                } else {
                    say("\(name) did not come back. " + error.plainWords)
                    done(false)
                }
                await refreshRoutines(force: false)
            }
        }
    }

    /// The run that asks for a look no longer does.
    func markSeen(_ routine: Routine, say: @escaping (String) -> Void) {
        guard active, let id = desktopID(routine), let runID = seenRunID(routine), !busy.contains(id) else { return }
        let account = self.account
        busy.insert(id)
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                try await client().botRoutineRunSeen(runID)
                guard stillLive(account) else { return }
                await refreshRoutines(force: false)
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                say(unconfirmed(error) ? unsure("it was marked as seen") : "It was not marked as seen. " + error.plainWords)
                await refreshRoutines(force: false)
            }
        }
    }

    /// Move only the next run to just after the account's usage limit resets.
    func moveAfterReset(_ routine: Routine, say: @escaping (String) -> Void) {
        guard active, let id = desktopID(routine), !busy.contains(id) else { return }
        let account = self.account
        busy.insert(id)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(id) } }
            do {
                let saved = try await client().botRoutineAfterReset(id)
                endWrite()
                guard stillLive(account) else { return }
                replace(saved)
                moved.insert(id)
                say("Moved to after the reset.")
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say(unsure("it was moved"))
                    await refreshRoutines(force: false)
                } else {
                    say("It was not moved. " + error.plainWords)
                }
            }
        }
    }

    // MARK: Trigger writes

    func setOn(_ trigger: BotTrigger, _ on: Bool, say: @escaping (String) -> Void) {
        guard active, let ref = triggerRefs[trigger.id], let index = triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        let key = ref.kind.rawValue + ":" + ref.id
        guard !busy.contains(key) else { return }
        let account = self.account
        let name = trigger.name
        let before = triggers[index].on
        triggers[index].on = on
        busy.insert(key)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                let saved: BotEventTriggerDTO
                switch ref.kind {
                case .webhook: saved = try await client().botWebhookSetEnabled(ref.id, on)
                case .app: saved = try await client().botAppTriggerSetEnabled(ref.id, on, expectedRevision: ref.revision)
                }
                endWrite()
                guard stillLive(account) else { return }
                replaceTrigger(saved, kind: ref.kind)
                say(on ? "\(name) is on." : "\(name) is paused.")
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say(unsure(on ? "\(name) was turned on" : "\(name) was paused"))
                    await loadTriggers()
                    return
                }
                if status(error) == 409 && ref.kind == .app && (error as? APIError)?.plain.hasPrefix("That trigger changed") == true {
                    say("\(name) changed on your desktop. This list now shows what your desktop has.")
                    await loadTriggers()
                    return
                }
                if let now = triggers.firstIndex(where: { $0.id == trigger.id }), triggers[now].on == on { triggers[now].on = before }
                say((on ? "\(name) was not turned on. " : "\(name) was not paused. ") + error.plainWords)
            }
        }
    }

    // MARK: Kip's watch

    /// Pause or resume the watch: it is a routine of Kip's, so this is that routine's on switch.
    func setWatchOn(_ on: Bool, say: @escaping (String) -> Void) {
        guard active, let current = watch, let id = current.routineId, !watchBusy else { return }
        let account = self.account
        var fields: [String: Any] = ["enabled": on]
        if let revision = current.revisionText { fields["expected_revision"] = revision }
        watch?.enabled = on
        watchBusy = true
        beginWrite()
        Task {
            defer { if stillLive(account) { watchBusy = false } }
            do {
                let saved = try await client().botRoutineUpdate(id, fields)
                endWrite()
                guard stillLive(account) else { return }
                if records[saved.id] != nil { replace(saved) }
                say(on ? "Kip is watching your day again." : "Kip stopped watching your day.")
                await loadWatch()
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say("Your desktop did not answer, so this iPhone could not confirm the watch changed. This shows what your desktop has.")
                } else if status(error) == 409 {
                    say("The watch changed on your desktop. This shows what your desktop has.")
                } else {
                    if watch?.enabled == on { watch?.enabled = current.enabled }
                    say((on ? "The watch was not resumed. " : "The watch was not paused. ") + error.plainWords)
                    return
                }
                await loadWatch()
                await refreshRoutines(force: false)
            }
        }
    }

    /// Change the morning brief: only what the person changed is sent.
    func setMorning(on: Bool? = nil, time: String? = nil, say: @escaping (String) -> Void) {
        guard active, watch != nil, !watchBusy, on != nil || time != nil else { return }
        let account = self.account
        var fields: [String: Any] = [:]
        if let on { fields["morning_on"] = on }
        if let time { fields["morning_time"] = time }
        let before = watch?.morning
        if let on { watch?.morning?.on = on }
        if let time { watch?.morning?.time = time }
        watchBusy = true
        Task {
            defer { if stillLive(account) { watchBusy = false } }
            do {
                let saved = try await client().botWatchSettings(fields)
                guard stillLive(account) else { return }
                watch?.morning = saved
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say("Your desktop did not answer, so this iPhone could not confirm the morning brief changed. This shows what your desktop has.")
                    await loadWatch()
                } else {
                    watch?.morning = before
                    say("The morning brief was not changed. " + error.plainWords)
                }
            }
        }
    }

    // MARK: The editor

    /// The form for a routine on screen, from the desktop's record.
    func form(for routineID: UUID) -> BotRoutineForm? {
        guard isCurrent, let id = desktopIDs[routineID], let record = records[id] else { return nil }
        var found = Self.form(record, limits: limits)
        found.account = account
        return found
    }

    /// A new routine's form: the desktop's own defaults, so nothing the person did not pick is sent.
    func newForm(botID: String) -> BotRoutineForm {
        var draft = Routine(botID: botID, name: "", instructions: "", mode: .weekdays)
        draft.rememberLast = false
        draft.lastRun = "Has not run yet"
        let calendar = Calendar.current
        return BotRoutineForm(draft: draft,
                              onceDate: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                              stopAfter: false,
                              stopDate: calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date(),
                              endpointID: limits.first?.endpointId ?? "", zone: nil, limitSet: false, revision: nil,
                              account: account)
    }

    /// What the desktop says a schedule means. Untouched, the routine's own stored schedule is asked about.
    func preview(_ form: BotRoutineForm, base: BotRoutineForm?, routineID: UUID?) async -> BotRoutinePreview? {
        guard active else { return nil }
        let account = self.account
        var schedule = Self.schedule(form)
        if let base, Self.signature(form) == Self.signature(base), let routineID, let id = desktopIDs[routineID],
           let stored = records[id]?.schedule, let plain = BotRoutineWire.plain(stored) as? [String: Any] {
            schedule = plain
        }
        guard let schedule else { return .refused("Pick which usage limit it follows.") }
        do {
            let answer = try await client().botRoutinePreview(schedule, count: 3)
            guard stillLive(account) else { return nil }
            return .shown(sentence: answer.sentence ?? "", next: (answer.next ?? []).compactMap { TasksWire.date($0) })
        } catch {
            guard stillLive(account), !(error is CancellationError) else { return nil }
            if let code = status(error), (400..<500).contains(code) { return .refused(error.plainWords) }
            return .unknown("Your desktop could not check this schedule. " + error.plainWords)
        }
    }

    /// Schedule a new routine. A Schedule whose answer was lost is looked for, never sent again blind.
    func create(_ form: BotRoutineForm, base: BotRoutineForm) async -> BotRoutineOutcome {
        guard active else { return .refused("Your desktop is not connected.") }
        guard base.account == self.account, isCurrent else { return .refused("Your desktop changed. Open this again to start over.") }
        if createCheck != nil { return await confirmCreate() }
        guard let schedule = Self.schedule(form) else { return .refused("Pick which usage limit it follows.") }
        let account = self.account
        let botID = form.draft.botID
        let name = Self.cleanName(form.draft.name)
        var body = Self.changes(form, from: base)
        body["bot_id"] = botID
        body["name"] = name
        body["instructions"] = form.draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        body["schedule"] = schedule
        let before = Set(records.keys)
        let changed = "Your desktop changed while the routine was being scheduled."
        beginWrite()
        do {
            let made = try await client().botRoutineCreate(body)
            endWrite()
            guard stillLive(account) else { return .refused(changed) }
            replace(made)
            return .done("Scheduled. " + (made.sentence ?? "") + ".")
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused(changed) }
            if unconfirmed(error) {
                createCheck = BotRoutineCreateCheck(botID: botID, name: name, before: before)
                return await confirmCreate()
            }
            return .refused("It was not scheduled. " + error.plainWords)
        }
    }

    /// After a Schedule whose answer was lost: read the routines again and look for the new one.
    func confirmCreate() async -> BotRoutineOutcome {
        guard active, let check = createCheck else { return .refused("Your desktop is not connected.") }
        let account = self.account
        let read = await refreshRoutines(force: true)
        guard stillLive(account) else { return .refused("Your desktop changed while the routine was being scheduled.") }
        guard read else {
            return .unsure("Your desktop did not answer, so this iPhone could not confirm it was scheduled. Try again to look for it before scheduling it a second time.")
        }
        createCheck = nil
        if records.values.contains(where: { !check.before.contains($0.id) && $0.botId == check.botID && Self.cleanName($0.name ?? "") == check.name }) {
            return .done("Scheduled.")
        }
        return .refused("It was not scheduled. Your desktop has no such routine, so you can schedule it again.")
    }

    /// Save a routine's changed fields. The second value is the desktop's current form when it was read again
    /// (the form keeps what was typed and saves against it next time).
    func update(_ routineID: UUID, _ form: BotRoutineForm, base: BotRoutineForm) async -> (BotRoutineOutcome, BotRoutineForm?) {
        guard active, let id = desktopIDs[routineID] else { return (.refused("Your desktop is not connected."), nil) }
        guard base.account == self.account, isCurrent else { return (.refused("Your desktop changed. Open this again to start over."), nil) }
        let account = self.account
        if recheck.contains(id) {
            // The last save got no answer: look first, never send it again blind.
            guard let fresh = await readOne(id, account: account) else {
                return (.unsure("Your desktop did not answer, so this iPhone could not confirm the changes were saved. Try again to look before saving a second time."), nil)
            }
            recheck.remove(id)
            if Self.changes(form, from: fresh).isEmpty { return (.done("Saved."), fresh) }
            return (.unsure("Your desktop does not have these changes. They are kept here; save again to send them."), fresh)
        }
        var fields = Self.changes(form, from: base)
        if fields.isEmpty { return (.done("Nothing changed."), nil) }
        if let schedule = fields["schedule"], schedule is NSNull { return (.refused("Pick which usage limit it follows."), nil) }
        if let revision = base.revision ?? records[id]?.revision { fields["expected_revision"] = revision }
        beginWrite()
        do {
            let saved = try await client().botRoutineUpdate(id, fields)
            endWrite()
            guard stillLive(account) else { return (.refused("Your desktop changed while this was being saved."), nil) }
            replace(saved)
            return (.done("Saved."), nil)
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else { return (.refused("Your desktop changed while this was being saved."), nil) }
            if unconfirmed(error) {
                recheck.insert(id)
                guard let fresh = await readOne(id, account: account) else {
                    return (.unsure("Your desktop did not answer, so this iPhone could not confirm the changes were saved. Try again to look before saving a second time."), nil)
                }
                recheck.remove(id)
                if Self.changes(form, from: fresh).isEmpty { return (.done("Saved."), fresh) }
                return (.unsure("Your desktop did not answer, and it does not show these changes. They are kept here; save again to send them."), fresh)
            }
            if status(error) == 409 {
                let fresh = await readOne(id, account: account)
                return (.refused("This routine changed on your desktop. Your changes are kept here. Check them and save again."), fresh)
            }
            if status(error) == 404 {
                await refreshRoutines(force: false)
                return (.refused("This routine is not on your desktop any more."), nil)
            }
            return (.refused("It was not saved. " + error.plainWords), nil)
        }
    }

    /// Read one routine again and show it. Nil when it could not be read.
    private func readOne(_ id: String, account: String) async -> BotRoutineForm? {
        do {
            let fresh = try await client().botRoutine(id)
            guard stillLive(account) else { return nil }
            replace(fresh)
            var found = Self.form(fresh, limits: limits)
            found.account = account
            return found
        } catch {
            Connection.shared.note(error)
            return nil
        }
    }

    // MARK: Desktop to phone

    /// The same UUID for the same desktop id every time, so routes and rows keep pointing at it.
    static func uuid(_ text: String) -> UUID {
        var b = Array(SHA256.hash(data: Data(("routine:" + text).utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    static func cleanName(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func routine(_ item: BotRoutineDTO) -> Routine {
        form(item, limits: []).draft
    }

    /// A desktop routine in the editor's shape.
    static func form(_ item: BotRoutineDTO, limits: [BotLimitDTO]) -> BotRoutineForm {
        let calendar = Calendar.current
        var draft = Routine(id: uuid(item.id), botID: item.botId ?? "", name: item.name ?? "Untitled routine",
                            instructions: item.instructions ?? "")
        draft.on = item.enabled ?? false
        draft.queueIfRunning = item.overlap == "queue"
        draft.readOnly = item.access == "read-and-draft"
        draft.runOnStart = item.runOnStartup ?? false
        draft.rememberLast = item.continuity ?? false
        draft.showAsCall = item.call ?? false
        draft.blockMinutes = item.durationMinutes ?? 30
        draft.runLimit = item.timeoutMinutes ?? 30
        draft.failedInARow = item.status?.failureStreak ?? 0
        draft.lastRun = lastRunText(item)
        draft.needsYou = needsYouText(item)
        var onceDate = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        var stopAfter = false
        var stopDate = calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        var endpoint = ""
        let schedule = item.schedule
        var zone = BotRoutineWire.field(schedule, "time_zone")?.string
        let weekdays = Set((BotRoutineWire.field(schedule, "weekdays")?.array ?? []).compactMap { $0.int }.compactMap { Weekday(rawValue: $0) })
        switch BotRoutineWire.field(schedule, "kind")?.string {
        case "once":
            draft.mode = .once
            if let at = TasksWire.date(BotRoutineWire.field(schedule, "at")?.string) {
                onceDate = at
                draft.hour = calendar.component(.hour, from: at)
                draft.minute = calendar.component(.minute, from: at)
            }
        case "daily":
            if weekdays.isEmpty || weekdays.count == 7 {
                draft.mode = .daily
            } else if weekdays == Set([.mon, .tue, .wed, .thu, .fri]) {
                draft.mode = .weekdays
            } else {
                draft.mode = .weekly
                draft.days = weekdays
            }
            if let clock = TasksWire.clock(BotRoutineWire.field(schedule, "time")?.string) {
                draft.hour = clock.hour
                draft.minute = clock.minute
            }
        case "interval":
            draft.mode = .interval
            draft.intervalMinutes = BotRoutineWire.field(schedule, "every_minutes")?.int ?? 60
            draft.days = weekdays.isEmpty ? Set(Weekday.allCases) : weekdays
            if let window = BotRoutineWire.field(schedule, "window"),
               let start = TasksWire.clock(BotRoutineWire.field(window, "start")?.string),
               let end = TasksWire.clock(BotRoutineWire.field(window, "end")?.string) {
                draft.onlyBetween = true
                draft.startHour = start.hour
                draft.endHour = end.hour
            }
            if let ends = TasksWire.date(BotRoutineWire.field(schedule, "ends_at")?.string) {
                stopAfter = true
                stopDate = ends
            }
        case "cron":
            draft.mode = .custom
            draft.cron = BotRoutineWire.field(schedule, "expression")?.string ?? draft.cron
        case "limit_reset":
            draft.mode = .limitReset
            draft.afterEveryReset = BotRoutineWire.field(schedule, "repeat")?.string == "every_reset"
            endpoint = BotRoutineWire.field(schedule, "endpoint_id")?.string ?? ""
            draft.limitName = limits.first { $0.endpointId == endpoint }?.name ?? "usage"
            zone = nil
        default:
            break
        }
        if zone == TimeZone.current.identifier { zone = nil }
        return BotRoutineForm(draft: draft, onceDate: onceDate, stopAfter: stopAfter, stopDate: stopDate,
                              endpointID: endpoint, zone: zone, limitSet: item.timeoutMinutes != nil, revision: item.revision)
    }

    static func lastRunText(_ item: BotRoutineDTO) -> String {
        if item.waiting == true { return "Waiting for you" }
        if item.running == true { return "Running now" }
        guard let last = item.lastRun?.value else { return "Has not run yet" }
        let when = (last.finishedAt?.date ?? last.startedAt?.date ?? TasksWire.date(last.scheduledFor)).map { BotRoutineText.past($0) }
        switch last.status {
        case "running": return "Running now"
        case "queued": return "Queued to run"
        case "waiting": return "Waiting for you"
        case "missed": return when.map { "Missed a run \($0)" } ?? "Missed a run"
        case "cancelled": return when.map { "Last run stopped \($0)" } ?? "Last run stopped"
        case "failed": return when.map { "Last run failed \($0)" } ?? "Last run failed"
        default: return when.map { "Last ran \($0)" } ?? "Has run"
        }
    }

    static func needsYouText(_ item: BotRoutineDTO) -> String? {
        if item.waiting == true { return "A run is waiting for you in this bot's inbox." }
        if item.state == "needs_you" {
            let last = item.lastRun?.value
            let text = [last?.summary, last?.error].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            return text.map { String($0.prefix(140)) } ?? "A run needs a look."
        }
        if !(item.status?.checkTrouble ?? []).isEmpty { return "A check before each run needs fixing on your desktop." }
        return nil
    }

    private static let appNames = ["mail": "Email", "calendar": "Calendar", "kairos": "Kairos activity"]
    private static let eventNames = [
        "mail.received": "A new email arrives",
        "calendar.event_starting": "A calendar event is about to start",
        "task.finished": "A task or goal run finished",
        "card.review": "A board card is ready for review",
        "agent.inbox": "A bot sent a report or a question",
    ]

    static func fill(_ trigger: inout BotTrigger, _ item: BotEventTriggerDTO, kind: BotTriggerRef.Kind) {
        trigger.botID = item.agentId ?? trigger.botID
        trigger.name = item.name ?? "Trigger"
        trigger.on = item.enabled ?? false
        trigger.instructions = item.promptTemplate ?? ""
        trigger.runStraightAway = item.autoRun ?? false
        trigger.mostAtOnce = item.maxPending ?? trigger.mostAtOnce
        let events = item.events ?? []
        let last = item.lastEventAt?.date
        switch kind {
        case .webhook:
            trigger.app = "Webhook"
            trigger.event = events.isEmpty ? "Any call" : events.joined(separator: ", ")
            if let pending = item.pendingRuns, pending > 0 {
                trigger.lastEvent = pending == 1 ? "1 call waiting for you" : "\(pending) calls waiting for you"
            } else {
                trigger.lastEvent = last.map { "Last call \(BotRoutineText.past($0))" } ?? "Nothing has arrived yet"
            }
        case .app:
            trigger.app = appNames[item.adapter ?? ""] ?? "An app"
            trigger.event = events.map { eventNames[$0] ?? $0 }.joined(separator: ", ")
            let problem = item.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !problem.isEmpty {
                trigger.lastEvent = String(problem.prefix(120))
            } else {
                trigger.lastEvent = last.map { "Last event \(BotRoutineText.past($0))" } ?? "Nothing has arrived yet"
            }
        }
    }

    // MARK: Phone to desktop

    /// The schedule to send, or nil when a limit reset routine has no limit picked.
    static func schedule(_ form: BotRoutineForm) -> [String: Any]? {
        let draft = form.draft
        let zone = TimeZone.current.identifier
        let clock = String(format: "%02d:%02d", draft.hour, draft.minute)
        let days = Weekday.allCases.filter { draft.days.contains($0) }.map(\.rawValue)
        switch draft.mode {
        case .once:
            let calendar = Calendar.current
            var parts = calendar.dateComponents([.year, .month, .day], from: form.onceDate)
            parts.hour = draft.hour
            parts.minute = draft.minute
            let at = calendar.date(from: parts) ?? form.onceDate
            return ["kind": "once", "at": TasksWire.iso(at)]
        case .daily:
            return ["kind": "daily", "time": clock, "time_zone": zone]
        case .weekdays:
            return ["kind": "daily", "time": clock, "time_zone": zone, "weekdays": [0, 1, 2, 3, 4]]
        case .weekly:
            return ["kind": "daily", "time": clock, "time_zone": zone, "weekdays": days]
        case .interval:
            var out: [String: Any] = ["kind": "interval", "every_minutes": draft.intervalMinutes, "time_zone": zone]
            if !days.isEmpty && days.count < 7 { out["weekdays"] = days }
            if draft.onlyBetween {
                out["window"] = ["start": String(format: "%02d:00", draft.startHour), "end": String(format: "%02d:00", draft.endHour)]
            }
            if form.stopAfter {
                let calendar = Calendar.current
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: form.stopDate) ?? form.stopDate
                out["ends_at"] = TasksWire.iso(end)
            }
            return out
        case .custom:
            return ["kind": "cron", "expression": draft.cron.trimmingCharacters(in: .whitespaces), "time_zone": zone]
        case .limitReset:
            guard !form.endpointID.isEmpty else { return nil }
            return ["kind": "limit_reset", "endpoint_id": form.endpointID, "repeat": draft.afterEveryReset ? "every_reset" : "once"]
        }
    }

    /// Everything the schedule depends on, to tell whether the person changed it.
    static func signature(_ form: BotRoutineForm) -> String {
        let draft = form.draft
        let days = Weekday.allCases.filter { draft.days.contains($0) }.map { String($0.rawValue) }.joined()
        let clock = "\(draft.hour):\(draft.minute)"
        switch draft.mode {
        case .once:
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: form.onceDate)
            return "once|\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)|\(clock)"
        case .daily: return "daily|\(clock)"
        case .weekdays: return "weekdays|\(clock)"
        case .weekly: return "weekly|\(days)|\(clock)"
        case .interval:
            let stop: String
            if form.stopAfter {
                let parts = Calendar.current.dateComponents([.year, .month, .day], from: form.stopDate)
                stop = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
            } else {
                stop = "-"
            }
            let window = draft.onlyBetween ? "\(draft.startHour)-\(draft.endHour)" : "-"
            return "interval|\(draft.intervalMinutes)|\(days)|\(window)|\(stop)"
        case .custom: return "cron|\(draft.cron.trimmingCharacters(in: .whitespaces))"
        case .limitReset: return "reset|\(form.endpointID)|\(draft.afterEveryReset)"
        }
    }

    /// Only what differs from `base`: never a value the person did not change on this phone.
    /// A schedule that changed but cannot be sent is NSNull.
    static func changes(_ form: BotRoutineForm, from base: BotRoutineForm) -> [String: Any] {
        let draft = form.draft
        let old = base.draft
        var out: [String: Any] = [:]
        if cleanName(draft.name) != cleanName(old.name) { out["name"] = cleanName(draft.name) }
        let instructions = draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if instructions != old.instructions.trimmingCharacters(in: .whitespacesAndNewlines) { out["instructions"] = instructions }
        if signature(form) != signature(base) { out["schedule"] = schedule(form) ?? NSNull() }
        if draft.queueIfRunning != old.queueIfRunning { out["overlap"] = draft.queueIfRunning ? "queue" : "skip" }
        if draft.readOnly != old.readOnly { out["access"] = draft.readOnly ? "read-and-draft" : "normal" }
        if draft.runOnStart != old.runOnStart { out["run_on_startup"] = draft.runOnStart }
        if draft.rememberLast != old.rememberLast { out["continuity"] = draft.rememberLast }
        if draft.showAsCall != old.showAsCall { out["call"] = draft.showAsCall }
        if draft.blockMinutes != old.blockMinutes { out["duration_minutes"] = draft.blockMinutes }
        if form.limitSet && (draft.runLimit != old.runLimit || !base.limitSet) { out["timeout_minutes"] = draft.runLimit }
        return out
    }
}

/// Times in plain words for runs that already happened.
enum BotRoutineText {
    static func past(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let clock = clockText(calendar.component(.hour, from: date), calendar.component(.minute, from: date))
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(clock)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday at \(clock)"
        }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 6, days >= 0 {
            return "\(RoutineTiming.weekday(of: date).short) at \(clock)"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// A run's status as one word, and whether it went wrong.
    static func runWord(_ status: String?) -> (word: String, bad: Bool, quiet: Bool) {
        switch status {
        case "completed": return ("Done", false, false)
        case "failed": return ("Failed", true, false)
        case "missed": return ("Missed", false, true)
        case "cancelled": return ("Stopped", false, true)
        case "running": return ("Running", false, false)
        case "queued": return ("Queued", false, true)
        case "waiting": return ("Waiting for you", false, false)
        default: return ("Ran", false, true)
        }
    }
}
