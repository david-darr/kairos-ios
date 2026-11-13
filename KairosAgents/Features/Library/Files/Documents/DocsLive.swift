import SwiftUI
import PDFKit

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

    func stillLive(_ key: String) -> Bool {
        isLive && account == key && Self.accountKey == key
    }

    private static let desktopChanged = "Your paired desktop changed. Try again."

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
        docsSerial += 1
        filesSerial += 1
        writeSerial += 1
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
                let size = dto.size?.double
                return ChatDocsFile(id: group.sessionId + "|" + dto.id, name: name, bytes: Int(size ?? 0),
                                    origin: DocsWire.origin(dto.origin), look: DocsWire.look(forName: name),
                                    available: dto.exists?.bool == true && dto.url?.string != nil,
                                    url: dto.url?.string, added: DocsWire.time(dto.createdAt), sizeKnown: size != nil)
            }
            let title = (group.title ?? "").isEmpty ? "Untitled chat" : (group.title ?? "")
            return ChatDocsGroup(id: group.sessionId, title: title, files: files)
        }
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

    /// Look for a create whose answer was lost.
    func findCreated(_ pending: DocsLivePendingCreate, why: String = "") async -> DocsLiveCreateOutcome {
        let key = account
        let unsure = "Your desktop did not confirm this, and it could not be read to check. " +
            "Check again before you try it again."
        guard await loadDocuments(), stillLive(key) else { return .unconfirmed(pending, unsure) }
        let candidates = documents.filter { !pending.before.contains($0.id) && $0.title == (pending.title.isEmpty ? "Untitled" : pending.title) }
        for candidate in candidates.prefix(5) {
            guard case .found(let doc) = await read(candidate.id), stillLive(key) else { continue }
            if doc.content == pending.content { return .made(doc) }
        }
        guard stillLive(key) else { return .unconfirmed(pending, unsure) }
        return .refused("Your desktop did not confirm this, and it is not in your documents. " +
                        "Your text is still here, so you can try again. " + why)
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

/// Temporary copies of opened files, for the share sheet. They live in the app's temporary folder (never
/// backed up or synced) and are removed when the viewer closes.
@Observable
final class DocsLiveTempFiles {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("docs-viewer-" + UUID().uuidString, isDirectory: true)
    private(set) var urls: [String: URL] = [:]

    func keep(_ data: Data, for ref: DocsLiveFileRef) {
        let place = folder.appendingPathComponent(String(urls.count), isDirectory: true)
        let safe = ref.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = place.appendingPathComponent(safe.isEmpty ? "file" : safe)
        do {
            try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            urls[ref.id] = url
        } catch {
            // Without a copy the file still shows; only sharing is off.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: folder)
        urls = [:]
    }
}

/// Real chat files from the paired desktop: "n of N", Share, a details pill and the file itself.
struct DocsLiveViewer: View {
    let files: [DocsLiveFileRef]
    @State var index: Int
    @State private var temp = DocsLiveTempFiles()

    private var current: DocsLiveFileRef { files[min(max(0, index), files.count - 1)] }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Text("\(index + 1) of \(files.count)")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    Spacer()
                    if let url = temp.urls[current.id] {
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
        }
        .animation(Motion.snappy, value: index)
        .onDisappear { temp.clear() }
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
    private let store = DocsLiveStore.shared
    private static let textLimit = 200_000

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

    private func fetchForShare() {
        guard !fetching else { return }
        fetching = true
        fetchProblem = nil
        Task {
            do {
                let data = try await store.fileBytes(file, download: true)
                temp.keep(data, for: file)
                if temp.urls[file.id] == nil { fetchProblem = "The file could not be kept for sharing." }
            } catch is CancellationError {
            } catch {
                fetchProblem = "The file could not be read. " + error.plainWords
            }
            fetching = false
        }
    }

    private func open() async {
        do {
            let info = try await store.fileInfo(file)
            let kind = DocsFileKind(wire: info.kind)
            let size = Int(info.size ?? Double(file.bytes))
            switch kind {
            case .markdown, .text, .html, .image, .pdf:
                guard size <= DocsWire.maxBytes else {
                    phase = .other(kind: kind, size: size)
                    return
                }
                let data = try await store.fileBytes(file, download: false)
                temp.keep(data, for: file)
                phase = show(data, kind: kind, size: size)
            default:
                phase = .other(kind: kind, size: size)
            }
        } catch is CancellationError {
        } catch {
            if case .server(status: 404, _) = error as? APIError {
                phase = .failed("No longer available. This file is not on your desktop any more.")
            } else {
                phase = .failed("This file could not be opened. " + error.plainWords)
            }
        }
    }

    private func show(_ data: Data, kind: DocsFileKind, size: Int) -> Phase {
        switch kind {
        case .image:
            if let image = UIImage(data: data) { return .image(image) }
            return .other(kind: kind, size: size)
        case .pdf:
            if let document = PDFDocument(data: data) { return .pdf(document) }
            return .other(kind: kind, size: size)
        default:
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            let cut = text.count > Self.textLimit
            let shown = cut ? String(text.prefix(Self.textLimit)) : text
            return kind == .markdown && !cut ? .markdown(shown) : .text(shown, cut: cut)
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
