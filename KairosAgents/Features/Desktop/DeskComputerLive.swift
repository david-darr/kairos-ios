import SwiftUI
import UIKit

// The paired desktop behind the Computer screen (Net/DeskComputerAPI.swift). Not paired, nothing here runs and the
// screen is the sample screen from ComputerScreen, exactly as before.
//
// Paired, the phone WATCHES a computer and can STOP it, and does nothing else to it:
// - Live: the list of running computers, their live screen (a stream), the steps kept for them and a step's
//   pictures. Stop keeps a confirm that names the computer, and takes no request id: it is sent once, the button
//   stays off while it is on its way, and a lost answer is checked by reading the list, never by sending again.
// - Off: take over, hand back, every click, drag, scroll and key, record, save as a skill and the zip export. The
//   screen says "Take control in Kairos on your desktop." There is no function in the API file for any of them.
// - What a view shows is said on the screen: the live screen, the page address, and steps that can include what
//   was typed. Pictures live in memory only, for as long as the screen: nothing is cached, saved or shared.
// - The stream stops when the screen goes away, when the app leaves the foreground and when the account changes. A
//   dropped stream says so and offers Try again. A picture that is not live is marked with its time.

// MARK: - What the screens read

nonisolated enum DeskComputerPhase: Equatable, Sendable {
    case idle
    /// Opening the stream, no picture yet.
    case connecting
    case live
    /// The app is not in front: the stream is closed and the picture dropped.
    case paused
    /// The stream ended or failed. The sentence says why.
    case down(String)
    /// The desktop says the computer closed.
    case closed
}

nonisolated enum DeskComputerStopPhase: Equatable, Sendable {
    /// Sent, no answer yet.
    case sending
    /// The answer was lost: the list is read again to see what the desktop has.
    case checking
    /// The list could not be read to check. Stop stays off; "Check again" reads it once more. A stop is never sent
    /// again while this is not settled.
    case unchecked
}

/// An unsettled stop belongs to one account on one desktop and one computer.
nonisolated struct DeskComputerStopKey: Hashable, Sendable {
    var account: String
    var owner: String
}

nonisolated struct DeskComputerRunsState: Sendable {
    var load: DeskForgeLoad = .idle
    var runs: [DeskComputerRun] = []
    var skipped = 0
}

nonisolated struct DeskComputerStepsState: Sendable {
    var load: DeskForgeLoad = .idle
    var steps: [DeskComputerStep] = []
    var skipped = 0
    var days: Int?
}

// MARK: - The store

@Observable
final class DeskComputerLive {
    static let shared = DeskComputerLive()

    /// The desktop and account everything below was read for. Nothing else is ever shown.
    private var account = "sample"
    private var listLoad: DeskForgeLoad = .idle
    private var rows: [DeskComputer] = []
    private var skippedRows = 0
    private var chosen: String?
    private var watchPhase: DeskComputerPhase = .idle
    private var shownPicture: UIImage?
    private var shownPictureAt: Date?
    private var eventAt: Date?
    private var closedTime: Date?
    private var watchedState: DeskComputer?
    /// When the watched computer was opened, from the list. Owner ids are reused, so this tells it from a new one.
    private var watchedOpened: Double?
    private var runMap: [String: DeskComputerRunsState] = [:]
    private var stepMap: [String: DeskComputerStepsState] = [:]
    private var stepPictures: [String: UIImage] = [:]
    private var pictureOrder: [String] = []
    private var pictureFailed: Set<String> = []
    /// Stops whose answer is not settled, by account and owner. Kept here, not in a screen, and never cleared by
    /// leaving or reopening the screen, an account switch or an unpair: only a list read that shows what happened
    /// ends one.
    private var stopMap: [DeskComputerStopKey: DeskComputerStopPhase] = [:]
    private var noteMap: [DeskComputerStopKey: String] = [:]
    /// When the computer was opened, as the list said when its stop was sent (owner ids are reused).
    private var stopOpened: [DeskComputerStopKey: Double] = [:]

