import Foundation

// The desktop routes behind Studio (Make > Studio, the Content dashboard), as the phone reads and writes them.
// Every route is under /api/content-studio (routes/content_studio_routes.py over services/content_studio/*),
// signed-in account only, and works in that account's own store. Answers are read leniently: each answer is
// decoded as a free JSON value and each row is read on its own, so one odd row never empties a list.
//
// Reads used (the shape of each is the service code's, not a guess):
// - GET /niches {niches: [{id, name, status (live, retired), slots}], max_live}                 (store.py list_niches)
// - GET /channels {channels: [{id, niche_id, platform, handle, status (live, archived), paused (0 or 1), look,
//   aspect, notes, voice, style_pack, long_per_week, renderer, fps, made_for_kids (1, 0, null), niche_name}]}
//   (store.py list_channels). No account, email or connection data is in a channel row.
// - GET /posts {posts: [{id, channel_id, title, caption, tags, script_ref, format, format_name, pick_reason,
//   state, render_status, rejection_count, reject_reason, posted_url, posted_at, approved_at, created_at,
//   step_since, long_form, video_id, made_for_kids, style_pack, platform, handle, niche_id, niche_name}]}
//   (store.py POST_SQL). render_ref and approved_by are not read: the first is a local file name, the second a name.
// - GET /publishing {items: [{post_id, state (drafted, awaiting_approval, approved, prepared, waiting_for_you,
//   posted, failed, rejected), next: {who, what}, scheduled_at, posted_at, posted_url, prep_id, problems, error,
//   fill: {stage, filled, missing, note}, checklist: [{key, text, by, status}]}], counts}     (publishing.py dashboard)
// - GET /pipeline {items: [...]} (pipeline.py): a topic is {kind "topic", id, title, niche_id, age_h}; a post is
//   {kind "post", id, step (script, render, queue, approval, publish, tracking, rejected), owner, status, state,
//   age_h, in_step_h, window_h, rejection_count, overdue}.
// - GET /approvals {posts: [{id, chapters}], characters: [{id, name, family, version, status, note, submitted_at}],
//   style_packs: [{id, name, version, status, note, submitted_at}], plans: [{video_id, title, text, seconds,
//   chapters: [{title, start}], submitted_at, post_id, version}]}. The style pack's spec and every "by" name
//   are left out.
// - GET /decisions {decisions: [{id, kind, subject_type, subject_id, subject_name, numbers, reason, status}]}
// - GET /scoreboard {weights, niches, formats, style_packs, top_posts, posts_scored, posts_posted} (review.py)
// - GET /settings (weights, batch_approval, hands_off, team_paused ...), GET /hands-off {on, paused, taps}
// - GET /setup {dismissed, team: {imported, cycle: {running, last_run}, budget: {monthly_usd, spent_usd}}}
// - GET /report {from, to, text, spend}, GET /watch {findings: [{kind, severity, message, channel_id}]}
// - GET /posts/{id}: the post with metrics: [{taken_at, views, avg_view_duration_s, video_length_s, likes,
//   comments, shares, follows_gained, source}] and chapters.
// - GET /formats: only style_packs: [{id, name, available}] is read, for the channel look choice.
//
// Writes used (none takes a request id, so each one is kept "unconfirmed" in MakeStudioLive until the desktop
// shows the result):
// - POST /posts/{id}/approve, /approvals/approve-batch {post_ids} (batch approval must be on), /posts/{id}/reject
//   {reason}, /posts/{id}/redraft (rejected posts only), /posts/{id}/prepare {} (an approved post)
// - POST /api/videos/{id}/plan/approve and /reject {reason}: approves the plan "as it is now", so the phone
//   reads GET /api/videos/{id}/plan first and refuses when its status or version is not what the person saw.
// - POST /api/characters/{id}/versions/{n}/approve|reject and /api/style-packs/{id}/versions/{n}/approve|reject
//   {reason}: refused with 409 by the desktop unless the version is waiting.
// - PUT /hands-off {on: false} (only off is ever sent), PUT /team-pause {on}
// - POST /channels/{id}/resume, /archive {reason}, /edit (only the fields the person changed)
// - POST /decisions/{id}/confirm {actor: "user"}, /reject {reason}
// - POST /report/send: puts the report in the Inbox (and, with hands-off on, sends a message).
//
// With hands-off posting on, an approved post is posted by the desktop within minutes, so before approve,
// approve-batch, redraft, a plan, sheet or pack approval, team resume and channel resume the phone reads
// GET /hands-off again and sends nothing when it is on or cannot be read.
//
// Never called from the phone: publish to YouTube, TikTok or Instagram, schedule, mark posted, hands-off on,
// social apps and connections, metrics import, routines on, run a cycle, add channel, post edit.

// MARK: - Reading one row

/// One JSON object, read with plain accessors. Keys are camelCase because the decoder turns snake_case into it.
nonisolated struct MakeStudioRow: Sendable {
    let o: [String: JSONValue]

    init?(_ value: JSONValue?) {
        guard let object = value?.object else { return nil }
        o = object
    }

    /// The value under a camelCase key, or under the same key written in snake_case.
    func value(_ key: String) -> JSONValue? {
        if let found = o[key] { return found }
        var snake = ""
        for character in key {
            if character.isUppercase { snake += "_" + character.lowercased() } else { snake.append(character) }
        }
        return o[snake]
    }

    func str(_ key: String) -> String? { value(key)?.string }
    func int(_ key: String) -> Int? { value(key)?.int }
    func dbl(_ key: String) -> Double? { value(key)?.double }

    /// A switch the desktop stores as true, false, 1 or 0.
    func flag(_ key: String) -> Bool {
        if let found = value(key)?.bool { return found }
        if let number = value(key)?.int { return number != 0 }
        return false
    }

    func row(_ key: String) -> MakeStudioRow? { MakeStudioRow(value(key)) }
    func list(_ key: String) -> [JSONValue] { value(key)?.array ?? [] }
    func strings(_ key: String) -> [String] { list(key).compactMap(\.string) }
}

