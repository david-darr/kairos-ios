import SwiftUI

nonisolated enum DocSaveState: Hashable, Sendable {
    case idle, saving, saved
}

nonisolated enum DocEditorField: Hashable, Sendable {
    case title, text
}

/// Where the paired desktop's copy of the open document stands.
nonisolated enum DocsLiveEditorState: Equatable, Sendable {
    case loading, ready, gone
    case failed(String)
}

/// What the last live save sent, kept to compare with the desktop when its answer is lost.
nonisolated struct DocsLiveSent: Equatable, Sendable {
    var title: String?
    var content: String?
}

/// The Library document editor, a full-screen cover: a title, a comfortable text area, Save, and Delete.
/// Leaving with unsaved changes asks first. Pass nil to start a new "Untitled" document.
/// Paired, it is a form over the desktop's document: it remembers the title and text it was filled from,
/// sends only what the person changed, and never replaces a newer desktop copy without saying so.
struct LibraryDocumentEditor: View {
    @Environment(\.dismiss) private var dismiss
    /// The screen that opened the editor, if it shows toasts, so "Document deleted" outlives the editor.
    @Environment(FilesToaster.self) private var outerToaster: FilesToaster?

    @State private var toaster = FilesToaster()
    @State private var documentID: String?
    @State private var title = ""
    @State private var text = ""
    /// What the form was filled from (the desktop's values when paired).
    @State private var savedTitle = ""
    @State private var savedText = ""
    @State private var saveState: DocSaveState = .idle
    @State private var loaded = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @FocusState private var field: DocEditorField?

    // Paired only.
    @State private var live = false
    @State private var liveState: DocsLiveEditorState = .ready
    @State private var problem: String?
    @State private var pendingCreate: DocsLivePendingCreate?
    @State private var unconfirmedSave: DocsLiveSent?
    @State private var unconfirmedDelete = false
    @State private var conflict: DocsLiveDoc?
    @State private var checking = false
    @State private var deleting = false

    private let store = LibraryDocumentsStore.shared
    private let docs = DocsLiveStore.shared

    init(documentID: String?) {
        _documentID = State(initialValue: documentID)
    }

    private var dirty: Bool {
        loaded && (title != savedTitle || text != savedText)
    }

    /// A write is on its way or its outcome is not known yet: nothing may send again, nothing may close.
    private var writing: Bool {
        saveState == .saving || deleting || checking || pendingCreate != nil || unconfirmedSave != nil || unconfirmedDelete
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if live, liveState != .ready {
                    liveLine
                        .padding(.top, 8)
                } else {
                    titleField
                    Palette.line.frame(height: 1)
                        .padding(.vertical, 6)
                    if live, let line = problemLine {
                        line.padding(.bottom, 6)
                    }
                    textArea
                }
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
        .interactiveDismissDisabled(dirty || writing)
        .onAppear(perform: load)
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .sheet(isPresented: $confirmDelete) {
            ConfirmSheet(title: "Delete \"\(deleteName)\"?", detail: "This can't be undone.", confirm: "Delete document") {
                deleteDocument()
            }
        }
        .alert("This document changed since you opened it", isPresented: conflictShown, presenting: conflict) { latest in
            Button("Copy my version") {
                UIPasteboard.general.string = text
                rebase(to: latest)
                toaster.say("Your version is copied")
            }
            Button("Reload their version") {
                title = latest.title.isEmpty ? "Untitled" : latest.title
                text = latest.content
                savedTitle = title
                savedText = text
                toaster.say("Loaded the latest version")
            }
            Button("Cancel", role: .cancel) { rebase(to: latest) }
        } message: { _ in
            Text("Someone saved it from another place. Keep a copy of yours, or load theirs. Your text stays here; saving again replaces theirs.")
        }
    }

    // MARK: - Parts

