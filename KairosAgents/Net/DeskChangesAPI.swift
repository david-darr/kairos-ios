import Foundation

// The desktop's Forge review routes (routes/forge_routes.py over services/forge_sessions.py,
// forge_session_git.py, forge_git.py and forge_apps.py), as the phone reads them for a session's
// changes, diffs, Git sheet, files and app. Every /api/forge route answers an admin account only.
//
// - GET .../changes answers every changed file with its whole patch and its hunks (each with a `hash` of its
//   path and text). A revert names the hunk by that hash and carries `confirmed: true`; the desktop refuses
//   without it, and answers 409 when the hunk changed since.
// - GET .../git answers the branch, upstream, ahead and behind, the changed files and the branch names.
//   POST .../git runs stage, unstage, commit (the repository's own hooks run) and pull (the same). Push and
//   merge answer an approval stream, read with `deskForgeApprovalStream` from Net/DeskForgeAPI.swift.
//   There is no route for a session's commit log: only the project's own summary has the last commit.
// - GET .../files lists one folder; ignored files are never listed. GET .../file reads one file with the
//   `hash` and `mtime` it must be saved against. PUT .../file saves it: 409 when either changed, and
//   `overwrite` skips that check (the phone sends it only after the person confirms).
// - The phone never calls: create-branch or switch, the terminal routes, app start, PUT app/command.

// MARK: - Plain lists

/// A JSON list of text read item by item: one odd item is skipped, never the whole list.
nonisolated struct DeskChangesStrings: Decodable, Hashable, Sendable {
    var items: [String] = []

    init(from decoder: Decoder) throws {
        var list = try decoder.unkeyedContainer()
        while !list.isAtEnd {
            if let text = try? list.decode(String.self) {
                items.append(text)
            } else {
                _ = try list.decode(JSONValue.self)
            }
        }
    }
}

// MARK: - Changes

nonisolated struct DeskChangesHunkDTO: Decodable, Hashable, Sendable {
    /// sha256 of the path and the hunk's text: what a revert names.
    var hash: String
    var oldStart: Int?
    var newStart: Int?
    /// "@@ -12,4 +12,5 @@ section" and then its lines, each starting with a space, "+" or "-".
    var patch: String?

    private enum CodingKeys: String, CodingKey { case hash, oldStart, newStart, patch }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hash = try container.decode(String.self, forKey: .hash)
        oldStart = try? container.decodeIfPresent(Int.self, forKey: .oldStart)
        newStart = try? container.decodeIfPresent(Int.self, forKey: .newStart)
        patch = try? container.decodeIfPresent(String.self, forKey: .patch)
    }
}

/// One row of GET .../changes: a file changed since the session's base commit, or an untracked one.
nonisolated struct DeskChangesFileDTO: Decodable, Sendable {
    var path: String
    /// Null for a binary file or one that cannot be read.
    var added: Int?
    var removed: Int?
    var binary: Bool?
    var untracked: Bool?
    /// The file's whole patch, with its header. Read only for the kind of change.
    var patch: String?
    var hunks: DeskForgeList<DeskChangesHunkDTO>?
    /// Why the file cannot be shown or reverted (a link, an unsafe path).
    var unavailable: String?

    private enum CodingKeys: String, CodingKey { case path, added, removed, binary, untracked, patch, hunks, unavailable }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let given = try container.decode(String.self, forKey: .path)
        path = given
        added = try? container.decodeIfPresent(Int.self, forKey: .added)
        removed = try? container.decodeIfPresent(Int.self, forKey: .removed)
        binary = try? container.decodeIfPresent(Bool.self, forKey: .binary)
        untracked = try? container.decodeIfPresent(Bool.self, forKey: .untracked)
        // A secret file's text is never decoded, so it is never held in memory.
        if !DeskChangesWire.isSecret(given) {
            patch = try? container.decodeIfPresent(String.self, forKey: .patch)
            hunks = try? container.decodeIfPresent(DeskForgeList<DeskChangesHunkDTO>.self, forKey: .hunks)
        }
        unavailable = try? container.decodeIfPresent(String.self, forKey: .unavailable)
    }
}

nonisolated struct DeskChangesDTO: Decodable, Sendable {
    var baseCommit: String?
    var files: DeskForgeList<DeskChangesFileDTO>?

    private enum CodingKeys: String, CodingKey { case baseCommit, files }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseCommit = try? container.decodeIfPresent(String.self, forKey: .baseCommit)
        files = try? container.decodeIfPresent(DeskForgeList<DeskChangesFileDTO>.self, forKey: .files)
    }
}

// MARK: - Git

