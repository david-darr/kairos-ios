import Foundation

// The desktop's workspace browse route (routes/workspace_routes.py over core/workspace.py: browse_dir), as the phone
// lists the folders of the PC. The route answers an admin account only.
//
// - GET /api/workspace/browse?path= lists the folders inside `path` (the home folder when it is empty, and also
//   when `path` is not a folder: the answer's `path` is what was really listed, so it is shown, not assumed).
//   Folders only: hidden folders and linked folders are skipped, files are never listed, 500 folders at most.
// - There is no route that lists files, reads one, opens one on the PC or sends one. The phone has none of those.
// - Browse (tabs, history, downloads, site settings) has no route, and the saved-passwords routes are never called:
//   there is no function here for any of them.

// MARK: - The answer

nonisolated struct DeskFilesDirDTO: Decodable, Hashable, Sendable {
    var name: String?
    /// The folder's whole path on the PC.
    var path: String

    private enum CodingKeys: String, CodingKey { case name, path }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
    }
}

/// GET /api/workspace/browse. `selectable` (whether the folder can be a Forge workspace) is not read.
nonisolated struct DeskFilesFolderDTO: Decodable, Sendable {
    var path: String?
    /// The folder above, or null at the top of a drive.
    var parent: String?
    var dirs: DeskForgeList<DeskFilesDirDTO>?
    var truncated: Bool?

    private enum CodingKeys: String, CodingKey { case path, parent, dirs, truncated }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try? container.decodeIfPresent(String.self, forKey: .path)
        parent = try? container.decodeIfPresent(String.self, forKey: .parent)
        dirs = try? container.decodeIfPresent(DeskForgeList<DeskFilesDirDTO>.self, forKey: .dirs)
        truncated = try? container.decodeIfPresent(Bool.self, forKey: .truncated)
    }
}

// MARK: - What the screen shows

nonisolated struct DeskFilesDir: Identifiable, Hashable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    /// A name that cannot go into the request's address is shown without a link.
    var openable: Bool
}

nonisolated struct DeskFilesFolder: Sendable {
    var load: DeskForgeLoad = .idle
    /// The folder the desktop really listed.
    var path = ""
    var parent: String?
    var dirs: [DeskFilesDir] = []
    var truncated = false
    var skipped = 0
    /// The desktop listed a different folder than the one asked for.
    var differs = false
}

// MARK: - Wire helpers

