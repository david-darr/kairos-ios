import Foundation

// The desktop's video routes (routes/video_routes.py over core/video_store.py, video_render.py, video_agent.py
// and video_narration.py), as the phone's editor reads and writes them.
//
// - A video is the store's own project object: id (12 hex characters), title, look, bpm, fps, aspects, beats,
//   music, narration, cast, palette, style_pack, chapters, renderer, tracks, plus owner, chat_ids, visible_to,
//   version (a whole number that goes up by one on every save), created and updated.
// - The project is read as plain JSON (JSONSerialization), never through KJSON: the shared decoder turns
//   "fade_in" into "fadeIn", and the project goes back to the desktop under its own names.
// - PUT /api/videos/{id} takes the WHOLE project (title, look and beats are required) with `version`. A version
//   that is not the desktop's current one answers 409. The phone keeps the project it was filled from and sends
//   that project with only the person's edits applied on top (MakeVideoCodec in Features/Make/MakeVideoLive.swift).
// - Beat, clip and track ids are text ("intro", "k1"); comment ids and run ids are text too.
// - Render: POST /api/videos/{id}/render answers a job at once; GET /api/video-jobs/{id} is its progress; there is
//   no route that lists a video's jobs, so the phone reads them through the Studio tab's resources route
//   (GET /api/tab-studio/videos/{id}/resources), which answers 409 while that tab is off.
// - Ask Kairos (POST /api/videos/{id}/agent/ask) and narration (POST /api/videos/{id}/narrate) take no request id.

// MARK: - Wire helpers

