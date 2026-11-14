import SwiftUI

/// Where the desktop's Make list stands, for one plain sentence on screen.
nonisolated enum MakeHomeLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// Where a front-desk task stands (services/front_desk_work.py: project). A state this app does not know is `other`.
nonisolated enum MakeHomeJobState: Hashable, Sendable {
    case working, needsInput, ready, failed, resolved, other

    static func from(_ wire: String?) -> MakeHomeJobState {
        switch wire {
        case "working": .working
        case "needs_input": .needsInput
        case "ready_for_review": .ready
        case "failed": .failed
        case "resolved": .resolved
        default: .other
        }
    }

    /// Still being made: the card keeps reading the desktop.
    var isOpen: Bool { self == .working || self == .needsInput }
}

/// One thing being made on the desktop, as a card shows it. Only what the desktop said; no made-up progress.
nonisolated struct MakeHomeJob: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    /// What the person asked for. Only tasks this phone started or read in full carry it.
    var ask: String?
    var kind: MakeHomeKind?
    var threadID: String?
    var created: Date?
    var state: MakeHomeJobState
    var step: String
    var turnCount: Int?
}

/// The one Make tap on its way to the desktop. Its send id is kept for a retry of that same tap, never reused for another.
nonisolated struct MakeHomeSend: Hashable, Sendable {
    let sendID: String
    let text: String
    let kind: MakeHomeKind
    /// Set when the desktop's answer never arrived: the request may have started there.
    var unconfirmed: String?
}

/// How a Make tap ended.
nonisolated enum MakeHomeOutcome: Equatable, Sendable {
    case started
    /// Not sent: another tap is still on its way, or Make is not open to this account.
    case busy
    case refused(String)
    case unconfirmed
}

/// Real made files opened in the file viewer.
struct MakeHomeFileViewing: Identifiable {
    let id = UUID()
    let files: [DocsLiveFileRef]
    let index: Int
}

/// The paired desktop behind Make home and the made list: what the front desk made (GET /api/front-desk/make),
/// the videos (GET /api/videos), starting a make (POST /api/front-desk/tasks with one send id per tap),
/// one task (GET /api/front-desk/tasks/{id}) and Try again on a failed one (POST .../again with its turn count).
/// Unpaired, nothing here runs and Make shows its sample shelves and jobs.
@Observable
final class MakeHomeLive {
    static let shared = MakeHomeLive()

    private(set) var isLive = false
    private(set) var account = "sample"
    private(set) var load: MakeHomeLoad = .idle
    /// Every made item, newest first: the front desk's, then the videos.
    private(set) var items: [MakeItem] = []
    private(set) var opens: [String: MakeHomeOpen] = [:]
    private(set) var skipped = 0
    private(set) var videosProblem: String?
    /// The desktop's own list of tasks still being made.
    private(set) var making: [MakeHomeJob] = []
    /// Tasks this phone started or retried, newest first, read one by one until they finish.
    private(set) var tracked: [MakeHomeJob] = []
    private(set) var hidden: Set<String> = []
    private(set) var send: MakeHomeSend?
    /// Why the last Make tap did not start, in one line.
    private(set) var sendProblem: String?
    /// The desktop refused this account the Make box (it is not the owner of the assistant there).
    private(set) var notYours = false
    private(set) var againBusy: Set<String> = []
    private(set) var jobProblems: [String: String] = [:]

    @ObservationIgnored private var itemThreads: [String: String] = [:]
    @ObservationIgnored private var itemKinds: [String: MakeHomeKind] = [:]
    @ObservationIgnored private var itemTimes: [String: Date] = [:]
    /// The desktop's own page keeps a refused tap's send id for the same text, so a second tap of it can never
    /// start a task twice if the first one was saved before it was refused.
    @ObservationIgnored private var refusedSend: MakeHomeSend?
    @ObservationIgnored private var readSerial = 0
    @ObservationIgnored private var writeSerial = 0
    @ObservationIgnored private var jobSerial = 0

    static let desktopChanged = "Your paired desktop changed. Try again."
    static let notYoursLine = "Making from here needs this account's own assistant on your desktop. You can still open what was made."