/// One changed file of GET .../git (forge_git.py: status_files): its status letters in the index and the tree.
nonisolated struct DeskChangesGitRowDTO: Decodable, Hashable, Sendable {
    var path: String
    var staged: Bool?
    var unstaged: Bool?
    /// A letter: M, A, D, R, C, or "?" for a file Git does not track yet.
    var index: String?
    var working: String?

    private enum CodingKeys: String, CodingKey { case path, staged, unstaged, index, working }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        staged = try? container.decodeIfPresent(Bool.self, forKey: .staged)
        unstaged = try? container.decodeIfPresent(Bool.self, forKey: .unstaged)
        index = try? container.decodeIfPresent(String.self, forKey: .index)
        working = try? container.decodeIfPresent(String.self, forKey: .working)
    }
}

/// GET and POST .../git (forge_session_git.py: status).
nonisolated struct DeskChangesGitDTO: Decodable, Sendable {
    var branch: String?
    /// "origin/main", or null when the branch was never pushed.
    var upstream: String?
    var ahead: Int?
    var behind: Int?
    var files: DeskForgeList<DeskChangesGitRowDTO>?
    var branches: DeskChangesStrings?
    /// The branch has work the base branch does not.
    var unmerged: Bool?

    private enum CodingKeys: String, CodingKey { case branch, upstream, ahead, behind, files, branches, unmerged }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        branch = try? container.decodeIfPresent(String.self, forKey: .branch)
        upstream = try? container.decodeIfPresent(String.self, forKey: .upstream)
        ahead = try? container.decodeIfPresent(Int.self, forKey: .ahead)
        behind = try? container.decodeIfPresent(Int.self, forKey: .behind)
        files = try? container.decodeIfPresent(DeskForgeList<DeskChangesGitRowDTO>.self, forKey: .files)
        branches = try? container.decodeIfPresent(DeskChangesStrings.self, forKey: .branches)
        unmerged = try? container.decodeIfPresent(Bool.self, forKey: .unmerged)
    }
}

// MARK: - Files

nonisolated struct DeskChangesEntryDTO: Decodable, Hashable, Sendable {
    var name: String?
    /// Relative to the session's folder, with forward slashes.
    var path: String
    var directory: Bool?
    var changed: Bool?
    /// Not sent today (ignored files are not listed at all); read in case a desktop marks them.
    var ignored: Bool?

    private enum CodingKeys: String, CodingKey { case name, path, directory, changed, ignored }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        directory = try? container.decodeIfPresent(Bool.self, forKey: .directory)
        changed = try? container.decodeIfPresent(Bool.self, forKey: .changed)
        ignored = try? container.decodeIfPresent(Bool.self, forKey: .ignored)
    }
}

/// GET .../files?path=: one folder's entries, folders first.
nonisolated struct DeskChangesFolderDTO: Decodable, Sendable {
    var path: String?
    var entries: DeskForgeList<DeskChangesEntryDTO>?

    private enum CodingKeys: String, CodingKey { case path, entries }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try? container.decodeIfPresent(String.self, forKey: .path)
        entries = try? container.decodeIfPresent(DeskForgeList<DeskChangesEntryDTO>.self, forKey: .entries)
    }
}

/// GET and PUT .../file (forge_sessions.py: _editor_file): the text, with the `hash` and `mtime` a save needs.
nonisolated struct DeskChangesFileTextDTO: Decodable, Sendable {
    var path: String?
    var content: String?
    var binary: Bool?
    var hash: String?
    var mtime: String?

    private enum CodingKeys: String, CodingKey { case path, content, binary, hash, mtime }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try? container.decodeIfPresent(String.self, forKey: .path)
        content = try? container.decodeIfPresent(String.self, forKey: .content)
        binary = try? container.decodeIfPresent(Bool.self, forKey: .binary)
        hash = try? container.decodeIfPresent(String.self, forKey: .hash)
        mtime = try? container.decodeIfPresent(String.self, forKey: .mtime)
    }
}

// MARK: - App

/// GET .../app/status and POST .../app/stop (forge_apps.py: status). The page address is never read:
/// the app listens on the desktop only.
nonisolated struct DeskChangesAppDTO: Decodable, Hashable, Sendable {
    var sessionId: String?
    var running: Bool?
    var ready: Bool?
    var port: Int?
    var startedAt: Double?
    var exitCode: Int?

    private enum CodingKeys: String, CodingKey { case sessionId, running, ready, port, startedAt, exitCode }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try? container.decodeIfPresent(String.self, forKey: .sessionId)
        running = try? container.decodeIfPresent(Bool.self, forKey: .running)
        ready = try? container.decodeIfPresent(Bool.self, forKey: .ready)
        port = try? container.decodeIfPresent(Int.self, forKey: .port)
        startedAt = try? container.decodeIfPresent(Double.self, forKey: .startedAt)
        exitCode = try? container.decodeIfPresent(Int.self, forKey: .exitCode)
    }
}

/// GET .../app/logs: the app's last lines, newest last.
nonisolated struct DeskChangesLogsDTO: Decodable, Sendable {
    var lines: DeskChangesStrings?

    private enum CodingKeys: String, CodingKey { case lines }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lines = try? container.decodeIfPresent(DeskChangesStrings.self, forKey: .lines)
    }
}

