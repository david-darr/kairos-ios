import SwiftUI

/// Which note the details sheet shows, and what it should put first.
struct NotesSheetItem: Identifiable, Hashable {
    enum Focus: Hashable { case none, text, due }
    let id: String
    var focus: Focus = .none
}

/// "Note": edit the text, the due time and the pin; see when it was made; delete it.
/// Sample notes are saved as they are changed. The paired desktop's notes are saved with Save, once,
/// and the sheet stays open until a change is saved or discarded, so typed text is never lost.
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

    // Paired only: what the desktop last saved, and how the last write went.
    @State private var savedText = ""
    @State private var savedDue: Date?
    @State private var saving = false
    @State private var working = false
    @State private var failure: String?

    private var note: KNote? { store.note(item.id) }
    private var live: Bool { !store.isSample }
    /// A note from the vault's task list: the vault owns its text, so it is not edited here.
    private var textLocked: Bool { live && (note?.fromVault ?? false) }

    var body: some View {
        FittedSheet(estimate: 600) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Note")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)

                textCard
                if textLocked {
                    NotesLiveLine(text: "This note comes from your vault, so change its text there. Its due time can change here.")
                }
                dueCard
                actionRow
                if live { liveFooter }
                createdLine
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .interactiveDismissDisabled(live && (dirty || saving))
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
            .foregroundStyle(textLocked ? Palette.inkDim : Palette.ink)
            .lineLimit(2...10)
            .focused($textFocused)
            .disabled(textLocked || saving)
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
        .disabled(saving)
    }

    private var overdue: Bool {
        guard let note else { return false }
        return !note.done && hasDue && due < .now
    }

    private var actionRow: some View {
        let pinned = note?.pinned ?? false
        let done = note?.done ?? false
        return HStack(spacing: 10) {
            if !live {
                ActionTile(symbol: "pin", title: pinned ? "Unpin" : "Pin", on: pinned) {
                    withAnimation(Motion.snappy) { store.togglePin(item.id) }
                }
            }
            ActionTile(symbol: done ? "arrow.uturn.backward" : "checkmark", title: done ? "Reopen" : "Complete", on: done) {
                if live {
                    setDoneLive(!done)
                    return
                }
                withAnimation(Motion.snappy) { store.setDone(item.id, !done) }
                chrome.say(done ? "Note reopened" : "Note finished")
            }
            ActionTile(symbol: "trash", title: "Delete", danger: true) {
                confirmDelete = true
            }
        }
        .disabled(working || saving)
    }

    /// Paired: what went wrong, and Save and Discard while there is a change the desktop does not have yet.
    @ViewBuilder
    private var liveFooter: some View {
        if loaded && note == nil {
            NotesLiveLine(text: "This note is not on your desktop any more.")
        }
        if let failure {
            NotesLiveLine(text: failure)
        }
        if dirty || saving {
            VStack(spacing: 4) {
                GoldButton(title: saving ? "Saving" : "Save") {
                    if !saving { saveLive() }
                }
                if !saving {
                    QuietButton(title: "Discard changes") {
                        Haptics.tap()
                        discard()
                    }
                }
            }
            .transition(.opacity)
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
        savedText = note.text
        savedDue = note.due
        if let noteDue = note.due {
            hasDue = true
            due = noteDue
        } else {
            hasDue = item.focus == .due
        }
        loaded = true
        if item.focus == .due { save() }
        if item.focus == .text && !textLocked { textFocused = true }
    }

    /// Sample notes only: saved as they change.
    private func save() {
        guard store.isSample, loaded, var current = store.note(item.id) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { current.text = text }
        current.due = hasDue ? due : nil
        store.update(current)
    }

    /// A sample note left blank keeps the text it had.
    private func finish() {
        guard store.isSample, loaded, var current = store.note(item.id) else { return }
        if current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current.text = original
            store.update(current)
        }
    }

    private func deleteNote() {
        if live {
            deleteLive()
            return
        }
        Haptics.thud()
        withAnimation(Motion.snappy) { store.delete(id: item.id) }
        chrome.say("Note deleted")
        dismiss()
    }

    // MARK: - Paired

    private var shownDue: Date? { hasDue ? due : nil }

    private var textChanged: Bool { !textLocked && text != savedText }

    private var dueChanged: Bool {
        switch (shownDue, savedDue) {
        case (nil, nil): return false
        case let (shown?, saved?): return abs(shown.timeIntervalSince(saved)) >= 1
        default: return true
        }
    }

    /// A change the desktop does not have yet.
    private var dirty: Bool { live && loaded && (textChanged || dueChanged) }

    /// One PATCH with only what changed. On failure everything typed stays, and Save can be tapped again.
    private func saveLive() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if textChanged && clean.isEmpty {
            withAnimation(Motion.snappy) { failure = "A note needs some text. Type something, or discard the change." }
            return
        }
        let sendText = textChanged ? clean : nil
        let sendDue = dueChanged
        let wanted = shownDue
        saving = true
        textFocused = false
        let store = store
        let id = item.id
        Task {
            let outcome = await store.saveLive(id, text: sendText, changesDue: sendDue, due: wanted)
            withAnimation(Motion.snappy) {
                saving = false
                switch outcome {
                case .saved:
                    if let sendText {
                        savedText = sendText
                        text = sendText
                    }
                    if sendDue { savedDue = wanted }
                    failure = nil
                case .busy:
                    failure = "Wait a moment for the last change to this note to save, then tap Save again."
                case .failed(let why):
                    failure = why
                }
            }
            switch outcome {
            case .saved:
                Haptics.success()
                chrome.say("Note saved")
            case .busy, .failed:
                Haptics.thud()
            }
        }
    }

    private func discard() {
        withAnimation(Motion.snappy) {
            text = savedText
            if let savedDue {
                hasDue = true
                due = savedDue
            } else {
                hasDue = false
            }
            failure = nil
        }
    }

    private func setDoneLive(_ done: Bool) {
        working = true
        let store = store
        let id = item.id
        Task {
            let outcome = await store.setDoneLive(id, done)
            withAnimation(Motion.snappy) {
                working = false
                switch outcome {
                case .saved: failure = nil
                case .busy: failure = "Wait a moment for the last change to this note to save."
                case .failed(let why): failure = why
                }
            }
            if outcome == .saved { chrome.say(done ? "Note finished" : "Note reopened") }
        }
    }

    private func deleteLive() {
        working = true
        let store = store
        let id = item.id
        Task {
            let outcome = await store.deleteLive(id)
            withAnimation(Motion.snappy) {
                working = false
                switch outcome {
                case .saved: failure = nil
                case .busy: failure = "Wait a moment for the last change to this note to save."
                case .failed(let why): failure = why
                }
            }
            if outcome == .saved {
                Haptics.thud()
                chrome.say("Note deleted")
                dismiss()
            }
        }
    }
}
