import Foundation

// The desktop's Google Drive, Sheets and Forms routes (routes/google_routes.py over core/google_workspace.py),
// as the phone reads them: one decoder per answer and one function per route.
//
// - Every Drive, Sheets and Forms route takes `account`, the opaque Google account id from GET /api/google/status.
//   The phone always sends it, so a file is only ever read or changed with the account it was listed under.
// - Google's own answers (files, permissions, revisions, sheets, forms) come through as Google sent them, in
//   camelCase, and are decoded WITHOUT the snake_case conversion. The status answer is the desktop's own, in
//   snake_case, and uses the shared decoder.
// - A Google refusal the desktop passes on keeps its status: 401 "Google authorization expired; reconnect the
//   account" is NOT this phone's pairing failing. Only a 401 saying "authentication required" (or saying nothing)
//   is the phone's token being refused, so these calls read the status themselves (driveData).
// - There is no revision or version on any Drive, Sheets or Forms write. Sheets writes go one cell at a time and
//   Forms writes one item at a time; nothing whole is ever sent back.

// MARK: - Accounts

/// GET /api/google/status (google_workspace.status). Never a token.
nonisolated struct DriveDTOStatus: Decodable, Sendable {
    var configured: Bool?
    var connected: Bool?
    var email: String?
    var accounts: DriveDTOList<DriveDTOAccount>?
    /// The account the person's Drive opens on.
    var defaultAccount: String?
}

/// One of `accounts` (google_workspace._public).
nonisolated struct DriveDTOAccount: Decodable, Sendable {
    var id: String
    var email: String?
    var `default`: Bool?
    /// "Google sign-in expired or was revoked. Reconnect this account." or null.
    var error: String?
    var canSendEmail: Bool?
}