    // MARK: Connection

    /// Paired with a desktop (whether or not it is answering): Make never shows its sample items.
    static var paired: Bool { !Connection.shared.usesSampleData }

    /// A key that changes when the phone is paired or unpaired, the desktop comes back,
    /// or a different desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// Which desktop and which account the items belong to. Live items are only ever shown under this key.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Showing the current account's items, so the screen may draw them.
    var showing: Bool { isLive && account == Self.accountKey }

    func stillLive(_ key: String) -> Bool {
        isLive && account == key && Self.accountKey == key
    }

    func followConnection() {
        let key = Self.accountKey
        if Self.paired {
            guard !isLive || account != key else { return }
            reset()
            isLive = true
            account = key
        } else if isLive {
            reset()
            isLive = false
            account = "sample"
        }
    }

    private func reset() {
        load = .idle
        items = []
        opens = [:]
        skipped = 0
        videosProblem = nil
        making = []
        tracked = []
        hidden = []
        send = nil
        sendProblem = nil
        notYours = false
        againBusy = []
        jobProblems = [:]
        itemThreads = [:]
        itemKinds = [:]
        itemTimes = [:]
        refusedSend = nil
        readSerial += 1
        jobSerial += 1
    }

    private func client() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    // MARK: What the screen shows

    func items(_ kind: MadeKind) -> [MakeItem] { items.filter { $0.kind == kind } }

    func item(_ id: String) -> MakeItem? { items.first { $0.id == id } }

    /// The cards: this phone's tasks, then the desktop's other tasks still being made.
    var cards: [MakeHomeJob] {
        let mine = Set(tracked.map(\.id))
        return tracked.filter { !hidden.contains($0.id) }
            + making.filter { !mine.contains($0.id) && !hidden.contains($0.id) }
    }

    /// Something is still being made or a tap is unconfirmed, so the screen keeps reading.
    var needsPolling: Bool { send != nil || cards.contains { $0.state.isOpen } }

    /// What a finished task made: the newest item in its own conversation, of its own kind, made after it started.
    func result(for job: MakeHomeJob) -> MakeItem? {
        guard let thread = job.threadID else { return nil }
        let after = job.created?.addingTimeInterval(-5) ?? .distantPast
        return items.first { item in
            itemThreads[item.id] == thread
                && (job.kind == nil || itemKinds[item.id] == job.kind)
                && (itemTimes[item.id] ?? .distantPast) >= after
        }
    }

    /// The shelf title for a phone kind while paired, in the desktop's words.
    static func shelfTitle(_ kind: MadeKind) -> String {
        switch kind {
        case .deck: "Slides"
        case .document: "Files"
        default: kind.plural
        }
    }

    /// The real files of one shelf, for the viewer.
    func fileRefs(_ kind: MadeKind) -> [(item: String, ref: DocsLiveFileRef)] {
        items(kind).compactMap { item in
            guard case .file(let session, let url, let name) = opens[item.id] else { return nil }
            return (item.id, DocsLiveFileRef(id: item.id, sessionID: session, url: url, name: name, bytes: 0,
                                             sizeKnown: false, origin: .generated))
        }
    }

    /// The viewer for one file item, with the other files of its shelf beside it.
    func fileViewing(_ item: MakeItem) -> MakeHomeFileViewing? {
        let refs = fileRefs(item.kind)
        guard let index = refs.firstIndex(where: { $0.item == item.id }) else { return nil }
        // The viewer belongs to Library files; it checks its own store is on this desktop before it reads.
        DocsLiveStore.shared.followConnection()
        return MakeHomeFileViewing(files: refs.map(\.ref), index: index)
    }

    // MARK: Turning answers into rows

    nonisolated static func when(_ date: Date?) -> String {
        guard let date else { return "" }
        let text = ChatFormat.listTime(date)
        return text == "now" ? "just now" : text
    }

    nonisolated static func madeItem(_ dto: MakeHomeItemDTO) -> MakeItem {
        let kind = MakeHomeKind.from(dto.kind)
        let title = (dto.title?.string).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
        return MakeItem(id: dto.id, title: title, kind: kind?.shelf ?? .document,
                        when: when(MakeHomeWire.time(dto.updatedAt)), detail: kind?.title ?? "File", size: "",
                        fresh: false, source: "Make")
    }

