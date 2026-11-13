import Foundation

// The desktop's Email tab routes (routes/email_routes.py), as the phone reads them: one decoder per answer
// and one function per route. Shapes were read from core/email_triage.py, core/builtin_tasks.py
// (_run_triage_email), core/email_send.py (accounts) and services/email_service.py.
//
// - Triage keeps headers only: sender, subject, the Date header as written, the receiving account and the
//   model's one-line reason. No body, no message id, no "needs a reply" flag.
// - Lists are decoded item by item: one item of an unexpected shape is skipped and counted, never the list.
// - Sending goes through POST /api/email/accounts/{id}/send, which sends over SMTP from an Email tab account.
//   Google accounts send only through a bot's tool on the desktop, so the phone cannot send from them.

// MARK: - Item by item

/// One list item that decodes, or nil when it does not. The list around it still decodes.
nonisolated struct MailLossy<T: Decodable & Sendable>: Decodable, Sendable {
    var value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - Triage

/// GET /api/email/triage (email_triage.load) and POST /api/email/triage/run (the same, plus `summary`).
nonisolated struct MailTriageDTO: Decodable, Sendable {
    /// Epoch seconds of the last run, or nil before the first.
    var generatedAt: Double?
    var scanned: Int?
    /// The last run's problem in the desktop's words ("No email accounts connected."), or nil.
    var error: String?
    /// The run's own report. POST /api/email/triage/run only.
    var summary: String?
    var items: [MailTriageItemDTO]
    /// Items that did not decode and were left out.
    var skipped: Int

    enum CodingKeys: String, CodingKey {
        case generatedAt, scanned, error, summary, items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(Double.self, forKey: .generatedAt)
        scanned = try container.decodeIfPresent(Int.self, forKey: .scanned)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        let raw = try container.decodeIfPresent([MailLossy<MailTriageItemDTO>].self, forKey: .items) ?? []
        items = raw.compactMap(\.value)
        skipped = raw.count - items.count
    }
}

/// One important message (builtin_tasks.py: _run_triage_email).
nonisolated struct MailTriageItemDTO: Decodable, Sendable {
    /// The From header, decoded: "Name <name@example.com>" or a bare address.
    var from: String?
    var subject: String?
    /// The Date header as written ("Tue, 3 Nov 2026 08:12:30 +0000").
    var date: String?
    /// The connected address the message arrived at.
    var account: String?
    var reason: String?
}

// MARK: - Accounts

/// One Email tab account (email_service.py: list_accounts, create_account). The password never leaves the desktop.
nonisolated struct MailAccountDTO: Decodable, Sendable {
    var id: String
    var email: String
    var imapHost: String?
    var imapPort: Int?
    var smtpHost: String?
    var smtpPort: Int?
    var smtpSecurity: String?
    var createdAt: Double?
    var owner: String?
}

/// GET /api/email/sending-accounts: every address a bot can send from (email_send.py: accounts).
nonisolated struct MailSendingAccountsDTO: Decodable, Sendable {
    var accounts: [MailSendingAccountDTO]
    var skipped: Int
    var googleConfigured: Bool?

    enum CodingKeys: String, CodingKey {
        case accounts, googleConfigured
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([MailLossy<MailSendingAccountDTO>].self, forKey: .accounts) ?? []
        accounts = raw.compactMap(\.value)
        skipped = raw.count - accounts.count
        googleConfigured = try container.decodeIfPresent(Bool.self, forKey: .googleConfigured)
    }
}

nonisolated struct MailSendingAccountDTO: Decodable, Sendable {
    var email: String
    /// "Google" or "Email tab".
    var via: String?
    /// A Google account id, or the Email tab account id the send route takes.
    var id: String?
    var canSend: Bool?
    var note: String?
}

/// POST /api/email/accounts/{id}/test (email_service.py: test_connection).
nonisolated struct MailTestDTO: Decodable, Sendable {
    var imap: Bool?
    var smtp: Bool?
    var imapError: String?
    var smtpError: String?
}

/// `{"ok": true}`: DELETE /api/email/accounts/{id} and POST /api/email/accounts/{id}/send.
nonisolated struct MailOKDTO: Decodable, Sendable {
    var ok: Bool?
}

/// One header row of GET /api/email/accounts/{id}/messages (email_service.py: list_messages, read only).
nonisolated struct MailHeaderDTO: Decodable, Sendable {
    var uid: String?
    var from: String?
    var subject: String?
    var date: String?
    var seen: Bool?
}

// MARK: - Calls

nonisolated enum MailWire {
    /// The desktop's own limit (email_send.py: MAX_RECIPIENTS).
    static let maxRecipients = 20

    /// Request timeouts, each longer than the desktop's own wait. Email tab accounts connect with a
    /// 10 second timeout per step (email_service.py); a send is connect, log in, send and quit.
    static let sendTimeout: TimeInterval = 120
    static let testTimeout: TimeInterval = 90
    static let folderTimeout: TimeInterval = 60
    /// The one Sent folder read after a send with no answer. The whole check stops after `sentCheckLimit`.
    static let sentCheckTimeout: TimeInterval = 25
    static let sentCheckLimit: TimeInterval = 30
    /// A triage run reads every account and asks a model. The session allows 180 seconds in all.
    static let runTimeout: TimeInterval = 175
    /// After a run that did not answer, a new run waits this long: the desktop may still be on the first.
    static let runSettle: TimeInterval = 300

    /// Where this provider usually keeps sent mail, read once when a send could not be confirmed.
    /// The desktop hands the name to imaplib as written, so a name with a space carries its own IMAP quotes.
    static func sentFolder(imapHost: String) -> String {
        let host = imapHost.lowercased()
        if host.contains("gmail") || host.contains("googlemail") { return "\"[Gmail]/Sent Mail\"" }
        if host.contains("outlook") || host.contains("office365") || host.contains("hotmail") { return "\"Sent Items\"" }
        if host.contains("icloud") || host.hasSuffix(".me.com") || host.hasSuffix(".mac.com") { return "\"Sent Messages\"" }
        return "Sent"
    }

    /// The SMTP security the desktop should use for a port (email_service.py: "ssl", "starttls" or "none").
    /// 587 and 25 upgrade with STARTTLS; everything else connects over SSL. Never "none": the password must not go in the clear.
    static func smtpSecurity(port: Int) -> String {
        port == 587 || port == 25 ? "starttls" : "ssl"
    }

    /// A subject as compared with the Sent folder: folded lines and runs of spaces become one space.
    static func plainSubject(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    /// Split a To line into addresses, the way the desktop checks them (email_send.py: _addresses).
    /// Nil when one part is not an address.
    static func recipients(_ line: String) -> [String]? {
        guard !line.contains("\r"), !line.contains("\n"), !line.contains("\0") else { return nil }
        let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var found: [String] = []
        for part in parts {
            let address = parse(part).address
            guard isAddress(address) else { return nil }
            found.append(address)
        }
        return found
    }

    static func isAddress(_ text: String) -> Bool {
        text.range(of: #"^[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+$"#, options: .regularExpression) != nil
    }

    /// "Name <name@example.com>" as its name and address. A bare address is both.
    static func parse(_ header: String) -> (name: String, address: String) {
        let text = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = text.lastIndex(of: "<"), let close = text[open...].firstIndex(of: ">") {
            let address = String(text[text.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            var name = String(text[..<open]).trimmingCharacters(in: .whitespaces)
            if name.count >= 2, name.hasPrefix("\""), name.hasSuffix("\"") { name = String(name.dropFirst().dropLast()) }
            name = name.trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? address : name, address)
        }
        return (text, text.contains("@") ? text : "")
    }

    /// The Date header as a date. Nil when it is not one of the usual shapes.
    static func date(_ header: String?) -> Date? {
        guard var text = header?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let comment = text.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            text.removeSubrange(comment)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for shape in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z",
                      "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss zzz"] {
            formatter.dateFormat = shape
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// How a row shows when a message came: "8:12 AM", "Yesterday", "Mon", "Nov 3". Empty when unreadable.
    static func timeText(_ header: String?, now: Date = Date()) -> String {
        guard let date = date(header) else { return "" }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if now.timeIntervalSince(date) < 6 * 86400, date < now { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// An Email tab account id in a path. Ids are short hex (email_service.py: uuid4().hex[:12]).
    static func pathID(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
    }
}

extension APIClient {

    /// A request with its own timeout, for the routes that wait on a mail server or a model.
    private func mailCall<T: Decodable>(_ method: String, _ path: String, query: [String: String?] = [:],
                                        json: [String: Any]? = nil, timeout: TimeInterval) async throws -> T {
        var request = try urlRequest(method, path, query: query)
        request.timeoutInterval = timeout
        if let json {
            guard JSONSerialization.isValidJSONObject(json) else { throw APIError.unreadable("request") }
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data = try await send(request)
        do {
            return try KJSON.decode(T.self, from: data)
        } catch {
            throw APIError.unreadable(String(describing: error))
        }
    }

    /// GET /api/email/triage
    func mailTriage() async throws -> MailTriageDTO {
        try await get("/api/email/triage")
    }

    /// POST /api/email/triage/run: the scheduled triage, now. Reads mail read only and asks a model.
    func mailRunTriage() async throws -> MailTriageDTO {
        try await mailCall("POST", "/api/email/triage/run", json: [:], timeout: MailWire.runTimeout)
    }

    /// GET /api/email/accounts, item by item.
    func mailAccounts() async throws -> (accounts: [MailAccountDTO], skipped: Int) {
        let raw: [MailLossy<MailAccountDTO>] = try await get("/api/email/accounts")
        let accounts = raw.compactMap(\.value)
        return (accounts, raw.count - accounts.count)
    }

    /// GET /api/email/sending-accounts
    func mailSendingAccounts() async throws -> MailSendingAccountsDTO {
        try await get("/api/email/sending-accounts")
    }

    /// POST /api/email/accounts. The desktop keeps the password encrypted and never sends it back.
    func mailAddAccount(email: String, password: String, imapHost: String, imapPort: Int,
                        smtpHost: String, smtpPort: Int) async throws -> MailAccountDTO {
        try await mailCall("POST", "/api/email/accounts", json: [
            "email": email, "password": password,
            "imap_host": imapHost, "imap_port": imapPort,
            "smtp_host": smtpHost, "smtp_port": smtpPort,
            "smtp_security": MailWire.smtpSecurity(port: smtpPort),
        ], timeout: 30)
    }

    /// DELETE /api/email/accounts/{id}: the account and its saved password go. Mail itself is not touched.
    func mailRemoveAccount(_ id: String) async throws -> MailOKDTO {
        try await mailCall("DELETE", "/api/email/accounts/" + MailWire.pathID(id), timeout: 30)
    }

    /// POST /api/email/accounts/{id}/test: signs in to IMAP and SMTP, changes nothing.
    func mailTestAccount(_ id: String) async throws -> MailTestDTO {
        try await mailCall("POST", "/api/email/accounts/" + MailWire.pathID(id) + "/test", json: [:], timeout: MailWire.testTimeout)
    }

    /// GET /api/email/accounts/{id}/messages?folder=&limit= : the newest headers of one folder, read only.
    func mailFolder(_ id: String, folder: String, limit: Int,
                    timeout: TimeInterval = MailWire.folderTimeout) async throws -> [MailHeaderDTO] {
        let raw: [MailLossy<MailHeaderDTO>] = try await mailCall(
            "GET", "/api/email/accounts/" + MailWire.pathID(id) + "/messages",
            query: ["folder": folder, "limit": String(limit)], timeout: timeout)
        return raw.compactMap(\.value)
    }

    /// POST /api/email/accounts/{id}/send: one message over SMTP. Never retried.
    func mailSend(accountID: String, to: String, subject: String, body: String) async throws -> MailOKDTO {
        try await mailCall("POST", "/api/email/accounts/" + MailWire.pathID(accountID) + "/send",
                           json: ["to": to, "subject": subject, "body": body], timeout: MailWire.sendTimeout)
    }
}

// MARK: - Samples

/// A sample answer for every mail route, shaped like the desktop's own (made-up content).
nonisolated enum MailSamples {

    static let triage = #"""
    {
      "generated_at": 1793000000.25,
      "items": [
        {"from": "Parts supplier <orders@supplier.example.com>", "subject": "Invoice 1042 is due Friday",
         "date": "Tue, 3 Nov 2026 08:12:30 +0000", "account": "hello@example.com",
         "reason": "A payment is due in two days."},
        {"from": "office@building.example.com", "subject": "Heating check on Thursday",
         "date": "Tue, 3 Nov 2026 07:40:00 +0100 (CET)", "account": "hello@example.com",
         "reason": "They need a time that suits you."},
        {"from": 42, "subject": "A row the phone cannot read"}
      ],
      "scanned": 38,
      "error": null
    }
    """#

    static let triageFirst = #"{"generated_at": null, "items": [], "scanned": 0, "error": null}"#

    static let triageRun = #"""
    {"summary": "1 of 12 unread look important:\n- Study group (Notes for Monday)", "generated_at": 1793003600.0,
     "items": [{"from": "\"Study group\" <group@study.example.com>", "subject": "Notes for Monday",
                "date": "Mon, 2 Nov 2026 18:05:00 -0500", "account": "studio@example.net", "reason": "Your section is due Sunday."}],
     "scanned": 12, "error": "studio@example.net: login failed"}
    """#

    static let accounts = #"""
    [
      {"id": "a1b2c3d4e5f6", "email": "hello@example.com", "imap_host": "imap.example.com", "imap_port": 993,
       "smtp_host": "smtp.example.com", "smtp_port": 465, "smtp_security": "ssl", "created_at": 1790000000.5, "owner": "alex"},
      {"id": "0f9e8d7c6b5a", "email": "studio@example.net", "imap_host": "imap.example.net", "imap_port": "993"},
      {"id": "112233445566", "email": "shop@example.org", "imap_host": "imap.example.org", "imap_port": 993,
       "smtp_host": "smtp.example.org", "smtp_port": 587, "smtp_security": "starttls", "created_at": 1790000100, "owner": null}
    ]
    """#

    static let sending = #"""
    {"accounts": [
       {"email": "shop@example.com", "via": "Google", "id": "g_0001", "can_send": true, "note": ""},
       {"email": "you@example.com", "via": "Google", "id": "g_0002", "can_send": false, "note": "reconnect it in Library to allow sending"},
       {"email": "hello@example.com", "via": "Email tab", "id": "a1b2c3d4e5f6", "can_send": true, "note": ""},
       {"via": "Email tab"}
     ],
     "google_configured": true}
    """#

    static let created = #"""
    {"id": "778899aabbcc", "email": "new@example.com", "imap_host": "imap.example.com", "imap_port": 993,
     "smtp_host": "smtp.example.com", "smtp_port": 465, "smtp_security": "ssl", "created_at": 1793000500.0, "owner": "alex"}
    """#

    static let test = #"{"imap": true, "smtp": false, "imap_error": null, "smtp_error": "authentication failed"}"#

    static let ok = #"{"ok": true}"#

    static let smtpError = #"{"detail": "SMTP error: connection closed"}"#

    static let folder = #"""
    [{"uid": "812", "from": "hello@example.com", "subject": "Re: Invoice 1042 is due Friday", "date": "Tue, 3 Nov 2026 09:30:00 +0000", "seen": true},
     {"uid": 811, "subject": "Bad uid type"}]
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("mail.triage") {
            let read = try KJSON.decode(MailTriageDTO.self, from: MailSamples.triage)
            let first = try KJSON.decode(MailTriageDTO.self, from: MailSamples.triageFirst)
            guard read.items.count == 2, read.skipped == 1, read.scanned == 38, read.generatedAt != nil,
                  first.generatedAt == nil, first.items.isEmpty else { throw SampleMismatch("triage fields") }
            let named = MailWire.parse(read.items[0].from ?? "")
            let bare = MailWire.parse(read.items[1].from ?? "")
            guard named.name == "Parts supplier", named.address == "orders@supplier.example.com",
                  bare.address == "office@building.example.com",
                  MailWire.date(read.items[0].date) != nil, MailWire.date(read.items[1].date) != nil else {
                throw SampleMismatch("from or date")
            }
            return "2 items, 1 skipped, names and dates"
        },
        DecodeCheck("mail.triage.run") {
            let ran = try KJSON.decode(MailTriageDTO.self, from: MailSamples.triageRun)
            guard ran.summary?.isEmpty == false, ran.items.count == 1, ran.error != nil,
                  MailWire.parse(ran.items[0].from ?? "").name == "Study group" else { throw SampleMismatch("run fields") }
            return "summary, quoted name, error"
        },
        DecodeCheck("mail.accounts") {
            let raw = try KJSON.decode([MailLossy<MailAccountDTO>].self, from: MailSamples.accounts)
            let accounts = raw.compactMap(\.value)
            let made = try KJSON.decode(MailAccountDTO.self, from: MailSamples.created)
            guard accounts.count == 2, raw.count == 3, accounts[0].imapPort == 993, accounts[1].owner == nil,
                  made.id == "778899aabbcc" else { throw SampleMismatch("account fields") }
            return "2 accounts, 1 skipped, created"
        },
        DecodeCheck("mail.sending") {
            let read = try KJSON.decode(MailSendingAccountsDTO.self, from: MailSamples.sending)
            guard read.accounts.count == 3, read.skipped == 1, read.googleConfigured == true,
                  read.accounts[1].canSend == false, read.accounts[2].via == "Email tab" else { throw SampleMismatch("sending fields") }
            return "3 senders, 1 skipped"
        },
        DecodeCheck("mail.writes") {
            let tested = try KJSON.decode(MailTestDTO.self, from: MailSamples.test)
            let done = try KJSON.decode(MailOKDTO.self, from: MailSamples.ok)
            let refused = try KJSON.decode(APIErrorBody.self, from: MailSamples.smtpError)
            let sent = try KJSON.decode([MailLossy<MailHeaderDTO>].self, from: MailSamples.folder).compactMap(\.value)
            guard tested.imap == true, tested.smtp == false, tested.smtpError != nil, done.ok == true,
                  refused.text.hasPrefix("SMTP error"), sent.count == 1 else { throw SampleMismatch("write fields") }
            return "test, ok, SMTP error, Sent headers"
        },
        DecodeCheck("mail.addresses") {
            guard MailWire.recipients("a@example.com, Name <b@example.org>") == ["a@example.com", "b@example.org"],
                  MailWire.recipients("not an address") == nil,
                  MailWire.recipients("a@example.com\r\nBcc: c@example.com") == nil,
                  MailWire.recipients("") == [] else { throw SampleMismatch("recipients") }
            guard MailWire.smtpSecurity(port: 587) == "starttls", MailWire.smtpSecurity(port: 465) == "ssl",
                  MailWire.plainSubject("Re: A long\r\n subject") == "re: a long subject" else { throw SampleMismatch("security or subject") }
            return "split, refuse, header break, security, subject"
        },
    ]
}
