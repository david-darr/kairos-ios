import SwiftUI

/// Where the desktop's notes list stands, for one plain sentence on screen.
nonisolated enum NotesLiveLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// How one change to the desktop ended.
nonisolated enum NotesWriteOutcome: Equatable, Sendable {
    case saved
    /// Not sent: a change to this note is already on its way.
    case busy
    case failed(String)
}

/// How Clear finished ended. Only notes the person confirmed that are still finished on the desktop are deleted.
nonisolated struct NotesClearResult: Equatable, Sendable {
    var deleted = 0
    var failed = 0
    /// Confirmed, but open again by the time they were checked: left alone.
    var kept = 0
    var why: String?
    /// The list could not be read from the desktop first, so nothing was deleted.
    var unchecked = false
}

/// The paired desktop behind Library > Notes (routes/notes_routes.py): the list (GET /api/notes),
/// a new note (POST), a change to its text, due time or done state (PATCH /api/notes/{id}) and delete
/// (DELETE /api/notes/{id}). The desktop has no pins, so pins are not offered while paired.
/// Unpaired, nothing here runs and the section shows its sample notes.
extension NotesStore {

    /// A key that changes when the phone is paired or unpaired, the desktop comes back,
    /// or a different desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// Which desktop and which account the notes belong to. Live notes are only ever shown under this key.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Still showing the live notes a request is for. Checked before sending and after every await.
    private func stillLive(_ account: String) -> Bool {
        !isSample && liveAccount == account && Self.accountKey == account
    }

    private static let desktopChanged = "Your paired desktop changed. Try again."

    /// Move between the sample notes and the paired desktop's to match the connection.
    func followConnection() {
        let wantLive = !Connection.shared.usesSampleData
        if wantLive && !isSample && liveAccount != Self.accountKey {
            // Another desktop or account: nothing read from the last one may stay on screen, not even a search.
            resetLive()
            query = ""
        }
        guard wantLive == isSample else { return }
        if wantLive {
            sampleStash = notes
            resetLive()
            isSample = false
        } else {
            isSample = true
            notes = sampleStash ?? NotesSample.make()
            sampleStash = nil
            clearLive()
            liveAccount = "sample"
        }
        query = ""
    }

    private func resetLive() {
        notes = []
        clearLive()
        liveAccount = Self.accountKey
    }

