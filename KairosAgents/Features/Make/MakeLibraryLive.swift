import SwiftUI
import UIKit

/// The libraries under Studio, on the paired desktop: formats (read), style packs (list, versions, new from a brief,
/// a starter, edit, make a sample), characters (list, versions, new, edit, make a sheet), connections (on or off, read
/// only) and templates (read only). Importing, exporting, sharing and duplicating packs, every connections change,
/// adding a team, and approving or rejecting a version stay on the desktop (Approvals already owns the last one).
///
/// Nothing here can post anything or let a pack or character be used without the person's approval: a pack or character
/// version made here is a draft, and only the person's approval (in Approvals) makes one usable (checked in
/// core/style_pack_store.py usable and core/character_store.py, and in services/content_studio/handsoff.py, whose
/// Producer approves posts only). So hands-off posting does not gate these controls.
///
/// A model run (a pack from a brief) and minutes of rendering (a sample, a sheet) take no request id on the desktop. Each
/// is kept "unconfirmed" in this shared store by account and item before the request leaves, and a lost answer is only
/// ever settled by reading the desktop again.
/// Unpaired, nothing here runs and the libraries are the sample screens.
nonisolated enum MakeLibraryPart: Hashable, Sendable {
    case formats, packs, characters, connections, templates
}

nonisolated enum MakeLibraryLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// How one change to the desktop ended.
nonisolated enum MakeLibraryOutcome: Equatable, Sendable {
    case done(String)
    /// The desktop said no, so it certainly did not do it.
    case refused(String)
    /// The answer never arrived. The desktop may have done it.
    case unconfirmed(String)
    /// Not sent: another change to the same thing is still on its way.
    case busy

    var line: String {
        switch self {
        case .done(let text), .refused(let text), .unconfirmed(let text): text
        case .busy: "The last change to this is still on its way to your desktop."
        }
    }
}

nonisolated enum MakeLibraryVerdict: Sendable {
    case applied, notApplied, unknown
}

/// A change that left the phone and has no answer yet, or whose answer was lost.
nonisolated struct MakeLibraryPending: Hashable, Sendable {
    var key: String
    var lost = false
    var note = ""
}

/// The desktop's own state said the change should not go ahead (a pack that moved on since the form was read).
nonisolated struct MakeLibraryChanged: Error, Sendable {
    var words: String
}

nonisolated struct MakeLibrarySnapshot: Sendable {
    var formats: [MakeLibraryFormatDTO]?
    var ports: [MakeLibraryPortDTO]?
    var packs: MakeLibraryPackList?
    var characters: [MakeLibraryCharacterDTO]?
    var connections: MakeLibraryConnections?
    var niches: [MakeLibraryNicheDTO]?
    var templates: [MakeLibraryTemplateDTO]?
    var skipped = 0
}

// MARK: - Forms

nonisolated enum MakeLibraryPackField: String, CaseIterable, Hashable, Sendable {
    case name, summary, brief, mood, captions, captionCase, voice
}

/// A style pack's edit form. It remembers the desktop values and the version number it was filled from. A read under
/// it only moves the fields the person has not touched, and a save sends only the fields the person changed.
@Observable
final class MakeLibraryPackForm {
    private(set) var shown: [MakeLibraryPackField: String] = [:]
    private(set) var base: [MakeLibraryPackField: String] = [:]
    private(set) var touched: Set<MakeLibraryPackField> = []
    private(set) var baseVersion: Int

    init?(_ pack: MakeLibraryPackDTO) {
        guard let values = Self.values(pack), let latest = pack.latest else { return nil }
        shown = values
        base = values
        baseVersion = latest.number
    }

    static func values(_ pack: MakeLibraryPackDTO) -> [MakeLibraryPackField: String]? {
        guard let spec = pack.spec else { return nil }
        return [.name: spec.name, .summary: spec.summary, .brief: spec.brief, .mood: spec.mood,
                .captions: spec.captionsOn ? "on" : "off", .captionCase: spec.captionCase, .voice: spec.voice]
    }

    func set(_ field: MakeLibraryPackField, _ value: String) {
        shown[field] = value
        if value == base[field] { touched.remove(field) } else { touched.insert(field) }
    }

    /// A read came back: untouched fields follow the desktop, edited ones keep what the person typed.
    func refill(_ pack: MakeLibraryPackDTO) {
        guard let values = Self.values(pack), let latest = pack.latest else { return }
        baseVersion = latest.number
        for field in MakeLibraryPackField.allCases {
            let now = values[field] ?? ""
            base[field] = now
            if touched.contains(field) {
                if shown[field] == now { touched.remove(field) }
            } else {
                shown[field] = now
            }
        }
    }

    /// The fields the person changed that still differ from the desktop.
    var changes: [MakeLibraryPackField: String] {
        var out: [MakeLibraryPackField: String] = [:]
        for field in touched {
            if let value = shown[field], value != base[field] { out[field] = value }
        }
        return out
    }

    func settle(_ sent: [MakeLibraryPackField: String]) {
        for (field, value) in sent where shown[field] == value { touched.remove(field) }
    }

    private static let voicePattern = try? NSRegularExpression(pattern: "^[a-z]{2}_[a-z0-9]{1,30}$")

    static func problem(_ sent: [MakeLibraryPackField: String]) -> String? {
        if let name = sent[.name] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.count > MakeLibraryWire.nameLimit { return "The name is 1 to 60 characters." }
        }
        if let summary = sent[.summary], summary.count > 300 { return "The summary can be up to 300 characters." }
        if let brief = sent[.brief], brief.count > MakeLibraryWire.briefLimit { return "The director brief can be up to 12000 characters." }
        if let voice = sent[.voice] {
            let range = NSRange(voice.startIndex..., in: voice)
            if voicePattern?.firstMatch(in: voice, range: range) == nil { return "The narrator voice is a voice id like af_heart." }
        }
        return nil
    }

    /// The desktop's own names for the changed fields (it merges them over the latest version).
    static func body(_ sent: [MakeLibraryPackField: String]) -> [String: Any] {
        var out: [String: Any] = [:]
        var captions: [String: Any] = [:]
        for (field, value) in sent {
            switch field {
            case .name: out["name"] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            case .summary: out["summary"] = value
            case .brief: out["director_brief"] = value
            case .mood: out["music"] = ["mood": value]
            case .captions: captions["on"] = value == "on"
            case .captionCase: captions["case"] = value
            case .voice: out["voice"] = ["voice": value]
            }
        }
        if !captions.isEmpty { out["captions"] = captions }
        return out
    }
}

nonisolated enum MakeLibraryCharacterField: String, CaseIterable, Hashable, Sendable {
    case name, accessory, body, accent
}

/// A character's edit form, with the same rules as the pack's.
@Observable
final class MakeLibraryCharacterForm {
    private(set) var shown: [MakeLibraryCharacterField: String] = [:]
    private(set) var base: [MakeLibraryCharacterField: String] = [:]
    private(set) var touched: Set<MakeLibraryCharacterField> = []
    private(set) var baseVersion: Int
    /// A block character's colours come from its outfit, which the phone does not edit.
    private(set) var blocky: Bool

    init?(_ character: MakeLibraryCharacterDTO) {
        guard let values = Self.values(character), let latest = character.latest else { return nil }
        shown = values
        base = values
        baseVersion = latest.number
        blocky = character.spec?.form == "block"
    }

    static func values(_ character: MakeLibraryCharacterDTO) -> [MakeLibraryCharacterField: String]? {
        guard let spec = character.spec else { return nil }
        return [.name: spec.name, .accessory: spec.accessory, .body: spec.body, .accent: spec.accent]
    }

    func set(_ field: MakeLibraryCharacterField, _ value: String) {
        shown[field] = value
        if value == base[field] { touched.remove(field) } else { touched.insert(field) }
    }

    func refill(_ character: MakeLibraryCharacterDTO) {
        guard let values = Self.values(character), let latest = character.latest else { return }
        baseVersion = latest.number
        blocky = character.spec?.form == "block"
        for field in MakeLibraryCharacterField.allCases {
            let now = values[field] ?? ""
            base[field] = now
            if touched.contains(field) {
                if shown[field] == now { touched.remove(field) }
            } else {
                shown[field] = now
            }
        }
    }

    var changes: [MakeLibraryCharacterField: String] {
        var out: [MakeLibraryCharacterField: String] = [:]
        for field in touched {
            if let value = shown[field], value != base[field] { out[field] = value }
        }
        return out
    }

    func settle(_ sent: [MakeLibraryCharacterField: String]) {
        for (field, value) in sent where shown[field] == value { touched.remove(field) }
    }

    private static let namePattern = try? NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9 '-]{0,39}$")