// MARK: - What the screens show

nonisolated struct DeskChangesLine: Identifiable, Hashable, Sendable {
    let id: String
    var kind: DiffKind
    var old: Int?
    var new: Int?
    var text: String
}

/// One block of a file's diff, keyed by the desktop's own hash.
nonisolated struct DeskChangesHunk: Identifiable, Hashable, Sendable {
    var id: String { hash }
    var hash: String
    var header: String
    var lines: [DeskChangesLine]
    var added: Int
    var removed: Int
}

/// One changed file, keyed by its path.
nonisolated struct DeskChangesFile: Identifiable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var mark: ChangeMark
    var added: Int?
    var removed: Int?
    var binary: Bool
    /// A file that can hold secrets: its text is never read onto the phone.
    var secret: Bool
    var hunks: [DeskChangesHunk]
    var unavailable: String?
    /// Some blocks were left out because the diff is long.
    var truncated: Bool

    var name: String { path.split(separator: "/").last.map(String.init) ?? path }
    /// Whole-file revert is offered for this file.
    var canRevert: Bool { !secret && unavailable == nil }
}

nonisolated struct DeskChangesGitFile: Identifiable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var mark: ChangeMark
}

nonisolated struct DeskChangesGit: Hashable, Sendable {
    var branch: String
    var upstream: String?
    var ahead: Int
    var behind: Int
    var staged: [DeskChangesGitFile]
    var unstaged: [DeskChangesGitFile]
    var branches: [String]
    var unmerged: Bool

    /// What a write was sent against: compared again after a lost answer.
    var signature: String {
        "\(branch)|\(ahead)|\(behind)|" + staged.map(\.path).sorted().joined(separator: ",")
            + "|" + unstaged.map(\.path).sorted().joined(separator: ",")
    }
}

nonisolated struct DeskChangesEntry: Identifiable, Hashable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var directory: Bool
    var changed: Bool
    /// Never opened on the phone: shown without a link.
    var secret: Bool
}

// MARK: - Wire helpers

