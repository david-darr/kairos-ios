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

    /// Still showing the live notes a request was sent for. Checked after every await before writing a result.
    private func stillLive(_ account: String) -> Bool {
        !isSample && liveAccount == account && Self.accountKey == account
    }

    /// Move between the sample notes and the paired desktop's to match the connection.
    func followConnection() {
        let wantLive = !Connection.shared.usesSampleData
        if wantLive && !isSample && liveAccount != Self.accountKey {
            // Another desktop or account: nothing read from the last one may stay on screen.
            resetLive()
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
            fromVault: dto.isFromVault
        )
    }

    // MARK: The list

    /// Read every note. Already read, the list stays on screen while it refreshes.
    func loadLive() async {
        guard !isSample else { return }
        let account = liveAccount
        if liveLoad != .loaded { liveLoad = .loading }
        do {
            let read = try await liveClient().notesList()
            guard stillLive(account) else { return }
            show(read)
            liveLoad = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            liveLoad = .failed("Your notes could not be read. " + error.plainWords)
        }
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

    // MARK: Writing

    /// Make a note on the desktop. Sent once; the person's text stays in the box until this says saved.
    func createLive(text: String, due: Date?) async -> NotesWriteOutcome {
        guard !isSample else { return .failed("This note is a sample.") }
        guard !adding else { return .busy }
        let account = liveAccount
        adding = true
        defer { if liveAccount == account { adding = false } }
        do {
            let made = try await liveClient().notesCreate(text: text, due: due)
            guard stillLive(account) else { return .saved }
            let top = (notes.map(\.order).min() ?? 0) - 1
            notes.removeAll { $0.id == made.id }
            notes.append(Self.liveNote(made, order: top))
            Task { if stillLive(account) { await loadLive() } }
            return .saved
        } catch {
            Connection.shared.note(error)
            if let api = error as? APIError, api.isOffline {
                // The note may have reached the desktop before the answer was lost: read the list
                // so the person can see it before adding it again.
                Task { if stillLive(account) { await loadLive() } }
                return .failed("Your desktop did not confirm this note. Check the list before adding it again. " + error.plainWords)
            }
            return .failed("Your note was not saved. " + error.plainWords)
        }
    }

    /// Mark a note done or open. The store changes only when the desktop has saved it.
    func setDoneLive(_ id: String, _ done: Bool) async -> NotesWriteOutcome {
        guard !isSample else { return .failed("This note is a sample.") }
        guard !busy.contains(id) else { return .busy }
        let account = liveAccount
        busy.insert(id)
        defer { if liveAccount == account { busy.remove(id) } }
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
        guard text != nil || changesDue else { return .saved }
        guard !busy.contains(id) else { return .busy }
        let account = liveAccount
        busy.insert(id)
        defer { if liveAccount == account { busy.remove(id) } }
        do {
            let saved = try await liveClient().notesUpdate(id, text: text, changesDue: changesDue, due: due)
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
        busy.insert(id)
        defer { if liveAccount == account { busy.remove(id) } }
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

    /// Delete every finished note, one at a time, as the desktop's own page does.
    /// Answers how many were deleted and how many were not.
    func clearFinishedLive() async -> (deleted: Int, failed: Int, why: String?) {
        guard !isSample else { return (0, 0, nil) }
        let account = liveAccount
        let finished = notes.filter { $0.done && !busy.contains($0.id) }.map(\.id)
        var deleted = 0
        var failed = 0
        var why: String?
        for id in finished {
            guard stillLive(account) else { break }
            switch await deleteLive(id) {
            case .saved: deleted += 1
            case .busy: failed += 1
            case .failed(let reason):
                failed += 1
                if why == nil { why = reason }
            }
        }
        return (deleted, failed, why)
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
