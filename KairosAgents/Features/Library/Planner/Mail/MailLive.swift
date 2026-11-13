import SwiftUI

/// Where the first desktop read stands, for one plain sentence on screen.
nonisolated enum MailLiveLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// How a send ended, as far as the phone can know.
nonisolated enum MailSendOutcome: Equatable, Sendable {
    /// The desktop said it went. Only the desktop's own answer counts, never the Sent folder. The text is the sending address.
    case sent(String)
    /// The desktop refused it before sending: nothing went.
    case notSent(String)
    /// No answer, or an answer that does not say. It may have gone.
    case unknown(String)
}

/// How an account change ended.
nonisolated enum MailWriteOutcome: Equatable, Sendable {
    case done(String)
    case failed(String)
    case unknown(String)
}

/// The sample mail, kept aside while the phone shows the paired desktop's mail.
struct MailSampleStash {
    var items: [MailItem]
    var drafts: [String: MailDraft]
    var lastChecked: Date?
    var scanned: Int
    var error: String?
    var googleSenders: [MailSender]
    var accounts: [MailAccount]
    var testResults: [String: MailTestResult]
    var query: String
    var arrivalsUsed: Bool
}

/// The paired desktop behind Mail (routes/email_routes.py): triage (GET /api/email/triage, POST /api/email/triage/run),
/// the Email tab accounts (GET, POST, DELETE /api/email/accounts, POST .../test), the sending addresses
/// (GET /api/email/sending-accounts) and a reply (POST /api/email/accounts/{id}/send). Unpaired, nothing here runs.
extension MailStore {

