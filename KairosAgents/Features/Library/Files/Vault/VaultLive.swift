import SwiftUI

/// Where a desktop read stands, for one plain sentence on screen.
nonisolated enum VaultLiveLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// The sample vault, kept aside while the phone shows the paired desktop's vault.
struct VaultSampleStash {
    var notes: [String: VaultNote]
    var pins: [String]
    var recent: [String]
    var history: [String: [VaultChange]]
    var expanded: Set<String>
    var dailyFolder: String
    var templatePath: String
}

/// The line today's note would add to its folder index, as the desktop proposed it.
nonisolated struct VaultLiveIndex: Hashable, Sendable {
    var noteID: String
    var indexID: String
    var line: String
    var content: String
    var version: String
}

/// The paired desktop behind the Vault (routes/vault_routes.py): the list and links (GET /api/vault/graph),
/// one note (GET and POST /api/vault/note), search, related, pins, recent changes and today's note.
/// Unpaired, nothing here runs and the Vault shows its sample notes.
extension VaultStore {

    /// A key that changes when the phone is paired or unpaired, the desktop comes back,
    /// or a different desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// Which desktop and which account the vault belongs to. Live notes are only ever shown under this key.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Still showing the live vault a request was sent for. Checked after every await before writing a result.
    private func stillLive(_ account: String) -> Bool {
        !isSample && liveAccount == account && Self.accountKey == account
    }

    /// Move between sample notes and the paired desktop to match the connection.
    func followConnection() {
        let wantLive = !Connection.shared.usesSampleData
        if wantLive && !isSample && liveAccount != Self.accountKey {
            // Another desktop or account: nothing read from the last one may stay on screen.
            resetLive()
        }
        guard wantLive == isSample else { return }
        if wantLive {
            sampleStash = VaultSampleStash(notes: notes, pins: pins, recent: recent, history: history, expanded: expanded,
                                           dailyFolder: dailyFolder, templatePath: templatePath)
            resetLive()
            isSample = false
        } else {
            clearLive()
            isSample = true
            if let stash = sampleStash {
                notes = stash.notes
                pins = stash.pins
                recent = stash.recent
                history = stash.history
                expanded = stash.expanded
                dailyFolder = stash.dailyFolder
                templatePath = stash.templatePath
            } else {
                reload()
            }
            sampleStash = nil
        }
    }

    /// Every live note, pin, recent list and load state goes, ready to read the current account's vault.
    private func resetLive() {
        notes = [:]
        pins = []
        recent = []
        history = [:]
        expanded = []
        clearLive()
        liveAccount = Self.accountKey
    }