    static func problem(_ sent: [MakeLibraryCharacterField: String]) -> String? {
        if let name = sent[.name] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if namePattern?.firstMatch(in: trimmed, range: range) == nil {
                return "A name is 1 to 40 letters, numbers, spaces, apostrophes or dashes, starting with a letter."
            }
        }
        return nil
    }

    static func body(_ sent: [MakeLibraryCharacterField: String]) -> [String: Any] {
        var out: [String: Any] = [:]
        var palette: [String: Any] = [:]
        for (field, value) in sent {
            switch field {
            case .name: out["name"] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            case .accessory: out["accessory"] = value
            case .body: palette["body"] = value
            case .accent: palette["accent"] = value
            }
        }
        if !palette.isEmpty { out["palette"] = palette }
        return out
    }
}

// MARK: - The shared store

@Observable
final class MakeLibraryLive {
    static let shared = MakeLibraryLive()

    private(set) var isLive = false
    private(set) var account = "sample"
    private(set) var loads: [MakeLibraryPart: MakeLibraryLoad] = [:]
    /// One line per part when a refresh failed. What was read before stays on screen.
    private(set) var problems: [MakeLibraryPart: String] = [:]
    private(set) var formats: [MakeLibraryFormatDTO] = []
    private(set) var ports: [MakeLibraryPortDTO] = []
    private(set) var packs: [MakeLibraryPackDTO] = []
    private(set) var builtIn: [MakeLibraryNamedDTO] = []
    private(set) var starters: [MakeLibraryNamedDTO] = []
    private(set) var characters: [MakeLibraryCharacterDTO] = []
    private(set) var connections = MakeLibraryConnections()
    private(set) var niches: [MakeLibraryNicheDTO] = []
    private(set) var templates: [MakeLibraryTemplateDTO] = []
    private(set) var skipped = 0
    /// Changes that have left the phone and are not settled, by account and item. Never cleared by a screen.
    private(set) var pendingMap: [String: MakeLibraryPending] = [:]
    private(set) var packForms: [String: MakeLibraryPackForm] = [:]
    private(set) var characterForms: [String: MakeLibraryCharacterForm] = [:]

    @ObservationIgnored private var verifiers: [String: () -> MakeLibraryVerdict] = [:]
    @ObservationIgnored private var serials: [MakeLibraryPart: Int] = [:]

    // MARK: Connection

    static var paired: Bool { !Connection.shared.usesSampleData }

    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    func stillLive(_ key: String) -> Bool {
        isLive && account == key && Self.accountKey == key
    }

    /// Follow pairing: paired starts empty, unpaired forgets everything. Safe to call from every library screen.
    func follow() {
        let key = Self.accountKey
        if Self.paired {
            guard !isLive || account != key else { return }
            reset()
            isLive = true
            account = key
        } else if isLive {
            reset()
            isLive = false
            account = "sample"
        }
    }

    private func reset() {
        for part in [MakeLibraryPart.formats, .packs, .characters, .connections, .templates] { serials[part, default: 0] += 1 }
        loads = [:]
        problems = [:]
        formats = []
        ports = []
        packs = []
        builtIn = []
        starters = []
        characters = []
        connections = MakeLibraryConnections()
        niches = []
        templates = []
        skipped = 0
        packForms = [:]
        characterForms = [:]
    }

    private func client() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    // MARK: Reading

    /// Everything these parts need has been read from this desktop.
    func ready(_ parts: [MakeLibraryPart]) -> Bool {
        isLive && account == Self.accountKey && parts.allSatisfy { loads[$0] == .loaded }
    }

    func state(_ parts: [MakeLibraryPart]) -> MakeLibraryLoad {
        for part in parts {
            if case .failed(let why) = loads[part] ?? .idle { return .failed(why) }
        }
        return .loading
    }

    func firstProblem(_ parts: [MakeLibraryPart]) -> String? {
        parts.compactMap { problems[$0] }.first
    }

    func loadIfNeeded(_ parts: [MakeLibraryPart]) async {
        for part in parts {
            switch loads[part] ?? .idle {
            case .idle, .failed: await load(part)
            case .loading, .loaded: break
            }
        }
    }

    func reload(_ parts: [MakeLibraryPart]) async {
        for part in parts { await load(part) }
    }

    /// Read one part of the libraries. An older read never replaces a newer one, and what was read before stays on screen
    /// while this runs. `quiet` leaves the loading note alone (a poll or a read after a change).
    @discardableResult
    func load(_ part: MakeLibraryPart, quiet: Bool = false) async -> Bool {
        guard isLive else { return false }
        let key = account
        serials[part, default: 0] += 1
        let mine = serials[part] ?? 0
        if !quiet, loads[part] != .loaded { loads[part] = .loading }
        do {
            let snapshot = try await fetch(part, try client())
            guard stillLive(key), mine == serials[part] else { return false }
            apply(snapshot)
            loads[part] = .loaded
            problems[part] = nil
            return true
        } catch {
            if error is CancellationError || Task.isCancelled {
                if mine == serials[part], loads[part] == .loading { loads[part] = .idle }
                return false
            }
            Connection.shared.note(error)
            guard stillLive(key), mine == serials[part] else { return false }
            if loads[part] != .loaded {
                loads[part] = .failed("This could not be read from your desktop. " + error.plainWords)
            } else {
                problems[part] = "This could not be refreshed. " + error.plainWords
            }
            return false
        }
    }

    private func fetch(_ part: MakeLibraryPart, _ client: APIClient) async throws -> MakeLibrarySnapshot {
        var snapshot = MakeLibrarySnapshot()
        switch part {
        case .formats:
            let answer = try await client.makeLibraryFormats()
            guard let row = MakeLibraryRow(answer) else { throw APIError.unreadable("formats") }
            let formats = MakeLibraryWire.rows(row.list("formats"), MakeLibraryFormatDTO.init)
            let ports = MakeLibraryWire.rows(row.list("ports"), MakeLibraryPortDTO.init)
            snapshot.formats = formats.rows
            snapshot.ports = ports.rows
            snapshot.skipped = formats.skipped + ports.skipped
        case .packs:
            let answer = try await client.makeLibraryPacks()
            guard MakeLibraryRow(answer) != nil else { throw APIError.unreadable("style packs") }
            let list = MakeLibraryPackList(answer)
            snapshot.packs = list
            snapshot.skipped = list.skipped
        case .characters:
            let answer = try await client.makeLibraryCharacters()
            guard let row = MakeLibraryRow(answer) else { throw APIError.unreadable("characters") }
            let list = MakeLibraryWire.rows(row.list("characters"), MakeLibraryCharacterDTO.init)
            snapshot.characters = list.rows
            snapshot.skipped = list.skipped
        case .templates:
            snapshot.templates = try await client.makeLibraryTemplates().templates
        case .connections:
            var failures = 0
            var lastError: Error?
            func attempt<T>(_ work: () async throws -> T) async throws -> T? {
                do {
                    return try await work()
                } catch {
                    if error is CancellationError || Task.isCancelled { throw CancellationError() }
                    if let api = error as? APIError, api == .unauthorized { throw error }
                    failures += 1
                    lastError = error
                    return nil
                }
            }
            let youtube = try await attempt { try await client.makeLibraryYouTube() }
            let posting = try await attempt { try await client.makeLibraryPosting() }
            let social = try await attempt { try await client.makeLibrarySocial() }
            let settings = try await attempt { try await client.makeLibrarySettings() }
            let nicheAnswer = try await attempt { try await client.makeLibraryNiches() }
            if failures == 5, let lastError { throw lastError }
            snapshot.connections = MakeLibraryConnections(youtube: youtube, posting: posting, social: social, settings: settings)
            if let nicheAnswer {
                snapshot.niches = MakeLibraryWire.rows(MakeLibraryRow(nicheAnswer)?.list("niches") ?? [], MakeLibraryNicheDTO.init).rows
            }
        }
        return snapshot
    }

    private func apply(_ snapshot: MakeLibrarySnapshot) {
        skipped = snapshot.skipped
        if let found = snapshot.formats { formats = found }
        if let found = snapshot.ports { ports = found }
        if let list = snapshot.packs {
            packs = list.packs
            builtIn = list.builtIn
            starters = list.starters
            // An open edit form moves only its untouched fields.
            for pack in list.packs { packForms[pack.id]?.refill(pack) }
        }
        if let found = snapshot.characters { characters = found }
        if let found = snapshot.connections { connections = found }
        if let found = snapshot.niches { niches = found }
        if let found = snapshot.templates { templates = found }
    }

    // MARK: Watching the desktop

    /// A sample is rendering, or a change is not settled.
    var needsWatching: Bool {
        let prefix = account + "|"
        if pendingMap.keys.contains(where: { $0.hasPrefix(prefix) }) { return true }
        return packs.contains { pack in pack.versions.contains { MakeLibraryPackState.of($0) == .rendering } }
    }

