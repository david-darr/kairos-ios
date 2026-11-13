import SwiftUI
import UniformTypeIdentifiers

/// Files uploaded from this phone, in a full-screen cover: sort, search, upload, share, rename and delete.
/// Paired, it lists the files sent to the desktop's chats (the desktop keeps uploads with their chat and has
/// no list, rename or delete of its own), opens them, and shares them from the viewer.
struct UploadsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    private let store = UploadsStore.shared
    private let live = DocsLiveStore.shared

    @State private var toaster = FilesToaster()
    @State private var query = ""
    @State private var picking = false
    @State private var renaming: UploadedFile?
    @State private var newName = ""
    @State private var deleting: UploadedFile?
    @State private var liveViewing: DocsLiveViewing?
    @State private var openingChat = false

    init() {}

    private var paired: Bool { DocsLiveStore.paired }

    /// Paired: every file sent to a chat, in the screen's shape, with where it came from.
    private var liveUploads: [String: (file: ChatDocsFile, group: ChatDocsGroup)] {
        Dictionary(live.uploads.map { ($0.file.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var liveFiles: [UploadedFile] {
        live.uploads.map { item in
            let name = item.file.name
            return UploadedFile(id: item.file.id, name: (name as NSString).deletingPathExtension,
                                ext: (name as NSString).pathExtension, bytes: item.file.bytes,
                                added: item.file.added ?? .distantPast)
        }
    }

    private var allFiles: [UploadedFile] { paired ? liveFiles : store.files }

    private var shown: [UploadedFile] {
        paired ? UploadsStore.sorted(liveFiles, matching: query, by: store.sort) : store.shown(matching: query)
    }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FilesSearchField(text: $query, prompt: "Search uploads")
                    .arrives(0)
                toolbarRow
                    .arrives(1)
                content
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
        .animation(Motion.snappy, value: store.files)
        .animation(Motion.snappy, value: store.sort)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handlePick(result)
        }
        .alert("Rename file", isPresented: renamingShown) {
            TextField("Name", text: $newName)
            Button("Rename", action: rename)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The extension stays the same.")
        }
        .sheet(item: $deleting) { file in
            ConfirmSheet(title: "Delete \(file.fileName)?", detail: "This can't be undone.", confirm: "Delete file") {
                deleteFile(file)
            }
        }
        .sheet(item: $liveViewing) { item in
            DocsLiveViewer(files: item.files, index: item.index)
                .kSheet()
        }
        .task(id: DocsLiveStore.connectionKey) {
            guard paired else { return }
            await live.loadAll()
        }
    }

    // MARK: - Parts

    private var header: some View {
        FilesHeader(
            title: "Uploads",
            subtitle: NotesCopy.count(allFiles.count, "file"),
            backSymbol: "chevron.down",
            backLabel: "Close",
            back: { dismiss() }
        ) {
            if !paired {
                GlassIconButton(symbol: "arrow.up.doc", label: "Upload files") { startPick() }
            }
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            Text(countLine)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
            Spacer()
            Menu {
                Picker("Sort uploads", selection: sortBinding) {
                    ForEach(UploadsSort.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                    Text(store.sort.rawValue)
                        .font(KFont.ui(14, .medium, relativeTo: .footnote))
                }
                .foregroundStyle(Palette.goldText)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Sort uploads")
            .accessibilityValue(store.sort.rawValue)
        }
    }

    @ViewBuilder
    private var content: some View {
        if paired {
            liveContent
        } else {
            sampleContent
        }
    }

    @ViewBuilder
    private var liveContent: some View {
        let list = shown
        let lookup = liveUploads
        HintLine(text: "These are the files sent to your chats. To upload a file, attach it to a chat message. Your desktop cannot rename or delete them.")
            .padding(.horizontal, 4)
        if live.groups.isEmpty, live.filesLoad != .loaded {
            if case .failed(let why) = live.filesLoad {
                DocsLiveLine(text: why, action: "Try again") { Task { await live.loadFiles() } }
            } else {
                DocsLiveLine(text: "Reading your uploads…")
            }
        } else if liveFiles.isEmpty {
            FilesEmpty(symbol: "arrow.up.doc", title: "No uploads yet", detail: "Files you send in a chat appear here.")
                .kCard(radius: 20)
        } else if list.isEmpty {
            FilesEmpty(symbol: "magnifyingglass", title: "No matches", detail: "Try another name.", action: "Clear search") {
                query = ""
            }
            .kCard(radius: 20)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, file in
                    if let item = lookup[file.id] {
                        UploadsLiveRow(file: item.file, chat: item.group.title, last: index == list.count - 1,
                                       open: { openLive(file.id, in: list) },
                                       openChat: { openChat(item.group.id) })
                            .arrives(index + 2)
                    }
                }
            }
            .kCard(radius: 20)
        }
    }

    @ViewBuilder
    private var sampleContent: some View {
        let list = shown
        if store.files.isEmpty {
            FilesEmpty(symbol: "arrow.up.doc", title: "No uploads yet", detail: "Files you upload from this phone appear here.", action: "Upload files") {
                startPick()
            }
            .kCard(radius: 20)
        } else if list.isEmpty {
            FilesEmpty(symbol: "magnifyingglass", title: "No matches", detail: "Try another name.", action: "Clear search") {
                query = ""
            }
            .kCard(radius: 20)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, file in
                    UploadsRow(file: file, last: index == list.count - 1) { action in
                        handle(action, on: file)
                    }
                    .arrives(index + 2)
                }
            }
            .kCard(radius: 20)
        }
    }

    // MARK: - Bindings

    private var sortBinding: Binding<UploadsSort> {
        Binding(get: { store.sort }, set: { value in
            Haptics.select()
            store.sort = value
        })
    }

    private var renamingShown: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var countLine: String {
        guard searching else { return "Sorted by \(store.sort.rawValue.lowercased())" }
        let count = shown.count
        return count == 1 ? "1 match" : "\(count) matches"
    }

    // MARK: - Actions

    private func handle(_ action: UploadsRowAction, on file: UploadedFile) {
        switch action {
        case .rename:
            newName = file.name
            renaming = file
        case .delete:
            deleting = file
        }
    }

    private func rename() {
        guard let file = renaming else { return }
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !clean.isEmpty, clean != file.name else { return }
        store.rename(file.id, to: clean)
        Haptics.success()
        toaster.say("Renamed to \(clean)")
    }

    private func deleteFile(_ file: UploadedFile) {
        guard !paired else { return }
        deleting = nil
        Haptics.thud()
        store.delete(file.id)
        toaster.say("Deleted \(file.fileName)")
    }

    private func openLive(_ id: String, in list: [UploadedFile]) {
        let lookup = liveUploads
        let refs = list.compactMap { file in lookup[file.id].flatMap { DocsLiveStore.ref($0.file, in: $0.group) } }
        guard let index = refs.firstIndex(where: { $0.id == id }) else { return }
        Haptics.tap()
        liveViewing = DocsLiveViewing(files: refs, index: index)
    }

    private func openChat(_ sessionID: String) {
        guard !openingChat else { return }
        openingChat = true
        Task {
            let problem = await live.chatProblem(sessionID)
            openingChat = false
            if let problem {
                toaster.say(problem)
                return
            }
            dismiss()
            router.paths[.home] = []
            router.push(.chat(sessionID), on: .home)
        }
    }

    private func startPick() {
        guard !paired else { return }
        Haptics.tap()
        picking = true
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            toaster.say("Upload failed: \(error.localizedDescription)")
        case .success(let urls):
            guard !urls.isEmpty else { return }
            for url in urls {
                let picked = UploadsPick.read(url)
                store.add(name: picked.name, ext: picked.ext, bytes: picked.bytes)
            }
            Haptics.success()
            if urls.count == 1, let first = urls.first {
                toaster.say("Uploaded \(first.lastPathComponent)")
            } else {
                toaster.say("Uploaded \(urls.count) files")
            }
        }
    }
}

