import SwiftUI

/// What the Drive screens need. The sample store fills it today; the desktop connection replaces it later.
protocol DriveProviding: AnyObject {
    var accounts: [DriveAccount] { get }
    var currentAccountID: String? { get }
    var files: [DriveFile] { get }

    func file(_ id: String) -> DriveFile?
    func listing(section: DriveSection, folder: String?, query: String, filter: DriveFilter) -> [DriveFile]
    func recent(limit: Int) -> [DriveFile]
    func ancestors(of id: String) -> [DriveFile]
    func destinations(excluding ids: [String]) -> [DriveFile]

    func switchAccount(_ id: String)
    func disconnect(_ id: String)

    @discardableResult func create(_ kind: DriveKind, name: String, in folder: String?) -> DriveFile
    @discardableResult func upload(name: String, size: Int64, in folder: String?) -> DriveFile
    func rename(_ id: String, to name: String)
    func move(_ ids: [String], to folder: String?)
    func copy(_ ids: [String])
    func setStarred(_ ids: [String], _ on: Bool)
    func trash(_ ids: [String])
    func restore(_ ids: [String])
    func deleteForever(_ id: String)

    func share(_ id: String, with member: DriveMember)
    func setAccess(_ id: String, member: String, to access: DriveAccess)
    func removeMember(_ id: String, member: String)

    func cells(_ id: String, tab: Int, range: DriveCellRange) -> [[String]]
    func saveCells(_ id: String, tab: Int, range: DriveCellRange, values: [[String]])

    func setFormTitle(_ id: String, _ title: String)
    func addQuestion(_ id: String, _ question: DriveQuestion)
    func removeQuestion(_ id: String, question: String)
    func setPublished(_ id: String, _ on: Bool)
}

@Observable
final class DriveStore: DriveProviding {
    static let shared = DriveStore()

    var accounts: [DriveAccount]
    var currentAccountID: String?
    var files: [DriveFile]

    // The paired desktop's Drive (DriveLive.swift). Unpaired, none of this is used.
    var isSample = true
    var liveAccount = "sample"
    var sampleStash: DriveSampleStash?
    var accountsLoad: DriveLiveLoad = .idle
    var accountsSerial = 0
    var lists: [DriveLiveKey: DriveLiveList] = [:]
    var listSerial: [DriveLiveKey: Int] = [:]
    /// The list on screen, read again after every change.
    var shownKey: DriveLiveKey?
    var writeSerial = 0
    /// Files with a change on its way, and "new" while something is being made or uploaded.
    var busy: Set<String> = []
    /// How far the upload on its way has gone, 0 to 1.
    var uploadProgress: Double?
    /// Per-file reads: "info|id", "revisions|id", "people|id".
    var reads: [String: DriveLiveLoad] = [:]
    var readSerials: [String: Int] = [:]
    /// A longer sentence about the last change than a toast can hold.
    var liveNote: String?

    init() {
        accounts = DriveSample.accounts
        currentAccountID = DriveSample.accounts.first?.id
        files = DriveSample.files
    }

    var currentAccount: DriveAccount? { accounts.first { $0.id == currentAccountID } }

    // MARK: Reading

    func file(_ id: String) -> DriveFile? { files.first { $0.id == id } }

    private var mine: [DriveFile] { files.filter { $0.account == currentAccountID } }

    /// True when the file or any folder above it is in the trash.
    private func hidden(_ file: DriveFile) -> Bool {
        if file.trashed { return true }
        var parent = file.parent
        var guardCount = 0
        while let id = parent, guardCount < 20 {
            guard let folder = self.file(id) else { return false }
            if folder.trashed { return true }
            parent = folder.parent
            guardCount += 1
        }
        return false
    }

