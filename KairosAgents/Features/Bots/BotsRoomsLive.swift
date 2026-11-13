import SwiftUI

// The paired desktop behind a room (routes/bot_room_routes.py): the room, its messages, sending, stop, hold,
// the waiting queue, pin, settings, members and conversations. Unpaired, nothing here runs and RoomScreen shows
// BotsStore's sample rooms exactly as before. Everything read here belongs to one desktop and one account; a
// result that lands for another is dropped. Live updates are a short poll while a room is on screen
// (BotRoomLiveScreen); the desktop's event stream is not used yet.

/// Small pure helpers, also used by the decode checks.
nonisolated enum BotRoomLiveMap {
    /// A send id made on this iPhone: 8 to 80 characters, as the desktop asks.
    static func sendID() -> String { "phone-" + UUID().uuidString.lowercased() }

    /// "Auto chooses who answers" and the rest, as the sample screen words them.
    static func whoAnswers(_ responder: BotRmResponder, name: (String) -> String) -> String {
        switch responder {
        case .auto: return "Auto chooses who answers"
        case .everyone: return "Everyone answers"
        case .mentions: return "Only mentioned bots answer"
        case .member(let id): return "\(name(id)) answers"
        }
    }

    /// A length as the desktop counts it (Python `len`: code points), not as the screen draws it.
    static func length(_ text: String) -> Int { text.unicodeScalars.count }

    /// The 409 of a stale `expected_revision` (bot_rooms_store.update_room, bot_rooms.update). Any other 409 is a
    /// refusal that a second save of the same thing gets again.
    static func isStale(_ detail: String) -> Bool { detail.hasPrefix("The room changed") }

    /// The 409 for members changed while the room works or waits on a card (bot_rooms._blocked_by_work).
    static func isBusy(_ detail: String) -> Bool { detail.hasPrefix("This room is working") }

    /// Whether the newest page of a conversation joins what is loaded, so merging it leaves no hole.
    /// `tail`: the newest seq that came from a page read (rows added one by one do not count). `oldestRead`: the
    /// oldest seq of the new page. `older`: the desktop has rows before the page. Seqs are room-wide, so a
    /// conversation's seqs have gaps; a page that starts at or below `tail` holds every row after it.
    static func joins(tail: Int?, oldestRead: Int?, older: Bool) -> Bool {
        guard let tail else { return false }
        guard older, let oldestRead else { return true }
        return oldestRead <= tail
    }
}

/// Where one of this iPhone's messages stands until the desktop's list shows it.
nonisolated enum BotRmSendState: Equatable, Sendable {
    case sending
    /// The answer was lost: the desktop's messages are being read to look for its send id.
    case checking
    /// The answer was lost and the desktop could not be read to check.
    case unchecked
    /// The answer was lost and the desktop's messages do not have it. Sending again uses the same send id.
    case notSent(String)
    /// The desktop refused it. Nothing was stored.
    case refused(String)
}

/// A message typed on this iPhone. Its text stays here until the desktop has it.
nonisolated struct BotRmOutgoing: Identifiable, Equatable, Sendable {
    let sendID: String
    let roomID: String
    let threadID: String?
    let text: String
    var state: BotRmSendState
    var id: String { sendID }
}

/// How a write a sheet waits on came back.
nonisolated enum BotRmOutcome: Equatable, Sendable {
    case done(String)
    /// Nothing was saved, and the same save would be refused again: the desktop's own words.
    case refused(String)
    /// 409 for a stale revision: the room changed on the desktop. It was read again; what was typed stays.
    case changed(String)
    /// 409 because the room is working or waiting on a card: nothing was saved; the same save can work once it is idle.
    case busy(String)
    /// The answer was lost. `checked`: the desktop was read again since and does not have the change.
    case unsure(String, checked: Bool)
}

/// What `createRoom` came back with.
nonisolated enum BotRmCreateOutcome: Equatable, Sendable {
    case created(String)
    case refused(String)
    /// The answer was lost. Nothing is sent again until a read of the desktop's rooms settles it.
    case unsure(String)
}

/// A room create whose answer was lost: what to look for before sending again.
nonisolated struct BotRmCreateCheck: Equatable, Sendable {
    var name: String
    var members: Set<String>
    var before: Set<String>
}

/// The settings and members a sheet edits, read from the desktop's room.
nonisolated struct BotRoomLiveForm: Equatable, Sendable {
    var name: String
    var responder: BotRmResponder
    var turnLimit: Int
    var bulletin: String
    var members: [String]

    init(name: String, responder: BotRmResponder, turnLimit: Int, bulletin: String, members: [String]) {
        self.name = name
        self.responder = responder
        self.turnLimit = turnLimit
        self.bulletin = bulletin
        self.members = members
    }

    init(_ room: BotRoomDTO) {
        name = room.name ?? ""
        responder = BotRmResponder.read(room.defaultResponder)
        turnLimit = Int(room.turnTimeoutMinutes ?? 5)
        bulletin = room.bulletin ?? ""
        members = (room.members ?? []).compactMap(\.botId)
    }

    static let blank = BotRoomLiveForm(name: "", responder: .mentions, turnLimit: 5, bulletin: "", members: [])

    /// After the desktop changed: what was typed stays, and every field left alone takes the desktop's value.
    func rebased(from old: BotRoomLiveForm, onto desk: BotRoomLiveForm) -> BotRoomLiveForm {
        var out = self
        if Self.clean(name) == Self.clean(old.name) { out.name = desk.name }
        if responder.sameChoice(old.responder) { out.responder = desk.responder }
        if turnLimit == old.turnLimit { out.turnLimit = desk.turnLimit }
        if Self.clean(bulletin) == Self.clean(old.bulletin) { out.bulletin = desk.bulletin }
        if members == old.members { out.members = desk.members }
        return out
    }

    private static func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Only what changed from `base`, as the desktop takes it.
    func changes(from base: BotRoomLiveForm) -> [String: Any] {
        var out: [String: Any] = [:]
        if Self.clean(name) != Self.clean(base.name) { out["name"] = Self.clean(name) }
        if !responder.sameChoice(base.responder) { out["default_responder"] = responder.wire }
        if turnLimit != base.turnLimit { out["turn_timeout_minutes"] = turnLimit }
        if Self.clean(bulletin) != Self.clean(base.bulletin) { out["bulletin"] = Self.clean(bulletin) }
        if members != base.members { out["member_ids"] = members }
        return out
    }

    /// Every field this form changed from `base` is what the desktop has in `room`.
    func landed(in room: BotRoomDTO, from base: BotRoomLiveForm) -> Bool {
        let desk = BotRoomLiveForm(room)
        let sent = changes(from: base)
        if sent["name"] != nil && Self.clean(desk.name) != Self.clean(name) { return false }
        if sent["default_responder"] != nil && !desk.responder.sameChoice(responder) { return false }
        if sent["turn_timeout_minutes"] != nil && desk.turnLimit != turnLimit { return false }
        if sent["bulletin"] != nil && Self.clean(desk.bulletin) != Self.clean(bulletin) { return false }
        if sent["member_ids"] != nil && desk.members != members { return false }
        return true
    }
}

