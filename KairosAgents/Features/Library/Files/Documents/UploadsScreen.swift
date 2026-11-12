import SwiftUI
import UniformTypeIdentifiers

/// Files uploaded from this phone, in a full-screen cover: sort, search, upload, share, rename and delete.
struct UploadsScreen: View {
    @Environment(\.dismiss) private var dismiss

    private let store = UploadsStore.shared

    @State private var toaster = FilesToaster()
    @State private var query = ""
    @State private var picking = false
    @State private var renaming: UploadedFile?
    @State private var newName = ""
    @State private var deleting: UploadedFile?

    init() {}

    private var shown: [UploadedFile] { store.shown(matching: query) }
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
        .confirmationDialog(deleteTitle, isPresented: deletingShown, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteFile)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Parts

    private var header: some View {
        FilesHeader(
            title: "Uploads",
            subtitle: NotesCopy.count(store.files.count, "file"),
            backSymbol: "chevron.down",
            backLabel: "Close",
            back: { dismiss() }
        ) {
            GlassIconButton(symbol: "arrow.up.doc", label: "Upload files") { startPick() }
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

    private var deletingShown: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var countLine: String {
        guard searching else { return "Sorted by \(store.sort.rawValue.lowercased())" }
        let count = shown.count
        return count == 1 ? "1 match" : "\(count) matches"
    }

    private var deleteTitle: String {
        "Delete \(deleting?.fileName ?? "this file")?"
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

    private func deleteFile() {
        guard let file = deleting else { return }
        deleting = nil
        Haptics.thud()
        store.delete(file.id)
        toaster.say("Deleted \(file.fileName)")
    }

    private func startPick() {
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