    @ObservationIgnored private var reads: [String: Int] = [:]
    @ObservationIgnored private var writeSerial = 0
    @ObservationIgnored private var inFlight = 0
    @ObservationIgnored private var streamSerial = 0
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var checkTasks: [DeskComputerStopKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var checkGeneration = 0
    @ObservationIgnored private var checkOwners: [DeskComputerStopKey: Int] = [:]

    private init() {}

    // MARK: Which desktop

    /// Paired (whether or not the desktop is answering right now): the screen shows the desktop, never samples.
    var on: Bool { DeskForgeLive.shared.on }
    var isAdmin: Bool { DeskForgeLive.shared.isAdmin }

    private static let desktopChanged = "Your paired desktop changed. Try again."
    private static let maxStepPictures = 8

    private var current: Bool { on && account == DeskForgeLive.accountKey }

    private func stillLive(_ account: String) -> Bool {
        on && self.account == account && DeskForgeLive.accountKey == account
    }

    private func watching(_ account: String, _ serial: Int) -> Bool {
        stillLive(account) && streamSerial == serial && !Task.isCancelled
    }

    /// Before anything is read: drop whatever was read for another desktop, another account or sample mode.
    private func follow() {
        let key = DeskForgeLive.accountKey
        guard account != key else { return }
        streamSerial += 1
        streamTask?.cancel()
        streamTask = nil
        for task in checkTasks.values { task.cancel() }
        checkTasks = [:]
        checkOwners = [:]
        account = key
        listLoad = .idle
        rows = []
        skippedRows = 0
        chosen = nil
        watchPhase = .idle
        shownPicture = nil
        shownPictureAt = nil
        eventAt = nil
        closedTime = nil
        watchedState = nil
        watchedOpened = nil
        runMap = [:]
        stepMap = [:]
        stepPictures = [:]
        pictureOrder = []
        pictureFailed = []
        // Unsettled stops stay: they belong to their own account and are checked again when it is current.
        reads = [:]
    }

    private static func waitWhileConnecting() async {
        var waited = 0
        while Connection.shared.state == .connecting, waited < 80, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
    }

    // MARK: What was read

    var load: DeskForgeLoad { current ? listLoad : .loading }
    var computers: [DeskComputer] { current ? rows : [] }
    var skipped: Int { current ? skippedRows : 0 }
    /// The computer being watched, by owner.
    var selected: String? { current ? chosen : nil }
    var phase: DeskComputerPhase { current ? watchPhase : .idle }
    var picture: UIImage? { current ? shownPicture : nil }
    var pictureTime: Date? { current ? shownPictureAt : nil }
    var lastEvent: Date? { current ? eventAt : nil }
    var closedAt: Date? { current ? closedTime : nil }

    /// What the stream last said about the watched computer, else its row of the list.
    var watched: DeskComputer? {
        guard current, let chosen else { return nil }
        return watchedState ?? rows.first { $0.owner == chosen }
    }

    private func stopKey(_ owner: String) -> DeskComputerStopKey { DeskComputerStopKey(account: account, owner: owner) }

    /// Stop is on its way or being checked (the button reads "Stopping").
    func isStopping(_ owner: String) -> Bool {
        let phase = stopPhase(owner)
        return phase == .sending || phase == .checking
    }
    func stopPhase(_ owner: String) -> DeskComputerStopPhase? { current ? stopMap[stopKey(owner)] : nil }
    func note(_ owner: String) -> String? { current ? noteMap[stopKey(owner)] : nil }
    func runs(_ owner: String) -> DeskComputerRunsState? { current ? runMap[owner] : nil }
    func steps(_ runID: String) -> DeskComputerStepsState? { current ? stepMap[runID] : nil }
    func stepPicture(_ key: String) -> UIImage? { current ? stepPictures[key] : nil }
    func stepPictureFailed(_ key: String) -> Bool { current && pictureFailed.contains(key) }

    // MARK: Reading the desktop

    /// One read. It answers `.fresh` only when it is still the newest read of its kind, for the desktop it was
    /// sent to, and no stop was on its way or finished meanwhile (then it is read again). A cancelled read is not
    /// an error: it changes nothing.
    private func read<Value: Sendable>(_ key: String, _ account: String, afterStops: Bool = true,
                                       _ fetch: (APIClient) async throws -> Value) async -> DeskForgeRead<Value> {
        let serial = (reads[key] ?? 0) + 1
        reads[key] = serial
        for _ in 0..<3 {
            let writes = writeSerial
            do {
                guard let client = Connection.shared.client else { throw APIError.notPaired }
                let value = try await fetch(client)
                guard stillLive(account), reads[key] == serial else { return .stale }
                if afterStops, writes != writeSerial || inFlight > 0 { continue }
                return .fresh(value)
            } catch {
                if error is CancellationError || Task.isCancelled { return .stale }
                Connection.shared.note(error)
                guard stillLive(account), reads[key] == serial else { return .stale }
                var missing = false
                if let api = error as? APIError, case .server(let status, _) = api, status == 404 { missing = true }
                return .failed(DeskComputerWire.words(error), missing: missing)
            }
        }
        guard stillLive(account), reads[key] == serial else { return .stale }
        return .failed("Your desktop was busy stopping a computer. Try again in a moment.", missing: false)
    }

    /// The running computers. Answers true when the list on screen is what the desktop has now.
    @discardableResult
    func loadList() async -> Bool {
        guard on else { return false }
        follow()
        let account = self.account
        let loaded = listLoad == .loaded
        if !loaded { listLoad = .loading }
        await Self.waitWhileConnecting()
        guard stillLive(account) else { return false }
        switch await read("list", account, { try await $0.deskComputerList() }) {
        case .stale:
            return false
        case .failed(let why, _):
            if !loaded { listLoad = .failed("The running computers could not be read. " + why) }
            return false
        case .fresh(let list):
            rows = DeskComputerWire.computers(list)
            skippedRows = list.skipped
            listLoad = .loaded
            resumeStops(account)
            // The watched computer was replaced by a new one for the same chat or bot: the picture stops and Stop
            // is no longer offered, so nothing said about the old one is ever applied to the new one.
            if let chosen, let now = rows.first(where: { $0.owner == chosen })?.startedAt {
                if let was = watchedOpened {
                    if was != now {
                        streamSerial += 1
                        streamTask?.cancel()
                        streamTask = nil
                        watchPhase = .closed
                        if closedTime == nil { closedTime = Date() }
                    }
                } else {
                    watchedOpened = now
                }
            }
            return true
        }
    }

    // MARK: Watching

    /// Open the live screen of one computer. Any earlier stream is closed first.
    func startWatching(_ owner: String) {
        guard on, (try? DeskComputerWire.ownerPath(owner)) != nil else { return }
        follow()
        streamTask?.cancel()
        streamSerial += 1
        let serial = streamSerial
        let account = self.account
        if chosen != owner {
            shownPicture = nil
            shownPictureAt = nil
            eventAt = nil
            closedTime = nil
            watchedState = nil
        }
        chosen = owner
        watchedOpened = rows.first { $0.owner == owner }?.startedAt
        watchPhase = .connecting
        streamTask = Task { [weak self] in
            await self?.runStream(owner, account, serial)
        }
    }

    /// Back to the list: the stream closes and the picture is dropped.
    func stopWatching() {
        streamSerial += 1
        streamTask?.cancel()
        streamTask = nil
        chosen = nil
        watchPhase = .idle
        shownPicture = nil
        shownPictureAt = nil
        eventAt = nil
        closedTime = nil
        watchedState = nil
        watchedOpened = nil
    }

    /// What the Stop confirm is about to describe, taken at the moment it opens.
    func seenNow() -> DeskComputerSeen {
        let state = watched
        return DeskComputerSeen(startedAt: watchedOpened, recording: state?.recording ?? false, takenOver: state?.takenOver ?? false)
    }

    /// The app left the foreground: the stream closes and the picture is dropped.
    func pause() {
        guard chosen != nil else { return }
        streamSerial += 1
        streamTask?.cancel()
        streamTask = nil
        shownPicture = nil
        shownPictureAt = nil
        eventAt = nil
        switch watchPhase {
        case .connecting, .live, .down: watchPhase = .paused
        default: break
        }
    }

    /// The screen went away: nothing it showed is kept.
    func leave() {
        stopWatching()
        leaveSteps()
        rows = []
        skippedRows = 0
        listLoad = .idle
        for key in Array(noteMap.keys) where stopMap[key] == nil { noteMap[key] = nil }
    }

    /// The steps sheet closed: its text and pictures are dropped.
    func leaveSteps() {
        runMap = [:]
        stepMap = [:]
        stepPictures = [:]
        pictureOrder = []
        pictureFailed = []
    }

    private func runStream(_ owner: String, _ account: String, _ serial: Int) async {
        await Self.waitWhileConnecting()
        guard watching(account, serial) else { return }
        do {
            guard let client = Connection.shared.client else { throw APIError.notPaired }
            let bytes = try await client.deskComputerFrames(owner)
            guard watching(account, serial) else { return }
            var reader = DeskComputerWire.EventReader()
            for try await line in bytes.lines {
                guard watching(account, serial) else { return }
                guard let event = reader.feed(line) else { continue }
                switch event.name {
                case "frame":
                    guard let dto = try? KJSON.decode(DeskComputerFrameDTO.self, from: event.data) else { continue }
                    show(dto, owner)
                case "closed":
                    await closedStream(owner, account, serial)
                    return
                default:
                    break
                }
            }
            guard watching(account, serial) else { return }
            watchPhase = .down("The live picture stopped. Your desktop ended the connection.")
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            Connection.shared.note(error)
            guard watching(account, serial) else { return }
            if let api = error as? APIError, case .server(let status, _) = api, status == 404 {
                await closedStream(owner, account, serial)
            } else {
                watchPhase = .down("The live picture stopped. " + DeskComputerWire.words(error))
            }
        }
    }

    private func show(_ dto: DeskComputerFrameDTO, _ owner: String) {
        eventAt = Date()
        watchPhase = .live
        watchedState = DeskComputerWire.computer(dto, owner: owner)
        if let data = DeskComputerWire.imageData(dto.image), let image = UIImage(data: data) {
            shownPicture = image
            shownPictureAt = Date()
        }
    }

    /// The desktop says the computer closed: the list is read again and the last picture it kept is asked for.
    private func closedStream(_ owner: String, _ account: String, _ serial: Int) async {
        guard watching(account, serial) else { return }
        watchPhase = .closed
        if closedTime == nil { closedTime = Date() }
        if case .fresh(let dto) = await read("last", account, afterStops: false, { try await $0.deskComputerLast(owner) }),
           watching(account, serial) {
            if let data = DeskComputerWire.imageData(dto.image), let image = UIImage(data: data) {
                shownPicture = image
                if shownPictureAt == nil { shownPictureAt = DeskComputerWire.date(dto.closedAt) ?? Date() }
            }
            if let time = DeskComputerWire.date(dto.closedAt) { closedTime = time }
        }
        guard watching(account, serial) else { return }
        await loadList()
    }

    // MARK: Stopping

    /// The desktop refused the request, so it certainly did not do it. Anything else (not reached, timed out, an
    /// answer this app could not read, a server error, a cancelled wait) may have come after it did.
    private static func refused(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
    }

    /// Stop a computer. No request id exists, so it is sent once. The unsettled state is set before the request
    /// leaves and stays until the desktop's list shows what happened.
    /// `expected` is what the confirm described when it opened: the stop is sent only to that same computer, in that
    /// same state.
    func stop(_ owner: String, expected: DeskComputerSeen) async -> DeskForgeOutcome {
        guard on, (try? DeskComputerWire.ownerPath(owner)) != nil else {
            return .refused("This computer could not be read, so nothing was stopped.")
        }
        follow()
        let account = self.account
        let key = stopKey(owner)
        guard stopMap[key] == nil else { return .busy }
        let gone = "This computer had already closed. Nothing was sent."
        if chosen == owner, watchPhase == .closed {
            noteMap[key] = gone
            return .refused(gone)
        }
        stopMap[key] = .sending
        noteMap[key] = nil
        // Owner ids are reused and the desktop's stop route knows only the owner. So the list is read once first,
        // and the stop leaves only when it still shows the computer the confirm described: opened at the same
        // time, and not recording or taken over where the confirm did not say so. A read that fails sends nothing.
        guard let client = Connection.shared.client, let list = try? await client.deskComputerList() else {
            stopMap[key] = nil
            let line = "Your desktop could not be read, so nothing was stopped. Try again."
            if stillLive(account) { noteMap[key] = line }
            return .refused(line)
        }
        guard stillLive(account) else {
            stopMap[key] = nil
            return .refused(Self.desktopChanged)
        }
        guard let now = DeskComputerWire.computers(list).first(where: { $0.owner == owner }) else {
            stopMap[key] = nil
            noteMap[key] = gone
            await loadList()
            return .refused(gone)
        }
        if let before = expected.startedAt, let after = now.startedAt, before != after {
            stopMap[key] = nil
            let line = "Nothing was stopped. This \(now.isBot ? "bot's" : "chat's") computer was replaced by a new one. Choose it again from the list."
            noteMap[key] = line
            await loadList()
            return .refused(line)
        }
        if (now.recording && !expected.recording) || (now.takenOver && !expected.takenOver) {
            stopMap[key] = nil
            let line = "This computer changed since you asked. Nothing was stopped. Look again and stop it if you still want to."
            noteMap[key] = line
            await loadList()
            return .refused(line)
        }
        let opened = now.startedAt ?? expected.startedAt
        guard stillLive(account) else {
            stopMap[key] = nil
            return .refused(Self.desktopChanged)
        }
        stopOpened[key] = opened
        writeSerial += 1
        inFlight += 1
        var status: Int?
        var detail = ""
        var failure: Error?
        do {
            guard let client = Connection.shared.client else { throw APIError.notPaired }
            _ = try await client.deskComputerStop(owner)
        } catch {
            failure = error
            if let api = error as? APIError, case .server(let code, let text) = api {
                status = code
                detail = text.lowercased()
            }
            Connection.shared.note(error)
        }
        inFlight -= 1
        writeSerial += 1
        let live = stillLive(account)
        guard let error = failure else {
            // The desktop said it stopped it.
            stopMap[key] = nil
            stopOpened[key] = nil
            if live { await settle(owner, account, opened: opened) }
            return .done
        }
        if Self.refused(error) {
            stopMap[key] = nil
            stopOpened[key] = nil
            // Only "computer is closed" means it is not running. The desktop also answers 404 for a chat or bot
            // it does not know, and then it stopped nothing.
            if status == 404, detail.contains("closed") {
                if live { await settle(owner, account, opened: opened) }
                return .done
            }
            let line = "Nothing was stopped. " + DeskComputerWire.words(error)
            noteMap[key] = line
            return .refused(live ? line : Self.desktopChanged)
        }
        // The answer never arrived. The state stays under this account and computer, and the list is read until
        // it shows what happened. Stop stays off until then, and is never sent again.
        stopMap[key] = .checking
        let line = "Your desktop did not confirm the stop, and this phone is checking. Stop stays off until it knows."
        noteMap[key] = line
        if live { watchStop(owner, account) }
        return .unconfirmed(line)
    }

    /// After a stop the desktop answered: read the list so the screen shows what the desktop has.
    private func settle(_ owner: String, _ account: String, opened: Double?) async {
        let fresh = await loadList()
        guard stillLive(account) else { return }
        let key = stopKey(owner)
        if fresh, let row = rows.first(where: { $0.owner == owner }) {
            if let opened, let now = row.startedAt, opened != now {
                noteMap[key] = "Stopped. The chat or bot has opened a new computer since."
            } else {
                noteMap[key] = "Your desktop answered, but it lists this computer as running."
            }
        } else {
            noteMap[key] = nil
        }
    }

    /// What a fresh list says about an unsettled stop. True when it is settled (the entry is gone). It never sends.
    @discardableResult
    private func resolveStop(_ owner: String, _ account: String) -> Bool {
        let key = DeskComputerStopKey(account: account, owner: owner)
        guard let phase = stopMap[key], phase != .sending else { return stopMap[key] == nil }
        guard let row = rows.first(where: { $0.owner == owner }) else {
            // Not running any more: stopped.
            stopMap[key] = nil
            stopOpened[key] = nil
            noteMap[key] = "Stopped. Your desktop no longer lists this computer."
            return true
        }
        if let opened = stopOpened[key], let now = row.startedAt, opened != now {
            stopMap[key] = nil
            stopOpened[key] = nil
            noteMap[key] = "Stopped. The chat or bot has opened a new computer since."
            return true
        }
        return false
    }

    /// After a fresh list: every unsettled stop of this account is resolved by it, and one that is still waiting
    /// and has no check running is checked again. A check that ended because the account was not current (an
    /// account switch, an unpair) picks up here, so Stop never stays on "Stopping" for good.
    private func resumeStops(_ account: String) {
        for key in Array(stopMap.keys) where key.account == account {
            guard let phase = stopMap[key], phase != .sending else { continue }
            if resolveStop(key.owner, account) { continue }
            if phase == .checking, checkTasks[key] == nil { watchStop(key.owner, account) }
        }
    }

    /// "Check again": read the list once more for a stop that could not be checked. It never sends the stop.
    func recheckStop(_ owner: String) {
        guard on, stopPhase(owner) == .unchecked else { return }
        let key = stopKey(owner)
        stopMap[key] = .checking
        noteMap[key] = "Checking with your desktop. Stop stays off until it knows."
        watchStop(owner, account)
    }

    /// Read the list for about 30 seconds after a lost stop. It never sends the stop again, and it always ends in
    /// one of: stopped, still running (Stop is offered again behind its confirm) or could not check (Check again).
    private func watchStop(_ owner: String, _ account: String) {
        let key = DeskComputerStopKey(account: account, owner: owner)
        checkTasks[key]?.cancel()
        checkGeneration += 1
        let generation = checkGeneration
        checkOwners[key] = generation
        checkTasks[key] = Task { [weak self] in
            var checked = false
            for attempt in 0..<10 {
                try? await Task.sleep(for: .seconds(attempt == 0 ? 1 : 3))
                guard let self, !Task.isCancelled else { return }
                guard self.stillLive(account) else {
                    // Not current (another account, unpaired): the entry stays, and the next fresh list picks it up.
                    self.endCheck(key, generation)
                    return
                }
                if await self.loadList() {
                    guard !Task.isCancelled, self.stillLive(account) else {
                        if !Task.isCancelled { self.endCheck(key, generation) }
                        return
                    }
                    checked = true
                    if self.resolveStop(owner, account) {
                        self.endCheck(key, generation)
                        return
                    }
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.endCheck(key, generation)
            guard self.stillLive(account), self.stopMap[key] != nil else { return }
            if checked {
                self.stopMap[key] = nil
                self.stopOpened[key] = nil
                self.noteMap[key] = "Your desktop still lists this computer as running, so the stop may not have arrived. You can stop it again."
            } else {
                self.stopMap[key] = .unchecked
                self.noteMap[key] = "This phone could not read your desktop to check the stop. Look at your desktop, then Check again."
            }
        }
    }

    private func endCheck(_ key: DeskComputerStopKey, _ generation: Int) {
        guard checkOwners[key] == generation else { return }
        checkOwners[key] = nil
        checkTasks[key] = nil
    }

    // MARK: Steps

    func loadRuns(_ owner: String) async {
        guard on, (try? DeskComputerWire.ownerPath(owner)) != nil else { return }
        follow()
        let account = self.account
        let loaded = runMap[owner]?.load == .loaded
        if !loaded { runMap[owner] = DeskComputerRunsState(load: .loading) }
        await Self.waitWhileConnecting()
        guard stillLive(account) else { return }
        switch await read("runs:" + owner, account, afterStops: false, { try await $0.deskComputerRuns(owner) }) {
        case .stale:
            break
        case .failed(let why, _):
            if !loaded { runMap[owner] = DeskComputerRunsState(load: .failed("The steps could not be read. " + why)) }
        case .fresh(let list):
            runMap[owner] = DeskComputerRunsState(load: .loaded, runs: DeskComputerWire.runs(list), skipped: list.skipped)
        }
    }

    func loadSteps(_ runID: String) async {
        guard on, (try? DeskComputerWire.runPath(runID)) != nil else { return }
        follow()
        let account = self.account
        let loaded = stepMap[runID]?.load == .loaded
        if !loaded { stepMap[runID] = DeskComputerStepsState(load: .loading) }
        switch await read("steps:" + runID, account, afterStops: false, { try await $0.deskComputerSteps(runID) }) {
        case .stale:
            break
        case .failed(let why, _):
            if !loaded { stepMap[runID] = DeskComputerStepsState(load: .failed("The steps could not be read. " + why)) }
        case .fresh(let dto):
            let mapped = DeskComputerWire.steps(dto)
            stepMap[runID] = DeskComputerStepsState(load: .loaded, steps: mapped.steps, skipped: mapped.skipped, days: dto.days)
        }
    }

    static func pictureKey(_ runID: String, _ number: Int, _ name: String) -> String { "\(runID)|\(number)|\(name)" }

    /// One kept picture of a step. It stays in memory for the sheet's life only, and at most a few at a time.
    func loadPicture(_ runID: String, number: Int, name: String) async {
        let key = Self.pictureKey(runID, number, name)
        guard on, stepPictures[key] == nil else { return }
        follow()
        let account = self.account
        pictureFailed.remove(key)
        switch await read("picture:" + key, account, afterStops: false, { try await $0.deskComputerStepImage(runID, number: number, name: name) }) {
        case .stale:
            break
        case .failed:
            pictureFailed.insert(key)
        case .fresh(let data):
            guard let image = UIImage(data: data) else {
                pictureFailed.insert(key)
                return
            }
            stepPictures[key] = image
            pictureOrder.append(key)
            while pictureOrder.count > Self.maxStepPictures {
                stepPictures[pictureOrder.removeFirst()] = nil
            }
        }
    }
}

// MARK: - The screen

/// What the Stop confirm described when it opened: which computer (by its opening time) and what it said would be lost.
nonisolated struct DeskComputerSeen: Hashable, Sendable {
    var startedAt: Double?
    var recording: Bool
    var takenOver: Bool
}

/// The Computer screen while paired: the running computers, one computer's live screen and its steps. Watch and
/// Stop only.
struct DeskComputerScreen: View {
    var start: ComputerStart = .watch

    @State private var live = DeskComputerLive.shared
    @State private var askStop = false
    @State private var stopSeen = DeskComputerSeen(startedAt: nil, recording: false, takenOver: false)
    @State private var showSteps = false
    @State private var toast: String?
    @State private var picked = false
    @State private var openedSteps = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let owner = live.selected {
                    watching(owner)
                } else {
                    listing
                }
                HintLine(text: "Take control in Kairos on your desktop.", symbol: "desktopcomputer")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await live.loadList() }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Computer", subtitle: live.selected == nil ? "Running on your desktop" : live.watched?.heading) {
                if live.selected != nil {
                    GlassIconButton(symbol: "list.number", label: "Steps Kairos took") { showSteps = true }
                }
            }
        }
        .kScreen()
        .machineToast($toast)
        .animation(Motion.snappy, value: live.selected)
        .sheet(isPresented: $showSteps) {
            if let owner = live.selected {
                DeskComputerStepsSheet(owner: owner)
            }
        }
        .sheet(isPresented: $askStop) {
            if let owner = live.selected {
                ConfirmSheet(title: DeskComputerWire.isBot(owner) ? "Stop this bot's computer?" : "Stop this chat's computer?",
                             detail: stopDetail,
                             confirm: "Stop computer") {
                    Task {
                        let outcome = await live.stop(owner, expected: stopSeen)
                        if outcome == .done {
                            Haptics.success()
                            toast = "The computer was stopped"
                        }
                    }
                }
            }
        }
        .task(id: DeskForgeLive.connectionKey) { await keepList() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if live.phase == .paused, let owner = live.selected {
                    live.startWatching(owner)
                } else if live.selected == nil {
                    Task { await live.loadList() }
                }
            } else {
                live.pause()
            }
        }
        .onChange(of: live.selected) { _, owner in
            if owner != nil, start == .steps, !openedSteps {
                openedSteps = true
                showSteps = true
            }
        }
        .onDisappear { live.leave() }
    }

    private func keepList() async {
        guard live.on else { return }
        picked = false
        await live.loadList()
        if !picked {
            picked = true
            // One computer running: go straight to it. More than one: the person picks.
            if live.selected == nil, live.computers.count == 1, let only = live.computers.first {
                live.startWatching(only.owner)
            }
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            if Task.isCancelled { break }
            if live.selected == nil { await live.loadList() }
        }
    }

    private var stopDetail: String {
        let watched = live.watched
        let what = watched.map { $0.isBot ? "This bot's computer" : "This chat's computer" } ?? "This computer"
        // The page's own title is the website's text: it is only said as what the page shows, never as the name.
        var page = ""
        if let watched, !watched.title.isEmpty {
            let title = watched.title.count > 60 ? String(watched.title.prefix(60)) + "..." : watched.title
            page = " It is showing a page titled \"\(title)\"" + (watched.address.isEmpty ? "." : " on \(watched.address).")
        } else if let watched, !watched.address.isEmpty {
            page = " It is showing a page on \(watched.address)."
        }
        var lost = ""
        if watched?.recording == true { lost += " The recording in progress on your desktop is thrown away." }
        if watched?.takenOver == true { lost += " The person using it on your desktop loses control." }
        return "\(what) closes on your desktop.\(page) Whatever it had open is lost.\(lost) The chat or bot keeps going and can open a new computer on its next step. The last picture stays here for a short while. You cannot undo this from your iPhone."
    }

    // MARK: List

    @ViewBuilder
    private var listing: some View {
        HintLine(text: "Watching shows a computer's live screen and its page address. Recorded steps can include what was typed.", symbol: "eye")
        switch live.load {
        case .idle, .loading:
            DeskForgeLine(text: "Reading the running computers from your desktop.")
        case .failed(let why):
            DeskForgeLine(text: why, action: "Try again", perform: { Task { await live.loadList() } })
        case .loaded:
            if live.computers.isEmpty {
                DeskEmptyNote(symbol: "cursorarrow.rays", title: "No computer is running",
                              text: "A computer starts when a chat or a bot needs one on your desktop.")
                    .kCard(radius: 22)
            } else {
                let items = live.computers
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            Haptics.tap()
                            live.startWatching(item.owner)
                        } label: {
                            CardRow(symbol: item.isBot ? "cpu" : "cursorarrow.rays", title: item.heading,
                                    detail: item.title.isEmpty ? item.detail : "\(item.kindName) · \(item.detail)",
                                    value: ChatFormat.listTime(item.lastAction), last: index == items.count - 1)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                        .arrives(index)
                    }
                }
                .kCard(radius: 22)
            }
            if live.skipped > 0 {
                HintLine(text: "\(live.skipped) could not be read and are not shown.")
            }
        }
        if !live.isAdmin {
            HintLine(text: "Bots' computers are shown to admin accounts only. You see the computers your own chats use.")
        }
    }

    // MARK: One computer

    @ViewBuilder
    private func watching(_ owner: String) -> some View {
        Button {
            Haptics.tap()
            live.stopWatching()
            Task { await live.loadList() }
        } label: {
            Label("All computers", systemImage: "chevron.left")
                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.goldText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())

        let bot = DeskComputerWire.isBot(owner)
        HintLine(text: "This is the live screen of \(bot ? "a bot's" : "this chat's") computer, with its page address. Recorded steps can include what was typed.",
                 symbol: "eye")
        stateCard
        DeskComputerPicture(image: live.picture, phase: live.phase, lastEvent: live.lastEvent,
                            pictureTime: live.pictureTime, closedAt: live.closedAt, shielded: scenePhase != .active)
        controls(owner)
    }

    private var stateCard: some View {
        let state = live.watched
        return HStack(spacing: 10) {
            switch live.phase {
            case .live where state?.takenOver == true: Circle().fill(Palette.gold).frame(width: 8, height: 8)
            case .live: PulsingDot(color: Palette.working, size: 8)
            case .connecting: ProgressView().controlSize(.small).tint(Palette.goldText)
            default: Circle().fill(Palette.inkFaint).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(stateTitle(state))
                    .font(KFont.ui(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Text(stateDetail(state))
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if state?.recording == true {
                Text("Recording on your desktop")
                    .font(KFont.ui(12.5, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .kCard(radius: 18)
        .accessibilityElement(children: .combine)
    }

    private func stateTitle(_ state: DeskComputer?) -> String {
        switch live.phase {
        case .idle, .connecting: return "Opening the live screen"
        case .paused: return "Paused while Kairos is in the background"
        case .down: return "The live picture stopped"
        case .closed: return "Computer closed"
        case .live:
            if state?.takenOver == true { return "Someone has control on your desktop" }
            return state?.waitingModel == true ? "Waiting for the model" : "Kairos has control"
        }
    }

    private func stateDetail(_ state: DeskComputer?) -> String {
        guard let state else { return " " }
        var parts: [String] = []
        if !state.title.isEmpty { parts.append(state.title) }
        if !state.address.isEmpty { parts.append(state.address) }
        let page = parts.isEmpty ? state.detail : parts.joined(separator: " · ")
        guard let when = state.lastAction else { return page }
        return page + " · last action " + ChatFormat.listTime(when)
    }

    @ViewBuilder
    private func controls(_ owner: String) -> some View {
        if case .down(let why) = live.phase {
            DeskForgeLine(text: why, action: "Try again", perform: { live.startWatching(owner) })
        }
        if live.phase == .closed {
            HintLine(text: "This computer is closed. The picture is the last one the desktop kept.", symbol: "moon")
        } else {
            if live.stopPhase(owner) == .unchecked {
                // The stop could not be checked: no second Stop is offered until the desktop's list says what happened.
                DeskPillButton(title: "Check again", symbol: "arrow.clockwise") {
                    live.recheckStop(owner)
                }
            } else {
                let stopping = live.isStopping(owner)
                DeskPillButton(title: stopping ? "Stopping" : "Stop this computer", symbol: "stop.circle", tint: Palette.danger) {
                    stopSeen = live.seenNow()
                    askStop = true
                }
                .disabled(stopping)
                .opacity(stopping ? 0.5 : 1)
            }
        }
        if let note = live.note(owner) {
            HintLine(text: note, symbol: "exclamationmark.triangle", color: Palette.goldText)
        }
    }
}

// MARK: - Steps

/// The steps kept for one computer, one at a time, with the kept pictures. Nothing here changes the computer,
/// and nothing is exported or saved: the pictures live in memory until the sheet closes.
struct DeskComputerStepsSheet: View {
    let owner: String

    @State private var live = DeskComputerLive.shared
    @State private var runID: String?
    @State private var index = 0
    @State private var shot: ComputerShot = .after

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Steps")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                HintLine(text: "Steps are kept on your desktop and can include what was typed. Their pictures are not kept on this iPhone.",
                         symbol: "eye")
                content
                HintLine(text: "Export and Make a skill are in Kairos on your desktop.")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet()
        .task {
            await live.loadRuns(owner)
            if runID == nil, let runs = live.runs(owner), runs.load == .loaded, runs.runs.count == 1 { runID = runs.runs[0].id }
        }
        .task(id: runID) {
            if let runID { await live.loadSteps(runID) }
        }
        .onDisappear { live.leaveSteps() }
    }

    @ViewBuilder
    private var content: some View {
        switch live.runs(owner)?.load ?? .loading {
        case .idle, .loading:
            DeskForgeLine(text: "Reading the steps from your desktop.")
        case .failed(let why):
            DeskForgeLine(text: why, action: "Try again", perform: { Task { await live.loadRuns(owner) } })
        case .loaded:
            let runs = live.runs(owner)?.runs ?? []
            if runs.isEmpty {
                DeskEmptyNote(symbol: "list.number", title: "No steps yet", text: "No computer steps are kept for this computer yet.")
            } else if let runID {
                viewer(runID, many: runs.count > 1)
            } else {
                chooser(runs)
            }
        }
    }

    private func chooser(_ runs: [DeskComputerRun]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Choose a run")
            VStack(spacing: 0) {
                ForEach(Array(runs.enumerated()), id: \.element.id) { offset, item in
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) {
                            runID = item.id
                            index = 0
                            shot = .after
                        }
                    } label: {
                        CardRow(symbol: "play.rectangle", title: Self.when(item), detail: "\(item.count) steps", last: offset == runs.count - 1)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
            .kCard(radius: 20)
        }
    }

    private static func when(_ run: DeskComputerRun) -> String {
        guard let date = run.updated ?? run.started else { return "A run" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private func viewer(_ run: String, many: Bool) -> some View {
        switch live.steps(run)?.load ?? .loading {
        case .idle, .loading:
            DeskForgeLine(text: "Reading this run's steps from your desktop.")
        case .failed(let why):
            DeskForgeLine(text: why, action: "Try again", perform: { Task { await live.loadSteps(run) } })
        case .loaded:
            let steps = live.steps(run)?.steps ?? []
            if steps.isEmpty {
                DeskEmptyNote(symbol: "list.number", title: "No steps in this run", text: "The desktop kept no readable steps for it.")
            } else {
                let step = steps[min(index, steps.count - 1)]
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        if many {
                            Button {
                                withAnimation(Motion.snappy) {
                                    runID = nil
                                    index = 0
                                }
                            } label: {
                                Label("All runs", systemImage: "chevron.left")
                                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                                    .foregroundStyle(Palette.goldText)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(PressStyle())
                        }
                        Spacer()
                        Text("Step \(min(index, steps.count - 1) + 1) of \(steps.count)")
                            .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkDim)
                            .contentTransition(.numericText())
                    }
                    pictureBox(run, step)
                    HStack {
                        Spacer()
                        GlassSwitch(items: ComputerShot.allCases, selection: $shot) { $0.rawValue }
                        Spacer()
                    }
                    stepCard(step)
                    HStack(spacing: 10) {
                        DeskPillButton(title: "Previous", symbol: "chevron.left") {
                            withAnimation(Motion.snappy) { index = max(0, index - 1) }
                        }
                        .disabled(index == 0)
                        .opacity(index == 0 ? 0.4 : 1)
                        Spacer()
                        DeskPillButton(title: "Next", symbol: "chevron.right") {
                            withAnimation(Motion.snappy) { index = min(steps.count - 1, index + 1) }
                        }
                        .disabled(index >= steps.count - 1)
                        .opacity(index >= steps.count - 1 ? 0.4 : 1)
                    }
                    if let skipped = live.steps(run)?.skipped, skipped > 0 {
                        HintLine(text: "\(skipped) steps could not be read and are not shown.")
                    }
                    if let days = live.steps(run)?.days {
                        HintLine(text: days > 0 ? "Your desktop keeps steps for \(days) days." : "Your desktop keeps no steps.")
                    }
                }
            }
        }
    }

    private func pictureBox(_ run: String, _ step: DeskComputerStep) -> some View {
        let name = step.name(for: shot)
        let key = DeskComputerLive.pictureKey(run, step.number, name)
        let kept = step.kept.contains(name)
        return Group {
            if kept {
                if let image = live.stepPicture(key) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                        .accessibilityLabel("The \(shot.rawValue.lowercased()) picture of this step")
                } else if live.stepPictureFailed(key) {
                    VStack(spacing: 8) {
                        Text("This picture could not be read.")
                            .font(KFont.ui(14.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkDim)
                        DeskPillButton(title: "Try again") {
                            Task { await live.loadPicture(run, number: step.number, name: name) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .kCard(radius: 14)
                } else {
                    ProgressView()
                        .tint(Palette.goldText)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .kCard(radius: 14)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash").font(.system(size: 22, weight: .medium)).foregroundStyle(Palette.inkFaint)
                    Text(missing(step, name))
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 10, contentMode: .fit)
                .kCard(radius: 14)
            }
        }
        .task(id: key) {
            if kept { await live.loadPicture(run, number: step.number, name: name) }
        }
    }

    private func missing(_ step: DeskComputerStep, _ name: String) -> String {
        if name == "marker.jpg", !step.isClick { return "This step was not a click, so there is no click picture." }
        if let reason = step.reasons[name], !reason.isEmpty { return "This picture was not kept: " + reason + "." }
        return "This picture was not kept."
    }

    private func stepCard(_ step: DeskComputerStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.title)
                .font(KFont.ui(17, .medium))
                .foregroundStyle(Palette.ink)
            if !step.result.isEmpty {
                Text(step.result)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(step.failed ? Palette.danger : Palette.inkDim)
            }
            if let typed = step.typed, !typed.isEmpty {
                Text("Typed: " + typed)
                    .font(CodeFont.mono(13))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !step.address.isEmpty {
                Text(step.address)
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 18)
    }
}