/// The name, extension and size of a picked file.
nonisolated enum UploadsPick {
    static func read(_ url: URL) -> (name: String, ext: String, bytes: Int) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return (url.deletingPathExtension().lastPathComponent, url.pathExtension, size)
    }
}

/// One file sent to a chat on the paired desktop: type, name, size, date and chat. Tap opens it;
/// long-press opens its chat.
struct UploadsLiveRow: View {
    let file: ChatDocsFile
    let chat: String
    let last: Bool
    let open: () -> Void
    let openChat: () -> Void

    private var detail: String {
        guard file.available else { return "No longer available · \(chat)" }
        var parts: [String] = []
        if file.sizeKnown { parts.append(file.size) }
        if let added = file.added { parts.append(FilesDates.short(added)) }
        parts.append(chat)
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                TypeBadge(text: file.ext.isEmpty ? "File" : file.ext, tint: file.available ? Palette.goldText : Palette.inkFaint)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                        .foregroundStyle(file.available ? Palette.ink : Palette.inkFaint)
                        .lineLimit(1)
                    Text(detail)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if file.available {
                    Image(systemName: "eye")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Palette.line.frame(height: 1).padding(.leading, 74) }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .disabled(!file.available)
        .contextMenu {
            Button("Open chat", systemImage: "bubble.left.and.bubble.right", action: openChat)
        }
        .accessibilityHint(file.available ? "Opens the file" : "")
    }
}

enum UploadsRowAction {
    case rename, delete
}

/// One upload: its type, name, size and date, with Share, Rename and Delete on a long press or the ... button.
struct UploadsRow: View {
    let file: UploadedFile
    let last: Bool
    let act: (UploadsRowAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            TypeBadge(text: file.ext.isEmpty ? "File" : file.ext)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("\(file.size) · \(FilesDates.short(file.added))")
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.inkDim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(file.fileName)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 74) }
        }
        .contextMenu { menuItems }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var menuItems: some View {
        ShareLink(item: file.fileName) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button("Rename", systemImage: "pencil") { act(.rename) }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { act(.delete) }
    }
}
