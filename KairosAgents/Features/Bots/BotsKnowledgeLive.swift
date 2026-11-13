import SwiftUI

// The paired desktop behind a bot's knowledge and reach settings: memory, About you, usage and plan, and its
// conversations and folders (read and write); skills, the skill library, access, reach, connections, browser and
// saved logins (read only). Unpaired, nothing here runs and the pages show BotsStore's samples exactly as before.
// Everything read here belongs to one desktop and one account; a result that lands for another is dropped.

/// How a write the page waits on came back.
nonisolated enum BotKnowOutcome: Equatable, Sendable {
    case done(String)
    case refused(String)
    /// The answer was lost; the page re-read the desktop. What the person typed stays.
    case unsure(String)
}

/// Where About you stands. "Saved" only ever follows an answer, or a read, that has the text that was sent.
nonisolated enum BotKnowAboutState: Equatable, Sendable {
    /// The text on screen is the desktop's.
    case idle
    case unsaved
    case saving
    case saved
    /// The desktop has other text than the one this iPhone read: the person's text is kept and not sent until
    /// they choose.
    case changedOnDesktop
    /// The answer was lost and the desktop does not have the text: nothing was saved. Saving again is safe
    /// (the desktop refuses a save made against an older text).
    case notSaved(String)
    /// The answer was lost and the desktop could not be read either.
    case unsure(String)
    case refused(String)
}

/// A note removal that can still be undone.
nonisolated struct BotKnowUndo: Equatable, Sendable {
    var change: String
    var text: String
    /// It took the place of an earlier removal's Undo: only this last removal can be undone.
    var replaced = false
}

/// A note whose add answer was lost: what was SENT, and the page hash it was sent against.
nonisolated struct BotKnowSentNote: Equatable, Sendable {
    var section: String
    var text: String
    var hash: String
}

/// The usage page's period.
nonisolated enum BotKnowPeriod: String, CaseIterable, Hashable, Sendable {
    case today = "Today", week = "This week", month = "This month"

    func start(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        switch self {
        case .today: return calendar.startOfDay(for: now)
        case .week: return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: return calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        }
    }
}

