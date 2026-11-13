import SwiftUI

/// The Notes section of Library: quick Kairos notes with optional due times.
/// Plain stacked content; LibraryView scrolls it. The notes, the sort and the search live in `NotesStore`,
/// because this view is made again each time the person switches sections.
struct LibraryNotesSection: View {
    @Environment(ChromeState.self) private var chrome
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let store: NotesStore
    private let start: NotesDebug?

    @State private var draft = ""
    @State private var hasDue = false
    @State private var draftDue = NotesDue.suggested()
    @State private var flipping: Set<String> = []
    @State private var sheet: NotesSheetItem?
    @State private var confirmClear = false
    @State private var deleting: KNote?
    @State private var started = false
    @FocusState private var captureFocused: Bool

    init() {
        self.init(store: .shared, start: nil)
    }

    /// For pictures and previews: a given store, opened in a given state.
    init(store: NotesStore, start: NotesDebug?) {
        self.store = store
        self.start = start
    }

    /// Showing the paired desktop's notes.
    private var live: Bool { !store.isSample }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NotesCaptureCard(draft: $draft, hasDue: $hasDue, due: $draftDue, focused: $captureFocused,
                             busy: live && store.adding, add: addDraft)
                .arrives(0)
            if live { liveLines }
            if !live || store.liveLoad == .loaded || !store.notes.isEmpty {
                stats
                    .arrives(1)
            }
            if live && store.notes.isEmpty && store.liveLoad != .loaded {
                // Still reading, or the read failed: the line above says which. Never "No notes yet".
                EmptyView()
            } else if store.notes.isEmpty {
                FilesEmpty(
                    symbol: "note.text",
                    title: "No notes yet",
                    detail: "Track priorities, todos, and reminders here. Anything with a due date also shows up on your Calendar.",
                    action: "Add your first note"
                ) {
                    captureFocused = true
                }
                .kCard(radius: 24)
                .arrives(2)
            } else {
                listHeader
                    .arrives(2)
                noteList
            }
        }
        .padding(.bottom, 12)
        .animation(reduceMotion ? nil : Motion.snappy, value: store.notes)
        .sheet(item: $sheet) { item in
            NotesDetailsSheet(store: store, item: item)
                .environment(chrome)
        }
        .confirmationDialog("Clear finished notes?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear finished", role: .destructive, action: clearFinished)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \(NotesCopy.count(store.finishedCount, "finished note"))? This can't be undone.")
        }
        .confirmationDialog("Delete this note?", isPresented: deletingShown, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let note = deleting { delete(note) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .onAppear(perform: applyStart)
        .task(id: NotesStore.connectionKey) {
            // Only the shared store follows the desktop; the debug pictures keep their own sample stores.
            guard store === NotesStore.shared else { return }
            store.followConnection()
            await store.loadLive()
        }
        .onChange(of: chrome.addTick) {
            if router.tab == .library { captureFocused = true }
        }
    }

    // MARK: - Parts

    /// Paired only: reading, a failed read, notes that could not be shown, and what last went wrong.
    @ViewBuilder
    private var liveLines: some View {
        switch store.liveLoad {
        case .idle, .loading:
            if store.notes.isEmpty { NotesLiveLine(text: "Reading your notes") }
        case .failed(let why):
            NotesLiveLine(text: why, action: "Try again") {
                Task { await store.loadLive() }
            }
        case .loaded:
            EmptyView()
        }
        if store.skipped > 0 {
            NotesLiveLine(text: "\(NotesCopy.count(store.skipped, "note")) could not be shown. Update this app to see \(store.skipped == 1 ? "it" : "them").")
        }
        if let problem = store.problem {
            NotesLiveLine(text: problem, action: "Dismiss") {
                withAnimation(Motion.snappy) { store.problem = nil }
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            NotesStatTile(symbol: "checkmark", value: store.finishedCount, label: "Finished")
            NotesStatTile(symbol: "calendar", value: store.dueThisWeek(), label: "Due this week")
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Open")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Spacer()
                sortMenu
            }
            FilesSearchField(text: queryBinding, prompt: "Search notes")
            HStack(spacing: 8) {
                Text("\(NotesCopy.count(store.notes.count, "note")) · \(store.finishedCount) finished")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .contentTransition(.numericText())
                Spacer()
                if store.finishedCount > 0 {
                    Button {
                        Haptics.tap()
                        confirmClear = true
                    } label: {
                        Label("Clear finished", systemImage: "trash")
                            .font(KFont.ui(14, .medium, relativeTo: .footnote))
                            .foregroundStyle(Palette.goldText)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .transition(.opacity)
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort notes", selection: sortBinding) {
                ForEach(NotesSort.allCases, id: \.self) { mode in
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
        .accessibilityLabel("Sort notes")
        .accessibilityValue(store.sort.rawValue)
    }

    @ViewBuilder
    private var noteList: some View {
        let open = store.shown(done: false)
        let finished = store.shown(done: true)
        let searching = !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if searching && open.isEmpty && finished.isEmpty {
            FilesEmpty(symbol: "magnifyingglass", title: "No matches", detail: "Try another word.", action: "Clear search") {
                store.query = ""
            }
        } else {
            VStack(spacing: 10) {
                if open.isEmpty {
                    Text("Nothing open. Add a note above.")
                        .font(KFont.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                ForEach(Array(open.enumerated()), id: \.element.id) { index, note in
                    card(note)
                        .arrives(index + 3)
                }
            }
            if !finished.isEmpty {
                FilesGroup(label: "Finished") {
                    VStack(spacing: 10) {
                        ForEach(finished) { note in
                            card(note)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func card(_ note: KNote) -> some View {
        NotesCard(
            note: note,
            showsDone: note.done != flipping.contains(note.id),
            canPin: !live,
            toggle: { toggle(note) },
            act: { action in handle(action, on: note) }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: - Bindings

    private var queryBinding: Binding<String> {
        Binding(get: { store.query }, set: { store.query = $0 })
    }

    private var sortBinding: Binding<NotesSort> {
        Binding(get: { store.sort }, set: { value in
            Haptics.select()
            withAnimation(Motion.snappy) { store.sort = value }
        })
    }

    private var deletingShown: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    // MARK: - Actions

    private func addDraft() {
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            captureFocused = true
            return
        }
        if live {
            addLive(clean)
            return
        }
        Haptics.success()
        withAnimation(Motion.snappy) {
            _ = store.add(text: clean, due: hasDue ? draftDue : nil)
            draft = ""
            hasDue = false
            draftDue = NotesDue.suggested()
        }
    }

    /// Sent once. The typed text and due time stay in the card until the desktop has the note.
    private func addLive(_ text: String) {
        guard !store.adding else { return }
        let due = hasDue ? draftDue : nil
        let sent = draft
        let store = store
        Task {
            let outcome = await store.createLive(text: text, due: due)
            switch outcome {
            case .saved:
                Haptics.success()
                withAnimation(Motion.snappy) {
                    // Only clear what was sent: anything typed since stays.
                    if draft == sent {
                        draft = ""
                        hasDue = false
                        draftDue = NotesDue.suggested()
                    }
                    store.problem = nil
                }
            case .busy:
                break
            case .failed(let why):
                Haptics.thud()
                withAnimation(Motion.snappy) { store.problem = why }
            }
        }
    }

    /// The strike-through shows at once; the note moves to its new group a moment later.
    private func toggle(_ note: KNote) {
        guard !flipping.contains(note.id) else { return }
        let target = !note.done
        if live {
            toggleLive(note, to: target)
            return
        }
        if target { Haptics.success() } else { Haptics.tap() }
        if reduceMotion {
            store.setDone(note.id, target)
            return
        }
        withAnimation(Motion.gentle) { _ = flipping.insert(note.id) }
        let id = note.id
        let store = store
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(Motion.snappy) {
                store.setDone(id, target)
                flipping.remove(id)
            }
        }
    }

    /// Paired: the strike-through shows at once, and goes back if the desktop does not save it.
    private func toggleLive(_ note: KNote, to target: Bool) {
        guard !store.busy.contains(note.id) else { return }
        if target { Haptics.success() } else { Haptics.tap() }
        let id = note.id
        let store = store
        let motion = !reduceMotion
        if motion {
            withAnimation(Motion.gentle) { _ = flipping.insert(id) }
        } else {
            flipping.insert(id)
        }
        let work = Task { await store.setDoneLive(id, target) }
        Task {
            if motion { try? await Task.sleep(for: .milliseconds(320)) }
            let result = await work.value
            withAnimation(motion ? Motion.snappy : nil) {
                flipping.remove(id)
                if case .failed(let why) = result { store.problem = why }
            }
            if case .failed = result { Haptics.thud() }
        }
    }

    private func handle(_ action: NotesCardAction, on note: KNote) {
        switch action {
        case .edit: sheet = NotesSheetItem(id: note.id, focus: .text)
        case .details: sheet = NotesSheetItem(id: note.id)
        case .due: sheet = NotesSheetItem(id: note.id, focus: .due)
        case .pin:
            guard !live else { return }
            Haptics.select()
            withAnimation(Motion.snappy) { store.togglePin(note.id) }
            chrome.say(note.pinned ? "Note unpinned" : "Note pinned")
        case .delete:
            deleting = note
        }
    }

    private func delete(_ note: KNote) {
        if live {
            deleting = nil
            let id = note.id
            let store = store
            Task {
                let outcome = await store.deleteLive(id)
                switch outcome {
                case .saved:
                    Haptics.thud()
                    chrome.say("Note deleted")
                case .busy:
                    withAnimation(Motion.snappy) { store.problem = "Wait a moment for the last change to this note to save." }
                case .failed(let why):
                    withAnimation(Motion.snappy) { store.problem = why }
                }
            }
            return
        }
        Haptics.thud()
        withAnimation(Motion.snappy) { store.delete(id: note.id) }
        deleting = nil
        chrome.say("Note deleted")
    }

    private func clearFinished() {
        if live {
            let store = store
            Task {
                let result = await store.clearFinishedLive()
                if result.deleted > 0 { Haptics.thud() }
                if result.failed == 0 {
                    chrome.say("Deleted \(NotesCopy.count(result.deleted, "finished note"))")
                } else {
                    let total = result.deleted + result.failed
                    let why = result.why.map { " " + $0 } ?? ""
                    withAnimation(Motion.snappy) {
                        store.problem = "Deleted \(result.deleted) of \(total) finished notes. \(result.failed) could not be deleted." + why
                    }
                }
            }
            return
        }
        Haptics.thud()
        var count = 0
        withAnimation(Motion.snappy) { count = store.clearFinished() }
        chrome.say("Deleted \(NotesCopy.count(count, "finished note"))")
    }

    private func applyStart() {
        guard !started else { return }
        started = true
        switch start {
        case .details:
            if let first = store.shown(done: false).first { sheet = NotesSheetItem(id: first.id) }
        case .composing:
            draft = "Pick up the new bike stand from the supplier"
            hasDue = true
            captureFocused = true
        default:
            break
        }
    }
}

/// Plain counted words: "1 note", "3 notes".
nonisolated enum NotesCopy {
    static func count(_ value: Int, _ word: String) -> String {
        value == 1 ? "1 \(word)" : "\(value) \(word)s"
    }
}

/// Debug pictures of the Notes section on its own: a list, empty, the details sheet, or a note being written.
struct NotesDebugView: View {
    let state: NotesDebug
    @State private var emptyStore = NotesStore(notes: [])

    init(state: NotesDebug) {
        self.state = state
    }

    var body: some View {
        ScrollView {
            LibraryNotesSection(store: state == .empty ? emptyStore : NotesStore.shared, start: state)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
        .scrollIndicators(.hidden)
        .kScreen()
    }
}