    /// Read the desktop again every few seconds while something is rendering or not settled, so progress is the
    /// desktop's own state. Ends when the screen goes away.
    func watch() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, isLive else { continue }
            if needsWatching {
                await load(.packs, quiet: true)
                await load(.characters, quiet: true)
            }
        }
    }

    // MARK: Pending changes

    private static func slot(_ account: String, _ key: String) -> String { account + "|" + key }

    func pending(_ key: String) -> MakeLibraryPending? { pendingMap[Self.slot(account, key)] }

    func isBusy(_ key: String) -> Bool { pending(key) != nil }

    /// On its way right now (a lost answer is not "writing": the sheet may close).
    func isWriting(_ key: String) -> Bool {
        guard let pending = pending(key) else { return false }
        return !pending.lost
    }

    /// The desktop refused the request, so it certainly did not do it.
    private static func wasRefused(_ error: Error) -> Bool {
        if error is MakeLibraryChanged { return true }
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, let detail):
            // 503 with the desktop's own sentence is its "the desktop app is not open" answer, given before any work.
            return (400..<500).contains(status) || (status == 503 && !detail.isEmpty)
        case .offline, .unreadable: return false
        }
    }

    private func perform(_ key: String, done: String, notApplied: String, lostLine: String, reload: [MakeLibraryPart],
                         verify: @escaping () -> MakeLibraryVerdict,
                         send: (APIClient) async throws -> String?) async -> MakeLibraryOutcome {
        guard isLive else { return .busy }
        let acct = account
        guard stillLive(acct), pending(key) == nil else { return .busy }
        let slot = Self.slot(acct, key)
        // Set before the request leaves: nothing turns this back on until the desktop shows the result or says no.
        pendingMap[slot] = MakeLibraryPending(key: key)
        verifiers[slot] = verify
        var outcome: MakeLibraryOutcome
        do {
            let message = try await send(try client())
            pendingMap[slot] = nil
            verifiers[slot] = nil
            outcome = .done(message ?? done)
        } catch {
            Connection.shared.note(error)
            if Self.wasRefused(error) {
                pendingMap[slot] = nil
                verifiers[slot] = nil
                outcome = .refused((error as? MakeLibraryChanged)?.words ?? error.plainWords)
            } else {
                pendingMap[slot]?.lost = true
                pendingMap[slot]?.note = lostLine
                outcome = .unconfirmed(lostLine)
            }
        }
        guard stillLive(acct) else { return outcome }
        for part in reload { await load(part, quiet: true) }
        if case .unconfirmed = outcome, stillLive(acct), let check = verifiers[slot] {
            switch check() {
            case .applied:
                pendingMap[slot] = nil
                verifiers[slot] = nil
                return .done(done)
            case .notApplied:
                pendingMap[slot] = nil
                verifiers[slot] = nil
                return .refused(notApplied)
            case .unknown:
                break
            }
        }
        return outcome
    }

    /// Read the desktop again for a change whose answer was lost, and say what it has. Never sends anything.
    func checkAgain(_ key: String) async -> String {
        guard isLive else { return "" }
        let acct = account
        let slot = Self.slot(acct, key)
        guard pendingMap[slot]?.lost == true else { return "" }
        let readPacks = await load(.packs, quiet: true)
        let readCharacters = await load(.characters, quiet: true)
        guard stillLive(acct), pendingMap[slot]?.lost == true else { return "" }
        guard readPacks, readCharacters else { return "Your desktop did not answer. It is still not confirmed." }
        switch verifiers[slot]?() ?? .unknown {
        case .applied:
            pendingMap[slot] = nil
            verifiers[slot] = nil
            return "Your desktop has it."
        case .notApplied:
            pendingMap[slot] = nil
            verifiers[slot] = nil
            return "Your desktop does not have it, so nothing was changed."
        case .unknown:
            return "Your desktop shows nothing new yet. This stays off so it is not sent twice."
        }
    }

    private func lostWords(_ what: String) -> String {
        "Your desktop did not confirm \(what). It may already be doing it. Check again reads your desktop; nothing is sent twice."
    }

    // MARK: Looking things up

    func pack(_ id: String) -> MakeLibraryPackDTO? { packs.first { $0.id == id } }
    func character(_ id: String) -> MakeLibraryCharacterDTO? { characters.first { $0.id == id } }

    /// The characters of a pack's cast whose sheet is not approved: the ones whose sheet the desktop must render first,
    /// and the ones whose sheet already waits for the person.
    func castNeedingSheets(_ pack: MakeLibraryPackDTO) -> (render: [String], waiting: [String]) {
        var render: [String] = []
        var waiting: [String] = []
        for entry in pack.spec?.cast ?? [] {
            guard let found = character(entry.character), let version = found.versions.first(where: { $0.number == entry.version }) else { continue }
            if version.status == "awaiting_approval" { waiting.append(found.name) } else if version.status != "approved" { render.append(found.name) }
        }
        return (render, waiting)
    }

    private func castStatuses(_ pack: MakeLibraryPackDTO) -> [String: String] {
        var out: [String: String] = [:]
        for entry in pack.spec?.cast ?? [] {
            let status = character(entry.character)?.versions.first(where: { $0.number == entry.version })?.status ?? ""
            out[entry.character + "#" + String(entry.version)] = status
        }
        return out
    }

    // MARK: Changes: packs

    /// A pack from a written brief: a model run on the desktop's first model connection, which can cost money. Takes no
    /// request id, so a lost answer is settled only by finding the pack, made from this brief, on the desktop.
    func createPackFromBrief(_ brief: String, name: String) async -> MakeLibraryOutcome {
        let text = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .refused("Write the brief first.") }
        guard text.count <= MakeLibraryWire.briefLimit else { return .refused("Keep the brief under 12000 characters.") }
        guard title.count <= MakeLibraryWire.nameLimit else { return .refused("The name is up to 60 characters.") }
        let before = Set(packs.map(\.id))
        return await perform("brief", done: "Pack made as a draft. Make its sample to send it for your OK.",
                             notApplied: "Your desktop did not make the pack.",
                             lostLine: "Your desktop did not confirm the pack. The model run may still be going, or it may be done. This stays off so a second model run is not started. Check again reads your desktop.",
                             reload: [.packs, .characters],
                             verify: { [weak self] in
                                 guard let self else { return .unknown }
                                 let found = self.packs.contains { !before.contains($0.id) && $0.originKind == "brief"
                                     && $0.originBrief.trimmingCharacters(in: .whitespacesAndNewlines) == text }
                                 return found ? .applied : .unknown
                             },
                             send: { client in
                                 try await client.makeLibraryCreateFromBrief(brief: text, name: title)
                                 return nil
                             })
    }

    /// A shipped starter pack, as a draft with its starter characters. No model run and no rendering.
    func installStarter(_ id: String) async -> MakeLibraryOutcome {
        guard starters.contains(where: { $0.id == id }) else { return .refused("That starter pack is not on your desktop.") }
        return await perform("starter:" + id, done: "Starter pack added as a draft. Make its sample to send it for your OK.",
                             notApplied: "Your desktop did not add the starter pack.", lostLine: lostWords("the starter pack"),
                             reload: [.packs, .characters],
                             verify: { [weak self] in
                                 guard let self else { return .unknown }
                                 return self.packs.contains { $0.originKind == "starter" && $0.originFrom == id } ? .applied : .unknown
                             },
                             send: { client in
                                 try await client.makeLibraryInstallStarter(id)
                                 return nil
                             })
    }

    /// Render a pack version's sample on the desktop (minutes). When a character of the pack has no approved sheet, the
    /// desktop first renders those sheets inside the same request.
    func makeSample(_ packID: String, version: Int) async -> MakeLibraryOutcome {
        guard let pack = pack(packID), let found = pack.versions.first(where: { $0.number == version }) else {
            return .refused("That pack is not on your desktop.")
        }
        let state = MakeLibraryPackState.of(found)
        guard state == .draft || state == .rejected || state == .failed || state == .waitingSheets else {
            return .refused("This version cannot make a sample right now.")
        }
        let key = "sample:\(packID)#\(version)"
        let sampleAt = found.sample?.at
        let cast = castStatuses(pack)
        return await perform(key, done: "Your desktop started the sample. It takes a few minutes.",
                             notApplied: "Your desktop did not start the sample.",
                             lostLine: lostWords("the sample"), reload: [.packs, .characters],
                             verify: { [weak self] in
                                 guard let self, let now = self.pack(packID), let current = now.versions.first(where: { $0.number == version }) else { return .unknown }
                                 let changed = current.sample?.at != sampleAt || current.status == "awaiting_approval"
                                     || self.castStatuses(now) != cast
                                 return changed ? .applied : .unknown
                             },
                             send: { client in
                                 try await client.makeLibraryMakeSample(packID, version: version)
                                 return nil
                             })
    }

    // MARK: Changes: pack edit form

    func openPackForm(_ id: String) {
        guard packForms[id] == nil, let pack = pack(id), let form = MakeLibraryPackForm(pack) else { return }
        packForms[id] = form
    }

    func closePackForm(_ id: String) { packForms[id] = nil }

    /// Save the form: only the fields the person changed, as a new draft version. The desktop has no base check, so the
    /// pack is read first, and a pack that moved on since the form was filled is shown again instead of being written over.
    func savePack(_ packID: String, note: String) async -> MakeLibraryOutcome {
        guard let form = packForms[packID] else { return .refused("This pack is not on your desktop.") }
        let sent = form.changes
        guard !sent.isEmpty else { return .refused("Change something first.") }
        if let problem = MakeLibraryPackForm.problem(sent) { return .refused(problem) }
        let baseVersion = form.baseVersion
        let words = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = await perform("editpack:" + packID, done: "Saved as a new draft version. Make its sample to send it for your OK.",
                                    notApplied: "Your desktop did not save these changes. What you typed is still here.",
                                    lostLine: lostWords("the new version"), reload: [.packs],
                                    verify: { [weak self] in
                                        guard let self, let now = self.pack(packID), let latest = now.latest,
                                              let values = MakeLibraryPackForm.values(now) else { return .unknown }
                                        guard latest.number > baseVersion else { return .notApplied }
                                        let same = sent.allSatisfy { field, value in
                                            field == .name ? (values[field] ?? "").hasPrefix(value.trimmingCharacters(in: .whitespacesAndNewlines)) : values[field] == value
                                        }
                                        return same ? .applied : .unknown
                                    },
                                    send: { client in
                                        let answer = try await client.makeLibraryPack(packID)
                                        guard let row = MakeLibraryRow(answer), let current = MakeLibraryPackDTO(row), let latest = current.latest else {
                                            throw MakeLibraryChanged(words: "Your desktop sent this pack in a form this app could not read. Nothing was saved.")
                                        }
                                        if latest.number != baseVersion {
                                            form.refill(current)
                                            throw MakeLibraryChanged(words: "This pack changed on your desktop since you opened it. It is shown again with your edits kept. Check it, then save again.")
                                        }
                                        try await client.makeLibraryNewPackVersion(packID, changes: MakeLibraryPackForm.body(sent),
                                                                                    note: words.isEmpty ? "Edited in the iPhone app." : words)
                                        return nil
                                    })
        if case .done = outcome { form.settle(sent) }
        return outcome
    }

    // MARK: Changes: characters

    func createCharacter(family: String, name: String) async -> MakeLibraryOutcome {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let wire = family.lowercased()
        guard ["round", "square", "triangle"].contains(wire) else { return .refused("Choose round, square or triangle.") }
        if !title.isEmpty {
            let probe = MakeLibraryCharacterForm.problem([.name: title])
            if let probe { return .refused(probe) }
        }
        let before = Set(characters.map(\.id))
        return await perform("newcharacter", done: "Character made as a draft. Make its sheet to send it for your OK.",
                             notApplied: "Your desktop did not make the character.", lostLine: lostWords("the character"),
                             reload: [.characters],
                             verify: { [weak self] in
                                 guard let self else { return .unknown }
                                 let found = self.characters.contains { !before.contains($0.id) && $0.family == wire
                                     && (title.isEmpty || $0.name.lowercased() == title.lowercased()) }
                                 return found ? .applied : .unknown
                             },
                             send: { client in
                                 try await client.makeLibraryCreateCharacter(family: wire, name: title)
                                 return nil
                             })
    }

    /// Open a character's edit form. Reads the character with its spec, so the form is filled from one desktop answer.
    /// Returns a plain sentence when it cannot be opened.
    func openCharacterForm(_ id: String) async -> String? {
        guard isLive else { return "This iPhone is not paired with a desktop." }
        let key = account
        do {
            let answer = try await client().makeLibraryCharacter(id)
            guard stillLive(key) else { return "Your desktop changed. Try again." }
            guard let row = MakeLibraryRow(answer), let dto = MakeLibraryCharacterDTO(row), dto.spec != nil,
                  let form = MakeLibraryCharacterForm(dto) else {
                return "Your desktop sent this character in a form this app could not read."
            }
            if let existing = characterForms[id] { existing.refill(dto) } else { characterForms[id] = form }
            return nil
        } catch {
            if error is CancellationError || Task.isCancelled { return "" }
            Connection.shared.note(error)
            return "This character could not be read from your desktop. " + error.plainWords
        }
    }

    func closeCharacterForm(_ id: String) { characterForms[id] = nil }

    func saveCharacter(_ id: String, note: String) async -> MakeLibraryOutcome {
        guard let form = characterForms[id] else { return .refused("This character is not on your desktop.") }
        let sent = form.changes
        guard !sent.isEmpty else { return .refused("Change something first.") }
        if let problem = MakeLibraryCharacterForm.problem(sent) { return .refused(problem) }
        let baseVersion = form.baseVersion
        let words = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteSent = words.isEmpty ? "Edited in the iPhone app." : words
        let outcome = await perform("editchar:" + id, done: "Saved as a new draft version. Make its sheet to send it for your OK.",
                                    notApplied: "Your desktop did not save these changes. What you typed is still here.",
                                    lostLine: lostWords("the new version"), reload: [.characters],
                                    verify: { [weak self] in
                                        guard let self, let now = self.character(id), let latest = now.latest else { return .unknown }
                                        guard latest.number > baseVersion else { return .notApplied }
                                        let mine = now.versions.contains { $0.number > baseVersion && $0.note == noteSent }
                                        return mine ? .applied : .unknown
                                    },
                                    send: { client in
                                        let answer = try await client.makeLibraryCharacter(id)
                                        guard let row = MakeLibraryRow(answer), let current = MakeLibraryCharacterDTO(row), let latest = current.latest else {
                                            throw MakeLibraryChanged(words: "Your desktop sent this character in a form this app could not read. Nothing was saved.")
                                        }
                                        if latest.number != baseVersion {
                                            form.refill(current)
                                            throw MakeLibraryChanged(words: "This character changed on your desktop since you opened it. It is shown again with your edits kept. Check it, then save again.")
                                        }
                                        try await client.makeLibraryNewCharacterVersion(id, changes: MakeLibraryCharacterForm.body(sent), note: noteSent)
                                        return nil
                                    })
        if case .done = outcome { form.settle(sent) }
        return outcome
    }

    /// Render a version's reference sheet on the desktop (minutes of rendering inside one request).
    func makeSheet(_ id: String, version: Int) async -> MakeLibraryOutcome {
        guard let found = character(id), let current = found.versions.first(where: { $0.number == version }) else {
            return .refused("That character is not on your desktop.")
        }
        guard current.status == "draft" || current.status == "rejected" else { return .refused("This version cannot make a sheet right now.") }
        let before = current.status
        return await perform("sheet:\(id)#\(version)", done: "Sheet made. It is waiting for your OK in Approvals.",
                             notApplied: "Your desktop did not make the sheet.", lostLine: lostWords("the sheet"),
                             reload: [.characters],
                             verify: { [weak self] in
                                 guard let status = self?.character(id)?.versions.first(where: { $0.number == version })?.status else { return .unknown }
                                 return status != before ? .applied : .unknown
                             },
                             send: { client in
                                 try await client.makeLibraryMakeSheet(id, version: version)
                                 return nil
                             })
    }
}

