import SwiftUI

// MARK: - Data

/// One message triage flagged as important. Mail is triage, not an inbox: only these come to the phone.
nonisolated struct MailItem: Identifiable, Hashable, Sendable {
    let id: String
    var sender: String
    var address: String
    var subject: String
    var time: String
    var reason: String
    var preview: String
    var needsReply: Bool
    /// What Kip writes when asked to draft a reply.
    var suggestedReply: String

    var initial: String {
        let letter = sender.first { $0.isLetter || $0.isNumber }
        return letter.map { String($0).uppercased() } ?? "?"
    }

    var subjectLine: String { subject.isEmpty ? "(no subject)" : subject }
}

/// A reply Kip drafted. It waits for the person's approval before anything is sent.
nonisolated struct MailDraft: Hashable, Sendable {
    var itemID: String
    var from: String
    var to: String
    var subject: String
    var body: String
}

/// An address agents can send from.
nonisolated struct MailSender: Identifiable, Hashable, Sendable {
    enum Via: Hashable, Sendable { case google, emailTab }
    var email: String
    var via: Via
    var canSend: Bool

    var id: String { email }

    var detail: String {
        switch via {
        case .google: canSend ? "Google · can send" : "Google · needs permission to send"
        case .emailTab: "Email tab account · can send"
        }
    }
}

/// An IMAP and SMTP account connected in the Email tab.
nonisolated struct MailAccount: Identifiable, Hashable, Sendable {
    var email: String
    var imapHost: String
    var imapPort: Int
    var smtpHost: String
    var smtpPort: Int
    /// Sample only: whether a test of this account's SMTP side works.
    var smtpWorks = true

    var id: String { email }
    var hosts: String { "\(imapHost) / \(smtpHost)" }
}

/// The result of "Test connection".
nonisolated struct MailTestResult: Hashable, Sendable {
    var text: String
    var ok: Bool
}

// MARK: - Provider

/// Where Mail's data comes from. The sample fills it now; the desktop connection replaces it later
/// (`/api/email/triage`, `/api/email/triage/run`, `/api/email/accounts`, `/api/email/sending-accounts`).
protocol MailProviding {
    func triage() -> [MailItem]
    /// Messages a fresh run finds that the last one did not.
    func newArrivals() -> [MailItem]
    func senders() -> [MailSender]
    func accounts() -> [MailAccount]
}

struct MailSampleProvider: MailProviding {
    func triage() -> [MailItem] {
        [
            MailItem(
                id: "m-invoice", sender: "Parts supplier", address: "orders@supplier.example.com",
                subject: "Invoice 1042 is due Friday", time: "8:12 AM",
                reason: "A payment is due in two days and they ask you to confirm the delivery date.",
                preview: "Hello, a reminder that invoice 1042 for the spring stock order is due on Friday. Could you confirm the delivery date that works for the shop?",
                needsReply: true,
                suggestedReply: "Hello,\n\nThanks for the reminder. The invoice will be paid by Friday. Tuesday morning works well for the delivery.\n\nBest regards"
            ),
            MailItem(
                id: "m-heating", sender: "Building office", address: "office@building.example.com",
                subject: "Heating check on Thursday", time: "7:40 AM",
                reason: "They need a time that suits you this week.",
                preview: "We are checking the heating in every flat this Thursday between 9 and 4. Please reply with a two hour window when someone can let us in.",
                needsReply: true,
                suggestedReply: "Hello,\n\nThursday between 10 and 12 works for me. Thank you for letting me know.\n\nBest regards"
            ),
            MailItem(
                id: "m-study", sender: "Study group", address: "group@study.example.com",
                subject: "Notes for Monday's meeting", time: "Yesterday",
                reason: "Your section is asked for by Sunday evening.",
                preview: "Could everyone send their section of the notes by Sunday evening? I will put them together before we meet on Monday.",
                needsReply: true,
                suggestedReply: "Hi all,\n\nI will send my section by Sunday afternoon.\n\nThanks"
            ),
            MailItem(
                id: "m-dentist", sender: "Dental clinic", address: "front.desk@clinic.example.com",
                subject: "Appointment reminder", time: "Yesterday",
                reason: "Your check-up is next Wednesday at 3:30 PM.",
                preview: "This is a reminder of your check-up next Wednesday at 3:30 PM. Reply only if you need to move it.",
                needsReply: false,
                suggestedReply: "Hello,\n\nThank you, I will be there on Wednesday at 3:30.\n\nBest regards"
            ),
            MailItem(
                id: "m-bank", sender: "Bank alerts", address: "alerts@bank.example.com",
                subject: "Your statement is ready", time: "Mon",
                reason: "The October statement shows a charge you have not seen before.",
                preview: "Your October statement is ready to view. Sign in to your account to see the full list of charges.",
                needsReply: false,
                suggestedReply: "Hello,\n\nThank you. I will review the statement.\n\nBest regards"
            ),
        ]
    }

    func newArrivals() -> [MailItem] {
        [
            MailItem(
                id: "m-room", sender: "Course office", address: "courses@college.example.com",
                subject: "Room change for Thursday's class", time: "Just now",
                reason: "Thursday's class moved to room B12.",
                preview: "Please note that Thursday's class meets in room B12 from this week on.",
                needsReply: false,
                suggestedReply: "Hello,\n\nThank you for the update.\n\nBest regards"
            ),
        ]
    }