    func listing(section: DriveSection, folder: String?, query: String, filter: DriveFilter) -> [DriveFile] {
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [DriveFile]
        if section == .trash && folder == nil {
            result = mine.filter { $0.trashed }
        } else {
            let live = mine.filter { !hidden($0) }
            if !words.isEmpty {
                result = live.filter { $0.name.lowercased().contains(words) }
            } else if let folder {
                result = live.filter { $0.parent == folder }
            } else {
                switch section {
                case .myDrive: result = live.filter { $0.parent == nil && !$0.sharedWithMe }
                case .shared: result = live.filter { $0.parent == nil && $0.sharedWithMe }
                case .starred: result = live.filter { $0.starred }
                case .recent: result = Array(live.filter { !$0.isFolder }.sorted { $0.modified > $1.modified }.prefix(15))
                case .trash: result = []
                }
            }
        }
        result = result.filter { filter.keeps($0) }
        if section == .recent && folder == nil && words.isEmpty { return result }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func recent(limit: Int) -> [DriveFile] {
        Array(mine.filter { !$0.isFolder && !hidden($0) }.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    /// The folders from the top down to this one, including it.
    func ancestors(of id: String) -> [DriveFile] {
        var chain: [DriveFile] = []
        var next: String? = id
        while let current = next, let folder = file(current), chain.count < 20 {
            chain.insert(folder, at: 0)
            next = folder.parent
        }
        return chain
    }

    private func descendants(of id: String) -> Set<String> {
        var found: Set<String> = []
        var queue = [id]
        while let current = queue.popLast() {
            for child in files where child.parent == current && !found.contains(child.id) {
                found.insert(child.id)
                queue.append(child.id)
            }
        }
        return found
    }

    /// Folders a file can move into: not itself, not inside itself, not in the trash.
    func destinations(excluding ids: [String]) -> [DriveFile] {
        var blocked = Set(ids)
        for id in ids { blocked.formUnion(descendants(of: id)) }
        return mine
            .filter { $0.isFolder && !hidden($0) && !blocked.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Accounts

    func switchAccount(_ id: String) {
        guard let account = accounts.first(where: { $0.id == id }), !account.broken else { return }
        currentAccountID = id
    }

    func disconnect(_ id: String) {
        accounts.removeAll { $0.id == id }
        files.removeAll { $0.account == id }
        if currentAccountID == id {
            currentAccountID = accounts.first(where: { !$0.broken })?.id ?? accounts.first?.id
        }
    }

    // MARK: Changing files

    private func update(_ id: String, _ change: (inout DriveFile) -> Void) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        change(&files[index])
    }

    private var owner: DriveMember {
        DriveMember(audience: .person, address: currentAccount?.email ?? "you@example.com", access: .owner)
    }

    @discardableResult
    func create(_ kind: DriveKind, name: String, in folder: String?) -> DriveFile {
        var file = DriveFile(id: UUID().uuidString, account: currentAccountID ?? "", name: name, kind: kind, modified: .now, parent: folder)
        file.members = [owner]
        file.revisions = kind == .folder ? [] : [.now]
        switch kind {
        case .sheet:
            file.sheets = [DriveSheetTab(title: "Sheet1", cells: [])]
        case .form:
            file.form = DriveForm(title: name)
        case .doc:
            file.body = "A new document. Write in it from Google Docs."
        default:
            break
        }
        files.append(file)
        return file
    }

    @discardableResult
    func upload(name: String, size: Int64, in folder: String?) -> DriveFile {
        var file = DriveFile(id: UUID().uuidString, account: currentAccountID ?? "", name: name, kind: DriveKind.from(fileName: name), size: size, modified: .now, parent: folder)
        file.members = [owner]
        file.revisions = [.now]
        file.body = "Uploaded from your phone."
        files.append(file)
        return file
    }

    func rename(_ id: String, to name: String) {
        update(id) { $0.name = name; $0.modified = .now }
    }

    func move(_ ids: [String], to folder: String?) {
        for id in ids where id != folder {
            update(id) { $0.parent = folder; $0.sharedWithMe = false }
        }
    }

    func copy(_ ids: [String]) {
        for id in ids {
            guard var copy = file(id) else { continue }
            copy.id = UUID().uuidString
            copy.name = "\(copy.name) copy"
            copy.modified = .now
            copy.starred = false
            copy.trashed = false
            copy.sharedWithMe = false
            copy.members = [owner]
            copy.revisions = copy.isFolder ? [] : [.now]
            files.append(copy)
        }
    }

    func setStarred(_ ids: [String], _ on: Bool) {
        for id in ids { update(id) { $0.starred = on } }
    }

    func trash(_ ids: [String]) {
        for id in ids { update(id) { $0.trashed = true } }
    }

    func restore(_ ids: [String]) {
        for id in ids { update(id) { $0.trashed = false } }
    }

    func deleteForever(_ id: String) {
        let gone = descendants(of: id).union([id])
        files.removeAll { gone.contains($0.id) }
    }

    // MARK: Sharing

    func share(_ id: String, with member: DriveMember) {
        update(id) { file in
            if let index = file.members.firstIndex(where: { $0.audience == member.audience && $0.address == member.address && $0.access != .owner }) {
                file.members[index].access = member.access
            } else {
                file.members.append(member)
            }
        }
    }

    func setAccess(_ id: String, member: String, to access: DriveAccess) {
        update(id) { file in
            if let index = file.members.firstIndex(where: { $0.id == member }) { file.members[index].access = access }
        }
    }

    func removeMember(_ id: String, member: String) {
        update(id) { file in file.members.removeAll { $0.id == member && $0.access != .owner } }
    }

    // MARK: Sheets

    func cells(_ id: String, tab: Int, range: DriveCellRange) -> [[String]] {
        let source: [[String]]
        if let file = file(id), tab >= 0, tab < file.sheets.count {
            source = file.sheets[tab].cells
        } else {
            source = []
        }
        return (0..<range.rows).map { r in
            (0..<range.columns).map { c in
                let row = range.top + r
                let column = range.left + c
                return row < source.count && column < source[row].count ? source[row][column] : ""
            }
        }
    }

    func saveCells(_ id: String, tab: Int, range: DriveCellRange, values: [[String]]) {
        update(id) { file in
            guard tab >= 0, tab < file.sheets.count else { return }
            var grid = file.sheets[tab].cells
            for (r, row) in values.enumerated() {
                let target = range.top + r
                while grid.count <= target { grid.append([]) }
                for (c, value) in row.enumerated() {
                    let column = range.left + c
                    while grid[target].count <= column { grid[target].append("") }
                    grid[target][column] = value
                }
            }
            file.sheets[tab].cells = grid
            file.modified = .now
            file.revisions.insert(.now, at: 0)
        }
    }

    // MARK: Forms

    func setFormTitle(_ id: String, _ title: String) {
        update(id) { $0.form?.title = title; $0.modified = .now }
    }

    func addQuestion(_ id: String, _ question: DriveQuestion) {
        update(id) { $0.form?.questions.append(question); $0.modified = .now }
    }

    func removeQuestion(_ id: String, question: String) {
        update(id) { file in file.form?.questions.removeAll { $0.id == question } }
    }

    func setPublished(_ id: String, _ on: Bool) {
        update(id) { $0.form?.published = on }
    }
}