/// A list read item by item: an item of the wrong shape is left out and counted, never the whole list.
nonisolated struct DriveDTOList<Element: Decodable>: Decodable {
    var items: [Element] = []
    var skipped = 0

    init(items: [Element]) { self.items = items }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) {
                items.append(item)
            } else {
                // A failed decode does not move past the element; read it as anything to step over it.
                _ = try container.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

// MARK: - Files

/// GET /api/google/drive/files: Google's files.list with FILE_FIELDS.
nonisolated struct DriveDTOFileList: Decodable, Sendable {
    var files: DriveDTOList<DriveDTOFile>?
    var nextPageToken: String?
    var incompleteSearch: Bool?
}

/// One Google file (FILE_FIELDS). `size` is text in Google's answers.
nonisolated struct DriveDTOFile: Decodable, Sendable {
    var id: String
    var name: String?
    var mimeType: String?
    var size: JSONValue?
    var parents: [String]?
    var modifiedTime: String?
    var webViewLink: String?
    var starred: Bool?
    var trashed: Bool?
    var shared: Bool?
    var owners: [DriveDTOUser]?
    var capabilities: JSONValue?
}

nonisolated struct DriveDTOUser: Decodable, Sendable {
    var displayName: String?
    var emailAddress: String?
    var me: Bool?
}

/// GET /api/google/drive/storage: Google's about.storageQuota. Numbers are text; `limit` is missing on unlimited plans.
nonisolated struct DriveDTOStorage: Decodable, Sendable {
    var storageQuota: DriveDTOQuota?
}

nonisolated struct DriveDTOQuota: Decodable, Sendable {
    var limit: JSONValue?
    var usage: JSONValue?
}

/// POST /api/google/drive/action "revisions".
nonisolated struct DriveDTORevisions: Decodable, Sendable {
    var revisions: DriveDTOList<DriveDTORevision>?
}

nonisolated struct DriveDTORevision: Decodable, Sendable {
    var id: String?
    var modifiedTime: String?
    var lastModifyingUser: DriveDTOUser?
}

/// POST /api/google/drive/action "permissions".
nonisolated struct DriveDTOPermissions: Decodable, Sendable {
    var permissions: DriveDTOList<DriveDTOPermission>?
}

/// One permission. `type` is user, group, domain or anyone; `role` is owner, organizer, fileOrganizer,
/// writer, commenter or reader.
nonisolated struct DriveDTOPermission: Decodable, Sendable {
    var id: String
    var type: String?
    var role: String?
    var emailAddress: String?
    var displayName: String?
    var domain: String?
}

/// What a Drive write answers: the file's id, name and state (rename, move, copy, trash, restore, star,
/// create_folder, upload). Only the fields the action asked for are there.
nonisolated struct DriveDTOChanged: Decodable, Sendable {
    var id: String?
    var name: String?
    var mimeType: String?
    var parents: [String]?
    var trashed: Bool?
    var starred: Bool?
    var webViewLink: String?
}

// MARK: - Sheets

/// GET /api/google/sheets/{id}: the spreadsheet's tabs.
nonisolated struct DriveDTOSheetMeta: Decodable, Sendable {
    var spreadsheetId: String?
    var properties: DriveDTOTitle?
    var sheets: DriveDTOList<DriveDTOSheetTab>?
}

nonisolated struct DriveDTOTitle: Decodable, Sendable {
    var title: String?
}

nonisolated struct DriveDTOSheetTab: Decodable, Sendable {
    var properties: DriveDTOSheetTabProperties?
}

nonisolated struct DriveDTOSheetTabProperties: Decodable, Sendable {
    var sheetId: Int?
    var title: String?
    var index: Int?
}

/// GET /api/google/sheets/{id}?cell_range= : formatted values, rows of cells. Trailing empty rows and cells are left out.
nonisolated struct DriveDTOSheetValues: Decodable, Sendable {
    var range: String?
    var values: [[JSONValue]]?
}

/// POST /api/google/sheets/action "create": the new spreadsheet.
nonisolated struct DriveDTOSheetMade: Decodable, Sendable {
    var spreadsheetId: String?
}

// MARK: - Forms

/// GET /api/google/forms/{id}: Google's form.
nonisolated struct DriveDTOForm: Decodable, Sendable {
    var formId: String?
    var info: DriveDTOFormInfo?
    var items: DriveDTOList<DriveDTOFormItem>?
    var publishSettings: DriveDTOPublishSettings?
}

nonisolated struct DriveDTOFormInfo: Decodable, Sendable {
    var title: String?
    var documentTitle: String?
}

/// One form item. Only question items carry `questionItem`; a section, picture or grid has its own kind.
nonisolated struct DriveDTOFormItem: Decodable, Sendable {
    var itemId: String?
    var title: String?
    var questionItem: DriveDTOQuestionItem?
}

nonisolated struct DriveDTOQuestionItem: Decodable, Sendable {
    var question: DriveDTOQuestion?
}

nonisolated struct DriveDTOQuestion: Decodable, Sendable {
    var questionId: String?
    var choiceQuestion: DriveDTOChoice?
    var textQuestion: DriveDTOText?
}

nonisolated struct DriveDTOChoice: Decodable, Sendable {
    /// RADIO, CHECKBOX or DROP_DOWN.
    var type: String?
    var options: [DriveDTOOption]?
}

nonisolated struct DriveDTOOption: Decodable, Sendable {
    var value: String?
}

nonisolated struct DriveDTOText: Decodable, Sendable {
    var paragraph: Bool?
}

nonisolated struct DriveDTOPublishSettings: Decodable, Sendable {
    var publishState: DriveDTOPublishState?
}

nonisolated struct DriveDTOPublishState: Decodable, Sendable {
    var isPublished: Bool?
    var isAcceptingResponses: Bool?
}

/// GET /api/google/forms/{id}?responses=true
nonisolated struct DriveDTOFormResponses: Decodable, Sendable {
    var responses: DriveDTOList<DriveDTOFormResponse>?
    var nextPageToken: String?
}

nonisolated struct DriveDTOFormResponse: Decodable, Sendable {
    var responseId: String?
    var lastSubmittedTime: String?
    /// Question id to {questionId, textAnswers: {answers: [{value}]}}.
    var answers: [String: JSONValue]?
}

/// POST /api/google/forms/action "create": the new form.
nonisolated struct DriveDTOFormMade: Decodable, Sendable {
    var formId: String?
}

// MARK: - Wire helpers

nonisolated enum DriveWire {
    static let folderMime = "application/vnd.google-apps.folder"
    /// Kairos's limit on one file sent through the desktop (google_workspace.MAX_DOWNLOAD).
    static let maxUpload = 25 * 1024 * 1024

    /// One session for these calls. Google writes can take long on the desktop (a 45 s wait for Google after a
    /// token refresh of up to 30 s, tried twice), so the phone waits longer than that.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 170
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    /// The phone's own token refused (the desktop's middleware says this). Anything else on a 401 is Google's.
    static let pairingRefused = "authentication required"

    /// Google's answers keep their own key names.
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.unreadable(String(describing: error))
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, text: String) throws -> T {
        try decode(type, Data(text.utf8))
    }

    /// A number Google sends as text ("1048576") or as a number.
    static func int64(_ value: JSONValue?) -> Int64? {
        guard let value else { return nil }
        if let text = value.string { return Int64(text) }
        if let number = value.double { return Int64(number) }
        return nil
    }

    static func time(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return FlexibleDate.parse(text)
    }

    /// A Google file id the desktop accepts (google_workspace._id), or "root".
    static func isGoogleID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 256
            && id.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "_" }
    }

    /// The name the desktop gives an upload: the multipart filename, with quotes and line breaks taken out.
    static func uploadName(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }

    /// The multipart body for POST /api/google/drive/upload, with the file read here. Call it off the main actor.
    /// At most `maxUpload + 1` bytes are read, so a file that grew past the cap is refused without reading it whole.
    static func uploadBody(_ item: DriveUploadItem, parent: String?, boundary: String) throws -> Data {
        if let parent, !isGoogleID(parent) { throw APIError.unreadable("file id") }
        let scoped = item.url.startAccessingSecurityScopedResource()
        defer { if scoped { item.url.stopAccessingSecurityScopedResource() } }
        var read: Result<Data, DriveUploadProblem> = .failure(.unreadable)
        var coordination: NSError?
        NSFileCoordinator().coordinate(readingItemAt: item.url, options: [.withoutChanges], error: &coordination) { url in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? handle.close() }
            let chunk: Data
            do { chunk = try handle.read(upToCount: maxUpload + 1) ?? Data() } catch { return }
            read = chunk.count > maxUpload ? .failure(.tooBig) : .success(chunk)
        }
        let data = try read.get()
        var body = Data()
        body.reserveCapacity(data.count + 1024)
        if let parent {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"parent\"\r\n\r\n\(parent)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(uploadName(item.name))\"\r\n".utf8))
        body.append(Data("Content-Type: \(item.mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    /// A cell range on one tab, as the desktop's own page writes it: 'Tab name'!A1:F12.
    static func cellRange(tab: String, _ cells: String) -> String {
        "'" + tab.replacingOccurrences(of: "'", with: "''") + "'!" + cells
    }

    /// A Google link that may be opened in the browser: https on a Google host. Anything else is not offered.
    static func googleLink(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), host == "google.com" || host.hasSuffix(".google.com") else { return nil }
        return url
    }

    /// The text of a form answer: every text answer's value, joined.
    static func answerText(_ value: JSONValue) -> String {
        let answers = value["textAnswers"]?["answers"]?.array ?? []
        return answers.compactMap { $0["value"]?.string }.joined(separator: ", ")
    }

    /// The readable text of an HTML preview (a Google Doc as sanitized HTML): block ends become line breaks,
    /// tags go, and the common entities are read. Nothing is fetched.
    static func plainText(html: String) -> String {
        var text = html
        if let body = text.range(of: "<body", options: .caseInsensitive) { text = String(text[body.lowerBound...]) }
        for pattern in ["<style[^>]*>[\\s\\S]*?</style>", "<script[^>]*>[\\s\\S]*?</script>", "<head[^>]*>[\\s\\S]*?</head>"] {
            text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</(p|div|h[1-6]|li|tr|table|ul|ol)>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</t[dh]>", with: "  ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&amp;": "&"]
        for (entity, plain) in entities { text = text.replacingOccurrences(of: entity, with: plain) }
        text = text.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One picked file to upload: where it is and what its attributes said, checked before anything is read.
nonisolated struct DriveUploadItem: Hashable, Sendable {
    var url: URL
    var name: String
    var size: Int
    var mimeType: String
}

/// Why a picked file could not be read for an upload.
nonisolated enum DriveUploadProblem: Error, Sendable {
    case tooBig, unreadable
}

/// A file's bytes for the preview, with the type the desktop said it is.
nonisolated struct DrivePreviewBytes: Sendable {
    var data: Data
    var mime: String
}

/// Watches an upload's progress and reports it as a fraction from 0 to 1.
nonisolated final class DriveUploadWatch: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let report: @Sendable (Double) -> Void

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}

// MARK: - Calls

extension APIClient {

    /// Send and read the status. A Google refusal keeps its own status and sentence; only the desktop refusing
    /// this phone's token is `.unauthorized`.
    func driveData(_ request: URLRequest, upload: Data? = nil, watch: DriveUploadWatch? = nil) async throws -> Data {
        let answer: (Data, URLResponse)
        do {
            if let upload {
                answer = try await DriveWire.session.upload(for: request, from: upload, delegate: watch)
            } else {
                answer = try await DriveWire.session.data(for: request)
            }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError.from(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.offline("Your desktop could not be reached. Try again in a moment.")
        }
        if let http = answer.1 as? HTTPURLResponse, http.statusCode == 401 {
            let detail = (try? KJSON.decode(APIErrorBody.self, from: answer.0))?.text ?? ""
            if !detail.isEmpty && detail != DriveWire.pairingRefused {
                throw APIError.server(status: 401, detail: detail)
            }
        }
        try APIClient.check(answer.1, body: answer.0)
        return answer.0
    }

    private func driveGet(_ path: String, _ query: [String: String?]) async throws -> Data {
        try await driveData(urlRequest("GET", path, query: query))
    }

    private func drivePost(_ path: String, account: String, json: [String: Any]) async throws -> Data {
        guard JSONSerialization.isValidJSONObject(json) else { throw APIError.unreadable("request") }
        var request = try urlRequest("POST", path, query: ["account": account])
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await driveData(request)
    }

    /// A Google file id goes into the path as it is. One the desktop would refuse is refused here first.
    private static func driveID(_ id: String) throws -> String {
        guard DriveWire.isGoogleID(id) else { throw APIError.unreadable("file id") }
        return id
    }

    /// GET /api/google/status
    func driveStatus() async throws -> DriveDTOStatus {
        let data = try await driveGet("/api/google/status", [:])
        do {
            return try KJSON.decode(DriveDTOStatus.self, from: data)
        } catch {
            throw APIError.unreadable(String(describing: error))
        }
    }

    /// GET /api/google/drive/files. `section` is all, my_drive, shared, starred, recent or trash;
    /// `kind` is all, folder, sheet or form.
    func driveFiles(account: String, section: String, parent: String?, query: String, kind: String,
                    pageToken: String?) async throws -> DriveDTOFileList {
        var params: [String: String?] = ["account": account, "section": section, "kind": kind, "q": query]
        if let parent { params["parent"] = try Self.driveID(parent) }
        if let pageToken { params["page_token"] = pageToken }
        return try DriveWire.decode(DriveDTOFileList.self, try await driveGet("/api/google/drive/files", params))
    }

    /// GET /api/google/drive/storage
    func driveStorage(account: String) async throws -> DriveDTOStorage {
        try DriveWire.decode(DriveDTOStorage.self, try await driveGet("/api/google/drive/storage", ["account": account]))
    }

    /// GET /api/google/drive/files/{id}
    func driveFile(account: String, id: String) async throws -> DriveDTOFile {
        let path = "/api/google/drive/files/" + (try Self.driveID(id))
        return try DriveWire.decode(DriveDTOFile.self, try await driveGet(path, ["account": account]))
    }

    /// GET /api/google/drive/files/{id}/preview: html (a Doc), pdf (Slides, a PDF), an image, or text.
    /// 415 for a kind that cannot be previewed.
    func drivePreview(account: String, id: String) async throws -> DrivePreviewBytes {
        var request = try urlRequest("GET", "/api/google/drive/files/" + (try Self.driveID(id)) + "/preview", query: ["account": account])
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, mime) = try await driveBytes(request)
        return DrivePreviewBytes(data: data, mime: mime)
    }

    private func driveBytes(_ request: URLRequest) async throws -> (Data, String) {
        let answer: (Data, URLResponse)
        do {
            answer = try await DriveWire.session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError.from(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.offline("Your desktop could not be reached. Try again in a moment.")
        }
        if let http = answer.1 as? HTTPURLResponse, http.statusCode == 401 {
            let detail = (try? KJSON.decode(APIErrorBody.self, from: answer.0))?.text ?? ""
            if !detail.isEmpty && detail != DriveWire.pairingRefused { throw APIError.server(status: 401, detail: detail) }
        }
        try APIClient.check(answer.1, body: answer.0)
        let mime = (answer.1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        return (answer.0, mime.lowercased())
    }

    /// POST /api/google/drive/action. Sent once. Only the status matters to the caller unless it reads the answer.
    @discardableResult
    func driveAction(account: String, _ body: [String: Any]) async throws -> Data {
        var checked = body
        if let id = body["file_id"] as? String { checked["file_id"] = try Self.driveID(id) }
        if let parent = body["parent"] as? String, parent != "root" { checked["parent"] = try Self.driveID(parent) }
        return try await drivePost("/api/google/drive/action", account: account, json: checked)
    }

    func driveRevisions(account: String, id: String) async throws -> DriveDTORevisions {
        try DriveWire.decode(DriveDTORevisions.self, try await driveAction(account: account, ["action": "revisions", "file_id": id]))
    }

    func drivePermissions(account: String, id: String) async throws -> DriveDTOPermissions {
        try DriveWire.decode(DriveDTOPermissions.self, try await driveAction(account: account, ["action": "permissions", "file_id": id]))
    }

    /// POST /api/google/drive/upload: one file, into `parent` (nil for My Drive), with progress. The file is read
    /// and the body built off the main actor, just before it is sent; nothing is kept after.
    /// Answers the new file's id when the desktop's answer says it.
    func driveUpload(account: String, item: DriveUploadItem, parent: String?, watch: DriveUploadWatch) async throws -> String? {
        var request = try urlRequest("POST", "/api/google/drive/upload", query: ["account": account])
        let boundary = "kairos-" + UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = try await Task.detached(priority: .userInitiated) {
            try DriveWire.uploadBody(item, parent: parent, boundary: boundary)
        }.value
        let answer = try await driveData(request, upload: body, watch: watch)
        return (try? DriveWire.decode(DriveDTOChanged.self, answer))?.id
    }

    /// GET /api/google/sheets/{id}
    func driveSheetMeta(account: String, id: String) async throws -> DriveDTOSheetMeta {
        let path = "/api/google/sheets/" + (try Self.driveID(id))
        return try DriveWire.decode(DriveDTOSheetMeta.self, try await driveGet(path, ["account": account]))
    }

    /// GET /api/google/sheets/{id}?cell_range=
    func driveSheetValues(account: String, id: String, range: String) async throws -> DriveDTOSheetValues {
        let path = "/api/google/sheets/" + (try Self.driveID(id))
        return try DriveWire.decode(DriveDTOSheetValues.self, try await driveGet(path, ["account": account, "cell_range": range]))
    }

    /// POST /api/google/sheets/action "update" for ONE cell. Never a block of cells: that could overwrite
    /// cells someone else changed since the phone read them.
    func driveSheetSetCell(account: String, id: String, cell: String, value: String) async throws {
        _ = try await drivePost("/api/google/sheets/action", account: account, json: [
            "action": "update", "file_id": try Self.driveID(id), "cell_range": cell, "values": [[value]],
        ])
    }

    /// POST /api/google/sheets/action "create": a blank spreadsheet in My Drive.
    func driveSheetCreate(account: String, title: String) async throws -> DriveDTOSheetMade {
        try DriveWire.decode(DriveDTOSheetMade.self, try await drivePost("/api/google/sheets/action", account: account,
                                                                        json: ["action": "create", "title": title]))
    }

    /// GET /api/google/forms/{id}
    func driveForm(account: String, id: String) async throws -> DriveDTOForm {
        let path = "/api/google/forms/" + (try Self.driveID(id))
        return try DriveWire.decode(DriveDTOForm.self, try await driveGet(path, ["account": account]))
    }

    /// GET /api/google/forms/{id}?responses=true
    func driveFormResponses(account: String, id: String, pageToken: String? = nil) async throws -> DriveDTOFormResponses {
        let path = "/api/google/forms/" + (try Self.driveID(id))
        var params: [String: String?] = ["account": account, "responses": "true"]
        if let pageToken { params["page_token"] = pageToken }
        return try DriveWire.decode(DriveDTOFormResponses.self, try await driveGet(path, params))
    }

    /// POST /api/google/forms/action "batch" with exactly ONE request (one item, or the title).
    func driveFormChange(account: String, id: String, _ request: [String: Any]) async throws {
        _ = try await drivePost("/api/google/forms/action", account: account, json: [
            "action": "batch", "file_id": try Self.driveID(id), "requests": [request],
        ])
    }

    /// POST /api/google/forms/action "publish"
    func driveFormPublish(account: String, id: String, published: Bool) async throws {
        _ = try await drivePost("/api/google/forms/action", account: account, json: [
            "action": "publish", "file_id": try Self.driveID(id), "published": published,
        ])
    }

    /// POST /api/google/forms/action "create": a form in My Drive.
    func driveFormCreate(account: String, title: String) async throws -> DriveDTOFormMade {
        try DriveWire.decode(DriveDTOFormMade.self, try await drivePost("/api/google/forms/action", account: account,
                                                                       json: ["action": "create", "title": title]))
    }
}

// MARK: - Samples

/// A sample answer for every Drive, Sheets and Forms route the phone reads, shaped like the desktop's and
/// Google's own (made-up content).
nonisolated enum DriveAPISamples {

    static let status = #"""
    {"configured": true, "connected": true, "email": "shop@example.com", "client_id": "",
     "granted_scopes": [], "calendar_connected": true, "calendar_ids": null, "calendar_account": "acct_a1",
     "accounts": [
       {"id": "acct_a1", "email": "shop@example.com", "default": true, "error": null, "can_send_email": true, "calendar_connected": true},
       {"id": "acct_b2", "email": "books@example.com", "default": false,
        "error": "Google sign-in expired or was revoked. Reconnect this account.", "can_send_email": false, "calendar_connected": false},
       {"email": "an account with no id"}
     ],
     "default_account": "acct_a1", "active_account": "acct_a1"}
    """#

    static let files = #"""
    {"files": [
      {"id": "1FoLdEr_abc", "name": "Bike shop", "mimeType": "application/vnd.google-apps.folder", "parents": ["0RooT"],
       "modifiedTime": "2027-01-04T10:00:00.000Z", "webViewLink": "https://drive.google.com/drive/folders/1FoLdEr_abc",
       "starred": true, "trashed": false, "shared": false, "owners": [{"displayName": "Shop", "emailAddress": "shop@example.com", "me": true}]},
      {"id": "1ShEeT-xyz", "name": "Inventory", "mimeType": "application/vnd.google-apps.spreadsheet", "parents": ["1FoLdEr_abc"],
       "modifiedTime": "2027-01-04T09:30:00Z", "webViewLink": "https://docs.google.com/spreadsheets/d/1ShEeT-xyz/edit",
       "starred": false, "trashed": false, "capabilities": {"canEdit": true}},
      {"id": "1PdF", "name": "Q3 summary.pdf", "mimeType": "application/pdf", "size": "1480000",
       "modifiedTime": "2026-12-20T08:00:00.000Z", "webViewLink": "https://evil.example.com/file", "trashed": false},
      {"name": "A file with no id"}
     ],
     "nextPageToken": "page-2", "incompleteSearch": false}
    """#

    static let storage = #"{"storageQuota": {"limit": "16106127360", "usage": "6657199308", "usageInDrive": "6000000000"}}"#

    static let unlimited = #"{"storageQuota": {"usage": "1073741824"}}"#

    static let revisions = #"""
    {"revisions": [{"id": "1", "modifiedTime": "2027-01-02T08:00:00.000Z", "keepForever": false,
                    "lastModifyingUser": {"displayName": "Shop", "emailAddress": "shop@example.com"}},
                   {"id": "2", "modifiedTime": "2027-01-04T09:30:00.000Z"}]}
    """#

    static let permissions = #"""
    {"permissions": [
      {"id": "0123", "type": "user", "role": "owner", "emailAddress": "shop@example.com", "displayName": "Shop"},
      {"id": "4567", "type": "user", "role": "writer", "emailAddress": "mechanic@example.com"},
      {"id": "anyoneWithLink", "type": "anyone", "role": "reader"},
      {"id": "8901", "type": "domain", "role": "commenter", "domain": "example.com"},
      {"type": "user", "role": "reader"}
    ]}
    """#

    static let changed = #"""
    {"id": "1ShEeT-xyz", "name": "Inventory 2027", "mimeType": "application/vnd.google-apps.spreadsheet",
     "parents": ["1FoLdEr_abc"], "trashed": false, "starred": true, "webViewLink": "https://docs.google.com/spreadsheets/d/1ShEeT-xyz/edit"}
    """#

    static let googleExpired = #"{"detail": "Google authorization expired; reconnect the account"}"#

    static let sheetMeta = #"""
    {"spreadsheetId": "1ShEeT-xyz", "spreadsheetUrl": "https://docs.google.com/spreadsheets/d/1ShEeT-xyz/edit",
     "properties": {"title": "Inventory"},
     "sheets": [{"properties": {"sheetId": 0, "title": "Bikes", "index": 0, "gridProperties": {"rowCount": 1000, "columnCount": 26}}},
                {"properties": {"sheetId": 7, "title": "Parts' list", "index": 1}}]}
    """#

    static let sheetValues = #"""
    {"range": "'Bikes'!A1:F12", "majorDimension": "ROWS",
     "values": [["Model", "Size", "Stock"], ["City commuter", "M", "4"], [], ["Kids 20 inch", "S", 6]]}
    """#

    static let sheetMade = #"{"spreadsheetId": "1NeW-sheet", "properties": {"title": "Rota"}, "sheets": []}"#

    static let form = #"""
    {"formId": "1FoRm", "info": {"title": "Customer survey", "documentTitle": "Customer survey"},
     "revisionId": "00000042", "responderUri": "https://docs.google.com/forms/d/e/x/viewform",
     "items": [
       {"itemId": "a1b2", "title": "How did you hear about us?",
        "questionItem": {"question": {"questionId": "q1", "required": false,
          "choiceQuestion": {"type": "RADIO", "options": [{"value": "A friend"}, {"value": "Online"}]}}}},
       {"itemId": "c3d4", "title": "Anything we could do better?",
        "questionItem": {"question": {"questionId": "q2", "textQuestion": {"paragraph": true}}}},
       {"itemId": "e5f6", "title": "About your visit", "pageBreakItem": {}}
     ],
     "publishSettings": {"publishState": {"isPublished": true, "isAcceptingResponses": true}}}
    """#

    static let responses = #"""
    {"responses": [{"responseId": "r1", "lastSubmittedTime": "2027-01-03T10:00:00Z",
                    "answers": {"q1": {"questionId": "q1", "textAnswers": {"answers": [{"value": "Online"}]}},
                                "q2": {"questionId": "q2", "textAnswers": {"answers": [{"value": "Open earlier"}]}}}}],
     "nextPageToken": "responses-2"}
    """#

    static let formMade = #"{"formId": "1NeW-form", "info": {"title": "Event sign-up"}}"#

    static let checks: [DecodeCheck] = [
        DecodeCheck("drive.status") {
            let status = try KJSON.decode(DriveDTOStatus.self, from: DriveAPISamples.status)
            let accounts = status.accounts?.items ?? []
            guard accounts.count == 2, status.accounts?.skipped == 1, status.defaultAccount == "acct_a1",
                  accounts[0].canSendEmail == true, accounts[0].default == true,
                  accounts[1].error?.isEmpty == false else { throw SampleMismatch("status accounts") }
            let mapped = DriveStore.liveAccounts(status)
            guard mapped.count == 2, mapped[1].broken, !mapped[0].broken else { throw SampleMismatch("accounts mapped") }
            return "2 accounts, 1 skipped, broken flag"
        },
        DecodeCheck("drive.files") {
            let list = try DriveWire.decode(DriveDTOFileList.self, text: DriveAPISamples.files)
            let files = (list.files?.items ?? []).map { DriveStore.liveFile($0, account: "acct_a1") }
            guard files.count == 3, list.files?.skipped == 1, list.nextPageToken == "page-2",
                  files[0].kind == .folder, files[0].starred, files[1].kind == .sheet,
                  files[1].parentRemote == "1FoLdEr_abc", files[2].kind == .pdf, files[2].size == 1_480_000,
                  files[1].id != files[1].remoteID, files[1].account == "acct_a1",
                  DriveWire.googleLink(files[1].webLink) != nil, DriveWire.googleLink(files[2].webLink) == nil
            else { throw SampleMismatch("file fields") }
            return "3 files, kinds, sizes, links checked"
        },
        DecodeCheck("drive.storage") {
            let some = try DriveWire.decode(DriveDTOStorage.self, text: DriveAPISamples.storage)
            let open = try DriveWire.decode(DriveDTOStorage.self, text: DriveAPISamples.unlimited)
            guard DriveWire.int64(some.storageQuota?.limit) == 16_106_127_360,
                  DriveWire.int64(some.storageQuota?.usage) == 6_657_199_308,
                  open.storageQuota?.limit == nil, DriveWire.int64(open.storageQuota?.usage) == 1_073_741_824
            else { throw SampleMismatch("quota") }
            return "limit and unlimited"
        },
        DecodeCheck("drive.details") {
            let revisions = try DriveWire.decode(DriveDTORevisions.self, text: DriveAPISamples.revisions)
            let people = try DriveWire.decode(DriveDTOPermissions.self, text: DriveAPISamples.permissions)
            let members = (people.permissions?.items ?? []).map(DriveStore.liveMember)
            let changed = try DriveWire.decode(DriveDTOChanged.self, text: DriveAPISamples.changed)
            guard revisions.revisions?.items.count == 2, DriveWire.time(revisions.revisions?.items.first?.modifiedTime) != nil,
                  members.count == 4, people.permissions?.skipped == 1,
                  members[0].access == .owner, members[1].access == .editor, members[2].audience == .anyone,
                  members[3].audience == .domain, members[3].address == "example.com",
                  changed.starred == true, changed.name == "Inventory 2027" else { throw SampleMismatch("details") }
            let refused = try KJSON.decode(APIErrorBody.self, from: DriveAPISamples.googleExpired)
            guard refused.text != DriveWire.pairingRefused, !refused.text.isEmpty else { throw SampleMismatch("google 401") }
            return "revisions, 4 people, Google's 401 kept apart"
        },
        DecodeCheck("drive.sheets") {
            let meta = try DriveWire.decode(DriveDTOSheetMeta.self, text: DriveAPISamples.sheetMeta)
            let values = try DriveWire.decode(DriveDTOSheetValues.self, text: DriveAPISamples.sheetValues)
            let made = try DriveWire.decode(DriveDTOSheetMade.self, text: DriveAPISamples.sheetMade)
            let grid = DriveStore.liveGrid(values, rows: 4, columns: 3)
            guard meta.sheets?.items.count == 2, meta.sheets?.items[1].properties?.title == "Parts' list",
                  DriveWire.cellRange(tab: "Parts' list", "B3") == "'Parts'' list'!B3",
                  grid.count == 4, grid[0][0] == "Model", grid[2][1] == "", grid[3][2] == "6",
                  made.spreadsheetId == "1NeW-sheet" else { throw SampleMismatch("sheet fields") }
            return "tabs, quoted range, padded grid"
        },
        DecodeCheck("drive.forms") {
            let form = try DriveWire.decode(DriveDTOForm.self, text: DriveAPISamples.form)
            let mapped = DriveStore.liveForm(form)
            let answers = try DriveWire.decode(DriveDTOFormResponses.self, text: DriveAPISamples.responses)
            let lines = DriveStore.liveResponses(answers, form: form)
            let made = try DriveWire.decode(DriveDTOFormMade.self, text: DriveAPISamples.formMade)
            guard mapped.title == "Customer survey", mapped.published, mapped.questions.count == 3,
                  mapped.questions[0].type == .choice, mapped.questions[0].choices == ["A friend", "Online"],
                  mapped.questions[1].type == .paragraph, mapped.questions[2].label != nil,
                  mapped.questions[0].remoteID == "a1b2",
                  lines == ["Online · Open earlier"], answers.nextPageToken == "responses-2",
                  made.formId == "1NeW-form" else { throw SampleMismatch("form fields") }
            return "3 items, one not a question, responses"
        },
        DecodeCheck("drive.preview") {
            let text = DriveWire.plainText(html: "<html><head><style>p{}</style></head><body><h1>Report</h1><p>Due &amp; ready</p><ul><li>One</li></ul></body></html>")
            guard text == "Report\nDue & ready\n• One" else { throw SampleMismatch("html text: \(text)") }
            return "html read as text"
        },
        DecodeCheck("drive.upload") {
            let made = try DriveWire.decode(DriveDTOChanged.self, text: #"{"id": "1UpLoAd", "name": "Price list.pdf", "mimeType": "application/pdf"}"#)
            guard made.id == "1UpLoAd", DriveWire.isGoogleID("root"), DriveWire.isGoogleID("1FoLdEr_abc"),
                  !DriveWire.isGoogleID("a/b"), !DriveWire.isGoogleID(""),
                  DriveWire.uploadName("Say \"hi\"\r\n.txt") == "Say hi.txt" else { throw SampleMismatch("upload") }
            return "upload answer id, ids, names"
        },
    ]
}