@Observable
final class BotRoomLiveStore {
    static let shared = BotRoomLiveStore()

    var rooms: [String: BotRoomDTO] = [:]
    var roomLoad: [String: BotsLiveLoad] = [:]
    /// Rooms the desktop answered 404 for.
    var gone: Set<String> = []
    /// Rooms whose last poll did not reach the desktop: what is on screen may be behind.
    var trouble: Set<String> = []
    /// The shown conversation's messages, oldest first.
    var messages: [String: [BotRmMessageDTO]] = [:]
    var messagesLoad: [String: BotsLiveLoad] = [:]
    /// The conversation each room shows.
    var threadOf: [String: String] = [:]
    var hasMore: [String: Bool] = [:]
    var olderLoading: Set<String> = []
    /// Rows of the last read this app could not read.
    var skipped: [String: Int] = [:]
    var queue: [String: [BotRmQueueItemDTO]] = [:]
    var threads: [String: [BotRmThreadDTO]] = [:]
    var threadsLoad: [String: BotsLiveLoad] = [:]
    var outgoing: [BotRmOutgoing] = []
    /// What is typed in each room's composer, kept while the room is closed.
    var drafts: [String: String] = [:]
    /// Writes on their way, by a key ("stop|room|bot", "hold|room|bot", "pin|room", "queue|id", "thread|id").
    var busy: Set<String> = []
    var createCheck: BotRmCreateCheck?
    /// The desktop's rooms (not archived), for the rooms list. Nil until this account's first read lands.
    var roomList: [BotRoomDTO]?
    var roomListLoad: BotsLiveLoad = .idle
    /// Rows of the last list read this app could not read.
    var roomListSkipped = 0

    @ObservationIgnored private var account = "sample"
    @ObservationIgnored private var roomListSeq = 0
    /// The newest seq of the shown conversation that came from a page read: rows after it may not be loaded yet.
    @ObservationIgnored private var tailSeq: [String: Int] = [:]
    /// The room's newest seq (any conversation) as the last page read said.
    @ObservationIgnored private var pageLast: [String: Int] = [:]
    @ObservationIgnored private var writing = 0
    @ObservationIgnored private var writeGeneration = 0
    @ObservationIgnored private var roomSeq: [String: Int] = [:]
    @ObservationIgnored private var messageSeq: [String: Int] = [:]
    @ObservationIgnored private var queueSeq: [String: Int] = [:]
    @ObservationIgnored private var threadSeq: [String: Int] = [:]
    @ObservationIgnored private var readUpTo: [String: Int] = [:]
    /// A conversation create whose answer was lost and not checked, by room.
    @ObservationIgnored private var threadCheck: [String: (title: String, before: Set<String>)] = [:]

    // MARK: Which desktop

    /// Paired: the room screen reads from here, never from the samples.
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

    /// Another desktop or account, or unpairing, drops everything read before.
    func followConnection() {
        let want = active ? Self.accountKey : "sample"
        guard want != account else { return }
        // Unsent messages and drafts belong to the desktop they were typed for: they are not sent anywhere else.
        let typed = drafts.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if account != "sample" && (!outgoing.isEmpty || typed) {
            say("Room messages and drafts not yet on your previous desktop were cleared from this iPhone.")
        }
        roomList = nil
        roomListLoad = .idle
        roomListSkipped = 0
        roomListSeq += 1
        tailSeq = [:]
        pageLast = [:]
        rooms = [:]
        roomLoad = [:]
        gone = []
        trouble = []
        messages = [:]
        messagesLoad = [:]
        threadOf = [:]
        hasMore = [:]
        olderLoading = []
        skipped = [:]
        queue = [:]
        threads = [:]
        threadsLoad = [:]
        outgoing = []
        drafts = [:]
        busy = []
        createCheck = nil
        writing = 0
        writeGeneration += 1
        for key in roomSeq.keys { roomSeq[key, default: 0] += 1 }
        for key in messageSeq.keys { messageSeq[key, default: 0] += 1 }
        for key in queueSeq.keys { queueSeq[key, default: 0] += 1 }
        for key in threadSeq.keys { threadSeq[key, default: 0] += 1 }
        readUpTo = [:]
        threadCheck = [:]
        account = want
    }

    private func stillLive(_ account: String) -> Bool {
        active && self.account == account && Self.accountKey == account
    }

