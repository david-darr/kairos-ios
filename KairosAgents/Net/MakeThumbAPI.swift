import Foundation

// The small pictures on Make, as the phone reads them from the paired desktop:
//
// - A design's picture: GET /api/designs/{id}/boards/{slug}/thumb (routes/design_routes.py: board_thumb), a PNG of
//   the design's first board. The desktop answers 404 "No thumbnail" when it cannot draw one right now.
// - A video's picture: GET /api/videos/{id}/renders/thumb-{16-9|9-16|1-1}.png (routes/video_routes.py: download).
//   core/video_render.py and core/video_longform.py write that file (a frame of the video, 480 pixels wide at most)
//   next to every finished render of that aspect. A video with no finished render of an aspect answers 404 for it.
//   There is no route that names a video's renders without starting something, so the phone asks for the
//   picture of each of the video's aspects in turn and stops at the first one that exists. Nothing is started and
//   the video file itself is never downloaded.
// - GET /api/designs (design_store.summary): every design the account may see, newest change first, each with
//   its `first_board`. Make home reads it, with the designs the front desk made, so a design made in any chat or on
//   the canvas has a shelf place.

// MARK: - Rows and sources

/// One design of GET /api/designs, only what the Make shelf shows.
nonisolated struct MakeThumbDesignRow: Hashable, Sendable {
    let id: String
    var title: String
    var boards: Int
    var updated: Date?
    var firstBoard: String?

    init?(_ dto: MakeDesignRowDTO) {
        guard MakeHomeWire.isHex(dto.id, 12) else { return nil }
        id = dto.id
        let name = dto.title?.string ?? ""
        title = name.isEmpty ? "Untitled design" : name
        boards = max(0, dto.boards?.int ?? 0)
        updated = MakeHomeWire.time(dto.updated)
        firstBoard = dto.firstBoard?.string.flatMap { try? MakeDesignWire.part($0) }
    }

    var detail: String {
        switch boards {
        case 0: "Design"
        case 1: "Design · 1 board"
        default: "Design · \(boards) boards"
        }
    }
}

/// What a picture is a picture of, and which request fetches it.
nonisolated enum MakeThumbKind: Hashable, Sendable {
    case design(board: String)
    case video(aspects: [String])
}

/// One thing that has a picture on the desktop. `stamp` is when it last changed there, so a changed
/// design or video asks again instead of showing an older picture.
nonisolated struct MakeThumbSource: Hashable, Sendable {
    let id: String
    let kind: MakeThumbKind
    let stamp: Double

    var isVideo: Bool {
        if case .video = kind { return true }
        return false
    }

    var key: String {
        switch kind {
        case .design(let board): "design/\(id)/\(board)/\(stamp)"
        case .video(let aspects): "video/\(id)/\(aspects.joined(separator: ","))/\(stamp)"
        }
    }
}

nonisolated enum MakeThumbWire {
    /// The aspects a video can have, as the desktop writes them into a render's file name.
    static let aspectSlugs: [String: String] = ["16:9": "16-9", "9:16": "9-16", "1:1": "1-1"]

    static func stamp(_ date: Date?) -> Double { date?.timeIntervalSince1970 ?? 0 }

    /// /api/designs/{id}/boards/{slug}/thumb
    static func designPath(id: String, board: String) throws -> String {
        try MakeDesignWire.path(id, "/boards/" + MakeDesignWire.part(board) + "/thumb")
    }

    /// The design and board a front-desk `thumb_url` names, or nil for anything else.
    static func board(fromThumbURL value: String?) -> (design: String, board: String)? {
        let prefix = "/api/designs/"
        guard let value, value.hasPrefix(prefix) else { return nil }
        let parts = value.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[1] == "boards", parts[3] == "thumb",
              MakeHomeWire.isHex(parts[0], 12),
              let slug = parts[2].removingPercentEncoding, (try? MakeDesignWire.part(slug)) != nil else { return nil }
        return (parts[0], slug)
    }

    /// The video's aspects the desktop knows, in the video's own order. A video that names none has 16:9.
    static func videoAspects(_ aspects: [String]?) -> [String] {
        let known = (aspects ?? []).filter { aspectSlugs[$0] != nil }
        return known.isEmpty ? ["16:9"] : known
    }

    /// The picture files to ask for, one per aspect, in order.
    static func videoPaths(id: String, aspects: [String]) -> [String] {
        guard MakeHomeWire.isHex(id, 12) else { return [] }
        return aspects.compactMap { aspectSlugs[$0] }.map { "/api/videos/\(id)/renders/thumb-\($0).png" }
    }
}

// MARK: - Calls

extension APIClient {