    nonisolated static func videoItem(_ dto: MakeHomeVideoDTO) -> MakeItem {
        var parts: [String] = []
        if let aspect = dto.aspects?.first, !aspect.isEmpty { parts.append(aspect) }
        if dto.beatCount > 0 { parts.append(dto.beatCount == 1 ? "1 beat" : "\(dto.beatCount) beats") }
        let title = (dto.title).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled video"
        return MakeItem(id: "video:" + dto.id, title: title, kind: .video, when: when(MakeHomeWire.time(dto.updated)),
                        detail: parts.joined(separator: " · "), size: "", fresh: false, source: "Video editor")
    }

    nonisolated static func job(_ dto: MakeHomeTaskDTO) -> MakeHomeJob {
        let title = (dto.title).flatMap { $0.isEmpty ? nil : $0 } ?? "Making something for you"
        return MakeHomeJob(id: dto.id, title: title, ask: dto.ask, kind: MakeHomeKind.from(dto.makeKind),
                           threadID: dto.threadId, created: MakeHomeWire.time(dto.createdAt),
                           state: MakeHomeJobState.from(dto.state), step: dto.nextStep ?? "", turnCount: dto.turnCount?.int)
    }

    // MARK: Reading

    func loadLiveIfNeeded() async {
        switch load {
        case .idle, .failed: await loadLive()
        case .loading, .loaded: break
        }
    }