    /// What was read belongs to the desktop and account paired right now.
    var isCurrent: Bool { active && account == Self.accountKey }

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

    private func say(_ text: String) { BotsStore.shared.say(text) }

    // MARK: What the screen asks

    /// The rooms list: the desktop's rooms, never a sample one.
    func shownRoomList() -> [BotRoomDTO] { isCurrent ? (roomList ?? []) : [] }

    /// Reading until this account's first list read has landed.
    func roomListState() -> BotsLiveLoad {
        guard isCurrent else { return .loading }
        return roomListLoad == .idle ? .loading : roomListLoad
    }

    func room(_ id: String) -> BotRoomDTO? { isCurrent ? rooms[id] : nil }

    func isGone(_ id: String) -> Bool { isCurrent && gone.contains(id) }

    /// Reading until this account's first read of the room has landed.
    func roomState(_ id: String) -> BotsLiveLoad {
        guard isCurrent else { return .loading }
        let state = roomLoad[id] ?? .idle
        return state == .idle ? .loading : state
    }

    func messageState(_ id: String) -> BotsLiveLoad {
        guard isCurrent else { return .loading }
        let state = messagesLoad[id] ?? .idle
        return state == .idle ? .loading : state
    }

    func shownMessages(_ id: String) -> [BotRmMessageDTO] { isCurrent ? (messages[id] ?? []) : [] }

    /// This iPhone's messages for the shown conversation that the desktop's list does not show yet.
    func pending(_ id: String) -> [BotRmOutgoing] {
        guard isCurrent else { return [] }
        let thread = threadOf[id]
        return outgoing.filter { $0.roomID == id && ($0.threadID == nil || $0.threadID == thread) }
    }

    func shownQueue(_ id: String) -> [BotRmQueueItemDTO] {
        guard isCurrent else { return [] }
        let thread = threadOf[id]
        return (queue[id] ?? []).filter { thread == nil || $0.threadId == nil || $0.threadId == thread }
    }

    func shownThreads(_ id: String) -> [BotRmThreadDTO] { isCurrent ? (threads[id] ?? []) : [] }

    /// A member's name: the room's own list first, then the roster.
    func name(_ roomID: String, _ botID: String) -> String {
        if let found = rooms[roomID]?.members?.first(where: { $0.botId == botID })?.name, !found.isEmpty { return found }
        return BotsStore.shared.bot(botID).name
    }

    func whoAnswers(_ roomID: String) -> String {
        guard let room = rooms[roomID] else { return "" }
        return BotRoomLiveMap.whoAnswers(BotRmResponder.read(room.defaultResponder)) { name(roomID, $0) }
    }

    /// Members cannot change while the room works or a member waits on a card (bot_rooms.py: _blocked_by_work).
    func locked(_ roomID: String) -> Bool {
        guard let room = rooms[roomID] else { return true }
        return room.working == true || (room.members ?? []).contains { $0.working == true || $0.waiting == true }
    }

    /// The room can take a message from this iPhone now.
    func canSend(_ roomID: String) -> Bool {
        guard let room = room(roomID), messageState(roomID) == .loaded else { return false }
        return room.archivedAt == nil && room.setupState != "pending"
    }

    // MARK: Reading