    private func clearLive() {
        savingNotes = []
        liveLoad = .idle
        noteLoad = [:]
        linksOut = [:]
        linksIn = [:]
        linksMissing = [:]
        backlinkSnippets = [:]
        relatedLive = [:]
        liveTodayID = nil
        liveTemplateExists = false
        liveIndex = nil
        problem = nil
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    // MARK: The list

    /// Read the vault's notes, folders and links (no note text), pins, recent changes and today's note.
    func loadLive() async {
        guard !isSample else { return }
        let account = liveAccount
        if liveLoad != .loaded { liveLoad = .loading }
        do {
            let client = try liveClient()
            let graph = try await client.vaultGraph()
            guard stillLive(account) else { return }
            let pinned = try? await client.vaultPins()
            guard stillLive(account) else { return }
            let daily = try? await client.vaultDaily()
            guard stillLive(account) else { return }
            let activity = try? await client.vaultActivity()
            guard stillLive(account) else { return }
            showGraph(graph, activity: activity)
            if let pinned { pins = (pinned.pins ?? []).map(VaultWire.id(forPath:)) }
            if let daily { showDaily(daily) }
            liveLoad = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            liveLoad = .failed("Your vault could not be read. " + error.plainWords)
        }
    }

    /// Load the list once, when it has not been read yet.
    func loadLiveIfNeeded() async {
        guard !isSample else { return }
        switch liveLoad {
        case .idle, .failed: await loadLive()
        case .loading, .loaded: break
        }
    }

    private static let propertyOrder = ["status", "project", "type", "tags"]

    private func showGraph(_ graph: VaultGraphDTO, activity: VaultActivityDTO?) {
        var labels: [String: String] = [:]
        for item in activity?.recent ?? [] {
            if let label = item.label { labels[VaultWire.id(forPath: item.path)] = label }
        }
        var fresh: [String: VaultNote] = [:]
        for node in graph.nodes ?? [] where node.type == "note" {
            let id = VaultWire.id(forPath: node.id)
            let edited = Date(timeIntervalSince1970: node.mtime ?? 0)
            if var kept = notes[id], kept.loaded, abs(kept.edited.timeIntervalSince(edited)) < 0.01 {
                if let label = labels[id] { kept.changeLabel = label }
                fresh[id] = kept
                continue
            }
            let pairs = (node.frontmatter ?? [:]).compactMap { key, value in
                VaultWire.text(value).map { VaultPropertyPair(key: key, value: $0) }
            }
            let ordered = pairs.sorted { a, b in
                let x = Self.propertyOrder.firstIndex(of: a.key) ?? 99
                let y = Self.propertyOrder.firstIndex(of: b.key) ?? 99
                return x == y ? a.key < b.key : x < y
            }
            fresh[id] = VaultNote(id: id, body: "", edited: edited, editedBy: "", loaded: false,
                                  listed: VaultListedFacts(properties: ordered, words: node.words ?? 0),
                                  changeLabel: labels[id])
            // Changed on the desktop (or never read): its text must be read again, so an open reader
            // sees an unread note and asks for it instead of waiting on a load that already ended.
            if let state = noteLoad[id], state != .loading { noteLoad[id] = nil }
        }
        var out: [String: [String]] = [:]
        var into: [String: [String]] = [:]
        for edge in graph.edges ?? [] where edge.kind == "link" {
            let from = VaultWire.id(forPath: edge.source)
            let to = VaultWire.id(forPath: edge.target)
            out[from, default: []].append(to)
            into[to, default: []].append(from)
        }
        var missing: [String: [String]] = [:]
        for link in graph.missing ?? [] {
            missing[VaultWire.id(forPath: link.source), default: []].append(link.target)
        }
        notes = fresh
        linksOut = out
        linksIn = into
        linksMissing = missing
        recent = recent.filter { fresh[$0] != nil }
    }

    private func showDaily(_ daily: VaultDailyDTO) {
        if let path = daily.path, !path.isEmpty { liveTodayID = VaultWire.id(forPath: path) }
        if let folder = daily.folder, !folder.isEmpty { dailyFolder = folder }
        if let template = daily.template, !template.isEmpty { templatePath = VaultWire.id(forPath: template) }
        liveTemplateExists = daily.templateExists ?? false
    }

    // MARK: One note

    /// Read one note's text, its links both ways and related notes. Already read, it refreshes quietly.
    func open(_ id: String) async {
        guard !isSample else { return }
        let account = liveAccount
        if notes[id]?.loaded != true { noteLoad[id] = .loading }
        do {
            let client = try liveClient()
            let read = try await client.vaultNote(path: VaultWire.path(forID: id))
            guard stillLive(account) else { return }
            show(read, as: id)
            noteLoad[id] = notes[id]?.loaded == true ? .loaded : .failed("This note could not be read. Your desktop sent no text for it.")
            let near = try? await client.vaultRelated(path: VaultWire.path(forID: id))
            if let near, stillLive(account) {
                relatedLive[id] = (near.results ?? []).map { VaultWire.id(forPath: $0.path) }.filter { notes[$0] != nil }
            }
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            if notes[id]?.loaded == true {
                noteLoad[id] = .loaded
            } else if case .server(status: 404, _) = error as? APIError {
                noteLoad[id] = .failed("This note is not in your vault any more. It may have been moved or deleted.")
            } else {
                noteLoad[id] = .failed("This note could not be read. " + error.plainWords)
            }
        }
    }

    private func show(_ read: VaultNoteDTO, as id: String) {
        var note = notes[id] ?? VaultNote(id: id, body: "", edited: .now, editedBy: "", loaded: false)
        if let content = read.content {
            note.body = content
            note.loaded = true
        }
        if let version = read.version { note.version = version }
        note.editable = read.canEdit ?? read.editable ?? note.editable
        if let mtime = read.mtime { note.edited = Date(timeIntervalSince1970: mtime) }
        if let label = read.lastChange?.label { note.changeLabel = label }
        notes[id] = note

        if let links = read.links {
            var targets: [String] = []
            for link in links where link.kind == "note" {
                guard let path = link.id else { continue }
                let target = VaultWire.id(forPath: path)
                if target != id && !targets.contains(target) { targets.append(target) }
            }
            for old in linksOut[id] ?? [] where !targets.contains(old) {
                linksIn[old]?.removeAll { $0 == id }
            }
            for target in targets where !(linksIn[target] ?? []).contains(id) {
                linksIn[target, default: []].append(id)
            }
            linksOut[id] = targets
            var missing: [String] = []
            for link in links where link.kind == "missing" {
                if let target = link.target, !missing.contains(target) { missing.append(target) }
            }
            linksMissing[id] = missing
        }
        if let backlinks = read.backlinks {
            var snippets: [String: String] = [:]
            for link in backlinks {
                let source = VaultWire.id(forPath: link.id)
                if snippets[source] == nil { snippets[source] = link.snippet ?? "" }
            }
            backlinkSnippets[id] = snippets
            let sources = Array(snippets.keys)
            for source in sources where !(linksOut[source] ?? []).contains(id) {
                linksOut[source, default: []].append(id)
            }
            linksIn[id] = sources
        }
    }

    // MARK: Saving

    /// Save the whole note against the version it was opened at. On a conflict the latest version is read
    /// into the store, so "Reload their version" shows it.
    func saveLive(_ id: String, body: String, version: String, allowRemoveProperties: Bool = false) async -> VaultSaveOutcome {
        guard !isSample else { return .failed("This note is a sample.") }
        // One save per note at a time: a second one would send the same version and come back as a false conflict.
        guard !savingNotes.contains(id) else { return .busy }
        let account = liveAccount
        savingNotes.insert(id)
        defer { if liveAccount == account { savingNotes.remove(id) } }
        do {
            let saved = try await liveClient().vaultSave(path: VaultWire.path(forID: id), content: body, version: version,
                                                         allowRemoveProperties: allowRemoveProperties)
            // The desktop has it; only the store moved on, so nothing is written here.
            guard stillLive(account) else { return .saved }
            show(saved, as: id)
            Task { await open(id) }
            return .saved
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .failed("Your vault changed while this note was saving.") }
            if case .server(status: 409, let detail) = error as? APIError, detail == VaultWire.conflictDetail {
                await open(id)
                return .conflict
            }
            return .failed(error.plainWords)
        }
    }

