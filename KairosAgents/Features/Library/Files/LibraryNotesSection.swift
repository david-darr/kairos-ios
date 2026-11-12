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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NotesCaptureCard(draft: $draft, hasDue: $hasDue, due: $draftDue, focused: $captureFocused, add: addDraft)
                .arrives(0)
            stats
                .arrives(1)
            if store.notes.isEmpty {
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
        .onChange(of: chrome.addTick) {
            if router.tab == .library { captureFocused = true }
        }
    }

    // MARK: - Parts

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
        Haptics.success()
        withAnimation(Motion.snappy) {
            _ = store.add(text: clean, due: hasDue ? draftDue : nil)
            draft = ""
            hasDue = false
            draftDue = NotesDue.suggested()
        }
    }

    /// The strike-through shows at once; the note moves to its new group a moment later.
    private func toggle(_ note: KNote) {
        guard !flipping.contains(note.id) else { return }
        let target = !note.done
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

    private func handle(_ action: NotesCardAction, on note: KNote) {
        switch action {
        case .edit: sheet = NotesSheetItem(id: note.id, focus: .text)
        case .details: sheet = NotesSheetItem(id: note.id)
        case .due: sheet = NotesSheetItem(id: note.id, focus: .due)
        case .pin:
            Haptics.select()
            withAnimation(Motion.snappy) { store.togglePin(note.id) }
            chrome.say(note.pinned ? "Note unpinned" : "Note pinned")
        case .delete:
            deleting = note
        }
    }

    private func delete(_ note: KNote) {
        Haptics.thud()
        withAnimation(Motion.snappy) { store.delete(id: note.id) }
        deleting = nil
        chrome.say("Note deleted")
    }

    private func clearFinished() {
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