    func senders() -> [MailSender] {
        [
            MailSender(email: "shop@example.com", via: .google, canSend: true),
            MailSender(email: "you@example.com", via: .google, canSend: false),
        ]
    }

    func accounts() -> [MailAccount] {
        [
            MailAccount(email: "hello@example.com", imapHost: "imap.example.com", imapPort: 993, smtpHost: "smtp.example.com", smtpPort: 465),
            MailAccount(email: "studio@example.net", imapHost: "imap.example.net", imapPort: 993, smtpHost: "smtp.example.net", smtpPort: 465, smtpWorks: false),
        ]
    }
}

// MARK: - Store

@Observable
final class MailStore {
    /// One store for the session, so the list, drafts and accounts survive leaving Mail.
    static let shared = MailStore(provider: MailSampleProvider())

    private let provider: any MailProviding
    var items: [MailItem]
    var drafts: [String: MailDraft] = [:]
    var lastChecked: Date?
    var scanned: Int
    var error: String?
    var refreshing = false
    var googleSenders: [MailSender]
    var accounts: [MailAccount]
    var testing: Set<String> = []
    var testResults: [String: MailTestResult] = [:]
    var query = ""
    var debugApplied = false
    private var arrivalsUsed = false

    init(provider: any MailProviding) {
        self.provider = provider
        items = provider.triage()
        googleSenders = provider.senders()
        accounts = provider.accounts()
        scanned = 38
        lastChecked = Calendar.current.date(bySettingHour: 5, minute: 50, second: 0, of: Date())
    }

    // Reading

    var needsReply: [MailItem] { filtered.filter(\.needsReply) }
    var alsoImportant: [MailItem] { filtered.filter { !$0.needsReply } }

    var filtered: [MailItem] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return items }
        return items.filter {
            $0.subjectLine.localizedCaseInsensitiveContains(text)
                || $0.sender.localizedCaseInsensitiveContains(text)
                || $0.address.localizedCaseInsensitiveContains(text)
                || $0.reason.localizedCaseInsensitiveContains(text)
        }
    }

    var matchingAccounts: [MailAccount] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return accounts.filter { $0.email.localizedCaseInsensitiveContains(text) || $0.hosts.localizedCaseInsensitiveContains(text) }
    }

    /// Every address agents can send from: Google accounts, then every Email tab account.
    var senders: [MailSender] {
        googleSenders + accounts.map { MailSender(email: $0.email, via: .emailTab, canSend: true) }
    }

    var defaultSender: String { senders.first(where: \.canSend)?.email ?? "" }

    var checkedLine: String {
        guard let lastChecked else { return "Runs automatically each morning at 5:50. Nothing checked yet." }
        let time = lastChecked.formatted(date: .omitted, time: .shortened)
        let day = Calendar.current.isDateInToday(lastChecked) ? time : lastChecked.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "Last checked \(day) · \(scanned) unread scanned"
    }

    // Triage

    /// Run triage now. Returns the summary for the toast.
    func refresh() async -> String {
        refreshing = true
        error = nil
        try? await Task.sleep(for: .seconds(1.5))
        var fresh = 0
        if lastChecked == nil && items.isEmpty {
            items = provider.triage()
            fresh = items.count
        }
        if !arrivalsUsed {
            arrivalsUsed = true
            let arrivals = provider.newArrivals().filter { arrival in !items.contains { $0.id == arrival.id } }
            items.insert(contentsOf: arrivals, at: 0)
            fresh += arrivals.count
        }
        scanned += 4 + fresh
        lastChecked = Date()
        refreshing = false
        if items.isEmpty { return "Triage complete" }
        return "\(items.count) important, \(fresh) new"
    }

    func markHandled(_ id: String) {
        items.removeAll { $0.id == id }
        drafts[id] = nil
    }

    func saveDraft(_ draft: MailDraft) {
        drafts[draft.itemID] = draft
    }

    /// Send an approved draft: the message leaves the list.
    func send(_ draft: MailDraft) {
        drafts[draft.itemID] = nil
        items.removeAll { $0.id == draft.itemID }
    }

    func newDraft(for item: MailItem) -> MailDraft {
        MailDraft(itemID: item.id, from: defaultSender, to: item.address,
                  subject: item.subject.hasPrefix("Re:") ? item.subject : "Re: \(item.subjectLine)",
                  body: item.suggestedReply)
    }

    // Accounts

    func addAccount(_ account: MailAccount) {
        accounts.removeAll { $0.email.lowercased() == account.email.lowercased() }
        accounts.append(account)
    }

    func remove(_ account: MailAccount) {
        accounts.removeAll { $0.id == account.id }
        testResults[account.id] = nil
    }

    /// Test an account's IMAP and SMTP. Returns whether both worked.
    func test(_ account: MailAccount) async -> Bool {
        testing.insert(account.id)
        testResults[account.id] = nil
        try? await Task.sleep(for: .seconds(1.2))
        testing.remove(account.id)
        let result = MailTestResult(text: "IMAP: OK · SMTP: \(account.smtpWorks ? "OK" : "failed")", ok: account.smtpWorks)
        testResults[account.id] = result
        return result.ok
    }

    // Debug pictures

    func showFirstRun() {
        items = []
        lastChecked = nil
        scanned = 0
        error = nil
    }

    func showEmptyRun() {
        items = []
        arrivalsUsed = true
        error = nil
    }

    func showError() {
        error = "Triage failed: imap.example.net did not accept the password. Check the account and try again."
    }
}
