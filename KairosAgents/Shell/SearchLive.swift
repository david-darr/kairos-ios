import SwiftUI

// Search while the phone is paired. Everything it lists is the paired desktop's own. An area another screen has
// already read is listed from that screen's store; an area nobody has read yet is read here, into this sheet only,
// so no other screen's store is ever marked as reading, filled or changed by Search. The text searches are the
// desktop's own (the Vault, documents, Drive and bot chats). Search only reads: nothing here writes to the desktop,
// and nothing it finds is kept on the phone beyond the open sheet. Not paired, `SearchView` shows its sample sheet.

/// Where one desktop text search stands.
nonisolated enum SearchLiveWait: Equatable, Sendable {
    /// Answered, or nothing was asked.
    case ready
    /// Still asking the desktop.
    case waiting
    case failed(String)
}

/// Where Search's own read of one area stands: not asked yet, asking, or answered (with items, with nothing, or
/// failed). A read cut short goes back to not asked.
nonisolated enum SearchLiveAsk: Equatable, Sendable {
    case notAsked
    case asking
    case answered
    case failed(String)
}

/// The areas Search reads itself when no other screen has read them yet.
nonisolated enum SearchLiveArea: CaseIterable, Hashable, Sendable {
    case rooms, teams, notes, documents, chatFiles, tasks, calendar, mail, drive
}

/// One plain row Search keeps from its own read.
nonisolated struct SearchLiveRow: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String
}

nonisolated struct SearchLiveVaultHit: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var snippet: String
}

nonisolated struct SearchLiveDocHit: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var snippet: String
}

nonisolated struct SearchLiveChatHit: Identifiable, Hashable, Sendable {
    /// The bot conversation's id (the desktop session).
    let id: String
    var botID: String
    var title: String
    var snippet: String
}

/// Where a desktop conversation opens on this phone.
nonisolated enum SearchLivePlace: Equatable, Sendable {
    /// A chat with a model.
    case model
    /// A bot's seat in a room: only the room shows it.
    case room(String)
    /// One of a bot's own conversations.
    case bot(String)
    case gone
    case failed(String)
}

/// The desktop reads behind the paired sheet. A text search runs only after a short pause in typing; an answer for
/// an older query or another account is dropped; closing the sheet stops everything and leaves nothing marked as
/// asking.
@Observable
final class SearchLiveModel {
    // The desktop's text searches, for the query in `asked`.
    private(set) var vault: [SearchLiveVaultHit] = []
    private(set) var vaultWait: SearchLiveWait = .ready
    private(set) var docHits: [SearchLiveDocHit] = []
    private(set) var docsWait: SearchLiveWait = .ready
    /// Drive file ids, as the Drive store keeps them.
    private(set) var drive: [String] = []
    private(set) var driveWait: SearchLiveWait = .ready
    private(set) var chats: [SearchLiveChatHit] = []
    private(set) var chatsWait: SearchLiveWait = .ready
    /// The query the desktop is being asked about, "" when none.
    private(set) var asked = ""

    // Search's own reads of the areas no other screen has read yet.
    private(set) var asks: [SearchLiveArea: SearchLiveAsk] = [:]
    private(set) var rooms: [BotRoomDTO] = []
    private(set) var teams: [SearchLiveRow] = []
    private(set) var notes: [KNote] = []
    private(set) var documents: [LibraryDocument] = []
    private(set) var groups: [ChatDocsGroup] = []
    private(set) var tasks: [SearchLiveRow] = []
    private(set) var events: [CalEvent] = []
    private(set) var mail: [SearchLiveRow] = []
    /// Which desktop and account everything above belongs to.
    private(set) var owner = ""

    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var launched = -1
    @ObservationIgnored private var driveAsked = -1
    @ObservationIgnored private var searches: [Task<Void, Never>] = []
    @ObservationIgnored private var workers: [Task<Void, Never>] = []
    @ObservationIgnored private var queue: [SearchLiveArea] = []
    @ObservationIgnored private var warmed = false

    static let pause: Duration = .milliseconds(350)
    static let minimum = 2
    /// The bot chat search scans every message on the desktop: it waits for three characters.
    static let chatMinimum = 3
    /// At most this many area reads at once.
    static let lanes = 3

    /// Which desktop and account the answers belong to.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Answers held here belong to the desktop and account paired right now.
    var isCurrent: Bool { owner == Self.accountKey && !Connection.shared.usesSampleData }

    /// Drive can be searched with one call: the Google accounts are read and one is connected.
    var driveSearchable: Bool {
        let store = DriveStore.shared
        return !store.isSample && store.liveAccount == DriveStore.accountKey && store.accountsLoad == .loaded
            && store.currentAccountID != nil
    }

    func ask(_ area: SearchLiveArea) -> SearchLiveAsk { isCurrent ? (asks[area] ?? .notAsked) : .notAsked }

    private func current(_ mine: Int) -> Bool {
        serial == mine && isCurrent
    }

    /// Another desktop or account: nothing read for the one before is kept or shown.
    private func followAccount() {
        let key = Self.accountKey
        guard owner != key else { return }
        stopAll()
        owner = key
        asks = [:]
        rooms = []
        teams = []
        notes = []
        documents = []
        groups = []
        tasks = []
        events = []
        mail = []
        warmed = false
        clearSearch()
    }

    private func clearSearch() {
        vault = []
        docHits = []
        drive = []
        chats = []
        asked = ""
        vaultWait = .ready
        docsWait = .ready
        driveWait = .ready
        chatsWait = .ready
    }

    // MARK: The text searches

