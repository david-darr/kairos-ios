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
    case refused(String)
    /// 409: the room changed on the desktop. It was read again; what was typed stays.
    case changed(String)
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

    @ObservationIgnored private var account = "sample"
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
    /// shown (the write reads again itself), unless `force`.
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
            guard stillLive(account), roomSeq[id] == seq else { return nil }
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

    /// Read the newest messages of the shown conversation and add them to what is loaded. Answers the rows read.
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
            let (rows, left) = BotRoutineWire.items(page.messages)
            let first = messages[id] == nil
            if thread == nil, let read = page.threadId { threadOf[id] = read }
            merge(id, rows)
            if first { hasMore[id] = page.hasMore ?? false }
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
                messages[id] = nil
                hasMore[id] = nil
                messagesLoad[id] = .idle
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
            guard stillLive(account), threadOf[id] == thread else { return }
            merge(id, BotRoutineWire.items(page.messages).items)
            hasMore[id] = page.hasMore ?? false
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), !(error is CancellationError) else { return }
            say("Earlier messages could not be read. " + error.plainWords)
        }
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

    /// Mark what is loaded as read, once per new message.
    private func markRead(_ id: String) async {
        guard active, let last = messages[id]?.last?.seq, last > (readUpTo[id] ?? 0) else { return }
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
        guard text.count <= 100_000 else {
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
                if status(error) == 409 {
                    say("This room changed on your desktop. It now shows what your desktop has; pin it again if you still want to.")
                } else {
                    say((messageID == nil ? "Not unpinned. " : "Not pinned. ") + error.plainWords)
                }
                await loadRoom(roomID, force: true)
            }
        }
    }

    // MARK: Settings and members

    /// Save what changed in a settings or members sheet, with the revision the sheet was read at.
    func save(_ roomID: String, form: BotRoomLiveForm, base: BotRoomLiveForm, revision: Int?) async -> BotRmOutcome {
        guard active else { return .refused("This iPhone is not paired with a desktop.") }
        var fields = form.changes(from: base)
        guard !fields.isEmpty else { return .done("Nothing changed.") }
        if let revision { fields["expected_revision"] = revision }
        let account = self.account
        let key = "save|\(roomID)"
        busy.insert(key)
        beginWrite()
        defer { if stillLive(account) { busy.remove(key) } }
        do {
            let saved = try await client().botRoomUpdate(roomID, fields)
            endWrite()
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
            rooms[roomID] = saved
            return .done("Saved")
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
            if unconfirmed(error) {
                guard let read = await loadRoom(roomID, force: true) else {
                    return .unsure("Your desktop did not answer, so this iPhone could not confirm the changes were saved, and could not read the room again. Check again before saving.", checked: false)
                }
                if form.landed(in: read, from: base) { return .done("Saved") }
                return .unsure("Your desktop did not answer. It does not have these changes now. What you typed is still here; save again to send it.", checked: true)
            }
            if status(error) == 409 {
                _ = await loadRoom(roomID, force: true)
                return .changed(error.plainWords)
            }
            if status(error) == 404 {
                gone.insert(roomID)
                return .refused("This room is not on your desktop.")
            }
            return .refused(error.plainWords)
        }
    }

    // MARK: Conversations

    func loadThreads(_ id: String) async {
        guard active else { return }
        let account = self.account
        let seq = (threadSeq[id] ?? 0) + 1
        threadSeq[id] = seq
        if threads[id] == nil { threadsLoad[id] = .loading }
        do {
            let answer = try await client().botRoomThreads(id)
            guard stillLive(account), threadSeq[id] == seq else { return }
            threads[id] = BotRoutineWire.items(answer.threads).items
            threadsLoad[id] = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), threadSeq[id] == seq else { return }
            if error is CancellationError {
                if threadsLoad[id] == .loading { threadsLoad[id] = .idle }
            } else {
                threadsLoad[id] = .failed("Conversations could not be read. " + error.plainWords)
            }
        }
    }

    /// Show another conversation of the room.
    func openThread(_ roomID: String, _ threadID: String) {
        guard threadOf[roomID] != threadID else { return }
        threadOf[roomID] = threadID
        messages[roomID] = nil
        hasMore[roomID] = nil
        messagesLoad[roomID] = .idle
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
        // An earlier create whose answer was lost and could not be checked: look before sending anything.
        if let pending = threadCheck[roomID] {
            await loadThreads(roomID)
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
            guard threadsLoad[roomID] == .loaded else {
                return .unsure("An earlier conversation was not confirmed, and your desktop could not be read to check it. Nothing was sent.", checked: false)
            }
            threadCheck[roomID] = nil
            let found = (threads[roomID] ?? []).contains { !pending.before.contains($0.id) && ($0.title ?? "") == pending.title }
            if found && pending.title == clean { return .done("Conversation created") }
        }
        let before = Set((threads[roomID] ?? []).map(\.id))
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
                await loadThreads(roomID)
                guard threadsLoad[roomID] == .loaded else {
                    threadCheck[roomID] = (title: clean, before: before)
                    return .unsure("Your desktop did not answer, so this iPhone could not confirm the conversation was created. It checks before sending again.", checked: false)
                }
                if (threads[roomID] ?? []).contains(where: { !before.contains($0.id) && ($0.title ?? "") == clean }) {
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
                    await loadThreads(roomID)
                    if threads[roomID]?.first(where: { $0.id == threadID })?.title == clean {
                        say("Renamed")
                    } else {
                        say("Your desktop did not answer, so this iPhone could not confirm the new name. This list shows what your desktop has.")
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
                    say("Your desktop did not answer, so this iPhone could not confirm the delete. This list shows what your desktop has.")
                } else if status(error) == 409 {
                    say("That conversation is working. Stop it first, then delete it.")
                } else {
                    say("Not deleted. " + error.plainWords)
                }
            }
            await loadThreads(roomID)
            if let shown = threadOf[roomID], threads[roomID]?.contains(where: { $0.id == shown }) == false,
               threadsLoad[roomID] == .loaded {
                threadOf[roomID] = nil
                messages[roomID] = nil
                hasMore[roomID] = nil
                messagesLoad[roomID] = .idle
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
        guard clean.count <= 100 else { return .refused("A room name is at most 100 characters.") }
        guard about.count <= 60 else { return .refused("The context is at most 60 characters.") }
        guard !ids.isEmpty else { return .refused("A room needs at least one bot.") }
        guard ids.count <= 20 else { return .refused("A room holds at most 20 bots.") }
        let account = self.account
        let wanted = Set(ids)

        // Read the desktop's rooms first: to settle an earlier lost answer, and to know which rooms are new after one.
        let listed: [BotRoomDTO]
        do {
            listed = try await client().botRooms().rooms ?? []
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
            return .created(made.id)
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("This iPhone is now paired with another desktop.") }
            guard unconfirmed(error) else { return .refused("The room was not created. " + error.plainWords) }
            let check = BotRmCreateCheck(name: clean, members: wanted, before: before)
            createCheck = check
            if let after = try? await client().botRooms().rooms, stillLive(account) {
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