// MARK: - Words and small helpers

nonisolated enum MakeLibraryWords {
    static let packFiles = "Importing, exporting, sharing and duplicating packs, and watching a pack's sample, are done in Kairos on your desktop."
    static let approvals = "Approving or rejecting a version is done in Approvals."
    static let connections = "Connecting accounts, upload privacy, page reads, syncing numbers, adding a channel and social app keys are changed in Kairos on your desktop."
    static let templates = "Adding a team is done in Kairos on your desktop."
    static let blockColours = "A block character's colours come from its outfit. Change them in Kairos on your desktop."

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return formatter.string(from: date)
    }

    static func lengthText(_ low: Double, _ high: Double) -> String {
        func one(_ seconds: Double) -> String {
            seconds >= 120 ? "\(Int((seconds / 60).rounded())) min" : "\(Int(seconds.rounded())) s"
        }
        if low <= 0 && high <= 0 { return "Length not given" }
        return low == high ? one(low) : one(low) + " to " + one(high)
    }

    static func originText(_ kind: String) -> String {
        switch kind {
        case "brief": "Made from a written brief"
        case "starter": "Starter pack"
        case "duplicate": "Duplicated"
        case "import": "Imported"
        case "shared": "Shared"
        default: ""
        }
    }

    static func checkTitle(_ key: String) -> String {
        let words = key.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func rgb(_ hex: String) -> UInt32? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        return digits.count == 6 ? UInt32(digits, radix: 16) : nil
    }

    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}

