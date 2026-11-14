import SwiftUI
import UIKit

// The paired desktop behind Make > Designs (routes/design_routes.py). While paired, the list, a design, its
// boards, versions, comments, tokens and linked chats are the desktop's own; unpaired, nothing here runs and
// DesignViews.swift shows its sample designs. A board is the desktop's rendered page in the design web view.
// The design routes take no revision (the last writer wins), so every write sends only what changed and the
// design is read again after it.

// MARK: - Models

nonisolated enum MakeDesignLoad: Equatable, Sendable {
    case idle, loading, loaded
    /// The desktop no longer has it.
    case gone
    case failed(String)
}

/// How one change ended.
nonisolated enum MakeDesignOutcome: Equatable, Sendable {
    case saved
    /// Not sent: another change to this design is on its way.
    case busy
    /// The desktop refused it, so it certainly did not happen.
    case failed(String)
    /// The answer never arrived. The design was read again; the sentence says what to check.
    case unconfirmed(String)
}

nonisolated struct MakeDesignRow: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var boardCount: Int
    var version: Int
    var updated: Date?
    var firstBoard: String?
    var chatTitle: String?
    var boardTitles: [String]

    init(_ dto: MakeDesignRowDTO) {
        id = dto.id
        title = dto.title?.string ?? "Untitled design"
        boardCount = dto.boards?.int ?? 0
        version = dto.version?.int ?? 0
        updated = MakeDesignWire.time(dto.updated)
        firstBoard = dto.firstBoard?.string
        chatTitle = dto.chatTitle?.string
        boardTitles = dto.boardTitles?.array?.compactMap(\.string) ?? []
    }
}

/// One board, keyed by the desktop's slug.
nonisolated struct MakeDesignBoard: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var width: Double
    var height: Double
    var sizeText: String
    /// The canvas row it belongs to ("website:desktop", "slides").
    var section: String

    var aspect: CGFloat { CGFloat(width / max(1, height)) }

    init(slug: String, _ dto: MakeDesignBoardDTO) {
        id = slug
        title = dto.title?.string ?? slug
        width = max(1, dto.w?.double ?? 800)
        height = max(1, dto.h?.double ?? 600)
        let size = "\(Int(width))x\(Int(height))"
        if let label = dto.formatLabel?.string, !label.isEmpty {
            sizeText = dto.grows?.bool == true ? "\(label) · \(Int(width)) wide" : "\(label) · \(size)"
        } else {
            sizeText = size
        }
        section = dto.section?.string ?? dto.format?.string ?? "custom"
    }

    /// The boards in the desktop's order: `order` first, then anything it left out by its own number.
    static func ordered(_ boards: [String: MakeDesignMaybe<MakeDesignBoardDTO>]?, order: [String]) -> [MakeDesignBoard] {
        var read: [String: MakeDesignBoard] = [:]
        var place: [String: Double] = [:]
        for (slug, maybe) in boards ?? [:] {
            guard let dto = maybe.value else { continue }
            read[slug] = MakeDesignBoard(slug: slug, dto)
            place[slug] = dto.order?.double ?? 0
        }
        var out: [MakeDesignBoard] = []
        for slug in order {
            if let board = read.removeValue(forKey: slug) { out.append(board) }
        }
        let rest = read.keys.sorted { first, second in
            let a = place[first] ?? 0
            let b = place[second] ?? 0
            return a == b ? first < second : a < b
        }
        for slug in rest {
            if let board = read[slug] { out.append(board) }
        }
        return out
    }
}

nonisolated struct MakeDesignChat: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
}

/// A pinned comment, keyed by the desktop's own 8-character id.
nonisolated struct MakeDesignComment: Identifiable, Hashable, Sendable {
    let id: String
    var number: Int
    var board: String
    var elementIDs: [String]
    var pointX: Double?
    var pointY: Double?
    var text: String
    /// "open", "addressed" or "resolved".
    var status: String
    var addressedIn: Int?
    var madeOn: Int

    var isOpen: Bool { status == "open" }

    init(number: Int, _ dto: MakeDesignCommentDTO) {
        id = dto.id
        self.number = number
        board = dto.board?.string ?? ""
        elementIDs = dto.elementIds?.array?.compactMap(\.string) ?? []
        pointX = dto.point?["x"]?.double
        pointY = dto.point?["y"]?.double
        text = dto.text?.string ?? ""
        let read = dto.status?.string ?? "open"
        status = read == "addressed" || read == "resolved" ? read : "open"
        addressedIn = dto.addressedIn?.int
        madeOn = dto.madeOnVersion?.int ?? 0
    }
}

/// One value of the design's look ("--ds-accent"), with the look's own value.
nonisolated struct MakeDesignToken: Identifiable, Hashable, Sendable {
    let id: String
    var value: String
    var standard: String?

    var name: String { id.hasPrefix("--ds-") ? String(id.dropFirst(5)) : id }
}

nonisolated struct MakeDesignDoc: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var version: Int
    var boards: [MakeDesignBoard]
    var chats: [MakeDesignChat]
    var comments: [MakeDesignComment]
    var tokens: [MakeDesignToken]
    /// The values this design changed from its look.
    var overridden: Set<String>
    var lookName: String
    /// The desktop app's own window is open, so PNG, PDF and PowerPoint can be made.
    var canRender: Bool

    var openComments: Int { comments.filter(\.isOpen).count }

    init(_ dto: MakeDesignDTO) {
        id = dto.id
        title = dto.title?.string ?? "Untitled design"
        version = dto.version?.int ?? 0
        boards = MakeDesignBoard.ordered(dto.boards, order: dto.order?.array?.compactMap(\.string) ?? [])
        chats = (dto.chats ?? []).compactMap(\.value).map { MakeDesignChat(id: $0.id, title: $0.title?.string ?? "Chat") }
        let read = (dto.comments ?? []).compactMap(\.value)
        comments = read.enumerated().map { MakeDesignComment(number: $0.offset + 1, $0.element) }
        let variables = dto.system?.value?.variables ?? [:]
        let defaults = dto.system?.value?.defaults ?? [:]
        var values: [MakeDesignToken] = []
        for name in variables.keys.sorted() {
            guard let value = variables[name]?.string else { continue }
            values.append(MakeDesignToken(id: name, value: value, standard: defaults[name]?.string))
        }
        tokens = values
        overridden = Set((dto.tokenOverrides?.object ?? [:]).keys)
        lookName = dto.system?.value?.name?.string ?? "Kairos"
        canRender = dto.renderAvailable?.bool ?? false
    }
}

nonisolated struct MakeDesignVersionRow: Identifiable, Hashable, Sendable {
    let id: Int
    var author: String
    var summary: String
    var tool: String
    var date: Date?
    var name: String?

    init?(_ dto: MakeDesignVersionDTO) {
        guard let number = dto.n?.int else { return nil }
        id = number
        author = dto.by?.string ?? "Kairos"
        summary = dto.summary?.string ?? ""
        tool = dto.tool?.string ?? ""
        date = MakeDesignWire.time(dto.at)
        name = dto.name?.string
    }
}

/// A board's page from the desktop, with the address its pictures and fonts hang from.
nonisolated struct MakeDesignPage: Equatable, Sendable {
    var html: String
    var base: URL
}

nonisolated enum MakeDesignTurnState: Equatable, Sendable {
    case sending
    /// The desktop took the message and a model is working.
    case working
    /// The model is waiting for an approval or an answer in the chat.
    case waiting
    case done
    case failed(String)
    /// The answer never arrived. The same message can go again: its request id starts it only once.
    case lost(String)
}

/// One message to a design's chat, with the request id it keeps for a retry.
nonisolated struct MakeDesignTurn: Equatable, Sendable {
    var sessionID: String
    var message: String
    var references: [MakeDesignReference]
    var requestID: String
    var state: MakeDesignTurnState
    var turnID: String?

    var isOpen: Bool { state == .sending || state == .working || state == .waiting }
    var isLost: Bool { if case .lost = state { return true } else { return false } }
    /// No other message for this design may go while a turn is open or its send is unresolved.
    var blocksSend: Bool { isOpen || isLost }
}

/// "Design with a model", kept so a retry carries on from where it stopped.
nonisolated struct MakeDesignStart: Equatable, Sendable {
    var title: String
    var message: String
    var sessionID: String?
}

// MARK: - Store

@Observable
final class MakeDesignLive {
    static let shared = MakeDesignLive()
    /// The key of the turn that "Design with a model" starts, in `turns`.
    static let startKey = "start"

    private(set) var account = "sample"
    private(set) var rows: [MakeDesignRow] = []
    private(set) var skipped = 0
    private(set) var listLoad: MakeDesignLoad = .idle
    private(set) var docs: [String: MakeDesignDoc] = [:]
    private(set) var docLoad: [String: MakeDesignLoad] = [:]
    private(set) var versions: [String: [MakeDesignVersionRow]] = [:]
    private(set) var versionsLoad: [String: MakeDesignLoad] = [:]
    private(set) var elements: [String: [MakeDesignElement]] = [:]
    private(set) var elementsLoad: [String: MakeDesignLoad] = [:]
    /// Designs with a change on its way. One change at a time for each.
    private(set) var busy: Set<String> = []
    private(set) var creating = false
    private(set) var turns: [String: MakeDesignTurn] = [:]
    /// What the person has typed to the model for each design, kept while they look elsewhere.
    var drafts: [String: String] = [:]

    @ObservationIgnored private var listSerial = 0
    @ObservationIgnored private var listWrites = 0
    @ObservationIgnored private var docSerial: [String: Int] = [:]
    @ObservationIgnored private var versionsSerial: [String: Int] = [:]
    @ObservationIgnored private var writeSerial: [String: Int] = [:]
    @ObservationIgnored private var starting: MakeDesignStart?
    @ObservationIgnored private var startBusy = false
    @ObservationIgnored private var watchers: [String: Task<Void, Never>] = [:]
    /// Turns the person gave up on after a lost answer. The same words to the same chat carry the same
    /// request id again, so a turn the desktop did run is never run a second time.
    @ObservationIgnored private var discarded: [String: MakeDesignTurn] = [:]
    /// Keys whose screen is away: nothing follows their turn until the screen is back.
    @ObservationIgnored private var paused: Set<String> = []
    @ObservationIgnored private var thumbs: [String: UIImage] = [:]

    private static let desktopChanged = "Your paired desktop changed. Try again."
    private static let sample = "This design is a sample."
    private static let changedUnconfirmed = "Your paired desktop changed before this was confirmed. It may have reached the first desktop. Check it there."

    /// After a request whose answer did not arrive, once the desktop or account is no longer the one it went to.
    private static func lostAfterChange(_ error: Error) -> MakeDesignOutcome {
        wasRefused(error) ? .failed(desktopChanged) : .unconfirmed(changedUnconfirmed)
    }

    // MARK: Which desktop

    static var isLive: Bool { !Connection.shared.usesSampleData }

    /// A key that changes when the phone is paired or unpaired, the desktop comes back,
    /// or a different desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Nothing read from another desktop or account may stay.
    func follow() {
        let now = Self.accountKey
        guard now != account else { return }
        for task in watchers.values { task.cancel() }
        watchers = [:]
        rows = []
        skipped = 0
        listLoad = .idle
        docs = [:]
        docLoad = [:]
        versions = [:]
        versionsLoad = [:]
        elements = [:]
        elementsLoad = [:]
        busy = []
        creating = false
        turns = [:]
        discarded = [:]
        paused = []
        drafts = [:]
        starting = nil
        startBusy = false
        thumbs = [:]
        versionsSerial = [:]
        account = now
    }

    /// Still showing the desktop and account a request was sent for. Checked after every await.
    private func stillLive(_ account: String) -> Bool {
        account != "sample" && self.account == account && Self.accountKey == account
    }

