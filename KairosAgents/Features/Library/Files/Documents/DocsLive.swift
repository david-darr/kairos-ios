import SwiftUI
import PDFKit
import ImageIO
import CryptoKit

// The paired desktop behind Library documents, chat files and uploads (see Net/DocsAPI.swift for the routes).
// Unpaired, nothing here runs and the screens show their sample stores exactly as before.

/// Where one desktop read stands, for one plain sentence on screen.
nonisolated enum DocsLiveLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// One document as the desktop has it now.
nonisolated struct DocsLiveDoc: Equatable, Sendable {
    var id: String
    var title: String
    var content: String
    var updated: Date?
}

nonisolated enum DocsLiveRead: Sendable {
    case found(DocsLiveDoc)
    case gone
    case failed(String)
}

/// How a new document or an import ended.
nonisolated enum DocsLiveCreateOutcome: Sendable {
    case made(DocsLiveDoc)
    /// Certainly not made (refused, or not sent at all).
    case refused(String)
    /// Sent, and the answer never came. Nothing may be offered again until the desktop is checked.
    case unconfirmed(DocsLivePendingCreate, String)
    /// Sent, the answer never came, and the desktop does not have it yet. It may still land late, so it is
    /// looked for again before anything is sent again.
    case notFound(DocsLivePendingCreate, String)
}

/// A create whose answer was lost: what was sent, and which documents existed before it.
nonisolated struct DocsLivePendingCreate: Equatable, Sendable {
    var title: String
    var content: String
    var before: Set<String>
}

/// How a save of an open document ended.
nonisolated enum DocsLiveSaveOutcome: Sendable {
    case saved(DocsLiveDoc)
    /// The desktop's copy of a field being sent is not the one the form was filled from.
    case conflict(DocsLiveDoc)
    case gone
    /// Certainly not saved.
    case failed(String)
    /// Sent, the answer was lost, and the desktop could not be read to check.
    case unconfirmed(String)
    case busy
}

nonisolated enum DocsLiveDeleteOutcome: Sendable {
    case deleted
    case failed(String)
    case unconfirmed(String)
}

/// One chat file the viewer can open.
nonisolated struct DocsLiveFileRef: Identifiable, Hashable, Sendable {
    var id: String
    var sessionID: String
    var url: String
    var name: String
    var bytes: Int
    var sizeKnown: Bool
    var origin: ChatDocsOrigin
}

@Observable
final class DocsLiveStore {
    static let shared = DocsLiveStore()

    private(set) var isLive = false
    private(set) var account = "sample"
    private(set) var documents: [LibraryDocument] = []
    private(set) var docsLoad: DocsLiveLoad = .idle
    private(set) var docsSkipped = 0
    private(set) var groups: [ChatDocsGroup] = []
    private(set) var filesLoad: DocsLiveLoad = .idle
    private(set) var filesSkipped = 0
    var openGroups: Set<String> = []
    /// Documents with a save or delete on its way.
    private(set) var busyDocs: Set<String> = []
    /// An import whose answer never arrived: checked on the desktop before Import is offered again.
    var pendingImport: DocsLivePendingCreate?
    var pendingImportName = ""
    /// An import whose answer never arrived and that was not on the desktop when checked: looked for again
    /// before the next import is sent, so a late one is not made twice.
    var lostImport: DocsLivePendingCreate?
    var lostImportName = ""

    private var docsSerial = 0
    private var filesSerial = 0
    private var writeSerial = 0

    // MARK: Connection

    /// Changes when the phone is paired or unpaired, the desktop comes back, or another desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Paired right now: screens never show a sample item.
    static var paired: Bool { !Connection.shared.usesSampleData }

    private init() {
        // A new run of the app: copies a viewer left behind (a crash, the app killed) are removed before
        // any viewer of this run can exist.
        DocsLiveTempFiles.sweep()
    }

    func stillLive(_ key: String) -> Bool {
        isLive && account == key && Self.accountKey == key
    }

    static let desktopChanged = "Your paired desktop changed. Try again."