    /// A small change made in place (a ticked box): shown at once, put back if the desktop refuses it.
    func saveQuietly(_ id: String, body: String) {
        guard let before = notes[id], before.loaded, before.body != body else { return }
        guard let version = before.version, before.editable else {
            problem = "This note cannot be changed from here. Edit it on your desktop."
            return
        }
        guard noteLoad[id] != .loading else {
            problem = "Wait a moment for the last change to save."
            return
        }
        guard !isSample else { return }
        let account = liveAccount
        var changed = before
        changed.body = body
        notes[id] = changed
        noteLoad[id] = .loading
        Task {
            let outcome = await saveLive(id, body: body, version: version)
            guard stillLive(account) else { return }
            if noteLoad[id] == .loading { noteLoad[id] = .loaded }
            switch outcome {
            case .saved:
                break
            case .conflict:
                problem = "This note changed on your desktop, so your change was not saved. It now shows the latest version."
            case .busy:
                if notes[id]?.body == body { notes[id] = before }
                problem = "Wait a moment for the last change to save."
            case .failed(let why):
                if notes[id]?.body == body { notes[id] = before }
                problem = "Your change was not saved. " + why
            }
        }
    }

    func togglePinLive(_ id: String) {
        guard !isSample else { return }
        let account = liveAccount
        let before = pins
        if pins.contains(id) { pins.removeAll { $0 == id } } else { pins.append(id) }
        let wanted = pins
        Task {
            do {
                let stored = try await liveClient().vaultSetPins(wanted.map(VaultWire.path(forID:)))
                guard stillLive(account) else { return }
                if pins == wanted, let list = stored.pins { pins = list.map(VaultWire.id(forPath:)) }
            } catch {
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if pins == wanted { pins = before }
                problem = "Your pins could not be saved. " + error.plainWords
            }
        }
    }