nonisolated enum DeskChangesWire {
    static let secretLine = "Open this file in Kairos on your desktop."
    /// Changed lines shown for one file. Longer diffs are cut at a whole block and say so.
    static let maxLines = 3000

    /// A path that can hold secrets, tested on every part of it, lowercased. A name is secret when it starts
    /// or ends with `.env`, contains `credential`, `secret`, `password` or `passwd`, ends with `.pem`, `.key`,
    /// `.p12`, `.pfx`, `.keystore`, `.jks` or `.kdbx`, starts with `id_rsa`, `id_ed25519`, `id_ecdsa` or
    /// `id_dsa`, or is `.npmrc`, `.netrc`, `.pgpass` or `.htpasswd`. A path with a `.ssh`, `.aws`, `.gnupg` or
    /// `.kube` folder is secret whole.
    static func isSecret(_ path: String) -> Bool {
        let endings = [".env", ".pem", ".key", ".p8", ".p12", ".pfx", ".keystore", ".jks", ".kdbx", ".tfvars"]
        let starts = [".env", "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa"]
        let words = ["credential", "secret", "password", "passwd", "service-account", "service_account"]
        let names = [".npmrc", ".netrc", ".pgpass", ".htpasswd", ".pypirc", "token.json", "tokens.json"]
        let folders = [".ssh", ".aws", ".gnupg", ".kube", ".docker"]
        for part in path.split(whereSeparator: { $0 == "/" || $0 == "\\" }) {
            let name = part.lowercased()
            if folders.contains(name) || names.contains(name) { return true }
            if starts.contains(where: { name.hasPrefix($0) }) || endings.contains(where: { name.hasSuffix($0) })
                || words.contains(where: { name.contains($0) }) {
                return true
            }
        }
        return false
    }

    /// A path that goes safely into a request's address. One that could be read as two values is not sent.
    static func pathOK(_ path: String) -> Bool {
        !path.isEmpty && !path.contains("&") && !path.contains("=")
            && !path.unicodeScalars.contains { $0.value < 32 }
    }

    static func gitMark(_ letter: String?) -> ChangeMark {
        switch letter {
        case "A": return .added
        case "D": return .deleted
        case "?": return .untracked
        default: return .modified
        }
    }

    /// What kind of change a changed file is, from the header of its patch.
    static func mark(of row: DeskChangesFileDTO) -> ChangeMark {
        if row.untracked == true { return .untracked }
        for line in (row.patch ?? "").prefix(2000).split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") { break }
            if line.hasPrefix("new file mode") { return .added }
            if line.hasPrefix("deleted file mode") { return .deleted }
        }
        return .modified
    }

    /// "@@ -12,4 +12,5 @@ section": where its old and new lines start.
    static func starts(_ header: String) -> (old: Int, new: Int)? {
        let parts = header.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "@@", parts[1].hasPrefix("-"), parts[2].hasPrefix("+") else { return nil }
        func first(_ part: Substring) -> Int? {
            Int(part.dropFirst().split(separator: ",").first ?? "")
        }
        guard let old = first(parts[1]), let new = first(parts[2]) else { return nil }
        return (old, new)
    }

    /// One block as header, numbered lines and counts. A block that is not a block gives nil.
    static func hunk(_ dto: DeskChangesHunkDTO) -> DeskChangesHunk? {
        guard let patch = dto.patch else { return nil }
        var rows = patch.components(separatedBy: "\n")
        if rows.last == "" { rows.removeLast() }
        guard let head = rows.first, head.hasPrefix("@@") else { return nil }
        let parsed = starts(head)
        var old = dto.oldStart ?? parsed?.old ?? 1
        var new = dto.newStart ?? parsed?.new ?? 1
        var lines: [DeskChangesLine] = []
        var added = 0
        var removed = 0
        for raw in rows.dropFirst() {
            var text = raw
            if text.hasSuffix("\r") { text.removeLast() }
            let id = "l\(lines.count)"
            guard let marker = text.first else {
                lines.append(DeskChangesLine(id: id, kind: .context, old: old, new: new, text: ""))
                old += 1
                new += 1
                continue
            }
            let body = String(text.dropFirst())
            switch marker {
            case "+":
                lines.append(DeskChangesLine(id: id, kind: .add, old: nil, new: new, text: body))
                new += 1
                added += 1
            case "-":
                lines.append(DeskChangesLine(id: id, kind: .remove, old: old, new: nil, text: body))
                old += 1
                removed += 1
            case "\\":
                // "\ No newline at end of file" belongs to the line before it.
                continue
            default:
                lines.append(DeskChangesLine(id: id, kind: .context, old: old, new: new, text: body))
                old += 1
                new += 1
            }
        }
        return DeskChangesHunk(hash: dto.hash, header: head.trimmingCharacters(in: .whitespaces),
                               lines: lines, added: added, removed: removed)
    }

    static func file(_ row: DeskChangesFileDTO) -> DeskChangesFile {
        let secret = isSecret(row.path)
        var result = DeskChangesFile(path: row.path, mark: mark(of: row), added: row.added, removed: row.removed,
                                     binary: row.binary ?? false, secret: secret, hunks: [],
                                     unavailable: row.unavailable, truncated: false)
        // A secret file's text is dropped here, so it is never kept on the phone.
        if secret || result.binary || row.unavailable != nil { return result }
        var budget = maxLines
        var seen = Set<String>()
        for item in row.hunks?.items ?? [] {
            guard !seen.contains(item.hash), let block = hunk(item) else { continue }
            if block.lines.count > budget {
                result.truncated = true
                break
            }
            budget -= block.lines.count
            seen.insert(item.hash)
            result.hunks.append(block)
        }
        return result
    }

    static func changes(_ dto: DeskChangesDTO) -> (files: [DeskChangesFile], skipped: Int) {
        var seen = Set<String>()
        var files: [DeskChangesFile] = []
        for row in dto.files?.items ?? [] {
            if seen.insert(row.path).inserted { files.append(file(row)) }
        }
        return (files, dto.files?.skipped ?? 0)
    }

    static func git(_ dto: DeskChangesGitDTO) -> DeskChangesGit {
        var staged: [DeskChangesGitFile] = []
        var unstaged: [DeskChangesGitFile] = []
        var seenStaged = Set<String>()
        var seenUnstaged = Set<String>()
        for row in dto.files?.items ?? [] {
            if row.staged == true, seenStaged.insert(row.path).inserted {
                staged.append(DeskChangesGitFile(path: row.path, mark: gitMark(row.index)))
            }
            if row.unstaged == true, seenUnstaged.insert(row.path).inserted {
                let untracked = row.working == "?" || row.index == "?"
                unstaged.append(DeskChangesGitFile(path: row.path, mark: untracked ? .untracked : gitMark(row.working)))
            }
        }
        return DeskChangesGit(branch: dto.branch ?? "", upstream: (dto.upstream ?? "").isEmpty ? nil : dto.upstream,
                              ahead: dto.ahead ?? 0, behind: dto.behind ?? 0, staged: staged, unstaged: unstaged,
                              branches: dto.branches?.items ?? [], unmerged: dto.unmerged ?? false)
    }

    static func entries(_ dto: DeskChangesFolderDTO) -> [DeskChangesEntry] {
        var seen = Set<String>()
        var result: [DeskChangesEntry] = []
        for item in dto.entries?.items ?? [] {
            guard !item.path.isEmpty, seen.insert(item.path).inserted else { continue }
            let given = item.name ?? ""
            let name = given.isEmpty ? (item.path.split(separator: "/").last.map(String.init) ?? item.path) : given
            result.append(DeskChangesEntry(name: name, path: item.path, directory: item.directory ?? false,
                                           changed: item.changed ?? false,
                                           secret: isSecret(item.path) || item.ignored == true))
        }
        return result
    }
}