    /// Read the made list and the videos. Already read, they stay on screen while this runs. An older read never
    /// replaces a newer one, and a read that was on its way while a Make tap finished is read again.
    @discardableResult
    func loadLive() async -> Bool {
        guard isLive else { return false }
        let key = account
        readSerial += 1
        let mine = readSerial
        if load != .loaded { load = .loading }
        for _ in 0..<3 {
            let writes = writeSerial
            do {
                let list = try await client().makeHomeList()
                guard stillLive(key), mine == readSerial else { return false }
                var videos: MakeHomeVideosDTO?
                var videoError: Error?
                do {
                    videos = try await client().makeHomeVideos()
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        if mine == readSerial, load == .loading { load = .idle }
                        return false
                    }
                    videoError = error
                }
                guard stillLive(key), mine == readSerial else { return false }
                guard writes == writeSerial else { continue }
                show(list, videos: videos)
                videosProblem = videoError.map { "Your videos could not be read. " + $0.plainWords }
                load = .loaded
                return true
            } catch {
                if error is CancellationError || Task.isCancelled {
                    if mine == readSerial, load == .loading { load = .idle }
                    return false
                }
                Connection.shared.note(error)
                guard stillLive(key), mine == readSerial else { return false }
                load = .failed("What you made could not be read from your desktop. " + error.plainWords)
                return false
            }
        }
        guard stillLive(key), mine == readSerial else { return false }
        if load != .loaded { load = .failed("Your desktop kept changing while it was read. Try again.") }
        return false
    }

    private func show(_ list: MakeHomeListDTO, videos: MakeHomeVideosDTO?) {
        var fresh: [MakeItem] = []
        var links: [String: MakeHomeOpen] = [:]
        var threads: [String: String] = [:]
        var kinds: [String: MakeHomeKind] = [:]
        var times: [String: Date] = [:]
        var seen = Set<String>()
        for dto in list.items {
            guard seen.insert(dto.id).inserted else { continue }
            fresh.append(Self.madeItem(dto))
            if let link = MakeHomeWire.open(dto) { links[dto.id] = link }
            if let thread = dto.open?.sessionId { threads[dto.id] = thread }
            if let kind = MakeHomeKind.from(dto.kind) { kinds[dto.id] = kind }
            if let time = MakeHomeWire.time(dto.updatedAt) { times[dto.id] = time }
        }
        var skippedNow = list.skipped
        if let videos {
            skippedNow += videos.skipped
            for dto in videos.videos {
                guard seen.insert("video:" + dto.id).inserted else { continue }
                let item = Self.videoItem(dto)
                fresh.append(item)
                if MakeHomeWire.isHex(dto.id, 12) { links[item.id] = .video(dto.id) }
            }
        } else {
            // The videos were not read this time: the ones already shown stay.
            for item in items where item.kind == .video {
                guard seen.insert(item.id).inserted else { continue }
                fresh.append(item)
                if let link = opens[item.id] { links[item.id] = link }
            }
        }
        items = fresh
        opens = links
        itemThreads = threads
        itemKinds = kinds
        itemTimes = times
        skipped = skippedNow
        making = list.making.map(Self.job)
    }

    /// Read every task this phone is following that is still being made.
    private func refreshTracked() async {
        guard isLive else { return }
        let key = account
        jobSerial += 1
        let mine = jobSerial
        var finished = false
        defer {
            // A task that just finished made something: read the list again so its item is there to open.
            if finished, stillLive(key) { Task { [weak self] in await self?.loadLive() } }
        }
        for job in tracked where job.state.isOpen || job.state == .other {
            guard !againBusy.contains(job.id) else { continue }
            let writes = writeSerial
            do {
                let dto = try await client().makeHomeTask(job.id)
                guard stillLive(key), mine == jobSerial else { return }
                guard writes == writeSerial, !againBusy.contains(job.id) else { continue }
                if job.state.isOpen && !MakeHomeJobState.from(dto.state).isOpen { finished = true }
                update(dto)
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                Connection.shared.note(error)
                guard stillLive(key), mine == jobSerial else { return }
                if Self.status(error) == 404 { tracked.removeAll { $0.id == job.id } }
            }
        }
    }

    /// One poll while something is being made: the list, then each followed task.
    func poll() async {
        guard isLive else { return }
        await loadLive()
        await refreshTracked()
    }

    private func update(_ dto: MakeHomeTaskDTO) {
        var job = Self.job(dto)
        if let index = tracked.firstIndex(where: { $0.id == dto.id }) {
            if job.ask == nil { job.ask = tracked[index].ask }
            if job.kind == nil { job.kind = tracked[index].kind }
            tracked[index] = job
        } else {
            tracked.insert(job, at: 0)
        }
    }

    private static func status(_ error: Error) -> Int? {
        if case .server(let status, _) = error as? APIError { return status }
        return nil
    }

    /// The desktop refused the request, so it certainly did not do it.
    private static func wasRefused(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
    }

    // MARK: Making

    /// One Make tap: one send id, kept for a retry of this same tap. The text stays in the box until the
    /// desktop says it started.
    func start(text: String, kind: MakeHomeKind, fresh: Bool = false) async -> MakeHomeOutcome {
        guard isLive, send == nil, !notYours else { return .busy }
        let key = account
        guard stillLive(key) else { return .refused(Self.desktopChanged) }
        let id: String
        if !fresh, let refused = refusedSend, refused.text == text, refused.kind == kind {
            id = refused.sendID
        } else {
            id = MakeHomeWire.newSendID()
        }
        send = MakeHomeSend(sendID: id, text: text, kind: kind, unconfirmed: nil)
        sendProblem = nil
        return await deliver(key)
    }

    /// Send the unconfirmed tap again, with the same send id, text and kind, so it can never start twice.
    func retrySend() async -> MakeHomeOutcome {
        guard isLive, var pending = send, pending.unconfirmed != nil else { return .busy }
        let key = account
        guard stillLive(key) else { return .refused(Self.desktopChanged) }
        pending.unconfirmed = nil
        send = pending
        return await deliver(key)
    }

    /// Stop waiting on an unconfirmed tap. What the desktop has shows in the list.
    func leaveSend() {
        guard let pending = send, pending.unconfirmed != nil else { return }
        // A later tap of the same text reuses this id, so a request the desktop did save is not started twice.
        refusedSend = MakeHomeSend(sendID: pending.sendID, text: pending.text, kind: pending.kind, unconfirmed: nil)
        send = nil
    }

    private func deliver(_ key: String) async -> MakeHomeOutcome {
        guard let sent = send else { return .busy }
        defer { writeSerial += 1 }
        do {
            let dto = try await client().makeHomeStart(text: sent.text, kind: sent.kind, sendID: sent.sendID)
            // Another desktop or account is showing now: nothing from this answer is drawn or cleared.
            guard stillLive(key), send?.sendID == sent.sendID else { return .busy }
            send = nil
            // Only this tap's own kept id is done with. A kept id for other words stays, so those words cannot start twice.
            if refusedSend?.sendID == sent.sendID { refusedSend = nil }
            var job = Self.job(dto)
            if job.ask == nil { job.ask = sent.text }
            if job.kind == nil { job.kind = sent.kind }
            tracked.removeAll { $0.id == job.id }
            tracked.insert(job, at: 0)
            hidden.remove(job.id)
            Task { [weak self] in
                guard let self, self.stillLive(key) else { return }
                await self.loadLive()
            }
            return .started
        } catch {
            Connection.shared.note(error)
            guard stillLive(key), send?.sendID == sent.sendID else { return .refused(error.plainWords) }
            if Self.wasRefused(error) {
                send = nil
                let line: String
                let api = error as? APIError
                switch api {
                case .some(.server(status: 404, let detail)) where detail == "Task or suggestion not found":
                    // The desktop says this for a member account, and also when a start broke part way after
                    // it saved the task. Keep the id. Only a second refusal of this same id, on an account with
                    // no task of its own, gets the member line.
                    let again = refusedSend?.sendID == sent.sendID
                    refusedSend = sent
                    if again && tracked.isEmpty && making.isEmpty {
                        notYours = true
                        line = Self.notYoursLine
                    } else {
                        line = "Your desktop did not start this. Tap Make to try once more."
                    }
                case .some(.server(status: 404, _)):
                    line = "Your desktop cannot start this yet. It may need a newer Kairos."
                case .some(.server(status: 409, _)):
                    refusedSend = sent
                    line = "Your desktop already has a different request under this send, so nothing new was started. What it is making shows below."
                default:
                    refusedSend = sent
                    line = "Your desktop did not start this. " + error.plainWords
                }
                sendProblem = notYours ? nil : line
                return .refused(line)
            }
            // The answer was lost: the desktop may have started it. Keep this tap and its id, and read what is there.
            send?.unconfirmed = "Your desktop did not confirm this request. It may already be making it. "
                + "Check again sends this same request, so it cannot start twice. " + error.plainWords
            await loadLive()
            return .unconfirmed
        }
    }

    /// Try again on a failed task, the desktop's way: with the turn count read with the failure, so a second
    /// tap never repeats a newer failure. A lost answer reads the task again and shows what it has.
    func again(_ id: String) async {
        guard isLive, let job = tracked.first(where: { $0.id == id }), job.state == .failed,
              let count = job.turnCount, !againBusy.contains(id) else { return }
        let key = account
        againBusy.insert(id)
        jobProblems[id] = nil
        defer {
            writeSerial += 1
            if account == key { againBusy.remove(id) }
        }
        do {
            let dto = try await client().makeHomeAgain(id, turnCount: count)
            guard stillLive(key) else { return }
            update(dto)
        } catch {
            Connection.shared.note(error)
            guard stillLive(key) else { return }
            if Self.status(error) == 404 {
                tracked.removeAll { $0.id == id }
                return
            }
            if Self.wasRefused(error) {
                jobProblems[id] = "It was not sent again. " + error.plainWords
                return
            }
            jobProblems[id] = "Your desktop did not confirm Try again. This card shows what it has now."
            if let dto = try? await client().makeHomeTask(id), stillLive(key) { update(dto) }
        }
    }

    /// Hide a finished card on this phone. Nothing changes on the desktop.
    func hide(_ id: String) {
        guard let job = cards.first(where: { $0.id == id }), !job.state.isOpen else { return }
        hidden.insert(id)
        tracked.removeAll { $0.id == id }
    }
}