    // MARK: Search

    /// Notes whose text matches, with a snippet. Paired, the desktop searches; unpaired, the samples.
    func searchText(_ query: String) async throws -> [(note: VaultNote, snippet: String)] {
        guard !isSample else { return textMatches(query) }
        let account = liveAccount
        let found = try await liveClient().vaultSearch(query)
        guard stillLive(account) else { return [] }
        let marks = (found.mark ?? []).filter { !$0.isEmpty }
        return (found.results ?? []).map { hit in
            let id = VaultWire.id(forPath: hit.path)
            var snippet = hit.snippet ?? ""
            for mark in marks { snippet = snippet.replacingOccurrences(of: mark, with: "") }
            let note = notes[id] ?? VaultNote(id: id, body: "", edited: .now, editedBy: "", loaded: false)
            return (note: note, snippet: VaultMarkdown.plain(snippet))
        }
    }

    // MARK: Today's note

    /// Make today's note on the desktop (or find it). Returns a plain sentence when it failed.
    func makeTodayLive() async -> (created: Bool, problem: String?) {
        let changed = "Today's note could not be shown. Your vault changed while it was being made."
        guard !isSample else { return (false, changed) }
        let account = liveAccount
        do {
            let made = try await liveClient().vaultMakeDaily()
            guard stillLive(account) else { return (false, changed) }
            guard let path = made.path, !path.isEmpty else { return (false, "Today's note could not be made.") }
            let id = VaultWire.id(forPath: path)
            liveTodayID = id
            if notes[id] == nil { notes[id] = VaultNote(id: id, body: "", edited: .now, editedBy: "", loaded: false) }
            if let index = made.index, let line = index.line, let content = index.content, let version = index.version {
                liveIndex = VaultLiveIndex(noteID: id, indexID: VaultWire.id(forPath: index.path), line: line, content: content, version: version)
            } else {
                liveIndex = nil
            }
            return (made.created ?? false, nil)
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return (false, changed) }
            return (false, "Today's note could not be made. " + error.plainWords)
        }
    }

    /// Add the proposed line to the folder index. False when the index changed since, or the save failed.
    func addToIndexLive(_ id: String) async -> Bool {
        guard !isSample, let proposal = liveIndex, proposal.noteID == id else { return false }
        let account = liveAccount
        liveIndex = nil
        let outcome = await saveLive(proposal.indexID, body: proposal.content, version: proposal.version)
        return stillLive(account) && outcome == .saved
    }
}

/// One quiet line on a Vault screen: loading, or what failed with a Try again.
struct VaultLiveLine: View {
    let text: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button {
                    Haptics.tap()
                    retry()
                } label: {
                    Text("Try again")
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
