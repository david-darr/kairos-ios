import SwiftUI

/// Where a desktop read stands, for one plain sentence on screen.
nonisolated enum DriveLiveLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// How one change sent to the desktop ended.
nonisolated enum DriveLiveOutcome: Equatable, Sendable {
    case done
    /// The answer never arrived and the desktop does not show the change: it may still land. Never "failed".
    case unconfirmed(String)
    case failed(String)
    /// Not sent: a change to this file is already on its way.
    case busy
}

/// The sample Drive, kept aside while the phone shows the paired desktop's.
struct DriveSampleStash {
    var accounts: [DriveAccount]
    var currentAccountID: String?
    var files: [DriveFile]
}

/// One list the desktop was asked for: a view, a folder, a search and a type, in one Google account.
nonisolated struct DriveLiveKey: Hashable, Sendable {
    var account: String
    var section: DriveSection
    /// Google's id of the folder, or nil for the top of a view.
    var folder: String?
    var query: String
    var filter: DriveFilter
}

nonisolated struct DriveLiveList: Equatable, Sendable {
    var ids: [String] = []
    var load: DriveLiveLoad = .idle
    var next: String?
    var partial = false
    var loadingMore = false
}

/// What the phone knew when it asked for a new item (folder, sheet, form, copy, upload), so that after a lost
/// answer it only ever takes an item it can prove is that one.
nonisolated struct DriveMakeProof: Sendable {
    var name: String
    /// Google's id of the folder it was made in, or "root" for the top of My Drive.
    var parent: String
    /// The exact type Google gives the new item.
    var mime: String
    /// Every item with that name and type in that folder just before the request. Nil when that could not be read
    /// whole, so nothing can be proved.
    var before: Set<String>?
    /// When the request went out.
    var sentAt: Date
}

/// One form change, decided from the form as read just before it is sent.
enum DriveFormPlan {
    case send((APIClient, String, String) async throws -> Void)
    /// Nothing is sent; the outcome says why.
    case stop(DriveLiveOutcome)
}