/// What a style pack version is doing, in the desktop's own words.
nonisolated enum MakeLibraryPackState: Hashable, Sendable {
    case draft, rendering, waitingSheets, failed, awaiting, approved, rejected

    var label: String {
        switch self {
        case .draft: "Draft, no sample yet"
        case .rendering: "Rendering its sample"
        case .waitingSheets: "Waiting for character sheets"
        case .failed: "Sample failed"
        case .awaiting: "Waiting for your OK"
        case .approved: "Approved"
        case .rejected: "Rejected"
        }
    }

    var tone: PillTone {
        switch self {
        case .draft: .muted
        case .rendering, .waitingSheets: .working
        case .failed, .rejected: .error
        case .awaiting: .gold
        case .approved: .ok
        }
    }

    static func of(_ version: MakeLibraryPackVersionDTO) -> MakeLibraryPackState {
        if version.status == "approved" { return .approved }
        let sample = version.sample?.status ?? ""
        if sample == "rendering" { return .rendering }
        if sample.hasPrefix("waiting") { return .waitingSheets }
        if version.status == "awaiting_approval" { return .awaiting }
        if sample.hasPrefix("failed") { return .failed }
        return version.status == "rejected" ? .rejected : .draft
    }
}

// MARK: - Views: shared parts

/// Shows the libraries' content once the desktop has been read, and a plain line (with Try again) until then.
struct MakeLibraryGate<Content: View>: View {
    let parts: [MakeLibraryPart]
    @ViewBuilder var content: Content
    private let live = MakeLibraryLive.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if live.ready(parts) {
                if let problem = live.firstProblem(parts) {
                    MakeHomeLine(text: problem, action: "Refresh") { Task { await live.reload(parts) } }
                }
                content
            } else if case .failed(let why) = live.state(parts) {
                MakeHomeLine(text: why, action: "Try again") { Task { await live.reload(parts) } }
            } else {
                MakeHomeLine(text: "Reading from your desktop.")
            }
        }
        .task(id: MakeLibraryLive.connectionKey) {
            live.follow()
            await live.loadIfNeeded(parts)
        }
    }
}

/// A change on its way to the desktop, or one whose answer was lost, with Check again.
struct MakeLibraryPendingLine: View {
    let key: String
    @Environment(MakeToast.self) private var toast
    private let live = MakeLibraryLive.shared

    var body: some View {
        if let pending = live.pending(key) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !pending.lost { PulsingDot(color: Palette.working, size: 7) }
                    Text(pending.lost ? pending.note : "Sending to your desktop.")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if pending.lost {
                    MakePillButton(title: "Check again") {
                        Task {
                            let line = await live.checkAgain(key)
                            if !line.isEmpty { toast.say(line) }
                        }
                    }
                }
            }
        }
    }
}