    /// The document list is shown, but the last read of it failed: one line says so.
    var docsStale: String? {
        guard case .failed(let why) = docsLoad, !documents.isEmpty else { return nil }
        return "This list may be out of date. " + why
    }

    /// The chat files are shown, but the last read of them failed.
    var filesStale: String? {
        guard case .failed(let why) = filesLoad, !groups.isEmpty else { return nil }
        return "This list may be out of date. " + why
    }

    func followConnection() {
        let wantLive = Self.paired
        if wantLive {
            guard !isLive || account != Self.accountKey else { return }
            reset()
            isLive = true
            account = Self.accountKey
        } else if isLive {
            reset()
            isLive = false
            account = "sample"
        }
    }

    private func reset() {
        documents = []
        docsLoad = .idle
        docsSkipped = 0
        groups = []
        filesLoad = .idle
        filesSkipped = 0
        openGroups = []
        busyDocs = []
        pendingImport = nil
        pendingImportName = ""
        lostImport = nil
        lostImportName = ""
        docsSerial += 1
        filesSerial += 1
        writeSerial += 1
        // Unpaired, or another desktop or account: no copy of the old desktop's files stays on the phone.
        DocsLiveTempFiles.sweep()
    }

    private func client() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    var fileCount: Int { groups.reduce(0) { $0 + $1.files.count } }

    /// Every file sent to a chat, newest first: the desktop's own uploads.
    var uploads: [(file: ChatDocsFile, group: ChatDocsGroup)] {
        groups.flatMap { group in group.files.filter { $0.origin == .sent }.map { (file: $0, group: group) } }
    }

    // MARK: Reading

    func loadAll() async {
        followConnection()
        guard isLive else { return }
        await loadDocuments()
        await loadFiles()
    }

    /// Read the document list. An older read never replaces newer state; a read that was on its way while a
    /// write finished is read again. A cancelled read changes nothing.
    @discardableResult
    func loadDocuments() async -> Bool {
        guard isLive else { return false }
        let key = account
        docsSerial += 1
        let mine = docsSerial
        if docsLoad != .loaded { docsLoad = .loading }
        for _ in 0..<3 {
            let writes = writeSerial
            do {
                let read = try await client().docsList()
                guard stillLive(key), mine == docsSerial else { return false }
                guard writes == writeSerial else { continue }
                documents = read.documents.map(Self.liveDocument)
                docsSkipped = read.skipped
                docsLoad = .loaded
                return true
            } catch {
                if error is CancellationError || Task.isCancelled { return false }
                Connection.shared.note(error)
                guard stillLive(key), mine == docsSerial else { return false }
                docsLoad = .failed("Your documents could not be read. " + error.plainWords)
                return false
            }
        }
        guard stillLive(key), mine == docsSerial else { return false }
        if docsLoad != .loaded { docsLoad = .failed("Your documents kept changing while they were read. Try again.") }
        return false
    }

    func loadFiles() async {
        guard isLive else { return }
        let key = account
        filesSerial += 1
        let mine = filesSerial
        if filesLoad != .loaded { filesLoad = .loading }
        do {
            let read = try await client().docsChatFiles()
            guard stillLive(key), mine == filesSerial else { return }
            groups = Self.liveGroups(read)
            filesSkipped = read.skipped
            filesLoad = .loaded
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            Connection.shared.note(error)
            guard stillLive(key), mine == filesSerial else { return }
            filesLoad = .failed("Your chat files could not be read. " + error.plainWords)
        }
    }

    nonisolated static func liveDocument(_ dto: DocsDocumentDTO) -> LibraryDocument {
        let title = dto.title?.string ?? ""
        return LibraryDocument(id: dto.id, title: title.isEmpty ? "Untitled" : title, body: "",
                               updated: DocsWire.time(dto.updatedAt) ?? DocsWire.time(dto.createdAt) ?? .distantPast)
    }

    nonisolated static func liveDoc(_ dto: DocsDocumentDTO) -> DocsLiveDoc {
        DocsLiveDoc(id: dto.id, title: dto.title?.string ?? "", content: dto.content?.string ?? "",
                    updated: DocsWire.time(dto.updatedAt))
    }