    private func clearLive() {
        liveLoad = .idle
        busy = []
        adding = false
        clearing = false
        skipped = 0
        problem = nil
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    /// A desktop note in the screen's own shape. `order` is its place in the desktop's list.
    nonisolated static func liveNote(_ dto: NoteDTO, order: Int) -> KNote {
        KNote(
            id: dto.id,
            text: dto.text?.string ?? "",
            due: NotesWire.due(dto.dueDate),
            done: dto.completed?.bool ?? false,
            pinned: false,
            created: NotesWire.time(dto.createdAt) ?? NotesWire.time(dto.updatedAt) ?? .now,
            order: order,
            fromVault: dto.isFromVault,
            dueUnreadable: NotesWire.dueUnreadable(dto.dueDate)
        )
    }

    // MARK: The list

    /// Read every note. Already read, the list stays on screen while it refreshes.
    /// Answers true only when this read is now what the screen shows. A read overtaken by a newer one is
    /// dropped, and a read that was on its way while a change finished is read again, so an older answer
    /// never replaces a newer state. A cancelled read (the section closed) changes nothing.
    @discardableResult
    func loadLive() async -> Bool {
        guard !isSample else { return false }
        let account = liveAccount
        readSerial += 1
        let mine = readSerial
        if liveLoad != .loaded { liveLoad = .loading }
        for _ in 0..<3 {
            let writes = writeSerial
            do {
                let read = try await liveClient().notesList()
                guard stillLive(account), mine == readSerial else { return false }
                guard writes == writeSerial else { continue }
                show(read)
                liveLoad = .loaded
                return true
            } catch {
                if error is CancellationError || Task.isCancelled { return false }
                Connection.shared.note(error)
                guard stillLive(account), mine == readSerial else { return false }
                liveLoad = .failed("Your notes could not be read. " + error.plainWords)
                return false
            }
        }
        guard stillLive(account), mine == readSerial else { return false }
        if liveLoad != .loaded {
            liveLoad = .failed("Your notes kept changing while they were read. Try again.")
        }
        return false
    }

    private func show(_ read: NotesListDTO) {
        let mine = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var fresh: [KNote] = []
        for (index, dto) in read.notes.enumerated() where dto.dismissed?.bool != true {
            var note = Self.liveNote(dto, order: index)
            // A change still on its way keeps what the person sees until the desktop answers it.
            if busy.contains(note.id), let kept = mine[note.id] {
                note = kept
                note.order = index
            }
            fresh.append(note)
        }
        notes = fresh
        skipped = read.skipped
    }

    private func replace(_ dto: NoteDTO) {
        guard let index = notes.firstIndex(where: { $0.id == dto.id }) else { return }
        notes[index] = Self.liveNote(dto, order: notes[index].order)
    }

    /// The desktop no longer has this note: it leaves the list and the list is read again.
    private func gone(_ id: String, account: String) {
        notes.removeAll { $0.id == id }
        Task { if stillLive(account) { await loadLive() } }
    }

    private static func isMissing(_ error: Error) -> Bool {
        if case .server(status: 404, _) = error as? APIError { return true }
        return false
    }

    /// The desktop refused the request, so it certainly did not save it. Anything else (not reached,
    /// timed out, an answer this app could not read, a server error) may have come after it saved.
    private static func wasRefused(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
    }

    // MARK: Writing

    /// Make a note on the desktop. Sent once; the person's text stays in the box until this says saved.
    /// When the desktop does not confirm it, the list is read again: if the new note is there it counts
    /// as saved, and if not the person is told plainly, so a second tap is never a blind duplicate.
    func createLive(text: String, due: Date?) async -> NotesWriteOutcome {
        guard !isSample else { return .failed("This note is a sample.") }
        guard !adding else { return .busy }
        let account = liveAccount
        guard stillLive(account) else { return .failed(Self.desktopChanged) }
        adding = true
        defer { if liveAccount == account { adding = false } }
        let before = Set(notes.map(\.id))
        // Only a list that was really read can prove a note is new.
        let listWasRead = liveLoad == .loaded
        do {
            let made = try await liveClient().notesCreate(text: text, due: due)
            writeSerial += 1
            guard stillLive(account) else { return .saved }
            let top = (notes.map(\.order).min() ?? 0) - 1
            notes.removeAll { $0.id == made.id }
            notes.append(Self.liveNote(made, order: top))
            Task { if stillLive(account) { await loadLive() } }
            return .saved
        } catch {
            writeSerial += 1
            Connection.shared.note(error)
            guard stillLive(account) else { return .failed(error.plainWords) }
            if Self.wasRefused(error) {
                return .failed("Your note was not saved. " + error.plainWords)
            }
            // The note may have reached the desktop before the answer was lost: look for it.
            let read = await loadLive()
            guard stillLive(account) else { return .failed(error.plainWords) }
            if read && listWasRead && notes.contains(where: { !before.contains($0.id) && $0.text == text }) {
                return .saved
            }
            if read {
                return .failed("Your desktop did not confirm this note, and it is not in your list yet. Your text is still in the box. Check the list again in a moment before adding it again. " + error.plainWords)
            }
            return .failed("Your desktop did not confirm this note, and your list could not be read to check. Your text is still in the box. Check the list before adding it again. " + error.plainWords)
        }
    }

    /// Mark a note done or open. The store changes only when the desktop has saved it.
    func setDoneLive(_ id: String, _ done: Bool) async -> NotesWriteOutcome {
        guard !isSample else { return .failed("This note is a sample.") }
        guard !busy.contains(id) else { return .busy }
        let account = liveAccount
        guard stillLive(account) else { return .failed(Self.desktopChanged) }
        busy.insert(id)
        defer {
            writeSerial += 1
            if liveAccount == account { busy.remove(id) }
        }
        do {
            let saved = try await liveClient().notesUpdate(id, completed: done)
            guard stillLive(account) else { return .saved }
            replace(saved)
            return .saved
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .failed(error.plainWords) }
            if Self.isMissing(error) {
                gone(id, account: account)
                return .failed("This note is not on your desktop any more.")
            }
            return .failed((done ? "This note was not marked finished. " : "This note was not reopened. ") + error.plainWords)
        }
    }