// MARK: - Calls

extension APIClient {

    private func deskChangesBase(_ sessionID: String) throws -> String {
        "/api/forge/sessions/" + (try DeskForgeWire.pathID(sessionID))
    }

    /// GET /api/forge/sessions/{id}/changes.
    func deskChangesList(_ sessionID: String) async throws -> DeskChangesDTO {
        try await get(try deskChangesBase(sessionID) + "/changes")
    }

    /// POST .../revert-file with `confirmed`: puts the file back to the session's start (an untracked or added
    /// file is deleted). 409 when it changed in a way the desktop cannot undo.
    func deskChangesRevertFile(_ sessionID: String, path: String) async throws -> DeskForgeOkDTO {
        try await post(try deskChangesBase(sessionID) + "/revert-file", json: ["path": path, "confirmed": true])
    }

    /// POST .../revert-hunk with the hunk's hash and `confirmed`. 409 when the hunk is not there any more.
    func deskChangesRevertHunk(_ sessionID: String, path: String, hash: String) async throws -> DeskForgeOkDTO {
        try await post(try deskChangesBase(sessionID) + "/revert-hunk",
                       json: ["path": path, "hunk_hash": hash, "confirmed": true])
    }

    /// GET .../git.
    func deskChangesGit(_ sessionID: String) async throws -> DeskChangesGitDTO {
        try await get(try deskChangesBase(sessionID) + "/git")
    }

    /// POST .../git with "stage", "unstage", "commit" or "pull": the answer is the status after it. The phone
    /// never sends "create-branch", "switch", "push" or "merge" through here.
    func deskChangesGitAction(_ sessionID: String, action: String, path: String? = nil,
                              message: String? = nil) async throws -> DeskChangesGitDTO {
        var body: [String: Any] = ["action": action]
        if let path { body["path"] = path }
        if let message { body["message"] = message }
        return try await post(try deskChangesBase(sessionID) + "/git", json: body)
    }

    /// POST .../git with "push" or "merge": an approval stream, read by the caller.
    func deskChangesGitStream(_ sessionID: String, action: String) async throws -> URLSession.AsyncBytes {
        try await deskForgeApprovalStream(try deskChangesBase(sessionID) + "/git", json: ["action": action])
    }

    /// GET .../files?path=: one folder.
    func deskChangesFolder(_ sessionID: String, path: String) async throws -> DeskChangesFolderDTO {
        try await get(try deskChangesBase(sessionID) + "/files", query: ["path": path])
    }

    /// GET .../file?path=.
    func deskChangesFile(_ sessionID: String, path: String) async throws -> DeskChangesFileTextDTO {
        try await get(try deskChangesBase(sessionID) + "/file", query: ["path": path])
    }

    /// PUT .../file with the `hash` and `mtime` the text was read with. `overwrite` is sent only when true.
    func deskChangesSave(_ sessionID: String, path: String, content: String, hash: String, mtime: String,
                         overwrite: Bool) async throws -> DeskChangesFileTextDTO {
        var body: [String: Any] = ["path": path, "content": content, "hash": hash, "mtime": mtime]
        if overwrite { body["overwrite"] = true }
        return try await request("PUT", try deskChangesBase(sessionID) + "/file", json: body)
    }

    /// GET .../app/status.
    func deskChangesAppStatus(_ sessionID: String) async throws -> DeskChangesAppDTO {
        try await get(try deskChangesBase(sessionID) + "/app/status")
    }

    /// GET .../app/logs: the last 200 lines.
    func deskChangesAppLogs(_ sessionID: String) async throws -> DeskChangesLogsDTO {
        try await get(try deskChangesBase(sessionID) + "/app/logs", query: ["limit": "200"])
    }

    /// POST .../app/stop: stops the app and answers its status.
    func deskChangesAppStop(_ sessionID: String) async throws -> DeskChangesAppDTO {
        try await post(try deskChangesBase(sessionID) + "/app/stop")
    }

    /// POST .../app/restart: stops the app and starts it again; an approval stream when the command needs approving.
    func deskChangesAppRestart(_ sessionID: String) async throws -> URLSession.AsyncBytes {
        try await deskForgeApprovalStream(try deskChangesBase(sessionID) + "/app/restart", json: nil)
    }
}

// MARK: - Samples

