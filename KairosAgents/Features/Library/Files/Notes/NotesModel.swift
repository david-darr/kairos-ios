import SwiftUI

// The data behind Library > Notes: quick Kairos notes with an optional due time.
// The sample store stands in until the desktop connection fills it.

nonisolated struct KNote: Identifiable, Hashable, Sendable {
    let id: String
    var text: String
    var due: Date?
    var done: Bool
    var pinned: Bool
    var created: Date
    var order: Int
    /// Imported from the vault's task list on the paired desktop: its text belongs to the vault.
    var fromVault = false
    /// The paired desktop has a due time for this note that this app cannot read. It is shown as such
    /// and never sent, so a save cannot replace a time the person never saw.
    var dueUnreadable = false
}

nonisolated enum NotesSort: String, CaseIterable, Hashable, Sendable {
    case saved = "Saved order"
    case due = "Due time"
    case alphabetical = "A-Z"
}

/// The states the Notes section can be pictured in.
enum NotesDebug: Hashable {
    case list, empty, details, composing
}

/// What the Notes screens need from wherever the notes live.
protocol NotesProviding: AnyObject {
    var notes: [KNote] { get }
    func note(_ id: String) -> KNote?
    @discardableResult func add(text: String, due: Date?) -> KNote?
    func update(_ note: KNote)
    func setDone(_ id: String, _ done: Bool)
    func togglePin(_ id: String)
    func delete(id: String)
    @discardableResult func clearFinished() -> Int
}

@Observable
final class NotesStore: NotesProviding {
    static let shared = NotesStore(notes: NotesSample.make())

    var notes: [KNote]
    /// Kept here, not in the view, so they survive switching Library sections.
    var sort: NotesSort = .saved
    var query = ""

    // The paired desktop (NotesLive.swift). Unpaired, none of this is used.
    /// Showing sample notes. False while the phone shows the paired desktop's notes.
    var isSample = true
    var liveLoad: NotesLiveLoad = .idle
    /// The desktop and account the live notes came from (NotesStore.accountKey when they were read).
    var liveAccount = "sample"
    /// Notes with a change on its way to the desktop: one at a time each, and a list read leaves them be.
    var busy: Set<String> = []
    /// A new note is on its way to the desktop.
    var adding = false
    /// Notes the desktop sent that this app could not read.
    var skipped = 0
    /// What last went wrong, in one plain sentence, until the person dismisses it.
    var problem: String?
    /// The sample notes, kept aside while the desktop's are shown.
    var sampleStash: [KNote]?
    /// Clear finished is running.
    var clearing = false
    /// Counts list reads started and changes finished, so an older list answer never replaces a newer state.
    var readSerial = 0
    var writeSerial = 0
    /// Paired only: the note being typed in the capture card. Kept here, not in the view, so it survives
    /// switching Library sections while it is on its way to the desktop or after it failed.
    var liveDraft = ""
    var liveDraftHasDue = false
    var liveDraftDue = NotesDue.suggested()

    init(notes: [KNote]) {
        self.notes = notes
    }

    func note(_ id: String) -> KNote? {
        notes.first { $0.id == id }
    }

    @discardableResult
    func add(text: String, due: Date?) -> KNote? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let top = (notes.map(\.order).min() ?? 0) - 1
        let note = KNote(id: "note-\(UUID().uuidString)", text: clean, due: due, done: false, pinned: false, created: .now, order: top)
        notes.append(note)
        return note
    }

    func update(_ note: KNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = note
    }

    func setDone(_ id: String, _ done: Bool) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].done = done
    }

    func togglePin(_ id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].pinned.toggle()
    }

    func delete(id: String) {
        notes.removeAll { $0.id == id }
    }

    @discardableResult
    func clearFinished() -> Int {
        let count = notes.filter(\.done).count
        notes.removeAll { $0.done }
        return count
    }

    // MARK: - What the screen shows

    var finishedCount: Int { notes.filter(\.done).count }

    /// Open notes due between now and seven days from now.
    func dueThisWeek(now: Date = .now) -> Int {
        let end = now.addingTimeInterval(7 * 86_400)
        return notes.filter { note in
            guard !note.done, let due = note.due else { return false }
            return due >= now && due <= end
        }.count
    }

    func shown(done: Bool) -> [KNote] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let picked = notes.filter { note in
            guard note.done == done else { return false }
            return needle.isEmpty || note.text.localizedCaseInsensitiveContains(needle)
        }
        return NotesStore.sorted(picked, by: sort)
    }

    nonisolated static func sorted(_ list: [KNote], by mode: NotesSort) -> [KNote] {
        list.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            switch mode {
            case .saved:
                return a.order < b.order
            case .due:
                switch (a.due, b.due) {
                case let (first?, second?): return first < second
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.order < b.order
                }
            case .alphabetical:
                return a.text.localizedCaseInsensitiveCompare(b.text) == .orderedAscending
            }
        }
    }
}

/// Small date helpers for notes.
nonisolated enum NotesDue {
    /// Tomorrow at 9:00, the default when someone turns a due time on.
    static func suggested(now: Date = .now) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    static func isOverdue(_ note: KNote, now: Date = .now) -> Bool {
        guard !note.done, let due = note.due else { return false }
        return due < now
    }
}

/// Made-up notes: a bike shop, a report due Friday.
nonisolated enum NotesSample {
    static func make(now: Date = .now) -> [KNote] {
        let calendar = Calendar.current
        func at(days: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        return [
            KNote(id: "n-newsletter", text: "Ideas for the bike shop newsletter: a spring tune-up checklist, a short piece on picking the right tyre pressure for city riding, a photo of the new repair bench, the opening hours for the holiday weekend, and a reminder that the loyalty card now covers chain replacements too.", due: nil, done: false, pinned: true, created: now.addingTimeInterval(-5 * 86_400), order: 0),
            KNote(id: "n-supplier", text: "Call the supplier about the late inner tubes", due: now.addingTimeInterval(-3 * 3600), done: false, pinned: false, created: now.addingTimeInterval(-2 * 86_400), order: 1),
            KNote(id: "n-van", text: "Book the van for the Saturday delivery", due: now.addingTimeInterval(2 * 3600), done: false, pinned: false, created: now.addingTimeInterval(-86_400), order: 2),
            KNote(id: "n-report", text: "Finish the weekly report, due Friday", due: at(days: 3, hour: 17), done: false, pinned: false, created: now.addingTimeInterval(-3 * 86_400), order: 3),
            KNote(id: "n-shopping", text: "Shopping list: chain oil, zip ties, shop towels", due: nil, done: false, pinned: false, created: now.addingTimeInterval(-4 * 3600), order: 4),
            KNote(id: "n-tags", text: "Order new price tags", due: at(days: -1, hour: 10), done: true, pinned: false, created: now.addingTimeInterval(-6 * 86_400), order: 5),
            KNote(id: "n-reply", text: "Reply to the question about the opening date", due: nil, done: true, pinned: false, created: now.addingTimeInterval(-7 * 86_400), order: 6),
        ]
    }
}