    nonisolated static func liveGroups(_ read: DocsChatLibraryDTO) -> [ChatDocsGroup] {
        read.groups.map { group in
            let files = group.files.map { dto -> ChatDocsFile in
                let name = dto.name?.string ?? "File"
                let size = byteCount(dto.size?.double)
                return ChatDocsFile(id: group.sessionId + "|" + dto.id, name: name, bytes: size ?? 0,
                                    origin: DocsWire.origin(dto.origin), look: DocsWire.look(forName: name),
                                    available: dto.exists?.bool == true && dto.url?.string != nil,
                                    url: dto.url?.string, added: DocsWire.time(dto.createdAt), sizeKnown: size != nil)
            }
            let title = (group.title ?? "").isEmpty ? "Untitled chat" : (group.title ?? "")
            return ChatDocsGroup(id: group.sessionId, title: title, files: files)
        }
    }

    /// A byte count from the desktop. One that is not a whole, sane number is treated as unknown rather than
    /// trapping on the conversion.
    nonisolated static func byteCount(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0, value < 1e15 else { return nil }
        return Int(value)
    }

    static func ref(_ file: ChatDocsFile, in group: ChatDocsGroup) -> DocsLiveFileRef? {
        guard file.available, let url = file.url else { return nil }
        return DocsLiveFileRef(id: file.id, sessionID: group.id, url: url, name: file.name, bytes: file.bytes,
                               sizeKnown: file.sizeKnown, origin: file.origin)
    }

    /// Desktop search over document text (at most 5 hits): id to snippet ("" for a title match).
    func search(_ query: String) async -> [String: String]? {
        guard isLive else { return nil }
        let key = account
        guard let found = try? await client().docsSearch(query), stillLive(key) else { return nil }
        var hits: [String: String] = [:]
        for hit in found.hits { hits[hit.id] = hit.snippet?.string ?? "" }
        return hits
    }

    func read(_ id: String) async -> DocsLiveRead {
        guard isLive else { return .failed("This document is a sample.") }
        let key = account
        do {
            let dto = try await client().docsGet(id)
            guard stillLive(key) else { return .failed(Self.desktopChanged) }
            return .found(Self.liveDoc(dto))
        } catch {
            Connection.shared.note(error)
            if Self.isMissing(error) { return .gone }
            return .failed(error.plainWords)
        }
    }

    // MARK: Writing

    private static func isMissing(_ error: Error) -> Bool {
        if case .server(status: 404, _) = error as? APIError { return true }
        return false
    }

    /// The desktop refused, so it certainly did not act. Anything else may have come after it acted.
    private static func wasRefused(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
    }

    private func upsert(_ doc: DocsLiveDoc) {
        let row = LibraryDocument(id: doc.id, title: doc.title.isEmpty ? "Untitled" : doc.title, body: "",
                                  updated: doc.updated ?? .now)
        documents.removeAll { $0.id == doc.id }
        documents.insert(row, at: 0)
    }

    /// Make a document (a new one, or an import). Sent once. A lost answer is looked for on the desktop: a
    /// document that was not there before, with the title and text that were sent. Nothing is sent unless the
    /// list was read first, so the check can prove a document is new.
    func create(title: String, content: String, importing filename: String? = nil) async -> DocsLiveCreateOutcome {
        guard isLive else { return .refused("This is a sample.") }
        let key = account
        if docsLoad != .loaded { await loadDocuments() }
        guard stillLive(key) else { return .refused(Self.desktopChanged) }
        guard docsLoad == .loaded else {
            return .refused("Your documents could not be read first, so nothing was sent. Try again.")
        }
        let pending = DocsLivePendingCreate(title: title, content: content, before: Set(documents.map(\.id)))
        do {
            let client = try client()
            let dto: DocsDocumentDTO
            if let filename {
                dto = try await client.docsImport(filename: filename, content: content)
            } else {
                dto = try await client.docsCreate(title: title, content: content)
            }
            writeSerial += 1
            guard stillLive(key) else { return .refused(Self.desktopChanged) }
            let made = Self.liveDoc(dto)
            upsert(made)
            return .made(made)
        } catch {
            writeSerial += 1
            Connection.shared.note(error)
            guard stillLive(key) else { return .refused(Self.desktopChanged) }
            if Self.wasRefused(error) { return .refused(error.plainWords) }
            return await findCreated(pending, why: error.plainWords)
        }
    }

