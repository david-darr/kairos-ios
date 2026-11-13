import SwiftUI

/// How a write the screen waits on came back.
nonisolated enum BotsWriteOutcome: Equatable, Sendable {
    case done
    /// The desktop said no. Nothing changed there.
    case refused(String)
    /// The answer was lost, so the desktop may have done it. The screen re-reads instead of sending again.
    case unsure
}

/// One row of a bot's Working or Done list, from a card or a routine on the desktop.
nonisolated struct BotWorkRow: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable { case running, waiting, failed, done }
    var id: String
    var title: String
    var detail: String
    var state: State
    /// A running card or routine can be stopped (POST /api/tasks/{id}/stop).
    var canStop: Bool
    var updated: String
    var at: Double
}

/// One activity entry in the screen's words.
nonisolated struct BotActivityLine: Hashable, Sendable {
    var title: String
    var detail: String
    var source: String
}

/// How a notification kind looks (the kinds of bot_attention.NOTIFICATION_KINDS).
nonisolated struct BotNoticeLook: Hashable, Sendable {
    var label: String
    var symbol: String
    var problem = false
    var needsYou = false
}

/// Turning what the desktop sends into what the Inbox screens show. No state; checked by `BotInboxSamples.checks`.
nonisolated enum BotsInboxWire {

    /// "item", "review" or "permission" for an inbox row id like "item:abc".
    static func lane(_ rowID: String) -> String {
        String(rowID.split(separator: ":", maxSplits: 1).first ?? "")
    }

    static func noticeLook(_ kind: String?) -> BotNoticeLook {
        switch kind {
        case "approval": BotNoticeLook(label: "Approval", symbol: "checkmark.shield", needsYou: true)
        case "question": BotNoticeLook(label: "Question", symbol: "questionmark.bubble", needsYou: true)
        case "done": BotNoticeLook(label: "Finished", symbol: "checkmark.circle")
        case "routine-failed": BotNoticeLook(label: "Routine failed", symbol: "exclamationmark.triangle", problem: true)
        case "routine-deferred": BotNoticeLook(label: "Routine moved", symbol: "clock")
        case "turn-failed": BotNoticeLook(label: "Could not finish", symbol: "exclamationmark.triangle", problem: true)
        case "incident": BotNoticeLook(label: "Problem", symbol: "exclamationmark.octagon", problem: true)
        case "sign-in": BotNoticeLook(label: "Sign-in needed", symbol: "key", needsYou: true)
        case "delegation-settled": BotNoticeLook(label: "Handoff settled", symbol: "arrow.left.arrow.right")
        case "mention": BotNoticeLook(label: "Mention", symbol: "at")
        case "spend": BotNoticeLook(label: "Spend", symbol: "dollarsign.circle")
        case "brief": BotNoticeLook(label: "Brief", symbol: "sun.max")
        case "missed-call": BotNoticeLook(label: "Missed call", symbol: "phone.arrow.down.left")
        case "message": BotNoticeLook(label: "Message", symbol: "bubble.left")
        default: BotNoticeLook(label: "Notification", symbol: "bell")
        }
    }

    static func activityLine(_ entry: BotActivityEntryDTO) -> BotActivityLine {
        let data = entry.data ?? [:]
        func text(_ key: String) -> String? {
            let value = data[key]?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        if entry.source == "kairos-run-timeline" {
            let step = TasksWire.stepLabel(text("kind"))
            var parts: [String] = []
            if text("name") != nil { parts.append(step) }
            if let detail = text("detail") { parts.append(detail) }
            if let seconds = data["seconds"]?.double { parts.append(seconds < 10 ? String(format: "%.1f s", seconds) : "\(Int(seconds)) s") }
            if data["ok"]?.bool == false { parts.append("Did not work") }
            return BotActivityLine(title: text("name") ?? step, detail: parts.joined(separator: " · "), source: "Run timeline")
        }
        let title = text("label") ?? words(text("type")) ?? "Something happened"
        let detail = text("detail") ?? text("outcome") ?? text("status") ?? ""
        return BotActivityLine(title: title, detail: detail, source: "Runtime event")
    }

    /// "turn.completed" as "Turn completed".
    static func words(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        let spaced = code.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// A bot's cards and routines as Working (running, waiting its turn, stuck) and Done, newest first.
    /// Cards in Review are left out: they wait in Needs you.
    static func workRows(_ records: [BotWorkCardDTO]) -> (working: [BotWorkRow], done: [BotWorkRow]) {
        var working: [BotWorkRow] = []
        var done: [BotWorkRow] = []
        for record in records {
            let name = (record.name?.isEmpty == false ? record.name : nil) ?? "Untitled"
            let at = record.statusChangedAt ?? record.runStartedAt ?? record.lastRunAt ?? record.createdAt ?? 0
            let updated = ChatFormat.listTime(at > 0 ? Date(timeIntervalSince1970: at) : nil)
            let note = record.latestNote.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            if record.scheduleKind == "card" {
                switch record.status {
                case "running":
                    working.append(BotWorkRow(id: record.id, title: name, detail: "Working on it", state: .running,
                                              canStop: true, updated: updated, at: at))
                case "ready":
                    working.append(BotWorkRow(id: record.id, title: name, detail: "Waiting its turn", state: .waiting,
                                              canStop: false, updated: updated, at: at))
                case "blocked":
                    working.append(BotWorkRow(id: record.id, title: name, detail: note ?? "It could not finish.", state: .failed,
                                              canStop: false, updated: updated, at: at))
                case "done":
                    done.append(BotWorkRow(id: record.id, title: name, detail: note ?? "Done", state: .done,
                                           canStop: false, updated: updated, at: at))
                default:
                    break
                }
            } else if record.runStartedAt != nil {
                working.append(BotWorkRow(id: record.id, title: name, detail: "Routine running", state: .running,
                                          canStop: true, updated: updated, at: at))
            }
        }
        let rank: (BotWorkRow.State) -> Int = { $0 == .running ? 0 : ($0 == .failed ? 1 : 2) }
        working.sort { rank($0.state) != rank($1.state) ? rank($0.state) < rank($1.state) : $0.at > $1.at }
        done.sort { $0.at > $1.at }
        return (working, done)
    }

    static func tokens(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        if count < 1_000_000 { return "\(count / 1_000)K" }
        return String(format: "%.1fM", Double(count) / 1_000_000)
    }

    static func money(_ dollars: Double) -> String {
        if dollars > 0 && dollars < 0.01 { return "Under $0.01" }
        return String(format: "$%.2f", dollars)
    }

    /// The words the desktop takes as an approval when a review is answered (agent_service.py: APPROVALS).
    /// A change request in these words would approve the result instead.
    static func isApprovalWord(_ text: String) -> Bool {
        let trimmed = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!\n\t"))
        let words = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return ["approve", "approved", "lgtm", "ok", "okay", "yes", "looks good", "ship it", "done"].contains(words)
    }
}

/// An inbox row the desktop took an answer for, kept on screen with what happened.
nonisolated struct BotAnsweredRow: Sendable {
    var row: BotInboxRowDTO
    var text: String
    /// A read since the answer no longer listed the row as open. When it is open again it is a new request,
    /// even with the same text (and so the same revision); when a second read still has it closed, it goes.
    var closedSeen = false
}

/// The paired desktop behind a bot's Inbox half: the questions and reviews waiting in Needs you
/// (GET /api/bot-attention/inbox, POST .../inbox/{id}/respond), Working and Done (GET /api/tasks, stop, and a
/// stuck card sent back to Ready), notifications (GET /api/bot-attention/notifications, read, pin),
/// activity (GET /api/bot-attention/bots/{id}/activity) and the report (GET /api/bot-reports/bots/{id}).
/// Unpaired, nothing here runs and the screens show their samples.
@Observable
final class BotsInboxLive {
    static let shared = BotsInboxLive()

    private(set) var isLive = false
    @ObservationIgnored private var account = "sample"

    // Needs you: every bot's open inbox rows. The screens keep one bot's.
    var inboxRows: [BotInboxRowDTO] = []
    var inboxLoad: BotsLiveLoad = .idle
    var inboxSkipped = 0
    /// Rows whose answer is on its way.
    var busyRows: Set<String> = []
    /// Rows the desktop took an answer for, with what it said, kept on screen as settled.
    var answered: [String: BotAnsweredRow] = [:]

    // Working and Done: every task and card. The screens keep one bot's.
    var work: [BotWorkCardDTO] = []
    var workLoad: BotsLiveLoad = .idle
    var workSkipped = 0
    var busyWork: Set<String> = []

    // Notifications: every bot's. The screen keeps one bot's.
    var notices: [BotNotificationDTO] = []
    var noticesLoad: BotsLiveLoad = .idle
    var noticesSkipped = 0
    var busyNotices: Set<String> = []
    /// Bots whose Mark all read is going.
    var markingAll: Set<String> = []

    // Activity and reports, by bot (reports by bot and days).
    var activity: [String: [BotActivityEntryDTO]] = [:]
    var activityLoad: [String: BotsLiveLoad] = [:]
    var activitySkipped: [String: Int] = [:]
    var reports: [String: BotReportDTO] = [:]
    var reportLoad: [String: BotsLiveLoad] = [:]

    /// A counter per read: an answer is shown only when no newer read of the same thing began.
    @ObservationIgnored private var reads: [String: Int] = [:]
    /// Writes on their way, and a counter bumped when one is sent or answered, per group of lists.
    @ObservationIgnored private var writing: [String: Int] = [:]
    @ObservationIgnored private var writeSerial: [String: Int] = [:]

    // MARK: Pairing

    /// Match the connection: unpaired, nothing is kept; paired with another desktop or account, nothing read
    /// from the last one stays.
    func follow() {
        let want = !Connection.shared.usesSampleData
        let key = BotsStore.accountKey
        if want && isLive && account != key {
            reset()
            account = key
        }
        guard want != isLive else { return }
        reset()
        account = want ? key : "sample"
        isLive = want
    }

    private func reset() {
        inboxRows = []
        inboxLoad = .idle
        inboxSkipped = 0
        busyRows = []
        answered = [:]
        work = []
        workLoad = .idle
        workSkipped = 0
        busyWork = []
        notices = []
        noticesLoad = .idle
        noticesSkipped = 0
        busyNotices = []
        markingAll = []
        activity = [:]
        activityLoad = [:]
        activitySkipped = [:]
        reports = [:]
        reportLoad = [:]
        reads = [:]
    }

    /// Still showing the account a request was sent for. Checked after every await.
    private func stillLive(_ account: String) -> Bool {
        isLive && self.account == account && BotsStore.accountKey == account
    }

    private var liveNow: Bool { isLive && account == BotsStore.accountKey }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    private func say(_ text: String) { BotsStore.shared.say(text) }

    // MARK: Reading

    /// One read. Its answer is shown only when it is still this account's, no newer read of the same thing
    /// began, and no write to the same lists was sent or answered meanwhile (that write's own re-read follows).
    private func read<T>(
        _ key: String,
        group: String,
        state: BotsLiveLoad,
        set: (BotsLiveLoad) -> Void,
        failed: String,
        fetch: (APIClient) async throws -> T,
        show: (T) -> Void
    ) async {
        guard isLive else { return }
        let account = self.account
        let serial = (reads[key] ?? 0) + 1
        reads[key] = serial
        if state != .loaded { set(.loading) }
        // While the desktop is still being reached, wait for that to settle, then read whatever the state.
        await BotsStore.waitWhileConnecting()
        let writes = writeSerial[group] ?? 0
        do {
            try Task.checkCancellation()
            let answer = try await fetch(try liveClient())
            guard stillLive(account), reads[key] == serial else { return }
            // A first read is shown anyway: nothing is on screen yet for it to put back.
            guard state != .loaded || (writes == (writeSerial[group] ?? 0) && (writing[group] ?? 0) == 0) else { return }
            show(answer)
            set(.loaded)
        } catch {
            guard stillLive(account), reads[key] == serial else { return }
            if error is CancellationError {
                // Not read is not failed: the next look reads again.
                if state != .loaded { set(.idle) }
                return
            }
            Connection.shared.note(error)
            // What was read before stays on screen under the note.
            set(.failed(failed + " " + error.plainWords))
        }
    }

    func loadInbox() async {
        await read("inbox", group: "inbox", state: inboxLoad, set: { inboxLoad = $0 },
                   failed: "Questions and reviews could not be read.",
                   fetch: { try await $0.botInboxRows() },
                   show: { answer in
                       let list = BotLossyList(answer.rows)
                       withAnimation(Motion.snappy) { inboxRows = list.items }
                       inboxSkipped = list.skipped
                       // A row the desktop opened again shows as waiting again: a new revision, or open after a
                       // read had it closed (a redone review can come back with the same text and revision).
                       // A row still closed on a second read leaves the list.
                       for (id, kept) in answered {
                           let fresh = list.items.first(where: { $0.id == id })
                           if let fresh, fresh.status == "open" {
                               if fresh.revision != kept.row.revision || kept.closedSeen { answered[id] = nil }
                           } else if kept.closedSeen {
                               answered[id] = nil
                           } else {
                               answered[id]?.closedSeen = true
                           }
                       }
                   })
    }

    func loadWork() async {
        await read("work", group: "work", state: workLoad, set: { workLoad = $0 },
                   failed: "Working and Done could not be read.",
                   fetch: { try await $0.botWorkCards() },
                   show: { answer in
                       let list = BotLossyList(answer)
                       withAnimation(Motion.snappy) { work = list.items }
                       workSkipped = list.skipped
                   })
    }

    func loadNotices() async {
        await read("notices", group: "notices", state: noticesLoad, set: { noticesLoad = $0 },
                   failed: "Notifications could not be read.",
                   fetch: { try await $0.botNotificationRows() },
                   show: { answer in
                       let list = BotLossyList(answer.rows)
                       withAnimation(Motion.snappy) { notices = list.items }
                       noticesSkipped = list.skipped
                   })
    }

    func loadActivity(_ botID: String) async {
        await read("activity|\(botID)", group: "activity", state: activityLoad[botID] ?? .idle,
                   set: { activityLoad[botID] = $0 },
                   failed: "Activity could not be read.",
                   fetch: { try await $0.botActivity(botID) },
                   show: { answer in
                       let list = BotLossyList(answer.entries)
                       activity[botID] = list.items
                       activitySkipped[botID] = list.skipped
                   })
    }

    static func reportKey(_ botID: String, days: Int) -> String { "\(botID)|\(days)" }

    func loadReport(_ botID: String, days: Int) async {
        let key = Self.reportKey(botID, days: days)
        await read("report|\(key)", group: "report", state: reportLoad[key] ?? .idle,
                   set: { reportLoad[key] = $0 },
                   failed: "The report could not be read.",
                   fetch: { try await $0.botReport(botID, days: days) },
                   show: { reports[key] = $0 })
    }

    // MARK: What the screens ask

    /// This bot's rows waiting on the person: its questions ("item:") and results to review ("review:").
    /// Live approvals and questions in a conversation ("permission:") are the bot cards above them.
    func needsRows(_ botID: String) -> [BotInboxRowDTO] {
        let open = inboxRows.filter { row in
            row.sender?.id == botID && row.bucket == "needs-you" && answered[row.id] == nil
                && ["item", "review"].contains(BotsInboxWire.lane(row.id))
        }
        let kept = answered.values.map(\.row).filter { $0.sender?.id == botID }.sorted { ($0.at ?? 0) > ($1.at ?? 0) }
        return open + kept
    }

    func workRows(_ botID: String) -> (working: [BotWorkRow], done: [BotWorkRow]) {
        let mine = work.filter { $0.agentId == botID }
        var rows = BotsInboxWire.workRows(mine)
        // A card in Review waits in Needs you. The desktop's inbox leaves out one older than 30 days, so once the
        // inbox is read, such a card is shown here instead of nowhere.
        if inboxLoad == .loaded {
            let inInbox = Set(inboxRows.map(\.id))
            for record in mine where record.scheduleKind == "card" && record.status == "review"
                && !inInbox.contains("review:" + record.id) {
                let at = record.statusChangedAt ?? record.lastRunAt ?? record.createdAt ?? 0
                rows.working.append(BotWorkRow(
                    id: record.id, title: (record.name?.isEmpty == false ? record.name : nil) ?? "Untitled",
                    detail: "Waiting for your review. Review it on your desktop.", state: .waiting, canStop: false,
                    updated: ChatFormat.listTime(at > 0 ? Date(timeIntervalSince1970: at) : nil), at: at
                ))
            }
        }
        return rows
    }

    /// Something of this bot's is running, so it is checked again every few seconds. A card waiting its turn
    /// can wait for hours (its bot off or out of runs), so it is not watched.
    func watching(_ botID: String) -> Bool {
        isLive && BotsInboxWire.workRows(work.filter { $0.agentId == botID }).working.contains { $0.state == .running }
    }

    /// The light check while something of this bot's runs: each running card or routine on its own
    /// (GET /api/tasks/{id}). Only when one of them changed (or is gone) are Working, Done and Needs you read
    /// again in full. A check that does not get through waits for the next one, quietly.
    func pollRunning(_ botID: String) async {
        guard liveNow else { return }
        let account = self.account
        let running = BotsInboxWire.workRows(work.filter { $0.agentId == botID }).working
            .filter { $0.state == .running }.map(\.id)
        var changed = false
        for id in running {
            guard let before = work.first(where: { $0.id == id }) else { continue }
            do {
                let now = try await liveClient().botWorkCard(id)
                guard stillLive(account), !Task.isCancelled else { return }
                if now.status != before.status || now.runStartedAt != before.runStartedAt {
                    changed = true
                    break
                }
            } catch {
                guard stillLive(account), !Task.isCancelled else { return }
                if case .server(status: 404, _) = error as? APIError {
                    changed = true
                    break
                }
                return
            }
        }
        guard changed else { return }
        await loadWork()
        await loadInbox()
    }

    func noticeRows(_ botID: String) -> [BotNotificationDTO] {
        notices.filter { $0.agentId == botID }.sorted { a, b in
            if (a.pinned ?? false) != (b.pinned ?? false) { return a.pinned ?? false }
            return (a.at ?? 0) > (b.at ?? 0)
        }
    }

    func unread(_ botID: String) -> Int {
        notices.filter { $0.agentId == botID && $0.read != true }.count
    }

    // MARK: Writing

    private func beginWrite(_ groups: [String]) {
        for group in groups {
            writing[group, default: 0] += 1
            writeSerial[group, default: 0] += 1
        }
    }

    private func endWrite(_ groups: [String]) {
        for group in groups {
            writing[group] = max(0, (writing[group] ?? 0) - 1)
            writeSerial[group, default: 0] += 1
        }
    }

    /// A write whose answer never came: the desktop may have done it. An error that means the request never
    /// left this iPhone (no network, no such address, no secure connection) is not in doubt. An answer this app
    /// could not read, or a server error, can come after the desktop acted, so both are in doubt.
    private func unconfirmed(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        guard let api = error as? APIError else { return true }
        switch api {
        case .unreadable: return true
        case .server(let status, _): return status >= 500
        case .offline:
            let neverSent: [URLError.Code] = [.notConnectedToInternet, .cannotFindHost, .secureConnectionFailed,
                                              .appTransportSecurityRequiresSecureConnection]
            return !neverSent.contains { APIError.from(URLError($0)) == api }
        default: return false
        }
    }

    private func unsure(_ what: String) -> String {
        "Your desktop did not answer, so this iPhone could not confirm \(what). This list shows what your desktop has."
    }

    /// Answer a question or a review. `action` is one of the row's own actions: "reply" or "close" for a
    /// question, "approve" or "reply" (send it back with a note) for a review.
    func respond(_ row: BotInboxRowDTO, action: String, text: String = "") async -> BotsWriteOutcome {
        guard liveNow else {
            let words = "Still reading your desktop. Try again in a moment."
            say(words)
            return .refused(words)
        }
        guard let revision = row.revision, (row.actions ?? []).contains(action), action != "open",
              !busyRows.contains(row.id) else { return .refused("") }
        let account = self.account
        let groups = ["inbox", "work"]
        let review = BotsInboxWire.lane(row.id) == "review"
        let what: String
        switch (review, action) {
        case (true, "approve"): what = "the approval"
        case (true, _): what = "your note"
        case (false, "close"): what = "the question was closed"
        default: what = "your reply"
        }
        busyRows.insert(row.id)
        beginWrite(groups)
        do {
            _ = try await liveClient().botInboxRespond(row.id, action: action, expectedRevision: revision, text: text)
            endWrite(groups)
            guard stillLive(account) else { return .done }
            busyRows.remove(row.id)
            let settled: String
            switch (review, action) {
            case (true, "approve"): settled = "Approved. It is in Done."
            case (true, _): settled = "Sent back with your note. It will do it again."
            case (false, "close"): settled = "Closed without an answer."
            default: settled = "You replied: \(text)"
            }
            withAnimation(Motion.bouncy) { answered[row.id] = BotAnsweredRow(row: row, text: settled) }
            Haptics.success()
            // The screen stops saying "Sending" now; the re-reads follow on their own.
            Task {
                await loadInbox()
                await loadWork()
            }
            return .done
        } catch {
            endWrite(groups)
            guard stillLive(account) else { return .unsure }
            busyRows.remove(row.id)
            if unconfirmed(error) {
                if let api = error as? APIError, api != APIError.from(URLError(.timedOut)) { Connection.shared.note(api) }
                say(unsure(what))
                // The buttons stay off until the desktop's lists are read, so nothing is sent twice unseen.
                await loadInbox()
                await loadWork()
                return .unsure
            }
            Connection.shared.note(error)
            let words = error.plainWords
            say(words)
            Task { await loadInbox() }
            return .refused(words)
        }
    }

    /// Stop a running card or routine. A stopped card goes to its stuck list on the desktop.
    func stop(_ item: BotWorkRow) {
        guard liveNow, item.canStop, !busyWork.contains(item.id) else { return }
        let account = self.account
        busyWork.insert(item.id)
        beginWrite(["work"])
        Task {
            do {
                try await liveClient().taskStop(item.id)
                endWrite(["work"])
                guard stillLive(account) else { return }
                say("Stopping \(item.title)")
                try? await Task.sleep(for: .seconds(0.8))
                guard stillLive(account) else { return }
                busyWork.remove(item.id)
                await loadWork()
            } catch {
                endWrite(["work"])
                guard stillLive(account) else { return }
                busyWork.remove(item.id)
                if case .server(status: 409, _) = error as? APIError {
                    say("\(item.title) was not running.")
                } else if unconfirmed(error) {
                    say(unsure("\(item.title) stopped"))
                } else {
                    Connection.shared.note(error)
                    say("\(item.title) was not stopped. " + error.plainWords)
                }
                await loadWork()
            }
        }
    }

    /// Send a stuck card back to Ready, so the desktop runs it again when its turn comes
    /// (task_service.py: set_card_status, Blocked to Ready restores its attempts).
    func tryAgain(_ item: BotWorkRow) {
        guard liveNow, item.state == .failed, !busyWork.contains(item.id) else { return }
        let account = self.account
        busyWork.insert(item.id)
        beginWrite(["work"])
        Task {
            do {
                _ = try await liveClient().taskCardStatus(item.id, status: "ready", note: nil)
                endWrite(["work"])
                guard stillLive(account) else { return }
                busyWork.remove(item.id)
                say("\(item.title) will run again when its turn comes.")
                await loadWork()
            } catch {
                endWrite(["work"])
                guard stillLive(account) else { return }
                busyWork.remove(item.id)
                if unconfirmed(error) {
                    say("Your desktop did not answer, so this iPhone could not confirm \(item.title) will run again. It may be waiting to run; this list shows what your desktop has.")
                } else {
                    Connection.shared.note(error)
                    say("\(item.title) was not sent back to run. " + error.plainWords)
                }
                await loadWork()
            }
        }
    }

    /// Mark one notification read. Shown at once; put back if the desktop refuses.
    func markRead(_ notice: BotNotificationDTO) {
        guard liveNow, notice.read != true, !busyNotices.contains(notice.id) else { return }
        changeNotice(notice, what: "it was marked read", change: { $0.read = true }, undo: { $0.read = notice.read }) {
            try await $0.botNotificationMarkRead(notice.id)
        }
    }

    func setPinned(_ notice: BotNotificationDTO, _ pinned: Bool) {
        guard liveNow, !busyNotices.contains(notice.id) else { return }
        changeNotice(notice, what: pinned ? "it was pinned" : "it was unpinned",
                     change: { $0.pinned = pinned }, undo: { $0.pinned = notice.pinned }) {
            try await $0.botNotificationPin(notice.id, pinned: pinned)
        }
    }

    private func changeNotice(
        _ notice: BotNotificationDTO,
        what: String,
        change: @escaping (inout BotNotificationDTO) -> Void,
        undo: @escaping (inout BotNotificationDTO) -> Void,
        send: @escaping (APIClient) async throws -> Void
    ) {
        let account = self.account
        let id = notice.id
        busyNotices.insert(id)
        if let index = notices.firstIndex(where: { $0.id == id }) {
            withAnimation(Motion.snappy) { change(&notices[index]) }
        }
        beginWrite(["notices"])
        Task {
            do {
                try await send(try liveClient())
                endWrite(["notices"])
                guard stillLive(account) else { return }
                busyNotices.remove(id)
            } catch {
                endWrite(["notices"])
                guard stillLive(account) else { return }
                busyNotices.remove(id)
                if unconfirmed(error) {
                    say(unsure(what))
                } else {
                    Connection.shared.note(error)
                    if let index = notices.firstIndex(where: { $0.id == id }) {
                        withAnimation(Motion.snappy) { undo(&notices[index]) }
                    }
                    say(error.plainWords)
                }
                await loadNotices()
            }
        }
    }

    /// Mark this bot's unread notifications read, one by one. Never the desktop's read-all, which reads
    /// every bot's (bot_attention_routes.py: notifications_read_all).
    func markAllRead(_ botID: String) {
        guard liveNow, !markingAll.contains(botID) else { return }
        let ids = notices.filter { $0.agentId == botID && $0.read != true }.map(\.id).filter { !busyNotices.contains($0) }
        guard !ids.isEmpty else { return }
        let account = self.account
        markingAll.insert(botID)
        busyNotices.formUnion(ids)
        beginWrite(["notices"])
        Task {
            var lost = false
            var refused = 0
            for id in ids {
                do {
                    try await liveClient().botNotificationMarkRead(id)
                    guard stillLive(account) else { break }
                    if let index = notices.firstIndex(where: { $0.id == id }) {
                        withAnimation(Motion.snappy) { notices[index].read = true }
                    }
                } catch {
                    if unconfirmed(error) {
                        lost = true
                        break
                    }
                    Connection.shared.note(error)
                    refused += 1
                }
            }
            endWrite(["notices"])
            guard stillLive(account) else { return }
            markingAll.remove(botID)
            busyNotices.subtract(ids)
            if lost {
                say(unsure("every notification was marked read"))
            } else if refused > 0 {
                say(refused == 1 ? "One notification was not marked read. It may be gone from your desktop."
                                 : "\(refused) notifications were not marked read. They may be gone from your desktop.")
            } else {
                Haptics.success()
            }
            await loadNotices()
        }
    }
}