/// The paired desktop behind Google Drive (routes/google_routes.py): accounts (GET /api/google/status), lists
/// (GET /api/google/drive/files), storage, one file, previews, every Drive action, uploads, Sheets one cell at a
/// time and Forms one item at a time. Unpaired, nothing here runs and Drive shows its sample files.
extension DriveStore {

    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// Which desktop and which Kairos account the Drive belongs to.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    func stillLive(_ account: String) -> Bool {
        !isSample && liveAccount == account && Self.accountKey == account
    }

    private static let desktopChanged = "Your paired desktop changed. Try again."

    /// Move between the sample Drive and the paired desktop's to match the connection.
    func followConnection() {
        let wantLive = !Connection.shared.usesSampleData
        if wantLive && !isSample && liveAccount != Self.accountKey {
            resetLive()
        }
        guard wantLive == isSample else { return }
        if wantLive {
            sampleStash = DriveSampleStash(accounts: accounts, currentAccountID: currentAccountID, files: files)
            resetLive()
            isSample = false
        } else {
            clearLive()
            isSample = true
            liveAccount = "sample"
            accounts = sampleStash?.accounts ?? DriveSample.accounts
            currentAccountID = sampleStash?.currentAccountID ?? DriveSample.accounts.first?.id
            files = sampleStash?.files ?? DriveSample.files
            sampleStash = nil
        }
    }

    private func resetLive() {
        accounts = []
        currentAccountID = nil
        files = []
        clearLive()
        liveAccount = Self.accountKey
    }

    private func clearLive() {
        accountsLoad = .idle
        lists = [:]
        listSerial = [:]
        shownKey = nil
        busy = []
        uploadProgress = nil
        reads = [:]
        readSerials = [:]
        liveNote = nil
    }

    func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    /// Only the phone's own pairing failing or the desktop going quiet is passed to the connection. A Google
    /// refusal (a 401 from an expired Google sign-in among them) is about the Google account, not the phone.
    private func noteConnection(_ error: Error) {
        guard let api = error as? APIError else { return }
        switch api {
        case .unauthorized, .offline: Connection.shared.note(error)
        default: break
        }
    }

    /// The desktop refused the request, so it certainly did not happen. Anything else (not reached, timed out,
    /// an answer this app could not read, Google not answering the desktop) may have come after it happened.
    static func wasRefused(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status) && status != 408
        case .offline, .unreadable: return false
        }
    }

    private static func isCancel(_ error: Error) -> Bool {
        error is CancellationError || Task.isCancelled
    }

    /// A Google account the desktop says needs signing in again: marked here so the card says so.
    private func markBroken(_ google: String, _ error: Error) {
        guard case .server(status: 401, let detail) = error as? APIError,
              let index = accounts.firstIndex(where: { $0.id == google }) else { return }
        accounts[index].broken = true
        accounts[index].problem = detail
    }

    // MARK: Mapping

    nonisolated static func liveAccounts(_ status: DriveDTOStatus) -> [DriveAccount] {
        (status.accounts?.items ?? []).map { item in
            DriveAccount(id: item.id, email: item.email ?? "Google account", usedGB: 0, totalGB: 0,
                         broken: item.error?.isEmpty == false, canSend: item.canSendEmail ?? false,
                         storageText: "Storage not read yet", problem: item.error)
        }
    }

    nonisolated static func kind(_ mime: String, name: String) -> DriveKind {
        switch mime {
        case DriveWire.folderMime: return .folder
        case "application/vnd.google-apps.document": return .doc
        case "application/vnd.google-apps.spreadsheet": return .sheet
        case "application/vnd.google-apps.form": return .form
        case "application/vnd.google-apps.presentation": return .slides
        case "application/pdf": return .pdf
        default:
            if mime.hasPrefix("image/") { return .image }
            if mime.hasPrefix("text/") { return .text }
            return .file
        }
    }

    /// The phone's id for a Google file: the account and Google's id, so the same file under two accounts
    /// is two items, and every change goes out with the account it was listed under.
    nonisolated static func liveID(account: String, remote: String) -> String {
        account + "~" + remote
    }

    nonisolated static func liveFile(_ dto: DriveDTOFile, account: String) -> DriveFile {
        let mime = dto.mimeType ?? ""
        let name = dto.name ?? "Untitled"
        let parent = dto.parents?.first
        var file = DriveFile(
            id: liveID(account: account, remote: dto.id), account: account, name: name, kind: kind(mime, name: name),
            size: DriveWire.int64(dto.size) ?? 0, modified: DriveWire.time(dto.modifiedTime) ?? .distantPast,
            starred: dto.starred ?? false, trashed: dto.trashed ?? false,
            parent: parent.map { liveID(account: account, remote: $0) },
            sharedWithMe: dto.owners.map { owners in !owners.contains { $0.me == true } } ?? false
        )
        file.remoteID = dto.id
        file.parentRemote = parent
        file.mime = mime
        file.webLink = dto.webViewLink
        return file
    }

    nonisolated static func liveMember(_ dto: DriveDTOPermission) -> DriveMember {
        let audience: DriveAudience
        switch dto.type {
        case "group": audience = .group
        case "domain": audience = .domain
        case "anyone": audience = .anyone
        default: audience = .person
        }
        let access: DriveAccess
        var label: String?
        switch dto.role {
        case "reader": access = .viewer
        case "commenter": access = .commenter
        case "writer": access = .editor
        case "owner": access = .owner
        case "organizer":
            access = .owner
            label = "Manager"
        case "fileOrganizer":
            access = .owner
            label = "Content manager"
        default:
            access = .owner
            label = dto.role ?? "Access"
        }
        let address = audience == .domain ? (dto.domain ?? "") : (dto.emailAddress ?? dto.displayName ?? "")
        return DriveMember(id: dto.id, audience: audience, address: address, access: access, roleLabel: label)
    }

    /// Rows and columns of text, as many as asked for, empty where Google left a cell out.
    nonisolated static func liveGrid(_ dto: DriveDTOSheetValues, rows: Int, columns: Int) -> [[String]] {
        let values = dto.values ?? []
        return (0..<rows).map { r in
            (0..<columns).map { c in
                guard r < values.count, c < values[r].count else { return "" }
                return values[r][c].plainText
            }
        }
    }

    nonisolated static func liveForm(_ dto: DriveDTOForm) -> DriveForm {
        let questions = (dto.items?.items ?? []).map { item -> DriveQuestion in
            let question = item.questionItem?.question
            var type = DriveQuestionType.short
            var choices: [String] = []
            var label: String?
            if let choice = question?.choiceQuestion {
                type = choice.type == "CHECKBOX" ? .checkboxes : .choice
                choices = (choice.options ?? []).compactMap(\.value)
                if choice.type == "DROP_DOWN" { label = "Drop-down" }
            } else if let text = question?.textQuestion {
                type = text.paragraph == true ? .paragraph : .short
            } else if question != nil {
                label = "Question"
            } else {
                label = "Not a question"
            }
            return DriveQuestion(id: item.itemId ?? UUID().uuidString, text: item.title ?? "Untitled item", type: type,
                                 choices: choices, remoteID: item.itemId, label: label)
        }
        return DriveForm(title: dto.info?.title ?? dto.info?.documentTitle ?? "Untitled form", questions: questions,
                         published: dto.publishSettings?.publishState?.isPublished ?? false)
    }

    /// One line per response: the answers in the form's question order.
    nonisolated static func liveResponses(_ dto: DriveDTOFormResponses, form: DriveDTOForm) -> [String] {
        let order = (form.items?.items ?? []).compactMap { $0.questionItem?.question?.questionId }
        return (dto.responses?.items ?? []).map { response in
            let answers = response.answers ?? [:]
            let known = order.compactMap { answers[$0].map(DriveWire.answerText) }
            let rest = answers.keys.filter { !order.contains($0) }.sorted().compactMap { answers[$0].map(DriveWire.answerText) }
            return (known + rest).filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    nonisolated static func sectionText(_ section: DriveSection) -> String {
        switch section {
        case .myDrive: "my_drive"
        case .shared: "shared"
        case .starred: "starred"
        case .recent: "recent"
        case .trash: "trash"
        }
    }

    nonisolated static func kindText(_ filter: DriveFilter) -> String {
        switch filter {
        case .all: "all"
        case .folders: "folder"
        case .sheets: "sheet"
        case .forms: "form"
        }
    }

    /// Put a file read from the desktop in the store. A file with a change on its way keeps what the person sees
    /// until that change is answered; what the phone read about it before (people, revisions) stays.
    private func upsert(_ fresh: DriveFile, force: Bool = false) {
        if let index = files.firstIndex(where: { $0.id == fresh.id }) {
            guard force || !busy.contains(fresh.id) else { return }
            var file = fresh
            file.members = files[index].members
            file.revisions = files[index].revisions
            files[index] = file
        } else {
            files.append(fresh)
        }
    }

    // MARK: Accounts and storage

    var liveCurrentAccount: DriveAccount? { currentAccount }

    /// One line for the Files overview's Drive row.
    var overviewLine: String {
        if Connection.shared.usesSampleData || isSample {
            if !Connection.shared.usesSampleData { return "On your desktop" }
            guard let account = currentAccount else { return "Not connected" }
            return account.broken ? "Reconnect needed" : "Connected · \(account.storage)"
        }
        switch accountsLoad {
        case .idle, .loading: return accounts.isEmpty ? "Reading your Google accounts" : overviewAccountLine
        case .failed: return accounts.isEmpty ? "Could not be read" : overviewAccountLine
        case .loaded: return overviewAccountLine
        }
    }

    private var overviewAccountLine: String {
        guard let account = currentAccount else { return "Not connected" }
        return account.broken ? "Reconnect needed" : "Connected · \(account.email)"
    }

    /// For the Files overview: follow the connection and read the accounts once.
    func overviewTask() async {
        followConnection()
        guard !isSample else { return }
        if accountsLoad == .idle { await loadAccountsLive() }
    }

    /// Read the Google accounts this Kairos account may use, then the storage of the one being browsed.
    func loadAccountsLive() async {
        guard !isSample else { return }
        let account = liveAccount
        accountsSerial += 1
        let mine = accountsSerial
        if accountsLoad != .loaded { accountsLoad = .loading }
        do {
            let status = try await liveClient().driveStatus()
            guard stillLive(account), mine == accountsSerial else { return }
            var fresh = Self.liveAccounts(status)
            for index in fresh.indices {
                if let old = accounts.first(where: { $0.id == fresh[index].id }) {
                    fresh[index].storageText = old.storageText
                    fresh[index].usedGB = old.usedGB
                    fresh[index].totalGB = old.totalGB
                }
            }
            accounts = fresh
            if currentAccountID == nil || !fresh.contains(where: { $0.id == currentAccountID }) {
                let chosen = status.defaultAccount.flatMap { id in fresh.first { $0.id == id } }
                currentAccountID = (chosen ?? fresh.first(where: { !$0.broken }) ?? fresh.first)?.id
                lists = [:]
            }
            accountsLoad = .loaded
            if let current = currentAccountID { await loadStorageLive(current) }
        } catch {
            if Self.isCancel(error) {
                if accountsLoad == .loading, mine == accountsSerial { accountsLoad = .idle }
                return
            }
            noteConnection(error)
            guard stillLive(account), mine == accountsSerial else { return }
            accountsLoad = .failed("Your Google accounts could not be read. " + error.plainWords)
        }
    }

    func loadStorageLive(_ google: String) async {
        guard !isSample else { return }
        let account = liveAccount
        do {
            let read = try await liveClient().driveStorage(account: google)
            guard stillLive(account), let index = accounts.firstIndex(where: { $0.id == google }) else { return }
            let used = Double(DriveWire.int64(read.storageQuota?.usage) ?? 0)
            let limit = Double(DriveWire.int64(read.storageQuota?.limit) ?? 0)
            let gb = 1_073_741_824.0
            accounts[index].usedGB = used / gb
            accounts[index].totalGB = limit / gb
            accounts[index].storageText = limit > 0
                ? String(format: "%.1f GB used of %.1f GB", used / gb, limit / gb)
                : String(format: "%.1f GB used", used / gb)
        } catch {
            if Self.isCancel(error) { return }
            noteConnection(error)
            guard stillLive(account), let index = accounts.firstIndex(where: { $0.id == google }) else { return }
            markBroken(google, error)
            accounts[index].storageText = "Storage unavailable"
        }
    }

    func switchAccountLive(_ id: String) {
        guard !isSample, accounts.contains(where: { $0.id == id }) else { return }
        currentAccountID = id
        Task { await loadStorageLive(id) }
    }

    // MARK: Lists

    func key(section: DriveSection, folder: String?, query: String, filter: DriveFilter) -> DriveLiveKey? {
        guard let account = currentAccountID else { return nil }
        let remote = folder.flatMap { self.file($0)?.remoteID }
        // A folder this Drive does not know (another desktop or account) is never read as the top of a view.
        if folder != nil && remote == nil { return nil }
        let words = String(query.trimmingCharacters(in: .whitespaces).prefix(100))
        return DriveLiveKey(account: account, section: folder == nil ? section : (section == .trash ? .trash : section),
                            folder: remote, query: folder == nil ? words : "", filter: filter)
    }

    func liveItems(_ key: DriveLiveKey?) -> [DriveFile] {
        guard let key, let list = lists[key] else { return [] }
        return list.ids.compactMap { id in file(id) }
    }

    /// Read one list. Already read, it stays on screen while it refreshes. An older read never lands over a newer
    /// one; a read that was on its way while a change finished is read again; a cancelled read changes nothing.
    @discardableResult
    func loadList(_ key: DriveLiveKey, more: Bool = false) async -> Bool {
        guard !isSample else { return false }
        let account = liveAccount
        listSerial[key, default: 0] += 1
        let mine = listSerial[key] ?? 0
        var list = lists[key] ?? DriveLiveList()
        let token = more ? list.next : nil
        if more {
            guard token != nil, !list.loadingMore else { return false }
            list.loadingMore = true
        } else if list.load != .loaded {
            list.load = .loading
        }
        lists[key] = list
        func current() -> Bool { stillLive(account) && listSerial[key] == mine }
        for _ in 0..<3 {
            let writes = writeSerial
            do {
                let section = key.folder == nil ? Self.sectionText(key.section) : (key.section == .trash ? "trash" : "all")
                let read = try await liveClient().driveFiles(account: key.account, section: section, parent: key.folder,
                                                             query: key.query, kind: Self.kindText(key.filter), pageToken: token)
                guard current() else { return false }
                guard writes == writeSerial else { continue }
                let fresh = (read.files?.items ?? []).map { Self.liveFile($0, account: key.account) }
                for file in fresh { upsert(file) }
                var done = lists[key] ?? DriveLiveList()
                let ids = fresh.map(\.id)
                done.ids = more ? done.ids + ids.filter { !done.ids.contains($0) } : ids
                done.next = read.nextPageToken
                done.partial = read.incompleteSearch ?? false
                done.load = .loaded
                done.loadingMore = false
                lists[key] = done
                return true
            } catch {
                if Self.isCancel(error) {
                    if current() {
                        var back = lists[key] ?? DriveLiveList()
                        back.loadingMore = false
                        if back.load == .loading { back.load = .idle }
                        lists[key] = back
                    }
                    return false
                }
                noteConnection(error)
                guard current() else { return false }
                markBroken(key.account, error)
                var failed = lists[key] ?? DriveLiveList()
                failed.loadingMore = false
                if more {
                    liveNote = "More files could not be read. " + error.plainWords
                } else {
                    failed.load = .failed("Your Drive could not be read. " + error.plainWords)
                }
                lists[key] = failed
                return false
            }
        }
        guard current() else { return false }
        var busyList = lists[key] ?? DriveLiveList()
        busyList.loadingMore = false
        if busyList.load != .loaded { busyList.load = .failed("Your Drive kept changing while it was read. Try again.") }
        lists[key] = busyList
        return false
    }

    /// Read the list on screen again, after a change.
    private func refreshShown(_ account: String) {
        guard let key = shownKey else { return }
        Task { if stillLive(account) { await loadList(key) } }
    }

    /// Read the list on screen again, after a batch stopped.
    func refreshShownLive() {
        refreshShown(liveAccount)
    }

    /// Items named exactly `name` of one type directly in one folder (Google's id, or "root" for the top of My Drive).
    /// Nil when it could not be read whole: not read, more than one page, a partial search, or a row that could not
    /// be decoded. A partial read proves nothing.
    private func named(_ name: String, google: String, parent: String, mime: String) async -> [DriveDTOFile]? {
        let kind = mime == DriveWire.folderMime ? "folder"
            : (mime == "application/vnd.google-apps.spreadsheet" ? "sheet" : (mime == "application/vnd.google-apps.form" ? "form" : "all"))
        guard let client = try? liveClient(),
              let read = try? await client.driveFiles(account: google, section: "all", parent: parent,
                                                      query: name, kind: kind, pageToken: nil),
              read.nextPageToken == nil, read.incompleteSearch != true, (read.files?.skipped ?? 0) == 0 else { return nil }
        return (read.files?.items ?? []).filter { $0.name == name && $0.mimeType == mime }
    }

    /// Before a request that makes an item: what is already there under that name.
    private func proof(_ name: String, google: String, parent: String, mime: String) async -> DriveMakeProof {
        let before = await named(name, google: google, parent: parent, mime: mime).map { Set($0.map(\.id)) }
        return DriveMakeProof(name: name, parent: parent, mime: mime, before: before, sentAt: Date())
    }

    /// Folders in one Google account whose names match `query`, for "Move to folder".
    func foldersLive(account google: String, query: String) async throws -> [DriveFile] {
        let account = liveAccount
        let read = try await liveClient().driveFiles(account: google, section: "all", parent: nil,
                                                     query: String(query.prefix(100)), kind: "folder", pageToken: nil)
        guard stillLive(account) else { throw CancellationError() }
        let fresh = (read.files?.items ?? []).map { Self.liveFile($0, account: google) }
        for file in fresh { upsert(file) }
        return fresh.filter { !$0.trashed }
    }

    // MARK: One file

    /// Read one file again (its link, name and state). Quiet when it fails: the list's copy stays.
    func refreshFileLive(_ id: String) async {
        guard !isSample, let file = file(id), let remote = file.remoteID else { return }
        let account = liveAccount
        let key = "info|" + id
        readSerials[key, default: 0] += 1
        let mine = readSerials[key] ?? 0
        if reads[key] != .loaded { reads[key] = .loading }
        do {
            // A read that was on its way while a change finished is read again, so it never puts the old state back.
            for _ in 0..<3 {
                let writes = writeSerial
                let fresh = try await liveClient().driveFile(account: file.account, id: remote)
                guard stillLive(account), readSerials[key] == mine else { return }
                guard writes == writeSerial else { continue }
                upsert(Self.liveFile(fresh, account: file.account))
                reads[key] = .loaded
                return
            }
            if reads[key] != .loaded { reads[key] = .failed("This file kept changing while it was read. Try again.") }
        } catch {
            if Self.isCancel(error) { return }
            noteConnection(error)
            guard stillLive(account), readSerials[key] == mine else { return }
            if case .server(status: 404, _) = error as? APIError {
                reads[key] = .failed("This file is not in this Drive any more. It may have been deleted, or its sharing changed.")
            } else {
                reads[key] = .failed("This file could not be read again. " + error.plainWords)
            }
        }
    }

    func loadRevisionsLive(_ id: String) async {
        guard !isSample, let file = file(id), let remote = file.remoteID else { return }
        let account = liveAccount
        let key = "revisions|" + id
        readSerials[key, default: 0] += 1
        let mine = readSerials[key] ?? 0
        if reads[key] != .loaded { reads[key] = .loading }
        do {
            let read = try await liveClient().driveRevisions(account: file.account, id: remote)
            guard stillLive(account), readSerials[key] == mine, let index = files.firstIndex(where: { $0.id == id }) else { return }
            files[index].revisions = (read.revisions?.items ?? []).compactMap { DriveWire.time($0.modifiedTime) }.sorted(by: >)
            reads[key] = .loaded
        } catch {
            if Self.isCancel(error) { if reads[key] == .loading { reads[key] = nil }; return }
            noteConnection(error)
            guard stillLive(account), readSerials[key] == mine else { return }
            reads[key] = .failed("Revisions unavailable for this file.")
        }
    }

    /// Who has access. Answers true when this read is what the screen now shows.
    @discardableResult
    func loadPeopleLive(_ id: String) async -> Bool {
        guard !isSample, let file = file(id), let remote = file.remoteID else { return false }
        let account = liveAccount
        let key = "people|" + id
        readSerials[key, default: 0] += 1
        let mine = readSerials[key] ?? 0
        if reads[key] != .loaded { reads[key] = .loading }
        do {
            let read = try await liveClient().drivePermissions(account: file.account, id: remote)
            guard stillLive(account), readSerials[key] == mine, let index = files.firstIndex(where: { $0.id == id }) else { return false }
            let people = (read.permissions?.items ?? []).map(Self.liveMember)
            files[index].members = people.filter { $0.access == .owner } + people.filter { $0.access != .owner }
            reads[key] = .loaded
            return true
        } catch {
            if Self.isCancel(error) { if reads[key] == .loading { reads[key] = nil }; return false }
            noteConnection(error)
            guard stillLive(account), readSerials[key] == mine else { return false }
            reads[key] = .failed("Sharing could not be read. " + error.plainWords)
            return false
        }
    }

    func livePreview(_ id: String) async throws -> DrivePreviewBytes {
        guard let file = file(id), let remote = file.remoteID else { throw APIError.notPaired }
        let account = liveAccount
        let read = try await liveClient().drivePreview(account: file.account, id: remote)
        guard stillLive(account) else { throw CancellationError() }
        return read
    }

    // MARK: Changing one file

    /// Send one Drive action for one file. When the answer is lost, the file is read again and `check` says
    /// whether the desktop has the change; the file then shows what Google really has.
    private func change(_ id: String, action: String, extra: [String: Any] = [:], what: String, gone: String? = nil,
                        check: @escaping (DriveDTOFile) -> Bool) async -> DriveLiveOutcome {
        guard !isSample, let file = file(id), let remote = file.remoteID else { return .failed("This file is a sample.") }
        guard !busy.contains(id) else { return .busy }
        let account = liveAccount
        let google = file.account
        busy.insert(id)
        defer {
            writeSerial += 1
            if liveAccount == account { busy.remove(id) }
        }
        var body = extra
        body["action"] = action
        body["file_id"] = remote
        do {
            let data = try await liveClient().driveAction(account: google, body)
            guard stillLive(account) else { return .done }
            if let changed = try? DriveWire.decode(DriveDTOChanged.self, data), let index = files.firstIndex(where: { $0.id == id }) {
                if let name = changed.name { files[index].name = name }
                if let starred = changed.starred { files[index].starred = starred }
                if let trashed = changed.trashed { files[index].trashed = trashed }
                if let parent = changed.parents?.first {
                    files[index].parentRemote = parent
                    files[index].parent = Self.liveID(account: google, remote: parent)
                }
            }
            refreshShown(account)
            return .done
        } catch {
            noteConnection(error)
            guard stillLive(account) else { return .failed(Self.desktopChanged) }
            markBroken(google, error)
            if Self.wasRefused(error) {
                refreshShown(account)
                if case .server(status: 404, _) = error as? APIError {
                    return .failed(gone ?? "\(file.name) is not in this Drive any more.")
                }
                return .failed(what + " " + error.plainWords)
            }
            // The change may have reached Google before the answer was lost: look.
            if let fresh = try? await liveClient().driveFile(account: google, id: remote), stillLive(account) {
                upsert(Self.liveFile(fresh, account: google), force: true)
                refreshShown(account)
                if check(fresh) { return .done }
                return .unconfirmed("Your desktop did not confirm this, and Drive does not show it yet. It now shows what Google has. Check again in a moment before you try again.")
            }
            return .unconfirmed("Your desktop did not confirm this, and \(file.name) could not be read to check. Look again before you try again.")
        }
    }

    func renameLive(_ id: String, to name: String) async -> DriveLiveOutcome {
        await change(id, action: "rename", extra: ["name": name], what: "It was not renamed.") { $0.name == name }
    }

    func starLive(_ id: String, _ on: Bool) async -> DriveLiveOutcome {
        await change(id, action: on ? "star" : "unstar", what: on ? "It was not starred." : "The star was not removed.") { ($0.starred ?? false) == on }
    }

    func trashLive(_ id: String) async -> DriveLiveOutcome {
        await change(id, action: "trash", what: "It was not moved to the trash.") { $0.trashed == true }
    }

    func restoreLive(_ id: String) async -> DriveLiveOutcome {
        await change(id, action: "restore", what: "It was not restored.") { $0.trashed == false }
    }

    /// Move into a folder (its phone id), or to the top of My Drive (nil).
    func moveLive(_ id: String, to folder: String?) async -> DriveLiveOutcome {
        guard let file = file(id) else { return .failed("This file is not in this Drive any more.") }
        let target: String
        if let folder {
            guard let destination = self.file(folder), destination.account == file.account, let remote = destination.remoteID else {
                return .failed("That folder is in another Google account.")
            }
            target = remote
        } else {
            target = "root"
        }
        let before = file.parentRemote
        let place = folder.flatMap { self.file($0)?.name } ?? "My Drive"
        return await change(id, action: "move", extra: ["parent": target], what: "It was not moved.",
                            gone: "\(file.name) was not moved: Google could not find it or \(place). The list now shows what Google has.") { fresh in
            let parents = fresh.parents ?? []
            if target == "root" { return before.map { !parents.contains($0) } ?? false }
            return parents.contains(target)
        }
    }

    /// Copy a file next to it, named "<name> copy". A copy whose answer never arrived is looked for in that
    /// folder, and only an item proved to be this copy is reported as made; nothing is copied again by itself.
    func copyLive(_ id: String) async -> DriveLiveOutcome {
        guard !isSample, let file = file(id), let remote = file.remoteID else { return .failed("This file is a sample.") }
        guard !file.isFolder else { return .failed("Folders cannot be copied in Google Drive.") }
        guard !busy.contains(id) else { return .busy }
        let account = liveAccount
        let google = file.account
        let name = String((file.name + " copy").prefix(255))
        busy.insert(id)
        defer {
            writeSerial += 1
            if liveAccount == account { busy.remove(id) }
        }
        // Google puts a copy with no folder named into the top of My Drive.
        let place = file.parentRemote ?? "root"
        let check = await proof(name, google: google, parent: place, mime: file.mime)
        guard stillLive(account) else { return .failed(Self.desktopChanged) }
        var body: [String: Any] = ["action": "copy", "file_id": remote, "name": name]
        if let parent = file.parentRemote { body["parent"] = parent }
        do {
            try await liveClient().driveAction(account: google, body)
            guard stillLive(account) else { return .done }
            refreshShown(account)
            return .done
        } catch {
            noteConnection(error)
            guard stillLive(account) else { return .failed(Self.desktopChanged) }
            markBroken(google, error)
            if Self.wasRefused(error) {
                refreshShown(account)
                return .failed("It was not copied. " + error.plainWords)
            }
            return await lookFor(check, google: google, account: account, what: "the copy of \(file.name)").outcome
        }
    }

    /// After a make whose answer never arrived: look in the place it was sent to. Only an item that is provably the
    /// new one counts: the same name and exact type, not trashed, in that folder, not there before the request, and
    /// changed no earlier than the request (with two minutes for the phone's clock). Never a same-named older item.
    /// Anything less is "cannot tell", and the list then shows the folder as Google has it.
    private func lookFor(_ proof: DriveMakeProof, google: String, account: String,
                         what: String) async -> (outcome: DriveLiveOutcome, id: String?) {
        defer { if stillLive(account) { refreshShown(account) } }
        guard let before = proof.before else {
            return (.unconfirmed("Your desktop did not confirm \(what), and the phone could not tell what was there before. The list now shows what Google has. Look for it before you try again."), nil)
        }
        let after = await named(proof.name, google: google, parent: proof.parent, mime: proof.mime)
        guard stillLive(account) else { return (.failed(Self.desktopChanged), nil) }
        guard let after else {
            return (.unconfirmed("Your desktop did not confirm \(what), and Drive could not be read whole to check. The list now shows what Google has. Look for it before you try again."), nil)
        }
        let earliest = proof.sentAt.addingTimeInterval(-120)
        let made = after.filter { item in
            guard item.trashed != true, item.mimeType == proof.mime, !before.contains(item.id),
                  let changed = DriveWire.time(item.modifiedTime), changed >= earliest else { return false }
            return proof.parent == "root" || (item.parents ?? []).contains(proof.parent)
        }
        if made.count == 1, let item = made.first {
            upsert(Self.liveFile(item, account: google))
            return (.done, item.id)
        }
        if made.count > 1 {
            return (.unconfirmed("Your desktop did not confirm \(what), and more than one new item has that name, so the phone cannot tell which is yours. The list now shows what Google has."), nil)
        }
        return (.unconfirmed("Your desktop did not confirm \(what), and it is not in Drive yet. It may still appear, so look again before you try again."), nil)
    }

    static func mime(_ kind: DriveKind) -> String {
        switch kind {
        case .folder: DriveWire.folderMime
        case .sheet: "application/vnd.google-apps.spreadsheet"
        default: "application/vnd.google-apps.form"
        }
    }

    /// A new folder, sheet or form, in a folder (its phone id) or My Drive. One at a time.
    func createLive(_ kind: DriveKind, name: String, in folder: String?) async -> DriveLiveOutcome {
        guard !isSample, let google = currentAccountID else { return .failed("This Drive is a sample.") }
        guard kind == .folder || kind == .sheet || kind == .form else { return .failed("Only folders, sheets and forms can be made here.") }
        guard !busy.contains("new") else { return .busy }
        let account = liveAccount
        var parent: String?
        if let folder {
            guard let place = file(folder), place.account == google, let remote = place.remoteID else {
                return .failed("That folder is in another Google account.")
            }
            parent = remote
        }
        let clean = String(name.prefix(200))
        busy.insert("new")
        defer {
            writeSerial += 1
            if liveAccount == account { busy.remove("new") }
        }
        // Sheets and forms are made in My Drive first, then moved, as the desktop's own page does.
        let home = kind == .folder ? (parent ?? "root") : "root"
        let check = await proof(clean, google: google, parent: home, mime: Self.mime(kind))
        guard stillLive(account) else { return .failed(Self.desktopChanged) }
        var made: String?
        do {
            let client = try liveClient()
            switch kind {
            case .folder:
                var body: [String: Any] = ["action": "create_folder", "name": clean]
                if let parent { body["parent"] = parent }
                try await client.driveAction(account: google, body)
                guard stillLive(account) else { return .done }
                refreshShown(account)
                return .done
            case .sheet:
                made = try await client.driveSheetCreate(account: google, title: clean).spreadsheetId
            default:
                made = try await client.driveFormCreate(account: google, title: clean).formId
            }
        } catch {
            noteConnection(error)
            guard stillLive(account) else { return .failed(Self.desktopChanged) }
            markBroken(google, error)
            if Self.wasRefused(error) {
                refreshShown(account)
                return .failed("\(clean) was not made. " + error.plainWords)
            }
            let found = await lookFor(check, google: google, account: account, what: clean)
            guard found.outcome == .done, let id = found.id else { return found.outcome }
            // Only the item proved to be the new one is ever moved.
            made = id
        }
        guard stillLive(account) else { return .done }
        guard let parent else {
            refreshShown(account)
            return .done
        }
        guard let made, DriveWire.isGoogleID(made) else {
            refreshShown(account)
            return .unconfirmed("\(clean) was made in My Drive, but your desktop did not say which file it is, so it was not moved into this folder. Look for it in My Drive.")
        }
        do {
            try await liveClient().driveAction(account: google, ["action": "move", "file_id": made, "parent": parent])
        } catch {
            noteConnection(error)
            guard stillLive(account) else { return .done }
            refreshShown(account)
            if !Self.wasRefused(error), let fresh = try? await liveClient().driveFile(account: google, id: made), stillLive(account),
               (fresh.parents ?? []).contains(parent) {
                upsert(Self.liveFile(fresh, account: google), force: true)
                return .done
            }
            return .unconfirmed("\(clean) was made in My Drive, but it may not have moved into this folder. Look for it before you make it again.")
        }
        refreshShown(account)
        return .done
    }

    /// Upload files, one at a time, into a folder (its phone id) or My Drive. Each file's size was checked from its
    /// attributes before anything was read; each is read off the main actor just before it is sent and dropped
    /// after. An upload whose answer never arrived is looked for in the folder before anything else is sent.
    func uploadLive(_ items: [DriveUploadItem], in folder: String?) async -> (sent: Int, outcome: DriveLiveOutcome) {
        guard !isSample, let google = currentAccountID else { return (0, .failed("This Drive is a sample.")) }
        guard !busy.contains("new") else { return (0, .busy) }
        let account = liveAccount
        var parent: String?
        if let folder {
            guard let place = file(folder), place.account == google, let remote = place.remoteID else {
                return (0, .failed("That folder is in another Google account."))
            }
            parent = remote
        }
        busy.insert("new")
        uploadProgress = 0
        defer {
            writeSerial += 1
            if liveAccount == account {
                busy.remove("new")
                uploadProgress = nil
            }
        }
        var sent = 0
        for item in items {
            guard item.size <= DriveWire.maxUpload else {
                return (sent, .failed("\(item.name) is over 25 MB, so it was not sent."))
            }
            let name = String(DriveWire.uploadName(item.name).prefix(255))
            let check = await proof(name, google: google, parent: parent ?? "root", mime: item.mimeType)
            guard stillLive(account) else { return (sent, .failed(Self.desktopChanged)) }
            uploadProgress = 0
            let watch = DriveUploadWatch { fraction in
                Task { @MainActor in
                    let store = DriveStore.shared
                    if store.liveAccount == account, store.uploadProgress != nil { store.uploadProgress = fraction }
                }
            }
            do {
                _ = try await liveClient().driveUpload(account: google, item: item, parent: parent, watch: watch)
                guard stillLive(account) else { return (sent + 1, .done) }
                sent += 1
            } catch let problem as DriveUploadProblem {
                guard stillLive(account) else { return (sent, .failed(Self.desktopChanged)) }
                switch problem {
                case .tooBig: return (sent, .failed("\(item.name) is over 25 MB, so it was not sent."))
                case .unreadable: return (sent, .failed("\(item.name) could not be read on your phone, so it was not sent."))
                }
            } catch {
                noteConnection(error)
                guard stillLive(account) else { return (sent, .failed(Self.desktopChanged)) }
                markBroken(google, error)
                if Self.wasRefused(error) {
                    refreshShown(account)
                    return (sent, .failed("\(item.name) was not uploaded. " + error.plainWords))
                }
                let found = await lookFor(check, google: google, account: account, what: item.name)
                guard found.outcome == .done else { return (sent, found.outcome) }
                sent += 1
            }
        }
        refreshShown(account)
        return (sent, .done)
    }

    // MARK: Sharing

    private static func role(_ access: DriveAccess) -> String {
        switch access {
        case .viewer: "reader"
        case .commenter: "commenter"
        case .editor, .owner: "writer"
        }
    }

    private static func permissionType(_ audience: DriveAudience) -> String {
        switch audience {
        case .person: "user"
        case .group: "group"
        case .domain: "domain"
        case .anyone: "anyone"
        }
    }

    private func people(_ id: String, google: String, remote: String) async -> [DriveMember]? {
        guard let read = try? await liveClient().drivePermissions(account: google, id: remote) else { return nil }
        return (read.permissions?.items ?? []).map(Self.liveMember)
    }

    /// One sharing change after the person confirmed it. When the answer is lost, who has access is read again
    /// and `check` says whether the change is there.
    private func sharingChange(_ id: String, body: [String: Any], what: String,
                               check: @escaping ([DriveMember]) -> Bool) async -> DriveLiveOutcome {
        guard !isSample, let file = file(id), let remote = file.remoteID else { return .failed("This file is a sample.") }
        let key = "share|" + id
        guard !busy.contains(key) else { return .busy }
        let account = liveAccount
        busy.insert(key)
        defer {
            writeSerial += 1
            if liveAccount == account { busy.remove(key) }
        }
        var sent = body
        sent["file_id"] = remote
        do {
            try await liveClient().driveAction(account: file.account, sent)
            guard stillLive(account) else { return .done }
            await loadPeopleLive(id)
            return .done
        } catch {
            noteConnection(error)
            guard stillLive(account) else { return .failed(Self.desktopChanged) }
            markBroken(file.account, error)
            if Self.wasRefused(error) {
                await loadPeopleLive(id)
                return .failed(what + " " + error.plainWords)
            }
            guard let now = await people(id, google: file.account, remote: remote), stillLive(account) else {
                return .unconfirmed("Your desktop did not confirm this, and sharing could not be read to check. Look again before you try again.")
            }
            await loadPeopleLive(id)
            if check(now) { return .done }
            return .unconfirmed("Your desktop did not confirm this, and sharing does not show it yet. Check again in a moment before you try again.")
        }
    }

    func shareLive(_ id: String, audience: DriveAudience, address: String, access: DriveAccess) async -> DriveLiveOutcome {
        var body: [String: Any] = ["action": "share", "permission_type": Self.permissionType(audience), "role": Self.role(access)]
        switch audience {
        case .person, .group: body["email"] = address
        case .domain: body["domain"] = address
        case .anyone: break
        }
        return await sharingChange(id, body: body, what: "It was not shared.") { people in
            people.contains { member in
                member.audience == audience && member.access == access
                    && (audience == .anyone || member.address.lowercased() == address.lowercased())
            }
        }
    }

    func setAccessLive(_ id: String, member: DriveMember, to access: DriveAccess) async -> DriveLiveOutcome {
        await sharingChange(id, body: ["action": "update_permission", "permission_id": member.id, "role": Self.role(access)],
                            what: "Their access was not changed.") { people in
            people.contains { $0.id == member.id && $0.access == access }
        }
    }

    func removeAccessLive(_ id: String, member: DriveMember) async -> DriveLiveOutcome {
        await sharingChange(id, body: ["action": "revoke", "permission_id": member.id], what: "Their access was not removed.") { people in
            !people.contains { $0.id == member.id }
        }
    }

    // MARK: Sheets, read only while paired

    // The desktop reads cells only as their shown values (FORMATTED_VALUE) and writes them as typed
    // (USER_ENTERED), so the phone cannot tell a formula from its result and would replace a formula with its value.
    // Cells are therefore never written from the phone while paired; the editor says to change them in Google.

    func sheetTabsLive(_ id: String) async throws -> [String] {
        guard let file = file(id), let remote = file.remoteID else { throw APIError.notPaired }
        let account = liveAccount
        let meta = try await liveClient().driveSheetMeta(account: file.account, id: remote)
        guard stillLive(account) else { throw CancellationError() }
        let tabs = (meta.sheets?.items ?? []).compactMap(\.properties).sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        return tabs.compactMap(\.title)
    }

    func cellsLive(_ id: String, tab: String, range: DriveCellRange) async throws -> [[String]] {
        guard let file = file(id), let remote = file.remoteID else { throw APIError.notPaired }
        let account = liveAccount
        let text = DriveCellRange.columnName(range.left) + "\(range.top + 1):"
            + DriveCellRange.columnName(range.left + range.columns - 1) + "\(range.top + range.rows)"
        let read = try await liveClient().driveSheetValues(account: file.account, id: remote, range: DriveWire.cellRange(tab: tab, text))
        guard stillLive(account) else { throw CancellationError() }
        return Self.liveGrid(read, rows: range.rows, columns: range.columns)
    }

    // MARK: Forms, one item at a time

    func formLive(_ id: String) async throws -> DriveDTOForm {
        guard let file = file(id), let remote = file.remoteID else { throw APIError.notPaired }
        let account = liveAccount
        let read = try await liveClient().driveForm(account: file.account, id: remote)
        guard stillLive(account) else { throw CancellationError() }
        return read
    }

    /// Up to five pages of responses (500). `more` is true when Google has more than were read.
    func formResponsesLive(_ id: String, form: DriveDTOForm) async throws -> (lines: [String], more: Bool) {
        guard let file = file(id), let remote = file.remoteID else { throw APIError.notPaired }
        let account = liveAccount
        var lines: [String] = []
        var token: String?
        for _ in 0..<5 {
            let read = try await liveClient().driveFormResponses(account: file.account, id: remote, pageToken: token)
            guard stillLive(account) else { throw CancellationError() }
            lines += Self.liveResponses(read, form: form)
            token = read.nextPageToken
            if token == nil { break }
        }
        return (lines, token != nil)
    }

    /// One form change. The form is read first, under the same hold that blocks a second change, and `plan` decides
    /// from that read what to send, or to send nothing. The request is sent alone; when its answer is lost the form
    /// is read again and `check` says whether the change is there.
    private func formChange(_ id: String, what: String, plan: @escaping (DriveDTOForm) -> DriveFormPlan,
                            check: @escaping (DriveDTOForm) -> Bool) async -> (DriveLiveOutcome, DriveDTOForm?) {
        guard !isSample, let file = file(id), let remote = file.remoteID else { return (.failed("This form is a sample."), nil) }
        guard !busy.contains(id) else { return (.busy, nil) }
        let account = liveAccount
        busy.insert(id)
        defer {
            writeSerial += 1
            if liveAccount == account { busy.remove(id) }
        }
        let fresh: DriveDTOForm
        do {
            fresh = try await formLive(id)
        } catch {
            noteConnection(error)
            guard stillLive(account) else { return (.failed(Self.desktopChanged), nil) }
            return (.failed(what + " The form could not be read first. " + error.plainWords), nil)
        }
        let send: (APIClient, String, String) async throws -> Void
        switch plan(fresh) {
        case .stop(let outcome): return (outcome, fresh)
        case .send(let request): send = request
        }
        do {
            try await send(try liveClient(), file.account, remote)
            guard stillLive(account) else { return (.done, nil) }
            return (.done, try? await formLive(id))
        } catch {
            noteConnection(error)
            guard stillLive(account) else { return (.failed(Self.desktopChanged), nil) }
            markBroken(file.account, error)
            if Self.wasRefused(error) { return (.failed(what + " " + error.plainWords), try? await formLive(id)) }
            guard let now = try? await formLive(id) else {
                return (.unconfirmed("Your desktop did not confirm this, and the form could not be read to check. Look again before you try again."), nil)
            }
            if check(now) { return (.done, now) }
            return (.unconfirmed("Your desktop did not confirm this, and the form does not show it yet. Check again in a moment before you try again."), now)
        }
    }

    private static let formChanged = "The form changed on your desktop, so nothing was sent. It now shows what Google has."

    /// Save the title, only if the desktop's title is still the one the field was filled from.
    func formTitleLive(_ id: String, title: String, filledFrom: String) async -> (DriveLiveOutcome, DriveDTOForm?) {
        await formChange(id, what: "The title was not saved.", plan: { form in
            let desktop = form.info?.title ?? ""
            guard desktop == filledFrom else {
                return .stop(.failed("The title changed on your desktop to \"\(desktop)\". Your text is still here; save again to replace it."))
            }
            return .send({ client, google, remote in
                try await client.driveFormChange(account: google, id: remote,
                                                 ["updateFormInfo": ["info": ["title": title], "updateMask": "title"] as [String: Any]])
            })
        }, check: { $0.info?.title == title })
    }

    /// Add one question at the end of the form as it is on the desktop just before sending.
    func addQuestionLive(_ id: String, _ question: DriveQuestion) async -> (DriveLiveOutcome, DriveDTOForm?) {
        var body: [String: Any] = ["required": false]
        switch question.type {
        case .choice, .checkboxes:
            body["choiceQuestion"] = ["type": question.type == .choice ? "RADIO" : "CHECKBOX",
                                      "options": question.choices.map { ["value": $0] }] as [String: Any]
        case .short, .paragraph:
            body["textQuestion"] = ["paragraph": question.type == .paragraph]
        }
        let item: [String: Any] = ["title": question.text, "questionItem": ["question": body]]
        var before: Set<String> = []
        return await formChange(id, what: "The question was not added.", plan: { form in
            // Every item must be known for the end to be the end.
            let list = form.items ?? DriveDTOList<DriveDTOFormItem>(items: [])
            guard list.skipped == 0 else {
                return .stop(.failed("This form has an item your phone cannot read, so nothing was sent. Add the question in Google Forms."))
            }
            let items = list.items
            before = Set(items.compactMap(\.itemId))
            let request: [String: Any] = ["createItem": ["item": item, "location": ["index": items.count]] as [String: Any]]
            return .send({ client, google, remote in try await client.driveFormChange(account: google, id: remote, request) })
        }, check: { form in
            (form.items?.items ?? []).contains { !before.contains($0.itemId ?? "") && $0.title == question.text }
        })
    }

    /// Remove one item by its position, but only if, in the form as read just before sending, the item at that
    /// position is still the one the person chose (same item id and title). Otherwise nothing is sent.
    func removeQuestionLive(_ id: String, itemID: String, title: String) async -> (DriveLiveOutcome, DriveDTOForm?) {
        await formChange(id, what: "The question was not removed.", plan: { form in
            let list = form.items ?? DriveDTOList<DriveDTOFormItem>(items: [])
            guard list.skipped == 0 else {
                return .stop(.failed("This form has an item your phone cannot read, so nothing was sent. Remove the question in Google Forms."))
            }
            guard let index = list.items.firstIndex(where: { $0.itemId == itemID }) else {
                return .stop(.failed("That question is not in the form any more. The form now shows what Google has."))
            }
            guard (list.items[index].title ?? "Untitled item") == title else { return .stop(.failed(Self.formChanged)) }
            return .send({ client, google, remote in
                try await client.driveFormChange(account: google, id: remote, ["deleteItem": ["location": ["index": index]]])
            })
        }, check: { form in !(form.items?.items ?? []).contains { $0.itemId == itemID } })
    }

    func publishLive(_ id: String, _ on: Bool) async -> (DriveLiveOutcome, DriveDTOForm?) {
        await formChange(id, what: on ? "The form was not published." : "The form was not unpublished.", plan: { _ in
            .send({ client, google, remote in try await client.driveFormPublish(account: google, id: remote, published: on) })
        }, check: { ($0.publishSettings?.publishState?.isPublished ?? false) == on })
    }
}

/// One quiet line on a Drive screen: loading, or what happened, with one plain action.
struct DriveLiveLine: View {
    let text: String
    var action: String? = nil
    var perform: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let action, let perform {
                Button {
                    Haptics.tap()
                    perform()
                } label: {
                    Text(action)
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

/// "Open in Google", drawn only when the desktop gave a real Google link.
struct DriveLiveOpenLink: View {
    let file: DriveFile
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url = DriveWire.googleLink(file.webLink) {
            Button {
                Haptics.tap()
                openURL(url)
            } label: {
                Label("Open in Google", systemImage: "arrow.up.forward.square")
                    .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
                    .background(Palette.gold.opacity(0.14), in: Capsule())
            }
            .buttonStyle(PressStyle())
        }
    }
}