/// A confirm that names what will be made and what it uses.
struct MakeLibraryConfirmSheet: View {
    let title: String
    let detail: String?
    let points: [String]
    let button: String
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 440) {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: title, detail: detail)
                MakeLibraryPoints(points: points)
                GoldButton(title: button) {
                    Haptics.success()
                    action()
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

struct MakeLibraryPoints: View {
    let points: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Palette.gold).frame(width: 5, height: 5)
                    Text(point).font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Every sheet the live libraries open themselves. They never go through the Studio store's sheet.
nonisolated enum MakeLibrarySheet: Identifiable, Hashable, Sendable {
    case brief
    case starter(String)
    case editPack(String)
    case sample(String, Int)
    case newCharacter
    case editCharacter(String)
    case sheet(String, Int)

    var id: String { String(describing: self) }
}

struct MakeLibrarySheetView: View {
    let sheet: MakeLibrarySheet
    private let live = MakeLibraryLive.shared
    @Environment(MakeToast.self) private var toast

    var body: some View {
        switch sheet {
        case .brief:
            MakeLibraryBriefSheet()
        case .starter(let id):
            let starter = live.starters.first { $0.id == id }
            MakeLibraryConfirmSheet(title: "Add the \(starter?.name ?? "starter") pack?", detail: "A starter pack from Kairos.",
                                    points: ["Your desktop adds it as a draft, with its starter characters as drafts.",
                                             "No model run and no rendering. It costs nothing.",
                                             "Make its sample afterwards, then approve it in Approvals. Nothing uses it before that."],
                                    button: "Add the pack") {
                Task { toast.say(await live.installStarter(id).line) }
            }
        case .editPack(let id):
            MakeLibraryEditPackSheet(packID: id)
        case .sample(let id, let version):
            let pack = live.pack(id)
            MakeLibraryConfirmSheet(title: "Make a sample of version \(version)?", detail: pack?.name,
                                    points: samplePoints(pack), button: "Make the sample") {
                Task { toast.say(await live.makeSample(id, version: version).line) }
            }
        case .newCharacter:
            MakeLibraryNewCharacterSheet()
        case .editCharacter(let id):
            MakeLibraryEditCharacterSheet(characterID: id)
        case .sheet(let id, let version):
            let character = live.character(id)
            MakeLibraryConfirmSheet(title: "Make the sheet of version \(version)?", detail: character?.name,
                                    points: ["Your desktop renders this version's reference sheet. It takes a few minutes of your computer's rendering, and the Kairos desktop app has to stay open.",
                                             "The sheet then waits for your OK in Approvals. A video can only use an approved version."],
                                    button: "Make the sheet") {
                Task { toast.say(await live.makeSheet(id, version: version).line) }
            }
        }
    }

    private func samplePoints(_ pack: MakeLibraryPackDTO?) -> [String] {
        var points = ["Your desktop renders a short video in this pack. It takes a few minutes of your computer's rendering, and the Kairos desktop app has to stay open."]
        if let pack, live.ready([.characters]) {
            let needs = live.castNeedingSheets(pack)
            if !needs.render.isEmpty {
                points.append("First it renders the reference sheet of \(needs.render.joined(separator: ", ")) (a few minutes each) and sends it to Approvals. The sample then waits until you approve it.")
            }
            if !needs.waiting.isEmpty {
                points.append("The sheet of \(needs.waiting.joined(separator: ", ")) is already waiting for your OK in Approvals. The sample waits for it.")
            }
        } else {
            points.append("If a character in this pack has no approved sheet yet, your desktop renders that sheet first.")
        }
        points.append("When it is ready it waits for your OK in Approvals. Nothing uses the pack until you approve it.")
        return points
    }
}

// MARK: - Sheets

/// New style pack from a written brief: two steps, the second names the model run before anything is sent.
struct MakeLibraryBriefSheet: View {
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var brief = ""
    @State private var name = ""
    @State private var confirming = false
    @State private var message: String?
    private let live = MakeLibraryLive.shared

    var body: some View {
        let busy = live.isBusy("brief")
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if confirming {
                    MakeSheetTitle(title: "Make this pack?", detail: name.isEmpty ? "From your brief" : name)
                    MakeLibraryPoints(points: ["Your desktop sends your brief to a model: the first model connection it finds in Settings, Models. This is a model run and can cost money with that provider.",
                                               "The answer becomes a draft pack. Your desktop may also add starter characters as drafts for it.",
                                               "It takes a short while. Nothing uses the pack until you make its sample and approve it."])
                    if let message { Text(message).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
                    GoldButton(title: busy ? "Sending" : "Make the pack") { send() }
                        .disabled(busy)
                        .opacity(busy ? 0.5 : 1)
                    QuietButton(title: "Back") { confirming = false }
                        .disabled(busy)
                } else {
                    MakeSheetTitle(title: "New style pack", detail: "Describe the look and sound. Your desktop turns it into a pack.")
                    MakeField(label: "Brief", text: $brief, prompt: "Warm paper colours, hand-drawn arrows, calm narration...", limit: MakeLibraryWire.briefLimit, lines: 4...10)
                    MakeField(label: "Name (optional)", text: $name, limit: MakeLibraryWire.nameLimit)
                    if let message { Text(message).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
                    MakeLibraryPendingLine(key: "brief")
                    GoldButton(title: "Continue") {
                        guard !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { message = "Write the brief first."; return }
                        message = nil
                        confirming = true
                    }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                    QuietButton(title: "Cancel") { dismiss() }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet()
        .interactiveDismissDisabled(live.isWriting("brief"))
    }

    private func send() {
        message = nil
        Task {
            let outcome = await live.createPackFromBrief(brief, name: name)
            toast.say(outcome.line)
            switch outcome {
            case .done:
                Haptics.success()
                dismiss()
            case .refused(let line):
                message = line
                confirming = false
            case .unconfirmed, .busy:
                confirming = false
            }
        }
    }
}

struct MakeLibraryEditPackSheet: View {
    let packID: String
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var message: String?
    private let live = MakeLibraryLive.shared

    private static let moods = ["energetic", "calm", "warm", "dark", "playful"]
    private static let cases = ["sentence", "upper"]

    var body: some View {
        let key = "editpack:" + packID
        let busy = live.isBusy(key)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Edit style pack", detail: "Saving makes a new draft version. Only what you change is sent.")
                if let form = live.packForms[packID] {
                    MakeField(label: "Name", text: text(form, .name), limit: MakeLibraryWire.nameLimit)
                    MakeField(label: "Summary", text: text(form, .summary), limit: 300, lines: 2...4)
                    MakeField(label: "Director brief", text: text(form, .brief), limit: MakeLibraryWire.briefLimit, lines: 3...8)
                    VStack(spacing: 0) {
                        MakeChoiceRow(title: "Music mood", options: options(form, .mood, Self.moods).map(MakeLibraryWords.capitalized),
                                      selection: choice(form, .mood, options(form, .mood, Self.moods)))
                        MakeToggleRow(title: "Captions", isOn: Binding(get: { form.shown[.captions] == "on" }, set: { form.set(.captions, $0 ? "on" : "off") }))
                        MakeChoiceRow(title: "Caption case", options: options(form, .captionCase, Self.cases).map(MakeLibraryWords.capitalized),
                                      selection: choice(form, .captionCase, options(form, .captionCase, Self.cases)), last: true)
                    }
                    .kCard(radius: 18)
                    MakeField(label: "Narrator voice", text: text(form, .voice), prompt: "A voice id, like af_heart", limit: 40)
                    MakeField(label: "What changed", text: $note, limit: 300, lines: 1...3)
                    if let message { Text(message).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
                    MakeLibraryPendingLine(key: key)
                    let edited = !form.changes.isEmpty
                    GoldButton(title: busy ? "Saving" : "Save new version") { save() }
                        .disabled(busy || !edited)
                        .opacity(busy || !edited ? 0.5 : 1)
                } else {
                    MakeHomeLine(text: "This pack's settings could not be read from your desktop, so it cannot be edited here.")
                }
                QuietButton(title: "Close") { dismiss() }
                    .disabled(live.isWriting(key))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet()
        .interactiveDismissDisabled(live.isWriting(key))
        .onAppear { live.openPackForm(packID) }
        .onDisappear { live.closePackForm(packID) }
        .task { await live.load(.packs, quiet: true) }
    }

    /// The wire values the menu offers, with the current one added when it is not a known choice.
    private func options(_ form: MakeLibraryPackForm, _ field: MakeLibraryPackField, _ known: [String]) -> [String] {
        let current = form.shown[field] ?? ""
        return known.contains(current) || current.isEmpty ? known : known + [current]
    }

    private func text(_ form: MakeLibraryPackForm, _ field: MakeLibraryPackField) -> Binding<String> {
        Binding(get: { form.shown[field] ?? "" }, set: { form.set(field, $0) })
    }

    private func choice(_ form: MakeLibraryPackForm, _ field: MakeLibraryPackField, _ wires: [String]) -> Binding<String> {
        Binding(
            get: { MakeLibraryWords.capitalized(form.shown[field] ?? "") },
            set: { label in
                if let match = wires.first(where: { MakeLibraryWords.capitalized($0) == label }) { form.set(field, match) }
            }
        )
    }

    private func save() {
        message = nil
        Task {
            let outcome = await live.savePack(packID, note: note)
            toast.say(outcome.line)
            switch outcome {
            case .done:
                Haptics.success()
                dismiss()
            case .refused(let line):
                message = line
            case .unconfirmed, .busy:
                break
            }
        }
    }
}

struct MakeLibraryNewCharacterSheet: View {
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var family = "Round"
    @State private var name = ""
    @State private var message: String?
    private let live = MakeLibraryLive.shared

    var body: some View {
        let busy = live.isBusy("newcharacter")
        FittedSheet(estimate: 460) {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "New character", detail: "A draft from Kairos's own design. Make its sheet afterwards, then approve it.")
                GlassSwitch(items: ["Round", "Square", "Triangle"], selection: $family) { $0 }
                MakeField(label: "Name (optional)", text: $name, limit: 40)
                if let message { Text(message).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
                MakeLibraryPendingLine(key: "newcharacter")
                GoldButton(title: busy ? "Sending" : "Make character") { send() }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                QuietButton(title: "Cancel") { dismiss() }
                    .disabled(live.isWriting("newcharacter"))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled(live.isWriting("newcharacter"))
    }

    private func send() {
        message = nil
        Task {
            let outcome = await live.createCharacter(family: family, name: name)
            toast.say(outcome.line)
            switch outcome {
            case .done:
                Haptics.success()
                dismiss()
            case .refused(let line):
                message = line
            case .unconfirmed, .busy:
                break
            }
        }
    }
}

struct MakeLibraryEditCharacterSheet: View {
    let characterID: String
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var message: String?
    @State private var openError: String?
    private let live = MakeLibraryLive.shared

    private static let accessories = ["none", "scarf", "antenna", "leaf", "cap", "bow"]
    private static let swatches = ["#e8c39e", "#b9d2e3", "#d99a92", "#b5c7a5", "#cdbfd9", "#d9b260"]

    var body: some View {
        let key = "editchar:" + characterID
        let busy = live.isBusy(key)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "New version", detail: live.character(characterID)?.name)
                if let form = live.characterForms[characterID] {
                    MakeField(label: "Name", text: text(form, .name), limit: 40)
                    VStack(spacing: 0) {
                        MakeChoiceRow(title: "Accessory", options: accessoryOptions(form).map(MakeLibraryWords.capitalized),
                                      selection: Binding(get: { MakeLibraryWords.capitalized(form.shown[.accessory] ?? "none") },
                                                         set: { label in
                                                             if let match = accessoryOptions(form).first(where: { MakeLibraryWords.capitalized($0) == label }) { form.set(.accessory, match) }
                                                         }), last: true)
                    }
                    .kCard(radius: 18)
                    if form.blocky {
                        HintLine(text: MakeLibraryWords.blockColours)
                    } else {
                        swatchRow("Body", form, .body)
                        swatchRow("Accent", form, .accent)
                    }
                    MakeField(label: "What changed", text: $note, limit: 300)
                    if let message { Text(message).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
                    MakeLibraryPendingLine(key: key)
                    let edited = !form.changes.isEmpty
                    GoldButton(title: busy ? "Saving" : "Save new version") { save() }
                        .disabled(busy || !edited)
                        .opacity(busy || !edited ? 0.5 : 1)
                } else if let openError {
                    MakeHomeLine(text: openError, action: "Try again") { Task { await open() } }
                } else {
                    MakeHomeLine(text: "Reading this character from your desktop.")
                }
                QuietButton(title: "Close") { dismiss() }
                    .disabled(live.isWriting(key))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet()
        .interactiveDismissDisabled(live.isWriting(key))
        .task { await open() }
        .onDisappear { live.closeCharacterForm(characterID) }
    }

    private func open() async {
        openError = nil
        let problem = await live.openCharacterForm(characterID)
        if let problem, !problem.isEmpty { openError = problem }
    }

    private func accessoryOptions(_ form: MakeLibraryCharacterForm) -> [String] {
        let current = form.shown[.accessory] ?? "none"
        return Self.accessories.contains(current) ? Self.accessories : Self.accessories + [current]
    }

    private func text(_ form: MakeLibraryCharacterForm, _ field: MakeLibraryCharacterField) -> Binding<String> {
        Binding(get: { form.shown[field] ?? "" }, set: { form.set(field, $0) })
    }

    private func swatchRow(_ title: String, _ form: MakeLibraryCharacterForm, _ field: MakeLibraryCharacterField) -> some View {
        let current = (form.shown[field] ?? "").lowercased()
        var choices = Self.swatches
        if !current.isEmpty, !choices.contains(current) { choices.insert(current, at: 0) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(choices, id: \.self) { hex in
                        Button {
                            Haptics.select()
                            form.set(field, hex)
                        } label: {
                            Circle().fill(Color(hex: MakeLibraryWords.rgb(hex) ?? 0xCCCCCC)).frame(width: 36, height: 36)
                                .overlay(Circle().strokeBorder(current == hex ? Palette.gold : Palette.line, lineWidth: current == hex ? 3 : 1))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Colour \(hex)")
                        .accessibilityAddTraits(current == hex ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func save() {
        message = nil
        Task {
            let outcome = await live.saveCharacter(characterID, note: note)
            toast.say(outcome.line)
            switch outcome {
            case .done:
                Haptics.success()
                dismiss()
            case .refused(let line):
                message = line
            case .unconfirmed, .busy:
                break
            }
        }
    }
}

// MARK: - Views: the five libraries

struct MakeLibraryFormats: View {
    private let live = MakeLibraryLive.shared

    var body: some View {
        MakeLibraryGate(parts: [.formats]) {
            VStack(alignment: .leading, spacing: 12) {
                Text("A format card is a shape of video that works, with its sources. A port carries it into one of your niches.")
                    .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                if live.formats.isEmpty {
                    EmptyLine(text: "No format cards yet. The Researcher writes one when it finds a format that works, with its sources.")
                }
                ForEach(live.formats) { format in
                    MakeLibraryFormatCard(format: format, ports: live.ports.filter { $0.formatID == format.id })
                }
                if live.loads[.packs] == .loaded {
                    MakeTile(title: "Style packs", symbol: "paintbrush") {
                        if live.packs.isEmpty { EmptyLine(text: "No style packs of your own yet.") }
                        ForEach(live.packs) { pack in
                            let built = pack.approvedVersion != nil
                            HStack {
                                Text(pack.name).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                                Spacer()
                                StatePill(text: built ? "Built" : "Not built yet", tone: built ? .ok : .muted)
                            }
                            .frame(minHeight: 36)
                        }
                    }
                }
            }
        }
        .task(id: MakeLibraryLive.connectionKey) {
            live.follow()
            await live.loadIfNeeded([.packs])
        }
    }
}

struct MakeLibraryFormatCard: View {
    let format: MakeLibraryFormatDTO
    let ports: [MakeLibraryPortDTO]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(format.name).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
            if !format.premise.isEmpty {
                Text(format.premise).font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                StatePill(text: MakeLibraryWords.lengthText(format.lengthMin, format.lengthMax), tone: .muted)
                if !format.sourceNiche.isEmpty { StatePill(text: "Seen in \(format.sourceNiche)", tone: .muted) }
            }
            .scrollableRow()
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(format.beats.enumerated()), id: \.offset) { index, beat in
                    Text("\(index + 1). \(beat)").font(KFont.ui(14.5)).foregroundStyle(Palette.ink)
                }
            }
            if !format.audience.isEmpty {
                Text(format.audience).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(format.evidence.enumerated()), id: \.offset) { _, item in
                Label(evidenceLine(item), systemImage: "link").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            Text("Not ours to use: the sources stay theirs. Only the shape is ported.").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            DisclosureGroup(isExpanded: $open) {
                VStack(alignment: .leading, spacing: 10) {
                    if ports.isEmpty { EmptyLine(text: "Not ported into any of your niches yet.") }
                    ForEach(ports) { port in portRow(port) }
                }
                .padding(.top, 8)
            } label: {
                Text("Ports (\(ports.count))").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
            }
            .tint(Palette.goldText)
        }
        .padding(14)
        .kCard(radius: 22)
    }

    private func evidenceLine(_ item: MakeLibraryEvidenceDTO) -> String {
        var bits = [item.channel]
        if !item.title.isEmpty { bits.append(item.title) }
        if let views = item.views { bits.append("\(views) views") }
        if !item.checked.isEmpty { bits.append("checked " + item.checked) }
        if !item.host.isEmpty { bits.append(item.host) }
        return bits.joined(separator: ", ")
    }

    private func portRow(_ port: MakeLibraryPortDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("From \(format.sourceNiche.isEmpty ? "the source" : format.sourceNiche) into \(port.niche)").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                Spacer(minLength: 6)
                StatePill(text: MakeLibraryWords.capitalized(port.status), tone: port.status == "accepted" ? .ok : (port.status == "rejected" ? .error : .working))
            }
            if !port.audienceMatch.isEmpty {
                Text(port.audienceMatch).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            }
            if !port.checked {
                Text("Not checked yet.").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            } else if port.findings.isEmpty {
                StatePill(text: "Checks passed", tone: .ok)
            } else {
                ForEach(Array(port.findings.enumerated()), id: \.offset) { _, finding in
                    VStack(alignment: .leading, spacing: 2) {
                        StatePill(text: "\(MakeLibraryWords.checkTitle(finding.check)): \(finding.result == "reject" ? "Failed" : "Warning")",
                                  tone: finding.result == "reject" ? .error : .warn)
                        if !finding.reason.isEmpty { Text(finding.reason).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim) }
                    }
                }
            }
            if !port.cost.isEmpty { Text(port.cost).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint) }
            if !port.verdictReason.isEmpty {
                Text("Verdict: \(port.verdictReason)").font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink)
            }
        }
        .padding(12)
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MakeLibraryStyles: View {
    @Environment(MakeToast.self) private var toast
    @State private var sheet: MakeLibrarySheet?
    private let live = MakeLibraryLive.shared

    var body: some View {
        MakeLibraryGate(parts: [.packs]) {
            VStack(alignment: .leading, spacing: 12) {
                MakePillButton(title: "New from a brief", symbol: "plus", filled: true) { sheet = .brief }
                    .disabled(live.isBusy("brief"))
                    .opacity(live.isBusy("brief") ? 0.5 : 1)
                MakeLibraryPendingLine(key: "brief")
                ForEach(live.starters.filter { starter in !live.packs.contains { $0.originKind == "starter" && $0.originFrom == starter.id } || live.isBusy("starter:" + starter.id) }) { starter in
                    VStack(alignment: .leading, spacing: 6) {
                        MakePillButton(title: "Add \(starter.name) starter") { sheet = .starter(starter.id) }
                            .disabled(live.isBusy("starter:" + starter.id))
                            .opacity(live.isBusy("starter:" + starter.id) ? 0.5 : 1)
                        MakeLibraryPendingLine(key: "starter:" + starter.id)
                    }
                }
                if live.packs.isEmpty {
                    EmptyLine(text: "No style packs yet. Write a brief, or add a starter pack.")
                }
                ForEach(live.packs) { pack in
                    MakeLibraryPackCard(pack: pack) { sheet = $0 }
                }
                MakeTile(title: "Built into Kairos", symbol: "shippingbox") {
                    ForEach(live.builtIn) { item in
                        HStack {
                            Text(item.name).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                            Spacer()
                            StatePill(text: item.available ? "Available" : "Not built yet", tone: item.available ? .ok : .muted)
                        }
                        .frame(minHeight: 34)
                    }
                }
                HintLine(text: MakeLibraryWords.packFiles)
            }
        }
        .task(id: MakeLibraryLive.connectionKey) {
            live.follow()
            await live.loadIfNeeded([.characters])
            await live.watch()
        }
        .sheet(item: $sheet) { item in
            MakeLibrarySheetView(sheet: item).environment(toast)
        }
    }
}

struct MakeLibraryPackCard: View {
    let pack: MakeLibraryPackDTO
    let open: (MakeLibrarySheet) -> Void
    @Environment(MakeStore.self) private var make
    @State private var showBrief = false
    private let live = MakeLibraryLive.shared

    var body: some View {
        let editKey = "editpack:" + pack.id
        let brief = pack.spec?.brief.isEmpty == false ? pack.spec?.brief ?? "" : pack.originBrief
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                    let origin = MakeLibraryWords.originText(pack.originKind)
                    if !origin.isEmpty { Text(origin).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint) }
                }
                Spacer()
                if pack.spec != nil {
                    MakePillButton(title: "Edit", symbol: "pencil") { open(.editPack(pack.id)) }
                        .disabled(live.isBusy(editKey))
                        .opacity(live.isBusy(editKey) ? 0.5 : 1)
                }
            }
            if let summary = pack.spec?.summary, !summary.isEmpty {
                Text(summary).font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
            }
            Text(pack.approvedVersion.map { "Channels and videos use version \($0)." } ?? "Not approved yet, so no channel can use it.")
                .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                .foregroundStyle(pack.approvedVersion == nil ? Palette.goldText : Palette.success)
            MakeLibraryPendingLine(key: editKey)
            if !brief.isEmpty {
                DisclosureGroup("Show the brief", isExpanded: $showBrief) {
                    Text(brief).font(KFont.ui(14)).foregroundStyle(Palette.inkDim).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                .font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink).tint(Palette.goldText)
            }
            ForEach(pack.versions.reversed()) { version in versionRow(version) }
        }
        .padding(14)
        .kCard(radius: 22)
    }

    private func versionRow(_ version: MakeLibraryPackVersionDTO) -> some View {
        let state = MakeLibraryPackState.of(version)
        let key = "sample:\(pack.id)#\(version.number)"
        let busy = live.isBusy(key)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Version \(version.number)").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                Spacer()
                StatePill(text: state.label, tone: state.tone)
            }
            if !version.note.isEmpty { Text(version.note).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim) }
            if state == .rejected, !version.reason.isEmpty {
                Text("Rejected: \(version.reason)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.danger)
            }
            if state == .failed, let why = version.sample?.status {
                Text(String(why.dropFirst("failed:".count).trimmingCharacters(in: .whitespaces).prefix(160)))
                    .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.danger)
            }
            switch state {
            case .draft, .rejected, .failed:
                MakePillButton(title: state == .failed ? "Make the sample again" : "Make sample", filled: !busy) { open(.sample(pack.id, version.number)) }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
            case .rendering:
                renderingRow(version)
            case .waitingSheets:
                waitingRow(version, busy: busy)
            case .awaiting:
                MakePillButton(title: "Review", filled: true) { make.studio.open(.approvals) }
            case .approved:
                EmptyView()
            }
            MakeLibraryPendingLine(key: key)
        }
        .padding(12)
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func renderingRow(_ version: MakeLibraryPackVersionDTO) -> some View {
        let started = MakeLibraryWire.time(version.sample?.at)
        let long = started.map { Date().timeIntervalSince($0) > 3600 } ?? false
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PulsingDot(color: Palette.working, size: 6)
                Text(started.map { "Rendering on your desktop since \(MakeLibraryWords.stamp($0))" } ?? "Rendering on your desktop")
                    .font(KFont.ui(14, .medium)).foregroundStyle(Palette.working)
            }
            .frame(minHeight: 36)
            if long { HintLine(text: "This has been going for over an hour. Check Kairos on your desktop.") }
        }
    }

    private func waitingRow(_ version: MakeLibraryPackVersionDTO, busy: Bool) -> some View {
        let needs = live.castNeedingSheets(pack)
        let names = version.sample?.waiting ?? []
        return VStack(alignment: .leading, spacing: 6) {
            if !names.isEmpty {
                Text("Waiting for the sheet of \(names.joined(separator: ", ")).").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            }
            if live.loads[.characters] == .loaded, needs.render.isEmpty, needs.waiting.isEmpty {
                MakePillButton(title: "Make sample", filled: !busy) { open(.sample(pack.id, version.number)) }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
            } else {
                MakePillButton(title: "Review", filled: true) { make.studio.open(.approvals) }
            }
        }
    }
}