// MARK: - Views

/// One quiet line on Make: loading, or what failed, with one plain action.
struct MakeHomeLine: View {
    let text: String
    var action: String? = nil
    var perform: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let action, let perform {
                Button {
                    Haptics.tap()
                    perform()
                } label: {
                    Text(action)
                        .font(KFont.ui(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.goldText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(minHeight: 48)
        .kCard(radius: 16)
    }
}

/// The Make tap while it is on its way, or after its answer was lost.
struct MakeHomeSendCard: View {
    let send: MakeHomeSend
    let retry: () -> Void
    let leave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: send.kind.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.goldText)
                Text(send.unconfirmed == nil ? "Sending" : "Not confirmed")
                    .font(KFont.label).tracking(1.2).textCase(.uppercase).foregroundStyle(Palette.inkFaint)
                Spacer(minLength: 0)
                Text(send.kind.title).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            }
            Text(send.text).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink).lineLimit(2)
            if let unconfirmed = send.unconfirmed {
                Text(unconfirmed)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    MakePillButton(title: "Check again", filled: true, expand: true, action: retry)
                    MakePillButton(title: "Leave it", expand: true, action: leave)
                }
            } else {
                HStack(spacing: 8) {
                    PulsingDot(color: Palette.working, size: 7)
                    Text("Asking your desktop to make this. It is made there, with your assistant's model.")
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .kCard(radius: 24, raised: true)
    }
}