    /// The bytes of one small picture. Sent with the phone's usual header, asked for fresh, never kept by the
    /// system's URL cache. The caller decides what a 404 or any other failure means for its card.
    func makeThumbBytes(_ path: String) async throws -> Data {
        var request = try urlRequest("GET", path)
        request.setValue("image/png, image/*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        return try await send(request)
    }
}

// MARK: - Samples

/// Made-up answers for the Make pictures, shaped like the desktop's own.
nonisolated enum MakeThumbSamples {

    static let designs = #"""
    [
      {"id": "3f2a9c1b7d04", "title": "Bike shop booking page", "boards": 2, "version": 4, "updated": 1793000100.5,
       "created": 1792900000, "chat_ids": [], "first_board": "home", "board_titles": ["Home", "Prices"]},
      {"id": "d41c8e0b2a77", "title": "Made on the canvas", "boards": 1, "version": 1, "updated": 1793000500,
       "first_board": "screen-1"},
      {"id": "zz", "title": "A bad id"},
      {"id": "9a8b7c6d5e4f", "title": "", "boards": 0, "updated": 1792000000, "first_board": null},
      {"title": "No id"}
    ]
    """#

    static let videos = #"""
    [
      {"id": "a1b2c3d4e5f6", "title": "Spring ride tips", "beats": [], "aspects": ["9:16", "1:1", "4:3"], "updated": 1793000000.5},
      {"id": "b2c3d4e5f6a1", "title": "No aspects named", "beats": [], "updated": 1792000000}
    ]
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("makethumb.designs") {
            let read = try KJSON.decode([MakeDesignMaybe<MakeDesignRowDTO>].self, from: MakeThumbSamples.designs)
            let rows = read.compactMap(\.value).compactMap { MakeThumbDesignRow($0) }
            guard read.count == 5, rows.count == 3, rows[0].firstBoard == "home", rows[0].boards == 2,
                  rows[0].detail == "Design · 2 boards", rows[1].detail == "Design · 1 board",
                  rows[2].title == "Untitled design", rows[2].firstBoard == nil, rows[2].detail == "Design",
                  rows[0].updated == Date(timeIntervalSince1970: 1_793_000_100.5) else {
                throw SampleMismatch("design rows")
            }
            return "3 of 5 rows usable, boards, details"
        },
        DecodeCheck("makethumb.wire") {
            let found = MakeThumbWire.board(fromThumbURL: "/api/designs/3f2a9c1b7d04/boards/b1/thumb")
            guard found?.design == "3f2a9c1b7d04", found?.board == "b1",
                  MakeThumbWire.board(fromThumbURL: "/api/designs/3f2a9c1b7d04/boards/home%20two/thumb") == nil,
                  MakeThumbWire.board(fromThumbURL: "/api/designs/3f2a9c1b7d04/boards/../thumb") == nil,
                  MakeThumbWire.board(fromThumbURL: "/api/designs/short/boards/b1/thumb") == nil,
                  MakeThumbWire.board(fromThumbURL: "/other/3f2a9c1b7d04/boards/b1/thumb") == nil,
                  MakeThumbWire.board(fromThumbURL: nil) == nil,
                  (try? MakeThumbWire.designPath(id: "3f2a9c1b7d04", board: "screen-1")) == "/api/designs/3f2a9c1b7d04/boards/screen-1/thumb",
                  (try? MakeThumbWire.designPath(id: "3f2a9c1b7d04", board: "../x")) == nil else {
                throw SampleMismatch("design thumb paths")
            }
            return "design picture paths checked"
        },
        DecodeCheck("makethumb.videos") {
            let read = try KJSON.decode(MakeHomeVideosDTO.self, from: MakeThumbSamples.videos)
            guard read.videos.count == 2 else { throw SampleMismatch("video rows") }
            let first = MakeThumbWire.videoAspects(read.videos[0].aspects)
            let second = MakeThumbWire.videoAspects(read.videos[1].aspects)
            guard first == ["9:16", "1:1"], second == ["16:9"],
                  MakeThumbWire.videoPaths(id: read.videos[0].id, aspects: first)
                      == ["/api/videos/a1b2c3d4e5f6/renders/thumb-9-16.png", "/api/videos/a1b2c3d4e5f6/renders/thumb-1-1.png"],
                  MakeThumbWire.videoPaths(id: "not-hex", aspects: second).isEmpty else {
                throw SampleMismatch("video picture paths")
            }
            let one = MakeThumbSource(id: "a1b2c3d4e5f6", kind: .video(aspects: first), stamp: 5)
            let two = MakeThumbSource(id: "a1b2c3d4e5f6", kind: .video(aspects: first), stamp: 6)
            guard one.key != two.key, one.isVideo else { throw SampleMismatch("source key") }
            return "video picture paths and keys checked"
        },
    ]
}
