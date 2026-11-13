import SwiftUI
import UniformTypeIdentifiers

/// The states the Chat documents screen can be pictured in.
enum ChatDocsDebug: Hashable {
    case none, search, empty
}

/// A file group opened in the viewer.
struct ChatDocsViewing: Identifiable {
    let id = UUID()
    let documents: [ChatDocument]
    let index: Int
}

/// Real chat files opened in the viewer (paired).
struct DocsLiveViewing: Identifiable {
    let id = UUID()
    let files: [DocsLiveFileRef]
    let index: Int
}

/// Where the desktop's text search for the current query stands (paired).
nonisolated enum DocsLiveSearchState: Equatable, Sendable {
    case idle, searching
    /// Answered; `capped` when the desktop sent its most (five), so more may match.
    case done(capped: Bool)
    case failed
}

/// The editor opened on a document, or on a new one.
struct ChatDocsEditing: Identifiable {
    let id: String
    let documentID: String?

    init(documentID: String?) {
        self.documentID = documentID
        self.id = documentID ?? "new-\(UUID().uuidString)"
    }
}

/// Library documents and every file sent to or made in chats, in one place. A full-screen cover.
struct ChatDocumentsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    private let debug: ChatDocsDebug
    private let docs = LibraryDocumentsStore.shared
    private let chats = ChatDocsStore.shared
    private let live = DocsLiveStore.shared

    @State private var toaster = FilesToaster()
    @State private var query = ""
    @State private var viewing: ChatDocsViewing?
    @State private var editing: ChatDocsEditing?
    @State private var importing = false
    @State private var importStatus: String?
    @State private var liveViewing: DocsLiveViewing?
    /// Paired: the desktop's text search, id to snippet, for the current query.
    @State private var searchHits: [String: String] = [:]
    @State private var searchState: DocsLiveSearchState = .idle
    /// Paired: an import whose answer never arrived lives in the store, so closing this screen cannot lose it.
    @State private var importProblem: String?
    @State private var checkingImport = false
    @State private var openingChat = false

    init(debug: ChatDocsDebug = .none) {
        self.debug = debug
        _query = State(initialValue: debug == .search ? "launch" : "")
    }

    // MARK: - What is shown

    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searching: Bool { !needle.isEmpty }

    private var paired: Bool { DocsLiveStore.paired }
    private var allDocuments: [LibraryDocument] { paired ? live.documents : (debug == .empty ? [] : docs.documents) }
    private var allGroups: [ChatDocsGroup] { paired ? live.groups : (debug == .empty ? [] : chats.groups) }

    private var shownDocuments: [LibraryDocument] {
        guard searching else { return allDocuments }
        if paired {
            // Every title match, plus the desktop's own text search (it sends at most five).
            return allDocuments.filter { $0.title.localizedCaseInsensitiveContains(needle) || searchHits[$0.id] != nil }
        }
        return allDocuments.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || $0.body.localizedCaseInsensitiveContains(needle)
        }
    }

    private var importBusy: Bool { importStatus != nil || live.pendingImport != nil }

    private func isOpen(_ group: ChatDocsGroup) -> Bool {
        searching || (paired ? live.openGroups.contains(group.id) : chats.openGroups.contains(group.id))
    }

    private func toggleGroup(_ id: String) {
        if paired {
            if live.openGroups.contains(id) { live.openGroups.remove(id) } else { live.openGroups.insert(id) }
        } else {
            chats.toggle(id)
        }
    }

    private var shownGroups: [ChatDocsGroup] {
        guard searching else { return allGroups }
        return allGroups.compactMap { group in
            if group.title.localizedCaseInsensitiveContains(needle) { return group }
            let files = group.files.filter { $0.name.localizedCaseInsensitiveContains(needle) }
            if files.isEmpty { return nil }
            var trimmed = group
            trimmed.files = files
            return trimmed
        }
    }

    private var fileTotal: Int { allGroups.reduce(0) { $0 + $1.files.count } }
    private var documentsOpen: Bool { searching || chats.documentsOpen }
    private var filesOpen: Bool { searching || chats.filesOpen }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FilesSearchField(text: $query, prompt: "Search documents and chat files")
                    .arrives(0)
                actions
                    .arrives(1)
                if let importStatus {
                    importLine(importStatus)
                }
                if paired, live.pendingImport != nil {
                    DocsLiveLine(text: importProblem ?? "Your desktop did not confirm the import of \(live.pendingImportName).",
                                 action: checkingImport ? nil : "Check again") { checkImport() }
                } else if paired, let importProblem {
                    DocsLiveLine(text: importProblem)
                }
                documentsSection
                    .arrives(2)
                filesSection
                    .arrives(3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .kScreen()
        .filesToasts(toaster)
        .animation(Motion.snappy, value: needle)
        .fileImporter(isPresented: $importing, allowedContentTypes: ChatDocsImport.types) { result in
            handleImport(result)
        }
        .sheet(item: $viewing) { item in
            DocumentViewer(documents: item.documents, index: item.index)
                .kSheet()
        }
        .sheet(item: $liveViewing) { item in
            DocsLiveViewer(files: item.files, index: item.index)
                .kSheet()
        }
        .task(id: DocsLiveStore.connectionKey) {
            guard paired else { return }
            await live.loadAll()
        }
        .task(id: paired ? needle : "") {
            searchHits = [:]
            searchState = .idle
            guard paired, !needle.isEmpty else { return }
            let asked = needle
            searchState = .searching
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let hits = await live.search(asked)
            guard !Task.isCancelled, asked == needle else { return }
            if let hits {
                searchHits = hits
                searchState = .done(capped: hits.count >= 5)
            } else {
                searchState = .failed
            }
        }
        .onChange(of: editing == nil) {
            // Back from the editor: the desktop's list is read again.
            if editing == nil, paired { Task { await live.loadDocuments() } }
        }
        .fullScreenCover(item: $editing) { item in
            LibraryDocumentEditor(documentID: item.documentID)
                .environment(toaster)
        }
    }

    private var header: some View {
        FilesHeader(
            title: "Chat documents",
            subtitle: "\(NotesCopy.count(allDocuments.count, "document")) · \(NotesCopy.count(fileTotal, "chat file"))",
            backSymbol: "chevron.down",
            backLabel: "Close",
            back: { if paired && importStatus != nil { toaster.say("Wait until your desktop answers.") } else { dismiss() } }
        ) {
            GlassIconButton(symbol: "arrow.up.doc", label: "Upload a document") { startImport() }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            ActionTile(symbol: "square.and.pencil", title: "New document") {
                editing = ChatDocsEditing(documentID: nil)
            }
            ActionTile(symbol: "square.and.arrow.down", title: "Import from file") {
                startImport()
            }
            .disabled(paired && importBusy)
        }
    }

    private func importLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(Palette.goldText)
            Text(text)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }

    // MARK: - Documents

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChatDocsSectionHeader(
                title: "Documents",
                detail: "Notes and drafts saved to your Library",
                count: shownDocuments.count,
                open: documentsOpen
            ) {
                chats.documentsOpen.toggle()
            }
            if documentsOpen {
                documentsBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Paired: one line above the documents when the list may be out of date, or the search is partial.
    private var documentsNote: DocsLiveLine? {
        if let stale = live.docsStale {
            return DocsLiveLine(text: stale, action: "Try again") { Task { await live.loadDocuments() } }
        }
        guard searching else { return nil }
        switch searchState {
        case .failed:
            return DocsLiveLine(text: "Your desktop's text search did not answer, so only titles are matched here.")
        case .done(capped: true):
            return DocsLiveLine(text: "Your desktop sends at most five text matches, so some documents that match may not be listed.")
        default:
            return nil
        }
    }

    @ViewBuilder
    private var documentsBody: some View {
        if paired, let note = documentsNote {
            VStack(alignment: .leading, spacing: 8) {
                note
                documentsList
            }
        } else {
            documentsList
        }
    }

    @ViewBuilder
    private var documentsList: some View {
        let list = shownDocuments
        if paired, allDocuments.isEmpty, live.docsLoad != .loaded {
            if case .failed(let why) = live.docsLoad {
                DocsLiveLine(text: why, action: "Try again") { Task { await live.loadDocuments() } }
            } else {
                DocsLiveLine(text: "Reading your documents…")
            }
        } else if allDocuments.isEmpty {
            FilesEmpty(symbol: "doc.text", title: "No documents yet", detail: "Write a note or a draft here, or import a text file.", action: "Create a document") {
                editing = ChatDocsEditing(documentID: nil)
            }
            .kCard(radius: 20)
        } else if list.isEmpty, paired, searchState == .searching {
            DocsLiveLine(text: "Searching your documents…")
        } else if list.isEmpty {
            FilesEmpty(symbol: "magnifyingglass", title: "No documents match", detail: "Nothing matches \"\(needle)\". Chat files are listed below.")
                .kCard(radius: 20)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, document in
                    ChatDocsDocumentRow(document: document, query: needle, last: index == list.count - 1,
                                        snippet: paired ? searchHits[document.id] : nil) {
                        Haptics.tap()
                        editing = ChatDocsEditing(documentID: document.id)
                    }
                }
            }
            .kCard(radius: 20)
        }
    }

    // MARK: - Files by chat

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChatDocsSectionHeader(
                title: "Files by chat",
                detail: "Attachments and files created in conversations",
                count: shownGroups.reduce(0) { $0 + $1.files.count },
                open: filesOpen
            ) {
                chats.filesOpen.toggle()
            }
            if filesOpen {
                filesBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var filesBody: some View {
        if paired, let stale = live.filesStale {
            VStack(alignment: .leading, spacing: 8) {
                DocsLiveLine(text: stale, action: "Try again") { Task { await live.loadFiles() } }
                filesList
            }
        } else {
            filesList
        }
    }

    @ViewBuilder
    private var filesList: some View {
        let groups = shownGroups
        if paired, allGroups.isEmpty, live.filesLoad != .loaded {
            if case .failed(let why) = live.filesLoad {
                DocsLiveLine(text: why, action: "Try again") { Task { await live.loadFiles() } }
            } else {
                DocsLiveLine(text: "Reading your chat files…")
            }
        } else if groups.isEmpty {
            FilesEmpty(
                symbol: "bubble.left.and.text.bubble.right",
                title: allGroups.isEmpty ? "No chat files yet" : "No chat files match",
                detail: "Files sent to or created in chats will appear here.",
                action: "Open chats"
            ) {
                dismiss()
                router.select(.home)
            }
            .kCard(radius: 20)
        } else {
            VStack(spacing: 10) {
                ForEach(groups) { group in
                    ChatDocsGroupCard(
                        group: group,
                        open: isOpen(group),
                        toggle: { toggleGroup(group.id) },
                        openFile: { file in showFile(file, in: group) },
                        openChat: { openChat(group.id) }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func showFile(_ file: ChatDocsFile, in group: ChatDocsGroup) {
        if paired {
            let refs = group.files.compactMap { DocsLiveStore.ref($0, in: group) }
            guard let index = refs.firstIndex(where: { $0.id == file.id }) else { return }
            Haptics.tap()
            liveViewing = DocsLiveViewing(files: refs, index: index)
            return
        }
        let available = group.files.filter(\.available)
        guard let index = available.firstIndex(where: { $0.id == file.id }) else { return }
        Haptics.tap()
        let documents: [ChatDocument] = available.enumerated().map { offset, item in
            ChatDocument(id: item.id, name: item.name, label: "\(item.kind) \(offset + 1)", details: [item.ext.uppercased(), item.size, item.origin.label], look: item.look)
        }
        viewing = ChatDocsViewing(documents: documents, index: index)
    }

    private func openChat(_ conversationID: String) {
        if paired {
            guard !openingChat else { return }
            openingChat = true
            Task {
                let problem = await live.chatProblem(conversationID)
                openingChat = false
                if let problem {
                    toaster.say(problem)
                    return
                }
                dismiss()
                router.paths[.home] = []
                router.push(.chat(conversationID), on: .home)
            }
            return
        }
        let conversation = SampleData.conversation(conversationID)
        dismiss()
        router.open(conversation)
    }

    private func startImport() {
        guard !(paired && importBusy) else { return }
        Haptics.tap()
        importing = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            toaster.say("Import failed: \(error.localizedDescription)")
        case .success(let url) where paired:
            importLive(url)
        case .success(let url):
            let name = url.lastPathComponent
            withAnimation(Motion.snappy) { importStatus = "Importing \(name)…" }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                let outcome = ChatDocsImport.read(url)
                withAnimation(Motion.snappy) { importStatus = nil }
                switch outcome {
                case .success(let text):
                    let document = docs.importText(name: name, text: text)
                    Haptics.success()
                    toaster.say("Imported \(name)")
                    editing = ChatDocsEditing(documentID: document.id)
                case .failure(let error):
                    toaster.say("Import failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Paired import

    /// Import to the desktop: sent once. A lost answer is looked for on the desktop before Import is offered again.
    private func importLive(_ url: URL) {
        guard !importBusy else { return }
        let name = url.lastPathComponent
        importProblem = nil
        withAnimation(Motion.snappy) { importStatus = "Importing \(name)…" }
        Task {
            let read = await Task.detached(priority: .userInitiated) { DocsLiveImportFile.read(url, name: name) }.value
            let text: String
            switch read {
            case .text(let value):
                text = value
            case .problem(let why):
                withAnimation(Motion.snappy) { importStatus = nil }
                importProblem = why
                return
            }
            let title = DocsWire.importTitle(name)
            if let lost = live.lostImport {
                // The last import may have landed late: look for it before anything new is sent.
                let lostName = live.lostImportName
                switch await live.findCreated(lost) {
                case .made(let doc):
                    live.lostImport = nil
                    if lost.title == title && lost.content == text {
                        withAnimation(Motion.snappy) { importStatus = nil }
                        importFinished(.made(doc), name: name)
                        return
                    }
                    toaster.say("\(lostName) did reach your desktop")
                case .notFound:
                    live.lostImport = nil
                case let other:
                    withAnimation(Motion.snappy) { importStatus = nil }
                    importFinished(other, name: lostName)
                    return
                }
            }
            let outcome = await live.create(title: title, content: text, importing: name)
            withAnimation(Motion.snappy) { importStatus = nil }
            importFinished(outcome, name: name)
        }
    }

    private func importFinished(_ outcome: DocsLiveCreateOutcome, name: String) {
        switch outcome {
        case .made(let doc):
            live.pendingImport = nil
            importProblem = nil
            Haptics.success()
            toaster.say("Imported \(name)")
            editing = ChatDocsEditing(documentID: doc.id)
        case .refused(let why):
            live.pendingImport = nil
            importProblem = "\(name) was not imported. " + why
        case .unconfirmed(let pending, let why):
            live.pendingImport = pending
            live.pendingImportName = name
            importProblem = why
        case .notFound(let pending, let why):
            live.pendingImport = nil
            live.lostImport = pending
            live.lostImportName = name
            importProblem = "\(name) was not confirmed. " + why
        }
    }

    private func checkImport() {
        guard let waiting = live.pendingImport, !checkingImport else { return }
        checkingImport = true
        let name = live.pendingImportName
        Task {
            let outcome = await live.findCreated(waiting)
            checkingImport = false
            importFinished(outcome, name: name)
        }
    }
}

/// What reading a picked file for the desktop gave.
nonisolated enum DocsLiveImportRead: Sendable {
    case text(String)
    case problem(String)
}

/// Reading a picked text file to import it to the paired desktop: off the main actor, with a size cap, and
/// a plain sentence for a file that is too large or is not UTF-8 text.
nonisolated enum DocsLiveImportFile {
    static let maxBytes = 5 * 1024 * 1024

    static func read(_ url: URL, name: String) -> DocsLiveImportRead {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let tooLarge = DocsLiveImportRead.problem(
            "\(name) was not imported. Files over 5 MB cannot be imported from this iPhone; import it on your desktop.")
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes { return tooLarge }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return .problem("\(name) was not imported. It could not be read on this iPhone.")
        }
        guard data.count <= maxBytes else { return tooLarge }
        if let text = String(data: data, encoding: .utf8) { return .text(text) }
        // UTF-16 only with its byte-order mark, so other text is never guessed at.
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            return .text(text)
        }
        return .problem("\(name) was not imported. It is not UTF-8 text; save it as UTF-8 and import it again.")
    }
}

/// Reading a picked text file.
nonisolated enum ChatDocsImport {
    static var types: [UTType] {
        [UTType.plainText] + [UTType(filenameExtension: "md")].compactMap { $0 }
    }

    static func read(_ url: URL) -> Result<String, Error> {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            return .success(try String(contentsOf: url, encoding: .utf8))
        } catch {
            return .failure(error)
        }
    }
}