    /// A new query: every older search stops, and the desktop is asked after a short pause, once the phone has
    /// finished connecting.
    func search(_ raw: String) {
        followAccount()
        stopSearches()
        serial += 1
        let mine = serial
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        clearSearch()
        guard query.count >= Self.minimum, !Connection.shared.usesSampleData else { return }
        asked = query
        vaultWait = .waiting
        docsWait = .waiting
        chatsWait = query.count >= Self.chatMinimum ? .waiting : .ready
        driveWait = driveSearchable ? .waiting : .ready
        searches.append(Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            await BotsStore.waitWhileConnecting()
            guard let self, !Task.isCancelled, self.current(mine) else { return }
            self.launch(query, mine)
        })
    }

    private func launch(_ query: String, _ mine: Int) {
        launched = mine
        searches.append(Task { [weak self] in await self?.searchVault(query, mine) })
        searches.append(Task { [weak self] in await self?.searchDocs(query, mine) })
        if query.count >= Self.chatMinimum {
            searches.append(Task { [weak self] in await self?.searchChats(query, mine) })
        }
        startDrive(query, mine)
    }

    /// One Drive search per pause in typing: started at the launch, or later when the Google accounts arrive
    /// after it, never both.
    private func startDrive(_ query: String, _ mine: Int) {
        guard driveSearchable, driveAsked != mine, launched == mine, current(mine) else { return }
        driveAsked = mine
        driveWait = .waiting
        searches.append(Task { [weak self] in await self?.searchDrive(query, mine) })
    }

    private func searchVault(_ query: String, _ mine: Int) async {
        let store = VaultStore.shared
        store.followConnection()
        guard !store.isSample else {
            if current(mine) { vaultWait = .failed("Your vault could not be searched. Try again.") }
            return
        }
        do {
            let found = try await store.searchText(query)
            guard !Task.isCancelled, current(mine) else { return }
            var seen = Set<String>()
            vault = found.compactMap { hit -> SearchLiveVaultHit? in
                guard seen.insert(hit.note.id).inserted else { return nil }
                return SearchLiveVaultHit(id: hit.note.id, title: hit.note.title, snippet: SearchLiveText.line(hit.snippet))
            }
            vaultWait = .ready
        } catch {
            guard !(error is CancellationError), !Task.isCancelled, current(mine) else { return }
            Connection.shared.note(error)
            vaultWait = .failed("Your vault could not be searched. " + error.plainWords)
        }
    }

    private func searchDocs(_ query: String, _ mine: Int) async {
        guard let client = Connection.shared.client else {
            if current(mine) { docsWait = .failed(APIError.notPaired.plain) }
            return
        }
        do {
            let found = try await client.docsSearch(query)
            guard !Task.isCancelled, current(mine) else { return }
            var seen = Set<String>()
            docHits = found.hits.compactMap { hit -> SearchLiveDocHit? in
                guard seen.insert(hit.id).inserted else { return nil }
                let title = hit.title?.string ?? ""
                return SearchLiveDocHit(id: hit.id, title: title.isEmpty ? "Untitled" : title,
                                        snippet: SearchLiveText.line(hit.snippet?.string ?? ""))
            }
            docsWait = .ready
        } catch {
            guard !(error is CancellationError), !Task.isCancelled, current(mine) else { return }
            Connection.shared.note(error)
            docsWait = .failed("Your documents could not be searched. " + error.plainWords)
        }
    }

    private func searchDrive(_ query: String, _ mine: Int) async {
        let store = DriveStore.shared
        guard let key = store.key(section: .myDrive, folder: nil, query: query, filter: .all) else {
            if current(mine) { driveWait = .ready }
            return
        }
        let read = await store.loadList(key)
        guard !Task.isCancelled, current(mine) else { return }
        let list = store.lists[key]
        if read || list?.load == .loaded {
            drive = Array(store.liveItems(key).filter { !$0.trashed }.map(\.id).prefix(8))
            driveWait = .ready
        } else if case .failed(let why)? = list?.load {
            driveWait = .failed(why)
        } else {
            driveWait = .failed("Google Drive could not be searched. Try again.")
        }
    }

    private func searchChats(_ query: String, _ mine: Int) async {
        guard let client = Connection.shared.client else {
            if current(mine) { chatsWait = .failed(APIError.notPaired.plain) }
            return
        }
        do {
            let found = try await client.searchBotChats(query, limit: 30)
            guard !Task.isCancelled, current(mine) else { return }
            // Only the version of each conversation that is on screen. Which bots are shown is decided when the
            // rows are drawn, so a hit is not lost because Home has not read its bots yet.
            var seen = Set<String>()
            var hits: [SearchLiveChatHit] = []
            for hit in found.hits where !hit.isOtherVersion {
                guard let bot = hit.bot, seen.insert(hit.sessionId).inserted else { continue }
                hits.append(SearchLiveChatHit(id: hit.sessionId, botID: bot, title: SearchLiveText.line(hit.title?.string ?? ""),
                                              snippet: SearchLiveText.line(hit.snippet?.string ?? "")))
            }
            chats = hits
            chatsWait = .ready
        } catch {
            guard !(error is CancellationError), !Task.isCancelled, current(mine) else { return }
            Connection.shared.note(error)
            chatsWait = .failed("Bot chats could not be searched. " + error.plainWords)
        }
    }

    // MARK: Reading the areas nobody has read yet

    /// At the first letter of an open sheet: each area that no screen has read yet, and Search has not asked about
    /// in this sheet, is asked once, a few at a time, after the phone has finished connecting.
    func warmUp() {
        followAccount()
        guard !warmed, !Connection.shared.usesSampleData else { return }
        warmed = true
        let wanted = SearchLiveArea.allCases.filter { (asks[$0] ?? .notAsked) == .notAsked && Self.unread($0) }
        guard !wanted.isEmpty else { return }
        for area in wanted { asks[area] = .asking }
        queue = wanted
        for _ in 0..<min(Self.lanes, wanted.count) {
            workers.append(Task { [weak self] in await self?.lane() })
        }
    }

    /// No screen has read this area for the paired account yet (or its last read failed, for Drive's accounts).
    static func unread(_ area: SearchLiveArea) -> Bool {
        switch area {
        case .rooms:
            let store = BotRoomLiveStore.shared
            return !(store.isCurrent && store.roomListLoad == .loaded)
        case .teams:
            let store = BotsStore.shared
            return !(store.liveMode && store.rosterLoad == .loaded)
        case .notes:
            let store = NotesStore.shared
            return !(!store.isSample && store.liveAccount == NotesStore.accountKey && store.liveLoad == .loaded)
        case .documents:
            let store = DocsLiveStore.shared
            return !(store.isLive && store.account == DocsLiveStore.accountKey && store.docsLoad == .loaded)
        case .chatFiles:
            let store = DocsLiveStore.shared
            return !(store.isLive && store.account == DocsLiveStore.accountKey && store.filesLoad == .loaded)
        case .tasks:
            let store = TasksStore.shared
            return !(store.isLive && store.liveAccount == TasksStore.accountKey && store.boardLoad == .loaded)
        case .calendar:
            let store = CalStore.shared
            return !(!store.isSample && store.liveAccount == CalStore.accountKey && store.liveLoad == .loaded)
        case .mail:
            let store = MailStore.shared
            return !(!store.isSample && store.liveAccount == MailStore.accountKey && store.liveLoad == .loaded)
        case .drive:
            // Drive's own store is read here (a Drive hit opens the real Drive screen, which needs it). Its read
            // puts itself back to "not read" when it is stopped, so nothing is left marked as reading.
            let store = DriveStore.shared
            guard !store.isSample, store.liveAccount == DriveStore.accountKey else { return true }
            switch store.accountsLoad {
            case .idle, .failed: return true
            case .loading, .loaded: return false
            }
        }
    }

    private func lane() async {
        await BotsStore.waitWhileConnecting()
        while !Task.isCancelled, !queue.isEmpty {
            let area = queue.removeFirst()
            await read(area)
        }
    }

    private func read(_ area: SearchLiveArea) async {
        let mine = owner
        func live() -> Bool { owner == mine && isCurrent }
        guard live() else { return }
        guard let client = Connection.shared.client else {
            asks[area] = .failed("Your desktop could not be read. " + APIError.notPaired.plain)
            return
        }
        do {
            switch area {
            case .rooms:
                let answer = try await client.botRoomList()
                guard live() else { return }
                rooms = BotRoutineWire.items(answer.rooms).items
            case .teams:
                let map = try await client.botTeamMap()
                guard live() else { return }
                let people = map.members ?? map.bots ?? []
                teams = (map.departments ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.map { department -> SearchLiveRow in
                    let count = people.filter { $0.departmentId == department.id }.count
                    return SearchLiveRow(id: department.id, title: department.name ?? "Team",
                                         detail: count == 1 ? "1 bot" : "\(count) bots")
                }
            case .notes:
                let answer = try await client.notesList()
                guard live() else { return }
                notes = answer.notes.enumerated().compactMap { pair -> KNote? in
                    pair.element.dismissed?.bool == true ? nil : NotesStore.liveNote(pair.element, order: pair.offset)
                }
            case .documents:
                let answer = try await client.docsList()
                guard live() else { return }
                documents = answer.documents.map(DocsLiveStore.liveDocument)
            case .chatFiles:
                let answer = try await client.docsChatFiles()
                guard live() else { return }
                groups = DocsLiveStore.liveGroups(answer)
            case .tasks:
                let records = try await client.tasksList()
                guard live() else { return }
                tasks = records.map { record -> SearchLiveRow in
                    if record.scheduleKind == "card" {
                        let column = WorkColumn(rawValue: record.status ?? "") ?? .backlog
                        return SearchLiveRow(id: "c-" + record.id, title: record.name ?? "Untitled card", detail: "Card · " + column.title)
                    }
                    return SearchLiveRow(id: "j-" + record.id, title: record.name ?? "Untitled task", detail: "Scheduled task")
                }
            case .calendar:
                // The weeks the Calendar shows first: two back, six ahead.
                let today = CalDates.day(.now)
                let found = try await client.calendarEvents(start: CalDates.add(-14, to: today), end: CalDates.add(43, to: today))
                guard live() else { return }
                var seen = Set<String>()
                events = found.compactMap(CalendarWire.event).filter { seen.insert($0.id).inserted }
            case .mail:
                let triage = try await client.mailTriage()
                guard live() else { return }
                // Only what the Mail list shows: sender, subject and when. Never a message's text or the reason.
                mail = triage.items.enumerated().map { pair -> SearchLiveRow in
                    let dto = pair.element
                    let sender = MailWire.parse(dto.from ?? "")
                    let subject = dto.subject ?? ""
                    return SearchLiveRow(id: "\(pair.offset)", title: subject.isEmpty ? "(no subject)" : subject,
                                         detail: [sender.name.isEmpty ? "Unknown sender" : sender.name, MailWire.timeText(dto.date)]
                                            .filter { !$0.isEmpty }.joined(separator: " · "))
                }
            case .drive:
                let store = DriveStore.shared
                store.followConnection()
                guard !store.isSample else {
                    asks[area] = .answered
                    return
                }
                switch store.accountsLoad {
                case .idle, .failed: await store.loadAccountsLive()
                case .loading, .loaded: break
                }
                guard live(), !Task.isCancelled else {
                    if live() { asks[area] = .notAsked }
                    return
                }
                switch store.accountsLoad {
                case .loaded:
                    asks[area] = .answered
                    startDrive(asked, serial)
                case .failed(let why):
                    asks[area] = .failed(why)
                case .idle, .loading:
                    // Stopped before it was answered: asked again next time.
                    asks[area] = .notAsked
                }
                return
            }
            asks[area] = .answered
        } catch {
            guard live() else { return }
            if error is CancellationError || Task.isCancelled {
                asks[area] = .notAsked
                return
            }
            Connection.shared.note(error)
            asks[area] = .failed(Self.failure(area) + " " + error.plainWords)
        }
    }

    static func failure(_ area: SearchLiveArea) -> String {
        switch area {
        case .rooms: return "Your rooms could not be read."
        case .teams: return "Your teams could not be read."
        case .notes: return "Your notes could not be read."
        case .documents: return "Your documents could not be read."
        case .chatFiles: return "Your chat files could not be read."
        case .tasks: return "Your tasks could not be read."
        case .calendar: return "Your calendar could not be read."
        case .mail: return "Your mail could not be read."
        case .drive: return "Your Google accounts could not be read."
        }
    }

    // MARK: Where a conversation opens

    /// Asks the desktop what one conversation is (GET /api/sessions/{id}, a read): a model chat, a bot's own
    /// conversation, or a bot's seat in a room.
    func place(of sessionID: String) async -> SearchLivePlace {
        guard let client = Connection.shared.client else { return .failed(APIError.notPaired.plain) }
        do {
            let session = try await client.searchSession(sessionID)
            guard isCurrent else { return .failed("Your paired desktop changed. Try again.") }
            if let target = session.botsTarget, target.tab == "botsRoom", let room = target.roomId, !room.isEmpty {
                return .room(room)
            }
            if let bot = session.agentId, !bot.isEmpty { return .bot(bot) }
            return .model
        } catch {
            if error is CancellationError { return .failed("Stopped.") }
            Connection.shared.note(error)
            if case .server(status: 404, _)? = error as? APIError { return .gone }
            return .failed(error.plainWords)
        }
    }

    // MARK: Stopping

    private func stopSearches() {
        for task in searches { task.cancel() }
        searches = []
    }

    private func stopAll() {
        stopSearches()
        for task in workers { task.cancel() }
        workers = []
        queue = []
        serial += 1
        launched = -1
        driveAsked = -1
    }

    /// The sheet closed: every search and read it started stops, and nothing stays marked as asking, so the next
    /// look asks again.
    func stop() {
        stopAll()
        for (area, state) in asks where state == .asking { asks[area] = .notAsked }
        warmed = false
        clearSearch()
    }
}

