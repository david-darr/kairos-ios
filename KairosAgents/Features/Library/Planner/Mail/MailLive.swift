import SwiftUI

/// Where the first desktop read stands, for one plain sentence on screen.
nonisolated enum MailLiveLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// How a send ended, as far as the phone can know.
nonisolated enum MailSendOutcome: Equatable, Sendable {
    /// The desktop said it went (or it is in the Sent folder). The text is the sending address.
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

    /// A key that changes when the phone is paired or unpaired, the desktop comes back,
    /// or a different desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
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
        items = triage.items.map { dto in
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
        refreshing = true
        liveNote = nil
        do {
            let ran = try await liveClient().mailRunTriage()
            guard stillLive(account) else { return "" }
            writeSerial += 1
            showTriage(ran)
            refreshing = false
            if items.isEmpty { return "Triage complete. Nothing important." }
            return "\(items.count) important of \(scanned) unread"
        } catch {
            Connection.shared.note(error)
            guard stillLive(account) else { return "" }
            writeSerial += 1
            refreshing = false
            if case .server(let status, let detail)? = error as? APIError, status < 500 || detail.hasPrefix("triage failed") {
                liveNote = "Triage did not run. " + (detail.isEmpty ? error.plainWords : detail)
                await loadLive()
                return "Triage did not run"
            }
            // No answer: the run may still finish on the desktop. Show what it has now.
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
        case .server(let status, let detail) where status < 500: return detail.isEmpty ? api.plain : detail
        default: return nil
        }
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
                return .unknown("Your desktop did not answer. \(target.email) is still on its list, so it was not removed.")
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

    /// Check a reply before it goes. Nil when it can be sent, or the reason it cannot.
    func sendProblem(_ draft: MailDraft) -> String? {
        guard let sender = liveSenders.first(where: { $0.email.lowercased() == draft.from.lowercased() }), sender.sendsFromPhone else {
            return "Choose an Email tab account to send from. Google accounts send only from your desktop."
        }
        guard let to = MailWire.recipients(draft.to), !to.isEmpty else { return "Check the To line. Separate addresses with commas." }
        guard to.count <= MailWire.maxRecipients else { return "Send to at most \(MailWire.maxRecipients) addresses at once." }
        guard !draft.subject.contains("\n"), !draft.subject.contains("\r") else { return "The subject must be one line." }
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, draft.body.count <= 50_000 else { return "The reply must be 1 to 50,000 characters." }
        return nil
    }

    /// Send one reply through the desktop, exactly as written. Never retried. With no answer, the Sent
    /// folder is read to see whether it went; if that cannot tell, the draft is kept and the outcome says so.
    func sendLive(_ draft: MailDraft) async -> MailSendOutcome {
        guard !isSample else { return .notSent("This is sample mail.") }
        guard !sendingIDs.contains(draft.itemID) else { return .notSent("This reply is already on its way.") }
        if let problem = sendProblem(draft) { return .notSent(problem) }
        guard let sender = liveSenders.first(where: { $0.email.lowercased() == draft.from.lowercased() }),
              let accountID = sender.remoteID, let to = MailWire.recipients(draft.to) else {
            return .notSent("Choose an Email tab account to send from.")
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
                return await unconfirmed(draft, accountID: accountID, started: started, account: account)
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
            return await unconfirmed(draft, accountID: accountID, started: started, account: account)
        }
    }

    /// A send with no clear answer: read the Sent folder for it, and say plainly what is known.
    private func unconfirmed(_ draft: MailDraft, accountID: String, started: Date, account: String) async -> MailSendOutcome {
        guard stillLive(account) else {
            return .unknown("This iPhone could not confirm the reply was sent. Check Sent in your mail app before sending it again.")
        }
        writeSerial += 1
        unconfirmedSends[draft.itemID] = started
        drafts[draft.itemID] = draft
        if await foundInSent(draft, accountID: accountID, after: started), stillLive(account) {
            drafts[draft.itemID] = nil
            unconfirmedSends[draft.itemID] = nil
            sentIDs.insert(draft.itemID)
            return .sent(draft.from)
        }
        return .unknown("This iPhone could not confirm the reply was sent. It may have gone. Check Sent in your mail app before sending it again. Your reply is kept here.")
    }

    /// Whether the newest Sent mail has this reply. Folders are read only; nothing is marked or moved.
    private func foundInSent(_ draft: MailDraft, accountID: String, after started: Date) async -> Bool {
        guard let client = Connection.shared.client else { return false }
        let subject = draft.subject.trimmingCharacters(in: .whitespaces).lowercased()
        let from = draft.from.lowercased()
        for folder in MailWire.sentFolders {
            guard let rows = try? await client.mailFolder(accountID, folder: folder, limit: 20) else { continue }
            // The first folder that answers is the one that counts.
            return rows.contains { row in
                guard (row.subject ?? "").trimmingCharacters(in: .whitespaces).lowercased() == subject,
                      (row.from ?? "").lowercased().contains(from),
                      let when = MailWire.date(row.date) else { return false }
                return when >= started.addingTimeInterval(-300)
            }
        }
        return false
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