    /// Look for a create whose answer was lost. Not finding it is not final: it may still land, so the
    /// caller keeps it and looks again before it sends anything new.
    func findCreated(_ pending: DocsLivePendingCreate, why: String = "") async -> DocsLiveCreateOutcome {
        let key = account
        let unsure = "Your desktop did not confirm this, and it could not be read to check. " +
            "Check again before you try it again."
        guard await loadDocuments(), stillLive(key) else { return .unconfirmed(pending, unsure) }
        let candidates = documents.filter { !pending.before.contains($0.id) && $0.title == (pending.title.isEmpty ? "Untitled" : pending.title) }
        for candidate in candidates.prefix(5) {
            switch await read(candidate.id) {
            case .found(let doc):
                guard stillLive(key) else { return .unconfirmed(pending, unsure) }
                if doc.content == pending.content { return .made(doc) }
            case .gone:
                continue
            case .failed:
                // A candidate that could not be read may be the one: nothing is proven.
                return .unconfirmed(pending, unsure)
            }
        }
        guard stillLive(key) else { return .unconfirmed(pending, unsure) }
        return .notFound(pending, "Your desktop did not confirm this, and it is not in your documents yet. " +
                         "Your text is still here. Trying again looks for it first, so it is not made twice. " + why)
    }

    /// Save the fields the person changed. The desktop keeps no revision, so the document is read first and
    /// the save is refused when a field about to be sent is not what the form was filled from.
    func save(_ id: String, title: String?, content: String?, filledTitle: String, filledContent: String) async -> DocsLiveSaveOutcome {
        guard isLive else { return .failed("This document is a sample.") }
        guard title != nil || content != nil else { return .failed("Nothing changed.") }
        guard !busyDocs.contains(id) else { return .busy }
        let key = account
        busyDocs.insert(id)
        defer {
            writeSerial += 1
            if account == key { busyDocs.remove(id) }
        }
        switch await read(id) {
        case .gone: return .gone
        case .failed(let why): return .failed("Your document could not be checked, so it was not saved. " + why)
        case .found(let now):
            guard stillLive(key) else { return .failed(Self.desktopChanged) }
            if (title != nil && now.title != filledTitle) || (content != nil && now.content != filledContent) {
                return .conflict(now)
            }
        }
        do {
            let dto = try await client().docsUpdate(id, title: title, content: content)
            guard stillLive(key) else { return .failed(Self.desktopChanged) }
            let saved = Self.liveDoc(dto)
            upsert(saved)
            return .saved(saved)
        } catch {
            Connection.shared.note(error)
            guard stillLive(key) else { return .failed(Self.desktopChanged) }
            if Self.isMissing(error) { return .gone }
            if Self.wasRefused(error) { return .failed("Your change was not saved. " + error.plainWords) }
            // The answer was lost: compare what the desktop has now with what was sent.
            switch await read(id) {
            case .gone: return .gone
            case .failed:
                return .unconfirmed("Your desktop did not confirm this save, and it could not be read to check. Your text is still here.")
            case .found(let now):
                guard stillLive(key) else { return .failed(Self.desktopChanged) }
                let titleSent = title.map { now.title == $0 } ?? true
                let contentSent = content.map { now.content == $0 } ?? true
                if titleSent && contentSent {
                    upsert(now)
                    return .saved(now)
                }
                let titleOld = title == nil || now.title == filledTitle
                let contentOld = content == nil || now.content == filledContent
                if titleOld && contentOld {
                    return .failed("Your desktop did not get this save. Your text is still here. Save again.")
                }
                return .conflict(now)
            }
        }
    }