    /// The account to work for, or nil when the phone is not paired.
    private func ready() -> String? {
        follow()
        return account == "sample" ? nil : account
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    private static func isMissing(_ error: Error) -> Bool {
        if case .server(status: 404, _) = error as? APIError { return true }
        return false
    }

    /// The desktop refused the request, so it certainly did not act on it. Anything else (not reached,
    /// timed out, an answer this app could not read, a server error) may have come after it did.
    private static func wasRefused(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
    }

    // MARK: Reading

    /// Read the list. Answers true only when this read is what the screen now shows: an older read never
    /// replaces a newer one, a read that crossed a write is read again, and a cancelled read changes nothing.
    @discardableResult
    func loadList() async -> Bool {
        guard let account = ready() else { return false }
        listSerial += 1
        let mine = listSerial
        if listLoad != .loaded { listLoad = .loading }
        for _ in 0..<3 {
            let writes = listWrites
            do {
                let read = try await liveClient().makeDesignList()
                guard stillLive(account), mine == listSerial else { return false }
                guard writes == listWrites else { continue }
                rows = read.compactMap(\.value).map { MakeDesignRow($0) }
                skipped = read.count - rows.count
                listLoad = .loaded
                return true
            } catch {
                if error is CancellationError || Task.isCancelled { return false }
                Connection.shared.note(error)
                guard stillLive(account), mine == listSerial else { return false }
                if listLoad != .loaded { listLoad = .failed("Your designs could not be read. " + error.plainWords) }
                return false
            }
        }
        guard stillLive(account), mine == listSerial else { return false }
        if listLoad != .loaded { listLoad = .failed("Your designs kept changing while they were read. Try again.") }
        return false
    }

    /// Read one design. A read never lands over a change that is on its way: the change reads again itself.
    @discardableResult
    func loadDoc(_ id: String, afterWrite: Bool = false) async -> Bool {
        guard let account = ready() else { return false }
        if busy.contains(id) && !afterWrite { return false }
        let mine = (docSerial[id] ?? 0) + 1
        docSerial[id] = mine
        if docLoad[id] != .loaded { docLoad[id] = .loading }
        for _ in 0..<3 {
            let writes = writeSerial[id] ?? 0
            do {
                let read = try await liveClient().makeDesignGet(id)
                guard stillLive(account), mine == docSerial[id] else { return false }
                guard writes == (writeSerial[id] ?? 0) else { continue }
                let doc = MakeDesignDoc(read)
                if docs[id]?.version != doc.version { forgetElements(id) }
                docs[id] = doc
                docLoad[id] = .loaded
                return true
            } catch {
                if error is CancellationError || Task.isCancelled { return false }
                guard stillLive(account), mine == docSerial[id] else { return false }
                if Self.isMissing(error) {
                    docs[id] = nil
                    docLoad[id] = .gone
                    rows.removeAll { $0.id == id }
                    return false
                }
                Connection.shared.note(error)
                if docLoad[id] != .loaded { docLoad[id] = .failed("This design could not be read. " + error.plainWords) }
                return false
            }
        }
        guard stillLive(account), mine == docSerial[id] else { return false }
        if docLoad[id] != .loaded { docLoad[id] = .failed("This design kept changing while it was read. Try again.") }
        return false
    }

    @discardableResult
    func loadVersions(_ id: String) async -> Bool {
        guard let account = ready() else { return false }
        let mine = (versionsSerial[id] ?? 0) + 1
        versionsSerial[id] = mine
        if versionsLoad[id] != .loaded { versionsLoad[id] = .loading }
        do {
            let read = try await liveClient().makeDesignVersions(id)
            guard stillLive(account), mine == versionsSerial[id] else { return false }
            versions[id] = read.compactMap(\.value).compactMap { MakeDesignVersionRow($0) }.sorted { $0.id > $1.id }
            versionsLoad[id] = .loaded
            return true
        } catch {
            if error is CancellationError || Task.isCancelled { return false }
            Connection.shared.note(error)
            guard stillLive(account), mine == versionsSerial[id] else { return false }
            if versionsLoad[id] != .loaded { versionsLoad[id] = .failed("The versions could not be read. " + error.plainWords) }
            return false
        }
    }

    /// The boards of a design as they were at one version, for a read-only preview.
    func snapshotBoards(_ id: String, number: Int) async -> [MakeDesignBoard]? {
        guard let account = ready() else { return nil }
        do {
            let read = try await liveClient().makeDesignVersion(id, number: number)
            guard stillLive(account), let boards = read.manifest?.boards else { return nil }
            return MakeDesignBoard.ordered(boards, order: [])
        } catch {
            if !(error is CancellationError) { Connection.shared.note(error) }
            return nil
        }
    }

    /// One board as the desktop draws it, now or at a past version. Not kept here: its picture links carry a
    /// token, so the page lives only in the board frame that shows it.
    func page(_ id: String, board: String, stamp: Int, version: Int?) async throws -> MakeDesignPage {
        guard let account = ready() else { throw APIError.notPaired }
        let client = try liveClient()
        let data = try await client.makeDesignRender(id, board: board, version: version)
        guard stillLive(account) else { throw CancellationError() }
        let base = try client.url(MakeDesignWire.path(id, "/boards/" + MakeDesignWire.part(board) + "/render"))
        var origin = "\(client.base.scheme ?? "https")://\(client.base.host ?? "")"
        if let port = client.base.port { origin += ":\(port)" }
        let page = MakeDesignPage(html: MakeDesignWire.guarded(page: String(decoding: data, as: UTF8.self), origin: origin, designID: id),
                                  base: base)
        return page
    }

    private func forgetElements(_ id: String) {
        elements = elements.filter { !$0.key.hasPrefix(id + "/") }
        elementsLoad = elementsLoad.filter { !$0.key.hasPrefix(id + "/") }
    }

    /// The elements of one board, for picking, commenting and text edits.
    func loadElements(_ id: String, board: String) async {
        guard let account = ready() else { return }
        let key = id + "/" + board
        guard elementsLoad[key] != .loaded, elementsLoad[key] != .loading else { return }
        elementsLoad[key] = .loading
        do {
            let read = try await liveClient().makeDesignSource(id, board: board)
            guard stillLive(account) else { return }
            elements[key] = MakeDesignWire.elements(outline: read.outline ?? "")
            elementsLoad[key] = .loaded
        } catch {
            guard stillLive(account) else { return }
            if error is CancellationError || Task.isCancelled {
                elementsLoad[key] = .idle
                return
            }
            Connection.shared.note(error)
            elementsLoad[key] = .failed("This board's elements could not be read. " + error.plainWords)
        }
    }

    /// The whole text of one element as the desktop has it now, to fill the text form or to check a save.
    func elementText(_ id: String, board: String, element: String) async -> String? {
        guard let account = ready() else { return nil }
        guard let read = try? await liveClient().makeDesignSource(id, board: board), stillLive(account) else { return nil }
        return MakeDesignWire.leafText(html: read.html, id: element)
    }

    /// A design's small picture, when the desktop app has drawn one.
    func thumb(_ row: MakeDesignRow) async -> UIImage? {
        guard let account = ready(), let board = row.firstBoard else { return nil }
        let key = "\(row.id)/\(row.version)"
        if let kept = thumbs[key] { return kept }
        guard let path = try? MakeDesignWire.path(row.id, "/boards/" + MakeDesignWire.part(board) + "/thumb"),
              let data = try? await liveClient().bytes(path), stillLive(account), let image = UIImage(data: data) else { return nil }
        if thumbs.count > 80 { thumbs = [:] }
        thumbs[key] = image
        return image
    }

    /// The person's chats that could be linked to a design: not a bot's, not a Forge session, not linked yet.
    func chatsToLink(_ id: String) async -> [MakeDesignChat]? {
        guard let account = ready() else { return nil }
        guard let read = try? await liveClient().chatSessions(), stillLive(account) else { return nil }
        let linked = Set(docs[id]?.chats.map(\.id) ?? [])
        return read.filter { $0.isForge != true && $0.agentId == nil && !linked.contains($0.id) }
            .prefix(30).map { MakeDesignChat(id: $0.id, title: $0.title ?? "Chat") }
    }

    // MARK: Writing

    /// One change to a design: one at a time, the design read again after it, and a lost answer told apart
    /// from a refusal. `landed` looks at the design as just read and says whether what was SENT is there.
    private func write(_ id: String, _ failed: String, _ send: (APIClient) async throws -> Void,
                       landed: (() async -> Bool)? = nil) async -> MakeDesignOutcome {
        guard let account = ready() else { return .failed(Self.sample) }
        guard !busy.contains(id) else { return .busy }
        busy.insert(id)
        defer { if self.account == account { busy.remove(id) } }
        var thrown: Error?
        do {
            try await send(try liveClient())
        } catch {
            thrown = error
        }
        writeSerial[id, default: 0] += 1
        guard stillLive(account) else {
            if let thrown { return Self.lostAfterChange(thrown) }
            return .saved
        }
        guard let failure = thrown else {
            await loadDoc(id, afterWrite: true)
            return .saved
        }
        Connection.shared.note(failure)
        let words = (failed + " " + failure.plainWords).trimmingCharacters(in: .whitespaces)
        if Self.wasRefused(failure) {
            await loadDoc(id, afterWrite: true)
            return .failed(words)
        }
        // The change may have reached the desktop before the answer was lost: read what it really has.
        let read = await loadDoc(id, afterWrite: true)
        guard stillLive(account) else { return .unconfirmed(Self.changedUnconfirmed) }
        if read, let landed, await landed() { return .saved }
        if read {
            return .unconfirmed("Your desktop did not confirm this. The design was read again and shows what it has now. Check it before trying again.")
        }
        return .unconfirmed("Your desktop did not confirm this, and the design could not be read to check. Read it again before trying again.")
    }

    /// A new design, or a copy of one (or of one of its versions). The desktop makes it at once with no key
    /// to send twice, so the list is read first and a lost answer is checked against it.
    func make(copyOf source: String? = nil, version: Int? = nil) async -> (outcome: MakeDesignOutcome, id: String?) {
        guard let account = ready() else { return (.failed(Self.sample), nil) }
        guard !creating else { return (.busy, nil) }
        creating = true
        defer { if self.account == account { creating = false } }
        guard await loadList(), stillLive(account) else {
            return (.failed("Your designs could not be read first, so nothing was made. Try again."), nil)
        }
        let before = Set(rows.map(\.id))
        do {
            let client = try liveClient()
            let made: MakeDesignDTO
            if let source {
                made = try await client.makeDesignDuplicate(source, version: version)
            } else {
                made = try await client.makeDesignCreate(title: "Untitled design")
            }
            listWrites += 1
            guard stillLive(account) else { return (.saved, nil) }
            await loadList()
            return (.saved, made.id)
        } catch {
            listWrites += 1
            Connection.shared.note(error)
            guard stillLive(account) else { return (Self.lostAfterChange(error), nil) }
            if Self.wasRefused(error) { return (.failed("The design was not made. " + error.plainWords), nil) }
            let read = await loadList()
            guard stillLive(account) else { return (.unconfirmed(Self.changedUnconfirmed), nil) }
            let fresh = rows.filter { row in
                !before.contains(row.id) && (source == nil ? row.title == "Untitled design" : row.title.hasSuffix("(copy)"))
            }
            if read, fresh.count == 1 { return (.saved, fresh[0].id) }
            if read {
                return (.unconfirmed("Your desktop did not confirm the new design, and it is not in your list. Check the list before trying again."), nil)
            }
            return (.unconfirmed("Your desktop did not confirm the new design, and your list could not be read to check. Check the list before trying again."), nil)
        }
    }

    /// Delete a design for good. The screen asks first.
    func delete(_ id: String) async -> MakeDesignOutcome {
        let outcome = await write(id, "This design was not deleted.", { client in
            _ = try await client.makeDesignDelete(id)
        }, landed: { false })
        // The read after the delete finds nothing, which is the proof it went.
        if docLoad[id] == .gone {
            listWrites += 1
            rows.removeAll { $0.id == id }
            turns[id] = nil
            drafts[id] = nil
            return .saved
        }
        if outcome == .saved {
            return .unconfirmed("Your desktop answered, but the design is still there. Check it before trying again.")
        }
        return outcome
    }

    func move(_ id: String, board: String, to place: Int) async -> MakeDesignOutcome {
        await write(id, "The board was not moved.", { client in
            _ = try await client.makeDesignReorder(id, board: board, place: place + 1)
        }, landed: { [self] in
            docs[id]?.boards.firstIndex(where: { $0.id == board }) == place
        })
    }

    /// Set one element's text. After a lost answer the element is read again and compared with what was sent.
    func setText(_ id: String, board: String, element: String, text: String) async -> MakeDesignOutcome {
        await write(id, "The text was not saved.", { client in
            _ = try await client.makeDesignSetText(id, board: board, element: element, text: text)
        }, landed: { [self] in
            await elementText(id, board: board, element: element) == text
        })
    }

    /// Change only the named values of the look, or clear every change this design made to it.
    func setTokens(_ id: String, set values: [String: String], clear: Bool = false) async -> MakeDesignOutcome {
        await write(id, clear ? "The look's own values were not put back." : "The values were not saved.", { client in
            _ = try await client.makeDesignTokens(id, set: values, clear: clear)
        }, landed: { [self] in
            guard let doc = docs[id] else { return false }
            if clear && !doc.overridden.isEmpty { return false }
            let now = Dictionary(doc.tokens.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
            return values.allSatisfy { now[$0.key] == $0.value }
        })
    }

    func restore(_ id: String, number: Int) async -> MakeDesignOutcome {
        let before = docs[id]?.version ?? 0
        let outcome = await write(id, "Version \(number) was not restored.", { client in
            _ = try await client.makeDesignRestore(id, number: number)
        }, landed: { [self] in
            await restored(id, since: before, summary: "Restored version \(number)")
        })
        await loadVersions(id)
        return outcome
    }

    /// Step back over the person's own latest direct edit. The desktop refuses when there is none.
    func undo(_ id: String) async -> MakeDesignOutcome {
        let before = docs[id]?.version ?? 0
        let outcome = await write(id, "", { client in
            _ = try await client.makeDesignUndo(id)
        }, landed: { [self] in
            await restored(id, since: before, summary: nil)
        })
        if versionsLoad[id] == .loaded { await loadVersions(id) }
        return outcome
    }

    /// The newest version is a restore made after `since` (and says `summary`, when one is given).
    private func restored(_ id: String, since: Int, summary: String?) async -> Bool {
        guard await loadVersions(id), let newest = versions[id]?.first else { return false }
        return newest.id == since + 1 && newest.tool == "restore" && (summary == nil || newest.summary == summary)
    }

    func nameVersion(_ id: String, number: Int, name: String?) async -> MakeDesignOutcome {
        let outcome = await write(id, "The name was not saved.", { client in
            _ = try await client.makeDesignNameVersion(id, number: number, name: name)
        }, landed: { [self] in
            guard await loadVersions(id), let row = versions[id]?.first(where: { $0.id == number }) else { return false }
            return row.name == name
        })
        if outcome == .saved { await loadVersions(id) }
        return outcome
    }

    func addComment(_ id: String, board: String, elementIDs: [String], point: CGPoint?, text: String) async -> MakeDesignOutcome {
        let before = Set(docs[id]?.comments.map(\.id) ?? [])
        return await write(id, "Your comment was not pinned.", { client in
            _ = try await client.makeDesignCommentAdd(id, board: board, elementIDs: elementIDs, point: point, text: text)
        }, landed: { [self] in
            docs[id]?.comments.contains(where: { !before.contains($0.id) && $0.board == board && $0.text == text }) ?? false
        })
    }

    func setCommentStatus(_ id: String, comment: String, status: String) async -> MakeDesignOutcome {
        await write(id, "The comment was not changed.", { client in
            _ = try await client.makeDesignCommentStatus(id, comment: comment, status: status)
        }, landed: { [self] in
            docs[id]?.comments.first(where: { $0.id == comment })?.status == status
        })
    }

    /// Delete a comment for good. The sheet asks first.
    func deleteComment(_ id: String, comment: String) async -> MakeDesignOutcome {
        await write(id, "The comment was not deleted.", { client in
            _ = try await client.makeDesignCommentDelete(id, comment: comment)
        }, landed: { [self] in
            !(docs[id]?.comments.contains(where: { $0.id == comment }) ?? true)
        })
    }

    func link(_ id: String, sessionID: String) async -> MakeDesignOutcome {
        await write(id, "The chat was not linked.", { client in
            _ = try await client.makeDesignLink(id, sessionID: sessionID)
        }, landed: { [self] in
            docs[id]?.chats.contains(where: { $0.id == sessionID }) ?? false
        })
    }

    /// A new chat in Design mode, linked to this design. Made with no key to send twice, so a lost answer
    /// is checked against the design's chats as they were.
    func startChat(_ id: String, title: String) async -> MakeDesignOutcome {
        let before = Set(docs[id]?.chats.map(\.id) ?? [])
        return await write(id, "The design chat was not made.", { client in
            _ = try await client.makeDesignChatStart(designID: id, title: title)
        }, landed: { [self] in
            docs[id]?.chats.contains(where: { !before.contains($0.id) }) ?? false
        })
    }

    /// Export on the desktop. Answers the file's name, or the sentence to show.
    func export(_ id: String, format: String, sessionID: String?) async -> (outcome: MakeDesignOutcome, name: String?) {
        var name: String?
        var needsDesktop = false
        let outcome = await write(id, "", { client in
            do {
                name = try await client.makeDesignExport(id, format: format, sessionID: sessionID).filename?.string
            } catch {
                // 503 with the desktop's own sentence: this kind needs the desktop app's window.
                if case .server(status: 503, _) = error as? APIError { needsDesktop = true }
                throw error
            }
        })
        if needsDesktop { return (.failed(MakeDesignWire.exportOnDesktop), nil) }
        if case .unconfirmed = outcome {
            return (.unconfirmed("Your desktop did not confirm the export. Look in the chat's files before exporting again."), nil)
        }
        return (outcome, name)
    }

    // MARK: Asking a model

    /// Send a message to a chat linked to the design. It starts a model turn on the desktop, which can use
    /// the person's plan or cost money, so it is sent once: the same message after a lost answer carries
    /// the same request id.
    func send(_ id: String, sessionID: String, message: String, references: [MakeDesignReference]) async -> MakeDesignOutcome {
        guard let account = ready() else { return .failed(Self.sample) }
        if turns[id]?.blocksSend == true { return .busy }
        open(id, sessionID: sessionID, message: message, references: references)
        return await deliver(id, account)
    }

    /// Send the kept message again after a lost answer, with its own request id.
    func sendAgain(_ key: String) async -> MakeDesignOutcome {
        guard let account = ready() else { return .failed(Self.sample) }
        guard var turn = turns[key], case .lost = turn.state else { return .busy }
        turn.state = .sending
        turns[key] = turn
        return await deliver(key, account)
    }

    /// Give up on a message whose answer was lost. The person chooses this; nothing else clears it.
    func discardTurn(_ key: String) {
        guard let turn = turns[key], turn.isLost else { return }
        // Its request id is kept (and for a start, its chat): the desktop may have run it.
        discarded[key] = turn
        turns[key] = nil
    }

    func clearTurn(_ key: String) {
        guard let turn = turns[key], !turn.isOpen else { return }
        turns[key] = nil
    }

    private func open(_ key: String, sessionID: String, message: String, references: [MakeDesignReference]) {
        let requestID: String
        if let old = discarded[key], old.sessionID == sessionID, old.message == message {
            requestID = old.requestID
        } else {
            requestID = UUID().uuidString.lowercased()
        }
        turns[key] = MakeDesignTurn(sessionID: sessionID, message: message, references: references,
                                    requestID: requestID, state: .sending, turnID: nil)
    }

    private func deliver(_ key: String, _ account: String) async -> MakeDesignOutcome {
        guard var turn = turns[key] else { return .failed(Self.desktopChanged) }
        do {
            let answer = try await liveClient().makeDesignSend(sessionID: turn.sessionID, message: turn.message,
                                                               references: turn.references, requestID: turn.requestID)
            guard stillLive(account) else { return .saved }
            turn.turnID = answer.turnId
            turn.state = .working
            turns[key] = turn
            if discarded[key]?.requestID == turn.requestID { discarded[key] = nil }
            if key == Self.startKey { starting = nil }
            watch(key, account)
            return .saved
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return Self.lostAfterChange(error) }
            if Self.wasRefused(error) {
                let words = "Your message was not sent. " + error.plainWords
                turn.state = .failed(words)
                turns[key] = turn
                return .failed(words)
            }
            // The answer was lost. If the turn is running on the desktop, it arrived.
            let running = try? await liveClient().chatSnapshot().runs?[turn.sessionID]
            guard stillLive(account) else { return .unconfirmed(Self.changedUnconfirmed) }
            if let run = running ?? nil, run.status == "processing", run.prompt == turn.message {
                turn.turnID = run.turnId
                turn.state = .working
                turns[key] = turn
                watch(key, account)
                return .saved
            }
            let words = "Your desktop did not confirm this message. Send it again: it cannot run twice."
            turn.state = .lost(words)
            turns[key] = turn
            return .unconfirmed(words)
        }
    }

    private func watch(_ key: String, _ account: String) {
        watchers[key]?.cancel()
        watchers[key] = nil
        // Its screen is away: resumeWatch picks it up when the screen is back.
        guard !paused.contains(key) else { return }
        watchers[key] = Task { await watchTurn(key, account) }
    }

    /// The turn's screen went away: stop following it. The turn and what it says stay.
    func pauseWatch(_ key: String) {
        paused.insert(key)
        watchers[key]?.cancel()
        watchers[key] = nil
    }

    /// The turn's screen is back: follow it again when it is still open on the desktop.
    func resumeWatch(_ key: String) {
        paused.remove(key)
        guard let account = ready(), watchers[key] == nil, let turn = turns[key],
              turn.state == .working || turn.state == .waiting else { return }
        watch(key, account)
    }

    private func refresh(_ key: String) async {
        if key == Self.startKey {
            await loadList()
        } else {
            await loadDoc(key)
            if versionsLoad[key] == .loaded { await loadVersions(key) }
        }
    }

    /// Follow a turn until it ends, reading the design as the model changes it.
    private func watchTurn(_ key: String, _ account: String) async {
        var misses = 0
        for tick in 0..<300 {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, stillLive(account), let turn = turns[key], turn.isOpen else { return }
            guard let packet = try? await liveClient().chatSnapshot() else {
                misses += 1
                if misses > 30 { break }
                continue
            }
            guard !Task.isCancelled, stillLive(account), var now = turns[key], now.isOpen else { return }
            var run = packet.runs?[now.sessionID]
            if let read = run, let mine = now.turnID, let theirs = read.turnId, mine != theirs { run = nil }
            if let run, run.status == "processing" {
                now.state = run.permission != nil ? .waiting : .working
                turns[key] = now
                if tick % 2 == 1 { await refresh(key) }
                continue
            }
            // It ended (or ended a while ago and the desktop has cleared it away).
            await refresh(key)
            guard stillLive(account), var ended = turns[key], ended.isOpen else { return }
            switch run?.status {
            case "failed": ended.state = .failed(run?.error ?? "The model stopped with an error.")
            case "stopped": ended.state = .failed("The model was stopped before it finished.")
            default: ended.state = .done
            }
            turns[key] = ended
            if ended.state == .done {
                try? await Task.sleep(for: .seconds(4))
                if stillLive(account), turns[key]?.state == .done { turns[key] = nil }
            }
            return
        }
        guard stillLive(account), var late = turns[key], late.isOpen else { return }
        late.state = .failed("This is taking a long time. It may still be working on your desktop. Read the design again in a moment.")
        turns[key] = late
    }

    /// "Design with a model": a new chat in Design mode, then the person's words sent to it. Both start
    /// once: the chat is checked against the chats as they were, the message carries a kept request id.
    func startWithModel(prompt: String, format: String) async -> MakeDesignOutcome {
        guard let account = ready() else { return .failed(Self.sample) }
        let key = Self.startKey
        if turns[key]?.blocksSend == true || startBusy { return .busy }
        startBusy = true
        defer { if self.account == account { startBusy = false } }
        let message = prompt + "\n\nFormat: " + format
        // The same words again after a lost answer carry on with the chat that was made for them.
        var job: MakeDesignStart
        if let kept = starting, kept.message == message {
            job = kept
        } else {
            let words = prompt.split(separator: " ").prefix(5).joined(separator: " ")
            let title = words.prefix(1).uppercased() + String(words.dropFirst())
            job = MakeDesignStart(title: title.isEmpty ? "Design" : String(title.prefix(120)), message: message, sessionID: nil)
        }
        starting = job
        if job.sessionID == nil {
            let before: Set<String>
            do {
                before = Set(try await liveClient().chatSessions().map(\.id))
            } catch {
                Connection.shared.note(error)
                return .failed("Your chats could not be read first, so nothing was sent. " + error.plainWords)
            }
            guard stillLive(account) else { return .failed(Self.desktopChanged) }
            do {
                job.sessionID = try await liveClient().makeDesignChatStart(designID: nil, title: job.title).sessionId
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return Self.lostAfterChange(error) }
                if Self.wasRefused(error) { return .failed("The design chat was not made. " + error.plainWords) }
                let after = try? await liveClient().chatSessions()
                guard stillLive(account) else { return .unconfirmed(Self.changedUnconfirmed) }
                let fresh = (after ?? []).filter { !before.contains($0.id) && $0.title == job.title }
                guard after != nil else {
                    return .unconfirmed("Your desktop did not confirm the new chat, and your chats could not be read to check. Look at your chats before trying again.")
                }
                guard fresh.count == 1 else {
                    return .unconfirmed("Your desktop did not confirm the new chat, and it is not in your chats. Nothing was sent to a model. Try again.")
                }
                job.sessionID = fresh[0].id
            }
            guard stillLive(account) else { return .failed(Self.desktopChanged) }
            starting = job
        }
        guard let sessionID = job.sessionID else { return .failed(Self.desktopChanged) }
        open(key, sessionID: sessionID, message: message, references: [])
        let outcome = await deliver(key, account)
        if outcome == .saved { starting = nil }
        return outcome
    }
}