    /// Read the desktop's rooms for the rooms list. A failed read after a good one keeps the list and says so.
    func loadRoomList() async {
        followConnection()
        guard active else { return }
        await BotsStore.waitWhileConnecting()
        guard active else { return }
        followConnection()
        let account = self.account
        roomListSeq += 1
        let seq = roomListSeq
        if roomList == nil { roomListLoad = .loading }
        do {
            let answer = try await client().botRoomList()
            guard stillLive(account), roomListSeq == seq else { return }
            let (items, left) = BotRoutineWire.items(answer.rooms)
            roomList = items
            roomListSkipped = left
            roomListLoad = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), roomListSeq == seq else { return }
            if error is CancellationError {
                if roomListLoad == .loading { roomListLoad = .idle }
            } else {
                roomListLoad = .failed("Your rooms could not be read. " + error.plainWords)
            }
        }
    }

    /// The first look at a room: the room, its newest messages, its queue, then mark it read.
    func open(_ roomID: String) async {
        followConnection()
        guard active else { return }
        await BotsStore.waitWhileConnecting()
        guard active else { return }
        await loadRoom(roomID)
        guard rooms[roomID] != nil else { return }
        await loadMessages(roomID)
        await loadQueue(roomID)
        await markRead(roomID)
    }

    /// One poll while the room is on screen.
    func poll(_ roomID: String) async {
        guard active, rooms[roomID] != nil, !gone.contains(roomID) else { return }
        await loadRoom(roomID)
        guard rooms[roomID] != nil else { return }
        await loadMessages(roomID)
        if rooms[roomID]?.working == true || !(queue[roomID] ?? []).isEmpty {
            await loadQueue(roomID)
        }
        await markRead(roomID)
    }

    /// Read the room. Answers it when read. A read that began before a write finished does not replace what is
    /// shown (the write reads again itself), unless `force`. A forced read overtaken by a later read (a poll)
    /// still answers what the desktop said, so a check after a write is never reported as "no answer"; only
    /// the later read updates what is shown.
    @discardableResult
    func loadRoom(_ id: String, force: Bool = false) async -> BotRoomDTO? {
        guard active else { return nil }
        let account = self.account
        let seq = (roomSeq[id] ?? 0) + 1
        roomSeq[id] = seq
        if rooms[id] == nil { roomLoad[id] = .loading }
        let generation = writeGeneration
        do {
            let room = try await client().botRoomGet(id)
            guard stillLive(account) else { return nil }
            guard roomSeq[id] == seq else { return force ? room : nil }
            trouble.remove(id)
            gone.remove(id)
            if force || rooms[id] == nil || (writing == 0 && generation == writeGeneration) {
                rooms[id] = room
            }
            roomLoad[id] = .loaded
            return room
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), roomSeq[id] == seq else { return nil }
            if error is CancellationError {
                if roomLoad[id] == .loading { roomLoad[id] = .idle }
            } else if status(error) == 404 {
                gone.insert(id)
                rooms[id] = nil
                roomLoad[id] = .loaded
            } else if rooms[id] == nil {
                roomLoad[id] = .failed("This room could not be read. " + error.plainWords)
            } else {
                trouble.insert(id)
            }
            return nil
        }
    }

    /// Read the newest messages of the shown conversation. When the page joins what is loaded it is added to it;
    /// when rows may be missing between them (the room was closed or the app was away while many messages came),
    /// the page replaces what was loaded and "Show earlier messages" reads back from it, so the transcript never
    /// has a silent hole. Answers the rows read.
    @discardableResult
    func loadMessages(_ id: String, limit: Int = 50) async -> [BotRmMessageDTO]? {
        guard active else { return nil }
        let account = self.account
        let seq = (messageSeq[id] ?? 0) + 1
        messageSeq[id] = seq
        let thread = threadOf[id]
        if messages[id] == nil { messagesLoad[id] = .loading }
        do {
            let page = try await client().botRoomMessages(id, threadID: thread, limit: limit)
            guard stillLive(account), messageSeq[id] == seq, threadOf[id] == thread else { return nil }
            let (read, left) = BotRoutineWire.items(page.messages)
            let rows = read.sorted { ($0.seq ?? 0) < ($1.seq ?? 0) }
            let older = page.hasMore ?? false
            if thread == nil, let shown = page.threadId { threadOf[id] = shown }
            let joined = messages[id] != nil
                && BotRoomLiveMap.joins(tail: tailSeq[id], oldestRead: rows.first?.seq, older: older)
            if joined {
                merge(id, rows)
                if !older { hasMore[id] = false }
            } else {
                messages[id] = []
                merge(id, rows)
                hasMore[id] = older
            }
            if let newest = rows.compactMap(\.seq).max() {
                tailSeq[id] = joined ? max(newest, tailSeq[id] ?? 0) : newest
            } else if !joined {
                tailSeq[id] = 0
            }
            if let last = page.lastSeq { pageLast[id] = last }
            skipped[id] = left
            messagesLoad[id] = .loaded
            settle(id, rows)
            return rows
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), messageSeq[id] == seq else { return nil }
            if error is CancellationError {
                if messagesLoad[id] == .loading { messagesLoad[id] = .idle }
            } else if status(error) == 404, thread != nil {
                // The conversation was deleted on the desktop: show the room's first one.
                threadOf[id] = nil
                clearShown(id)
                say("That conversation is no longer on your desktop.")
            } else if messages[id] == nil {
                messagesLoad[id] = .failed("Messages could not be read. " + error.plainWords)
            } else {
                trouble.insert(id)
            }
            return nil
        }
    }

    /// The page before the oldest loaded message.
    func loadOlder(_ id: String) async {
        guard active, !olderLoading.contains(id), let before = messages[id]?.first?.seq else { return }
        let account = self.account
        let thread = threadOf[id]
        olderLoading.insert(id)
        defer { if stillLive(account) { olderLoading.remove(id) } }
        do {
            let page = try await client().botRoomMessages(id, threadID: thread, limit: 50, before: before)
            // What is loaded was replaced meanwhile: this page would not join it. The button stays to read again.
            guard stillLive(account), threadOf[id] == thread, messages[id]?.first?.seq == before else { return }
            merge(id, BotRoutineWire.items(page.messages).items)
            hasMore[id] = page.hasMore ?? false
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), !(error is CancellationError) else { return }
            say("Earlier messages could not be read. " + error.plainWords)
        }
    }

    /// Forget the shown conversation's rows; the next read starts it again.
    private func clearShown(_ id: String) {
        messages[id] = nil
        hasMore[id] = nil
        tailSeq[id] = nil
        pageLast[id] = nil
        messagesLoad[id] = .idle
    }

    private func merge(_ id: String, _ rows: [BotRmMessageDTO]) {
        var byID: [String: BotRmMessageDTO] = [:]
        for row in messages[id] ?? [] { byID[row.id] = row }
        for row in rows { byID[row.id] = row }
        let thread = threadOf[id]
        messages[id] = byID.values
            .filter { thread == nil || $0.threadId == nil || $0.threadId == thread }
            .sorted { ($0.seq ?? 0) < ($1.seq ?? 0) }
    }

    /// This iPhone's messages that the desktop's list now shows are sent.
    private func settle(_ id: String, _ rows: [BotRmMessageDTO]) {
        let sent = Set(rows.compactMap(\.sendId))
        guard !sent.isEmpty else { return }
        outgoing.removeAll { $0.roomID == id && sent.contains($0.sendID) }
    }

    func loadQueue(_ id: String) async {
        guard active else { return }
        let account = self.account
        let seq = (queueSeq[id] ?? 0) + 1
        queueSeq[id] = seq
        do {
            let answer = try await client().botRoomQueue(id, threadID: nil)
            guard stillLive(account), queueSeq[id] == seq else { return }
            queue[id] = BotRoutineWire.items(answer.items).items
        } catch {
            Connection.shared.note(error)
            // The queue is a side line: what was shown stays until the next read.
        }
    }

    /// Mark the room read up to its newest message, as the desktop does when its room view is at the bottom
    /// (botsRoom.js). The desktop sets its marker to the seq sent, even a lower one, and seqs are room-wide. So
    /// this only runs when the shown conversation's newest page holds the room's newest message (never from an
    /// older conversation, never past rows not loaded), and only while the desktop counts something unread.
    private func markRead(_ id: String) async {
        guard active, messagesLoad[id] == .loaded, let tail = tailSeq[id], let newest = pageLast[id] else { return }
        let roomNewest = max(newest, Int(rooms[id]?.lastSeq ?? 0))
        guard tail > 0, tail >= roomNewest, (rooms[id]?.unread ?? 1) > 0, tail > (readUpTo[id] ?? 0) else { return }
        let last = tail
        let account = self.account
        readUpTo[id] = last
        do {
            let answer = try await client().botRoomRead(id, seq: last)
            guard stillLive(account) else { return }
            if var room = rooms[id], let unread = answer.unread {
                room.unread = unread
                rooms[id] = room
            }
        } catch {
            Connection.shared.note(error)
            if stillLive(account), readUpTo[id] == last { readUpTo[id] = nil }
        }
    }

    // MARK: Sending

    /// Send what is typed in the room's composer. The text leaves the composer only into a bubble that keeps it
    /// until the desktop's list shows the message.
    func send(_ roomID: String) {
        let text = (drafts[roomID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard active, canSend(roomID), !text.isEmpty else { return }
        guard BotRoomLiveMap.length(text) <= 100_000 else {
            say("That message is too long for a room. Shorten it and send again.")
            return
        }
        let item = BotRmOutgoing(sendID: BotRoomLiveMap.sendID(), roomID: roomID, threadID: threadOf[roomID], text: text, state: .sending)
        withAnimation(Motion.snappy) { outgoing.append(item) }
        drafts[roomID] = ""
        deliver(item.sendID)
    }

    /// Send again a message that was refused or that the desktop did not have after a lost answer.
    /// Always with the same send id, so the desktop stores it at most once.
    func sendAgain(_ sendID: String) {
        guard let item = outgoing.first(where: { $0.sendID == sendID }) else { return }
        switch item.state {
        case .notSent, .refused: deliver(sendID)
        case .unchecked: Task { await check(sendID) }
        case .sending, .checking: return
        }
    }

    /// A refused message goes back into the composer to change.
    func edit(_ sendID: String) {
        guard let item = outgoing.first(where: { $0.sendID == sendID }), case .refused = item.state else { return }
        let typed = (drafts[item.roomID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        drafts[item.roomID] = typed.isEmpty ? item.text : item.text + "\n" + typed
        withAnimation(Motion.snappy) { outgoing.removeAll { $0.sendID == sendID } }
    }

    private func setState(_ sendID: String, _ state: BotRmSendState) {
        guard let index = outgoing.firstIndex(where: { $0.sendID == sendID }) else { return }
        withAnimation(Motion.snappy) { outgoing[index].state = state }
    }

    private func deliver(_ sendID: String) {
        guard active, let item = outgoing.first(where: { $0.sendID == sendID }) else { return }
        setState(sendID, .sending)
        let account = self.account
        beginWrite()
        Task {
            do {
                let answer = try await client().botRoomSend(item.roomID, text: item.text, sendID: item.sendID,
                                                            threadID: item.threadID, replyTo: nil)
                endWrite()
                guard stillLive(account) else { return }
                if let message = answer.message, message.threadId == nil || message.threadId == threadOf[item.roomID] {
                    withAnimation(Motion.snappy) { merge(item.roomID, [message]) }
                }
                withAnimation(Motion.snappy) { outgoing.removeAll { $0.sendID == item.sendID } }
                if let stopped = answer.stopped {
                    say(stopped.isEmpty ? "Nothing was running." : "Stopped.")
                } else if answer.queued == true {
                    say("Your message waits its turn.")
                }
                await loadRoom(item.roomID)
                // The bubble went in on its own: read the page so any rows that came before it show too.
                await loadMessages(item.roomID)
                await loadQueue(item.roomID)
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    await check(item.sendID)
                    return
                }
                if status(error) == 404 {
                    setState(item.sendID, .refused("This room or conversation is no longer on your desktop."))
                } else {
                    setState(item.sendID, .refused(error.plainWords))
                }
            }
        }
    }

    /// After a lost answer: look for the send id in the desktop's messages before saying sent or not sent.
    func check(_ sendID: String) async {
        guard active, let item = outgoing.first(where: { $0.sendID == sendID }) else { return }
        let account = self.account
        setState(sendID, .checking)
        do {
            let page = try await client().botRoomMessages(item.roomID, threadID: item.threadID, limit: 200)
            guard stillLive(account) else { return }
            let rows = BotRoutineWire.items(page.messages).items
            if let found = rows.first(where: { $0.sendId == sendID }) {
                if found.threadId == nil || found.threadId == threadOf[item.roomID] {
                    withAnimation(Motion.snappy) { merge(item.roomID, [found]) }
                }
                withAnimation(Motion.snappy) { outgoing.removeAll { $0.sendID == sendID } }
                say("Your message reached your desktop.")
                await loadRoom(item.roomID)
                await loadMessages(item.roomID)
                await loadQueue(item.roomID)
            } else {
                setState(sendID, .notSent("Your desktop does not have this message."))
            }
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            if status(error) == 404 {
                setState(sendID, .refused("This room or conversation is no longer on your desktop."))
            } else {
                setState(sendID, .unchecked)
            }
        }
    }

    // MARK: Stop, hold, queue, pin

    /// Stop one bot's running turn, or with no bot everything in the room. No confirm: it only stops.
    func stop(_ roomID: String, botID: String?) {
        let key = "stop|\(roomID)|\(botID ?? "*")"
        guard active, !busy.contains(key) else { return }
        let account = self.account
        let who = botID.map { name(roomID, $0) }
        busy.insert(key)
        Haptics.thud()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                let answer = try await client().botRoomStop(roomID, botID: botID, threadID: threadOf[roomID])
                guard stillLive(account) else { return }
                let stopped = answer.stopped ?? []
                if let who {
                    say(stopped.isEmpty ? "\(who) was not running." : "Stopped \(who)")
                } else {
                    say("Stopped everyone")
                }
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say("Your desktop did not answer, so this iPhone could not confirm the stop. This room shows what your desktop has.")
                } else {
                    say((who.map { "\($0) was not stopped. " } ?? "The room was not stopped. ") + error.plainWords)
                }
            }
            await loadRoom(roomID)
            await loadQueue(roomID)
            await loadMessages(roomID)
        }
    }

    /// Let a held member answer again.
    func resume(_ roomID: String, botID: String) {
        let key = "hold|\(roomID)|\(botID)"
        guard active, !busy.contains(key) else { return }
        let account = self.account
        let who = name(roomID, botID)
        busy.insert(key)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                _ = try await client().botRoomHold(roomID, botID: botID, held: false)
                endWrite()
                guard stillLive(account) else { return }
                say("\(who) can answer again")
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say("Your desktop did not answer, so this iPhone could not confirm \(who) was resumed. This room shows what your desktop has.")
                } else {
                    say("\(who) was not resumed. " + error.plainWords)
                }
            }
            await loadRoom(roomID, force: true)
        }
    }

    /// A waiting message stops waiting. It stays in the conversation; it just gets no turn.
    func cancelQueued(_ roomID: String, _ item: BotRmQueueItemDTO) {
        let key = "queue|\(item.id)"
        guard active, !busy.contains(key) else { return }
        let account = self.account
        busy.insert(key)
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                try await client().botRoomQueueCancel(roomID, queueID: item.id)
                guard stillLive(account) else { return }
                withAnimation(Motion.snappy) { queue[roomID]?.removeAll { $0.id == item.id } }
                say("That message will not get a turn")
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say("Your desktop did not answer, so this iPhone could not confirm the cancel. This list shows what your desktop has.")
                } else if status(error) == 409 {
                    say("That message already started.")
                } else if status(error) == 404 {
                    say("That message is no longer waiting.")
                } else {
                    say("Not cancelled. " + error.plainWords)
                }
            }
            await loadQueue(roomID)
        }
    }

    /// Pin a message (the room keeps one), or unpin with nil.
    func pin(_ roomID: String, messageID: String?) {
        let key = "pin|\(roomID)"
        guard active, !busy.contains(key), let room = rooms[roomID] else { return }
        let account = self.account
        var fields: [String: Any] = ["pinned_message_id": messageID.map { $0 as Any } ?? NSNull()]
        if let revision = room.revision { fields["expected_revision"] = revision }
        busy.insert(key)
        beginWrite()
        Haptics.tap()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                let saved = try await client().botRoomUpdate(roomID, fields)
                endWrite()
                guard stillLive(account) else { return }
                withAnimation(Motion.snappy) { rooms[roomID] = saved }
                say(messageID == nil ? "Unpinned" : "Pinned")
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    let read = await loadRoom(roomID, force: true)
                    if let read, read.pinnedMessageId == messageID {
                        say(messageID == nil ? "Unpinned" : "Pinned")
                    } else {
                        say("Your desktop did not answer, so this iPhone could not confirm the pin. This room shows what your desktop has.")
                    }
                    return
                }
                if status(error) == 409, BotRoomLiveMap.isStale(error.plainWords) {
                    say("This room changed on your desktop. It now shows what your desktop has; pin it again if you still want to.")
                } else {
                    say((messageID == nil ? "Not unpinned. " : "Not pinned. ") + error.plainWords)
                }
                await loadRoom(roomID, force: true)
            }
        }
    }

    // MARK: Settings and members

    /// Save what changed in a settings or members sheet, with the revision the sheet was read at. Answers how it
    /// came back and, when the room was read again after it, what the desktop has now (for the sheet to rebase on).
    func save(_ roomID: String, form: BotRoomLiveForm, base: BotRoomLiveForm, revision: Int?) async -> (outcome: BotRmOutcome, room: BotRoomDTO?) {
        guard active else { return (.refused("This iPhone is not paired with a desktop."), nil) }
        var fields = form.changes(from: base)
        guard !fields.isEmpty else { return (.done("Nothing changed."), nil) }
        if let revision { fields["expected_revision"] = revision }
        let account = self.account
        let key = "save|\(roomID)"
        busy.insert(key)
        beginWrite()
        defer { if stillLive(account) { busy.remove(key) } }
        do {
            let saved = try await client().botRoomUpdate(roomID, fields)
            endWrite()
            guard stillLive(account) else { return (.refused("This iPhone is now paired with another desktop."), nil) }
            rooms[roomID] = saved
            return (.done("Saved"), saved)
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else { return (.refused("This iPhone is now paired with another desktop."), nil) }
            if unconfirmed(error) {
                guard let read = await loadRoom(roomID, force: true) else {
                    return (.unsure("Your desktop did not answer, so this iPhone could not confirm the changes were saved, and could not read the room again. Check again before saving.", checked: false), nil)
                }
                if form.landed(in: read, from: base) { return (.done("Saved"), read) }
                return (.unsure("Your desktop did not answer. It does not have these changes now. What you typed is still here; save again to send it.", checked: true), read)
            }
            if status(error) == 409 {
                // Read again in every case: the sheet rebases on a stale revision, and a busy room locks its members.
                let read = await loadRoom(roomID, force: true)
                let words = error.plainWords
                if BotRoomLiveMap.isStale(words) { return (.changed(words), read) }
                if BotRoomLiveMap.isBusy(words) { return (.busy(words), read) }
                return (.refused(words), read)
            }
            if status(error) == 404 {
                gone.insert(roomID)
                return (.refused("This room is not on your desktop."), nil)
            }
            return (.refused(error.plainWords), nil)
        }
    }

    // MARK: Conversations

    /// Read the room's conversations. Answers the list this read got (nil when it failed), so a check after a
    /// write runs on a read made after it, never on an older list. A read overtaken by a later one still answers
    /// what the desktop said; only the later read updates what is shown.
    @discardableResult
    func loadThreads(_ id: String) async -> [BotRmThreadDTO]? {
        guard active else { return nil }
        let account = self.account
        let seq = (threadSeq[id] ?? 0) + 1
        threadSeq[id] = seq
        if threads[id] == nil { threadsLoad[id] = .loading }
        do {
            let answer = try await client().botRoomThreads(id)
            guard stillLive(account) else { return nil }
            let list = BotRoutineWire.items(answer.threads).items
            if threadSeq[id] == seq {
                threads[id] = list
                threadsLoad[id] = .loaded
            }
            return list
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), threadSeq[id] == seq else { return nil }
            if error is CancellationError {
                if threadsLoad[id] == .loading { threadsLoad[id] = .idle }
            } else {
                threadsLoad[id] = .failed("Conversations could not be read. " + error.plainWords)
            }
            return nil
        }
    }

    /// Show another conversation of the room.
    func openThread(_ roomID: String, _ threadID: String) {
        guard threadOf[roomID] != threadID else { return }
        threadOf[roomID] = threadID
        clearShown(roomID)
        messageSeq[roomID, default: 0] += 1
        Task {
            await loadMessages(roomID)
            await markRead(roomID)
        }
    }

    func createThread(_ roomID: String, title: String) async -> BotRmOutcome {
        guard active else { return .refused("This iPhone is not paired with a desktop.") }
        let account = self.account
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BotRoomLiveMap.length(clean) <= 100 else { return .refused("A conversation name is at most 100 characters.") }
        // An earlier create whose answer was lost and could not be checked: look before sending anything.
        if let pending = threadCheck[roomID] {
            let read = await loadThreads(roomID)
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
            guard let read else {
                return .unsure("An earlier conversation was not confirmed, and your desktop could not be read to check it. Nothing was sent.", checked: false)
            }
            threadCheck[roomID] = nil
            let found = read.contains { !pending.before.contains($0.id) && ($0.title ?? "") == pending.title }
            if found && pending.title == clean { return .done("Conversation created") }
        }
        // What the desktop had before this create, from a read: after a lost answer, only a conversation not in it counts.
        var known = threadsLoad[roomID] == .loaded ? threads[roomID] : nil
        if known == nil {
            known = await loadThreads(roomID)
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
        }
        guard let known else { return .refused("Your desktop's conversations could not be read, so nothing was sent. Try again.") }
        let before = Set(known.map(\.id))
        do {
            let made = try await client().botRoomThreadCreate(roomID, title: clean)
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
            await loadThreads(roomID)
            if threads[roomID]?.contains(where: { $0.id == made.id }) != true {
                threads[roomID, default: []].append(made)
            }
            return .done("Conversation created")
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
            if unconfirmed(error) {
                guard let read = await loadThreads(roomID) else {
                    threadCheck[roomID] = (title: clean, before: before)
                    return .unsure("Your desktop did not answer, so this iPhone could not confirm the conversation was created. It checks before sending again.", checked: false)
                }
                if read.contains(where: { !before.contains($0.id) && ($0.title ?? "") == clean }) {
                    return .done("Conversation created")
                }
                return .unsure("Your desktop did not answer. It does not have this conversation now.", checked: true)
            }
            return .refused(error.plainWords)
        }
    }

    func renameThread(_ roomID: String, _ threadID: String, title: String) {
        let key = "thread|\(threadID)"
        guard active, !busy.contains(key) else { return }
        let account = self.account
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BotRoomLiveMap.length(clean) <= 100 else {
            say("A conversation name is at most 100 characters.")
            return
        }
        busy.insert(key)
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                _ = try await client().botRoomThreadRename(roomID, threadID: threadID, title: clean)
                guard stillLive(account) else { return }
                say("Renamed")
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    guard let read = await loadThreads(roomID) else {
                        say("Your desktop did not answer, so this iPhone could not confirm the new name, and could not read the conversations again.")
                        return
                    }
                    if read.first(where: { $0.id == threadID })?.title == clean {
                        say("Renamed")
                    } else {
                        say("Your desktop did not answer. It does not have the new name now; rename it again to send it.")
                    }
                    return
                }
                say("Not renamed. " + error.plainWords)
            }
            await loadThreads(roomID)
        }
    }

    /// Delete a conversation and every message in it. Asked first on screen.
    func deleteThread(_ roomID: String, _ threadID: String) {
        let key = "thread|\(threadID)"
        guard active, !busy.contains(key) else { return }
        let account = self.account
        busy.insert(key)
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            var lost = false
            do {
                let answer = try await client().botRoomThreadDelete(roomID, threadID: threadID)
                guard stillLive(account) else { return }
                if answer.deleted?.contains(threadID) == true {
                    withAnimation(Motion.snappy) { threads[roomID]?.removeAll { $0.id == threadID } }
                    say("Conversation deleted")
                } else {
                    say("A room keeps at least one conversation, so this one stays.")
                }
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    lost = true
                } else if status(error) == 409 {
                    say("That conversation is working. Stop it first, then delete it.")
                } else {
                    say("Not deleted. " + error.plainWords)
                }
            }
            let read = await loadThreads(roomID)
            guard stillLive(account) else { return }
            if lost {
                if let read {
                    say(read.contains(where: { $0.id == threadID })
                        ? "Your desktop did not answer. It still has this conversation; delete it again if you want to."
                        : "Conversation deleted")
                } else {
                    say("Your desktop did not answer, so this iPhone could not confirm the delete, and could not read the conversations again.")
                }
            }
            if let shown = threadOf[roomID], let read, !read.contains(where: { $0.id == shown }) {
                threadOf[roomID] = nil
                clearShown(roomID)
                await loadMessages(roomID)
            }
            await loadRoom(roomID)
        }
    }

    // MARK: Making a room (for NewRoomSheet in TeamScreens.swift)

    /// Create a room on the desktop with these bots (1 to 20) and no working folder. After a lost answer nothing
    /// is sent again until a read of the desktop's rooms says whether it was made: a later call with the same
    /// name and bots looks first, and answers `.created` with the room it finds.
    func createRoom(name: String, context: String, memberIDs: [String]) async -> BotRmCreateOutcome {
        guard active else { return .refused("This iPhone is not paired with a desktop.") }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let about = context.trimmingCharacters(in: .whitespacesAndNewlines)
        var ids: [String] = []
        for id in memberIDs where !ids.contains(id) { ids.append(id) }
        guard !clean.isEmpty else { return .refused("Give the room a name.") }
        guard BotRoomLiveMap.length(clean) <= 100 else { return .refused("A room name is at most 100 characters.") }
        guard BotRoomLiveMap.length(about) <= 60 else { return .refused("The context is at most 60 characters.") }
        guard !ids.isEmpty else { return .refused("A room needs at least one bot.") }
        guard ids.count <= 20 else { return .refused("A room holds at most 20 bots.") }
        let account = self.account
        let wanted = Set(ids)

        // Read the desktop's rooms first: to settle an earlier lost answer, and to know which rooms are new after one.
        let listed: [BotRoomDTO]
        do {
            listed = BotRoutineWire.items(try await client().botRoomList().rooms).items
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
            if createCheck != nil {
                return .unsure("An earlier room was not confirmed, and your desktop could not be read to check it. Nothing was sent. " + error.plainWords)
            }
            return .refused("The room was not created. " + error.plainWords)
        }
        guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
        if let check = createCheck {
            if let found = Self.made(in: listed, check: check) {
                createCheck = nil
                if check.name == clean && check.members == wanted { return .created(found.id) }
            } else {
                createCheck = nil
            }
        }
        let before = Set(listed.map(\.id))
        do {
            let made = try await client().botRoomCreate(name: clean, context: about, botIDs: ids)
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
            if roomList != nil, roomList?.contains(where: { $0.id == made.id }) != true { roomList?.append(made) }
            return .created(made.id)
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
            guard unconfirmed(error) else { return .refused("The room was not created. " + error.plainWords) }
            let check = BotRmCreateCheck(name: clean, members: wanted, before: before)
            createCheck = check
            if let page = try? await client().botRoomList(), stillLive(account) {
                let after = BotRoutineWire.items(page.rooms).items
                if let found = Self.made(in: after, check: check) {
                    createCheck = nil
                    return .created(found.id)
                }
                return .unsure("Your desktop did not answer and does not show this room now. Create it again to send it.")
            }
            return .unsure("Your desktop did not answer, so this iPhone could not confirm the room was created. It checks before sending again.")
        }
    }

    private static func made(in rooms: [BotRoomDTO], check: BotRmCreateCheck) -> BotRoomDTO? {
        rooms.first { room in
            !check.before.contains(room.id) && (room.name ?? "") == check.name
                && Set((room.members ?? []).compactMap(\.botId)) == check.members
        }
    }
}