/// A sample answer for every review route the phone reads, shaped like the desktop's own (made-up content).
nonisolated enum DeskChangesSamples {

    static let changes = #"""
    {"base_commit": "9f1c2ab",
     "files": [
       {"path": "src/styles/layout.css", "added": 3, "removed": 2, "binary": false, "untracked": false,
        "patch": "diff --git a/src/styles/layout.css b/src/styles/layout.css\nindex 1a2b3c4..5d6e7f8 100644\n--- a/src/styles/layout.css\n+++ b/src/styles/layout.css\n@@ -12,4 +12,5 @@ .page\n .page {\n-  display: grid;\n+  display: flex;\n+  gap: 16px;\n   padding: 24px;\n }\n@@ -40,3 +41,3 @@ .card\n .card {\n-  width: 320px;\n+  width: 100%;\n }\n",
        "hunks": [
          {"hash": "aa11", "old_start": 12, "old_count": 4, "new_start": 12, "new_count": 5,
           "patch": "@@ -12,4 +12,5 @@ .page\n .page {\n-  display: grid;\n+  display: flex;\n+  gap: 16px;\n   padding: 24px;\n }\n"},
          {"hash": "bb22", "old_start": 40, "old_count": 3, "new_start": 41, "new_count": 3,
           "patch": "@@ -40,3 +41,3 @@ .card\n .card {\n-  width: 320px;\n+  width: 100%;\n }\n\\ No newline at end of file\n"},
          {"patch": "a hunk with no hash"},
          {"hash": "cc33", "patch": "not a hunk"}
        ]},
       {"path": ".env.local", "added": 1, "removed": 0, "binary": false, "untracked": true,
        "patch": "diff --git a/.env.local b/.env.local\nnew file mode 100644\n--- /dev/null\n+++ b/.env.local\n@@ -0,0 +1 @@\n+EXAMPLE_VALUE=not-a-real-secret\n",
        "hunks": [{"hash": "dd44", "old_start": 0, "new_start": 1, "patch": "@@ -0,0 +1 @@\n+EXAMPLE_VALUE=not-a-real-secret\n"}]},
       {"path": "public/hero.png", "added": null, "removed": null, "binary": true, "untracked": false,
        "patch": "diff --git a/public/hero.png b/public/hero.png\nBinary files a/public/hero.png and b/public/hero.png differ\n", "hunks": []},
       {"path": "old/legacy.js", "added": 0, "removed": 2, "binary": false, "untracked": false,
        "patch": "diff --git a/old/legacy.js b/old/legacy.js\ndeleted file mode 100644\n--- a/old/legacy.js\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-var a = 1;\n-var b = 2;\n",
        "hunks": [{"hash": "ee55", "old_start": 1, "old_count": 2, "new_start": 0, "new_count": 0,
                   "patch": "@@ -1,2 +0,0 @@\n-var a = 1;\n-var b = 2;\n"}]},
       {"path": "src/new.ts", "added": 2, "removed": 0, "binary": false, "untracked": true,
        "patch": "diff --git a/src/new.ts b/src/new.ts\nnew file mode 100644\n--- /dev/null\n+++ b/src/new.ts\n@@ -0,0 +1,2 @@\n+export const x = 1\n+export const y = 2\n",
        "hunks": [{"hash": "ff66", "old_start": 0, "new_start": 1, "patch": "@@ -0,0 +1,2 @@\n+export const x = 1\n+export const y = 2\n"}]},
       {"added": 1}
     ]}
    """#

    static let git = #"""
    {"branch": "forge/mobile-layout-a1b2c3", "upstream": null, "ahead": 2, "behind": 0, "unmerged": true,
     "files": [
       {"path": "src/a.css", "original": null, "staged": true, "unstaged": false, "index": "M", "working": " "},
       {"path": "src/b.tsx", "original": null, "staged": false, "unstaged": true, "index": " ", "working": "M"},
       {"path": "notes.txt", "original": null, "staged": false, "unstaged": true, "index": "?", "working": "?"},
       {"path": "src/c.ts", "original": null, "staged": true, "unstaged": true, "index": "A", "working": "M"},
       {"x": 1}
     ],
     "branches": ["main", "forge/mobile-layout-a1b2c3", 5]}
    """#

    static let gitPushed = #"""
    {"branch": "forge/mobile-layout-a1b2c3", "upstream": "origin/forge/mobile-layout-a1b2c3", "ahead": 0, "behind": 1,
     "files": [], "branches": ["main", "forge/mobile-layout-a1b2c3"], "unmerged": true}
    """#

    static let folder = #"""
    {"path": "", "entries": [
      {"name": "src", "path": "src", "directory": true, "changed": true},
      {"name": "README.md", "path": "README.md", "directory": false, "changed": false},
      {"name": ".env.production", "path": ".env.production", "directory": false, "changed": false},
      {"name": "deploy.key", "path": "keys/deploy.key", "directory": false, "changed": false},
      {"name": "notes.txt", "path": "notes.txt", "directory": false, "changed": true, "ignored": true},
      {"name": 5}
    ]}
    """#

    static let file = #"""
    {"path": "src/components/NavBar.tsx", "content": "export function NavBar() {\n  return null\n}\n", "binary": false,
     "hash": "9c0d5e3a77b1", "mtime": "1793100900123456789"}
    """#

    static let binaryFile = #"""
    {"path": "public/hero.png", "content": "", "binary": true, "hash": "00ff", "mtime": "1793100000000000000"}
    """#

    static let saved = #"""
    {"path": "src/components/NavBar.tsx", "content": "export function NavBar() {\n  return 1\n}\n", "binary": false,
     "hash": "1d2e3f4a5b6c", "mtime": "1793101200987654321"}
    """#

    static let conflict = #"{"detail": "This file changed on disk. Reload it or overwrite with your edits."}"#

    static let appStatus = #"""
    {"session_id": "5b9e2f0a4c18", "project_id": "3f2a9c1b7d04", "command": "npm run dev -- --port 51734",
     "running": true, "ready": true, "port": 51734, "ports": [51734], "url": "http://127.0.0.1:51734/",
     "exit_code": null, "started_at": 1793100700.5}
    """#

    static let appStopped = #"{"session_id": "5b9e2f0a4c18", "running": false, "ready": false, "ports": []}"#

    static let logs = #"""
    {"session_id": "5b9e2f0a4c18", "lines": ["vite v6 dev server running", "page reload src/styles/layout.css", 7, "GET /products 200 in 18 ms"]}
    """#

    static let pushAsk = #"""
    {"permission": {"kind": "permission", "id": "0f9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c", "tool": "forge_git_push",
      "target": "Push forge/mobile-layout-a1b2c3 to origin (https://alex:hunter2@example.com/shop/site.git), branch forge/mobile-layout-a1b2c3.",
      "title": "Push branch?",
      "description": "Push forge/mobile-layout-a1b2c3 to origin (https://alex:hunter2@example.com/shop/site.git), branch forge/mobile-layout-a1b2c3.",
      "arguments": {"remote": "origin", "url": "https://alex:hunter2@example.com/shop/site.git", "branch": "forge/mobile-layout-a1b2c3"},
      "choices": [{"id": "once", "label": "Approve", "behavior": "allow", "scope": "once"},
                  {"id": "reject", "label": "Cancel", "behavior": "deny", "scope": "once"}],
      "expires_at": 1793100820.0}}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("deskchanges.changes") {
            let read = try KJSON.decode(DeskChangesDTO.self, from: DeskChangesSamples.changes)
            let mapped = DeskChangesWire.changes(read)
            guard mapped.files.count == 5, mapped.skipped == 1, read.baseCommit == "9f1c2ab" else {
                throw SampleMismatch("changed files")
            }
            let css = mapped.files[0]
            guard css.path == "src/styles/layout.css", css.mark == .modified, css.added == 3, css.removed == 2,
                  css.hunks.count == 2, css.hunks[0].hash == "aa11", css.hunks[1].hash == "bb22",
                  css.hunks[0].lines.count == 6, css.hunks[0].added == 2, css.hunks[0].removed == 1,
                  css.hunks[0].header == "@@ -12,4 +12,5 @@ .page",
                  // Old and new line numbers move the way a diff's do.
                  css.hunks[0].lines[0].old == 12, css.hunks[0].lines[0].new == 12,
                  css.hunks[0].lines[1].kind == .remove, css.hunks[0].lines[1].old == 13, css.hunks[0].lines[1].new == nil,
                  css.hunks[0].lines[2].kind == .add, css.hunks[0].lines[2].new == 13,
                  css.hunks[0].lines[4].old == 14, css.hunks[0].lines[4].new == 15,
                  css.hunks[0].lines[4].text == "  padding: 24px;",
                  // "\ No newline at end of file" is not a line.
                  css.hunks[1].lines.count == 4, !css.truncated, css.canRevert else {
                throw SampleMismatch("css fields")
            }
            // A secret file keeps its path and counts and never its text.
            let env = mapped.files[1]
            guard env.secret, env.mark == .untracked, env.hunks.isEmpty, !env.canRevert,
                  mapped.files[2].binary, mapped.files[2].added == nil, mapped.files[2].hunks.isEmpty,
                  mapped.files[3].mark == .deleted, mapped.files[3].hunks.first?.lines.count == 2,
                  mapped.files[3].hunks.first?.lines.first?.old == 1,
                  mapped.files[4].mark == .untracked, mapped.files[4].hunks.first?.lines.last?.new == 2 else {
                throw SampleMismatch("other files")
            }
            return "5 files, 1 skipped, hunks keyed by hash, secret text dropped"
        },
        DecodeCheck("deskchanges.git") {
            let read = try KJSON.decode(DeskChangesGitDTO.self, from: DeskChangesSamples.git)
            let git = DeskChangesWire.git(read)
            let pushed = DeskChangesWire.git(try KJSON.decode(DeskChangesGitDTO.self, from: DeskChangesSamples.gitPushed))
            guard git.branch == "forge/mobile-layout-a1b2c3", git.upstream == nil, git.ahead == 2, git.behind == 0,
                  git.unmerged, read.files?.skipped == 1, read.branches?.items.count == 2,
                  git.staged.map(\.path) == ["src/a.css", "src/c.ts"],
                  git.unstaged.map(\.path) == ["src/b.tsx", "notes.txt", "src/c.ts"],
                  git.staged[1].mark == .added, git.unstaged[1].mark == .untracked, git.unstaged[2].mark == .modified,
                  pushed.upstream == "origin/forge/mobile-layout-a1b2c3", pushed.behind == 1, pushed.staged.isEmpty,
                  git.signature != pushed.signature else {
                throw SampleMismatch("git fields")
            }
            return "status, 2 staged, 3 unstaged, 1 row skipped"
        },
        DecodeCheck("deskchanges.files") {
            let folder = try KJSON.decode(DeskChangesFolderDTO.self, from: DeskChangesSamples.folder)
            let rows = DeskChangesWire.entries(folder)
            let file = try KJSON.decode(DeskChangesFileTextDTO.self, from: DeskChangesSamples.file)
            let binary = try KJSON.decode(DeskChangesFileTextDTO.self, from: DeskChangesSamples.binaryFile)
            let saved = try KJSON.decode(DeskChangesFileTextDTO.self, from: DeskChangesSamples.saved)
            let refused = try KJSON.decode(APIErrorBody.self, from: DeskChangesSamples.conflict)
            guard rows.count == 5, folder.entries?.skipped == 1, rows[0].directory, rows[0].changed, !rows[0].secret,
                  !rows[1].secret, rows[2].secret, rows[3].secret, rows[3].name == "deploy.key",
                  // An entry the desktop marks as ignored is never opened.
                  rows[4].secret,
                  file.hash == "9c0d5e3a77b1", file.mtime == "1793100900123456789", file.binary == false,
                  file.content?.hasPrefix("export function NavBar") == true,
                  binary.binary == true, binary.content == "",
                  saved.hash != file.hash, saved.content?.contains("return 1") == true,
                  refused.text.hasPrefix("This file changed on disk") else {
                throw SampleMismatch("file fields")
            }
            for name in [".env", ".env.local", "config/.env.production", "tls/server.pem", "a/b/deploy.KEY", "x.p12", "x.pfx",
                         "id_rsa", "id_rsa.pub", "id_ed25519", "ci.keystore", "credentials.json", "aws/credentials",
                         "secrets.yml", "secrets/token.txt", ".npmrc", ".netrc",
                         "prod.env", "config/local.env", "aws_credentials", "gcp-credentials.json",
                         "client_secret.json", "app-secrets.yml", "Config/PROD.ENV", "db/passwords.txt",
                         "etc/passwd", "ci/vault.jks", "home/store.kdbx", "keys/id_ecdsa", "keys/id_dsa.pub",
                         ".pgpass", "web/.htpasswd", ".ssh/config", "home/.aws/config", "x/.gnupg/pubring.txt",
                         ".kube/config", "src/.SSH/notes.txt"] {
                guard DeskChangesWire.isSecret(name) else { throw SampleMismatch("secret name " + name) }
            }
            for name in ["README.md", "src/environment.ts", "src/keys.ts", "docs/key-ideas.md", "src/main.tsx", "package.json",
                         "src/environment.ts", "docs/ssh-notes.md", "src/aws.ts"] {
                guard !DeskChangesWire.isSecret(name) else { throw SampleMismatch("plain name " + name) }
            }
            guard DeskChangesWire.pathOK("src/My File.tsx"), !DeskChangesWire.pathOK("a&b.txt"),
                  !DeskChangesWire.pathOK("a=b.txt"), !DeskChangesWire.pathOK("") else {
                throw SampleMismatch("path check")
            }
            return "folder, file, save, conflict, secret names"
        },
        DecodeCheck("deskchanges.app") {
            let running = try KJSON.decode(DeskChangesAppDTO.self, from: DeskChangesSamples.appStatus)
            let stopped = try KJSON.decode(DeskChangesAppDTO.self, from: DeskChangesSamples.appStopped)
            let logs = try KJSON.decode(DeskChangesLogsDTO.self, from: DeskChangesSamples.logs)
            let ask = try KJSON.decode(DeskForgeStreamPacketDTO.self, from: DeskChangesSamples.pushAsk)
            guard running.running == true, running.ready == true, running.port == 51734, running.startedAt == 1793100700.5,
                  running.exitCode == nil, stopped.running == false, stopped.port == nil,
                  logs.lines?.items.count == 3, logs.lines?.items.last == "GET /products 200 in 18 ms",
                  ask.permission?.tool == "forge_git_push", !ask.finished,
                  ask.permission?.choices?.count == 2 else {
                throw SampleMismatch("app fields")
            }
            return "status, stopped, 3 log lines, push request"
        },
    ]
}