// MARK: - Small pieces

/// One quiet line: loading, or what failed, with one plain action.
struct MakeDesignLine: View {
    let text: String
    var working = false
    var action: String? = nil
    var perform: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            if working { PulsingDot(color: Palette.working) }
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

/// A board as the desktop draws it: its page in the design web view, comment pins, and taps as a point
/// on the board. `maxHeight` shows only the top of a tall board.
struct MakeDesignBoardFrame: View {
    let designID: String
    let board: MakeDesignBoard
    let stamp: Int
    var version: Int? = nil
    var maxHeight: CGFloat? = nil
    var pins: [MakeDesignComment] = []
    var onTap: ((CGPoint) -> Void)? = nil
    var onPin: (() -> Void)? = nil

    @State private var page: MakeDesignPage?
    @State private var problem: String?
    @State private var width: CGFloat = 0
    @State private var attempt = 0

    private var key: String { "\(designID)/\(board.id)/\(stamp)/\(version ?? 0)/\(attempt)/\(MakeDesignLive.connectionKey)" }

    var body: some View {
        let full = CGSize(width: width, height: width / max(0.05, board.aspect))
        let shown = max(44, min(full.height, maxHeight ?? full.height))
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: shown)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay(alignment: .top) {
                ZStack(alignment: .topLeading) {
                    if let page {
                        DesignWebView(html: page.html, base: page.base).allowsHitTesting(false)
                    } else {
                        waiting.frame(width: full.width, height: shown, alignment: .center)
                    }
                    if let onTap, page != nil {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { point in
                                guard full.width > 0, full.height > 0 else { return }
                                onTap(CGPoint(x: min(1, max(0, point.x / full.width)), y: min(1, max(0, point.y / full.height))))
                            }
                    }
                    pinLayer(full)
                }
                .frame(width: full.width, height: max(shown, full.height), alignment: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .task(id: key) { await read() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(board.title)
    }

    @ViewBuilder
    private var waiting: some View {
        if let problem {
            VStack(spacing: 4) {
                Text(problem)
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                Button("Try again") { attempt += 1 }
                    .font(KFont.ui(13.5, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 12)
        } else {
            Text("Reading this board from your desktop...")
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private func pinLayer(_ size: CGSize) -> some View {
        ForEach(Array(pins.enumerated()), id: \.element.id) { offset, pin in
            let point = pinPoint(pin, offset, size)
            Button {
                Haptics.tap()
                onPin?()
            } label: {
                Text("\(pin.number)")
                    .font(KFont.ui(11, .semibold, relativeTo: .caption2))
                    .foregroundStyle(Palette.onGold)
                    .frame(width: 22, height: 22)
                    .background(pin.isOpen ? Palette.gold : Palette.success, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.cream.opacity(0.85), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .allowsHitTesting(onPin != nil)
            .offset(x: point.x - 17, y: point.y - 17)
            .accessibilityLabel("Comment \(pin.number): \(pin.text)")
        }
    }

    /// A comment pinned to a point sits there; one pinned to elements sits in a row along the top.
    private func pinPoint(_ pin: MakeDesignComment, _ offset: Int, _ size: CGSize) -> CGPoint {
        if let x = pin.pointX, let y = pin.pointY {
            return CGPoint(x: min(size.width - 12, max(12, CGFloat(x) * size.width)),
                           y: min(size.height - 12, max(12, CGFloat(y) * size.height)))
        }
        return CGPoint(x: min(size.width - 12, 18 + CGFloat(offset) * 28), y: 18)
    }

    private func read() async {
        problem = nil
        do {
            let read = try await MakeDesignLive.shared.page(designID, board: board.id, stamp: stamp, version: version)
            if page != read { page = read }
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            page = nil
            if case .server(status: 404, _) = error as? APIError, let version {
                problem = "This board was not in version \(version)."
            } else {
                problem = "This board could not be read. " + error.plainWords
            }
        }
    }
}

/// A small picture of a design for the list: the desktop's own when it has drawn one, else its board names.
struct MakeDesignThumbLive: View {
    let row: MakeDesignRow
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.surface2
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    .padding(10)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(row.boardTitles.prefix(4).enumerated()), id: \.offset) { _, title in
                        Text(title)
                            .font(KFont.ui(12, relativeTo: .caption))
                            .foregroundStyle(Palette.inkFaint)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
            }
        }
        .task(id: "\(row.id)/\(row.version)") { image = await MakeDesignLive.shared.thumb(row) }
        .accessibilityHidden(true)
    }
}

// MARK: - The list, paired

struct MakeDesignListLive: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MakeToast.self) private var toast
    @State private var query = ""
    @State private var starting = false
    @State private var openID: String?
    @State private var notice: String?

    private var live: MakeDesignLive { MakeDesignLive.shared }

    private var shown: [MakeDesignRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return live.rows }
        return live.rows.filter { row in
            row.title.lowercased().contains(q) || row.boardTitles.contains { $0.lowercased().contains(q) }
        }
    }

    private var subtitle: String? {
        guard live.listLoad == .loaded else { return nil }
        return live.rows.count == 1 ? "1 design" : "\(live.rows.count) designs"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Screens, pages and slides on a canvas, made and changed with any model.")
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                searchField
                HStack(spacing: 10) {
                    MakePillButton(title: "New design", symbol: "plus", filled: true, expand: true) { newDesign() }
                        .disabled(live.creating)
                        .opacity(live.creating ? 0.5 : 1)
                    MakePillButton(title: "Design with a model", symbol: "sparkles", expand: true) { starting = true }
                        .disabled(live.turns[MakeDesignLive.startKey]?.blocksSend == true)
                        .opacity(live.turns[MakeDesignLive.startKey]?.blocksSend == true ? 0.5 : 1)
                }
                if live.creating { MakeDesignLine(text: "Making a design on your desktop...", working: true) }
                if let notice { MakeDesignLine(text: notice, action: "OK") { self.notice = nil } }
                turnLine
                results
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await live.loadList() }
        .safeAreaInset(edge: .top, spacing: 0) {
            MakeHeader(title: "Designs", subtitle: subtitle, back: { dismiss() })
        }
        .sheet(isPresented: $starting) { MakeDesignStartLive() }
        .navigationDestination(item: $openID) { id in DesignScreen(designID: id) }
        .task(id: MakeDesignLive.connectionKey) {
            live.follow()
            await live.loadList()
        }
        .onAppear { live.resumeWatch(MakeDesignLive.startKey) }
        .onDisappear { live.pauseWatch(MakeDesignLive.startKey) }
        .kScreen()
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.inkFaint)
            TextField("Search designs", text: $query)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { withAnimation(Motion.snappy) { query = "" } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 48)
        .kCard(radius: 16, raised: true)
    }