// MARK: - The rooms list (paired)

/// The paired desktop's rooms, for the list in All bots. Never a sample room: while reading it shows the loading
/// note, on failure one sentence and Try again, and an honest note when the desktop has no rooms. Read again each
/// time it appears, so unread counts and who is working come back current after a room was open.
struct BotRoomLiveList: View {
    let open: (String) -> Void
    let live = BotRoomLiveStore.shared
    let store = BotsStore.shared

    var body: some View {
        let rooms = live.shownRoomList()
        let state = live.roomListState()
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Rooms").padding(.horizontal, 4)
            if state != .loaded {
                BotsLoadNote(state: state, waiting: "Reading your rooms from your desktop.") {
                    Task { await live.loadRoomList() }
                }
            }
            if state == .loaded && rooms.isEmpty {
                EmptyNote(text: "Your desktop has no rooms yet. Make one in Kairos on your desktop.", symbol: "number")
                    .kCard(radius: 20)
            }
            if !rooms.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                        if index > 0 { RowLine(inset: 54) }
                        Button {
                            Haptics.tap()
                            open(room.id)
                        } label: {
                            NavRow(title: (room.name ?? "").isEmpty ? "Room" : (room.name ?? "Room"), symbol: "number",
                                   detail: detail(room), badge: room.unread ?? 0)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 20)
            }
            if live.isCurrent && live.roomListSkipped > 0 {
                HintLine(text: "Some rooms on your desktop could not be read, so they are not shown here.", symbol: "info.circle")
                    .padding(.horizontal, 4)
            }
        }
        .task(id: BotRoomLiveStore.connectionKey) {
            guard live.active else { return }
            await live.loadRoomList()
        }
    }

    /// Who is working, else how many bots; a room still being set up says so.
    private func detail(_ room: BotRoomDTO) -> String {
        let members = room.members ?? []
        if room.setupState == "pending" { return "Finish setting it up in Kairos on your desktop" }
        let working = members.filter { $0.working == true }.map { $0.name ?? store.bot($0.botId ?? "").name }
        if !working.isEmpty { return working.joined(separator: ", ") + " working" }
        return members.count == 1 ? "1 bot" : "\(members.count) bots"
    }
}

