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

    @State private var toaster = FilesToaster()
    @State private var query = ""
    @State private var viewing: ChatDocsViewing?
    @State private var editing: ChatDocsEditing?
    @State private var importing = false
    @State private var importStatus: String?

    init(debug: ChatDocsDebug = .none) {
        self.debug = debug
        _query = State(initialValue: debug == .search ? "launch" : "")
    }

    // MARK: - What is shown

    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searching: Bool { !needle.isEmpty }

    private var allDocuments: [LibraryDocument] { debug == .empty ? [] : docs.documents }
    private var allGroups: [ChatDocsGroup] { debug == .empty ? [] : chats.groups }

    private var shownDocuments: [LibraryDocument] {
        guard searching else { return allDocuments }
        return allDocuments.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || $0.body.localizedCaseInsensitiveContains(needle)
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
            back: { dismiss() }
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

    @ViewBuilder
    private var documentsBody: some View {
        let list = shownDocuments
        if allDocuments.isEmpty {
            FilesEmpty(symbol: "doc.text", title: "No documents yet", detail: "Write a note or a draft here, or import a text file.", action: "Create a document") {
                editing = ChatDocsEditing(documentID: nil)
            }
            .kCard(radius: 20)
        } else if list.isEmpty {
            FilesEmpty(symbol: "magnifyingglass", title: "No documents match", detail: "Nothing matches \"\(needle)\". Chat files are listed below.")
                .kCard(radius: 20)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, document in
                    ChatDocsDocumentRow(document: document, query: needle, last: index == list.count - 1) {
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
        let groups = shownGroups
        if groups.isEmpty {
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
                        open: searching || chats.openGroups.contains(group.id),
                        toggle: { chats.toggle(group.id) },
                        openFile: { file in showFile(file, in: group) },
                        openChat: { openChat(group.id) }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func showFile(_ file: ChatDocsFile, in group: ChatDocsGroup) {
        let available = group.files.filter(\.available)
        guard let index = available.firstIndex(where: { $0.id == file.id }) else { return }
        Haptics.tap()
        let documents: [ChatDocument] = available.enumerated().map { offset, item in
            ChatDocument(id: item.id, name: item.name, label: "\(item.kind) \(offset + 1)", details: [item.ext.uppercased(), item.size, item.origin.label], look: item.look)
        }
        viewing = ChatDocsViewing(documents: documents, index: index)
    }

    private func openChat(_ conversationID: String) {
        let conversation = SampleData.conversation(conversationID)
        dismiss()
        router.open(conversation)
    }

    private func startImport() {
        Haptics.tap()
        importing = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            toaster.say("Import failed: \(error.localizedDescription)")
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