nonisolated enum MakeStudioWire {
    /// Read the rows of a list one by one. A row that cannot be read is counted and left out.
    static func rows<T>(_ list: [JSONValue], _ make: (MakeStudioRow) -> T?) -> (rows: [T], skipped: Int) {
        var out: [T] = []
        var skipped = 0
        for item in list {
            if let row = MakeStudioRow(item), let value = make(row) { out.append(value) } else { skipped += 1 }
        }
        return (out, skipped)
    }

    /// A desktop id that goes into a path: letters, digits and dashes only.
    static func pathID(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 60,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else {
            throw APIError.unreadable("id")
        }
        return id
    }

    static func isHex(_ text: String, _ count: Int) -> Bool {
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        return text.count == count && text.unicodeScalars.allSatisfy { hex.contains($0) }
    }

    /// The desktop's made-for-kids answer: 1 is "yes", 0 is "no", anything else is not set.
    static func kids(_ stored: Int?) -> String {
        guard let stored else { return "" }
        if stored == 1 { return "yes" }
        return stored == 0 ? "no" : ""
    }

    static func time(_ seconds: Double?) -> Date? {
        guard let seconds, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// The most the desktop takes for a reason (ReasonBody).
    static let reasonLimit = 500
    static let notesLimit = 1000
}

// MARK: - Answers

nonisolated struct MakeStudioNicheDTO: Sendable {
    var id: Int
    var name: String
    var retired: Bool
    var slots: Int

    init?(_ row: MakeStudioRow) {
        guard let id = row.int("id"), let name = row.str("name") else { return nil }
        self.id = id
        self.name = name
        retired = row.str("status") == "retired"
        slots = row.int("slots") ?? 1
    }
}

nonisolated struct MakeStudioChannelDTO: Sendable {
    var id: Int
    var nicheID: Int
    var platform: String
    var handle: String
    var archived: Bool
    var paused: Bool
    var look: String
    var aspect: String
    var notes: String
    var voice: String
    var stylePack: String
    var longPerWeek: Int?
    var renderer: String
    var fps: Int?
    /// "yes", "no" or "" (not set).
    var madeForKids: String

    init?(_ row: MakeStudioRow) {
        guard let id = row.int("id"), let handle = row.str("handle"), let platform = row.str("platform") else { return nil }
        self.id = id
        self.handle = handle
        self.platform = platform
        nicheID = row.int("nicheId") ?? 0
        archived = row.str("status") == "archived"
        paused = row.flag("paused")
        look = row.str("look") ?? ""
        aspect = row.str("aspect") ?? ""
        notes = row.str("notes") ?? ""
        voice = row.str("voice") ?? ""
        stylePack = row.str("stylePack") ?? ""
        longPerWeek = row.int("longPerWeek")
        renderer = row.str("renderer") ?? ""
        fps = row.int("fps")
        madeForKids = MakeStudioWire.kids(row.int("madeForKids"))
    }
}

nonisolated struct MakeStudioPostDTO: Sendable {
    var id: Int
    var channelID: Int
    var title: String
    var caption: String
    var tags: String
    var script: String
    var formatName: String
    var pickReason: String
    var state: String
    var renderStatus: String
    var rejectionCount: Int
    var rejectReason: String
    var postedURL: String?
    var postedAt: Double?
    var approvedAt: Double?
    var createdAt: Double
    var stepSince: Double
    var longForm: Bool
    var videoID: String?
    var madeForKids: String
    var stylePack: String

    init?(_ row: MakeStudioRow) {
        guard let id = row.int("id"), let channel = row.int("channelId"), let title = row.str("title") else { return nil }
        self.id = id
        channelID = channel
        self.title = title
        caption = row.str("caption") ?? ""
        tags = row.str("tags") ?? ""
        script = row.str("scriptRef") ?? ""
        formatName = row.str("formatName") ?? row.str("format") ?? ""
        pickReason = row.str("pickReason") ?? ""
        state = row.str("state") ?? "drafted"
        renderStatus = row.str("renderStatus") ?? "pending"
        rejectionCount = row.int("rejectionCount") ?? 0
        rejectReason = row.str("rejectReason") ?? ""
        postedURL = row.str("postedUrl")
        postedAt = row.dbl("postedAt")
        approvedAt = row.dbl("approvedAt")
        createdAt = row.dbl("createdAt") ?? 0
        stepSince = row.dbl("stepSince") ?? row.dbl("createdAt") ?? 0
        longForm = row.flag("longForm")
        videoID = row.str("videoId").flatMap { MakeStudioWire.isHex($0, 12) ? $0 : nil }
        madeForKids = MakeStudioWire.kids(row.int("madeForKids"))
        stylePack = row.str("stylePack") ?? ""
    }
}

nonisolated struct MakeStudioCheckDTO: Sendable {
    var key: String
    var text: String
    /// "kairos" or "you".
    var by: String
    var status: String
}

nonisolated struct MakeStudioPublishDTO: Sendable {
    var postID: Int
    var state: String
    var nextWho: String
    var nextWhat: String
    var scheduledAt: Double?
    var postedAt: Double?
    var postedURL: String?
    var prepID: Int?
    var problems: [String]
    var error: String
    var filled: [String]
    var missing: [String]
    var checklist: [MakeStudioCheckDTO]

    init?(_ row: MakeStudioRow) {
        guard let id = row.int("postId"), let state = row.str("state") else { return nil }
        postID = id
        self.state = state
        nextWho = row.row("next")?.str("who") ?? ""
        nextWhat = row.row("next")?.str("what") ?? ""
        scheduledAt = row.dbl("scheduledAt")
        postedAt = row.dbl("postedAt")
        postedURL = row.str("postedUrl")
        prepID = row.int("prepId")
        problems = row.strings("problems")
        error = row.str("error") ?? ""
        filled = row.row("fill")?.strings("filled") ?? []
        missing = row.row("fill")?.strings("missing") ?? []
        checklist = row.list("checklist").compactMap { item in
            guard let line = MakeStudioRow(item), let key = line.str("key"), let text = line.str("text") else { return nil }
            return MakeStudioCheckDTO(key: key, text: text, by: line.str("by") ?? "kairos", status: line.str("status") ?? "todo")
        }
    }
}

nonisolated struct MakeStudioPipelineDTO: Sendable {
    var isTopic: Bool
    var id: Int
    var title: String
    var step: String
    var owner: String
    var status: String
    var ageH: Double
    var inStepH: Double
    var windowH: Double?
    var overdue: Bool

    init?(_ row: MakeStudioRow) {
        guard let kind = row.str("kind"), let id = row.int("id") else { return nil }
        isTopic = kind == "topic"
        self.id = id
        title = row.str("title") ?? ""
        step = row.str("step") ?? ""
        owner = row.str("owner") ?? ""
        status = row.str("status") ?? ""
        ageH = row.dbl("ageH") ?? 0
        inStepH = row.dbl("inStepH") ?? row.dbl("ageH") ?? 0
        windowH = row.dbl("windowH")
        overdue = row.flag("overdue")
    }
}

nonisolated struct MakeStudioPlanDTO: Sendable {
    var videoID: String
    var title: String
    var text: String
    var chapters: [String]
    var postID: Int?
    var version: Int?

    init?(_ row: MakeStudioRow) {
        guard let id = row.str("videoId"), MakeStudioWire.isHex(id, 12) else { return nil }
        videoID = id
        title = row.str("title") ?? "Long video"
        text = row.str("text") ?? ""
        chapters = row.list("chapters").compactMap { item in
            guard let chapter = MakeStudioRow(item), let name = chapter.str("title") else { return nil }
            let start = Int(chapter.dbl("start") ?? 0)
            return "\(start / 60):" + String(format: "%02d", start % 60) + " " + name
        }
        postID = row.int("postId")
        version = row.int("version")
    }
}

nonisolated struct MakeStudioVersionDTO: Sendable {
    var id: String
    var name: String
    var family: String
    var version: Int
    var note: String

    init?(_ row: MakeStudioRow) {
        guard let id = row.str("id"), let version = row.int("version") else { return nil }
        self.id = id
        name = row.str("name") ?? "Untitled"
        family = row.str("family") ?? ""
        self.version = version
        note = row.str("note") ?? ""
    }
}

nonisolated struct MakeStudioApprovalsDTO: Sendable {
    /// The chapter lines of a long post, by post id.
    var postChapters: [Int: String] = [:]
    var waitingPostIDs: [Int] = []
    var characters: [MakeStudioVersionDTO] = []
    var packs: [MakeStudioVersionDTO] = []
    var plans: [MakeStudioPlanDTO] = []
    var skipped = 0

    init(_ root: JSONValue) {
        guard let row = MakeStudioRow(root) else { return }
        let posts = MakeStudioWire.rows(row.list("posts")) { post -> (Int, String)? in
            guard let id = post.int("id") else { return nil }
            return (id, post.str("chapters") ?? "")
        }
        for (id, chapters) in posts.rows {
            waitingPostIDs.append(id)
            if !chapters.isEmpty { postChapters[id] = chapters }
        }
        let characters = MakeStudioWire.rows(row.list("characters"), MakeStudioVersionDTO.init)
        let packs = MakeStudioWire.rows(row.list("stylePacks"), MakeStudioVersionDTO.init)
        let plans = MakeStudioWire.rows(row.list("plans"), MakeStudioPlanDTO.init)
        self.characters = characters.rows
        self.packs = packs.rows
        self.plans = plans.rows
        skipped = posts.skipped + characters.skipped + packs.skipped + plans.skipped
    }
}

nonisolated struct MakeStudioDecisionDTO: Sendable {
    var id: Int
    var kind: String
    var subjectType: String
    var subjectName: String
    var status: String
    var reason: String
    var numbers: [String: JSONValue]

    init?(_ row: MakeStudioRow) {
        guard let id = row.int("id"), let kind = row.str("kind"), let status = row.str("status") else { return nil }
        self.id = id
        self.kind = kind
        subjectType = row.str("subjectType") ?? ""
        subjectName = row.str("subjectName") ?? ""
        self.status = status
        reason = row.str("reason") ?? ""
        numbers = row.row("numbers")?.o ?? [:]
    }
}

nonisolated struct MakeStudioScoreRowDTO: Sendable {
    var name: String
    var score: Double?
    var postsScored: Int
    var ageDays: Int
    var eligible: Bool
    var notYet: String
    var retired: Bool
    var available: Bool

    init?(_ row: MakeStudioRow) {
        guard let name = row.str("name") else { return nil }
        self.name = name
        score = row.dbl("score")
        postsScored = row.int("postsScored") ?? 0
        ageDays = Int(row.dbl("ageDays") ?? 0)
        eligible = row.flag("eligible")
        notYet = row.str("notYet") ?? ""
        let status = row.str("status") ?? ""
        retired = status == "retired"
        available = row.value("available") == nil ? true : row.flag("available")
    }
}

nonisolated struct MakeStudioScoreboardDTO: Sendable {
    var niches: [MakeStudioScoreRowDTO] = []
    var formats: [MakeStudioScoreRowDTO] = []
    var packs: [MakeStudioScoreRowDTO] = []
    var topPosts: [Int] = []
    var postsScored = 0
    var postsPosted = 0

    init(_ root: JSONValue) {
        guard let row = MakeStudioRow(root) else { return }
        niches = MakeStudioWire.rows(row.list("niches"), MakeStudioScoreRowDTO.init).rows
        formats = MakeStudioWire.rows(row.list("formats"), MakeStudioScoreRowDTO.init).rows
        packs = MakeStudioWire.rows(row.list("stylePacks"), MakeStudioScoreRowDTO.init).rows
        topPosts = MakeStudioWire.rows(row.list("topPosts")) { $0.int("postId") }.rows
        postsScored = row.int("postsScored") ?? 0
        postsPosted = row.int("postsPosted") ?? 0
    }
}

nonisolated struct MakeStudioSettingsDTO: Sendable {
    /// views, watch and engagement as the desktop keeps them (parts of a whole).
    var weights: [Double] = [0.4, 0.4, 0.2]
    var batchApproval = false
    var handsOff = false
    var teamPaused = false

    init(_ root: JSONValue) {
        guard let row = MakeStudioRow(root) else { return }
        if let parts = row.row("weights"), let views = parts.dbl("views"), let watch = parts.dbl("watch"), let engagement = parts.dbl("engagement") {
            weights = [views, watch, engagement]
        }
        batchApproval = row.flag("batchApproval")
        handsOff = row.flag("handsOff")
        teamPaused = row.flag("teamPaused")
    }
}

nonisolated struct MakeStudioHandsOffDTO: Sendable {
    var on = false
    var paused = false
    var taps = 0
    /// The answer really said whether hands-off posting is on (a true or false, or 1 or 0). When it did not, the
    /// phone treats the state as not known.
    var readable = false

    init(_ root: JSONValue) {
        guard let row = MakeStudioRow(root) else { return }
        readable = row.value("on")?.bool != nil || row.value("on")?.int != nil
        on = row.flag("on")
        paused = row.flag("paused")
        taps = row.list("taps").count
    }
}

nonisolated struct MakeStudioSetupDTO: Sendable {
    var imported = false
    var cycleRunning = false
    var lastRunStarted: Double?
    var lastRunStatus = ""
    var monthlyCap: Double?
    var spent: Double?

    init(_ root: JSONValue) {
        guard let row = MakeStudioRow(root), let team = row.row("team") else { return }
        imported = team.flag("imported")
        if let cycle = team.row("cycle") {
            cycleRunning = cycle.flag("running")
            lastRunStarted = cycle.row("lastRun")?.dbl("startedAt")
            lastRunStatus = cycle.row("lastRun")?.str("status") ?? ""
        }
        monthlyCap = team.row("budget")?.dbl("monthlyUsd")
        spent = team.row("budget")?.dbl("spentUsd")
    }
}

nonisolated struct MakeStudioReportDTO: Sendable {
    var from: Double?
    var to: Double?
    var lines: [String] = []

    init(_ root: JSONValue) {
        guard let row = MakeStudioRow(root) else { return }
        from = row.dbl("from")
        to = row.dbl("to")
        lines = (row.str("text") ?? "").split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

nonisolated struct MakeStudioWarningDTO: Sendable {
    var channelID: Int
    var message: String
}

nonisolated struct MakeStudioNumbersDTO: Sendable {
    var views: Int
    var averageView: Int
    var likes: Int
    var comments: Int
    var shares: Int
    var follows: Int
    var source: String
    var takenAt: Double?
}

nonisolated struct MakeStudioDetailDTO: Sendable {
    var latest: MakeStudioNumbersDTO?
    var sets = 0
    var chapters = ""

    init(_ root: JSONValue) {
        guard let row = MakeStudioRow(root) else { return }
        chapters = row.str("chapters") ?? ""
        let found = MakeStudioWire.rows(row.list("metrics")) { metric -> MakeStudioNumbersDTO? in
            guard let views = metric.int("views") else { return nil }
            return MakeStudioNumbersDTO(views: views, averageView: Int(metric.dbl("avgViewDurationS") ?? 0), likes: metric.int("likes") ?? 0,
                                        comments: metric.int("comments") ?? 0, shares: metric.int("shares") ?? 0,
                                        follows: metric.int("followsGained") ?? 0, source: metric.str("source") ?? "manual",
                                        takenAt: metric.dbl("takenAt"))
        }.rows
        sets = found.count
        latest = found.max { ($0.takenAt ?? 0) < ($1.takenAt ?? 0) }
    }
}

nonisolated struct MakeStudioPackChoiceDTO: Sendable {
    var id: String
    var name: String

    init?(_ row: MakeStudioRow) {
        guard let id = row.str("id"), let name = row.str("name") else { return nil }
        if row.value("available") != nil, !row.flag("available") { return nil }
        self.id = id
        self.name = name
    }
}

// MARK: - Calls

extension APIClient {
    private static let studio = "/api/content-studio"

    func makeStudioNiches() async throws -> JSONValue { try await get(Self.studio + "/niches") }
    func makeStudioChannels() async throws -> JSONValue { try await get(Self.studio + "/channels") }
    func makeStudioPosts() async throws -> JSONValue { try await get(Self.studio + "/posts") }
    func makeStudioPublishing() async throws -> JSONValue { try await get(Self.studio + "/publishing") }
    func makeStudioPipeline() async throws -> JSONValue { try await get(Self.studio + "/pipeline") }
    func makeStudioApprovals() async throws -> JSONValue { try await get(Self.studio + "/approvals") }
    func makeStudioDecisions() async throws -> JSONValue { try await get(Self.studio + "/decisions") }
    func makeStudioScoreboard() async throws -> JSONValue { try await get(Self.studio + "/scoreboard") }
    func makeStudioSettings() async throws -> JSONValue { try await get(Self.studio + "/settings") }
    func makeStudioHandsOff() async throws -> JSONValue { try await get(Self.studio + "/hands-off") }
    func makeStudioSetup() async throws -> JSONValue { try await get(Self.studio + "/setup") }
    func makeStudioReport() async throws -> JSONValue { try await get(Self.studio + "/report") }
    func makeStudioWatch() async throws -> JSONValue { try await get(Self.studio + "/watch") }
    func makeStudioFormats() async throws -> JSONValue { try await get(Self.studio + "/formats") }

    func makeStudioPostDetail(_ id: Int) async throws -> JSONValue { try await get(Self.studio + "/posts/\(id)") }

    /// GET /api/videos/{id}/plan: {status, version, ...}. Read right before a plan is decided.
    func makeStudioPlanState(_ videoID: String) async throws -> JSONValue {
        try await get("/api/videos/" + MakeStudioWire.pathID(videoID) + "/plan")
    }

    // Writes. None takes a request id.

    func makeStudioApprove(_ id: Int) async throws {
        try await call("POST", Self.studio + "/posts/\(id)/approve", json: [:])
    }

    func makeStudioApproveBatch(_ ids: [Int]) async throws -> JSONValue {
        try await post(Self.studio + "/approvals/approve-batch", json: ["post_ids": ids])
    }

    func makeStudioReject(_ id: Int, reason: String) async throws {
        try await call("POST", Self.studio + "/posts/\(id)/reject", json: ["reason": String(reason.prefix(MakeStudioWire.reasonLimit))])
    }

    func makeStudioRedraft(_ id: Int) async throws {
        try await call("POST", Self.studio + "/posts/\(id)/redraft", json: [:])
    }

    func makeStudioPrepare(_ id: Int) async throws {
        try await call("POST", Self.studio + "/posts/\(id)/prepare", json: [:])
    }

    func makeStudioPlanDecide(_ videoID: String, approve: Bool, reason: String) async throws {
        let path = "/api/videos/" + (try MakeStudioWire.pathID(videoID)) + "/plan/" + (approve ? "approve" : "reject")
        try await call("POST", path, json: approve ? [:] : ["reason": String(reason.prefix(MakeStudioWire.reasonLimit))])
    }

    func makeStudioSheetDecide(_ characterID: String, version: Int, approve: Bool, reason: String) async throws {
        let path = "/api/characters/" + (try MakeStudioWire.pathID(characterID)) + "/versions/\(version)/" + (approve ? "approve" : "reject")
        try await call("POST", path, json: approve ? [:] : ["reason": String(reason.prefix(MakeStudioWire.reasonLimit))])
    }

    func makeStudioPackDecide(_ packID: String, version: Int, approve: Bool, reason: String) async throws {
        let path = "/api/style-packs/" + (try MakeStudioWire.pathID(packID)) + "/versions/\(version)/" + (approve ? "approve" : "reject")
        try await call("POST", path, json: approve ? [:] : ["reason": String(reason.prefix(MakeStudioWire.reasonLimit))])
    }

    /// Hands-off posting off. Turning it on is never sent from the phone.
    func makeStudioHandsOffTurnOff() async throws {
        try await call("PUT", Self.studio + "/hands-off", json: ["on": false])
    }

    func makeStudioTeamPause(_ on: Bool) async throws {
        try await call("PUT", Self.studio + "/team-pause", json: ["on": on])
    }

    func makeStudioResume(_ channelID: Int) async throws {
        try await call("POST", Self.studio + "/channels/\(channelID)/resume", json: [:])
    }

    func makeStudioArchive(_ channelID: Int) async throws {
        try await call("POST", Self.studio + "/channels/\(channelID)/archive", json: ["reason": "Archived from the iPhone app"])
    }

    /// Only the fields the person changed, with the desktop's own values (ChannelEditBody).
    func makeStudioEditChannel(_ channelID: Int, fields: [String: Any]) async throws {
        try await call("POST", Self.studio + "/channels/\(channelID)/edit", json: fields)
    }

    func makeStudioDecisionConfirm(_ id: Int) async throws {
        try await call("POST", Self.studio + "/decisions/\(id)/confirm", json: ["actor": "user"])
    }

    func makeStudioDecisionReject(_ id: Int) async throws {
        try await call("POST", Self.studio + "/decisions/\(id)/reject", json: ["actor": "user"])
    }

    /// Puts the weekly report in the Inbox. Sends a message, takes no request id.
    func makeStudioReportSend() async throws -> JSONValue {
        try await post(Self.studio + "/report/send", json: [:])
    }
}

// MARK: - Samples

/// A sample answer for every Studio route this app reads, shaped like the desktop's own (made-up content).
nonisolated enum MakeStudioSamples {

    static let niches = #"""
    {"niches": [{"id": 1, "name": "Bike care", "status": "live", "slots": 2, "created_at": 1792000000.5, "retired_at": null},
                {"id": 2, "name": "Small gardens", "status": "retired", "slots": 1, "created_at": 1792000100},
                {"name": "No id"}], "max_live": 5}
    """#

    static let channels = #"""
    {"channels": [
      {"id": 7, "niche_id": 1, "platform": "youtube", "handle": "@trailtips", "status": "live", "paused": 0, "look": null,
       "aspect": "9:16", "notes": "Calm and clear.", "voice": "af_heart", "style_pack": "motion-type", "long_per_week": 1,
       "renderer": null, "fps": null, "made_for_kids": 0, "niche_name": "Bike care", "created_at": 1792000200},
      {"id": 8, "niche_id": 1, "platform": "tiktok", "handle": "@spokeshorts", "status": "live", "paused": 1, "look": "warm",
       "aspect": null, "notes": "", "voice": null, "style_pack": null, "long_per_week": null, "renderer": "threejs", "fps": 60,
       "made_for_kids": null, "niche_name": "Bike care"},
      {"platform": "youtube"}
    ]}
    """#

    static let posts = #"""
    {"posts": [
      {"id": 31, "channel_id": 7, "title": "Clean your chain in 60 seconds", "caption": "A clean chain shifts better.",
       "tags": "bike care, chain", "script_ref": "Most chains are dirty.", "format": null, "format_name": "One fix, one minute",
       "pick_reason": "Chain care questions doubled.", "state": "awaiting_approval", "render_status": "ok", "rejection_count": 0,
       "reject_reason": null, "posted_url": null, "posted_at": null, "approved_at": null, "created_at": 1793000000,
       "step_since": 1792990000, "long_form": 0, "video_id": null, "made_for_kids": null, "style_pack": "motion-type",
       "platform": "youtube", "handle": "@trailtips", "niche_id": 1, "niche_name": "Bike care", "render_ref": "/private/path/x.mp4",
       "approved_by": "alex"},
      {"id": 32, "channel_id": 7, "title": "A full tune-up", "caption": "", "tags": "", "script_ref": null, "state": "posted",
       "render_status": "ok", "rejection_count": 2, "reject_reason": "Too long", "posted_url": "https://example.com/watch/abc",
       "posted_at": 1792900000, "approved_at": 1792800000, "created_at": 1792700000, "step_since": 1792900000, "long_form": 1,
       "video_id": "a1b2c3d4e5f6", "made_for_kids": 1, "style_pack": null, "platform": "youtube", "handle": "@trailtips",
       "niche_id": 1, "niche_name": "Bike care"},
      {"title": "No id"}
    ]}
    """#

    static let publishing = #"""
    {"items": [
      {"post_id": 31, "title": "Clean your chain", "platform": "youtube", "state": "awaiting_approval", "state_label": "Waiting for your approval",
       "next": {"who": "you", "what": "Approve, edit or reject it in Approvals."}, "scheduled_at": null, "posted_at": null,
       "posted_url": null, "prep_id": null, "problems": [], "error": "", "fill": {}, "checklist": []},
      {"post_id": 33, "title": "Lights", "state": "prepared", "next": {"who": "you", "what": "Press Open upload page."},
       "scheduled_at": 1793100000.0, "prep_id": 5, "problems": ["The video is 3:10."], "error": "",
       "fill": {"stage": "done", "filled": ["title"], "missing": ["thumbnail"], "note": ""},
       "checklist": [{"key": "title", "text": "Title", "by": "kairos", "status": "todo"}, {"key": "thumbnail", "text": "Thumbnail", "by": "you", "status": "todo"}, {"text": "no key"}]},
      {"title": "No post id"}
    ], "counts": {"posted": 1}, "labels": {}, "now": 1793000000, "this_week": 1792800000}
    """#

    static let pipeline = #"""
    {"items": [
      {"kind": "topic", "id": 4, "title": "Icing without a bag", "niche_id": 2, "step": "pick", "owner": "evaluator", "status": "candidate", "age_h": 1.5, "in_step_h": 1.5, "window_h": 24},
      {"kind": "post", "id": 31, "title": "Clean your chain", "step": "approval", "owner": "user", "status": "waiting", "state": "awaiting_approval",
       "age_h": 5.2, "in_step_h": 5.2, "window_h": 48, "rejection_count": 0, "posted_url": null, "overdue": false},
      {"kind": "post", "id": 35, "title": "Pick the right pump", "step": "render", "owner": "editor", "status": "failed", "state": "drafted",
       "age_h": 14, "in_step_h": 14, "window_h": 6, "overdue": false},
      {"id": 9}
    ]}
    """#

    static let approvals = #"""
    {"posts": [{"id": 31, "title": "Clean your chain", "chapters": ""}, {"id": 32, "chapters": "0:00 Start\n1:05 Brakes"}, {"title": "no id"}],
     "characters": [{"id": "a1b2c3d4e5f6", "name": "Pip", "family": "Round", "version": 2, "status": "awaiting_approval", "note": "Adds a scarf.",
                     "created": 1792000000, "by": "alex", "sheet": true, "metrics": null, "submitted_at": 1792990000}],
     "style_packs": [{"id": "f0e1d2c3b4a5", "name": "Flat 2D explainer", "version": 2, "status": "awaiting_approval", "note": "Softer colours.", "by": "alex", "submitted_at": 1792991000}],
     "plans": [{"video_id": "a1b2c3d4e5f6", "title": "A full tune-up", "text": "Shot plan\nChapter 1 at 0:00: Start", "seconds": 512.4,
                "chapters": [{"title": "Start", "start": 0}, {"title": "Brakes", "start": 65.5}], "submitted_by": "Producer", "submitted_at": 1792992000, "post_id": 32, "version": 3},
               {"video_id": "short", "title": "bad id"}]}
    """#

    static let decisions = #"""
    {"decisions": [
      {"id": 3, "kind": "retire", "subject_type": "niche", "subject_id": 2, "subject_name": "Small gardens",
       "numbers": {"score": 22.0, "team_median": 58.2, "posts_scored": 9, "age_days": 60, "freed_slots": 1, "winner": {"id": 1, "name": "Bike care", "score": 71.4}},
       "reason": "Below 50% of the team median.", "payload": {}, "status": "awaiting_user", "proposed_by": "executor"},
      {"id": 4, "kind": "add", "subject_type": "niche", "subject_id": 0, "subject_name": "Commuter tips", "numbers": {"live_niches": 2, "cap": 5}, "reason": "A candidate.", "status": "proposed"},
      {"kind": "retire"}
    ]}
    """#

    static let scoreboard = #"""
    {"at": 1793000000, "weights": {"views": 0.4, "watch": 0.4, "engagement": 0.2}, "minimum": {"weeks": 3, "posts": 10},
     "niches": [{"id": 1, "name": "Bike care", "status": "live", "slots": 2, "score": 71.4, "posts_scored": 18, "age_days": 30.2, "eligible": true},
                {"id": 2, "name": "Small gardens", "status": "retired", "slots": 1, "score": null, "posts_scored": 0, "age_days": 0, "eligible": false, "not_yet": "0 of 10 posts with 7 day numbers"}],
     "strategies": {"script_writer": []},
     "formats": [{"id": 1, "name": "One fix, one minute", "kind": "card", "status": "active", "score": 74.1, "posts_scored": 12, "age_days": 30, "eligible": true}],
     "style_packs": [{"id": "motion-type", "name": "Motion type", "available": true, "score": 69.8, "posts_scored": 15, "age_days": 30, "eligible": true}],
     "top_posts": [{"post_id": 32, "title": "A full tune-up", "platform": "youtube", "score": 80.5}], "posts_scored": 18, "posts_posted": 24}
    """#

    static let settings = #"""
    {"weights": {"views": 0.4, "watch": 0.4, "engagement": 0.2}, "batch_approval": true, "hands_off": false, "hands_off_since": null,
     "hands_off_by": null, "team_paused": true, "page_reads": {"tiktok": false, "instagram": false}, "team_roles": {}}
    """#

    static let handsOff = #"""
    {"on": true, "paused": false, "since": 1792000000, "by": "alex", "taps": [{"post_id": 8, "title": "Tyres", "handle": "@spokeshorts"}]}
    """#

    static let setup = #"""
    {"dismissed": false, "hands_off": {"on": false, "paused": false},
     "team": {"imported": true, "bots": [{"id": "b1", "name": "Producer", "role": "producer", "mode": "ask"}], "routines": [],
              "cycle": {"id": "r1", "name": "Content setup: one cycle now", "bot_id": "b1", "enabled": false, "running": true,
                        "last_run": {"status": "running", "started_at": 1793000500.5, "finished_at": null}},
              "producer": "b1", "budget": {"monthly_usd": 40.0, "spent_usd": 14.25}}}
    """#

    static let report = #"""
    {"from": 1792400000, "to": 1793000000, "text": "Content Studio weekly report\n\nWhat won: Bike care (71.4).\nRetiring: nothing waiting.\n",
     "spend": {"available": true, "cap_usd": 40, "all_bots_spent_usd": 14.25, "team_spent_usd": null}, "hands_off": false}
    """#

    static let watch = #"""
    {"findings": [{"kind": "platform_warning", "severity": "urgent", "message": "youtube warned @trailtips: a reused audio claim. The channel is paused.", "notify_user": true, "channel_id": 8, "warning_id": 2},
                  {"kind": "spend_near_cap", "severity": "urgent", "message": "Spend is near the monthly cap."}]}
    """#

    static let detail = #"""
    {"id": 32, "title": "A full tune-up", "state": "posted", "chapters": "0:00 Start\n1:05 Brakes",
     "metrics": [{"id": 1, "post_id": 32, "taken_at": 1792950000, "views": 900, "avg_view_duration_s": 31.5, "video_length_s": 60, "likes": 40, "comments": 3, "shares": 2, "follows_gained": 5, "source": "manual", "official": false},
                 {"id": 2, "post_id": 32, "taken_at": 1793000000, "views": 1200, "avg_view_duration_s": 33, "video_length_s": 60, "likes": 52, "comments": 4, "shares": 3, "follows_gained": 7, "source": "youtube_api", "official": true}],
     "evidence": [{"kind": "approval", "body": {"by": "alex"}}], "direct_post_blocker": null, "api_connected": true}
    """#

    static let packs = #"""
    {"formats": [], "ports": [], "style_packs": [{"id": "motion-type", "name": "Motion type", "available": true},
      {"id": "flat-2d", "name": "Flat 2D explainer", "available": true}, {"id": "glossy-3d", "name": "Glossy 3D mascot", "available": false}]}
    """#

    static let planState = #"""
    {"chaptered": true, "status": "awaiting_approval", "hash": "0a1b2c3d4e5f60718293a4b5", "version": 3, "text": "Shot plan", "current": "Shot plan"}
    """#

    static let batch = #"""
    {"approved": [{"id": 31, "state": "approved"}], "skipped": [{"post_id": 36, "reason": "that channel is archived or paused"}]}
    """#

    static let conflict = #"{"detail": "This routine is already running."}"#

    static let checks: [DecodeCheck] = [
        DecodeCheck("makestudio.niches-channels") {
            let niches = MakeStudioWire.rows(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.niches).object?["niches"]?.array ?? [], MakeStudioNicheDTO.init)
            let channels = MakeStudioWire.rows(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.channels).object?["channels"]?.array ?? [], MakeStudioChannelDTO.init)
            guard niches.rows.count == 2, niches.skipped == 1, niches.rows[1].retired, niches.rows[0].slots == 2,
                  channels.rows.count == 2, channels.skipped == 1, channels.rows[0].madeForKids == "no", channels.rows[0].look.isEmpty,
                  channels.rows[0].fps == nil, channels.rows[0].longPerWeek == 1, channels.rows[1].paused, channels.rows[1].madeForKids.isEmpty,
                  channels.rows[1].fps == 60, channels.rows[1].renderer == "threejs", !channels.rows[0].archived else {
                throw SampleMismatch("niche or channel fields")
            }
            return "2 niches, 2 channels, odd rows skipped"
        },
        DecodeCheck("makestudio.posts") {
            let list = MakeStudioWire.rows(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.posts).object?["posts"]?.array ?? [], MakeStudioPostDTO.init)
            guard list.rows.count == 2, list.skipped == 1, list.rows[0].state == "awaiting_approval", list.rows[0].script.hasPrefix("Most"),
                  list.rows[0].formatName == "One fix, one minute", list.rows[0].madeForKids.isEmpty, list.rows[0].videoID == nil,
                  list.rows[1].longForm, list.rows[1].videoID == "a1b2c3d4e5f6", list.rows[1].madeForKids == "yes",
                  list.rows[1].postedURL == "https://example.com/watch/abc", list.rows[1].rejectionCount == 2,
                  list.rows[1].script.isEmpty else { throw SampleMismatch("post fields") }
            return "2 posts, 1 skipped, render path left out"
        },
        DecodeCheck("makestudio.publishing-pipeline") {
            let items = MakeStudioWire.rows(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.publishing).object?["items"]?.array ?? [], MakeStudioPublishDTO.init)
            let steps = MakeStudioWire.rows(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.pipeline).object?["items"]?.array ?? [], MakeStudioPipelineDTO.init)
            guard items.rows.count == 2, items.skipped == 1, items.rows[0].nextWho == "you", items.rows[0].prepID == nil,
                  items.rows[1].scheduledAt == 1_793_100_000, items.rows[1].missing == ["thumbnail"], items.rows[1].checklist.count == 2,
                  items.rows[1].problems.count == 1, items.rows[1].prepID == 5,
                  steps.rows.count == 3, steps.skipped == 1, steps.rows[0].isTopic, steps.rows[1].step == "approval",
                  steps.rows[2].status == "failed", steps.rows[2].windowH == 6, !steps.rows[2].overdue else {
                throw SampleMismatch("publishing or pipeline fields")
            }
            return "2 publishing items, 3 pipeline items"
        },
        DecodeCheck("makestudio.approvals") {
            let read = MakeStudioApprovalsDTO(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.approvals))
            guard read.waitingPostIDs == [31, 32], read.postChapters[32]?.hasPrefix("0:00") == true, read.postChapters[31] == nil,
                  read.characters.count == 1, read.characters[0].version == 2, read.characters[0].id == "a1b2c3d4e5f6",
                  read.packs.count == 1, read.packs[0].name == "Flat 2D explainer",
                  read.plans.count == 1, read.plans[0].version == 3, read.plans[0].postID == 32,
                  read.plans[0].chapters == ["0:00 Start", "1:05 Brakes"], read.skipped == 2 else {
                throw SampleMismatch("approvals fields")
            }
            return "2 waiting posts, a sheet, a pack, a plan"
        },
        DecodeCheck("makestudio.decisions-scoreboard") {
            let decisions = MakeStudioWire.rows(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.decisions).object?["decisions"]?.array ?? [], MakeStudioDecisionDTO.init)
            let board = MakeStudioScoreboardDTO(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.scoreboard))
            guard decisions.rows.count == 2, decisions.skipped == 1, decisions.rows[0].status == "awaiting_user",
                  MakeStudioRow(.object(decisions.rows[0].numbers))?.int("postsScored") == 9, decisions.rows[1].kind == "add",
                  board.niches.count == 2, board.niches[0].score == 71.4, board.niches[1].score == nil, board.niches[1].retired,
                  board.formats.count == 1, board.packs.count == 1, board.topPosts == [32], board.postsScored == 18 else {
                throw SampleMismatch("decision or scoreboard fields")
            }
            return "2 decisions, scoreboard with 2 niches"
        },
        DecodeCheck("makestudio.settings-state") {
            let settings = MakeStudioSettingsDTO(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.settings))
            let hands = MakeStudioHandsOffDTO(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.handsOff))
            let handsNull = MakeStudioHandsOffDTO(try KJSON.decode(JSONValue.self, from: #"{"on": null, "paused": false}"#))
            let handsMissing = MakeStudioHandsOffDTO(try KJSON.decode(JSONValue.self, from: #"{"paused": false}"#))
            let setup = MakeStudioSetupDTO(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.setup))
            let report = MakeStudioReportDTO(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.report))
            guard settings.batchApproval, settings.teamPaused, !settings.handsOff, settings.weights == [0.4, 0.4, 0.2],
                  hands.on, hands.readable, !hands.paused, hands.taps == 1,
                  !handsNull.readable, !handsMissing.readable,
                  setup.imported, setup.cycleRunning, setup.monthlyCap == 40, setup.spent == 14.25, setup.lastRunStarted == 1_793_000_500.5,
                  report.lines.count == 3, report.lines[0] == "Content Studio weekly report", report.from == 1_792_400_000 else {
                throw SampleMismatch("settings, hands-off, setup or report fields")
            }
            return "settings, hands-off, setup and report"
        },
        DecodeCheck("makestudio.detail-packs-misc") {
            let detail = MakeStudioDetailDTO(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.detail))
            let packs = MakeStudioWire.rows(MakeStudioRow(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.packs))?.list("stylePacks") ?? [], MakeStudioPackChoiceDTO.init)
            let plan = MakeStudioRow(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.planState))
            let batch = try KJSON.decode(JSONValue.self, from: MakeStudioSamples.batch)
            let clash = try KJSON.decode(APIErrorBody.self, from: MakeStudioSamples.conflict)
            let watch = MakeStudioWire.rows(try KJSON.decode(JSONValue.self, from: MakeStudioSamples.watch).object?["findings"]?.array ?? []) { row -> MakeStudioWarningDTO? in
                guard row.str("kind") == "platform_warning", let channel = row.int("channelId"), let message = row.str("message") else { return nil }
                return MakeStudioWarningDTO(channelID: channel, message: message)
            }
            guard detail.sets == 2, detail.latest?.views == 1200, detail.latest?.averageView == 33, detail.latest?.follows == 7,
                  detail.chapters.hasPrefix("0:00"),
                  packs.rows.count == 2, packs.skipped == 1, packs.rows[1].id == "flat-2d",
                  plan?.str("status") == "awaiting_approval", plan?.int("version") == 3,
                  batch.object?["approved"]?.array?.count == 1, batch.object?["skipped"]?.array?.count == 1,
                  clash.text == "This routine is already running.",
                  watch.rows.count == 1, watch.rows[0].channelID == 8,
                  (try? MakeStudioWire.pathID("a1b2c3d4e5f6")) != nil, (try? MakeStudioWire.pathID("../x")) == nil else {
                throw SampleMismatch("detail, packs, plan state, batch, conflict or warnings")
            }
            return "detail with 2 number sets, packs, plan state, batch, conflict, warning"
        },
    ]
}