    /// Where "Design with a model" stands.
    @ViewBuilder
    private var turnLine: some View {
        if let turn = live.turns[MakeDesignLive.startKey] {
            switch turn.state {
            case .sending:
                MakeDesignLine(text: "Sending to your desktop...", working: true)
            case .working:
                MakeDesignLine(text: "Your desktop is working. A model is making your design.", working: true)
            case .waiting:
                MakeDesignLine(text: "The model is waiting for your OK. Answer it in the new chat.", working: true)
            case .done:
                MakeDesignLine(text: "The model finished. A new design shows in the list.", action: "OK") { live.clearTurn(MakeDesignLive.startKey) }
            case .failed(let words):
                MakeDesignLine(text: words, action: "OK") { live.clearTurn(MakeDesignLive.startKey) }
            case .lost(let words):
                MakeDesignLine(text: words, action: "Send again") { Task { _ = await live.sendAgain(MakeDesignLive.startKey) } }
                QuietButton(title: "Discard") { live.discardTurn(MakeDesignLive.startKey) }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if !live.rows.isEmpty {
            if shown.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No designs match").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                    MakePillButton(title: "Clear search") { withAnimation(Motion.snappy) { query = "" } }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: 22)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                        NavigationLink(value: MakeRoute.design(row.id)) { card(row) }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Open \(row.title)")
                            .arrives(index)
                    }
                }
                if live.skipped > 0 {
                    HintLine(text: live.skipped == 1 ? "1 design could not be read and is not shown." : "\(live.skipped) designs could not be read and are not shown.")
                }
            }
        } else {
            switch live.listLoad {
            case .failed(let words):
                MakeDesignLine(text: words, action: "Try again") { Task { await live.loadList() } }
            case .loaded:
                VStack(alignment: .leading, spacing: 10) {
                    Text("No designs yet").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                    EmptyLine(text: "Start a blank design, or ask a model to build one.")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: 22)
            default:
                MakeDesignLine(text: "Reading your designs from your desktop...", working: true)
            }
        }
    }

    private func card(_ row: MakeDesignRow) -> some View {
        let boards = row.boardCount == 1 ? "1 board" : "\(row.boardCount) boards"
        let detail = row.updated.map { "\(boards) · edited \(DesignSample.ago($0))" } ?? boards
        return VStack(alignment: .leading, spacing: 6) {
            MakeDesignThumbLive(row: row)
                .frame(height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(row.title)
                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(detail)
                .font(KFont.ui(12.5, relativeTo: .caption))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
            Text(row.chatTitle.map { "From \($0)" } ?? "No chat linked")
                .font(KFont.ui(12.5, relativeTo: .caption))
                .foregroundStyle(row.chatTitle == nil ? Palette.inkFaint : Palette.goldText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 22)
    }

    private func newDesign() {
        Task {
            let made = await live.make()
            switch made.outcome {
            case .saved:
                Haptics.success()
                if let id = made.id { openID = id }
            case .busy:
                toast.say("A design is already being made.")
            case .failed(let words), .unconfirmed(let words):
                notice = words
            }
        }
    }
}

/// "Design with a model" while paired: the person's words go to a new design chat on the desktop.
struct MakeDesignStartLive: View {
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var format: DesignFormat = .website
    @State private var sending = false
    @State private var problem: String?

    private var blank: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// The words of an unresolved send. While there is one, only "Send again" and "Discard" are offered.
    private var lostWords: String? {
        if let turn = MakeDesignLive.shared.turns[MakeDesignLive.startKey], case .lost(let words) = turn.state { return words }
        return nil
    }

    var body: some View {
        FittedSheet(estimate: 580) {
            VStack(alignment: .leading, spacing: 18) {
                MakeSheetTitle(title: "Design with a model",
                               detail: "A model on your desktop builds the boards. That can use your plan or cost money.")
                MakeField(label: "Describe it", text: $prompt, prompt: "A booking page for a bike shop", limit: 2000, lines: 3...6)
                    .disabled(sending || lostWords != nil)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Format")
                    HStack(spacing: 6) {
                        ForEach(DesignFormat.allCases, id: \.self) { item in
                            Button {
                                Haptics.select()
                                withAnimation(Motion.snappy) { format = item }
                            } label: {
                                Chip(text: item.rawValue, filled: format == item).frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .disabled(sending || lostWords != nil)
                            .accessibilityAddTraits(format == item ? .isSelected : [])
                        }
                    }
                }
                if sending { MakeDesignLine(text: "Sending to your desktop...", working: true) }
                if let problem, lostWords == nil { HintLine(text: problem, color: Palette.danger) }
                if let lostWords {
                    HintLine(text: lostWords, color: Palette.danger)
                    GoldButton(title: "Send again") { sendAgain() }
                        .disabled(sending)
                        .opacity(sending ? 0.5 : 1)
                    QuietButton(title: "Discard") { MakeDesignLive.shared.discardTurn(MakeDesignLive.startKey) }
                        .disabled(sending)
                } else {
                    GoldButton(title: problem == nil ? "Start" : "Try again") { start() }
                        .disabled(blank || sending)
                        .opacity(blank || sending ? 0.5 : 1)
                }
                QuietButton(title: "Cancel") { dismiss() }
                    .disabled(sending)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .interactiveDismissDisabled(sending)
    }

    private func sendAgain() {
        guard !sending else { return }
        sending = true
        problem = nil
        Task {
            let outcome = await MakeDesignLive.shared.sendAgain(MakeDesignLive.startKey)
            sending = false
            switch outcome {
            case .saved:
                Haptics.success()
                dismiss()
            case .busy:
                problem = "This message is already on its way."
            case .failed(let text):
                problem = text
            case .unconfirmed:
                break
            }
        }
    }

    private func start() {
        guard !sending, !blank else { return }
        sending = true
        problem = nil
        let words = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = format.rawValue.lowercased()
        Task {
            let outcome = await MakeDesignLive.shared.startWithModel(prompt: words, format: kind)
            sending = false
            switch outcome {
            case .saved:
                Haptics.success()
                dismiss()
            case .busy:
                problem = "A design is already being made. Wait for it to finish."
            case .failed(let text), .unconfirmed(let text):
                problem = text
            }
        }
    }
}

// MARK: - A design, paired

nonisolated struct MakeDesignPick: Identifiable, Hashable, Sendable {
    let board: String
    let boardTitle: String
    let element: String
    let name: String
    var id: String { board + "/" + element }
    var label: String { "\(boardTitle) · \(name)" }
}

/// What a new comment or a text edit is about: an element of a board, or a point on it.
nonisolated struct MakeDesignTarget: Hashable, Sendable {
    var board: String
    var boardTitle: String
    var element: MakeDesignElement?
    var pointX: Double?
    var pointY: Double?

    var id: String { board + "/" + (element?.id ?? "point") }
    var label: String { element.map { "\(boardTitle) · \($0.name)" } ?? "\(boardTitle) · a point on the board" }
}

nonisolated enum MakeDesignSheet: Identifiable, Hashable, Sendable {
    case versions, comments, export, tokens, chat
    case compare(Int)
    case comment(MakeDesignTarget)
    case text(MakeDesignTarget)

    var id: String {
        switch self {
        case .versions: "versions"
        case .comments: "comments"
        case .export: "export"
        case .tokens: "tokens"
        case .chat: "chat"
        case .compare(let number): "compare-\(number)"
        case .comment(let target): "comment-\(target.id)"
        case .text(let target): "text-\(target.id)"
        }
    }
}

nonisolated enum MakeDesignConfirm: Identifiable, Hashable, Sendable {
    case deleteDesign
    case restore(Int)

    var id: String {
        switch self {
        case .deleteDesign: "delete"
        case .restore(let number): "restore-\(number)"
        }
    }
}

struct MakeDesignScreenLive: View {
    let designID: String
    let start: DesignStart

    @Environment(\.dismiss) private var dismiss
    @Environment(MakeToast.self) private var toast
    @Namespace private var modeSpace

    @State private var layout: DesignLayout = .boards
    @State private var mode: DesignMode = .pan
    @State private var picks: [MakeDesignPick] = []
    @State private var sheet: MakeDesignSheet?
    @State private var confirm: MakeDesignConfirm?
    @State private var previewing: Int?
    @State private var previewBoards: [MakeDesignBoard] = []
    @State private var focusIndex: Int?
    @State private var chosenChat: String?
    @State private var openID: String?
    @State private var notice: String?
    @State private var started = false

    private var live: MakeDesignLive { MakeDesignLive.shared }
    private var doc: MakeDesignDoc? { live.docs[designID] }
    private var working: Bool { live.busy.contains(designID) }
    private var turn: MakeDesignTurn? { live.turns[designID] }
    private var shownBoards: [MakeDesignBoard] { previewing != nil ? previewBoards : doc?.boards ?? [] }

    private var sendChat: MakeDesignChat? {
        guard let doc else { return nil }
        return doc.chats.first(where: { $0.id == chosenChat }) ?? doc.chats.last
    }

    private var draft: Binding<String> {
        let id = designID
        return Binding(get: { MakeDesignLive.shared.drafts[id] ?? "" }, set: { MakeDesignLive.shared.drafts[id] = $0 })
    }

    var body: some View {
        ZStack { mainArea }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .overlay { focusLayer }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .sheet(item: $sheet) { which in sheetView(which) }
            .sheet(item: $confirm) { which in confirmView(which) }
            .navigationDestination(item: $openID) { id in DesignScreen(designID: id) }
            .task(id: MakeDesignLive.connectionKey) {
                live.follow()
                await live.loadDoc(designID)
                begin()
            }
            .onAppear { live.resumeWatch(designID) }
            .onDisappear { live.pauseWatch(designID) }
            .kScreen()
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            MakeHeader(title: doc?.title ?? "Design", subtitle: subtitle, back: { dismiss() }) {
                if doc != nil {
                    GlassIconButton(symbol: "arrow.uturn.backward", label: "Undo my last edit") { undo() }
                        .disabled(working || previewing != nil)
                        .opacity(working || previewing != nil ? 0.45 : 1)
                    optionsMenu
                }
            }
            if let doc {
                controls(doc)
                if working { MakeDesignLine(text: "Saving to your desktop...", working: true).padding(.horizontal, 16) }
                if let notice {
                    MakeDesignLine(text: notice, action: "OK") { self.notice = nil }.padding(.horizontal, 16)
                }
                if let number = previewing { previewBanner(number) }
            }
        }
        .padding(.bottom, 6)
        .background { HeaderFade() }
    }

    private var subtitle: String? {
        guard let doc else { return nil }
        if let number = previewing { return "v\(doc.version) · previewing v\(number)" }
        return "v\(doc.version)"
    }

    private var optionsMenu: some View {
        Menu {
            Button { duplicate(version: nil) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { sheet = .export } label: { Label("Export", systemImage: "square.and.arrow.up") }
            Button { openTokens() } label: { Label("Tokens", systemImage: "paintpalette") }
            Button { sheet = .chat } label: { Label("Linked chat", systemImage: "bubble.left.and.bubble.right") }
            Divider()
            Button(role: .destructive) { confirm = .deleteDesign } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .kGlass(Circle(), interactive: true)
        .disabled(working)
        .accessibilityLabel("Design options")
    }

    private func controls(_ doc: MakeDesignDoc) -> some View {
        HStack(spacing: 8) {
            GlassSwitch(items: DesignLayout.allCases, selection: $layout) { $0.rawValue }
            Spacer(minLength: 0)
            GlassIconButton(symbol: "clock.arrow.circlepath", label: "Versions") { sheet = .versions }
            GlassIconButton(symbol: "text.bubble", label: "Comments, \(doc.openComments) open") { sheet = .comments }
                .overlay(alignment: .topTrailing) {
                    if doc.openComments > 0 {
                        Text("\(doc.openComments)")
                            .font(KFont.ui(11, .semibold, relativeTo: .caption2))
                            .foregroundStyle(Palette.onGold)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Palette.gold, in: Capsule())
                            .offset(x: 4, y: -4)
                            .allowsHitTesting(false)
                            .contentTransition(.numericText())
                    }
                }
            GlassIconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Focus") { openFocus(0) }
        }
        .padding(.horizontal, 16)
    }

    private func previewBanner(_ number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Previewing version \(number), read only.")
                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 8) {
                MakePillButton(title: "Restore this version", filled: true) { confirm = .restore(number) }
                    .disabled(working)
                MakePillButton(title: "Back to current") { endPreview() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: Boards

    @ViewBuilder
    private var mainArea: some View {
        if let doc {
            if layout == .boards {
                boardsList(doc)
            } else {
                MakeDesignCanvasLive(designID: designID, boards: shownBoards, stamp: doc.version, version: previewing,
                                     pins: { pins($0) }, onTap: { index, point in tapped(index, point) },
                                     onPin: { sheet = .comments }, onFocus: { openFocus($0) },
                                     onMove: { index, delta in move(index, by: delta) })
            }
        } else {
            VStack {
                switch live.docLoad[designID] ?? .idle {
                case .gone:
                    MakeDesignLine(text: "This design is not on your desktop any more.", action: "Back") { dismiss() }
                case .failed(let words):
                    MakeDesignLine(text: words, action: "Try again") { Task { await live.loadDoc(designID) } }
                default:
                    MakeDesignLine(text: "Reading this design from your desktop...", working: true)
                }
            }
            .padding(24)
        }
    }

    private func boardsList(_ doc: MakeDesignDoc) -> some View {
        let boards = shownBoards
        return ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(Array(boards.enumerated()), id: \.element.id) { index, board in
                    boardCard(index, board, total: boards.count, stamp: doc.version)
                }
                if boards.isEmpty { EmptyLine(text: "This design has no boards yet.") }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await live.loadDoc(designID) }
    }

    private func boardCard(_ index: Int, _ board: MakeDesignBoard, total: Int, stamp: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(index + 1). \(board.title)")
                        .font(KFont.ui(16, .semibold, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(board.sizeText)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Menu {
                    Button { openFocus(index) } label: { Label("Open in focus", systemImage: "arrow.up.left.and.arrow.down.right") }
                    Button { move(index, by: -1) } label: { Label("Move earlier", systemImage: "arrow.up") }
                        .disabled(index == 0 || working || previewing != nil)
                    Button { move(index, by: 1) } label: { Label("Move later", systemImage: "arrow.down") }
                        .disabled(index >= total - 1 || working || previewing != nil)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.inkDim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options for \(board.title)")
            }
            MakeDesignBoardFrame(designID: designID, board: board, stamp: stamp, version: previewing, maxHeight: 340,
                                 pins: pins(board), onTap: { point in tapped(index, point) }, onPin: { sheet = .comments })
            if mode != .pan && previewing == nil {
                MakeDesignElementRow(designID: designID, board: board, stamp: stamp, textOnly: mode == .text,
                                     picked: Set(picks.filter { $0.board == board.id }.map(\.element))) { act($0, on: board) }
            }
        }
        .padding(12)
        .kCard(radius: 22)
    }

    private func pins(_ board: MakeDesignBoard) -> [MakeDesignComment] {
        guard previewing == nil else { return [] }
        return (doc?.comments ?? []).filter { $0.board == board.id && $0.status != "resolved" }
    }

    @ViewBuilder
    private var focusLayer: some View {
        if let index = focusIndex, let doc, !shownBoards.isEmpty {
            let boards = shownBoards
            MakeDesignFocusLive(designID: designID, boards: boards, stamp: doc.version, version: previewing,
                                index: Binding(get: { min(index, boards.count - 1) }, set: { focusIndex = $0 }),
                                mode: previewing == nil ? mode : .pan,
                                picked: { board in Set(picks.filter { $0.board == board.id }.map(\.element)) },
                                pins: { pins($0) },
                                onTap: { at, point in tapped(at, point, inFocus: true) },
                                onElement: { element, board in act(element, on: board) },
                                onPin: { sheet = .comments },
                                close: { withAnimation(Motion.snappy) { focusIndex = nil } })
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    // MARK: Mode bar and composer

    @ViewBuilder
    private var bottomBar: some View {
        if let doc {
            VStack(spacing: 8) {
                modeBar
                composer(doc)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    private var modeBar: some View {
        HStack(spacing: 2) {
            ForEach(DesignMode.allCases, id: \.self) { item in
                let on = item == mode
                Button { setMode(item) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol).font(.system(size: 15, weight: .semibold))
                        Text(item.rawValue).font(KFont.ui(11.5, .medium, relativeTo: .caption2))
                    }
                    .foregroundStyle(on ? Palette.ink : Palette.inkDim)
                    .opacity(previewing != nil && item != .pan ? 0.45 : 1)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background {
                        if on { Capsule().fill(Palette.ink.opacity(0.15)).matchedGeometryEffect(id: "mode", in: modeSpace) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .kGlass(Capsule())
    }

    private func composer(_ doc: MakeDesignDoc) -> some View {
        let open = turn?.blocksSend == true
        let typed = !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canSend = sendChat != nil && !open && previewing == nil && (typed || !picks.isEmpty)
        return VStack(alignment: .leading, spacing: 6) {
            if !picks.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(picks) { pick in
                            HStack(spacing: 0) {
                                Text(pick.label)
                                    .font(KFont.ui(13, .medium, relativeTo: .footnote))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Button {
                                    Haptics.tap()
                                    withAnimation(Motion.snappy) { picks.removeAll { $0.id == pick.id } }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Palette.inkDim)
                                        .frame(width: 40, height: 40)
                                        .contentShape(Rectangle())
                                }
                                .disabled(open)
                                .accessibilityLabel("Remove \(pick.name)")
                            }
                            .padding(.leading, 12)
                            .background(Palette.ink.opacity(0.1), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            statusLine
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Describe the change", text: draft, axis: .vertical)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1...5)
                    .padding(.vertical, 11)
                    .disabled(turn?.blocksSend == true)
                Button { send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: 38, height: 38)
                        .background(Palette.gold, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressStyle())
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
                .accessibilityLabel("Send to the model")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .kGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            switch turn?.state {
            case .sending:
                PulsingDot(color: Palette.working)
                Text("Sending to your desktop...")
            case .working:
                PulsingDot(color: Palette.working)
                Text("Your desktop is working. A model is changing this design.")
            case .waiting:
                PulsingDot(color: Palette.working)
                Text("The model is waiting for your OK. Answer it in the chat.")
            case .done:
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.success)
                Text("Done")
            case .failed(let words):
                Text(words).foregroundStyle(Palette.danger)
                Button("OK") { live.clearTurn(designID) }
                    .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
            case .lost(let words):
                Text(words).foregroundStyle(Palette.danger)
                Button("Send again") { Task { await finishSend(live.sendAgain(designID)) } }
                    .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
                Button("Discard") { live.discardTurn(designID) }
                    .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
            case nil:
                if let chat = sendChat {
                    Text("Sends to \(chat.title). A model on your desktop does the work.").lineLimit(2)
                } else {
                    Text("Link a chat to ask a model for changes.").lineLimit(1)
                    Button("Link a chat") { sheet = .chat }
                        .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.goldText)
                        .frame(minHeight: 44)
                }
            }
            Spacer(minLength: 4)
            if !picks.isEmpty {
                Text("\(picks.count)/10").contentTransition(.numericText())
            }
        }
        .font(KFont.ui(13, relativeTo: .footnote))
        .foregroundStyle(Palette.inkFaint)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ which: MakeDesignSheet) -> some View {
        switch which {
        case .versions:
            MakeDesignVersionsLive(designID: designID, previewing: previewing,
                                   onPreview: { preview($0) },
                                   onCompare: { sheet = .compare($0) },
                                   onRestored: { restored($0) },
                                   onDuplicate: { number in
                                       sheet = nil
                                       duplicate(version: number)
                                   })
        case .compare(let number):
            MakeDesignCompareLive(designID: designID, number: number)
        case .comments:
            MakeDesignCommentsLive(designID: designID, chat: sendChat, onLink: { sheet = .chat }, onSent: { sheet = nil })
        case .comment(let target):
            MakeDesignCommentLive(designID: designID, target: target)
        case .text(let target):
            MakeDesignTextLive(designID: designID, target: target)
        case .export:
            MakeDesignExportLive(designID: designID, chat: sendChat)
        case .tokens:
            MakeDesignTokensLive(designID: designID)
        case .chat:
            MakeDesignChatLive(designID: designID, chosen: sendChat?.id, onChoose: { chosenChat = $0 })
        }
    }

    @ViewBuilder
    private func confirmView(_ which: MakeDesignConfirm) -> some View {
        switch which {
        case .deleteDesign:
            ConfirmSheet(title: "Delete this design?",
                         detail: "\"\(doc?.title ?? "This design")\" is deleted from your desktop, with its boards, versions and comments. This cannot be undone.",
                         confirm: "Delete") { deleteDesign() }
        case .restore(let number):
            ConfirmSheet(title: "Restore version \(number)?",
                         detail: "Every board goes back to how it was in version \(number). What you see now stays in Versions as version \(doc?.version ?? 0).",
                         confirm: "Restore", danger: false) { restoreVersion(number) }
        }
    }

    // MARK: Actions

    private func begin() {
        guard !started, doc != nil else { return }
        started = true
        switch start {
        case .boards, .comment: break
        case .canvas: layout = .canvas
        case .versions: sheet = .versions
        case .compare: sheet = .versions
        case .focus: focusIndex = 0
        }
    }

    /// Say how a change ended: a short word when it worked, a line that stays when it did not.
    private func tell(_ outcome: MakeDesignOutcome, done: String) {
        switch outcome {
        case .saved:
            Haptics.success()
            toast.say(done)
        case .busy:
            toast.say("Wait for the last change to finish.")
        case .failed(let words), .unconfirmed(let words):
            notice = words
        }
    }

    private func reading() -> Bool {
        if previewing != nil {
            toast.say("Return to the current version to edit.")
            return true
        }
        return false
    }

    private func setMode(_ item: DesignMode) {
        if item != .pan && reading() { return }
        guard item != mode else { return }
        Haptics.select()
        withAnimation(Motion.snappy) { mode = item }
        switch item {
        case .pan: break
        case .select: toast.say("Select: pick elements under a board to add them to your message.")
        case .comment: toast.say("Comment: tap a board, or pick an element under it.")
        case .text: toast.say("Text: pick a text element under a board to edit it.")
        }
    }

    private func openFocus(_ index: Int) {
        guard !shownBoards.isEmpty else { return }
        Haptics.tap()
        withAnimation(Motion.snappy) { focusIndex = min(max(0, index), shownBoards.count - 1) }
    }

    private func tapped(_ index: Int, _ point: CGPoint, inFocus: Bool = false) {
        let boards = shownBoards
        guard boards.indices.contains(index) else { return }
        switch mode {
        case .pan:
            if !inFocus { openFocus(index) }
        case .comment:
            guard !reading() else { return }
            Haptics.tap()
            sheet = .comment(MakeDesignTarget(board: boards[index].id, boardTitle: boards[index].title, element: nil,
                                              pointX: Double(point.x), pointY: Double(point.y)))
        case .select, .text:
            toast.say("Pick an element from the row under the board.")
        }
    }

    private func act(_ element: MakeDesignElement, on board: MakeDesignBoard) {
        guard !reading() else { return }
        switch mode {
        case .pan:
            break
        case .select:
            let pick = MakeDesignPick(board: board.id, boardTitle: board.title, element: element.id, name: element.name)
            if picks.contains(where: { $0.id == pick.id }) {
                Haptics.tap()
                withAnimation(Motion.snappy) { picks.removeAll { $0.id == pick.id } }
            } else if picks.count >= 10 {
                toast.say("At most 10 selections or comments per message")
            } else if turn?.blocksSend == true {
                toast.say("Wait for the model to finish first.")
            } else {
                Haptics.select()
                withAnimation(Motion.snappy) { picks.append(pick) }
            }
        case .comment:
            Haptics.tap()
            sheet = .comment(MakeDesignTarget(board: board.id, boardTitle: board.title, element: element))
        case .text:
            guard element.isText else {
                toast.say("Pick an element that holds only text.")
                return
            }
            Haptics.tap()
            sheet = .text(MakeDesignTarget(board: board.id, boardTitle: board.title, element: element))
        }
    }

    private func send() {
        guard !reading() else { return }
        guard let chat = sendChat else {
            sheet = .chat
            return
        }
        let text = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !picks.isEmpty else { return }
        let references = picks.map { pick in
            MakeDesignReference(designID: designID, board: pick.board, elementIDs: [pick.element], pointX: nil, pointY: nil,
                                comment: "", commentID: nil, label: pick.label)
        }
        Haptics.tap()
        Task { await finishSend(live.send(designID, sessionID: chat.id, message: text, references: references)) }
    }

    /// The person's words and picks stay in the composer until the desktop has taken the message.
    private func finishSend(_ outcome: MakeDesignOutcome) {
        switch outcome {
        case .saved:
            draft.wrappedValue = ""
            withAnimation(Motion.snappy) { picks.removeAll() }
            Haptics.success()
        case .busy:
            toast.say("The model is still working on the last message.")
        case .failed, .unconfirmed:
            break
        }
    }

    private func move(_ index: Int, by delta: Int) {
        guard !reading(), let doc, doc.boards.indices.contains(index), doc.boards.indices.contains(index + delta) else { return }
        let board = doc.boards[index].id
        Task { tell(await live.move(designID, board: board, to: index + delta), done: "Board moved") }
    }

    private func undo() {
        guard !reading() else { return }
        Task { tell(await live.undo(designID), done: "Undone") }
    }

    private func preview(_ number: Int) {
        sheet = nil
        guard let doc, number != doc.version else {
            endPreview()
            return
        }
        Task {
            guard let boards = await live.snapshotBoards(designID, number: number) else {
                notice = "Version \(number) could not be read from your desktop."
                return
            }
            withAnimation(Motion.snappy) {
                previewBoards = boards
                previewing = number
                mode = .pan
                picks.removeAll()
            }
        }
    }

    private func endPreview() {
        withAnimation(Motion.snappy) {
            previewing = nil
            previewBoards = []
        }
    }

    private func restoreVersion(_ number: Int) {
        Task {
            let outcome = await live.restore(designID, number: number)
            if outcome == .saved { endPreview() }
            tell(outcome, done: "Restored version \(number) as a new version")
        }
    }

    private func restored(_ number: Int) {
        sheet = nil
        endPreview()
        Haptics.success()
        toast.say("Restored version \(number) as a new version")
    }

    private func duplicate(version: Int?) {
        Task {
            let made = await live.make(copyOf: designID, version: version)
            switch made.outcome {
            case .saved:
                Haptics.success()
                toast.say("Copy made")
                if let id = made.id { openID = id }
            case .busy:
                toast.say("A design is already being made.")
            case .failed(let words), .unconfirmed(let words):
                notice = words
            }
        }
    }

    private func deleteDesign() {
        Task {
            let outcome = await live.delete(designID)
            if outcome == .saved {
                Haptics.thud()
                toast.say("Design deleted")
                dismiss()
            } else {
                tell(outcome, done: "")
            }
        }
    }

    private func openTokens() {
        guard !reading() else { return }
        sheet = .tokens
    }
}

/// The elements of one board as chips, read from the desktop's outline of it.
struct MakeDesignElementRow: View {
    let designID: String
    let board: MakeDesignBoard
    let stamp: Int
    let textOnly: Bool
    let picked: Set<String>
    let onPick: (MakeDesignElement) -> Void

    private var key: String { designID + "/" + board.id }

    var body: some View {
        let live = MakeDesignLive.shared
        let all = live.elements[key] ?? []
        let shown = textOnly ? all.filter(\.isText) : all
        Group {
            switch live.elementsLoad[key] ?? .idle {
            case .failed(let words):
                HintLine(text: words)
            case .loaded where shown.isEmpty:
                HintLine(text: textOnly ? "This board has no element that holds only text." : "This board has no elements to pick.")
            case .loaded:
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(shown) { element in
                            let on = picked.contains(element.id)
                            Button { onPick(element) } label: {
                                Chip(text: element.name, filled: on).frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: 44)
            default:
                HintLine(text: "Reading this board's elements...")
            }
        }
        .task(id: "\(key)/\(stamp)/\(MakeDesignLive.connectionKey)") { await live.loadElements(designID, board: board.id) }
    }
}

// MARK: - Canvas and focus, paired

/// One row of the canvas: the boards of one format.
nonisolated struct MakeDesignCanvasRow: Identifiable, Hashable, Sendable {
    let id: String
    var indices: [Int]
}

/// The desktop's boards in rows by format. Pinch to zoom, drag to pan, Fit, and plus or minus.
struct MakeDesignCanvasLive: View {
    let designID: String
    let boards: [MakeDesignBoard]
    let stamp: Int
    let version: Int?
    let pins: (MakeDesignBoard) -> [MakeDesignComment]
    let onTap: (Int, CGPoint) -> Void
    let onPin: () -> Void
    let onFocus: (Int) -> Void
    let onMove: (Int, Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var contentSize: CGSize = .zero
    @State private var viewSize: CGSize = .zero
    @State private var fitted = false
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    /// Boards sit on the canvas at a fifth of their real width when the zoom is 1.
    private let unit: CGFloat = 0.2
    /// A canvas of web pages is heavy: beyond this many boards the rest stay in the Boards list.
    private let most = 24

    private var scale: CGFloat { clamp(zoom * pinch) }

    private var rows: [MakeDesignCanvasRow] {
        var out: [MakeDesignCanvasRow] = []
        for (index, board) in boards.prefix(most).enumerated() {
            if let row = out.firstIndex(where: { $0.id == board.section }) {
                out[row].indices.append(index)
            } else {
                out.append(MakeDesignCanvasRow(id: board.section, indices: [index]))
            }
        }
        return out
    }

    var body: some View {
        ZStack { layer }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .contentShape(Rectangle())
            .clipped()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                viewSize = size
                fitOnce()
            }
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .overlay(alignment: .top) { controls }
            .overlay(alignment: .bottom) {
                if boards.count > most {
                    MakeDesignLine(text: "The canvas shows the first \(most) boards. The rest are in Boards.").padding(12)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Design canvas")
    }

    private var layer: some View {
        VStack(alignment: .leading, spacing: 36) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 28) {
                    ForEach(row.indices, id: \.self) { index in tile(index) }
                }
            }
        }
        .padding(24)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            contentSize = size
            fitOnce()
        }
        .scaleEffect(scale)
        .offset(x: pan.width + drag.width, y: pan.height + drag.height)
    }

    private func tile(_ index: Int) -> some View {
        let board = boards[index]
        let width = max(60, CGFloat(board.width) * unit)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(index + 1). \(board.title)")
                .font(KFont.ui(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .lineLimit(1)
            Text(board.sizeText)
                .font(KFont.ui(10.5, relativeTo: .caption2))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
            MakeDesignBoardFrame(designID: designID, board: board, stamp: stamp, version: version, pins: pins(board),
                                 onTap: { point in onTap(index, point) }, onPin: onPin)
                .frame(width: width)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                .contextMenu {
                    Button { onFocus(index) } label: { Label("Open in focus", systemImage: "arrow.up.left.and.arrow.down.right") }
                    Button { onMove(index, -1) } label: { Label("Move earlier", systemImage: "arrow.left") }
                        .disabled(index == 0)
                    Button { onMove(index, 1) } label: { Label("Move later", systemImage: "arrow.right") }
                        .disabled(index >= boards.count - 1)
                }
        }
        .frame(width: max(width, 120), alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button { setZoom(zoom / 1.25) } label: {
                Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Zoom out")
            Text("\(Int((scale * unit * 100).rounded()))%")
                .monospacedDigit()
                .frame(minWidth: 54)
                .contentTransition(.numericText())
            Button { setZoom(zoom * 1.25) } label: {
                Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Zoom in")
            Button { fit(animated: true) } label: {
                Text("Fit").frame(minWidth: 52, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Fit all boards")
        }
        .font(KFont.ui(14.5, .semibold, relativeTo: .subheadline))
        .foregroundStyle(Palette.ink)
        .buttonStyle(PressStyle())
        .padding(.horizontal, 4)
        .kGlass(Capsule())
        .padding(.top, 8)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                pan.width += value.translation.width
                pan.height += value.translation.height
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in zoom = clamp(zoom * value.magnification) }
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(20, max(0.2, value)) }

    private func setZoom(_ value: CGFloat) {
        Haptics.tap()
        if reduceMotion { zoom = clamp(value) } else { withAnimation(Motion.snappy) { zoom = clamp(value) } }
    }

    private func fitOnce() {
        guard !fitted, contentSize.width > 0, viewSize.width > 0 else { return }
        fitted = true
        fit(animated: false)
    }

    private func fit(animated: Bool) {
        guard contentSize.width > 0, contentSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return }
        let byWidth = (viewSize.width - 24) / contentSize.width
        let byHeight = (viewSize.height - 80) / contentSize.height
        let target = clamp(min(byWidth, byHeight))
        if animated && !reduceMotion {
            withAnimation(Motion.sheet) {
                zoom = target
                pan = .zero
            }
        } else {
            zoom = target
            pan = .zero
        }
    }
}

/// One board large, at its own width, scrolling when it is tall: "n / total · title", Previous, Next, Close.
struct MakeDesignFocusLive: View {
    let designID: String
    let boards: [MakeDesignBoard]
    let stamp: Int
    let version: Int?
    @Binding var index: Int
    let mode: DesignMode
    let picked: (MakeDesignBoard) -> Set<String>
    let pins: (MakeDesignBoard) -> [MakeDesignComment]
    let onTap: (Int, CGPoint) -> Void
    let onElement: (MakeDesignElement, MakeDesignBoard) -> Void
    let onPin: () -> Void
    let close: () -> Void

    private var board: MakeDesignBoard { boards[min(max(0, index), boards.count - 1)] }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                GlassIconButton(symbol: "xmark", label: "Close", action: close)
                Text("\(index + 1) / \(boards.count) · \(board.title)")
                    .font(KFont.ui(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            TabView(selection: $index) {
                ForEach(Array(boards.enumerated()), id: \.element.id) { offset, item in
                    ScrollView {
                        MakeDesignBoardFrame(designID: designID, board: item, stamp: stamp, version: version, pins: pins(item),
                                             onTap: { point in onTap(offset, point) }, onPin: onPin)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                    .scrollIndicators(.hidden)
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if mode != .pan {
                MakeDesignElementRow(designID: designID, board: board, stamp: stamp, textOnly: mode == .text,
                                     picked: picked(board)) { onElement($0, board) }
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                MakePillButton(title: "Previous", symbol: "chevron.left", expand: true) { step(-1) }
                    .disabled(index <= 0)
                    .opacity(index <= 0 ? 0.45 : 1)
                MakePillButton(title: "Next", symbol: "chevron.right", expand: true) { step(1) }
                    .disabled(index >= boards.count - 1)
                    .opacity(index >= boards.count - 1 ? 0.45 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background { Palette.ground.ignoresSafeArea(edges: .top) }
    }

    private func step(_ delta: Int) {
        withAnimation(Motion.snappy) { index = max(0, min(boards.count - 1, index + delta)) }
    }
}

// MARK: - Sheets, paired

/// Pin a comment to an element or to a point. The words stay in the box until the desktop has them.
struct MakeDesignCommentLive: View {
    let designID: String
    let target: MakeDesignTarget
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @State private var problem: String?

    private var blank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        FittedSheet(estimate: 460) {
            VStack(spacing: 16) {
                MakeSheetTitle(title: "What should change?", detail: target.label)
                MakeField(label: "Comment", text: $text, prompt: "Say what to change", limit: 4000, lines: 3...8)
                    .disabled(sending)
                if sending { MakeDesignLine(text: "Pinning on your desktop...", working: true) }
                if let problem { HintLine(text: problem, color: Palette.danger) }
                GoldButton(title: "Pin comment") { pin() }
                    .disabled(blank || sending)
                    .opacity(blank || sending ? 0.5 : 1)
                QuietButton(title: "Cancel") { dismiss() }
                    .disabled(sending)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .interactiveDismissDisabled(sending)
    }

    private func pin() {
        guard !sending, !blank else { return }
        sending = true
        problem = nil
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var at: CGPoint?
        if target.element == nil, let x = target.pointX, let y = target.pointY { at = CGPoint(x: x, y: y) }
        let point = at
        Task {
            let outcome = await MakeDesignLive.shared.addComment(designID, board: target.board,
                                                                 elementIDs: target.element.map { [$0.id] } ?? [],
                                                                 point: point, text: words)
            sending = false
            switch outcome {
            case .saved:
                Haptics.success()
                dismiss()
            case .busy:
                problem = "Another change to this design is still on its way. Try again in a moment."
            case .failed(let words), .unconfirmed(let words):
                problem = words
            }
        }
    }
}

/// Edit one element's text. The form is filled once from the desktop and only sends when the text changed;
/// reading the design again under it never touches what the person is typing.
struct MakeDesignTextLive: View {
    let designID: String
    let target: MakeDesignTarget
    @Environment(\.dismiss) private var dismiss
    @State private var filled: String?
    @State private var text = ""
    @State private var unreadable = false
    @State private var sending = false
    @State private var problem: String?

    private var changed: Bool {
        guard let filled else { return false }
        return text != filled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        FittedSheet(estimate: 420) {
            VStack(spacing: 16) {
                MakeSheetTitle(title: "Edit text", detail: target.label)
                if filled != nil {
                    MakeField(label: "Text", text: $text, limit: 20000, lines: 2...8)
                        .disabled(sending)
                } else if unreadable {
                    MakeDesignLine(text: "This text could not be read from your desktop.", action: "Try again") { Task { await fill() } }
                } else {
                    MakeDesignLine(text: "Reading the text from your desktop...", working: true)
                }
                if sending { MakeDesignLine(text: "Saving to your desktop...", working: true) }
                if let problem { HintLine(text: problem, color: Palette.danger) }
                GoldButton(title: "Save") { save() }
                    .disabled(!changed || sending)
                    .opacity(!changed || sending ? 0.5 : 1)
                QuietButton(title: "Cancel") { dismiss() }
                    .disabled(sending)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .interactiveDismissDisabled(sending)
        .task { await fill() }
    }

    private func fill() async {
        guard filled == nil, let element = target.element else { return }
        unreadable = false
        guard let read = await MakeDesignLive.shared.elementText(designID, board: target.board, element: element.id) else {
            unreadable = true
            return
        }
        guard filled == nil else { return }
        filled = read
        text = read
    }

    private func save() {
        guard !sending, changed, let element = target.element, let before = filled else { return }
        sending = true
        problem = nil
        let sent = text
        Task {
            // The desktop replaces everything inside the element, so look again just before sending.
            let now = await MakeDesignLive.shared.elementText(designID, board: target.board, element: element.id)
            guard now == before else {
                sending = false
                if let now {
                    // The next Save is against what the desktop has now, which the person has just been shown.
                    filled = now
                    let theirs = now.count > 200 ? String(now.prefix(200)) + "..." : now
                    problem = "This text changed on your desktop, so nothing was saved. Your words are kept here. "
                        + "Your desktop now has: \"" + theirs + "\". Save again to replace it."
                } else {
                    problem = "This text could not be checked on your desktop, so nothing was saved. Your words are kept here. Try again."
                }
                return
            }
            let outcome = await MakeDesignLive.shared.setText(designID, board: target.board, element: element.id, text: sent)
            sending = false
            switch outcome {
            case .saved:
                Haptics.success()
                dismiss()
            case .busy:
                problem = "Another change to this design is still on its way. Try again in a moment."
            case .failed(let words), .unconfirmed(let words):
                problem = words
            }
        }
    }
}

/// The look's values. Only a value the person touched since the form opened is an edit; every other row
/// follows the desktop, so a read under the open form never makes an untouched value look edited.
struct MakeDesignTokensLive: View {
    let designID: String
    @Environment(\.dismiss) private var dismiss
    /// The desktop's values when the form was filled.
    @State private var filled: [String: String]?
    /// Only the values the person changed since then.
    @State private var edits: [String: String] = [:]
    @State private var sending = false
    @State private var problem: String?
    @State private var clearing = false

    private var live: MakeDesignLive { MakeDesignLive.shared }
    private var doc: MakeDesignDoc? { live.docs[designID] }
    private var unsafe: Bool { edits.values.contains { !MakeDesignWire.isSafeValue($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Tokens", detail: "The values of the \(doc?.lookName ?? "Kairos") look. Saved changes show on every board.")
                if let doc {
                    LazyVStack(spacing: 0) {
                        ForEach(doc.tokens) { token in row(token, changedHere: doc.overridden.contains(token.id)) }
                    }
                    .kCard(radius: 20)
                } else {
                    MakeDesignLine(text: "Reading this design from your desktop...", working: true)
                }
                if sending { MakeDesignLine(text: "Saving to your desktop...", working: true) }
                if let problem { HintLine(text: problem, color: Palette.danger) }
                if unsafe { HintLine(text: "A value cannot be empty or hold ; { } < > or a link.", color: Palette.danger) }
                GoldButton(title: edits.count == 1 ? "Save 1 change to this design" : "Save \(edits.count) changes to this design") { save() }
                    .disabled(edits.isEmpty || unsafe || sending)
                    .opacity(edits.isEmpty || unsafe || sending ? 0.5 : 1)
                HStack(spacing: 8) {
                    QuietButton(title: "Discard") { withAnimation(Motion.snappy) { edits = [:] } }
                        .disabled(edits.isEmpty || sending)
                    QuietButton(title: "Use the look's values") { clearing = true }
                        .disabled(doc?.overridden.isEmpty != false || sending)
                        .opacity(doc?.overridden.isEmpty != false ? 0.45 : 1)
                }
                HintLine(text: "To save these values to the design system itself, use Kairos on your desktop.")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .kSheet([.medium, .large])
        .interactiveDismissDisabled(sending)
        .sheet(isPresented: $clearing) {
            ConfirmSheet(title: "Use the look's values?",
                         detail: "Every value this design changed goes back to the \(doc?.lookName ?? "Kairos") look, as a new version. The version before stays in Versions.",
                         confirm: "Use the look's values", danger: false) { clear() }
        }
        .onAppear { fill() }
        .onChange(of: doc?.version) { fill() }
    }

    /// Filled once. A later read of the design leaves `filled` and `edits` alone.
    private func fill() {
        guard filled == nil, let doc else { return }
        filled = Dictionary(doc.tokens.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// Back at the value the desktop holds now (a colour in other letter case is the same colour): no edit.
    /// Any other value is an edit, an older value the form was filled with included.
    private func edit(_ name: String, _ value: String) {
        let held = doc?.tokens.first(where: { $0.id == name })?.value
        if value.lowercased() == held?.lowercased() { edits[name] = nil } else { edits[name] = value }
    }

    private func row(_ token: MakeDesignToken, changedHere: Bool) -> some View {
        let shown = edits[token.id] ?? token.value
        let edited = edits[token.id] != nil
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(token.name)
                    .font(KFont.ui(15, edited ? .semibold : .regular, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if edited {
                    Text("Edited, not saved").font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.goldText)
                } else if changedHere {
                    Text("Changed in this design").font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                }
            }
            Spacer(minLength: 8)
            if let hex = MakeDesignWire.hex(shown) {
                ColorPicker("Colour of \(token.name)", selection: Binding(
                    get: { Color(hex: hex) },
                    set: { picked in
                        let value = MakeDesignWire.hexText(MakeDesignTokensLive.number(picked))
                        if value != MakeDesignWire.hexText(hex) { edit(token.id, value) }
                    }), supportsOpacity: false)
                    .labelsHidden()
                    .disabled(sending)
                Text(shown.lowercased())
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
            } else {
                TextField(token.standard ?? "", text: Binding(get: { shown }, set: { edit(token.id, $0) }))
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(maxWidth: 170)
                    .disabled(sending)
                    .accessibilityLabel(token.name)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 14) }
    }

    private static func number(_ color: Color) -> UInt32 {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func part(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
        return part(red) << 16 | part(green) << 8 | part(blue)
    }

    private func save() {
        guard !sending, !edits.isEmpty, !unsafe else { return }
        sending = true
        problem = nil
        let sent = edits
        Task {
            let outcome = await live.setTokens(designID, set: sent)
            sending = false
            finish(outcome, sent: sent)
        }
    }

    private func clear() {
        guard !sending else { return }
        sending = true
        problem = nil
        Task {
            let outcome = await live.setTokens(designID, set: [:], clear: true)
            sending = false
            finish(outcome, sent: [:])
        }
    }

    /// The design was read again after the write. An edit the desktop now holds is no longer an edit; one it
    /// does not hold stays, so a second save carries only those.
    private func finish(_ outcome: MakeDesignOutcome, sent: [String: String]) {
        let now = Dictionary((doc?.tokens ?? []).map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        switch outcome {
        case .saved:
            Haptics.success()
            for (name, value) in sent where edits[name] == value { edits[name] = nil }
            filled = now
            if edits.isEmpty { dismiss() }
        case .busy:
            problem = "Another change to this design is still on its way. Try again in a moment."
        case .failed(let words):
            problem = words
        case .unconfirmed(let words):
            for (name, value) in sent where now[name] == value && edits[name] == value { edits[name] = nil }
            problem = words
        }
    }
}

/// Which chat the composer sends to, and linking another one. A link is made on the desktop at once.
struct MakeDesignChatLive: View {
    let designID: String
    let chosen: String?
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var others: [MakeDesignChat]?
    @State private var othersFailed = false
    @State private var sending = false
    @State private var problem: String?

    private var live: MakeDesignLive { MakeDesignLive.shared }
    private var doc: MakeDesignDoc? { live.docs[designID] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Chat that changes this design", detail: "Your selections, comments and messages go to this chat.")
                if let doc, !doc.chats.isEmpty {
                    SectionLabel(text: "Linked")
                    VStack(spacing: 0) {
                        ForEach(doc.chats) { chat in
                            chatRow(chat, symbol: "bubble.left", ticked: chat.id == (chosen ?? doc.chats.last?.id)) {
                                onChoose(chat.id)
                                dismiss()
                            }
                        }
                    }
                    .kCard(radius: 20)
                }
                if sending { MakeDesignLine(text: "Linking on your desktop...", working: true) }
                if let problem { HintLine(text: problem, color: Palette.danger) }
                MakePillButton(title: "Start a new design chat", symbol: "plus") { startChat() }
                    .disabled(sending)
                    .opacity(sending ? 0.5 : 1)
                SectionLabel(text: "Link another chat")
                if let others {
                    if others.isEmpty { EmptyLine(text: "No other chats to link.") }
                    VStack(spacing: 0) {
                        ForEach(others) { chat in
                            chatRow(chat, symbol: "link", ticked: false) { link(chat) }
                        }
                    }
                    .kCard(radius: 20)
                } else if othersFailed {
                    MakeDesignLine(text: "Your chats could not be read.", action: "Try again") { Task { await readOthers() } }
                } else {
                    MakeDesignLine(text: "Reading your chats...", working: true)
                }
                HintLine(text: "A linked chat stays linked: its model can change this design.")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .interactiveDismissDisabled(sending)
        .task { await readOthers() }
    }

    private func chatRow(_ chat: MakeDesignChat, symbol: String, ticked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 26)
                Text(chat.title).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: 0)
                if ticked {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 54) }
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .disabled(sending)
        .accessibilityAddTraits(ticked ? .isSelected : [])
    }

    private func readOthers() async {
        othersFailed = false
        if let read = await live.chatsToLink(designID) { others = read } else { othersFailed = true }
    }

    private func link(_ chat: MakeDesignChat) {
        run({ await live.link(designID, sessionID: chat.id) }, choose: chat.id)
    }

    private func startChat() {
        let title = doc?.title ?? "Design"
        run({ await live.startChat(designID, title: title) }, choose: nil)
    }

    private func run(_ change: @escaping () async -> MakeDesignOutcome, choose: String?) {
        guard !sending else { return }
        sending = true
        problem = nil
        Task {
            let outcome = await change()
            sending = false
            switch outcome {
            case .saved:
                Haptics.success()
                if let id = choose ?? doc?.chats.last?.id { onChoose(id) }
                dismiss()
            case .busy:
                problem = "Another change to this design is still on its way. Try again in a moment."
            case .failed(let words), .unconfirmed(let words):
                problem = words
                await readOthers()
            }
        }
    }
}

/// The desktop's versions, newest first: preview, compare, restore (asked first), name, duplicate.
struct MakeDesignVersionsLive: View {
    let designID: String
    let previewing: Int?
    let onPreview: (Int) -> Void
    let onCompare: (Int) -> Void
    let onRestored: (Int) -> Void
    let onDuplicate: (Int) -> Void
    @State private var renaming: Int?
    @State private var nameDraft = ""
    @State private var restoring: MakeDesignConfirm?
    @State private var problem: String?

    private var live: MakeDesignLive { MakeDesignLive.shared }
    private var working: Bool { live.busy.contains(designID) }

    var body: some View {
        let current = live.docs[designID]?.version ?? 0
        let rows = live.versions[designID] ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MakeSheetTitle(title: "Versions", detail: "Version \(current) is current")
                if working { MakeDesignLine(text: "Saving to your desktop...", working: true) }
                if let problem { MakeDesignLine(text: problem, action: "OK") { self.problem = nil } }
                if rows.isEmpty {
                    switch live.versionsLoad[designID] ?? .idle {
                    case .failed(let words):
                        MakeDesignLine(text: words, action: "Try again") { Task { await live.loadVersions(designID) } }
                    case .loaded:
                        EmptyLine(text: "No versions yet.")
                    default:
                        MakeDesignLine(text: "Reading the versions from your desktop...", working: true)
                    }
                }
                LazyVStack(spacing: 10) {
                    ForEach(rows) { version in row(version, current: current) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .interactiveDismissDisabled(working)
        .task(id: "\(MakeDesignLive.connectionKey)/\(current)") { await live.loadVersions(designID) }
        .sheet(item: $restoring) { which in
            if case .restore(let number) = which {
                ConfirmSheet(title: "Restore version \(number)?",
                             detail: "Every board goes back to how it was in version \(number). What you see now stays in Versions as version \(current).",
                             confirm: "Restore", danger: false) { restore(number) }
            }
        }
        .alert("Name this version", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                if let number = renaming { rename(number) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("A named version is kept when old versions are cleared.")
        }
    }

    private func row(_ version: MakeDesignVersionRow, current: Int) -> some View {
        let isCurrent = version.id == current
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(version.name ?? "Version \(version.id)")
                    .font(KFont.ui(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if isCurrent { StatePill(text: "Current", tone: .ok) }
                if previewing == version.id { StatePill(text: "Previewing", tone: .working) }
                Spacer(minLength: 4)
                if let date = version.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(KFont.ui(12.5, relativeTo: .caption))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
            }
            Text((version.name == nil ? "" : "v\(version.id) · ") + "\(version.author): \(version.summary)")
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    MakePillButton(title: "Preview") { onPreview(version.id) }
                    MakePillButton(title: "Compare") { onCompare(version.id) }
                        .disabled(isCurrent)
                        .opacity(isCurrent ? 0.4 : 1)
                    MakePillButton(title: "Restore") { restoring = .restore(version.id) }
                        .disabled(isCurrent || working)
                        .opacity(isCurrent || working ? 0.4 : 1)
                    MakePillButton(title: version.name == nil ? "Name" : "Rename") {
                        nameDraft = version.name ?? ""
                        renaming = version.id
                    }
                    .disabled(working)
                    MakePillButton(title: "Duplicate as new design") { onDuplicate(version.id) }
                        .disabled(working)
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .kCard(radius: 20, raised: isCurrent)
    }

    private func restore(_ number: Int) {
        Task {
            switch await live.restore(designID, number: number) {
            case .saved: onRestored(number)
            case .busy: problem = "Another change to this design is still on its way. Try again in a moment."
            case .failed(let words), .unconfirmed(let words): problem = words
            }
        }
    }

    /// Only the name is sent, and only when it is not the one the desktop already has.
    private func rename(_ number: Int) {
        let clean = String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let name: String? = clean.isEmpty ? nil : clean
        guard name != live.versions[designID]?.first(where: { $0.id == number })?.name else { return }
        Task {
            switch await live.nameVersion(designID, number: number, name: name) {
            case .saved: Haptics.success()
            case .busy: problem = "Another change to this design is still on its way. Try again in a moment."
            case .failed(let words), .unconfirmed(let words): problem = words
            }
        }
    }
}

/// One board at a past version above, the same board now below, both drawn by the desktop.
struct MakeDesignCompareLive: View {
    let designID: String
    let number: Int
    @State private var picked: String?

    var body: some View {
        let doc = MakeDesignLive.shared.docs[designID]
        let boards = doc?.boards ?? []
        let board = boards.first(where: { $0.id == picked }) ?? boards.first
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Compare v\(number) with current", detail: "Version \(number) above, the current design below.")
                if let board, let doc {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(boards) { item in
                                Button {
                                    Haptics.select()
                                    withAnimation(Motion.snappy) { picked = item.id }
                                } label: {
                                    Chip(text: item.title, filled: item.id == board.id).frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityAddTraits(item.id == board.id ? .isSelected : [])
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    SectionLabel(text: "Version \(number)")
                    MakeDesignBoardFrame(designID: designID, board: board, stamp: doc.version, version: number, maxHeight: 300)
                    SectionLabel(text: "Current")
                    MakeDesignBoardFrame(designID: designID, board: board, stamp: doc.version, maxHeight: 300)
                } else {
                    EmptyLine(text: "This design has no boards to compare.")
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }
}

/// The desktop's comments, keyed by its own ids: resolve, reopen, delete (asked first), send to the model.
struct MakeDesignCommentsLive: View {
    let designID: String
    let chat: MakeDesignChat?
    let onLink: () -> Void
    let onSent: () -> Void
    @State private var picks: Set<String> = []
    @State private var seeded = false
    @State private var deleting: MakeDesignComment?
    @State private var problem: String?

    private var live: MakeDesignLive { MakeDesignLive.shared }

    var body: some View {
        let doc = live.docs[designID]
        let comments = doc?.comments ?? []
        let openIDs = Set(comments.filter(\.isOpen).map(\.id))
        let chosen = picks.intersection(openIDs)
        let working = live.busy.contains(designID)
        let turnOpen = live.turns[designID]?.isOpen == true
        let turnLost = live.turns[designID]?.isLost == true
        let canSend = !chosen.isEmpty && chosen.count <= 10 && chat != nil && !turnOpen && !turnLost && !working
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MakeSheetTitle(title: "Comments", detail: openIDs.count == 1 ? "1 open" : "\(openIDs.count) open")
                if working { MakeDesignLine(text: "Saving to your desktop...", working: true) }
                if let problem { MakeDesignLine(text: problem, action: "OK") { self.problem = nil } }
                if comments.isEmpty { EmptyLine(text: "No comments yet.") }
                ForEach(comments) { comment in
                    row(comment, boardTitle: doc?.boards.first(where: { $0.id == comment.board })?.title ?? comment.board,
                        current: doc?.version ?? 0, working: working)
                }
                if chat == nil {
                    EmptyLine(text: "Link this design to a chat to send comments to a model.")
                    MakePillButton(title: "Link a chat", symbol: "link") { onLink() }
                } else {
                    HintLine(text: turnLost ? "Your last message was not confirmed. Send it again or discard it on the design first."
                             : turnOpen ? "Your desktop is working. A model is on the last message."
                             : "Sending starts a model on your desktop. That can use your plan or cost money.")
                }
                if chosen.count > 10 { HintLine(text: "At most 10 comments per message.") }
                GoldButton(title: chosen.count == 1 ? "Send 1 comment" : "Send \(chosen.count) comments") { send(chosen, comments, doc) }
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.5)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .interactiveDismissDisabled(working || live.turns[designID]?.state == .sending)
        .sheet(item: $deleting) { comment in
            ConfirmSheet(title: "Delete this comment?",
                         detail: "\"\(comment.text.prefix(120))\" is deleted from your desktop. This cannot be undone.",
                         confirm: "Delete") { delete(comment) }
        }
        .onAppear {
            guard !seeded else { return }
            seeded = true
            picks = Set(openIDs.prefix(10))
        }
    }

    private func row(_ comment: MakeDesignComment, boardTitle: String, current: Int, working: Bool) -> some View {
        let picked = comment.isOpen && picks.contains(comment.id)
        let place = comment.elementIDs.isEmpty ? "A point on the board" : comment.elementIDs.joined(separator: ", ")
        return HStack(alignment: .top, spacing: 6) {
            Button {
                Haptics.select()
                if picks.contains(comment.id) { picks.remove(comment.id) } else { picks.insert(comment.id) }
            } label: {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(picked ? Palette.goldText : Palette.inkFaint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(!comment.isOpen)
            .opacity(comment.isOpen ? 1 : 0.35)
            .accessibilityLabel("Include comment \(comment.number)")
            .accessibilityAddTraits(picked ? .isSelected : [])

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(comment.number). \(boardTitle)")
                        .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    statePill(comment)
                }
                Text(comment.text)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(comment.madeOn < current ? "\(place) · made on v\(comment.madeOn)" : place)
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if comment.status == "resolved" {
                        MakePillButton(title: "Reopen") { setStatus(comment, "open") }
                    } else {
                        MakePillButton(title: "Resolve") { setStatus(comment, "resolved") }
                    }
                    MakePillButton(title: "Delete", danger: true) { deleting = comment }
                }
                .disabled(working)
                .opacity(working ? 0.5 : 1)
            }
        }
        .padding(.vertical, 10)
        .padding(.trailing, 12)
        .padding(.leading, 2)
        .kCard(radius: 20)
    }

    private func statePill(_ comment: MakeDesignComment) -> StatePill {
        switch comment.status {
        case "addressed": return StatePill(text: comment.addressedIn.map { "Addressed in v\($0)" } ?? "Addressed", tone: .ok)
        case "resolved": return StatePill(text: "Resolved", tone: .muted)
        default: return StatePill(text: "Open", tone: .warn)
        }
    }

    private func tell(_ outcome: MakeDesignOutcome) {
        switch outcome {
        case .saved: Haptics.success()
        case .busy: problem = "Another change to this design is still on its way. Try again in a moment."
        case .failed(let words), .unconfirmed(let words): problem = words
        }
    }

    private func setStatus(_ comment: MakeDesignComment, _ status: String) {
        Task { tell(await live.setCommentStatus(designID, comment: comment.id, status: status)) }
    }

    private func delete(_ comment: MakeDesignComment) {
        Task { tell(await live.deleteComment(designID, comment: comment.id)) }
    }

    /// The comments go as references by their own ids, the way the desktop's page sends them, with no
    /// words added. The sheet stays until the desktop has taken the message.
    private func send(_ chosen: Set<String>, _ comments: [MakeDesignComment], _ doc: MakeDesignDoc?) {
        guard let chat else { return }
        let references = comments.filter { chosen.contains($0.id) }.map { comment in
            let title = doc?.boards.first(where: { $0.id == comment.board })?.title ?? comment.board
            return MakeDesignReference(designID: designID, board: comment.board, elementIDs: comment.elementIDs,
                                       pointX: comment.pointX, pointY: comment.pointY, comment: comment.text,
                                       commentID: comment.id, label: "\(title) · \(comment.text.prefix(40))")
        }
        Task {
            switch await live.send(designID, sessionID: chat.id, message: "", references: references) {
            case .saved:
                Haptics.success()
                onSent()
            case .busy:
                problem = "The model is still working on the last message."
            case .failed(let words), .unconfirmed(let words):
                problem = words
            }
        }
    }
}

/// Export on the desktop. The HTML zip works anywhere; the rest need the desktop app's own window.
struct MakeDesignExportLive: View {
    let designID: String
    let chat: MakeDesignChat?
    @State private var sending: String?
    @State private var result: String?
    @State private var problem: String?
    @State private var onDesktop: Set<String> = []

    private let kinds: [(format: String, symbol: String, title: String, detail: String)] = [
        ("html", "doc.zipper", "HTML zip", "Opens offline in any browser"),
        ("png", "photo", "PNG images", "Drawn by Kairos on your desktop"),
        ("pdf", "doc.richtext", "PDF", "Drawn by Kairos on your desktop"),
        ("pptx", "rectangle.on.rectangle", "PowerPoint", "Drawn by Kairos on your desktop"),
    ]

    var body: some View {
        let doc = MakeDesignLive.shared.docs[designID]
        FittedSheet(estimate: 560) {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Export", detail: chat.map { "The file is saved to the files of \($0.title)." })
                VStack(spacing: 0) {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { offset, kind in
                        let off = kind.format != "html" && (doc?.canRender != true || onDesktop.contains(kind.format))
                        let ready = !off && chat != nil && sending == nil
                        Button { export(kind.format) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(ready ? Palette.goldText : Palette.inkFaint)
                                    .frame(width: 40, height: 40)
                                    .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(kind.title).font(KFont.ui(16.5)).foregroundStyle(ready ? Palette.ink : Palette.inkFaint)
                                    Text(off ? MakeDesignWire.exportOnDesktop : kind.detail)
                                        .font(KFont.ui(13.5, relativeTo: .footnote))
                                        .foregroundStyle(Palette.inkFaint)
                                }
                                Spacer(minLength: 0)
                                if sending == kind.format { PulsingDot(color: Palette.working) }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if offset < kinds.count - 1 { Palette.line.frame(height: 1).padding(.leading, 68) }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .disabled(!ready)
                    }
                }
                .kCard(radius: 20)
                if chat == nil { HintLine(text: "Link a chat first: an export is saved to that chat's files.") }
                if sending != nil { MakeDesignLine(text: "Exporting on your desktop...", working: true) }
                if let result { HintLine(text: result, symbol: "checkmark", color: Palette.success) }
                if let problem { HintLine(text: problem, color: Palette.danger) }
                HintLine(text: "To build this design in Forge, use Kairos on your desktop.")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .interactiveDismissDisabled(sending != nil)
    }

    private func export(_ format: String) {
        guard sending == nil, let chat else { return }
        Haptics.tap()
        sending = format
        result = nil
        problem = nil
        Task {
            let made = await MakeDesignLive.shared.export(designID, format: format, sessionID: chat.id)
            sending = nil
            switch made.outcome {
            case .saved:
                Haptics.success()
                result = "Exported \(made.name ?? "the file"). It is in the files of \(chat.title)."
            case .busy:
                problem = "Another change to this design is still on its way. Try again in a moment."
            case .failed(let words):
                if words == MakeDesignWire.exportOnDesktop { onDesktop.insert(format) } else { problem = words }
            case .unconfirmed(let words):
                problem = words
            }
        }
    }
}
