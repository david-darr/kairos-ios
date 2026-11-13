import SwiftUI

// Search while the phone is paired. Everything it lists is the paired desktop's own, read from the stores the
// areas already keep (bots and chats, teams and rooms, notes, documents and chat files, tasks, calendar, mail)
// and from the desktop searches the areas already have (the Vault, documents, Drive) plus the desktop's bot chat
// search. Search only reads: it never writes anything to the desktop, and nothing it finds is kept on the phone
// beyond the open sheet. Not paired, `SearchView` shows its sample sheet exactly as before.

/// Where one desktop search stands.
nonisolated enum SearchLiveWait: Equatable, Sendable {
    /// Answered, or nothing was asked.
    case ready
    /// Still asking the desktop.
    case waiting
    case failed(String)
}

nonisolated struct SearchLiveVaultHit: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var snippet: String
}

nonisolated struct SearchLiveChatHit: Identifiable, Hashable, Sendable {
    /// The bot conversation's id.
    let id: String
    var botID: String
    var title: String
    var snippet: String
}

/// The desktop searches behind the paired sheet. A search runs only after a short pause in typing and only for
/// two or more characters; an answer for an older query is dropped; closing the sheet cancels everything.
@Observable
final class SearchLiveModel {
    private(set) var vault: [SearchLiveVaultHit] = []
    private(set) var vaultWait: SearchLiveWait = .ready
    /// Document id to snippet ("" for a title match).
    private(set) var docs: [String: String] = [:]
    private(set) var docsWait: SearchLiveWait = .ready
    /// Drive file ids, as the Drive store keeps them.
    private(set) var drive: [String] = []
    private(set) var driveWait: SearchLiveWait = .ready
    private(set) var chats: [SearchLiveChatHit] = []
    private(set) var chatsWait: SearchLiveWait = .ready
    /// The query the desktop is being asked about, "" when none.
    private(set) var asked = ""

    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var account = ""
    @ObservationIgnored private var driveQuery = ""
    @ObservationIgnored private var searches: [Task<Void, Never>] = []
    @ObservationIgnored private var warmups: [Task<Void, Never>] = []
    @ObservationIgnored private var warmed = false

    static let pause: Duration = .milliseconds(350)
    static let minimum = 2

    /// Which desktop and account the answers belong to.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Drive can be searched with one call: the paired desktop's Google accounts are already read.
    var driveSearchable: Bool {
        let store = DriveStore.shared
        return !store.isSample && store.liveAccount == DriveStore.accountKey && store.accountsLoad == .loaded
            && store.currentAccountID != nil
    }

    private func current(_ mine: Int) -> Bool {
        serial == mine && account == Self.accountKey && !Connection.shared.usesSampleData
    }

    // MARK: Asking