/// Snippets as one plain line.
nonisolated enum SearchLiveText {
    static func line(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// One section of the paired sheet: its rows, whether it is still asking the desktop, and what failed.
struct SearchLiveSection {
    let name: String
    var hits: [SearchLiveHit] = []
    var waiting = false
    var problems: [String] = []
}

struct SearchLiveHit: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    var bot: Bot? = nil
    var keywords = ""
    /// True when running it leaves Search open (a cover or sheet over it, or a check first).
    var stays = false
    var gold = false
    let run: () -> Void
}

/// What Search opens over itself.
enum SearchLiveCover: Identifiable {
    case vault(String)
    case document(String)
    case drive(String)
    case team(String)
    case room(String)
    case call(Bot)

    var id: String {
        switch self {
        case .vault(let id): "v-\(id)"
        case .document(let id): "d-\(id)"
        case .drive(let id): "g-\(id)"
        case .team(let id): "t-\(id)"
        case .room(let id): "r-\(id)"
        case .call(let bot): "c-\(bot.id)"
        }
    }
}

/// The Search sheet while paired.
struct SearchLiveView: View {
    var startQuery = ""
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var model = SearchLiveModel()
    @State private var cover: SearchLiveCover?
    @State private var noteSheet: NotesSheetItem?
    @State private var notice: String?
    @State private var openingChat = false
    @State private var opening: Task<Void, Never>?
    @State private var started = false
    @FocusState private var typing: Bool

    private let chats = ChatStore.shared
    private let bots = BotsStore.shared
    private let rooms = BotRoomLiveStore.shared
    private let vaultStore = VaultStore.shared
    private let notes = NotesStore.shared
    private let docs = DocsLiveStore.shared
    private let driveStore = DriveStore.shared
    private let tasks = TasksStore.shared
    private let calendar = CalStore.shared
    private let mail = MailStore.shared

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var needle: String { trimmed.lowercased() }

    /// The phone is paired but the desktop is not answering: one line says so instead of a line per section.
    private var unreachable: String? {
        switch Connection.shared.state {
        case .offline, .signedOut: return Connection.shared.statusLine
        case .sample, .connecting, .connected: return nil
        }
    }

    // MARK: Matching

    private func matches(_ needle: String, _ title: String, _ detail: String = "", _ keywords: String = "") -> Bool {
        let title = title.lowercased()
        if title.contains(needle) || detail.lowercased().contains(needle) || keywords.contains(needle) { return true }
        return needle.split(separator: " ").allSatisfy { word in title.contains(word) || keywords.contains(word) }
    }

    private func picked(_ hits: [SearchLiveHit], limit: Int = 8) -> [SearchLiveHit] {
        let needle = self.needle
        guard !needle.isEmpty else { return hits }
        return Array(hits.filter { matches(needle, $0.title, $0.detail, $0.keywords) }.prefix(limit))
    }

    /// One area's state in this sheet: what another screen already read, else Search's own read.
    private func apply(_ ask: SearchLiveAsk, to section: inout SearchLiveSection) {
        switch ask {
        case .notAsked, .answered: break
        case .asking: section.waiting = true
        case .failed(let why): section.problems.append(why)
        }
    }

    private func apply(_ wait: SearchLiveWait, to section: inout SearchLiveSection) {
        switch wait {
        case .ready: break
        case .waiting: section.waiting = true
        case .failed(let why): section.problems.append(why)
        }
    }

    /// Answers of the desktop's text searches for the query on screen, under the account paired now.
    private var searched: Bool { model.isCurrent && !model.asked.isEmpty && model.asked == trimmed }

    // MARK: Sections

    private var actions: [SearchLiveHit] {
        var hits: [SearchLiveHit] = []
        hits.append(SearchLiveHit(id: "a-chat", title: "New chat", detail: "Start a chat with a model", symbol: "plus.bubble", keywords: "start ask", gold: true) {
            router.push(.newChat, on: .home)
        })
        hits.append(SearchLiveHit(id: "a-note", title: "New note", detail: "Opens Notes", symbol: "square.and.pencil", keywords: "write jot", gold: true) {
            router.open(.notes)
            chrome.say("Notes is open. Tap the gold circle for a new note.")
        })
        // The paired desktop's own bots, each called the way its own screen calls it.
        for bot in chats.singleBots {
            hits.append(SearchLiveHit(id: "a-call-\(bot.id)", title: "Call \(bot.name)", detail: bot.isKip ? "Talk it through" : bot.role,
                                      symbol: "phone", keywords: "ring voice talk", stays: true, gold: true) {
                cover = .call(bot)
            })
        }
        hits.append(SearchLiveHit(id: "a-settings", title: "Open settings", detail: "Accounts and every setting", symbol: "gear", keywords: "preferences you", stays: true, gold: true) {
            router.sheet = .you
        })
        hits.append(SearchLiveHit(id: "a-tour", title: "Take the tour", detail: "A short walk past the real controls", symbol: "hand.point.up.left", keywords: "help demo", gold: true) {
            router.paths[.home] = []
            router.select(.home)
            TourPresenter.start(after: 0.6)
        })
        // No "Switch to" actions while paired: the accounts behind them are this phone's samples.
        return hits
    }

    /// Bots and chats come from Home's own store, which reads them when the phone connects.
    private var homeWait: (waiting: Bool, problem: String?) {
        guard !chats.isSample, !chats.homeLoaded else { return (false, nil) }
        if let error = chats.homeError { return (false, "Your bots and chats could not be read. " + error) }
        switch Connection.shared.state {
        case .connecting, .connected: return (true, nil)
        case .sample, .offline, .signedOut: return (false, "Your bots and chats could not be read. " + Connection.shared.statusLine)
        }
    }

    private var botHits: [SearchLiveHit] {
        guard !chats.isSample else { return [] }
        return chats.bots.map { bot -> SearchLiveHit in
            SearchLiveHit(id: "b-\(bot.id)", title: bot.name, detail: bot.role, symbol: "", bot: bot) {
                router.push(.bot(bot.id), on: .home)
            }
        }
    }

    private var chatHits: [SearchLiveHit] {
        guard !chats.isSample else { return [] }
        var hits = chats.chats.map { conversation -> SearchLiveHit in
            SearchLiveHit(id: "c-\(conversation.id)", title: conversation.title,
                          detail: [conversation.preview, conversation.time].filter { !$0.isEmpty }.joined(separator: " · "), symbol: "sparkle") {
                router.open(conversation)
            }
        }
        hits += chats.projects.map { project -> SearchLiveHit in
            SearchLiveHit(id: "p-\(project.id)", title: project.name, detail: "Project", symbol: "folder", keywords: "project") {
                router.push(.project(project.id), on: .home)
            }
        }
        return hits
    }

    /// The rooms list, from the Rooms screen's store when it has read it, else from Search's own read.
    private var roomList: [BotRoomDTO] {
        if rooms.isCurrent && rooms.roomListLoad == .loaded { return rooms.shownRoomList() }
        return model.ask(.rooms) == .answered ? model.rooms : []
    }

    /// Bot conversations whose messages match, from the desktop's own chat search. Each row names the bot and the
    /// conversation. A match in a bot's seat in a room opens that room. Any other match opens the bot's chat and says
    /// where the match is: this phone cannot open one exact bot conversation yet.
    private var botChatHits: [SearchLiveHit] {
        guard searched else { return [] }
        let list = roomList
        var hits: [SearchLiveHit] = []
        for hit in model.chats {
            guard let bot = chats.bots.first(where: { $0.id == hit.botID }) else { continue }
            if let room = list.first(where: { room in (room.members ?? []).contains { $0.seatSessionId == hit.id } }) {
                let name = (room.name ?? "").isEmpty ? "Room" : (room.name ?? "Room")
                hits.append(SearchLiveHit(id: "bc-\(hit.id)", title: "\(name) · \(bot.name)", detail: hit.snippet.isEmpty ? "In this room" : hit.snippet,
                                          symbol: "number", stays: true) {
                    cover = .room(room.id)
                })
            } else {
                let title = hit.title.isEmpty ? "\(bot.name) · A conversation" : "\(bot.name) · \(hit.title)"
                hits.append(SearchLiveHit(id: "bc-\(hit.id)", title: title, detail: hit.snippet.isEmpty ? "In a conversation with \(bot.name)" : hit.snippet,
                                          symbol: "bubble.left.and.text.bubble.right", stays: true) {
                    openConversation(hit.id, title: hit.title)
                })
            }
            if hits.count == 8 { break }
        }
        return hits
    }

    private var teamSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Teams")
        var hits: [SearchLiveHit] = []
        if bots.liveMode && bots.rosterLoad == .loaded {
            hits = bots.teams.map { team -> SearchLiveHit in
                teamHit(team.id, title: team.name,
                        detail: [team.department, team.members.count == 1 ? "1 bot" : "\(team.members.count) bots"].filter { !$0.isEmpty }.joined(separator: " · "))
            }
        } else {
            apply(model.ask(.teams), to: &section)
            if model.ask(.teams) == .answered {
                hits = model.teams.map { teamHit($0.id, title: $0.title, detail: $0.detail) }
            }
        }
        section.hits = picked(hits)
        return section
    }

    private func teamHit(_ id: String, title: String, detail: String) -> SearchLiveHit {
        SearchLiveHit(id: "tm-\(id)", title: title, detail: detail, symbol: "person.3", keywords: "team", stays: true) {
            cover = .team(id)
        }
    }

    private var roomSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Rooms")
        if !(rooms.isCurrent && rooms.roomListLoad == .loaded) { apply(model.ask(.rooms), to: &section) }
        section.hits = picked(roomList.map { room -> SearchLiveHit in
            let name = (room.name ?? "").isEmpty ? "Room" : (room.name ?? "Room")
            let count = room.members?.count ?? 0
            return SearchLiveHit(id: "rm-\(room.id)", title: name, detail: count == 1 ? "1 bot" : "\(count) bots",
                                 symbol: "number", keywords: "room", stays: true) {
                cover = .room(room.id)
            }
        })
        return section
    }

    private var vaultSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Vault")
        let live = !vaultStore.isSample && vaultStore.liveAccount == VaultStore.accountKey
        var hits: [SearchLiveHit] = []
        if live && !needle.isEmpty {
            // Titles the Vault screen already holds, at once; then what the desktop's search finds (it searches
            // titles too, so the Vault list is not read here).
            let named = vaultStore.notes.values.filter { $0.title.lowercased().contains(needle) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.prefix(8)
            hits = named.map { note in vaultHit(note.id, title: note.title, detail: note.folder.isEmpty ? "Vault" : note.folder) }
        }
        if live && searched {
            for hit in model.vault where !hits.contains(where: { $0.id == "v-\(hit.id)" }) {
                hits.append(vaultHit(hit.id, title: hit.title, detail: hit.snippet.isEmpty ? "Vault" : hit.snippet))
            }
        }
        section.hits = Array(hits.prefix(12))
        apply(model.vaultWait, to: &section)
        return section
    }

    private func vaultHit(_ id: String, title: String, detail: String) -> SearchLiveHit {
        SearchLiveHit(id: "v-\(id)", title: title, detail: detail, symbol: "doc.text", stays: true) {
            cover = .vault(id)
        }
    }

    private var notesRead: Bool { !SearchLiveModel.unread(.notes) }

    private var noteSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Notes")
        let list: [KNote]
        if notesRead {
            list = notes.notes
        } else {
            apply(model.ask(.notes), to: &section)
            list = model.ask(.notes) == .answered ? model.notes : []
        }
        let fromStore = notesRead
        section.hits = picked(list.map { note -> SearchLiveHit in
            let detail = note.done ? "Done" : (note.due.map { "Due " + SearchLiveText.day($0) } ?? "Note")
            return SearchLiveHit(id: "n-\(note.id)", title: SearchLiveText.line(note.text), detail: detail, symbol: "note.text", stays: fromStore) {
                if fromStore && notes.note(note.id) != nil {
                    noteSheet = NotesSheetItem(id: note.id)
                } else {
                    // The Notes screen has not read its list yet, so its note sheet cannot open from here.
                    router.open(.notes)
                    chrome.say("Notes is open. The note is in the list.")
                }
            }
        })
        return section
    }

    private var documentList: [LibraryDocument] {
        if !SearchLiveModel.unread(.documents) { return docs.documents }
        return model.ask(.documents) == .answered ? model.documents : []
    }

    private var documentSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Documents")
        if SearchLiveModel.unread(.documents) { apply(model.ask(.documents), to: &section) }
        let list = documentList
        var hits = picked(list.map { doc -> SearchLiveHit in
            documentHit(doc.id, title: doc.title, detail: "Updated " + SearchLiveText.day(doc.updated))
        })
        if searched {
            // The desktop's text search, in its own order.
            for hit in model.docHits where !hits.contains(where: { $0.id == "doc-\(hit.id)" }) {
                let title = list.first(where: { $0.id == hit.id })?.title ?? hit.title
                hits.append(documentHit(hit.id, title: title, detail: hit.snippet.isEmpty ? "Document" : hit.snippet))
            }
        }
        section.hits = hits
        apply(model.docsWait, to: &section)
        return section
    }

    private func documentHit(_ id: String, title: String, detail: String) -> SearchLiveHit {
        SearchLiveHit(id: "doc-\(id)", title: title, detail: detail, symbol: "doc.richtext", stays: true) {
            cover = .document(id)
        }
    }

    private var chatFileSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Chat files")
        let list: [ChatDocsGroup]
        if !SearchLiveModel.unread(.chatFiles) {
            list = docs.groups
        } else {
            apply(model.ask(.chatFiles), to: &section)
            list = model.ask(.chatFiles) == .answered ? model.groups : []
        }
        var hits: [SearchLiveHit] = []
        for group in list {
            for file in group.files {
                hits.append(SearchLiveHit(id: "cf-\(file.id)", title: file.name, detail: "In \(group.title)", symbol: "paperclip", keywords: "file", stays: true) {
                    openConversation(group.id, title: group.title)
                })
            }
        }
        section.hits = picked(hits)
        return section
    }

    private var driveSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Google Drive")
        guard needle.count >= SearchLiveModel.minimum, !driveStore.isSample, driveStore.liveAccount == DriveStore.accountKey else {
            if model.ask(.drive) == .asking && needle.count >= SearchLiveModel.minimum { section.waiting = true }
            return section
        }
        switch driveStore.accountsLoad {
        case .idle: if model.ask(.drive) == .asking { section.waiting = true }
        case .loading: section.waiting = true
        case .failed(let why): section.problems.append(why)
        case .loaded: break
        }
        guard driveStore.accountsLoad == .loaded, let account = driveStore.currentAccountID else { return section }
        if searched {
            // Only files of the Google account Drive is browsing, so a tap opens Drive on that same account.
            section.hits = model.drive.compactMap { id -> SearchLiveHit? in
                guard let file = driveStore.file(id), file.account == account else { return nil }
                return SearchLiveHit(id: "g-\(id)", title: file.name, detail: "Drive · " + SearchLiveText.day(file.modified),
                                     symbol: file.isFolder ? "folder" : "doc", stays: true) {
                    cover = .drive(id)
                }
            }
        }
        apply(model.driveWait, to: &section)
        return section
    }

    private var taskSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Tasks")
        var hits: [SearchLiveHit] = []
        // A tap opens Tasks: this phone cannot open one card or task from outside it yet.
        if !SearchLiveModel.unread(.tasks) {
            hits = tasks.cards.map { card -> SearchLiveHit in
                SearchLiveHit(id: "tc-\(card.id)", title: card.name, detail: "Card · " + card.column.title, symbol: "rectangle.on.rectangle", keywords: "card task") {
                    router.open(.tasks)
                }
            }
            hits += tasks.jobs.map { job -> SearchLiveHit in
                SearchLiveHit(id: "tj-\(job.id)", title: job.name, detail: "Scheduled task", symbol: "clock", keywords: "scheduled task") {
                    router.open(.tasks)
                }
            }
        } else {
            apply(model.ask(.tasks), to: &section)
            if model.ask(.tasks) == .answered {
                hits = model.tasks.map { row -> SearchLiveHit in
                    SearchLiveHit(id: "t\(row.id)", title: row.title, detail: row.detail,
                                  symbol: row.id.hasPrefix("c-") ? "rectangle.on.rectangle" : "clock", keywords: "task card") {
                        router.open(.tasks)
                    }
                }
            }
        }
        section.hits = picked(hits)
        return section
    }

    private var calendarSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Calendar")
        let list: [CalEvent]
        if !SearchLiveModel.unread(.calendar) {
            list = calendar.events
        } else {
            apply(model.ask(.calendar), to: &section)
            list = model.ask(.calendar) == .answered ? model.events : []
        }
        // A tap opens the Calendar: this phone cannot open one event from outside it yet.
        section.hits = picked(list.sorted { $0.start < $1.start }.map { event -> SearchLiveHit in
            let when = event.allDay ? SearchLiveText.day(event.start)
                : SearchLiveText.day(event.start) + ", " + event.start.formatted(date: .omitted, time: .shortened)
            return SearchLiveHit(id: "e-\(event.id)", title: event.title, detail: when, symbol: "calendar", keywords: "event") {
                router.open(.calendar)
            }
        })
        return section
    }

    private var mailSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Mail")
        // Only what the Mail list shows: sender, subject and when. Never a message's text. A tap opens Mail: this
        // phone cannot open one message from outside it yet.
        let needle = self.needle
        var rows: [SearchLiveRow] = []
        if !SearchLiveModel.unread(.mail) {
            rows = mail.items.map { SearchLiveRow(id: $0.id, title: $0.subjectLine,
                                                  detail: [$0.sender, $0.time].filter { !$0.isEmpty }.joined(separator: " · ")) }
        } else {
            apply(model.ask(.mail), to: &section)
            if model.ask(.mail) == .answered { rows = model.mail }
        }
        section.hits = Array(rows.filter { $0.title.lowercased().contains(needle) || $0.detail.lowercased().contains(needle) }
            .prefix(8).map { row -> SearchLiveHit in
                SearchLiveHit(id: "m-\(row.id)", title: row.title, detail: row.detail, symbol: "envelope") {
                    router.open(.mail)
                }
            })
        return section
    }

    private var settingHits: [SearchLiveHit] {
        let you = YouStore.shared
        return YouIndex.all.map { entry -> SearchLiveHit in
            SearchLiveHit(id: "s-\(entry.id)", title: entry.title, detail: "Settings", symbol: entry.symbol, keywords: entry.keywords, stays: true) {
                you.pendingRoute = entry.route
                router.sheet = .you
            }
        }
    }

    private var areaHits: [SearchLiveHit] {
        JumpArea.allCases.map { area -> SearchLiveHit in
            SearchLiveHit(id: "j-\(area.rawValue)", title: area.title, detail: area.about, symbol: area.symbol) {
                router.open(area)
            }
        }
    }

    /// What to show: the actions, bots, chats and areas before a query; every match while typing.
    private var sections: [SearchLiveSection] {
        let needle = self.needle
        let home = homeWait
        if needle.isEmpty {
            var starters: Set<String> = ["a-chat", "a-note"]
            if let kip = chats.kip { starters.insert("a-call-\(kip.id)") }
            var start = [SearchLiveSection(name: "Actions", hits: actions.filter { starters.contains($0.id) })]
            start.append(SearchLiveSection(name: "Bots", hits: botHits))
            start.append(SearchLiveSection(name: "Chats", hits: Array(chatHits.filter { $0.id.hasPrefix("c-") }.prefix(4))))
            start.append(SearchLiveSection(name: "Areas", hits: areaHits))
            return start.filter { !$0.hits.isEmpty }
        }
        var botSection = SearchLiveSection(name: "Bots", hits: picked(botHits), waiting: home.waiting, problems: home.problem.map { [$0] } ?? [])
        if !botSection.hits.isEmpty { botSection.waiting = false }
        var chatSection = SearchLiveSection(name: "Chats", hits: picked(chatHits) + botChatHits, waiting: home.waiting)
        apply(model.chatsWait, to: &chatSection)
        var all = [
            SearchLiveSection(name: "Actions", hits: picked(actions)),
            botSection,
            chatSection,
            teamSection,
            roomSection,
            vaultSection,
            noteSection,
            documentSection,
            chatFileSection,
            driveSection,
            taskSection,
            calendarSection,
            mailSection,
            SearchLiveSection(name: "Settings", hits: picked(settingHits)),
            SearchLiveSection(name: "Areas", hits: picked(areaHits)),
        ]
        if unreachable != nil {
            // One line for the whole sheet says the desktop is not answering.
            for index in all.indices { all[index].problems = [] }
        }
        return all.filter { !$0.hits.isEmpty || $0.waiting || !$0.problems.isEmpty }
    }

    // MARK: The sheet

    var body: some View {
        let shown = sections
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.inkFaint)
                TextField("Search or do something", text: $query)
                    .font(KFont.ui(17))
                    .foregroundStyle(Palette.ink)
                    .focused($typing)
                    .submitLabel(.go)
                    .autocorrectionDisabled()
                    .onSubmit { if let first = sections.first(where: { !$0.hits.isEmpty })?.hits.first { run(first) } }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkFaint).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .frame(height: 50)
            .kCard(radius: 25, raised: true)
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let notice {
                        HintLine(text: notice, symbol: "info.circle")
                            .padding(.top, 12)
                    }
                    if needle.isEmpty {
                        HintLine(text: "Type to search your desktop", symbol: "desktopcomputer")
                            .padding(.top, 12)
                    } else if let unreachable {
                        HintLine(text: "Your desktop could not be searched. " + unreachable, symbol: "exclamationmark.circle")
                            .padding(.top, 12)
                    } else if Connection.shared.state == .connecting {
                        HintLine(text: "Connecting to your desktop. Search asks it as soon as it answers.", symbol: "desktopcomputer")
                            .padding(.top, 12)
                    }
                    ForEach(shown, id: \.name) { section in
                        HStack(spacing: 8) {
                            SectionLabel(text: section.name)
                            if section.waiting {
                                ProgressView()
                                    .controlSize(.mini)
                                    .accessibilityLabel("Still asking your desktop")
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                        ForEach(section.problems, id: \.self) { problem in
                            HintLine(text: problem, symbol: "exclamationmark.circle")
                                .padding(.vertical, 4)
                        }
                        ForEach(section.hits) { hit in
                            row(hit)
                        }
                    }
                    // Never while anything is still being asked, and never under a line saying something failed.
                    if !needle.isEmpty && unreachable == nil
                        && !shown.contains(where: { !$0.hits.isEmpty || $0.waiting || !$0.problems.isEmpty }) {
                        Text("Nothing found")
                            .font(KFont.ui(15.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .kSheet()
        .fullScreenCover(item: $cover) { which in
            coverContent(which)
                .environment(router)
                .environment(chrome)
        }
        .sheet(item: $noteSheet) { item in
            NotesDetailsSheet(store: .shared, item: item)
                .environment(chrome)
        }
        // A trailing space or a change of case alone does not ask the desktop again.
        .onChange(of: trimmed) {
            notice = nil
            if !trimmed.isEmpty { model.warmUp() }
            model.search(trimmed)
        }
        // Something opened a screen behind this sheet (the Vault's "Ask Kairos", a notification): Search gets out of
        // the way so that screen is seen.
        .onChange(of: router.paths) {
            if cover == nil && noteSheet == nil { dismiss() }
        }
        .onAppear {
            SearchLiveModel.followStores()
            if !started {
                started = true
                if !startQuery.isEmpty { query = startQuery } else { typing = true }
            } else if !trimmed.isEmpty {
                // Back on screen after everything was stopped: ask again for what is typed.
                model.warmUp()
                model.search(trimmed)
            }
        }
        .onDisappear {
            model.stop()
            opening?.cancel()
            opening = nil
            openingChat = false
        }
    }

    @ViewBuilder
    private func coverContent(_ which: SearchLiveCover) -> some View {
        switch which {
        case .vault(let id): VaultScreen(start: .note(id))
        case .document(let id): LibraryDocumentEditor(documentID: id)
        case .drive(let id): DriveScreen(startFile: id)
        case .team(let id):
            NavigationStack { TeamScreen(teamID: id).botsDestinations() }
                .tint(Palette.gold)
        case .room(let id):
            NavigationStack { RoomScreen(roomID: id).botsDestinations() }
                .tint(Palette.gold)
        case .call(let bot): CallView(bot: bot)
        }
    }

    private func row(_ hit: SearchLiveHit) -> some View {
        Button { run(hit) } label: {
            HStack(spacing: 13) {
                if let bot = hit.bot {
                    BotFace(bot: bot, size: 50, showStatus: true)
                } else {
                    Image(systemName: hit.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(hit.gold ? Palette.onGold : Palette.goldText)
                        .frame(width: 40, height: 40)
                        .background(hit.gold ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Circle())
                        .frame(width: 50, height: 50)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(hit.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
    }

    private func run(_ hit: SearchLiveHit) {
        Haptics.select()
        if hit.stays {
            hit.run()
        } else {
            dismiss()
            hit.run()
        }
    }

    /// A desktop conversation (a chat file's chat, or a bot chat match). A model chat Home lists opens at once. Any
    /// other is asked about first, so nothing opens for a conversation the desktop does not have, and a bot's
    /// conversation never opens as a model chat: a seat in a room opens the room; a bot's own conversation opens
    /// the bot's chat and says where the match is.
    private func openConversation(_ sessionID: String, title: String) {
        guard !openingChat else { return }
        if let known = chats.conversations.first(where: { $0.id == sessionID }), known.kind == .model {
            dismiss()
            router.push(.chat(sessionID), on: .home)
            return
        }
        openingChat = true
        notice = "Opening the conversation…"
        opening = Task {
            let place = await model.place(of: sessionID)
            openingChat = false
            guard !Task.isCancelled else { return }
            switch place {
            case .gone:
                notice = "This conversation is no longer on your desktop."
            case .failed(let why):
                notice = "This conversation could not be opened. " + why
            case .model:
                notice = nil
                dismiss()
                router.push(.chat(sessionID), on: .home)
            case .room(let roomID):
                notice = nil
                cover = .room(roomID)
            case .bot(let botID):
                guard let bot = chats.bots.first(where: { $0.id == botID }) else {
                    notice = "This conversation belongs to a bot this iPhone does not list."
                    return
                }
                notice = nil
                dismiss()
                router.push(.bot(bot.id), on: .home)
                let match = title.isEmpty ? "one of \(bot.name)'s conversations" : "\u{201C}\(title)\u{201D}"
                chrome.say("\(bot.name)'s chat is open. The match is in \(match), which may be another conversation.")
            }
        }
    }
}

extension SearchLiveModel {
    /// The stores Search lists from or opens move to the paired desktop and account now, before anything of theirs
    /// is listed. A store only drops what it holds when the paired account changed, as its own screen would.
    static func followStores() {
        guard !Connection.shared.usesSampleData else { return }
        VaultStore.shared.followConnection()
        DriveStore.shared.followConnection()
        BotsStore.shared.followConnection()
    }
}
