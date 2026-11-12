import SwiftUI

/// Which note the details sheet shows, and what it should put first.
struct NotesSheetItem: Identifiable, Hashable {
    enum Focus: Hashable { case none, text, due }
    let id: String
    var focus: Focus = .none
}

/// "Note": edit the text, the due time and the pin; see when it was made; delete it.
/// Changes are saved as they are made.
struct NotesDetailsSheet: View {
    let store: NotesStore
    let item: NotesSheetItem

    @Environment(ChromeState.self) private var chrome
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var original = ""
    @State private var hasDue = false
    @State private var due = NotesDue.suggested()
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var textFocused: Bool

    private var note: KNote? { store.note(item.id) }

    var body: some View {
        FittedSheet(estimate: 600) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Note")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)

                textCard
                dueCard
                actionRow
                createdLine
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .onAppear(perform: load)
        .onDisappear(perform: finish)
        .onChange(of: text) { save() }
        .onChange(of: hasDue) { save() }
        .onChange(of: due) { save() }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteNote)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private var textCard: some View {
        TextField("Note", text: $text, axis: .vertical)
            .font(KFont.ui(17))
            .foregroundStyle(Palette.ink)
            .lineLimit(2...10)
            .focused($textFocused)
            .padding(14)
            .frame(minHeight: 52)
            .kCard(radius: 18, raised: true)
            .accessibilityLabel("Note text")
    }

    private var dueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $hasDue.animation(Motion.snappy)) {
                Text("Due time")
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
            }
            .tint(Palette.gold)
            .frame(minHeight: 44)
            if hasDue {
                DatePicker(selection: $due, displayedComponents: [.date, .hourAndMinute]) {
                    Text(FilesDates.short(due))
                        .font(KFont.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(overdue ? Palette.danger : Palette.inkDim)
                }
                .tint(Palette.gold)
                .frame(minHeight: 44)
                .transition(.opacity)
            } else {
                Text("No date")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .kCard(radius: 18)
    }

    private var overdue: Bool {
        guard let note else { return false }
        return !note.done && hasDue && due < .now
    }

    private var actionRow: some View {
        let pinned = note?.pinned ?? false
        let done = note?.done ?? false
        return HStack(spacing: 10) {
            ActionTile(symbol: "pin", title: pinned ? "Unpin" : "Pin", on: pinned) {
                withAnimation(Motion.snappy) { store.togglePin(item.id) }
            }
            ActionTile(symbol: done ? "arrow.uturn.backward" : "checkmark", title: done ? "Reopen" : "Complete", on: done) {
                withAnimation(Motion.snappy) { store.setDone(item.id, !done) }
                chrome.say(done ? "Note reopened" : "Note finished")
            }
            ActionTile(symbol: "trash", title: "Delete", danger: true) {
                confirmDelete = true
            }
        }
    }

    private var createdLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
            Text("Created \(FilesDates.full(note?.created ?? .now))")
                .font(KFont.ui(13.5, relativeTo: .footnote))
        }
        .foregroundStyle(Palette.inkFaint)
        .padding(.horizontal, 4)
    }

    // MARK: - Saving

    private func load() {
        guard !loaded, let note else { return }
        text = note.text
        original = note.text
        if let noteDue = note.due {
            hasDue = true
            due = noteDue
        } else {
            hasDue = item.focus == .due
        }
        loaded = true
        if item.focus == .due { save() }
        if item.focus == .text { textFocused = true }
    }

    private func save() {
        guard loaded, var current = store.note(item.id) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { current.text = text }
        current.due = hasDue ? due : nil
        store.update(current)
    }

    /// A note left blank keeps the text it had.
    private func finish() {
        guard loaded, var current = store.note(item.id) else { return }
        if current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current.text = original
            store.update(current)
        }
    }

    private func deleteNote() {
        Haptics.thud()
        withAnimation(Motion.snappy) { store.delete(id: item.id) }
        chrome.say("Note deleted")
        dismiss()
    }
}