    private var deleteName: String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Untitled" : clean
    }

    private var conflictShown: Binding<Bool> {
        Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } })
    }

    private var header: some View {
        FilesHeader(title: "Library", subtitle: status, backSymbol: "chevron.down", backLabel: "Back to Library", back: leave) {
            if canDelete {
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
    }

    private var canDelete: Bool {
        guard live else { return true }
        return documentID != nil && liveState == .ready && !writing
    }

    private var status: String {
        if live {
            if deleting { return "Deleting…" }
            if checking { return "Checking your desktop…" }
            if pendingCreate != nil || unconfirmedSave != nil || unconfirmedDelete { return "Not confirmed" }
            if liveState == .loading { return "Opening…" }
        }
        switch saveState {
        case .saving: return "Saving…"
        case .saved where !dirty: return "All changes saved"
        default: return dirty ? "Unsaved changes" : "Document"
        }
    }

    @ViewBuilder
    private var liveLine: some View {
        switch liveState {
        case .loading: DocsLiveLine(text: "Opening your document…")
        case .gone: DocsLiveLine(text: "This document is not on your desktop any more.")
        case .failed(let why): DocsLiveLine(text: why, action: "Try again") { openLive() }
        case .ready: EmptyView()
        }
    }

    private var problemLine: DocsLiveLine? {
        if pendingCreate != nil || unconfirmedSave != nil || unconfirmedDelete {
            return DocsLiveLine(text: problem ?? "Your desktop did not confirm this.", action: checking ? nil : "Check again") { checkAgain() }
        }
        if let problem { return DocsLiveLine(text: problem) }
        return nil
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
        let enabled = dirty && saveState != .saving && !(live && (writing || liveState != .ready))
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
        if DocsLiveStore.paired {
            live = true
            if documentID == nil {
                // A new document is made on the desktop at its first save, so an empty one is never left behind.
                title = "Untitled"
                savedTitle = "Untitled"
                loaded = true
                liveState = .ready
            } else {
                openLive()
            }
            return
        }
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

    private func openLive() {
        guard let id = documentID else { return }
        liveState = .loading
        Task {
            switch await docs.read(id) {
            case .found(let doc):
                fill(doc)
                liveState = .ready
            case .gone:
                liveState = .gone
            case .failed(let why):
                liveState = .failed("This document could not be opened. " + why)
            }
        }
    }

    private func fill(_ doc: DocsLiveDoc) {
        documentID = doc.id
        title = doc.title.isEmpty ? "Untitled" : doc.title
        text = doc.content
        savedTitle = doc.title
        savedText = doc.content
        loaded = true
    }

    /// The desktop's copy becomes the form's base. A field the person has not touched follows it;
    /// a field they edited keeps their text and still counts as edited.
    private func rebase(to doc: DocsLiveDoc) {
        if title == savedTitle { title = doc.title }
        if text == savedText { text = doc.content }
        savedTitle = doc.title
        savedText = doc.content
    }

    /// The desktop answered this save: untouched-since-sending fields follow it, the base becomes it.
    private func settle(_ doc: DocsLiveDoc, sentTitle: String?, sentText: String?) {
        if let sentTitle, title == sentTitle { title = doc.title }
        if sentTitle == nil, title == savedTitle { title = doc.title }
        if let sentText, text == sentText { text = doc.content }
        if sentText == nil, text == savedText { text = doc.content }
        savedTitle = doc.title
        savedText = doc.content
    }

    private func leave() {
        // A write in flight keeps the editor open. An unconfirmed one may be left: the text is unsaved, so the
        // discard prompt says so first.
        if live && (saveState == .saving || deleting || checking) {
            toaster.say("Wait until your desktop answers.")
            return
        }
        if live && (pendingCreate != nil || unconfirmedSave != nil) {
            Haptics.tap()
            confirmDiscard = true
            return
        }
        if dirty {
            Haptics.tap()
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        if live {
            saveLive()
            return
        }
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

    private func saveLive() {
        guard dirty, !writing, liveState == .ready else { return }
        Haptics.tap()
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? "Untitled" : title
        problem = nil
        withAnimation(Motion.snappy) { saveState = .saving }
        guard let id = documentID else {
            let sentText = text
            let typed = title
            Task {
                let outcome = await docs.create(title: finalTitle, content: sentText)
                saveState = .idle
                createFinished(outcome, sentTitle: typed, sentText: sentText)
            }
            return
        }
        let sent = DocsLiveSent(title: title != savedTitle ? finalTitle : nil, content: text != savedText ? text : nil)
        let typedTitle = title
        let filledTitle = savedTitle
        let filledText = savedText
        Task {
            let outcome = await docs.save(id, title: sent.title, content: sent.content, filledTitle: filledTitle, filledContent: filledText)
            withAnimation(Motion.snappy) { saveState = .idle }
            switch outcome {
            case .saved(let doc):
                if sent.title != nil, title == typedTitle { title = finalTitle }
                settle(doc, sentTitle: sent.title, sentText: sent.content)
                withAnimation(Motion.snappy) { saveState = .saved }
                Haptics.success()
                toaster.say("Document saved")
            case .conflict(let latest):
                conflict = latest
            case .gone:
                problem = "This document is not on your desktop any more, so your change was not saved. Your text is still here; copy it to keep it."
            case .failed(let why):
                problem = why
            case .unconfirmed(let why):
                problem = why
                unconfirmedSave = sent
            case .busy:
                problem = "Wait for the last change to finish, then save again."
            }
        }
    }

    private func createFinished(_ outcome: DocsLiveCreateOutcome, sentTitle: String, sentText: String) {
        switch outcome {
        case .made(let doc):
            pendingCreate = nil
            problem = nil
            documentID = doc.id
            settle(doc, sentTitle: sentTitle, sentText: sentText)
            saveState = .saved
            Haptics.success()
            toaster.say("Document saved")
        case .refused(let why):
            pendingCreate = nil
            problem = why
        case .unconfirmed(let pending, let why):
            pendingCreate = pending
            problem = why
        }
    }

    /// The answer to the last write was lost: read the desktop and show what it really has.
    private func checkAgain() {
        guard !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            if let pending = pendingCreate {
                let outcome = await docs.findCreated(pending)
                createFinished(outcome, sentTitle: title, sentText: pending.content)
                return
            }
            if unconfirmedDelete, let id = documentID {
                switch await docs.read(id) {
                case .gone:
                    unconfirmedDelete = false
                    finishDelete()
                case .found:
                    unconfirmedDelete = false
                    problem = "This document was not deleted."
                case .failed(let why):
                    problem = "Your desktop still could not be read. " + why
                }
                return
            }
            if let sent = unconfirmedSave, let id = documentID {
                switch await docs.read(id) {
                case .gone:
                    unconfirmedSave = nil
                    liveState = .ready
                    problem = "This document is not on your desktop any more. Your text is still here; copy it to keep it."
                case .failed(let why):
                    problem = "Your desktop still could not be read. " + why
                case .found(let now):
                    unconfirmedSave = nil
                    let titleSent = sent.title.map { now.title == $0 } ?? true
                    let textSent = sent.content.map { now.content == $0 } ?? true
                    if titleSent && textSent {
                        settle(now, sentTitle: sent.title, sentText: sent.content)
                        problem = nil
                        saveState = .saved
                        toaster.say("Document saved")
                    } else if (sent.title == nil || now.title == savedTitle) && (sent.content == nil || now.content == savedText) {
                        problem = "Your desktop did not get this save. Your text is still here. Save again."
                    } else {
                        problem = nil
                        conflict = now
                    }
                }
            }
        }
    }

    private func deleteDocument() {
        guard let id = documentID else { return }
        Haptics.thud()
        guard live else {
            store.delete(id: id)
            finishDelete()
            return
        }
        guard !writing else { return }
        deleting = true
        problem = nil
        Task {
            let outcome = await docs.delete(id)
            deleting = false
            switch outcome {
            case .deleted: finishDelete()
            case .failed(let why): problem = why
            case .unconfirmed(let why):
                problem = why
                unconfirmedDelete = true
            }
        }
    }

    private func finishDelete() {
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