    /// A new query: every older search stops, and the desktop is asked after a short pause.
    func search(_ raw: String) {
        stopSearches()
        serial += 1
        let mine = serial
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        vault = []
        docs = [:]
        drive = []
        chats = []
        driveQuery = ""
        guard query.count >= Self.minimum, !Connection.shared.usesSampleData else {
            asked = ""
            vaultWait = .ready
            docsWait = .ready
            driveWait = .ready
            chatsWait = .ready
            return
        }
        asked = query
        account = Self.accountKey
        vaultWait = .waiting
        docsWait = .waiting
        chatsWait = .waiting
        driveWait = driveSearchable ? .waiting : .ready
        searches.append(Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard let self, !Task.isCancelled, self.current(mine) else { return }
            self.launch(query, mine)
        })
    }

    private func launch(_ query: String, _ mine: Int) {
        searches.append(Task { [weak self] in await self?.searchVault(query, mine) })
        searches.append(Task { [weak self] in await self?.searchDocs(query, mine) })
        searches.append(Task { [weak self] in await self?.searchChats(query, mine) })
        if driveSearchable {
            driveQuery = query
            driveWait = .waiting
            searches.append(Task { [weak self] in await self?.searchDrive(query, mine) })
        }
    }

    /// The Drive accounts were read while a query waited: Drive is searched for it now.
    private func driveReady() {
        guard asked.count >= Self.minimum, driveSearchable, driveQuery != asked, current(serial) else { return }
        let mine = serial
        let query = asked
        driveQuery = query
        driveWait = .waiting
        searches.append(Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard let self, !Task.isCancelled, self.current(mine) else { return }
            await self.searchDrive(query, mine)
        })
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
        let store = DocsLiveStore.shared
        store.followConnection()
        let found = await store.search(query)
        guard !Task.isCancelled, current(mine) else { return }
        guard let found else {
            docsWait = .failed("Your documents could not be searched. Try again.")
            return
        }
        docs = found.mapValues(SearchLiveText.line)
        docsWait = .ready
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
        guard let client = Connection.shared.client, !ChatStore.shared.isSample else {
            if current(mine) { chatsWait = .failed(APIError.notPaired.plain) }
            return
        }
        do {
            let found = try await client.searchBotChats(query, limit: 30)
            guard !Task.isCancelled, current(mine) else { return }
            // Only the paired desktop's own bots, and only the version of each conversation that is on screen.
            let known = Set(ChatStore.shared.bots.map(\.id))
            var seen = Set<String>()
            var hits: [SearchLiveChatHit] = []
            for hit in found.hits where !hit.isOtherVersion {
                guard let bot = hit.bot, known.contains(bot), seen.insert(hit.sessionId).inserted else { continue }
                hits.append(SearchLiveChatHit(id: hit.sessionId, botID: bot, title: hit.title?.string ?? "",
                                              snippet: SearchLiveText.line(hit.snippet?.string ?? "")))
                if hits.count == 8 { break }
            }
            chats = hits
            chatsWait = .ready
        } catch {
            guard !(error is CancellationError), !Task.isCancelled, current(mine) else { return }
            Connection.shared.note(error)
            chatsWait = .failed("Bot chats could not be searched. " + error.plainWords)
        }
    }

    // MARK: What the stores already hold

    /// Once per open sheet, at the first letter typed: every store that has not been read yet is read once, the
    /// way its own screen reads it, so its items can be searched here. A store already reading is left to it.
    func warmUp() {
        guard !warmed, !Connection.shared.usesSampleData else { return }
        warmed = true
        warmups.append(Task { await HomeFaces.loadTeams() })
        warmups.append(Task {
            let rooms = BotRoomLiveStore.shared
            switch rooms.roomListState() {
            case .idle, .failed: await rooms.loadRoomList()
            case .loading, .loaded: break
            }
        })
        warmups.append(Task {
            let notes = NotesStore.shared
            switch notes.liveLoad {
            case .idle, .failed: await notes.loadLive()
            case .loading, .loaded: break
            }
        })
        warmups.append(Task {
            let docs = DocsLiveStore.shared
            let idle: (DocsLiveLoad) -> Bool = { load in
                switch load {
                case .idle, .failed: true
                case .loading, .loaded: false
                }
            }
            if idle(docs.docsLoad) || idle(docs.filesLoad) { await docs.loadAll() }
        })
        warmups.append(Task { await TasksStore.shared.loadLiveIfNeeded() })
        warmups.append(Task {
            let calendar = CalStore.shared
            switch calendar.liveLoad {
            case .idle, .failed: await calendar.loadLive()
            case .loading, .loaded: break
            }
        })
        warmups.append(Task {
            let mail = MailStore.shared
            switch mail.liveLoad {
            case .idle, .failed: await mail.loadLive()
            case .loading, .loaded: break
            }
        })
        warmups.append(Task { [weak self] in
            await DriveStore.shared.overviewTask()
            guard !Task.isCancelled else { return }
            self?.driveReady()
        })
    }

    /// Every store moves to the paired desktop and account now, before anything of theirs is listed.
    static func followStores() {
        guard !Connection.shared.usesSampleData else { return }
        VaultStore.shared.followConnection()
        NotesStore.shared.followConnection()
        DocsLiveStore.shared.followConnection()
        DriveStore.shared.followConnection()
        BotsStore.shared.followConnection()
        BotRoomLiveStore.shared.followConnection()
        TasksStore.shared.followConnection()
        CalStore.shared.followConnection()
        MailStore.shared.followConnection()
    }

    // MARK: Stopping

    private func stopSearches() {
        for task in searches { task.cancel() }
        searches = []
    }

    /// The sheet closed: every search and read it started stops.
    func stop() {
        stopSearches()
        for task in warmups { task.cancel() }
        warmups = []
        serial += 1
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
    /// True when running it leaves Search open (a cover or sheet over it).
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

    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

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

    // MARK: Sections

    private var actions: [SearchLiveHit] {
        let you = YouStore.shared
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
        for account in you.accounts where account.id != you.currentID {
            hits.append(SearchLiveHit(id: "a-switch-\(account.id)", title: "Switch to \(account.name)", detail: "Account on this phone",
                                      symbol: "arrow.left.arrow.right", keywords: "account user", stays: true, gold: true) {
                you.pendingRoute = .accounts
                router.sheet = .you
            })
        }
        return hits
    }

    /// Bots and chats come from Home's own store, which reads them when the phone pairs.
    private var homeWait: (waiting: Bool, problem: String?) {
        guard !chats.isSample else { return (true, nil) }
        if chats.homeLoaded { return (false, nil) }
        if let error = chats.homeError { return (false, "Your bots and chats could not be read. " + error) }
        return (true, nil)
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

    /// Bot conversations whose messages match, from the desktop's own chat search.
    private var botChatHits: [SearchLiveHit] {
        guard model.asked.lowercased() == needle else { return [] }
        return model.chats.compactMap { hit -> SearchLiveHit? in
            guard let bot = chats.bots.first(where: { $0.id == hit.botID }) else { return nil }
            let title = hit.title.isEmpty ? bot.name : "\(bot.name) · \(hit.title)"
            return SearchLiveHit(id: "bc-\(hit.id)", title: title, detail: hit.snippet, symbol: "bubble.left.and.text.bubble.right") {
                router.push(.bot(bot.id), on: .home)
            }
        }
    }

    private func wait(_ state: BotsLiveLoad) -> (waiting: Bool, problem: String?) {
        switch state {
        case .idle, .loading: (true, nil)
        case .loaded: (false, nil)
        case .failed(let why): (false, why)
        }
    }

    private var teamSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Teams")
        guard bots.liveMode else { section.waiting = true; return section }
        (section.waiting, section.problems) = split(wait(bots.rosterLoad))
        guard bots.rosterLoad == .loaded else { return section }
        section.hits = picked(bots.teams.map { team -> SearchLiveHit in
            SearchLiveHit(id: "tm-\(team.id)", title: team.name,
                          detail: [team.department, team.members.count == 1 ? "1 bot" : "\(team.members.count) bots"].filter { !$0.isEmpty }.joined(separator: " · "),
                          symbol: "person.3", keywords: "team", stays: true) {
                cover = .team(team.id)
            }
        })
        return section
    }

    private var roomSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Rooms")
        (section.waiting, section.problems) = split(wait(rooms.roomListState()))
        section.hits = picked(rooms.shownRoomList().map { room -> SearchLiveHit in
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
            // Titles the vault list already holds, at once; then what the desktop's text search finds.
            let named = vaultStore.notes.values.filter { $0.title.lowercased().contains(needle) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.prefix(8)
            hits = named.map { note in vaultHit(note.id, title: note.title, detail: note.folder.isEmpty ? "Vault" : note.folder) }
        }
        if live && model.asked.lowercased() == needle {
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

    private var noteSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Notes")
        guard !notes.isSample, notes.liveAccount == NotesStore.accountKey else { section.waiting = true; return section }
        switch notes.liveLoad {
        case .idle, .loading: section.waiting = notes.notes.isEmpty
        case .loaded: break
        case .failed(let why): if notes.notes.isEmpty { section.problems = [why] }
        }
        section.hits = picked(notes.notes.map { note -> SearchLiveHit in
            let detail = note.done ? "Done" : (note.due.map { "Due " + SearchLiveText.day($0) } ?? "Note")
            return SearchLiveHit(id: "n-\(note.id)", title: SearchLiveText.line(note.text), detail: detail, symbol: "note.text", stays: true) {
                noteSheet = NotesSheetItem(id: note.id)
            }
        })
        return section
    }

    private var docsLive: Bool { docs.isLive && docs.account == DocsLiveStore.accountKey }

    private var documentSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Documents")
        guard docsLive else { section.waiting = true; return section }
        switch docs.docsLoad {
        case .idle, .loading: section.waiting = docs.documents.isEmpty
        case .loaded: break
        case .failed(let why): if docs.documents.isEmpty { section.problems = [why] }
        }
        var hits = picked(docs.documents.map { doc -> SearchLiveHit in
            documentHit(doc.id, title: doc.title, detail: "Updated " + SearchLiveText.day(doc.updated))
        })
        if model.asked.lowercased() == needle {
            // The desktop's text search, in the list's order.
            let order = docs.documents.map(\.id)
            let found = model.docs.keys.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
            for id in found where !hits.contains(where: { $0.id == "doc-\(id)" }) {
                guard let doc = docs.documents.first(where: { $0.id == id }) else { continue }
                let snippet = model.docs[id] ?? ""
                hits.append(documentHit(id, title: doc.title, detail: snippet.isEmpty ? "Document" : snippet))
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
        guard docsLive else { section.waiting = true; return section }
        switch docs.filesLoad {
        case .idle, .loading: section.waiting = docs.groups.isEmpty
        case .loaded: break
        case .failed(let why): if docs.groups.isEmpty { section.problems = [why] }
        }
        var hits: [SearchLiveHit] = []
        for group in docs.groups {
            for file in group.files {
                hits.append(SearchLiveHit(id: "cf-\(file.id)", title: file.name, detail: "In \(group.title)", symbol: "paperclip", keywords: "file", stays: true) {
                    openChat(group.id)
                })
            }
        }
        section.hits = picked(hits)
        return section
    }

    private var driveSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Google Drive")
        if model.asked.lowercased() == needle {
            section.hits = model.drive.compactMap { id -> SearchLiveHit? in
                guard let file = driveStore.file(id) else { return nil }
                return SearchLiveHit(id: "g-\(id)", title: file.name, detail: "Drive · " + SearchLiveText.day(file.modified),
                                     symbol: file.isFolder ? "folder" : "doc", stays: true) {
                    cover = .drive(id)
                }
            }
        }
        apply(model.driveWait, to: &section)
        if model.driveWait == .ready && needle.count >= SearchLiveModel.minimum && !driveStore.isSample {
            switch driveStore.accountsLoad {
            case .idle, .loading: section.waiting = true
            case .failed(let why): section.problems.append(why)
            case .loaded: break
            }
        }
        return section
    }

    private var taskSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Tasks")
        guard tasks.isLive, tasks.liveAccount == TasksStore.accountKey else { section.waiting = true; return section }
        switch tasks.boardLoad {
        case .idle, .loading: section.waiting = tasks.cards.isEmpty && tasks.jobs.isEmpty
        case .loaded: break
        case .failed(let why): if tasks.cards.isEmpty && tasks.jobs.isEmpty { section.problems = [why] }
        }
        var hits = tasks.cards.map { card -> SearchLiveHit in
            SearchLiveHit(id: "tc-\(card.id)", title: card.name, detail: "Card · " + card.column.title, symbol: "rectangle.on.rectangle", keywords: "card task") {
                router.open(.tasks)
            }
        }
        hits += tasks.jobs.map { job -> SearchLiveHit in
            SearchLiveHit(id: "tj-\(job.id)", title: job.name, detail: "Scheduled task", symbol: "clock", keywords: "scheduled task") {
                router.open(.tasks)
            }
        }
        section.hits = picked(hits)
        return section
    }

    private var calendarSection: SearchLiveSection {
        var section = SearchLiveSection(name: "Calendar")
        guard !calendar.isSample, calendar.liveAccount == CalStore.accountKey else { section.waiting = true; return section }
        switch calendar.liveLoad {
        case .idle, .loading: section.waiting = calendar.events.isEmpty
        case .loaded: break
        case .failed(let why): if calendar.events.isEmpty { section.problems = [why] }
        }
        let events = calendar.events.sorted { $0.start < $1.start }
        section.hits = picked(events.map { event -> SearchLiveHit in
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
        guard !mail.isSample, mail.liveAccount == MailStore.accountKey else { section.waiting = true; return section }
        switch mail.liveLoad {
        case .idle, .loading: section.waiting = true
        case .loaded: break
        case .failed(let why): section.problems = [why]
        }
        guard mail.liveLoad == .loaded else { return section }
        // Only what the Mail screen shows in its list: sender, subject and when. Never a message's text.
        let needle = self.needle
        section.hits = Array(mail.items.filter { item in
            item.sender.lowercased().contains(needle) || item.subjectLine.lowercased().contains(needle)
        }.prefix(8).map { item -> SearchLiveHit in
            SearchLiveHit(id: "m-\(item.id)", title: item.subjectLine,
                          detail: [item.sender, item.time].filter { !$0.isEmpty }.joined(separator: " · "), symbol: "envelope") {
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

    private func split(_ wait: (waiting: Bool, problem: String?)) -> (Bool, [String]) {
        (wait.waiting, wait.problem.map { [$0] } ?? [])
    }

    private func apply(_ wait: SearchLiveWait, to section: inout SearchLiveSection) {
        switch wait {
        case .ready: break
        case .waiting: section.waiting = true
        case .failed(let why): section.problems.append(why)
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
        let all = [
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
                    if !needle.isEmpty && !shown.contains(where: { !$0.hits.isEmpty || $0.waiting }) {
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
        .onChange(of: query) {
            notice = nil
            if !needle.isEmpty { model.warmUp() }
            model.search(query)
        }
        .onAppear {
            SearchLiveModel.followStores()
            if !startQuery.isEmpty { query = startQuery }
            if startQuery.isEmpty { typing = true }
        }
        .onDisappear {
            model.stop()
            opening?.cancel()
            opening = nil
        }
    }

    @ViewBuilder
    private func coverContent(_ which: SearchLiveCover) -> some View {
        switch which {
        case .vault(let id): VaultScreen(start: .note(id))
        case .document(let id): LibraryDocumentEditor(documentID: id)
        case .drive(let id): SearchLiveDriveCover(fileID: id)
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

    /// A chat file's chat: one Home already lists opens at once; any other is checked on the desktop first, as
    /// Chat documents does, so no screen opens for a chat the desktop does not have.
    private func openChat(_ sessionID: String) {
        if let conversation = chats.conversations.first(where: { $0.id == sessionID }) {
            dismiss()
            router.open(conversation)
            return
        }
        guard !openingChat else { return }
        openingChat = true
        notice = "Opening the chat…"
        opening = Task {
            let problem = await DocsLiveStore.shared.chatProblem(sessionID)
            openingChat = false
            guard !Task.isCancelled else { return }
            if let problem {
                notice = problem
                return
            }
            notice = nil
            dismiss()
            router.paths[.home] = []
            router.push(.chat(sessionID), on: .home)
        }
    }
}

/// Google Drive opened at one file from Search: the Drive cover with that file's preview (or folder) on top,
/// so Back leads into the paired desktop's Drive. The same screens and sheets as `DriveScreen`.
struct SearchLiveDriveCover: View {
    @Environment(\.dismiss) private var dismiss
    @State private var toaster: FilesToaster
    @State private var ui: DriveUI

    init(fileID: String) {
        let toaster = FilesToaster()
        let ui = DriveUI(store: DriveStore.shared, toaster: toaster, debug: .none)
        if let file = DriveStore.shared.file(fileID) {
            ui.path = [ui.route(for: file)]
        }
        _toaster = State(initialValue: toaster)
        _ui = State(initialValue: ui)
    }

    var body: some View {
        NavigationStack(path: $ui.path) {
            DriveBrowser(folderID: nil, close: { dismiss() })
                .navigationDestination(for: DriveRoute.self) { route in
                    destination(route)
                }
        }
        .environment(ui)
        .task(id: DriveStore.connectionKey) {
            let store = ui.store
            let wasSample = store.isSample
            let wasAccount = store.liveAccount
            store.followConnection()
            // Another desktop or Kairos account: nothing from the one before stays open.
            if wasSample != store.isSample || (!store.isSample && wasAccount != store.liveAccount) {
                ui.path = []
                ui.selected = []
                ui.selecting = false
            }
            guard !store.isSample else { return }
            switch store.accountsLoad {
            case .idle, .failed: await store.loadAccountsLive()
            case .loading, .loaded: break
            }
        }
        .onChange(of: ui.query) { ui.dropSelectionLive() }
        .onChange(of: ui.filter) { ui.dropSelectionLive() }
        .onChange(of: ui.section) { ui.dropSelectionLive() }
        .onChange(of: ui.grid) { ui.dropSelectionLive() }
        .onChange(of: ui.path) { ui.dropSelectionLive() }
        .onChange(of: ui.store.currentAccountID) { ui.dropSelectionLive() }
        .filesToasts(toaster)
        .sheet(item: $ui.sheet, onDismiss: { ui.runPending() }) { sheet in
            sheetContent(sheet)
                .environment(ui)
                .environment(toaster)
        }
        .alert(ui.prompt.title, isPresented: $ui.promptShown) {
            TextField(ui.prompt.placeholder, text: $ui.promptText)
            Button("Save") { ui.savePrompt() }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $ui.importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            ui.receive(result)
        }
    }

    @ViewBuilder
    private func destination(_ route: DriveRoute) -> some View {
        switch route {
        case .folder(let id): DriveBrowser(folderID: id, close: {})
        case .details(let id): DriveDetailsView(fileID: id, openSharing: false)
        case .sharing(let id): DriveDetailsView(fileID: id, openSharing: true)
        case .preview(let id): DrivePreviewView(fileID: id)
        case .sheetEditor(let id): DriveSheetEditor(fileID: id)
        case .formEditor(let id): DriveFormEditor(fileID: id)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: DriveSheet) -> some View {
        switch sheet {
        case .accounts: DriveAccountsSheet()
        case .newMenu: DriveNewSheet()
        case .move(let ids): DriveMoveSheet(ids: ids)
        case .confirm(let ask): ConfirmSheet(title: ask.title, detail: ask.detail, confirm: ask.confirm, danger: ask.danger, action: ask.action)
        }
    }
}
