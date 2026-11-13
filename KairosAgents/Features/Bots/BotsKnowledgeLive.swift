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
        aboutTask?.cancel()
        aboutTask = nil
        aboutSaving = false
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
    /// answer, which must land.
    @discardableResult
    private func fetch<T>(_ key: String, failed: String, force: Bool = false,
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

    private func count(_ botID: String, section: String, text: String) -> Int {
        BotKnowWire.items(memory[botID]?.index?.notes).items
            .filter { $0.superseded == nil && $0.section == section && $0.text == text }.count
    }

    /// Add a note under a heading of the main page, against the page as it was read.
    func addNote(_ botID: String, section: String, text: String) async -> BotKnowOutcome {
        guard active, isCurrent, let hash = memory[botID]?.index?.hash else {
            return .refused("Its notes have not been read from your desktop yet.")
        }
        let key = "note|\(botID)"
        guard !busy.contains(key) else { return .refused("A note is still on its way.") }
        let account = self.account
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\r\n", with: "\n")
        let before = count(botID, section: section, text: clean)
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
                let read = await loadMemory(botID, force: true)
                guard stillLive(account) else { return .refused("Your desktop changed while the note was being added.") }
                if read && count(botID, section: section, text: clean) > before {
                    return .done("Your desktop did not answer at first, but it has the note now.")
                }
                if read {
                    return .unsure("Your desktop did not answer, and it does not have the note now. Your text is kept here.")
                }
                return .unsure(unsure("the note was added") + " Your text is kept here.")
            }
            if status(error) == 409 {
                await loadMemory(botID, force: true)
                return .refused("Its notes changed on your desktop, so the note was not added. This shows what your desktop has now; your text is kept here.")
            }
            return .refused("The note was not added. " + error.plainWords)
        }
    }

    /// Remove one note (asked first on screen). Undo stays offered until the next change.
    func removeNote(_ botID: String, _ note: BotKnowNoteDTO) {
        guard active, isCurrent, let hash = memory[botID]?.index?.hash else { return }
        let key = "rm|\(botID)|\(note.id)"
        guard !busy.contains(key) else { return }
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
                if let change = answer.changeId {
                    undos[botID] = BotKnowUndo(change: change, text: note.text ?? "")
                } else {
                    undos[botID] = nil
                }
                say("Note removed.")
                await loadMemory(botID)
            } catch {
                endWrite()
                Connection.shared.note(error)
                guard stillLive(account) else { return }
                undos[botID] = nil
                if unconfirmed(error) {
                    let read = await loadMemory(botID, force: true)
                    guard stillLive(account) else { return }
                    let gone = read && !BotKnowWire.items(memory[botID]?.index?.notes).items.contains { $0.id == note.id }
                    say(gone ? "Your desktop did not answer at first, but the note is gone from it now."
                             : unsure("the note was removed"))
                    return
                }
                if status(error) == 409 {
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
        guard !busy.contains(key) else { return }
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
        guard !busy.contains(key) else { return }
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

    @discardableResult
    func loadAbout(force: Bool = false) async -> Bool {
        await fetch("about", failed: "About you could not be read.", force: force,
                    { try await $0.botKnowledgeAbout() }) { value in
            showAbout(value)
        }
    }

    /// Take the desktop's text as the base. What the person typed is never replaced: if they have unsent text
    /// and the desktop's changed under it, the page says so and waits for them.
    private func showAbout(_ value: BotKnowAboutDTO) {
        let fresh = value.text ?? ""
        let old = aboutBase
        let edited = old != nil && aboutDraft != (old?.text ?? "")
        aboutBase = value
        let items = BotKnowWire.items(value.learned)
        learned = items.items
        skipped["about"] = items.skipped
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
        guard text.count <= limit else {
            aboutState = .refused("About you is limited to \(limit.formatted()) characters. Shorten it to save.")
            return
        }
        let account = self.account
        let expected = base.hash ?? ""
        aboutSaving = true
        aboutState = .saving
        beginWrite()
        do {
            let saved = try await client().botKnowledgeAboutSave(text: text, expectedHash: expected)
            endWrite()
            aboutSaving = false
            guard stillLive(account) else { return }
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
            aboutSaving = false
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            if status(error) == 409 {
                await recheckAbout(sent: text, expected: expected)
                return
            }
            if unconfirmed(error) {
                await recheckAbout(sent: text, expected: expected)
                return
            }
            aboutState = .refused("About you was not saved. " + error.plainWords)
        }
    }

    /// After a lost answer or a refusal: read the desktop and compare it with what was SENT.
    func recheckAbout(sent: String, expected: String) async {
        guard active else { return }
        let account = self.account
        do {
            let fresh = try await client().botKnowledgeAbout()
            guard stillLive(account) else { return }
            let text = fresh.text ?? ""
            aboutBase = fresh
            let items = BotKnowWire.items(fresh.learned)
            learned = items.items
            skipped["about"] = items.skipped
            loads["about"] = .loaded
            if text == sent {
                if aboutDraft == sent {
                    aboutState = .saved
                } else {
                    aboutState = .unsaved
                    scheduleAbout()
                }
            } else if fresh.hash == expected {
                aboutState = .notSaved("Your desktop did not answer, and it does not have this text. Nothing was saved; your text is kept here.")
            } else if aboutDraft == text {
                aboutState = .idle
            } else {
                aboutState = .changedOnDesktop
            }
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return }
            aboutState = .unsure("Your desktop did not answer, so this iPhone could not confirm About you was saved. Your text is kept here.")
        }
    }

    /// The person chose to keep their text over the desktop's (or to try again after nothing was saved).
    func keepMyAbout() {
        guard let base = aboutBase else { return }
        aboutState = aboutDraft == (base.text ?? "") ? .idle : .unsaved
        Task { await saveAbout() }
    }

    /// The person chose the desktop's text.
    func useDesktopAbout() {
        aboutTask?.cancel()
        aboutDraft = aboutBase?.text ?? ""
        aboutState = .idle
    }

    /// Check again after an answer that never came: nothing is sent.
    func checkAboutAgain() {
        guard let base = aboutBase else { return }
        let sent = aboutDraft
        Task { await recheckAbout(sent: sent, expected: base.hash ?? "") }
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
                    let read = await loadAbout(force: true)
                    guard stillLive(account) else { return }
                    say(read && !learned.contains { $0.id == fact.id } ? "Your desktop did not answer at first, but the fact is gone from it now."
                                                                    : unsure("the fact was removed"))
                    return
                }
                say(status(error) == 404 ? "That fact was already gone from your desktop." : "It was not removed. " + error.plainWords)
                await loadAbout(force: true)
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
                problem = unconfirmed(error) ? unsure("every one was archived") : "Some were not archived. " + error.plainWords
                break
            }
        }
        say(problem ?? "\(archived) archived.")
        await loadThreads(botID, force: true)
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
            say(unconfirmed(error) ? unsure("they were deleted") : "Nothing was deleted. " + error.plainWords)
            await loadThreads(botID, force: true)
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
