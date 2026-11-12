import SwiftUI

nonisolated enum DocSaveState: Hashable, Sendable {
    case idle, saving, saved
}

nonisolated enum DocEditorField: Hashable, Sendable {
    case title, text
}

/// The Library document editor, a full-screen cover: a title, a comfortable text area, Save, and Delete.
/// Leaving with unsaved changes asks first. Pass nil to start a new "Untitled" document.
struct LibraryDocumentEditor: View {
    @Environment(\.dismiss) private var dismiss
    /// The screen that opened the editor, if it shows toasts, so "Document deleted" outlives the editor.
    @Environment(FilesToaster.self) private var outerToaster: FilesToaster?

    @State private var toaster = FilesToaster()
    @State private var documentID: String?
    @State private var title = ""
    @State private var text = ""
    @State private var savedTitle = ""
    @State private var savedText = ""
    @State private var saveState: DocSaveState = .idle
    @State private var loaded = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @FocusState private var field: DocEditorField?

    private let store = LibraryDocumentsStore.shared

    init(documentID: String?) {
        _documentID = State(initialValue: documentID)
    }

    private var dirty: Bool {
        loaded && (title != savedTitle || text != savedText)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                titleField
                Palette.line.frame(height: 1)
                    .padding(.vertical, 6)
                textArea
            }
            .padding(.horizontal, 18)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .kScreen()
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { field = nil }
                        .font(KFont.ui(16, .semibold))
                        .foregroundStyle(Palette.goldText)
                }
            }
        }
        .filesToasts(toaster)
        .interactiveDismissDisabled(dirty)
        .onAppear(perform: load)
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .confirmationDialog("Delete this document?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteDocument)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Parts

    private var header: some View {
        FilesHeader(title: "Library", subtitle: status, backSymbol: "chevron.down", backLabel: "Back to Library", back: leave) {
            Menu {
                Button("Delete document", systemImage: "trash", role: .destructive) {
                    confirmDelete = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .kGlass(Circle(), interactive: true)
            .accessibilityLabel("More")
        }
    }

    private var status: String {
        switch saveState {
        case .saving: return "Saving…"
        case .saved where !dirty: return "All changes saved"
        default: return dirty ? "Unsaved changes" : "Document"
        }
    }

    private var titleField: some View {
        TextField("Title", text: $title)
            .font(KFont.ui(26, .semibold, relativeTo: .title))
            .foregroundStyle(Palette.ink)
            .focused($field, equals: .title)
            .submitLabel(.next)
            .onSubmit { field = .text }
            .frame(minHeight: 52)
            .accessibilityLabel("Document title")
    }

    private var textArea: some View {
        TextEditor(text: $text)
            .font(KFont.ui(17))
            .foregroundStyle(Palette.ink)
            .lineSpacing(5)
            .scrollContentBackground(.hidden)
            .focused($field, equals: .text)
            .frame(maxWidth: .infinity, minHeight: field == .text ? 120 : 340, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Start writing")
                        .font(KFont.ui(17))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Document text")
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text(NotesCopy.count(DocSnippet.words(text), "word"))
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .contentTransition(.numericText())
                .padding(.leading, 18)
            Spacer()
            saveButton
        }
        .padding(6)
        .kGlass(Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var saveButton: some View {
        let enabled = dirty && saveState != .saving
        let label = saveLabel
        return Button(action: save) {
            Text(label)
                .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                .foregroundStyle(enabled ? Palette.onGold : Palette.inkFaint)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(enabled ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Capsule())
                .contentTransition(.opacity)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .keyboardShortcut("s", modifiers: .command)
        .animation(Motion.snappy, value: label)
    }

    private var saveLabel: String {
        if saveState == .saving { return "Saving…" }
        if dirty { return "Save" }
        return saveState == .saved ? "All changes saved" : "Save"
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        let document: LibraryDocument
        if let id = documentID, let found = store.document(id) {
            document = found
        } else {
            document = store.create()
            documentID = document.id
        }
        title = document.title
        text = document.body
        savedTitle = document.title
        savedText = document.body
        loaded = true
    }

    private func leave() {
        if dirty {
            Haptics.tap()
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        guard dirty, saveState != .saving, let id = documentID else { return }
        Haptics.tap()
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? "Untitled" : title
        let snapshot = text
        withAnimation(Motion.snappy) { saveState = .saving }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            store.save(LibraryDocument(id: id, title: finalTitle, body: snapshot, updated: .now))
            withAnimation(Motion.snappy) {
                if cleanTitle.isEmpty { title = finalTitle }
                savedTitle = finalTitle
                savedText = snapshot
                saveState = .saved
            }
            Haptics.success()
            toaster.say("Document saved")
        }
    }

    private func deleteDocument() {
        guard let id = documentID else { return }
        Haptics.thud()
        store.delete(id: id)
        // Nothing is left to save, so leaving is safe.
        savedTitle = title
        savedText = text
        if let outerToaster {
            outerToaster.say("Document deleted")
            dismiss()
        } else {
            toaster.say("Document deleted")
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                dismiss()
            }
        }
    }
}