struct MakeLibraryCharacters: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @State private var sheet: MakeLibrarySheet?
    private let live = MakeLibraryLive.shared

    var body: some View {
        MakeLibraryGate(parts: [.characters]) {
            VStack(alignment: .leading, spacing: 12) {
                MakePillButton(title: "New character", symbol: "plus", filled: true) { sheet = .newCharacter }
                    .disabled(live.isBusy("newcharacter"))
                    .opacity(live.isBusy("newcharacter") ? 0.5 : 1)
                MakeLibraryPendingLine(key: "newcharacter")
                if live.characters.isEmpty {
                    EmptyLine(text: "No characters yet. Make one here, or the Editor makes one when a channel uses the Flat 2D pack.")
                }
                ForEach(live.characters) { character in card(character) }
                HintLine(text: MakeLibraryWords.approvals)
            }
        }
        .task(id: MakeLibraryLive.connectionKey) {
            live.follow()
            await live.watch()
        }
        .sheet(item: $sheet) { item in
            MakeLibrarySheetView(sheet: item).environment(toast)
        }
    }

    private func card(_ character: MakeLibraryCharacterDTO) -> some View {
        let editKey = "editchar:" + character.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                    Text("\(MakeLibraryWords.capitalized(character.family)) family · "
                         + (character.approvedVersion.map { "Videos can cast version \($0)." } ?? "No approved version yet, so no video can use it."))
                        .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                Spacer()
                MakePillButton(title: "New version") { sheet = .editCharacter(character.id) }
                    .disabled(live.isBusy(editKey))
                    .opacity(live.isBusy(editKey) ? 0.5 : 1)
            }
            MakeLibraryPendingLine(key: editKey)
            ForEach(character.versions.reversed()) { version in versionRow(character, version) }
        }
        .padding(14)
        .kCard(radius: 22)
    }

    private static func versionLabel(_ status: String) -> (String, PillTone) {
        switch status {
        case "awaiting_approval": ("Waiting for your OK", .gold)
        case "approved": ("Approved", .ok)
        case "rejected": ("Rejected", .error)
        default: ("Draft, no sheet yet", .muted)
        }
    }

    private func versionRow(_ character: MakeLibraryCharacterDTO, _ version: MakeLibraryCharVersionDTO) -> some View {
        let key = "sheet:\(character.id)#\(version.number)"
        let busy = live.isBusy(key)
        let shown = Self.versionLabel(version.status)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Version \(version.number)").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                Spacer(minLength: 4)
                StatePill(text: shown.0, tone: shown.1)
            }
            if !version.note.isEmpty { Text(version.note).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim) }
            if version.status == "rejected", !version.reason.isEmpty {
                Text("Rejected: \(version.reason)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.danger)
            }
            if version.status == "draft" || version.status == "rejected" {
                MakePillButton(title: "Make sheet", filled: !busy) { sheet = .sheet(character.id, version.number) }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
            } else if version.status == "awaiting_approval" {
                MakePillButton(title: "Review", filled: true) { make.studio.open(.approvals) }
            }
            MakeLibraryPendingLine(key: key)
        }
        .padding(10)
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Which platforms are connected and which reads are on. Read only: nothing here changes the desktop.
struct MakeLibraryConnectionsView: View {
    private let live = MakeLibraryLive.shared