/// Short plain words for numbers and times.
nonisolated enum BotKnowFormat {
    static func ago(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        if abs(now.timeIntervalSince(date)) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// A notebook date "2027-01-04" as "4 Jan".
    static func day(_ text: String?) -> String {
        guard let text, let date = FlexibleDate.parse(text) else { return text ?? "" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func cost(_ value: Double?) -> String {
        guard let value else { return "Unknown" }
        return String(format: "$%.2f", value)
    }

    static func tokens(_ value: Int?) -> String {
        let count = value ?? 0
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return "\(count / 1_000)K" }
        return "\(count)"
    }

    static func duration(_ seconds: Double?) -> String {
        let total = Int((seconds ?? 0).rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    static func resets(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset time not reported" }
        if date <= now { return "Resets now" }
        return "Resets " + ago(date, now: now)
    }
}

@Observable
final class BotsKnowledgeLive {
    static let shared = BotsKnowledgeLive()

    /// Every read's state, by key ("memory|<bot>", "about", "usage|<bot>|<period>", "plan", "agent|<bot>",
    /// "threads|<bot>", "skills|<bot>", "library", "access|<bot>", "reach|<bot>", "connections", "profiles", "logins").
    var loads: [String: BotsLiveLoad] = [:]
    /// Items of the last read of each key this app could not read, left out of the lists.
    var skipped: [String: Int] = [:]
    /// Writes on their way, by what they change: those controls wait.
    var busy: Set<String> = []

    var memory: [String: BotKnowMemoryDTO] = [:]
    var undos: [String: BotKnowUndo] = [:]
    /// Adds whose answer was lost and that no read has settled yet: Add waits until one does.
    var addChecks: [String: BotKnowSentNote] = [:]

    var aboutBase: BotKnowAboutDTO?
    var aboutDraft = ""
    var aboutState: BotKnowAboutState = .idle
    var learned: [BotKnowLearnedDTO] = []

    var usage: [String: BotKnowUsageSummaryDTO] = [:]
    var usageRuns: [String: [BotKnowUsageRunDTO]] = [:]
    var plan: [BotKnowPlanProviderDTO] = []

    var agents: [String: BotKnowAgentFieldsDTO] = [:]
    var threads: [String: [BotThreadDTO]] = [:]
    var mainIDs: [String: String] = [:]

    var skills: [String: BotKnowSkillsDTO] = [:]
    var library: [BotKnowSkillDTO] = []
    var access: [String: BotKnowAccessDTO] = [:]
    var reach: [String: BotKnowReachDTO] = [:]
    var apps: [BotKnowAppDTO] = []
    var profiles: [BotKnowProfileDTO] = []
    var logins: [BotKnowLoginDTO] = []

    @ObservationIgnored private var account = "sample"
    @ObservationIgnored private var seqs: [String: Int] = [:]
    @ObservationIgnored private var writing = 0
    @ObservationIgnored private var writeGeneration = 0
    @ObservationIgnored private var aboutTask: Task<Void, Never>?
    @ObservationIgnored private var aboutSaving = false
    /// The last About you text sent and the hash it was sent against, until an answer or a read settles it.
    @ObservationIgnored private var aboutSent: (text: String, expected: String)?
    /// Goes up with every save the desktop confirmed: a read that started before one does not replace the text.
    @ObservationIgnored private var aboutSaves = 0
    /// Goes up when everything is dropped for another account.
    @ObservationIgnored private var resets = 0

    // MARK: Which desktop

    /// Paired: the pages read from here, never from the samples.
    var active: Bool { !Connection.shared.usesSampleData }

    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Changes when the phone is paired or unpaired, the desktop starts answering, or another account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// Whether the paired account is an admin on the desktop (from the pairing answer).
    var isAdmin: Bool { Connection.shared.desktop?.isAdmin ?? false }

    /// Match the connection: another desktop or account, or unpairing, drops everything read before.
    func followConnection() {
        let want = active ? Self.accountKey : "sample"
        guard want != account else { return }
        reset()
        account = want
    }

    private func reset() {
        loads = [:]
        skipped = [:]
        busy = []
        memory = [:]
        undos = [:]
        addChecks = [:]
        aboutTask?.cancel()
        aboutTask = nil
        aboutSaving = false
        aboutChecking = false
        aboutSent = nil
        aboutSaves += 1
        resets += 1
        aboutBase = nil
        aboutDraft = ""
        aboutState = .idle
        learned = []
        usage = [:]
        usageRuns = [:]
        plan = []
        agents = [:]
        threads = [:]
        mainIDs = [:]
        skills = [:]
        library = []
        access = [:]
        reach = [:]
        apps = []
        profiles = []
        logins = []
        // Every read in flight for the last account is dropped when it lands.
        seqs = seqs.mapValues { $0 + 1 }
        writing = 0
        writeGeneration += 1
    }

    private func stillLive(_ account: String) -> Bool {
        active && self.account == account && Self.accountKey == account
    }

    /// What was read belongs to the desktop and account paired right now.
    var isCurrent: Bool { active && account == Self.accountKey }

    /// A load state for a page: reading until this account's first read has landed.
    func shown(_ key: String) -> BotsLiveLoad {
        guard isCurrent else { return .loading }
        let state = loads[key] ?? .idle
        return state == .idle ? .loading : state
    }

    /// The first read of this key has landed for this account.
    func ready(_ key: String) -> Bool { isCurrent && loads[key] == .loaded }

    /// The last read of this key failed.
    func failed(_ key: String) -> Bool {
        guard isCurrent, case .failed? = loads[key] else { return false }
        return true
    }

    private func client() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    private func beginWrite() {
        writing += 1
        writeGeneration += 1
    }

    private func endWrite() {
        writing = max(0, writing - 1)
        writeGeneration += 1
    }

    /// A write whose answer never came: the desktop may have done it. A request that never left this
    /// iPhone (no network, no such address, no secure connection) is not in doubt.
    private func unconfirmed(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        guard let api = error as? APIError else { return false }
        if case .unreadable = api { return true }
        if case .server(let status, _) = api, status >= 500 { return true }
        guard api.isOffline else { return false }
        let neverSent: [URLError.Code] = [.notConnectedToInternet, .cannotFindHost, .secureConnectionFailed,
                                          .appTransportSecurityRequiresSecureConnection]
        return !neverSent.contains { APIError.from(URLError($0)) == api }
    }

    private func status(_ error: Error) -> Int? {
        if case .server(let status, _)? = error as? APIError { return status }
        return nil
    }

    private func unsure(_ what: String) -> String {
        "Your desktop did not answer, so this iPhone could not confirm \(what). This page shows what your desktop has."
    }

    private func say(_ text: String) { BotsStore.shared.say(text) }

    // MARK: Reading

    /// One read. A read that began before a write finished does not replace what that write showed (the write
    /// reads again itself), and an older read never replaces a newer one. `force` is for the read after a lost
    /// answer, which must land: if another write began or ended while it read, it reads again (twice at most)
    /// so it does not put back what that write showed.
    @discardableResult
    private func fetch<T>(_ key: String, failed: String, force: Bool = false, attempt: Int = 0,
                          _ call: (APIClient) async throws -> T, apply: (T) -> Void) async -> Bool {
        guard active else { return false }
        let account = self.account
        let seq = (seqs[key] ?? 0) + 1
        seqs[key] = seq
        let prior = loads[key] ?? .idle
        if prior != .loaded { loads[key] = .loading }
        let generation = writeGeneration
        do {
            let value = try await call(try client())
            guard stillLive(account), seqs[key] == seq else { return false }
            if !force && prior == .loaded && (writing > 0 || writeGeneration != generation) { return false }
            if force && attempt < 2 && (writing > 0 || writeGeneration != generation) {
                return await fetch(key, failed: failed, force: true, attempt: attempt + 1, call, apply: apply)
            }
            apply(value)
            loads[key] = .loaded
            return true
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), seqs[key] == seq else { return false }
            if error is CancellationError {
                // Not read is not failed: the next look reads again.
                if loads[key] == .loading { loads[key] = .idle }
            } else if status(error) == 403 {
                loads[key] = .failed(isAdmin ? failed + " " + error.plainWords
                                             : "This needs an admin account on your desktop, and this iPhone is paired with one that is not.")
            } else if prior == .loaded && !force {
                // Shown already: keep it, and say the refresh failed.
                say(failed + " " + error.plainWords)
            } else {
                loads[key] = .failed(failed + " " + error.plainWords)
            }
            return false
        }
    }

    // MARK: Memory

    @discardableResult
    func loadMemory(_ botID: String, force: Bool = false) async -> Bool {
        await fetch("memory|\(botID)", failed: "Its memory could not be read.", force: force,
                    { try await $0.botKnowledgeMemory(botID) }) { value in
            memory[botID] = value
            skipped["memory|\(botID)"] = BotKnowWire.items(value.index?.notes).skipped
        }
    }

    /// The notes it remembers, newest first, without the ones replaced by a newer note.
    func notes(_ botID: String) -> [BotKnowNoteDTO] {
        guard isCurrent else { return [] }
        let all = BotKnowWire.items(memory[botID]?.index?.notes).items.filter { $0.superseded == nil }
        return all.sorted { ($0.learned ?? "") > ($1.learned ?? "") }
    }

    func topics(_ botID: String) -> [BotKnowMemoryFileDTO] {
        guard isCurrent else { return [] }
        return BotKnowWire.items(memory[botID]?.files).items.filter { $0.kind == "topic" }
    }

    func memorySetting(_ botID: String, _ field: String) -> Bool {
        let settings = memory[botID]?.settings
        switch field {
        case "enabled": return settings?.enabled ?? memory[botID]?.enabled ?? true
        case "upkeep": return settings?.upkeep ?? false
        default: return settings?.roomCapture ?? false
        }
    }

    private func setLocal(_ botID: String, _ field: String, _ value: Bool) {
        guard memory[botID] != nil else { return }
        if memory[botID]?.settings == nil { memory[botID]?.settings = BotKnowMemorySettingsDTO() }
        switch field {
        case "enabled": memory[botID]?.settings?.enabled = value
        case "upkeep": memory[botID]?.settings?.upkeep = value
        default: memory[botID]?.settings?.roomCapture = value
        }
    }

    /// Turn one memory switch: `enabled`, `upkeep` or `room_capture`. Shown at once, put back on a refusal.
    func setMemory(_ botID: String, _ field: String, _ value: Bool) {
        guard active, memory[botID] != nil else { return }
        let key = "memset|\(botID)|\(field)"
        guard !busy.contains(key) else { return }
        let account = self.account
        let before = memorySetting(botID, field)
        setLocal(botID, field, value)
        busy.insert(key)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                let saved = try await client().botKnowledgeMemorySettings(botID, [field: value])
                endWrite()
                guard stillLive(account) else { return }
                memory[botID]?.settings = saved
                if let enabled = saved.enabled { memory[botID]?.enabled = enabled }
                if let upkeep = saved.upkeep { memory[botID]?.maintenance?.upkeep = upkeep }
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say(unsure("the change was saved"))
                    let read = await loadMemory(botID, force: true)
                    // Not read either: the switch shows the desktop's last known state, never the unconfirmed tap.
                    if !read, stillLive(account), memorySetting(botID, field) == value { setLocal(botID, field, before) }
                    return
                }
                if memorySetting(botID, field) == value { setLocal(botID, field, before) }
                say("That was not changed. " + error.plainWords)
            }
        }
    }

    private func applyPage(_ botID: String, _ page: BotKnowMemoryPageDTO?) {
        guard let page, memory[botID] != nil else { return }
        if memory[botID]?.index == nil { memory[botID]?.index = BotKnowIndexDTO() }
        memory[botID]?.index?.hash = page.hash
        memory[botID]?.index?.notes = page.notes
    }

    /// A change to its main page is on its way (add, remove, undo or tidy): the others wait, so each one is
    /// sent against the page the last one left, and a refusal is never caused by this iPhone's own change.
    func pageBusy(_ botID: String) -> Bool {
        ["note", "rm", "undo", "tidy"].contains { busy.contains("\($0)|\(botID)") }
    }

    /// A note's text as the desktop stores it (bot_memory_entries.clean_text): one kind of line break, no
    /// control characters but newlines and tabs, no spaces at either end or at the end of a line.
    static func cleanNote(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var scalars = String.UnicodeScalarView()
        for scalar in unified.unicodeScalars {
            let value = scalar.value
            if value == 0x0A || value == 0x09 || (value > 0x1F && value != 0x7F) { scalars.append(scalar) }
        }
        let body = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return body.components(separatedBy: "\n")
            .map { line in
                var line = line
                while let last = line.unicodeScalars.last, CharacterSet.whitespaces.contains(last) { line.unicodeScalars.removeLast() }
                return line
            }
            .joined(separator: "\n")
    }

    /// The length the desktop counts (Python `len`: code points, not what the eye sees as characters).
    static func length(_ text: String) -> Int { text.unicodeScalars.count }

    /// A note's words for matching what was sent with what the desktop shows: a trailing " · until <date>"
    /// is read by the desktop as an end date, and line breaks and spacing may differ.
    private static func matchKey(_ text: String) -> String {
        var body = cleanNote(text)
        if let range = body.range(of: #" · until \d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            body.removeSubrange(range)
        }
        return body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func has(_ botID: String, _ sent: BotKnowSentNote) -> Bool {
        let want = Self.matchKey(sent.text)
        let section = sent.section.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return BotKnowWire.items(memory[botID]?.index?.notes).items.contains {
            $0.superseded == nil && ($0.section ?? "") == section && Self.matchKey($0.text ?? "") == want
        }
    }

    /// After a lost add, with a fresh read in hand: say what the desktop really has. The note is never called
    /// missing while the desktop has its text.
    private func settleAdd(_ botID: String, _ sent: BotKnowSentNote) -> BotKnowOutcome {
        addChecks[botID] = nil
        if has(botID, sent) {
            return .done("Your desktop did not answer at first, but it has this note.")
        }
        if memory[botID]?.index?.hash == sent.hash {
            return .refused("Your desktop did not answer, and its notes are as they were: the note was not added. Your text is kept here.")
        }
        // The desktop lists only its first 500 notes, and an added note goes at the end of its heading.
        let listed = BotKnowWire.items(memory[botID]?.index?.notes)
        if listed.items.count + listed.skipped >= 500 {
            return .unsure("Your desktop did not answer, and it lists only its first 500 notes, so this iPhone cannot tell whether this one was added. Look on your desktop before adding it again. Your text is kept here.")
        }
        return .refused("Your desktop did not answer, and it does not have this note. Your text is kept here.")
    }

    /// Add a note under a heading of the main page, against the page as it was read.
    func addNote(_ botID: String, section: String, text: String) async -> BotKnowOutcome {
        guard active, isCurrent, let hash = memory[botID]?.index?.hash else {
            return .refused("Its notes have not been read from your desktop yet.")
        }
        guard addChecks[botID] == nil else { return .refused("Check whether the last note arrived before adding another.") }
        let key = "note|\(botID)"
        guard !pageBusy(botID) else { return .refused("A change to its notes is still on its way.") }
        let account = self.account
        let clean = Self.cleanNote(text)
        let sent = BotKnowSentNote(section: section, text: clean, hash: hash)
        busy.insert(key)
        beginWrite()
        defer { if stillLive(account) { busy.remove(key) } }
        do {
            let answer = try await client().botKnowledgeMemoryEntry(botID, action: "append", expectedHash: hash,
                                                                    section: section, text: clean)
            endWrite()
            guard stillLive(account) else { return .refused("Your desktop changed while the note was being added.") }
            applyPage(botID, answer.file)
            undos[botID] = nil
            Task { await self.loadMemory(botID) }
            if let moved = answer.displaced, moved > 0 {
                return .done("Added. To make room, \(moved) older \(moved == 1 ? "note" : "notes") moved to its archive.")
            }
            return .done("Added to \(section).")
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else { return .refused("Your desktop changed while the note was being added.") }
            if unconfirmed(error) {
                // Until a read settles it, Add waits: a second tap could put the note in twice.
                addChecks[botID] = sent
                let read = await loadMemory(botID, force: true)
                guard stillLive(account) else { return .refused("Your desktop changed while the note was being added.") }
                if read { return settleAdd(botID, sent) }
                return .unsure(unsure("the note was added") + " Your text is kept here. Check again before adding it again.")
            }
            if status(error) == 409 {
                await loadMemory(botID, force: true)
                return .refused("Its notes changed on your desktop, so the note was not added. This shows what your desktop has now; your text is kept here.")
            }
            return .refused("The note was not added. " + error.plainWords)
        }
    }

    /// Read again after a lost add whose read failed too.
    func checkAdd(_ botID: String) async -> BotKnowOutcome? {
        guard active, let sent = addChecks[botID] else { return nil }
        let account = self.account
        let read = await loadMemory(botID, force: true)
        guard stillLive(account), addChecks[botID] == sent else { return nil }
        if read { return settleAdd(botID, sent) }
        return .unsure(unsure("the note was added") + " Your text is kept here. Check again before adding it again.")
    }

    /// Remove one note (asked first on screen), against the page hash read together with that note. If the
    /// page changed since, nothing is sent and the person picks again. Undo stays offered until the next change,
    /// and only for the last removal.
    func removeNote(_ botID: String, _ note: BotKnowNoteDTO, hash: String) {
        guard active, isCurrent, memory[botID] != nil else { return }
        guard !pageBusy(botID) else { say("A change to its notes is still on its way. Nothing was removed."); return }
        guard memory[botID]?.index?.hash == hash else {
            say("Its notes changed since you picked this one, so nothing was removed. This shows what your desktop has now; pick it again to remove it.")
            Task { await loadMemory(botID, force: true) }
            return
        }
        let key = "rm|\(botID)"
        let account = self.account
        busy.insert(key)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                let answer = try await client().botKnowledgeMemoryEntry(botID, action: "remove", expectedHash: hash, target: note.id)
                endWrite()
                guard stillLive(account) else { return }
                withAnimation(Motion.snappy) { applyPage(botID, answer.file) }
                let replaced = undos[botID] != nil
                if let change = answer.changeId {
                    undos[botID] = BotKnowUndo(change: change, text: note.text ?? "", replaced: replaced)
                    say(replaced ? "Note removed. Undo now brings back only this note, not the one removed before it."
                                 : "Note removed.")
                } else {
                    undos[botID] = nil
                    say(replaced ? "Note removed. It cannot be undone here, and neither can the one removed before it."
                                 : "Note removed. It cannot be undone here.")
                }
                await loadMemory(botID)
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    let read = await loadMemory(botID, force: true)
                    guard stillLive(account) else { return }
                    // The page changed: an earlier removal's Undo would be refused now.
                    if read && memory[botID]?.index?.hash != hash { undos[botID] = nil }
                    let gone = read && !BotKnowWire.items(memory[botID]?.index?.notes).items.contains { $0.id == note.id }
                    say(gone ? "Your desktop did not answer at first, but the note is gone from it now. It cannot be undone here."
                             : unsure("the note was removed"))
                    return
                }
                if status(error) == 409 {
                    undos[botID] = nil
                    say("Its notes changed on your desktop, so nothing was removed. This shows what your desktop has now.")
                } else {
                    say("The note was not removed. " + error.plainWords)
                }
                await loadMemory(botID, force: true)
            }
        }
    }

    /// Undo the last removal: the desktop puts the page back only while it is as the removal left it.
    func undoRemove(_ botID: String) {
        guard active, let undo = undos[botID] else { return }
        let key = "undo|\(botID)"
        guard !pageBusy(botID) else { return }
        let account = self.account
        busy.insert(key)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                _ = try await client().botKnowledgeMemoryRevert(botID, change: undo.change)
                endWrite()
                guard stillLive(account) else { return }
                undos[botID] = nil
                say("The note is back.")
                await loadMemory(botID, force: true)
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    // Undoing twice is refused by the desktop, so the offer can stay while it is not known.
                    let read = await loadMemory(botID, force: true)
                    guard stillLive(account) else { return }
                    let back = read && BotKnowWire.items(memory[botID]?.index?.notes).items.contains { $0.text == undo.text && $0.superseded == nil }
                    if back { undos[botID] = nil }
                    say(back ? "Your desktop did not answer at first, but the note is back now." : unsure("the note came back"))
                    return
                }
                undos[botID] = nil
                say("The note did not come back. " + error.plainWords)
                await loadMemory(botID, force: true)
            }
        }
    }

    /// Tidy its notes now (the desktop refuses unless keeping them tidy is on).
    func tidy(_ botID: String) {
        guard active else { return }
        let key = "tidy|\(botID)"
        guard !pageBusy(botID) else { return }
        let account = self.account
        busy.insert(key)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                let answer = try await client().botKnowledgeMemoryTidy(botID)
                endWrite()
                guard stillLive(account) else { return }
                undos[botID] = nil
                let pages = answer.passes?.count ?? 0
                say(pages == 0 ? "Nothing needed tidying." : "Tidied \(pages) \(pages == 1 ? "page" : "pages").")
                await loadMemory(botID, force: true)
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                say(unconfirmed(error) ? unsure("its notes were tidied") : "Its notes were not tidied. " + error.plainWords)
                await loadMemory(botID, force: true)
            }
        }
    }

    // MARK: About you

    /// A read that started before a save the desktop confirmed, or that lands while a save or a check is on its
    /// way, updates only the learned facts: it never puts older text back in the box. While a save is not
    /// confirmed, the read is settled against the text that was SENT first.
    @discardableResult
    func loadAbout(force: Bool = false) async -> Bool {
        let saves = aboutSaves
        return await fetch("about", failed: "About you could not be read.", force: force,
                           { try await $0.botKnowledgeAbout() }) { value in
            if aboutSaves != saves || aboutSaving {
                showLearned(value)
            } else if let sent = aboutSent {
                settleAbout(value, sent: sent.text, expected: sent.expected)
            } else {
                showAbout(value)
            }
        }
    }

    /// Only the learned facts: the text and its hash stay as they are.
    @discardableResult
    private func loadLearned() async -> Bool {
        await fetch("learned", failed: "What your bots learned could not be read.", force: true,
                    { try await $0.botKnowledgeAbout() }) { value in
            showLearned(value)
        }
    }

    private func showLearned(_ value: BotKnowAboutDTO) {
        let items = BotKnowWire.items(value.learned)
        learned = items.items
        skipped["about"] = items.skipped
    }

    /// Take the desktop's text as the base. What the person typed is never replaced: if they have unsent text
    /// and the desktop's changed under it, the page says so and waits for them.
    private func showAbout(_ value: BotKnowAboutDTO) {
        let fresh = value.text ?? ""
        let old = aboutBase
        let edited = old != nil && aboutDraft != (old?.text ?? "")
        aboutBase = value
        showLearned(value)
        if old == nil || !edited {
            aboutDraft = fresh
            if aboutState != .saved { aboutState = .idle }
        } else if aboutDraft == fresh {
            aboutState = .idle
        } else if old?.hash != value.hash {
            aboutTask?.cancel()
            aboutState = .changedOnDesktop
        }
    }

    /// The person typed: save a moment after they stop, unless the page is waiting on their choice.
    func editAbout(_ text: String) {
        // The desktop reads About you back with one kind of line break: a pasted CR or CRLF would never match.
        let text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        aboutDraft = text
        switch aboutState {
        case .changedOnDesktop, .unsure, .notSaved: return
        default: break
        }
        guard let base = aboutBase else { return }
        aboutState = text == (base.text ?? "") ? .idle : .unsaved
        scheduleAbout()
    }

    private func scheduleAbout() {
        aboutTask?.cancel()
        aboutTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await self.saveAbout()
        }
    }

    /// Send the text on screen against the desktop's hash read. Never two at once.
    func saveAbout() async {
        guard active, isCurrent, let base = aboutBase, !aboutSaving else { return }
        let text = aboutDraft
        guard text != (base.text ?? "") else {
            if aboutState == .unsaved { aboutState = .idle }
            return
        }
        let limit = base.limit ?? 24_000
        guard Self.length(text) <= limit else {
            aboutState = .refused("About you is limited to \(limit.formatted()) characters. Shorten it to save.")
            return
        }
        let account = self.account
        let epoch = resets
        let expected = base.hash ?? ""
        aboutSaving = true
        aboutSent = (text, expected)
        aboutState = .saving
        beginWrite()
        do {
            let saved = try await client().botKnowledgeAboutSave(text: text, expectedHash: expected)
            endWrite()
            if resets == epoch { aboutSaving = false }
            guard stillLive(account) else { lostAbout(epoch); return }
            aboutSaves += 1
            aboutSent = nil
            aboutBase?.text = saved.text
            aboutBase?.hash = saved.hash
            aboutBase?.chars = saved.chars
            if (saved.text ?? "") == text {
                if aboutDraft == text {
                    aboutState = .saved
                } else {
                    aboutState = .unsaved
                    scheduleAbout()
                }
            } else {
                aboutState = .unsure("Your desktop answered with other text than the one sent. Your text is kept here and was not saved.")
            }
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else {
                if resets == epoch { aboutSaving = false }
                lostAbout(epoch)
                return
            }
            if status(error) == 409 || unconfirmed(error) {
                // No other save starts until the desktop has been read and compared with what was sent.
                await recheckAbout(sent: text, expected: expected)
                if resets == epoch { aboutSaving = false }
                return
            }
            aboutSaving = false
            aboutSent = nil
            aboutState = .refused("About you was not saved. " + error.plainWords)
        }
    }

    /// After a lost answer or a refusal: read the desktop and compare it with what was SENT. The caller holds
    /// `aboutSaving`, so no save runs meanwhile.
    private func recheckAbout(sent: String, expected: String) async {
        guard active else { return }
        let account = self.account
        let saves = aboutSaves
        let epoch = resets
        do {
            let fresh = try await client().botKnowledgeAbout()
            guard stillLive(account) else { lostAbout(epoch); return }
            guard aboutSaves == saves else { return }
            settleAbout(fresh, sent: sent, expected: expected)
            loads["about"] = .loaded
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { lostAbout(epoch); return }
            aboutState = .unsure("Your desktop did not answer, so this iPhone could not confirm About you was saved. Your text is kept here.")
        }
    }

    /// A fresh read while a save is not confirmed: compare it with what was SENT. The desktop has the sent text:
    /// the save landed, and anything typed since stays as an unsaved edit on top. It still has the text the save
    /// was sent against: nothing was saved. Only other text is a change on the desktop, and the person's text
    /// stays until they choose.
    private func settleAbout(_ fresh: BotKnowAboutDTO, sent: String, expected: String) {
        let text = fresh.text ?? ""
        aboutBase = fresh
        showLearned(fresh)
        // Settled either way: the sent text is no longer in doubt.
        aboutSent = nil
        if text == sent {
            aboutSaves += 1
            if aboutDraft == sent {
                aboutState = .saved
            } else {
                aboutState = .unsaved
                scheduleAbout()
            }
            return
        }
        // Nothing is sent on its own while the person has to choose.
        aboutTask?.cancel()
        if aboutDraft == text {
            aboutState = .idle
        } else if fresh.hash == expected {
            aboutState = .notSaved("Your desktop did not answer, and it does not have this text. Nothing was saved; your text is kept here.")
        } else {
            aboutState = .changedOnDesktop
        }
    }

    /// No longer live, but nothing was dropped for another account (unpaired and paired again before a page
    /// looked): the outcome is not known, and the next read settles it against what was sent.
    private func lostAbout(_ epoch: Int) {
        guard resets == epoch, aboutSent != nil else { return }
        aboutState = .unsure("Your desktop did not answer, so this iPhone could not confirm About you was saved. Your text is kept here.")
    }

    /// The person chose to keep their text over the desktop's (or to try again after nothing was saved).
    func keepMyAbout() {
        guard let base = aboutBase, !aboutSaving else { return }
        aboutState = aboutDraft == (base.text ?? "") ? .idle : .unsaved
        Task { await saveAbout() }
    }

    /// The person chose the desktop's text.
    func useDesktopAbout() {
        guard !aboutSaving else { return }
        aboutTask?.cancel()
        aboutDraft = aboutBase?.text ?? ""
        aboutState = .idle
    }

    /// Whether a save or a check is on its way (the buttons that would send again wait).
    var aboutBusy: Bool { aboutState == .saving || aboutChecking }
    private(set) var aboutChecking = false

    /// Check again after an answer that never came: nothing is sent. The desktop is compared with the text
    /// that was SENT and the hash it was sent against, never with what is in the box now.
    func checkAboutAgain() {
        guard active, !aboutSaving else { return }
        guard let sent = aboutSent else {
            // Nothing sent is in doubt: read again. The text in the box is kept; if it is not the desktop's,
            // the person chooses.
            let account = self.account
            Task {
                let read = await loadAbout(force: true)
                guard read, stillLive(account), case .unsure = aboutState else { return }
                // The desktop's text came from this iPhone's own save, so it is not called a change on the desktop.
                aboutState = aboutDraft == (aboutBase?.text ?? "") ? .idle
                    : .notSaved("Your desktop has other text than this. Your text is kept here and has not been saved.")
            }
            return
        }
        let epoch = resets
        aboutSaving = true
        aboutChecking = true
        Task {
            await recheckAbout(sent: sent.text, expected: sent.expected)
            if resets == epoch {
                aboutSaving = false
                aboutChecking = false
            }
        }
    }

    /// Remove a learned fact (asked first on screen). Bots will not learn it again.
    func removeLearned(_ fact: BotKnowLearnedDTO) {
        guard active else { return }
        let key = "learned|\(fact.id)"
        guard !busy.contains(key) else { return }
        let account = self.account
        busy.insert(key)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                try await client().botKnowledgeLearnedRemove(fact.id)
                endWrite()
                guard stillLive(account) else { return }
                withAnimation(Motion.snappy) { learned.removeAll { $0.id == fact.id } }
                say("Removed. Bots will not learn that again.")
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    // Only the learned list: About you's text and hash are not touched by this read.
                    let read = await loadLearned()
                    guard stillLive(account) else { return }
                    say(read && !learned.contains { $0.id == fact.id } ? "Your desktop did not answer at first, but the fact is gone from it now."
                                                                    : unsure("the fact was removed"))
                    return
                }
                say(status(error) == 404 ? "That fact was already gone from your desktop." : "It was not removed. " + error.plainWords)
                await loadLearned()
            }
        }
    }

    // MARK: Usage and plan

    static func usageKey(_ botID: String, _ period: BotKnowPeriod) -> String { "usage|\(botID)|\(period.rawValue)" }

    func loadUsage(_ botID: String, _ period: BotKnowPeriod) async {
        let key = Self.usageKey(botID, period)
        let now = Date()
        let start = period.start(now: now)
        await fetch(key, failed: "Its usage could not be read.", { (client: APIClient) async throws -> (BotKnowUsageSummaryDTO, BotKnowUsageRunsDTO) in
            let summary = try await client.botKnowledgeUsageSummary(botID, from: start, to: now)
            let runs = try await client.botKnowledgeUsageRuns(botID, from: start, to: now)
            return (summary, runs)
        }) { value in
            usage[key] = value.0
            let rows = BotKnowWire.items(value.1.rows)
            usageRuns[key] = rows.items
            skipped[key] = rows.skipped + BotKnowWire.items(value.0.groups).skipped
        }
    }

    func loadPlan(refresh: Bool = false) async {
        if refresh {
            guard !busy.contains("plan") else { return }
            busy.insert("plan")
        }
        let account = self.account
        await fetch("plan", failed: "Plan usage could not be read.", force: refresh,
                    { try await $0.botKnowledgePlan(refresh: refresh) }) { value in
            plan = BotKnowWire.items(value.providers).items
        }
        if refresh && stillLive(account) { busy.remove("plan") }
    }

    @discardableResult
    func loadAgent(_ botID: String, force: Bool = false) async -> Bool {
        await fetch("agent|\(botID)", failed: "This bot could not be read.", force: force,
                    { try await $0.botKnowledgeAgent(botID) }) { value in
            if let agent = value.agent { agents[botID] = agent }
        }
    }

    // MARK: Conversations

    func folders(_ botID: String) -> [AgentFolderDTO] {
        guard isCurrent else { return [] }
        return BotKnowWire.items(agents[botID]?.folders).items.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    @discardableResult
    func loadThreads(_ botID: String, force: Bool = false) async -> Bool {
        let read = await fetch("threads|\(botID)", failed: "Its conversations could not be read.", force: force,
                               { try await $0.botKnowledgeThreads(botID) }) { value in
            let rows = BotKnowWire.items(value.threads)
            threads[botID] = rows.items
            mainIDs[botID] = value.mainId
            skipped["threads|\(botID)"] = rows.skipped
        }
        await loadAgent(botID, force: force)
        return read
    }

    func conversations(_ botID: String) -> [BotThreadDTO] {
        guard isCurrent else { return [] }
        return (threads[botID] ?? []).sorted { a, b in
            if (a.thread?.pinned ?? false) != (b.thread?.pinned ?? false) { return a.thread?.pinned ?? false }
            return (a.updatedAt ?? 0) > (b.updatedAt ?? 0)
        }
    }

    /// Change one conversation (only the fields named). The row shows the desktop's answer.
    func updateThread(_ botID: String, _ thread: BotThreadDTO, _ fields: [String: Any], done: String?) {
        guard active else { return }
        let key = "thread|\(thread.id)"
        guard !busy.contains(key) else { return }
        let account = self.account
        let name = thread.title?.isEmpty == false ? thread.title! : "This conversation"
        busy.insert(key)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                let saved = try await client().agentUpdateThread(botID, sessionId: thread.id, fields: fields)
                endWrite()
                guard stillLive(account) else { return }
                if let index = threads[botID]?.firstIndex(where: { $0.id == saved.id }) {
                    withAnimation(Motion.snappy) { threads[botID]?[index] = saved }
                }
                if let done { say(done) }
                // Making one main changes the others too.
                if fields["main"] != nil { await loadThreads(botID, force: true) }
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say(unsure("\(name) was changed"))
                } else if status(error) == 404 {
                    say("\(name) is not on your desktop any more.")
                } else {
                    say("\(name) was not changed. " + error.plainWords)
                }
                await loadThreads(botID, force: true)
            }
        }
    }

    /// Archive several, one after another. The main conversation is left alone.
    func archiveThreads(_ botID: String, ids: [String]) async {
        guard active else { return }
        let account = self.account
        let main = mainIDs[botID]
        var archived = 0
        var problem: String?
        for id in ids where id != main {
            let key = "thread|\(id)"
            guard !busy.contains(key) else { continue }
            busy.insert(key)
            beginWrite()
            do {
                let saved = try await client().agentUpdateThread(botID, sessionId: id, fields: ["archived": true])
                endWrite()
                guard stillLive(account) else { return }
                busy.remove(key)
                if let index = threads[botID]?.firstIndex(where: { $0.id == saved.id }) { threads[botID]?[index] = saved }
                archived += 1
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                busy.remove(key)
                problem = unconfirmed(error) ? "Your desktop did not answer." : "Some were not archived. " + error.plainWords
                break
            }
        }
        let read = await loadThreads(botID, force: true)
        guard stillLive(account) else { return }
        guard let problem else { say("\(archived) archived."); return }
        let wanted = ids.filter { $0 != main }
        guard read else { say(problem + " This iPhone could not read your desktop either, so it cannot say how many were archived."); return }
        let rows = threads[botID] ?? []
        let done = wanted.filter { id in rows.contains { $0.id == id && $0.thread?.archivedAt != nil } }.count
        say(problem + " Your desktop has \(done) of the \(wanted.count) archived now.")
    }

    /// After a delete whose answer was lost or refused: read again and say how many of those picked are
    /// really still on the desktop.
    private func sayLeft(_ botID: String, ids: [String], first: String, read: Bool) {
        guard read else {
            say(first + " This iPhone could not read your desktop either, so it cannot say which are left.")
            return
        }
        let rows = threads[botID] ?? []
        let left = ids.filter { id in rows.contains { $0.id == id } }.count
        let gone = ids.count - left
        if left == 0 {
            say(first + (ids.count == 1 ? " It is gone from your desktop now." : " All \(ids.count) are gone from your desktop now."))
        } else if gone == 0 {
            say(first + (ids.count == 1 ? " It is still on your desktop." : " All \(ids.count) are still on your desktop."))
        } else {
            say(first + " \(gone) of the \(ids.count) are gone; \(left) \(left == 1 ? "is" : "are") still on your desktop.")
        }
    }

    /// Delete conversations (asked first on screen). The desktop keeps busy ones and always keeps one.
    func deleteThreads(_ botID: String, ids: [String]) async {
        guard active, !ids.isEmpty else { return }
        let key = "delete|\(botID)"
        guard !busy.contains(key) else { return }
        let account = self.account
        busy.insert(key)
        beginWrite()
        defer { if stillLive(account) { busy.remove(key) } }
        do {
            let answer = try await client().botKnowledgeDeleteThreads(botID, ids: ids)
            endWrite()
            guard stillLive(account) else { return }
            let gone = Set((answer.deleted ?? []) + (answer.missing ?? []))
            withAnimation(Motion.snappy) { threads[botID]?.removeAll { gone.contains($0.id) } }
            let deleted = answer.deleted?.count ?? 0
            var words = deleted == 1 ? "Deleted." : "\(deleted) deleted."
            if let busy = answer.busy, !busy.isEmpty {
                words += busy.count == 1 ? " One is working, so it stays." : " \(busy.count) are working, so they stay."
            }
            if let kept = answer.kept, !kept.isEmpty { words += " A bot always keeps one conversation, so one stays." }
            say(words)
            await loadThreads(botID, force: true)
        } catch {
            endWrite()
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            let lost = unconfirmed(error)
            let read = await loadThreads(botID, force: true)
            guard stillLive(account) else { return }
            if lost {
                sayLeft(botID, ids: ids, first: "Your desktop did not answer.", read: read)
            } else {
                sayLeft(botID, ids: ids, first: "Your desktop refused: " + error.plainWords, read: read)
            }
        }
    }

    /// Start a new conversation. A lost answer is looked for, never sent again.
    func createThread(_ botID: String) {
        guard active else { return }
        let key = "create|\(botID)"
        guard !busy.contains(key) else { return }
        let account = self.account
        busy.insert(key)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                _ = try await client().agentCreateThread(botID)
                endWrite()
                guard stillLive(account) else { return }
                say("New conversation started.")
                await loadThreads(botID, force: true)
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                say(unconfirmed(error) ? unsure("a conversation was started") : "No conversation was started. " + error.plainWords)
                await loadThreads(botID, force: true)
            }
        }
    }

    /// A folder change: add, rename, order or delete. `work` returns what to say.
    private func folderWrite(_ botID: String, what: String, reload: Bool = false,
                             _ work: @escaping (APIClient) async throws -> String) {
        guard active else { return }
        let key = "folder|\(botID)"
        guard !busy.contains(key) else { return }
        let account = self.account
        busy.insert(key)
        beginWrite()
        Task {
            defer { if stillLive(account) { busy.remove(key) } }
            do {
                let words = try await work(try client())
                endWrite()
                guard stillLive(account) else { return }
                say(words)
                await loadAgent(botID, force: true)
                if reload { await loadThreads(botID, force: true) }
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                if unconfirmed(error) {
                    say(unsure(what))
                } else if status(error) == 404 {
                    say("That folder is not on your desktop any more.")
                } else {
                    say("The folder was not changed. " + error.plainWords)
                }
                await loadThreads(botID, force: true)
            }
        }
    }

    func addFolder(_ botID: String, name: String) {
        folderWrite(botID, what: "the folder was made") { client in
            _ = try await client.botKnowledgeAddFolder(botID, name: name)
            return "Folder made."
        }
    }

    func renameFolder(_ botID: String, _ folder: AgentFolderDTO, to name: String) {
        folderWrite(botID, what: "the folder was renamed") { client in
            _ = try await client.botKnowledgeRenameFolder(botID, folderID: folder.id, name: name)
            return "Folder renamed."
        }
    }

    func moveFolder(_ botID: String, _ folder: AgentFolderDTO, by offset: Int) {
        var ids = folders(botID).map(\.id)
        guard let index = ids.firstIndex(of: folder.id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        let order = ids
        folderWrite(botID, what: "the folders were moved") { client in
            _ = try await client.botKnowledgeOrderFolders(botID, ids: order)
            return "Folder moved."
        }
    }

    func deleteFolder(_ botID: String, _ folder: AgentFolderDTO) {
        folderWrite(botID, what: "the folder was deleted", reload: true) { client in
            _ = try await client.botKnowledgeDeleteFolder(botID, folderID: folder.id)
            return "Folder deleted. Its conversations stay, outside any folder."
        }
    }

    // MARK: Read only pages

    func loadSkills(_ botID: String) async {
        await fetch("skills|\(botID)", failed: "Its skills could not be read.", { try await $0.botKnowledgeSkills(botID) }) { value in
            skills[botID] = value
            skipped["skills|\(botID)"] = BotKnowWire.items(value.skills).skipped + BotKnowWire.items(value.library).skipped
        }
    }

    func loadLibrary() async {
        await fetch("library", failed: "The skill library could not be read.", { try await $0.botKnowledgeLibrary() }) { value in
            let rows = BotKnowWire.items(value.skills)
            library = rows.items
            skipped["library"] = rows.skipped
        }
    }

    func loadAccess(_ botID: String) async {
        await fetch("access|\(botID)", failed: "Its access could not be read.", { try await $0.botKnowledgeAccess(botID) }) { value in
            access[botID] = value
            skipped["access|\(botID)"] = BotKnowWire.items(value.apps).skipped
        }
        await fetch("reach|\(botID)", failed: "Who it can reach could not be read.", { try await $0.botKnowledgeReach(botID) }) { value in
            reach[botID] = value
        }
        await loadAgent(botID)
    }

    func loadConnections() async {
        await fetch("connections", failed: "Connections could not be read.", { try await $0.botKnowledgeConnections() }) { value in
            let rows = BotKnowWire.items(value.apps)
            apps = rows.items
            skipped["connections"] = rows.skipped
        }
    }

    func loadBrowser(_ botID: String) async {
        await loadAgent(botID)
        if isAdmin {
            await fetch("profiles", failed: "Browser profiles could not be read.", { try await $0.botKnowledgeProfiles() }) { value in
                let rows = BotKnowWire.items(value)
                profiles = rows.items
                skipped["profiles"] = rows.skipped
            }
        }
        await fetch("logins", failed: "Saved logins could not be read.", { try await $0.botKnowledgeLogins() }) { value in
            let rows = BotKnowWire.items(value.logins)
            logins = rows.items
            skipped["logins"] = rows.skipped
        }
    }
}