nonisolated enum DeskFilesWire {
    /// The most folders the desktop sends.
    static let limit = 500

    /// A path that goes safely into a request's address. One that could be read as two values is not sent.
    static func pathOK(_ path: String) -> Bool {
        !path.contains("&") && !path.contains("=") && !path.contains("#")
            && !path.unicodeScalars.contains { $0.value < 32 }
    }

    /// The last part of a path, whichever slash the PC uses.
    static func lastName(_ path: String) -> String {
        let parts = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        return parts.last.map(String.init) ?? path
    }

    /// A path compared without case, slash direction or a closing slash.
    static func same(_ left: String, _ right: String) -> Bool {
        func key(_ text: String) -> String {
            var value = text.replacingOccurrences(of: "\\", with: "/").lowercased()
            while value.count > 1, value.hasSuffix("/") { value.removeLast() }
            return value
        }
        return key(left) == key(right)
    }

    static func folder(_ dto: DeskFilesFolderDTO, asked: String) -> DeskFilesFolder {
        var seen = Set<String>()
        var rows: [DeskFilesDir] = []
        for item in dto.dirs?.items ?? [] where !item.path.isEmpty && seen.insert(item.path).inserted {
            let given = (item.name ?? "").trimmingCharacters(in: .whitespaces)
            let name = given.isEmpty ? lastName(item.path) : given
            rows.append(DeskFilesDir(name: name, path: item.path, openable: pathOK(item.path)))
        }
        let shown = dto.path ?? ""
        let parent = (dto.parent ?? "").isEmpty ? nil : dto.parent
        return DeskFilesFolder(load: .loaded, path: shown, parent: parent, dirs: rows, truncated: dto.truncated ?? false,
                               skipped: dto.dirs?.skipped ?? 0,
                               differs: !asked.isEmpty && !shown.isEmpty && !same(asked, shown))
    }

    /// A refusal as one plain sentence for a person.
    static func words(_ error: Error) -> String {
        if let api = error as? APIError, case .server(let status, _) = api, status == 403 {
            return "Files on this PC need an admin account on your desktop."
        }
        return error.plainWords
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/workspace/browse: the folders inside one folder, read only. An empty path is the home folder.
    func deskFilesBrowse(_ path: String) async throws -> DeskFilesFolderDTO {
        let query: [String: String?] = path.isEmpty ? [:] : ["path": path]
        return try await get("/api/workspace/browse", query: query)
    }
}

// MARK: - Samples

/// Sample answers for the folder route, shaped like the desktop's own (made-up content).
nonisolated enum DeskFilesSamples {

    static let home = #"""
    {"path": "C:\\Users\\sample", "parent": "C:\\Users", "truncated": false, "selectable": true,
     "dirs": [{"name": "Documents", "path": "C:\\Users\\sample\\Documents"},
              {"name": "Projects", "path": "C:\\Users\\sample\\Projects"},
              {"name": "R&D notes", "path": "C:\\Users\\sample\\R&D notes"},
              {"path": "C:\\Users\\sample\\Music"},
              {"name": "Duplicate", "path": "C:\\Users\\sample\\Music"},
              {"name": 5}]}
    """#

    static let top = #"""
    {"path": "C:\\", "parent": null, "dirs": [], "truncated": true, "selectable": false}
    """#

    static let forbidden = #"{"detail": "admin privileges required"}"#

    static let checks: [DecodeCheck] = [
        DecodeCheck("deskfiles.folder") {
            let read = try KJSON.decode(DeskFilesFolderDTO.self, from: DeskFilesSamples.home)
            let folder = DeskFilesWire.folder(read, asked: "")
            guard folder.path == "C:\\Users\\sample", folder.parent == "C:\\Users", folder.dirs.count == 4, folder.skipped == 1,
                  !folder.truncated, !folder.differs, folder.load == .loaded else { throw SampleMismatch("folder fields") }
            guard folder.dirs[0].name == "Documents", folder.dirs[0].openable,
                  // A name with an ampersand is listed but has no link.
                  folder.dirs[2].name == "R&D notes", !folder.dirs[2].openable,
                  // No name: the last part of the path.
                  folder.dirs[3].name == "Music" else { throw SampleMismatch("rows") }
            let top = DeskFilesWire.folder(try KJSON.decode(DeskFilesFolderDTO.self, from: DeskFilesSamples.top), asked: "C:\\")
            guard top.parent == nil, top.dirs.isEmpty, top.truncated, !top.differs else { throw SampleMismatch("top") }
            return "home folder, 4 rows, 1 odd row skipped, no parent at the top"
        },
        DecodeCheck("deskfiles.paths") {
            // The desktop opens home when the asked folder is not there: the screen says so.
            let read = try KJSON.decode(DeskFilesFolderDTO.self, from: DeskFilesSamples.home)
            guard DeskFilesWire.folder(read, asked: "D:\\Gone").differs,
                  !DeskFilesWire.folder(read, asked: "c:/users/sample/").differs,
                  !DeskFilesWire.folder(read, asked: "C:\\Users\\sample").differs else { throw SampleMismatch("differs") }
            guard DeskFilesWire.lastName("C:\\Users\\sample\\Projects") == "Projects", DeskFilesWire.lastName("/home/x/y/") == "y",
                  DeskFilesWire.pathOK("C:\\Users\\sample"), !DeskFilesWire.pathOK("a&b"), !DeskFilesWire.pathOK("a=b"),
                  !DeskFilesWire.pathOK("a#b") else { throw SampleMismatch("path helpers") }
            let refused = try KJSON.decode(APIErrorBody.self, from: DeskFilesSamples.forbidden)
            guard refused.text == "admin privileges required",
                  DeskFilesWire.words(APIError.server(status: 403, detail: refused.text)) == "Files on this PC need an admin account on your desktop." else {
                throw SampleMismatch("403")
            }
            return "different folder noticed, odd names kept off the address, 403 sentence"
        },
    ]
}