    func delete(_ id: String) async -> DocsLiveDeleteOutcome {
        guard isLive else { return .failed("This document is a sample.") }
        guard !busyDocs.contains(id) else { return .failed("Wait for the last change to finish.") }
        let key = account
        busyDocs.insert(id)
        defer {
            writeSerial += 1
            if account == key { busyDocs.remove(id) }
        }
        do {
            _ = try await client().docsDelete(id)
            guard stillLive(key) else { return .deleted }
            documents.removeAll { $0.id == id }
            return .deleted
        } catch {
            Connection.shared.note(error)
            guard stillLive(key) else { return .failed(Self.desktopChanged) }
            if Self.wasRefused(error) { return .failed("This document was not deleted. " + error.plainWords) }
            switch await read(id) {
            case .gone:
                documents.removeAll { $0.id == id }
                return .deleted
            case .found: return .failed("This document was not deleted. " + error.plainWords)
            case .failed: return .unconfirmed("Your desktop did not confirm the delete, and it could not be read to check.")
            }
        }
    }

    /// Is this chat still on the desktop. nil means yes; otherwise one sentence to show.
    func chatProblem(_ sessionID: String) async -> String? {
        guard isLive else { return "This chat is a sample." }
        let key = account
        do {
            _ = try await client().docsChatSession(sessionID)
            return stillLive(key) ? nil : Self.desktopChanged
        } catch {
            Connection.shared.note(error)
            if Self.isMissing(error) { return "This chat is no longer on your desktop." }
            return "This chat could not be opened. " + error.plainWords
        }
    }

    /// The bytes of one chat file.
    func fileBytes(_ ref: DocsLiveFileRef, download: Bool) async throws -> Data {
        let key = account
        let data = try await client().docsFileBytes(sessionId: ref.sessionID, url: ref.url, download: download)
        guard stillLive(key) else { throw CancellationError() }
        return data
    }

    func fileInfo(_ ref: DocsLiveFileRef) async throws -> DocsArtifactDTO {
        let key = account
        let info = try await client().docsFileInfo(sessionId: ref.sessionID, url: ref.url)
        guard stillLive(key) else { throw CancellationError() }
        return info
    }
}

// MARK: - A quiet line

/// Loading, or what failed, with one plain action.
struct DocsLiveLine: View {
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

// MARK: - The viewer for real files

/// What the desktop said a file is, kept for the life of one viewer so a page that comes back is not asked again.
nonisolated struct DocsLiveFileInfo: Sendable {
    var kind: DocsFileKind
    var size: Int
}

/// A decoded picture handed from the decoding task to the screen. A CGImage is immutable once made.
nonisolated struct DocsLivePicture: @unchecked Sendable {
    let image: CGImage
}

/// Temporary copies of the files one viewer opened, for the share sheet.
///
/// Each viewer has its own folder under `tmp/docs-viewer/`; inside it each file has a folder named from its
/// desktop id (cleaned so it holds no path separator and no dot), holding one copy under the file's own name.
/// A file is written once per viewer, so Share always hands over the bytes of the file on screen. Nothing is
/// written after the viewer closed or the paired desktop changed; closing cancels every task the viewer started
/// and removes its folder. Copies left by a crash are removed at the next start, and every copy is removed when
/// the phone unpairs or another desktop or account is paired. The folder is excluded from backup.
@Observable
final class DocsLiveTempFiles {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("docs-viewer", isDirectory: true)

    /// The paired desktop this viewer was opened for.
    let account: String
    private let folder = DocsLiveTempFiles.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    private(set) var urls: [String: URL] = [:]
    private(set) var closed = false
    @ObservationIgnored private var infos: [String: DocsLiveFileInfo] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    init(account: String) {
        self.account = account
    }

    /// Open, and still showing the desktop it was opened for. Nothing is written otherwise.
    var isOpen: Bool { !closed && DocsLiveStore.shared.stillLive(account) }

    func info(_ id: String) -> DocsLiveFileInfo? { infos[id] }

    func remember(_ info: DocsLiveFileInfo, for id: String) {
        guard isOpen else { return }
        infos[id] = info
    }