nonisolated enum MakeVideoWire {
    /// The 404 sentence the video routes send for a video that is not there (video_store.py: get).
    static let missingDetail = "No such video."

    /// A desktop video id: 12 lowercase hexadecimal characters.
    static func isVideoID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard bytes.count == 12 else { return false }
        return bytes.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }

    /// A video id goes into the path only when it is one.
    static func pathID(_ id: String) throws -> String {
        guard isVideoID(id) else { throw APIError.unreadable("video id") }
        return id
    }

    /// A job, run or version id goes into the path as it is. One that could leave the route is refused.
    static func pathPart(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 64,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else {
            throw APIError.unreadable("id")
        }
        return id
    }

    static func object(_ data: Data) throws -> [String: Any] {
        guard let any = try? JSONSerialization.jsonObject(with: data), let dict = any as? [String: Any] else {
            throw APIError.unreadable("video")
        }
        return dict
    }

    /// A top-level list read item by item: an item that is not an object is skipped.
    static func objects(_ data: Data) throws -> [[String: Any]] {
        guard let any = try? JSONSerialization.jsonObject(with: data), let list = any as? [Any] else {
            throw APIError.unreadable("list")
        }
        return list.compactMap { $0 as? [String: Any] }
    }

    static func str(_ value: Any?) -> String? { value as? String }

    static func isBool(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }

    static func num(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBool(number) else { return nil }
        return number.doubleValue
    }

    static func int(_ value: Any?) -> Int? {
        guard let double = num(value), double.isFinite, abs(double) < 1e12 else { return nil }
        return Int(double)
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBool(number) else { return nil }
        return number.boolValue
    }

    static func strings(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    static func dicts(_ value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    /// A time to two places, as the desktop keeps clip times to four.
    static func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
}

// MARK: - The video

/// One video as the desktop holds it: the whole project as plain JSON, and the numbers the phone reads from it.
nonisolated struct MakeVideoDoc {
    var raw: [String: Any]
    var id: String
    var version: Int

    /// The project fields the desktop's save takes. Everything else in the answer (owner, chat_ids, visible_to,
    /// version, created, updated) is the desktop's own and is never sent back.
    static let metaKeys: Set<String> = ["owner", "chat_ids", "visible_to", "version", "created", "updated"]

    init(raw: [String: Any]) throws {
        guard let id = MakeVideoWire.str(raw["id"]), MakeVideoWire.isVideoID(id),
              let version = MakeVideoWire.int(raw["version"]), version >= 1,
              raw["beats"] is [Any] else {
            throw APIError.unreadable("video")
        }
        self.raw = raw
        self.id = id
        self.version = version
    }

    var title: String { MakeVideoWire.str(raw["title"]) ?? "Video" }
    var bpm: Double { MakeVideoWire.num(raw["bpm"]) ?? 120 }
    var fps: Int { MakeVideoWire.int(raw["fps"]) ?? 30 }
    var aspects: [String] {
        let list = MakeVideoWire.strings(raw["aspects"])
        return list.isEmpty ? ["16:9"] : list
    }
    var beats: [[String: Any]] { MakeVideoWire.dicts(raw["beats"]) }
    var tracks: [[String: Any]] { MakeVideoWire.dicts(raw["tracks"]) }
    var chapters: [[String: Any]] { MakeVideoWire.dicts(raw["chapters"]) }
    var isChaptered: Bool { !chapters.isEmpty }
    var musicMood: String { MakeVideoWire.str((raw["music"] as? [String: Any])?["mood"]) ?? "energetic" }
    var updated: Date? { MakeVideoWire.num(raw["updated"]).map { Date(timeIntervalSince1970: $0) } }

    /// How long the video runs, from each beat's own length (a narrated beat keeps the seconds the desktop
    /// measured, any other beat is its bars at this video's tempo).
    var seconds: Double {
        let bar = 240 / max(60, bpm)
        return beats.reduce(0) { total, beat in
            total + (MakeVideoWire.num(beat["seconds"]) ?? (MakeVideoWire.num(beat["bars"]) ?? 1) * bar)
        }
    }

    /// Narrated beats whose line the desktop has not spoken and measured yet.
    var unspokenLines: Int {
        beats.filter { $0["say"] is String && $0["spoken"] == nil }.count
    }
}

/// One saved version in the video's history (GET /api/videos/{id}/history, newest first, 30 at most).
nonisolated struct MakeVideoVersionDTO: Identifiable, Equatable {
    var version: Int
    var title: String
    var updated: Date?
    var beats: Int
    var seconds: Double
    var id: Int { version }

    init?(_ raw: [String: Any]) {
        guard let doc = try? MakeVideoDoc(raw: raw) else { return nil }
        version = doc.version
        title = doc.title
        updated = doc.updated
        beats = doc.beats.count
        seconds = doc.seconds
    }
}

// MARK: - Render

/// GET /api/videos/ffmpeg: {found, version, message}.
nonisolated struct MakeVideoFfmpegDTO: Equatable {
    var found: Bool
    var version: String?
    var message: String

    init(_ raw: [String: Any]) {
        found = MakeVideoWire.bool(raw["found"]) ?? false
        version = MakeVideoWire.str(raw["version"])
        message = MakeVideoWire.str(raw["message"]) ?? ""
    }
}

/// One render job (video_render.py: the job's state dict, without its file path).
nonisolated struct MakeVideoJobDTO: Equatable {
    var id: String
    var videoID: String
    var aspect: String
    var version: Int?
    /// "queued", "narrating", "rendering 12/340", "encoding", "ready", "paused", or "failed: why".
    var status: String
    /// Nothing for a short video, "long" for a chaptered one, "export" for a WebM, MOV or GIF.
    var kind: String?
    var file: String?
    var notes: [String]
    var seconds: Double?

    init?(_ raw: [String: Any]) {
        guard let id = MakeVideoWire.str(raw["id"]), !id.isEmpty, let status = MakeVideoWire.str(raw["status"]) else { return nil }
        self.id = id
        videoID = MakeVideoWire.str(raw["video_id"]) ?? ""
        aspect = MakeVideoWire.str(raw["aspect"]) ?? ""
        version = MakeVideoWire.int(raw["version"])
        self.status = status
        kind = MakeVideoWire.str(raw["kind"])
        file = MakeVideoWire.str(raw["file"])
        notes = MakeVideoWire.strings(raw["notes"])
        seconds = MakeVideoWire.num(raw["seconds"])
    }

    var isReady: Bool { status == "ready" }
    var isFailed: Bool { status.hasPrefix("failed:") }
    /// Still working on the desktop. A paused long render is not: it resumes when rendering starts again.
    var isActive: Bool { !isReady && !isFailed && status != "paused" }
    var isExport: Bool { kind == "export" }
    var failure: String { String(status.dropFirst("failed:".count)).trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 0 to 1 while frames are drawn ("rendering 12/340"); nothing before or after that.
    var progress: Double? {
        let prefix = "rendering "
        guard status.hasPrefix(prefix) else { return nil }
        let parts = status.dropFirst(prefix.count).split(separator: "/")
        guard parts.count == 2, let done = Int(parts[0]), let total = Int(parts[1]), total > 0 else { return nil }
        return min(1, max(0, Double(done) / Double(total)))
    }

    /// What the desktop is doing, in plain words.
    var words: String {
        if isReady { return "Ready" }
        if isFailed { return failure.isEmpty ? "Failed" : "Failed: " + failure }
        if status == "paused" { return "Paused" }
        if status == "queued" { return "Waiting to start" }
        if status == "narrating" { return "Speaking the lines" }
        if status == "encoding" { return "Putting it together" }
        if let progress { return "Drawing frames, \(Int((progress * 100).rounded()))%" }
        return status
    }
}

/// GET /api/tab-studio/videos/{id}/resources: this video's render jobs (and files). Only the jobs are read.
nonisolated struct MakeVideoResourcesDTO: Equatable {
    var jobs: [MakeVideoJobDTO]
    var renders: [String]

    init(_ raw: [String: Any]) {
        jobs = MakeVideoWire.dicts(raw["jobs"]).compactMap { MakeVideoJobDTO($0) }
        renders = MakeVideoWire.strings(raw["renders"])
    }
}

// MARK: - Ask Kairos

/// One comment pinned on the preview (video_agent.py: add_comment). Only an open one is shown.
nonisolated struct MakeVideoCommentDTO: Equatable {
    var id: String
    var t: Double
    var text: String
    var open: Bool

    init?(_ raw: [String: Any]) {
        guard let id = MakeVideoWire.str(raw["id"]), !id.isEmpty else { return nil }
        self.id = id
        t = MakeVideoWire.num(raw["t"]) ?? 0
        text = MakeVideoWire.str(raw["text"]) ?? ""
        open = (MakeVideoWire.str(raw["status"]) ?? "open") == "open"
    }
}

/// One change a Kairos run made or would make, in plain words (video_agent.py: diff).
nonisolated struct MakeVideoChangeDTO: Equatable {
    var item: String
    var words: String

    init?(_ raw: [String: Any]) {
        guard let words = MakeVideoWire.str(raw["words"]), !words.isEmpty else { return nil }
        item = MakeVideoWire.str(raw["item"]) ?? words
        self.words = words
    }
}

/// One Ask Kairos run as the desktop publishes it (video_agent.py: _public, without its operations).
nonisolated struct MakeVideoRunDTO: Equatable, Identifiable {
    var id: String
    var request: String
    var reply: String
    /// "answered" (nothing to change), "applied", "pending" (a dry run waiting for Apply or Discard), "discarded",
    /// "undone" or "failed".
    var status: String
    var error: String?
    var afterVersion: Int?
    var changes: [MakeVideoChangeDTO]

    init?(_ raw: [String: Any]) {
        guard let id = MakeVideoWire.str(raw["id"]), !id.isEmpty else { return nil }
        self.id = id
        request = MakeVideoWire.str(raw["request"]) ?? ""
        reply = MakeVideoWire.str(raw["reply"]) ?? ""
        status = MakeVideoWire.str(raw["status"]) ?? "answered"
        error = MakeVideoWire.str(raw["error"])
        afterVersion = MakeVideoWire.int(raw["after_version"])
        changes = MakeVideoWire.dicts(raw["changes"]).compactMap { MakeVideoChangeDTO($0) }
    }

    var isPending: Bool { status == "pending" }
    var isApplied: Bool { status == "applied" }
}

/// GET /api/videos/{id}/review: the comments, the latest runs (newest first) and the connection Kairos would use.
nonisolated struct MakeVideoReviewDTO: Equatable {
    var comments: [MakeVideoCommentDTO]
    var runs: [MakeVideoRunDTO]
    var connection: String?
    var dryRunOver: Int

    init(_ raw: [String: Any]) {
        comments = MakeVideoWire.dicts(raw["comments"]).compactMap { MakeVideoCommentDTO($0) }
        runs = MakeVideoWire.dicts(raw["runs"]).compactMap { MakeVideoRunDTO($0) }
        connection = MakeVideoWire.str(raw["connection"])
        dryRunOver = MakeVideoWire.int(raw["dry_run_over"]) ?? 5
    }
}

// MARK: - Calls

extension APIClient {

    /// One request with a JSON body or none, answering the raw bytes (the video routes' answers are read by hand).
    fileprivate func makeVideoSend(_ method: String, _ path: String, json: [String: Any]? = nil, timeout: TimeInterval? = nil) async throws -> Data {
        var request = try urlRequest(method, path)
        if let json {
            guard JSONSerialization.isValidJSONObject(json) else { throw APIError.unreadable("request") }
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let timeout { request.timeoutInterval = timeout }
        return try await send(request)
    }

    /// GET /api/videos/{id}.
    func makeVideoGet(_ id: String) async throws -> MakeVideoDoc {
        let video = try MakeVideoWire.pathID(id)
        let data = try await bytes("/api/videos/\(video)")
        return try MakeVideoDoc(raw: MakeVideoWire.object(data))
    }

    /// PUT /api/videos/{id} with the whole project and the version it was read at. Answers the saved project.
    func makeVideoSave(_ id: String, body: [String: Any]) async throws -> MakeVideoDoc {
        let video = try MakeVideoWire.pathID(id)
        let data = try await makeVideoSend("PUT", "/api/videos/\(video)", json: body)
        return try MakeVideoDoc(raw: MakeVideoWire.object(data))
    }

    /// GET /api/videos/{id}/history. A version this app cannot read is skipped.
    func makeVideoHistory(_ id: String) async throws -> [MakeVideoVersionDTO] {
        let video = try MakeVideoWire.pathID(id)
        let data = try await bytes("/api/videos/\(video)/history")
        return try MakeVideoWire.objects(data).compactMap { MakeVideoVersionDTO($0) }
    }

    /// POST /api/videos/{id}/restore/{version}: makes that version the newest one. Answers the saved project.
    func makeVideoRestore(_ id: String, version: Int) async throws -> MakeVideoDoc {
        guard version >= 1 else { throw APIError.unreadable("version") }
        let video = try MakeVideoWire.pathID(id)
        let data = try await makeVideoSend("POST", "/api/videos/\(video)/restore/\(version)")
        return try MakeVideoDoc(raw: MakeVideoWire.object(data))
    }

    /// GET /api/videos/ffmpeg.
    func makeVideoFfmpeg() async throws -> MakeVideoFfmpegDTO {
        let data = try await bytes("/api/videos/ffmpeg")
        return MakeVideoFfmpegDTO(try MakeVideoWire.object(data))
    }

    /// GET /api/tab-studio/videos/{id}/resources, read for the video's render jobs.
    func makeVideoResources(_ id: String) async throws -> MakeVideoResourcesDTO {
        let video = try MakeVideoWire.pathID(id)
        let data = try await bytes("/api/tab-studio/videos/\(video)/resources")
        return MakeVideoResourcesDTO(try MakeVideoWire.object(data))
    }

    /// POST /api/videos/{id}/render for an MP4. Starts minutes of work on the desktop and answers the job at once.
    func makeVideoRenderStart(_ id: String, aspect: String) async throws -> MakeVideoJobDTO {
        let video = try MakeVideoWire.pathID(id)
        let data = try await makeVideoSend("POST", "/api/videos/\(video)/render", json: ["aspect": aspect, "format": "mp4"])
        guard let job = MakeVideoJobDTO(try MakeVideoWire.object(data)) else { throw APIError.unreadable("job") }
        return job
    }

    /// GET /api/video-jobs/{id}.
    func makeVideoJob(_ jobID: String) async throws -> MakeVideoJobDTO {
        let job = try MakeVideoWire.pathPart(jobID)
        let data = try await bytes("/api/video-jobs/\(job)")
        guard let found = MakeVideoJobDTO(try MakeVideoWire.object(data)) else { throw APIError.unreadable("job") }
        return found
    }

    /// POST /api/video-jobs/{id}/cancel. Answers the job as it stands.
    func makeVideoJobCancel(_ jobID: String) async throws -> MakeVideoJobDTO {
        let part = try MakeVideoWire.pathPart(jobID)
        let data = try await makeVideoSend("POST", "/api/video-jobs/\(part)/cancel")
        guard let job = MakeVideoJobDTO(try MakeVideoWire.object(data)) else { throw APIError.unreadable("job") }
        return job
    }

    /// POST /api/videos/{id}/narrate: speaks the lines not spoken yet and saves the measurements as a new version.
    /// The desktop answers when it is done, which can be minutes.
    func makeVideoNarrate(_ id: String) async throws -> MakeVideoDoc {
        let video = try MakeVideoWire.pathID(id)
        let data = try await makeVideoSend("POST", "/api/videos/\(video)/narrate", timeout: 170)
        return try MakeVideoDoc(raw: MakeVideoWire.object(data))
    }

    /// GET /api/videos/{id}/review.
    func makeVideoReview(_ id: String) async throws -> MakeVideoReviewDTO {
        let video = try MakeVideoWire.pathID(id)
        let data = try await bytes("/api/videos/\(video)/review")
        return MakeVideoReviewDTO(try MakeVideoWire.object(data))
    }

    /// POST /api/videos/{id}/agent/ask: one model turn on the desktop. `selection` names the beat or clip by the
    /// desktop's own ids; `comments` are open comment ids to address.
    func makeVideoAsk(_ id: String, request: String, selection: [String: Any]?, comments: [String]) async throws -> MakeVideoRunDTO {
        var body: [String: Any] = ["request": request, "comments": comments]
        if let selection { body["selection"] = selection }
        let video = try MakeVideoWire.pathID(id)
        let data = try await makeVideoSend("POST", "/api/videos/\(video)/agent/ask", json: body, timeout: 170)
        guard let run = MakeVideoRunDTO(try MakeVideoWire.object(data)) else { throw APIError.unreadable("run") }
        return run
    }

    /// POST /api/videos/{id}/agent/runs/{run}/{apply|discard|undo}. Apply and undo answer {run, project}; discard
    /// answers the run itself.
    func makeVideoRunAction(_ id: String, run: String, action: MakeVideoRunAction) async throws -> MakeVideoRunDTO {
        let video = try MakeVideoWire.pathID(id)
        let part = try MakeVideoWire.pathPart(run)
        let data = try await makeVideoSend("POST", "/api/videos/\(video)/agent/runs/\(part)/\(action.rawValue)", timeout: 60)
        let object = try MakeVideoWire.object(data)
        let inner = (object["run"] as? [String: Any]) ?? object
        guard let result = MakeVideoRunDTO(inner) else { throw APIError.unreadable("run") }
        return result
    }
}

nonisolated enum MakeVideoRunAction: String, Sendable {
    case apply, discard, undo
}

// MARK: - Samples

/// A sample answer for every video route the editor uses, shaped like the desktop's own (made-up content).
nonisolated enum MakeVideoSamples {

    static let video = #"""
    {"id": "a1b2c3d4e5f6", "title": "Spring bike tune-up", "look": "clean", "bpm": 120, "fps": 30, "aspects": ["9:16"],
     "beats": [
       {"id": "intro", "kind": "scene", "bars": 1, "say": "Spring is here, and the trails are calling.",
        "spoken": {"key": "0123456789abcdef", "seconds": 2.9, "parts": [[0.25, 3.1, "Spring is here, and the trails are calling."]]},
        "seconds": 3.6,
        "scene": {"setting": "meadow", "shot": "wide",
                  "cast": [{"character": "0123456789ab", "x": 0.32, "view": "front", "expression": "happy", "action": "idle", "facing": "right", "speaking": true}],
                  "props": [{"icon": "sun", "x": 0.78, "y": 0.28, "size": 0.12, "float": true}]}},
       {"id": "offer", "kind": "statement", "bars": 2, "text": "Spring prices end Friday", "sub": "Open till 6 pm"},
       {"id": "ride", "kind": "voxel", "bars": 3, "voxel": {"world": "village", "time": "dusk", "shot": "wide", "seed": 0, "cast": [], "people": {"count": 0, "seed": 0}, "props": [], "labels": []}},
       {"id": "tune", "kind": "stage", "bars": 2, "say": "A full tune-up in under an hour.", "seconds": 3.2,
        "stage": {"set": "mint", "shot": "medium", "pedestal": true, "cast": [], "people": {"count": 0, "seed": 0}, "props": [], "labels": []}}
     ],
     "music": {"mood": "warm", "volume": 0.7}, "narration": {"voice": "af_heart", "captions": true},
     "tracks": [
       {"id": "t1", "kind": "overlay", "name": "Overlay", "hidden": false, "locked": false, "clips": [
         {"id": "k1", "kind": "text", "start": 0.5, "in": 0, "out": 3, "opacity": 1, "fade_in": 0.3, "fade_out": 0.3,
          "text": "Spring ride", "role": "title", "style": "card", "color": "text", "align": "center",
          "box": {"x": 0.1, "y": 0.1, "w": 0.8, "h": 0.12},
          "keys": {"opacity": [{"t": 0, "v": 0, "ease": "linear"}, {"t": 0.3, "v": 1, "ease": "linear"}]}},
         {"id": "k2", "kind": "shape", "start": 8, "in": 0, "out": 12, "opacity": 1, "fade_in": 0, "fade_out": 0,
          "shape": "ellipse", "color": "accent", "fill": false, "stroke": 0.006, "box": {"x": 0.3, "y": 0.3, "w": 0.4, "h": 0.22}}]},
       {"id": "t2", "kind": "audio", "name": "Sound", "hidden": false, "locked": false, "clips": []}
     ],
     "owner": "example", "chat_ids": [], "visible_to": [], "version": 7, "created": 1793000000.5, "updated": 1793100000.25}
    """#

    static let history = #"""
    [
      {"id": "a1b2c3d4e5f6", "title": "Spring bike tune-up", "look": "clean", "bpm": 120, "fps": 30, "aspects": ["9:16"],
       "beats": [{"id": "intro", "kind": "statement", "bars": 2, "text": "Spring is here"}], "version": 7, "updated": 1793100000.25},
      {"id": "a1b2c3d4e5f6", "title": "Spring bike tune-up", "look": "clean", "bpm": 120, "fps": 30, "aspects": ["9:16"],
       "beats": [{"id": "intro", "kind": "statement", "bars": 2, "text": "Spring is here"}, {"id": "offer", "kind": "statement", "bars": 2, "text": "Prices end Friday"}],
       "version": 6, "updated": 1793090000.0},
      "not a version"
    ]
    """#

    static let ffmpegReady = #"{"found": true, "version": "7.0", "message": "FFmpeg is ready."}"#
    static let ffmpegMissing = #"{"found": false, "version": null, "message": "FFmpeg was not found on this computer."}"#

    static let jobRunning = #"""
    {"id": "9f8e7d6c5b4a3210", "video_id": "a1b2c3d4e5f6", "aspect": "9:16", "version": 7, "status": "rendering 120/360"}
    """#

    static let jobReady = #"""
    {"id": "9f8e7d6c5b4a3210", "video_id": "a1b2c3d4e5f6", "aspect": "9:16", "version": 7, "status": "ready",
     "file": "9-16-v1.mp4", "url": "/api/videos/a1b2c3d4e5f6/renders/9-16-v1.mp4", "seconds": 12.4, "fps": 30, "frames": 372,
     "notes": ["The last caption sits close to the bottom edge."], "loudness": -16.2}
    """#

    static let jobFailed = #"""
    {"id": "1111222233334444", "video_id": "a1b2c3d4e5f6", "aspect": "9:16", "version": 7, "status": "failed: cancelled"}
    """#

    static let resources = #"""
    {"assets": [], "renders": ["9-16-v1.mp4", "thumb-9-16.png"], "thumbnail": "thumb-9-16.png",
     "jobs": [{"id": "9f8e7d6c5b4a3210", "video_id": "a1b2c3d4e5f6", "aspect": "9:16", "version": 7, "status": "encoding"},
              {"id": "5555666677778888", "video_id": "a1b2c3d4e5f6", "aspect": "9:16", "version": 6, "status": "ready", "kind": "export", "format": "webm", "file": "9-16-v1.webm"},
              "not a job"]}
    """#

    static let review = #"""
    {"comments": [{"id": "m1a2b3c4d5", "t": 3.5, "x": 0.5, "y": 0.4, "text": "The caption feels long here.", "under": "", "status": "open", "created": 1793000100.0},
                  {"id": "m6e7f8a9b0", "t": 9, "x": 0.2, "y": 0.8, "text": "Music could dip lower.", "under": "", "status": "resolved", "created": 1793000200.0}],
     "runs": [{"id": "r0a1b2c3d4", "created": 1793100100.0, "request": "Shorten every caption", "comments": [], "reply": "That changes seven beats, so I held it for your OK.",
               "resolved": [], "base_version": 7, "status": "pending", "operations": 7,
               "changes": [{"item": "beat:intro", "type": "beat", "id": "intro", "change": "changed", "words": "Changed beat intro (scene): narration line."},
                           {"item": "beat:offer", "type": "beat", "id": "offer", "change": "changed", "words": "Changed beat offer (statement): text."}]},
              {"id": "r9z8y7x6w5", "created": 1793000300.0, "request": "Warmer opening", "comments": [], "reply": "Done.", "resolved": [],
               "base_version": 6, "status": "applied", "after_version": 7, "operations": 1,
               "changes": [{"item": "beat:intro", "type": "beat", "id": "intro", "change": "changed", "words": "Changed beat intro (scene): narration line."}]}],
     "since": {"since": 7, "changes": []}, "connection": "My model", "dry_run_over": 5}
    """#

    static let applied = #"{"run": {"id": "r0a1b2c3d4", "status": "applied", "reply": "Done.", "after_version": 8, "operations": 7, "changes": []}, "project": {"id": "a1b2c3d4e5f6"}}"#
    static let discarded = #"{"id": "r0a1b2c3d4", "status": "discarded", "reply": "That changes seven beats.", "operations": 7, "changes": []}"#

    static let stale = #"{"detail": "This video changed since you opened it (it is now version 8). Your last change wasn't saved; the latest version is loaded, make the change again."}"#
    static let missing = #"{"detail": "No such video."}"#

    static func doc() throws -> MakeVideoDoc {
        try MakeVideoDoc(raw: MakeVideoWire.object(Data(video.utf8)))
    }

    static let checks: [DecodeCheck] = [
        DecodeCheck("makevideo.video") {
            let doc = try MakeVideoSamples.doc()
            let ids = MakeVideoIDs()
            let state = MakeVideoCodec.state(doc, ids: ids)
            guard doc.version == 7, doc.id == "a1b2c3d4e5f6", doc.aspects == ["9:16"], doc.musicMood == "warm",
                  state.beats.count == 4, state.clips.count == 2, !state.trackRemoved, !state.trackLocked,
                  MakeVideoCodec.overlayTrackID(doc) == "t1", doc.unspokenLines == 1 else { throw SampleMismatch("video fields") }
            let intro = state.beats[0]
            guard intro.kind == .scene, intro.narrated, intro.caption.hasPrefix("Spring is here"), intro.captionField == "say",
                  intro.setting == "meadow", intro.shot == "wide", intro.characters.count == 1, intro.props.count == 1,
                  abs(intro.length - 3.6) < 0.001 else { throw SampleMismatch("scene beat") }
            let offer = state.beats[1]
            guard offer.kind == .card, offer.rawKind == "statement", offer.captionField == "text", !offer.narrated,
                  abs(offer.length - 4) < 0.001, state.beats[2].kind == .blocky, state.beats[2].timeOfDay == "dusk",
                  state.beats[3].kind == .stage, state.beats[3].pedestal, state.beats[3].world == "mint" else { throw SampleMismatch("other beats") }
            let title = state.clips[0]
            guard title.kind == .text, title.text == "Spring ride", title.size == "Headline", title.style == "On a card",
                  title.colour == "Text", abs(title.length - 3) < 0.001, abs(title.fadeIn - 0.3) < 0.001,
                  abs(title.left - 10) < 0.001, abs(title.width - 80) < 0.001, title.animated == ["Opacity"],
                  state.clips[1].kind == .shape, state.clips[1].shape == "Ellipse", !state.clips[1].filled else { throw SampleMismatch("clips") }
            return "4 beats, 2 clips, ids and fields"
        },
        DecodeCheck("makevideo.history") {
            let list = try MakeVideoWire.objects(Data(MakeVideoSamples.history.utf8)).compactMap { MakeVideoVersionDTO($0) }
            guard list.count == 2, list[0].version == 7, list[1].beats == 2, abs(list[1].seconds - 8) < 0.001,
                  list[0].updated != nil else { throw SampleMismatch("history") }
            return "2 versions, 1 skipped"
        },
        DecodeCheck("makevideo.render") {
            let ready = MakeVideoFfmpegDTO(try MakeVideoWire.object(Data(MakeVideoSamples.ffmpegReady.utf8)))
            let missing = MakeVideoFfmpegDTO(try MakeVideoWire.object(Data(MakeVideoSamples.ffmpegMissing.utf8)))
            guard ready.found, !missing.found, !missing.message.isEmpty else { throw SampleMismatch("ffmpeg") }
            guard let running = MakeVideoJobDTO(try MakeVideoWire.object(Data(MakeVideoSamples.jobRunning.utf8))),
                  let done = MakeVideoJobDTO(try MakeVideoWire.object(Data(MakeVideoSamples.jobReady.utf8))),
                  let failed = MakeVideoJobDTO(try MakeVideoWire.object(Data(MakeVideoSamples.jobFailed.utf8))) else {
                throw SampleMismatch("job decode")
            }
            guard running.isActive, let progress = running.progress, abs(progress - 120.0 / 360.0) < 0.0001,
                  running.words == "Drawing frames, 33%", done.isReady, !done.isActive, done.notes.count == 1, done.file == "9-16-v1.mp4",
                  failed.isFailed, failed.failure == "cancelled", !failed.isActive, failed.progress == nil else { throw SampleMismatch("job fields") }
            let list = MakeVideoResourcesDTO(try MakeVideoWire.object(Data(MakeVideoSamples.resources.utf8)))
            guard list.jobs.count == 2, list.jobs[0].words == "Putting it together", list.jobs[1].isExport,
                  list.renders.count == 2 else { throw SampleMismatch("resources") }
            return "3 jobs, progress, resources with 1 skipped"
        },
        DecodeCheck("makevideo.ask") {
            let review = MakeVideoReviewDTO(try MakeVideoWire.object(Data(MakeVideoSamples.review.utf8)))
            guard review.comments.count == 2, review.comments.filter(\.open).count == 1, review.runs.count == 2,
                  review.runs[0].isPending, review.runs[0].changes.count == 2, review.runs[1].isApplied,
                  review.runs[1].afterVersion == 7, review.connection == "My model", review.dryRunOver == 5 else {
                throw SampleMismatch("review")
            }
            let apply = try MakeVideoWire.object(Data(MakeVideoSamples.applied.utf8))
            let discard = try MakeVideoWire.object(Data(MakeVideoSamples.discarded.utf8))
            guard let a = MakeVideoRunDTO((apply["run"] as? [String: Any]) ?? apply), let d = MakeVideoRunDTO((discard["run"] as? [String: Any]) ?? discard),
                  a.isApplied, a.afterVersion == 8, d.status == "discarded" else { throw SampleMismatch("run answers") }
            let refused = try KJSON.decode(APIErrorBody.self, from: MakeVideoSamples.stale)
            let gone = try KJSON.decode(APIErrorBody.self, from: MakeVideoSamples.missing)
            guard refused.text.contains("changed since you opened it"), gone.text == MakeVideoWire.missingDetail else {
                throw SampleMismatch("error bodies")
            }
            return "review, 2 run answers, 2 refusals"
        },
        DecodeCheck("makevideo.save") {
            // The save sends the project as it was filled, with only the person's edits on top and the version it was filled from.
            let doc = try MakeVideoSamples.doc()
            let ids = MakeVideoIDs()
            let filled = MakeVideoCodec.state(doc, ids: ids)
            var mine = filled
            mine.beats[0].caption = "Spring is here. Come ride."
            mine.beats[1].bars = 3
            mine.clips[0].text = "Spring ride, now"
            mine.clips[0].left = 12
            let body = MakeVideoCodec.body(base: doc, filled: filled, mine: mine, ids: ids)
            let beats = MakeVideoWire.dicts(body["beats"])
            let tracks = MakeVideoWire.dicts(body["tracks"])
            let clips = MakeVideoWire.dicts(tracks.first?["clips"])
            guard MakeVideoWire.int(body["version"]) == 7, body["owner"] == nil, body["chat_ids"] == nil, body["updated"] == nil,
                  beats.count == 4, MakeVideoWire.str(beats[0]["say"]) == "Spring is here. Come ride.",
                  beats[0]["spoken"] != nil, MakeVideoWire.num(beats[1]["bars"]) == 3,
                  MakeVideoWire.str(beats[1]["sub"]) == "Open till 6 pm", MakeVideoWire.str(beats[1]["text"]) == "Spring prices end Friday",
                  MakeVideoWire.str(beats[3]["say"]) == "A full tune-up in under an hour.",
                  tracks.count == 2, clips.count == 2, MakeVideoWire.str(clips[0]["text"]) == "Spring ride, now",
                  clips[0]["keys"] != nil, MakeVideoWire.num(clips[0]["fade_in"]) == 0.3,
                  MakeVideoWire.str(clips[1]["shape"]) == "ellipse" else { throw SampleMismatch("body") }
            let box = clips[0]["box"] as? [String: Any]
            guard let box, abs((MakeVideoWire.num(box["x"]) ?? 0) - 0.12) < 0.0001, abs((MakeVideoWire.num(box["w"]) ?? 0) - 0.8) < 0.0001 else {
                throw SampleMismatch("box")
            }
            // Nothing changed, nothing in the edits.
            let same = MakeVideoCodec.body(base: doc, filled: filled, mine: filled, ids: ids)
            guard MakeVideoWire.str(MakeVideoWire.dicts(same["beats"])[0]["say"]) == "Spring is here, and the trails are calling." else {
                throw SampleMismatch("unchanged body")
            }
            return "edits on top, version sent, the rest untouched"
        },
        DecodeCheck("makevideo.rebase") {
            // The desktop changed beat 2 while the person edited beat 1: both stay, and an untouched field is never an edit.
            let doc = try MakeVideoSamples.doc()
            let ids = MakeVideoIDs()
            let filled = MakeVideoCodec.state(doc, ids: ids)
            var mine = filled
            mine.beats[0].caption = "Spring is here. Come ride."
            var theirs = filled
            theirs.beats[1].caption = "Prices end Friday"
            theirs.beats[0].caption = "Changed on the desktop too"
            theirs.beats[3].bars = 4
            let merged = MakeVideoCodec.rebase(base: filled, theirs: theirs, mine: mine)
            guard merged.state.beats[0].caption == "Spring is here. Come ride.", merged.state.beats[1].caption == "Prices end Friday",
                  merged.state.beats[3].bars == 4, merged.dropped == 0, !merged.state.sameContent(theirs) else { throw SampleMismatch("merge") }
            let untouched = MakeVideoCodec.rebase(base: filled, theirs: theirs, mine: filled)
            guard untouched.state.sameContent(theirs) else { throw SampleMismatch("untouched merge") }
            // The person's delete and the desktop's delete.
            var deleted = filled
            deleted.beats.remove(at: 2)
            var gone = filled
            gone.beats.remove(at: 1)
            let both = MakeVideoCodec.rebase(base: filled, theirs: gone, mine: deleted)
            guard both.state.beats.map(\.id) == [filled.beats[0].id, filled.beats[3].id] else { throw SampleMismatch("deletes") }
            // What was sent is what the desktop now holds.
            guard MakeVideoCodec.matches(sent: mine, desktop: merged.state) == false,
                  MakeVideoCodec.matches(sent: mine, desktop: mine) else { throw SampleMismatch("compare with sent") }
            return "edits kept on top, untouched follows the desktop, deletes, compare"
        },
    ]
}