    /// A key that changes with every connection state (paired or unpaired, connecting, offline, signed out,
    /// back again) and when a different desktop or account is paired. Connecting that ends offline
    /// changes it too, so the waiting card always ends in an answer or an error with Try again.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.state)-\(accountKey)"
    }

    /// Which desktop and which account the mail belongs to. Live mail is only ever shown under this key.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Still showing the live mail a request was sent for. Checked after every await before writing a result.
    func stillLive(_ account: String) -> Bool {
        !isSample && liveAccount == account && Self.accountKey == account
    }

    /// The screen may show what the store holds: sample mail unpaired, the desktop's mail once it has been read.
    var readyToShow: Bool {
        if Connection.shared.usesSampleData { return isSample }
        return !isSample && liveLoad == .loaded
    }

    /// Move between sample mail and the paired desktop to match the connection.
    func followConnection() {
        let wantLive = !Connection.shared.usesSampleData
        if wantLive && !isSample && liveAccount != Self.accountKey {
            // Another desktop or account: nothing read from the last one may stay on screen.
            resetLive()
        }
        guard wantLive == isSample else { return }
        if wantLive {
            sampleStash = MailSampleStash(items: items, drafts: drafts, lastChecked: lastChecked, scanned: scanned,
                                          error: error, googleSenders: googleSenders, accounts: accounts,
                                          testResults: testResults, query: query, arrivalsUsed: arrivalsUsed)
            resetLive()
            isSample = false
        } else {
            resetLive()
            liveAccount = "sample"
            isSample = true
            if let stash = sampleStash {
                items = stash.items
                drafts = stash.drafts
                lastChecked = stash.lastChecked
                scanned = stash.scanned
                error = stash.error
                googleSenders = stash.googleSenders
                accounts = stash.accounts
                testResults = stash.testResults
                query = stash.query
                arrivalsUsed = stash.arrivalsUsed
            } else {
                items = provider.triage()
                googleSenders = provider.senders()
                accounts = provider.accounts()
            }
            sampleStash = nil
        }
    }

    /// Every live item, draft, account and state goes, ready to read the current account's mail.
    private func resetLive() {
        items = []
        drafts = [:]
        lastChecked = nil
        scanned = 0
        error = nil
        googleSenders = []
        accounts = []
        testing = []
        testResults = [:]
        query = ""
        refreshing = false
        liveSenders = []
        googleConfigured = false
        liveNote = nil
        liveLoad = .idle
        sendingIDs = []
        sentIDs = []
        unconfirmedSends = [:]
        accountBusy = false
        triageUnclearSince = nil
        // Answers to anything already on its way are now stale.
        readSerial += 1
        writeSerial += 1
        liveAccount = Self.accountKey
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    // MARK: Reading

    /// Read triage, the Email tab accounts and the sending addresses. Already read, it refreshes quietly.
    func loadLive() async {
        guard !isSample else { return }
        let account = liveAccount
        if Connection.shared.state == .connecting {
            // The read starts by itself once the desktop answers (connectionKey changes).
            if liveLoad != .loaded { liveLoad = .loading }
            return
        }
        readSerial += 1
        let serial = readSerial
        let writesAtStart = writeSerial
        if liveLoad != .loaded { liveLoad = .loading }
        do {
            let client = try liveClient()
            let triage = try await client.mailTriage()
            let listed = try await client.mailAccounts()
            let sending = try await client.mailSendingAccounts()
            // A newer read, or a write that finished meanwhile, has the better answer.
            guard stillLive(account), serial == readSerial, writesAtStart == writeSerial else { return }
            showTriage(triage)
            showAccounts(listed.accounts)
            showSenders(sending)
            let skipped = triage.skipped + listed.skipped + sending.skipped
            liveNote = skipped == 0 ? nil
                : (skipped == 1 ? "1 item from your desktop could not be read and is left out."
                                : "\(skipped) items from your desktop could not be read and are left out.")
            liveLoad = .loaded
        } catch is CancellationError {
            // Stopped (the screen went away or the connection changed): not a failure.
            guard stillLive(account), serial == readSerial else { return }
            if liveLoad == .loading { liveLoad = .idle }
        } catch {
            Connection.shared.note(error)
            guard stillLive(account), serial == readSerial else { return }
            let words = (error as? APIError) == .notPaired ? Connection.shared.statusLine : error.plainWords
            if liveLoad == .loaded {
                liveNote = "Your mail could not be read again. This shows the last answer. " + words
            } else {
                liveLoad = .failed("Your mail could not be read. " + words)
            }
        }
    }

    private func showTriage(_ triage: MailTriageDTO) {
        var seen: [String: Int] = [:]
        let fresh: [MailItem] = triage.items.map { dto in
            let sender = MailWire.parse(dto.from ?? "")
            var key = [dto.account ?? "", dto.from ?? "", dto.subject ?? "", dto.date ?? ""].joined(separator: "|")
            let repeats = seen[key, default: 0]
            seen[key] = repeats + 1
            if repeats > 0 { key += "#\(repeats)" }
            return MailItem(id: "live|" + key,
                            sender: sender.name.isEmpty ? "Unknown sender" : sender.name,
                            address: sender.address,
                            subject: dto.subject ?? "",
                            time: MailWire.timeText(dto.date),
                            reason: dto.reason ?? "",
                            preview: "",
                            needsReply: false,
                            suggestedReply: "",
                            account: dto.account)
        }
        // A message with a reply waiting here (a draft, or a send that could not be confirmed) stays on
        // the list after triage stops listing it, so the reply and its warning can still be reached.
        let freshIDs = Set(fresh.map(\.id))
        let kept = items.filter { old in
            !freshIDs.contains(old.id) && (drafts[old.id] != nil || unconfirmedSends[old.id] != nil)
        }
        items = fresh + kept
        lastChecked = triage.generatedAt.map { Date(timeIntervalSince1970: $0) }
        scanned = triage.scanned ?? 0
        let problem = triage.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        error = problem.isEmpty ? nil : problem
    }

    private func showAccounts(_ list: [MailAccountDTO]) {
        accounts = list.map { dto in
            MailAccount(email: dto.email, imapHost: dto.imapHost ?? "", imapPort: dto.imapPort ?? 993,
                        smtpHost: dto.smtpHost ?? "", smtpPort: dto.smtpPort ?? 465, remoteID: dto.id)
        }
        let ids = Set(accounts.map(\.id))
        testResults = testResults.filter { ids.contains($0.key) }
    }

    private func showSenders(_ sending: MailSendingAccountsDTO) {
        liveSenders = sending.accounts.map { dto in
            MailSender(email: dto.email, via: dto.via == "Google" ? .google : .emailTab,
                       canSend: dto.canSend ?? false, remoteID: dto.id)
        }
        googleSenders = liveSenders.filter { $0.via == .google }
        googleConfigured = sending.googleConfigured ?? false
    }

    // MARK: Triage now

    /// Run triage on the desktop now (the same pass as its 05:50 task). Returns the line for the toast.
    func runTriageLive() async -> String {
        guard !isSample, !refreshing else { return "" }
        let account = liveAccount
        if let since = triageUnclearSince, Date().timeIntervalSince(since) < MailWire.runSettle {
            // The last run went without an answer and may still be going: a second run would ask the model again.
            // Read what the desktop has instead.
            refreshing = true
            await loadLive()
            guard stillLive(account) else { return "" }
            refreshing = false
            liveNote = "Your desktop may still be running the last check. This shows what it has now. Try again in a few minutes."
            return "The last check may still be running"
        }
        refreshing = true
        liveNote = nil
        do {
            let ran = try await liveClient().mailRunTriage()
            guard stillLive(account) else { return "" }
            writeSerial += 1
            triageUnclearSince = nil
            showTriage(ran)
            refreshing = false
            if items.isEmpty { return "Triage complete. Nothing important." }
            return "\(items.count) important of \(scanned) unread"
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return "" }
            writeSerial += 1
            refreshing = false
            if case .server(let status, let detail)? = error as? APIError, Self.isRefusal(status, detail) || detail.hasPrefix("triage failed") {
                liveNote = "Triage did not run. " + (detail.isEmpty ? error.plainWords : detail)
                await loadLive()
                return "Triage did not run"
            }
            // No answer: the run may still finish on the desktop. Show what it has now, and hold off a second run.
            triageUnclearSince = Date()
            await loadLive()
            if stillLive(account) {
                liveNote = "Your desktop did not answer in time, so this may not be the newest check. It shows what your desktop has now."
            }
            return "Could not confirm the check finished"
        }
    }

    // MARK: Accounts

    /// Read the accounts and sending addresses again, after a change. Nil when they could not be read.
    private func rereadAccounts(_ account: String) async -> [MailAccount]? {
        readSerial += 1
        do {
            let client = try liveClient()
            let listed = try await client.mailAccounts()
            let sending = try await client.mailSendingAccounts()
            guard stillLive(account) else { return nil }
            writeSerial += 1
            showAccounts(listed.accounts)
            showSenders(sending)
            return accounts
        } catch {
            Connection.shared.note(error)
            return nil
        }
    }

    /// Whether an error means the desktop answered and refused, so nothing changed.
    private static func refused(_ error: Error) -> String? {
        guard let api = error as? APIError else { return nil }
        switch api {
        case .notPaired, .unauthorized, .badAddress: return api.plain
        case .server(let status, let detail) where isRefusal(status, detail): return detail
        default: return nil
        }
    }

    /// The desktop answered and said no. A 408 or 499, or a 4xx with no readable reason, can come from a tunnel
    /// or proxy that stopped waiting after the desktop already took the request, so those count as no answer.
    private static func isRefusal(_ status: Int, _ detail: String) -> Bool {
        status < 500 && status != 408 && status != 499 && !detail.isEmpty
    }

    /// Add an Email tab account on the desktop. The password goes to the desktop only and is not kept here.
    func addAccountLive(email: String, password: String, imapHost: String, imapPort: Int,
                        smtpHost: String, smtpPort: Int) async -> MailWriteOutcome {
        guard !isSample, !accountBusy else { return .failed("Wait for the last change to finish.") }
        guard !accounts.contains(where: { $0.email.lowercased() == email.lowercased() }) else {
            return .failed("\(email) is already connected.")
        }
        let account = liveAccount
        accountBusy = true
        defer { if stillLive(account) { accountBusy = false } }
        do {
            _ = try await liveClient().mailAddAccount(email: email, password: password, imapHost: imapHost, imapPort: imapPort,
                                                      smtpHost: smtpHost, smtpPort: smtpPort)
            guard stillLive(account) else { return .done("Account added") }
            writeSerial += 1
            _ = await rereadAccounts(account)
            return .done("Account added")
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .unknown("Your desktop or account changed. Check the list on your desktop.") }
            writeSerial += 1
            if let why = Self.refused(error) { return .failed(why) }
            // No answer: look at the list before saying anything.
            if let now = await rereadAccounts(account) {
                if now.contains(where: { $0.email.lowercased() == email.lowercased() }) { return .done("Account added") }
                return .unknown("Your desktop did not answer, so this iPhone cannot tell whether \(email) was added. It is not on the list yet. Wait a moment before adding it again.")
            }
            return .unknown("Your desktop did not answer, so this iPhone cannot tell whether \(email) was added. Check the list on your desktop before adding it again.")
        }
    }

    /// Remove an Email tab account on the desktop: Kairos stops reading it and deletes its saved password.
    func removeAccountLive(_ target: MailAccount) async -> MailWriteOutcome {
        guard !isSample, !accountBusy else { return .failed("Wait for the last change to finish.") }
        guard let id = target.remoteID else { return .failed("This account cannot be removed from here.") }
        let account = liveAccount
        accountBusy = true
        defer { if stillLive(account) { accountBusy = false } }
        do {
            _ = try await liveClient().mailRemoveAccount(id)
            guard stillLive(account) else { return .done("Account removed") }
            writeSerial += 1
            testResults[target.id] = nil
            _ = await rereadAccounts(account)
            return .done("Account removed")
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return .unknown("Your desktop or account changed. Check the list on your desktop.") }
            writeSerial += 1
            if let why = Self.refused(error) { return .failed(why) }
            if let now = await rereadAccounts(account) {
                if !now.contains(where: { $0.remoteID == id }) { return .done("Account removed") }
                return .unknown("Your desktop did not answer. \(target.email) is still on its list, so it is not removed yet. Wait a moment and check the list before removing it again.")
            }
            return .unknown("Your desktop did not answer, so this iPhone cannot tell whether \(target.email) was removed. Check the list on your desktop.")
        }
    }

    /// Test an account's IMAP and SMTP sign-in on the desktop. Changes nothing.
    func testLive(_ target: MailAccount) async -> Bool {
        guard !isSample, let id = target.remoteID, !testing.contains(target.id) else { return false }
        let account = liveAccount
        testing.insert(target.id)
        testResults[target.id] = nil
        do {
            let result = try await liveClient().mailTestAccount(id)
            guard stillLive(account) else { return false }
            testing.remove(target.id)
            let imap = result.imap ?? false
            let smtp = result.smtp ?? false
            testResults[target.id] = MailTestResult(text: "IMAP: \(imap ? "OK" : "failed") · SMTP: \(smtp ? "OK" : "failed")", ok: imap && smtp)
            return imap && smtp
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return false }
            testing.remove(target.id)
            let text = Self.refused(error) ?? "The test did not finish"
            testResults[target.id] = MailTestResult(text: text, ok: false)
            return false
        }
    }

    // MARK: Sending

    /// The Email tab account a reply to this message goes from: only the account it came to, never another.
    /// Nil when that account cannot send from the phone (it is not an Email tab account here, or nothing says
    /// which account the message came to): then replying is off for this message and the person replies from
    /// the desktop. When the address is both a Google account and an Email tab account, the Email tab one sends.
    func replyAccount(for item: MailItem) -> MailAccount? {
        guard !isSample else { return nil }
        let to = (item.account ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !to.isEmpty else { return nil }
        let matches = accounts.filter { $0.remoteID != nil && $0.email.lowercased() == to }
        // An account the desktop lists as this person's own sender comes first.
        let own = Set(liveSenders.filter { $0.via == .emailTab }.compactMap(\.remoteID))
        return matches.first(where: { own.contains($0.remoteID ?? "") }) ?? matches.first
    }

    /// The reply account as a sender, for the draft's From line.
    func replySender(for item: MailItem) -> MailSender? {
        replyAccount(for: item).map { MailSender(email: $0.email, via: .emailTab, canSend: true, remoteID: $0.remoteID) }
    }

    /// One plain line when replying from the phone is off for this message.
    func replyOffLine(for item: MailItem) -> String {
        let to = (item.account ?? "").trimmingCharacters(in: .whitespaces)
        if to.isEmpty { return "Kairos does not know which address this came to. Reply from your desktop." }
        return "This came to \(to), which cannot send from this iPhone. Reply from your desktop."
    }

    /// Check a reply before it goes. Nil when it can be sent, or the reason it cannot.
    func sendProblem(_ draft: MailDraft, for item: MailItem) -> String? {
        guard let sender = replyAccount(for: item) else { return replyOffLine(for: item) }
        guard draft.from.lowercased() == sender.email.lowercased() else {
            return "A reply goes from \(sender.email), the address this came to."
        }
        guard let to = MailWire.recipients(draft.to), !to.isEmpty else { return "Check the To line. Separate addresses with commas." }
        guard to.count <= MailWire.maxRecipients else { return "Send to at most \(MailWire.maxRecipients) addresses at once." }
        guard !draft.subject.contains("\n"), !draft.subject.contains("\r") else { return "The subject must be one line." }
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, draft.body.count <= 50_000 else { return "The reply must be 1 to 50,000 characters." }
        return nil
    }

    /// Send one reply through the desktop, exactly as written. Never retried. Only the desktop's own
    /// "ok" counts as sent. With no answer, the draft is kept, the Sent folder is read once, and the
    /// outcome says honestly what is known.
    func sendLive(_ draft: MailDraft, for item: MailItem) async -> MailSendOutcome {
        guard !isSample else { return .notSent("This is sample mail.") }
        guard !sendingIDs.contains(draft.itemID) else { return .notSent("This reply is already on its way.") }
        if let problem = sendProblem(draft, for: item) { return .notSent(problem) }
        guard let sender = replyAccount(for: item), let accountID = sender.remoteID,
              let to = MailWire.recipients(draft.to) else {
            return .notSent(replyOffLine(for: item))
        }
        let account = liveAccount
        let started = Date()
        sendingIDs.insert(draft.itemID)
        // Kept from the start: if the answer never comes, the reply is still here.
        drafts[draft.itemID] = draft
        defer { if stillLive(account) { sendingIDs.remove(draft.itemID) } }
        do {
            let answer = try await liveClient().mailSend(accountID: accountID, to: to.joined(separator: ", "),
                                                         subject: draft.subject, body: draft.body)
            guard answer.ok == true else {
                return await unconfirmed(draft, sender: sender, started: started, account: account, said: nil)
            }
            if stillLive(account) {
                writeSerial += 1
                drafts[draft.itemID] = nil
                unconfirmedSends[draft.itemID] = nil
                sentIDs.insert(draft.itemID)
            }
            return .sent(sender.email)
        } catch {
            Connection.shared.note(error)
            if let why = Self.refused(error) {
                // Refused before anything was sent (a missing account, a bad request, signed out).
                return .notSent(why)
            }
            // A 502 "SMTP error" can come after the message went (the desktop reports a failed quit too),
            // so it is not called "not sent". Its words are shown, so a wrong password is plain to see.
            var said: String?
            if case .server(_, let detail)? = error as? APIError, detail.hasPrefix("SMTP error") { said = detail }
            return await unconfirmed(draft, sender: sender, started: started, account: account, said: said)
        }
    }

    /// A send with no clear answer. The draft stays and nothing says "sent": the Sent folder is read once,
    /// and what it shows only tells the person where to look before sending again.
    private func unconfirmed(_ draft: MailDraft, sender: MailAccount, started: Date, account: String,
                             said: String?) async -> MailSendOutcome {
        let lead = "The phone could not confirm this was sent."
        let tail = said.map { " Your desktop said: \($0)" } ?? ""
        guard stillLive(account) else {
            return .unknown(lead + " Check your Sent folder before sending again." + tail)
        }
        writeSerial += 1
        unconfirmedSends[draft.itemID] = started
        drafts[draft.itemID] = draft
        let found = await lookInSent(draft, sender: sender, after: started)
        switch found {
        case true?:
            return .unknown(lead + " Something like it is in your Sent folder: check it before sending again." + tail)
        case false?:
            return .unknown(lead + " Nothing like it is in your Sent folder yet: check Sent before sending again." + tail)
        case nil:
            return .unknown(lead + " Your Sent folder could not be checked either: check Sent in your mail app before sending again." + tail)
        }
    }

    /// One read-only look at the newest Sent mail for a message like this one (same subject, from this
    /// address, dated from about a minute before the send). Nil when the folder could not be read within
    /// `MailWire.sentCheckLimit`. A match cannot tell this reply from another with the same subject, so it
    /// is never taken as proof that this reply went.
    private func lookInSent(_ draft: MailDraft, sender: MailAccount, after started: Date) async -> Bool? {
        guard let client = Connection.shared.client, let accountID = sender.remoteID else { return nil }
        let folder = MailWire.sentFolder(imapHost: sender.imapHost)
        let read = Task { () -> [MailHeaderDTO] in
            try await client.mailFolder(accountID, folder: folder, limit: 20, timeout: MailWire.sentCheckTimeout)
        }
        // A hard stop for the whole check, whatever the network does.
        let stop = Task {
            try? await Task.sleep(for: .seconds(MailWire.sentCheckLimit))
            read.cancel()
        }
        defer { stop.cancel() }
        guard let rows = try? await read.value else { return nil }
        let subject = MailWire.plainSubject(draft.subject)
        let from = sender.email.lowercased()
        return rows.contains { row in
            guard MailWire.plainSubject(row.subject ?? "") == subject,
                  (row.from ?? "").lowercased().contains(from),
                  let when = MailWire.date(row.date) else { return false }
            return when >= started.addingTimeInterval(-60)
        }
    }
}

// MARK: - Shared pieces

/// One quiet line on the Mail screen: reading, what failed with Try again, or a note.
struct MailLiveLine: View {
    let text: String
    var symbol: String = "info.circle"
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
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