    /// Keep one copy of a file's bytes. A file already kept by this viewer is never written again.
    @discardableResult
    func keep(_ data: Data, for ref: DocsLiveFileRef) -> URL? {
        guard isOpen else { return nil }
        if let url = urls[ref.id] { return url }
        let manager = FileManager.default
        let place = folder.appendingPathComponent(Self.diskName(forID: ref.id), isDirectory: true)
        let url = place.appendingPathComponent(Self.diskName(forFile: ref.name), isDirectory: false)
        do {
            try Self.makeRoot()
            try manager.createDirectory(at: place, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            urls[ref.id] = url
            return url
        } catch {
            // Without a copy the file still shows; only sharing is off.
            try? manager.removeItem(at: place)
            return nil
        }
    }

    /// The bytes this viewer already kept for a file, read off the main actor.
    func keptData(for id: String) async -> Data? {
        guard let url = urls[id] else { return nil }
        return await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
    }

    /// Start a task that belongs to this viewer: it is cancelled when the viewer closes.
    func run(_ work: @escaping @MainActor () async -> Void) {
        guard isOpen else { return }
        let id = UUID()
        tasks[id] = Task { [weak self] in
            await work()
            self?.tasks[id] = nil
        }
    }

    /// The viewer closed, or its desktop is gone: cancel its tasks and remove everything it wrote.
    func close() {
        closed = true
        for task in tasks.values { task.cancel() }
        tasks = [:]
        infos = [:]
        urls = [:]
        try? FileManager.default.removeItem(at: folder)
    }

    /// Remove every viewer copy on the phone.
    static func sweep() {
        let manager = FileManager.default
        try? manager.removeItem(at: root)
        // Copies from earlier test builds, which used one folder per viewer at the top of tmp.
        let tmp = manager.temporaryDirectory
        if let names = try? manager.contentsOfDirectory(atPath: tmp.path(percentEncoded: false)) {
            for name in names where name.hasPrefix("docs-viewer-") {
                try? manager.removeItem(at: tmp.appendingPathComponent(name, isDirectory: true))
            }
        }
    }

    private static func makeRoot() throws {
        var url = root
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path(percentEncoded: false)) {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// A folder name made from a desktop file id. Letters, digits and "-" stay; every other byte becomes
    /// "_" and two hex digits, so two ids never share a name, and no name holds "/", "." or "..".
    nonisolated static func diskName(forID id: String) -> String {
        var name = "f"
        for byte in id.utf8 {
            let keep = (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == 0x2D
            if keep {
                name.append(Character(Unicode.Scalar(byte)))
            } else {
                name += String(format: "_%02X", byte)
            }
        }
        guard name.utf8.count > 160 else { return name }
        // A very long id: its SHA-256, still one name per id.
        return "h" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The file's own name, safe as one path component, so the share sheet shows it.
    nonisolated static func diskName(forFile name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned.allSatisfy({ $0 == "." }) { return "file" }
        guard cleaned.utf8.count > 200 else { return cleaned }
        let ext = (cleaned as NSString).pathExtension
        return ext.isEmpty || ext.utf8.count > 20 ? "file" : "file." + ext
    }
}

/// Decoding a file's bytes for the screen, off the main actor.
nonisolated enum DocsLiveDecode {
    /// A picture scaled down to at most `maxPixels` on its long side, never decoded whole.
    static func picture(_ data: Data, maxPixels: CGFloat) -> DocsLivePicture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        var longSide = maxPixels
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
           width > 0, height > 0 {
            longSide = min(maxPixels, CGFloat(max(width, height)))
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(longSide)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DocsLivePicture(image: image)
    }

    /// Text for the screen: the start of it when it is long.
    static func text(_ data: Data, limit: Int) -> (text: String, cut: Bool) {
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        guard text.count > limit else { return (text, false) }
        return (String(text.prefix(limit)), true)
    }
}

/// Real chat files from the paired desktop: "n of N", Share, a details pill and the file itself.
struct DocsLiveViewer: View {
    let files: [DocsLiveFileRef]
    @State var index: Int
    @State private var temp = DocsLiveTempFiles(account: DocsLiveStore.shared.account)
    private let store = DocsLiveStore.shared

    private var current: DocsLiveFileRef { files[min(max(0, index), files.count - 1)] }
    /// The paired desktop is still the one these files came from.
    private var desktopSame: Bool { store.stillLive(temp.account) }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Text("\(index + 1) of \(files.count)")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    Spacer()
                    if temp.isOpen, let url = temp.urls[current.id] {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Share or save")
                    }
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(minHeight: 44)
            }
            .padding(.top, 28)
            .padding(.horizontal, 12)

            if temp.isOpen {
                HStack(spacing: 10) {
                    Text(current.name).font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(DocsLiveViewer.details(current)).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .kCard(radius: 14)
                .padding(.horizontal, 16)

                TabView(selection: $index) {
                    ForEach(Array(files.enumerated()), id: \.offset) { offset, file in
                        DocsLivePage(file: file, temp: temp)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                DocsLiveLine(text: "Your paired desktop changed, so this file was closed. Open it again from the list.")
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
        }
        .animation(Motion.snappy, value: index)
        .onChange(of: desktopSame) { _, same in
            if !same { temp.close() }
        }
        .onDisappear { temp.close() }
    }

    static func details(_ file: DocsLiveFileRef) -> String {
        let ext = (file.name as NSString).pathExtension.uppercased()
        var parts: [String] = []
        if !ext.isEmpty { parts.append(ext) }
        if file.sizeKnown { parts.append(Int64(file.bytes).formatted(.byteCount(style: .file))) }
        parts.append(file.origin.label)
        return parts.joined(separator: " · ")
    }
}

/// One real file, large: text and Markdown rendered, a picture, a PDF, or an honest line.
private struct DocsLivePage: View {
    let file: DocsLiveFileRef
    let temp: DocsLiveTempFiles

    private enum Phase {
        case loading
        case markdown(String)
        case text(String, cut: Bool)
        case image(UIImage)
        case pdf(PDFDocument)
        case other(kind: DocsFileKind, size: Int)
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var fetching = false
    @State private var fetchProblem: String?
    @State private var box: CGSize = .zero
    @Environment(\.displayScale) private var displayScale
    private let store = DocsLiveStore.shared
    private static let textLimit = 200_000

    /// This page's task may still change the screen or write: the viewer is open and the task was not cancelled.
    private var stillOpen: Bool { temp.isOpen && !Task.isCancelled }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.surface)
            switch phase {
            case .loading:
                ProgressView().tint(Palette.goldText)
            case .markdown(let text):
                ScrollView {
                    VaultMarkdownView(blocks: VaultMarkdown.blocks(VaultMarkdown.stripFrontmatter(text)))
                        .padding(18)
                }
            case .text(let text, let cut):
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if cut { HintLine(text: "Only the start of this file is shown here.") }
                        Text(text)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18)
                }
            case .image(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .accessibilityLabel(file.name)
            case .pdf(let document):
                DocsLivePDF(document: document)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            case .other(let kind, let size):
                plainLine(kind: kind, size: size)
            case .failed(let reason):
                VStack(spacing: 6) {
                    Image(systemName: "doc.questionmark").font(.system(size: 26)).foregroundStyle(Palette.inkFaint)
                    Text(reason)
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { box = $0 }
        .task(id: file.id) { await open() }
    }

    private func plainLine(kind: DocsFileKind, size: Int) -> some View {
        VStack(spacing: 10) {
            TypeBadge(text: file.name.contains(".") ? (file.name as NSString).pathExtension : "File")
            Text("\(kindWord(kind)), \(Int64(size).formatted(.byteCount(style: .file))). This app cannot show it here.")
                .font(KFont.ui(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center)
            if temp.urls[file.id] != nil {
                HintLine(text: "Ready to share. Use the share button above.")
            } else if size > DocsWire.maxBytes {
                HintLine(text: "It is too large to bring to this iPhone.")
            } else {
                QuietButton(title: fetching ? "Getting the file…" : "Get the file to share") { fetchForShare() }
                    .disabled(fetching)
                if let fetchProblem { HintLine(text: fetchProblem) }
            }
        }
        .padding(24)
    }

    private func kindWord(_ kind: DocsFileKind) -> String {
        switch kind {
        case .office: return "An Office file"
        case .video: return "A video"
        case .audio: return "A sound file"
        case .image: return "A picture"
        case .pdf: return "A PDF"
        default:
            let ext = (file.name as NSString).pathExtension.uppercased()
            return ext.isEmpty ? "A file" : "A \(ext) file"
        }
    }

    /// Bring a file the app cannot show over for the share sheet. The task belongs to the viewer: closing the
    /// viewer cancels it, and it writes nothing once the viewer is closed.
    private func fetchForShare() {
        guard !fetching, temp.isOpen, temp.urls[file.id] == nil else { return }
        fetching = true
        fetchProblem = nil
        let file = file
        let temp = temp
        let store = store
        temp.run {
            defer { fetching = false }
            do {
                let data = try await store.fileBytes(file, download: true)
                guard temp.isOpen, !Task.isCancelled else { return }
                if temp.keep(data, for: file) == nil { fetchProblem = "The file could not be kept for sharing." }
            } catch is CancellationError {
            } catch {
                guard temp.isOpen, !Task.isCancelled else { return }
                fetchProblem = "The file could not be read. " + error.plainWords
            }
        }
    }

    private func open() async {
        guard stillOpen else { return }
        do {
            let info: DocsLiveFileInfo
            if let known = temp.info(file.id) {
                info = known
            } else {
                let dto = try await store.fileInfo(file)
                guard stillOpen else { return }
                info = DocsLiveFileInfo(kind: DocsFileKind(wire: dto.kind), size: DocsLiveStore.byteCount(dto.size) ?? file.bytes)
                temp.remember(info, for: file.id)
            }
            switch info.kind {
            case .markdown, .text, .html, .image, .pdf:
                guard info.size <= DocsWire.maxBytes else {
                    phase = .other(kind: info.kind, size: info.size)
                    return
                }
                let data: Data
                if let kept = await temp.keptData(for: file.id) {
                    guard stillOpen else { return }
                    data = kept
                } else {
                    let fetched = try await store.fileBytes(file, download: false)
                    guard stillOpen else { return }
                    temp.keep(fetched, for: file)
                    data = fetched
                }
                let shown = await show(data, kind: info.kind, size: info.size)
                guard stillOpen else { return }
                phase = shown
            default:
                phase = .other(kind: info.kind, size: info.size)
            }
        } catch is CancellationError {
        } catch {
            guard stillOpen else { return }
            if case .server(status: 404, _) = error as? APIError {
                phase = .failed("No longer available. This file is not on your desktop any more.")
            } else {
                phase = .failed("This file could not be opened. " + error.plainWords)
            }
        }
    }

    /// Pictures and text are decoded off the main actor; a picture is scaled to this page's size on screen.
    private func show(_ data: Data, kind: DocsFileKind, size: Int) async -> Phase {
        switch kind {
        case .image:
            let edge = max(box.width, box.height) * displayScale
            let maxPixels = min(4096, edge > 0 ? max(256, edge) : 2048)
            let picture = await Task.detached(priority: .userInitiated) { DocsLiveDecode.picture(data, maxPixels: maxPixels) }.value
            if let picture { return .image(UIImage(cgImage: picture.image)) }
            return .other(kind: kind, size: size)
        case .pdf:
            // PDFKit reads pages as they are drawn; the file is at most 25 MB.
            if let document = PDFDocument(data: data) { return .pdf(document) }
            return .other(kind: kind, size: size)
        default:
            let limit = Self.textLimit
            let read = await Task.detached(priority: .userInitiated) { DocsLiveDecode.text(data, limit: limit) }.value
            return kind == .markdown && !read.cut ? .markdown(read.text) : .text(read.text, cut: read.cut)
        }
    }
}

private struct DocsLivePDF: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}