/// A task on the desktop: what it says now, with Open, Make another or Try again when they apply.
struct MakeHomeJobCard: View {
    let job: MakeHomeJob
    let result: MakeItem?
    let busy: Bool
    let problem: String?
    /// Another tap is on its way, or Make is not open to this account.
    let canMake: Bool
    let open: (MakeItem) -> Void
    let makeAnother: () -> Void
    let again: () -> Void
    let hide: () -> Void

    private var label: String {
        switch job.state {
        case .working: "Making on your desktop"
        case .needsInput: "Needs you"
        case .ready: "Made"
        case .failed: "Could not finish"
        case .resolved: "Done"
        case .other: "On your desktop"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: job.kind?.symbol ?? "sparkles").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.goldText)
                Text(label).font(KFont.label).tracking(1.2).textCase(.uppercase).foregroundStyle(Palette.inkFaint)
                Spacer(minLength: 0)
                if let kind = job.kind {
                    Text(kind.title).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                if !job.state.isOpen {
                    Button(action: hide) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkFaint).frame(width: 44, height: 32)
                    }
                    .accessibilityLabel("Hide this card")
                }
            }

            if job.state == .ready, let result {
                HStack(spacing: 12) {
                    MadeArt(item: result)
                        .frame(width: 96, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                        Text("\(result.detail) · \(result.when)").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    MakePillButton(title: "Open", filled: true, expand: true) { open(result) }
                    if job.ask != nil {
                        MakePillButton(title: "Make another", expand: true, action: makeAnother)
                            .disabled(!canMake)
                            .opacity(canMake ? 1 : 0.5)
                    }
                }
            } else {
                Text(job.title).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                switch job.state {
                case .working:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        PulsingDot(color: Palette.working, size: 7)
                        Text(job.step.isEmpty || job.step == "Just started" ? "Your desktop is making this." : job.step)
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkDim)
                            .lineLimit(3)
                    }
                case .needsInput:
                    if !job.step.isEmpty { Text(job.step).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.ink).lineLimit(4) }
                    HintLine(text: "Answer it in Kairos on your desktop, in this task's conversation.")
                case .ready:
                    HintLine(text: "Made. It is with your other made things below.")
                    if job.ask != nil {
                        MakePillButton(title: "Make another", action: makeAnother)
                            .disabled(!canMake)
                            .opacity(canMake ? 1 : 0.5)
                    }
                case .failed:
                    if !job.step.isEmpty { Text(job.step).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim).lineLimit(3) }
                    if job.turnCount != nil {
                        MakePillButton(title: busy ? "Sending" : "Try again", symbol: "arrow.clockwise", filled: true, action: again)
                            .disabled(busy)
                    }
                case .resolved, .other:
                    if !job.step.isEmpty { Text(job.step).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim).lineLimit(3) }
                }
            }
            if let problem { HintLine(text: problem) }
        }
        .padding(16)
        .kCard(radius: 24, raised: true)
        .animation(Motion.bouncy, value: job.state)
    }
}