    /// Save a change to a note's text and due time. Only what changed is sent.
    func saveLive(_ id: String, text: String?, changesDue: Bool, due: Date?) async -> NotesWriteOutcome {
        guard !isSample else { return .failed("This note is a sample.") }
        // A due time this app cannot read is never sent over.
        let sendsDue = changesDue && note(id)?.dueUnreadable != true
        guard text != nil || sendsDue else { return .saved }
        guard !busy.contains(id) else { return .busy }
        let account = liveAccount
        guard stillLive(account) else { return .failed(Self.desktopChanged) }
        busy.insert(id)
        defer {
            writeSerial += 1
            if liveAccount == account { busy.remove(id) }
        }
        do {
            let saved = try await liveClient().notesUpdate(id, text: text, changesDue: sendsDue, due: due)
            guard stillLive(account) else { return .saved }
            replace(saved)
            return .saved
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .failed(error.plainWords) }
            if Self.isMissing(error) {
                gone(id, account: account)
                return .failed("This note is not on your desktop any more, so your change was not saved.")
            }
            return .failed("Your change was not saved. " + error.plainWords)
        }
    }

    /// Delete one note on the desktop. It leaves the list only once the desktop says so.
    func deleteLive(_ id: String) async -> NotesWriteOutcome {
        guard !isSample else { return .failed("This note is a sample.") }
        guard !busy.contains(id) else { return .busy }
        let account = liveAccount
        guard stillLive(account) else { return .failed(Self.desktopChanged) }
        busy.insert(id)
        defer {
            writeSerial += 1
            if liveAccount == account { busy.remove(id) }
        }
        do {
            _ = try await liveClient().notesDelete(id)
            guard stillLive(account) else { return .saved }
            notes.removeAll { $0.id == id }
            return .saved
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .failed(error.plainWords) }
            return .failed("This note was not deleted. " + error.plainWords)
        }
    }

    /// Delete the finished notes the person confirmed, one at a time, as the desktop's own page does.
    /// The list is read from the desktop first; a note is deleted only if it is still finished there and
    /// was in `confirmed`. If that read fails, nothing is deleted. The desktop deletes for good and has no
    /// version check, so the phone's older copy is never trusted for this.
    func clearFinishedLive(confirmed: Set<String>) async -> NotesClearResult {
        var result = NotesClearResult()
        guard !isSample, !clearing, !confirmed.isEmpty else { return result }
        let account = liveAccount
        guard stillLive(account) else {
            result.unchecked = true
            return result
        }
        clearing = true
        defer { if liveAccount == account { clearing = false } }
        guard await loadLive(), stillLive(account) else {
            result.unchecked = true
            return result
        }
        // Reopened on the desktop since the person confirmed: kept. Gone already: nothing to do.
        let fresh = notes.filter { confirmed.contains($0.id) }
        let finished = fresh.filter { $0.done && !busy.contains($0.id) }.map(\.id)
        result.kept = fresh.count - finished.count
        for (index, id) in finished.enumerated() {
            guard stillLive(account) else {
                result.failed += finished.count - index
                if result.why == nil { result.why = Self.desktopChanged }
                break
            }
            // Reopened while this ran (here, or on the desktop and read since): left alone.
            guard let current = note(id) else { continue }
            guard current.done else {
                result.kept += 1
                continue
            }
            switch await deleteLive(id) {
            case .saved: result.deleted += 1
            case .busy: result.kept += 1
            case .failed(let reason):
                result.failed += 1
                if result.why == nil { result.why = reason }
            }
        }
        return result
    }
}

/// One quiet line on the Notes section: loading, or what failed, with one plain action.
struct NotesLiveLine: View {
    let text: String
    var action: String? = nil
    var perform: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let action, let perform {
                Button {
                    Haptics.tap()
                    perform()
                } label: {
                    Text(action)
                        .font(KFont.ui(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.goldText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(minHeight: 48)
        .kCard(radius: 16)
    }
}