    var body: some View {
        MakeLibraryGate(parts: [.connections]) {
            let found = live.connections
            VStack(alignment: .leading, spacing: 12) {
                Text("Kairos reads numbers through your own Google project and your own apps. It posts only what you approve.")
                    .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                MakeTile(title: "YouTube", symbol: "play.rectangle") {
                    if found.youtubeAnalytics?.configured == false {
                        Text("Google first: set up your Kairos Google project on your desktop.").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                    }
                    row("Analytics", state(found.youtubeAnalytics))
                    row("Posting", state(found.youtubePosting))
                    if let privacy = found.uploadPrivacy {
                        row("Uploads ask for", (MakeLibraryWords.capitalized(privacy), .muted))
                    }
                    Text("Analytics read views, watch time, likes and follows once a day. Read-only: it never posts.")
                        .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                platformTile("TikTok", app: found.tiktokApp, connected: found.tiktokConnected, reads: found.tiktokPageReads)
                platformTile("Instagram", app: found.instagramApp, connected: found.instagramConnected, reads: found.instagramPageReads)
                MakeTile(title: "Niches", symbol: "square.grid.2x2") {
                    if live.niches.isEmpty { EmptyLine(text: "No niches yet.") }
                    ForEach(live.niches) { niche in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(niche.name).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                                Text(niche.retired ? "Retired. History kept." : "\(niche.slots) posting slots a day").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                            }
                            Spacer()
                            StatePill(text: niche.retired ? "Retired" : "Live", tone: niche.retired ? .muted : .ok)
                        }
                        .frame(minHeight: 40)
                    }
                }
                HintLine(text: MakeLibraryWords.connections)
            }
        }
    }

    private func state(_ part: MakeLibraryConnections.Part?) -> (String, PillTone) {
        guard let part else { return ("Could not read", .muted) }
        if part.needsSignIn { return ("Needs sign-in", .error) }
        switch part.connected {
        case .some(true): return ("Connected", .ok)
        case .some(false): return ("Not connected", .warn)
        case .none: return ("Could not read", .muted)
        }
    }

    private func flag(_ value: Bool?, on: String, off: String) -> (String, PillTone) {
        switch value {
        case .some(true): (on, .ok)
        case .some(false): (off, .muted)
        case .none: ("Could not read", .muted)
        }
    }

    private func row(_ title: String, _ state: (String, PillTone)) -> some View {
        HStack {
            Text(title).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
            Spacer()
            StatePill(text: state.0, tone: state.1)
        }
        .frame(minHeight: 44)
    }

    private func platformTile(_ name: String, app: Bool?, connected: Bool?, reads: Bool?) -> some View {
        MakeTile(title: name, symbol: "app.badge") {
            row("Your app", flag(app, on: "Saved", off: "Not set up"))
            row("Channels", flag(connected, on: "Connected", off: "Not connected"))
            row("Page reads", flag(reads, on: "On", off: "Off"))
        }
    }
}

struct MakeLibraryTemplatesView: View {
    private let live = MakeLibraryLive.shared

    var body: some View {
        MakeLibraryGate(parts: [.templates]) {
            VStack(alignment: .leading, spacing: 12) {
                if live.templates.isEmpty { EmptyLine(text: "Your desktop has no ready-made teams to show.") }
                ForEach(live.templates) { template in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(template.name).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                        if !template.detail.isEmpty {
                            Text(template.detail).font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 6) {
                            ForEach(Array(template.bots.enumerated()), id: \.offset) { _, bot in StatePill(text: bot, tone: .muted) }
                        }
                        .scrollableRow()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kCard(radius: 22)
                }
                HintLine(text: MakeLibraryWords.templates)
            }
        }
    }
}
