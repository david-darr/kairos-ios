import SwiftUI
import UIKit

/// Where Studio's read of the desktop stands, for one plain sentence on screen.
nonisolated enum MakeStudioLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// How one change to the desktop ended.
nonisolated enum MakeStudioOutcome: Equatable, Sendable {
    case done(String)
    /// The desktop said no, so it certainly did not do it.
    case refused(String)
    /// The answer never arrived. The desktop may have done it.
    case unconfirmed(String)
    /// Not sent: another change to the same thing is still on its way.
    case busy

    var line: String {
        switch self {
        case .done(let text), .refused(let text), .unconfirmed(let text): text
        case .busy: "The last change to this is still on its way to your desktop."
        }
    }
}

/// What a re-read of the desktop says about a change whose answer was lost.
nonisolated enum MakeStudioVerdict: Sendable {
    case applied, notApplied, unknown
}

/// A change that left the phone and has no answer yet, or whose answer was lost. Kept in the shared store
/// by account and item, so leaving the screen or reading again never turns its button back on.
nonisolated struct MakeStudioPending: Hashable, Sendable {
    var key: String
    var lost = false
    var note = ""
}

/// The desktop's own state said the change should not go ahead (a plan that changed, a run that was refused).
nonisolated struct MakeStudioChanged: Error, Sendable {
    var words: String
}

/// Everything one read of the desktop brings back.
nonisolated struct MakeStudioSnapshot: Sendable {
    var niches: [MakeStudioNicheDTO] = []
    var channels: [MakeStudioChannelDTO] = []
    var posts: [MakeStudioPostDTO] = []
    var publishing: [MakeStudioPublishDTO] = []
    var pipeline: [MakeStudioPipelineDTO]?
    var approvals = MakeStudioApprovalsDTO(.null)
    var decisions: [MakeStudioDecisionDTO]?
    var scoreboard: MakeStudioScoreboardDTO?
    var settings: MakeStudioSettingsDTO?
    var handsOff: MakeStudioHandsOffDTO?
    var setup: MakeStudioSetupDTO?
    var report: MakeStudioReportDTO?
    var warnings: [MakeStudioWarningDTO]?
    var skipped = 0
    var missing: [String] = []
}

/// The channel look fields the phone edits, as the desktop names their values.
nonisolated enum MakeStudioField: String, CaseIterable, Hashable, Sendable {
    case pack, renderer, look, aspect, fps, voice, kids, long, notes
}

/// One channel's look form. It remembers the desktop values it was filled from. A read under it only moves the
/// fields the person has not touched, and a save sends only the fields the person changed.
@Observable
final class MakeStudioChannelForm {
    private(set) var shown: [MakeStudioField: String] = [:]
    private(set) var base: [MakeStudioField: String] = [:]
    private(set) var touched: Set<MakeStudioField> = []

    init(_ channel: MakeStudioChannelDTO) {
        let values = Self.values(channel)
        shown = values
        base = values
    }

    static func values(_ channel: MakeStudioChannelDTO) -> [MakeStudioField: String] {
        [.pack: channel.stylePack, .renderer: channel.renderer, .look: channel.look, .aspect: channel.aspect,
         .fps: channel.fps == 60 ? "60" : "30", .voice: channel.voice, .kids: channel.madeForKids,
         .long: String(channel.longPerWeek ?? (channel.platform == "youtube" ? 1 : 0)), .notes: channel.notes]
    }

    func set(_ field: MakeStudioField, _ value: String) {
        shown[field] = value
        if value == base[field] { touched.remove(field) } else { touched.insert(field) }
    }

    /// A read came back: untouched fields follow the desktop, edited ones keep what the person typed.
    func refill(_ channel: MakeStudioChannelDTO) {
        let values = Self.values(channel)
        for field in MakeStudioField.allCases {
            let now = values[field] ?? ""
            base[field] = now
            if touched.contains(field) {
                if shown[field] == now { touched.remove(field) }
            } else {
                shown[field] = now
            }
        }
    }

    /// The fields the person changed that still differ from the desktop.
    var changes: [MakeStudioField: String] {
        var out: [MakeStudioField: String] = [:]
        for field in touched {
            if let value = shown[field], value != base[field] { out[field] = value }
        }
        return out
    }

    /// The person's edits are on the desktop now: the form stops calling them edits.
    func settle(_ sent: [MakeStudioField: String]) {
        for (field, value) in sent where shown[field] == value { touched.remove(field) }
    }
}

/// The paired desktop behind Studio: niches, channels, posts, approvals, pipeline, publishing, scoreboard, report and
/// settings (all reads), and the changes the phone may make (approve, reject, redraft, prepare, decide a plan, a
/// character sheet or a style pack, hands-off off, pause or resume the team, resume or archive or edit a channel,
/// confirm or reject a decision, run one cycle, send the report). Posting to any platform, scheduling, marking
/// posted, hands-off on, accounts and keys, metrics import and routines on stay on the desktop.
/// Unpaired, nothing here runs and Studio is its sample.
@Observable
final class MakeStudioLive {
    static let shared = MakeStudioLive()

    private(set) var isLive = false
    private(set) var account = "sample"
    private(set) var load: MakeStudioLoad = .idle
    /// One line when a part of Studio could not be read this time. What was read before stays on screen.
    private(set) var problem: String?
    private(set) var setup: MakeStudioSetupDTO?
    private(set) var looks: [Int: MakeStudioChannelDTO] = [:]
    private(set) var packChoices: [MakeStudioPackChoiceDTO] = []
    private(set) var forms: [Int: MakeStudioChannelForm] = [:]
    private(set) var planVersions: [String: Int] = [:]
    /// Changes that have left the phone and are not settled, by account and item. Never cleared by a screen.
    private(set) var pendingMap: [String: MakeStudioPending] = [:]
    /// Accounts whose weekly report was sent from this phone in this run of the app.
    private(set) var reportSent: Set<String> = []
    private(set) var skipped = 0

    @ObservationIgnored private var details: [String: MakeStudioDetailDTO] = [:]
    @ObservationIgnored private var verifiers: [String: () -> MakeStudioVerdict] = [:]
    @ObservationIgnored private var cycleSince: [String: Date] = [:]
    @ObservationIgnored private weak var studio: StudioStore?
    @ObservationIgnored private var readSerial = 0
    @ObservationIgnored private var writeSerial = 0
    @ObservationIgnored private var inFlight = 0
    @ObservationIgnored private var numbersTask: Task<Void, Never>?

    static let desktopChanged = "Your paired desktop changed. Try again."

    // MARK: Connection

    /// Paired with a desktop (whether or not it is answering): Studio never shows its sample items.
    static var paired: Bool { !Connection.shared.usesSampleData }

    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// Which desktop and which account the data belongs to. Live data is only ever shown under this key.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    func stillLive(_ key: String) -> Bool {
        isLive && account == key && Self.accountKey == key
    }

    /// The screen may draw the desktop's Studio.
    func showing(_ studio: StudioStore) -> Bool {
        isLive && studio.isLive && account == Self.accountKey && load == .loaded
    }

    /// Follow pairing: paired fills the store from the desktop, unpaired puts the sample back.
    func follow(_ studio: StudioStore) {
        self.studio = studio
        let key = Self.accountKey
        if Self.paired {
            guard !isLive || account != key || !studio.isLive else { return }
            reset()
            isLive = true
            account = key
            studio.beginLive()
        } else if isLive || studio.isLive {
            reset()
            isLive = false
            account = "sample"
            studio.restoreSample()
        }
    }

    private func reset() {
        load = .idle
        problem = nil
        setup = nil
        looks = [:]
        packChoices = []
        forms = [:]
        planVersions = [:]
        skipped = 0
        details = [:]
        numbersTask?.cancel()
        numbersTask = nil
        readSerial += 1
    }

    private func client() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    // MARK: Pending changes

    private static func slot(_ account: String, _ key: String) -> String { account + "|" + key }

    func pending(_ key: String) -> MakeStudioPending? { pendingMap[Self.slot(account, key)] }

    func isBusy(_ key: String) -> Bool { pending(key) != nil }

    /// A change of any kind is on its way (the screen keeps its sheets from closing meanwhile).
    var writing: Bool { inFlight > 0 }

    // MARK: Reading

    func loadLiveIfNeeded() async {
        switch load {
        case .idle, .failed: await loadLive()
        case .loading, .loaded: break
        }
    }

    /// Read everything Studio shows. What was read before stays on screen while this runs. An older read never
    /// replaces a newer one, and a read that was on its way while a change finished is read again.
    @discardableResult
    func loadLive() async -> Bool {
        guard isLive, let studio else { return false }
        let key = account
        readSerial += 1
        let mine = readSerial
        if load != .loaded { load = .loading }
        for _ in 0..<4 {
            let writes = writeSerial
            if inFlight > 0 {
                try? await Task.sleep(for: .milliseconds(500))
                guard stillLive(key), mine == readSerial else { return false }
                continue
            }
            do {
                let snapshot = try await fetch(try client())
                guard stillLive(key), mine == readSerial else { return false }
                guard writes == writeSerial, inFlight == 0 else { continue }
                apply(snapshot, to: studio)
                load = .loaded
                startNumbers()
                return true
            } catch {
                if error is CancellationError || Task.isCancelled {
                    if mine == readSerial, load == .loading { load = .idle }
                    return false
                }
                Connection.shared.note(error)
                guard stillLive(key), mine == readSerial else { return false }
                if load != .loaded {
                    load = .failed("Studio could not be read from your desktop. " + error.plainWords)
                } else {
                    problem = "Studio could not be refreshed. " + error.plainWords
                }
                return false
            }
        }
        guard stillLive(key), mine == readSerial else { return false }
        if load != .loaded { load = .failed("Your desktop kept changing while it was read. Try again.") }
        return false
    }

    private func fetch(_ client: APIClient) async throws -> MakeStudioSnapshot {
        var snapshot = MakeStudioSnapshot()
        var missing: [String] = []

        func attempt<T>(_ label: String, _ work: () async throws -> T) async throws -> T? {
            do {
                return try await work()
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if let api = error as? APIError, api == .unauthorized { throw error }
                missing.append(label)
                return nil
            }
        }

        // The parts Studio cannot draw without. A failure here is a failed read.
        let nicheAnswer = try await client.makeStudioNiches()
        let channelAnswer = try await client.makeStudioChannels()
        let postAnswer = try await client.makeStudioPosts()
        let publishAnswer = try await client.makeStudioPublishing()
        let approvalAnswer = try await client.makeStudioApprovals()
        let niches = MakeStudioWire.rows(MakeStudioRow(nicheAnswer)?.list("niches") ?? [], MakeStudioNicheDTO.init)
        let channels = MakeStudioWire.rows(MakeStudioRow(channelAnswer)?.list("channels") ?? [], MakeStudioChannelDTO.init)
        let posts = MakeStudioWire.rows(MakeStudioRow(postAnswer)?.list("posts") ?? [], MakeStudioPostDTO.init)
        let publishing = MakeStudioWire.rows(MakeStudioRow(publishAnswer)?.list("items") ?? [], MakeStudioPublishDTO.init)
        snapshot.niches = niches.rows
        snapshot.channels = channels.rows
        snapshot.posts = posts.rows
        snapshot.publishing = publishing.rows
        snapshot.approvals = MakeStudioApprovalsDTO(approvalAnswer)
        snapshot.skipped = niches.skipped + channels.skipped + posts.skipped + publishing.skipped + snapshot.approvals.skipped

        // The rest. A part that cannot be read this time keeps what was read before.
        if let answer = try await attempt("the pipeline", { try await client.makeStudioPipeline() }) {
            let rows = MakeStudioWire.rows(MakeStudioRow(answer)?.list("items") ?? [], MakeStudioPipelineDTO.init)
            snapshot.pipeline = rows.rows
            snapshot.skipped += rows.skipped
        }
        if let answer = try await attempt("the decisions", { try await client.makeStudioDecisions() }) {
            let rows = MakeStudioWire.rows(MakeStudioRow(answer)?.list("decisions") ?? [], MakeStudioDecisionDTO.init)
            snapshot.decisions = rows.rows
            snapshot.skipped += rows.skipped
        }
        if let answer = try await attempt("the scoreboard", { try await client.makeStudioScoreboard() }) {
            snapshot.scoreboard = MakeStudioScoreboardDTO(answer)
        }
        if let answer = try await attempt("the team settings", { try await client.makeStudioSettings() }) {
            snapshot.settings = MakeStudioSettingsDTO(answer)
        }
        if let answer = try await attempt("the hands-off state", { try await client.makeStudioHandsOff() }) {
            snapshot.handsOff = MakeStudioHandsOffDTO(answer)
        }
        if let answer = try await attempt("the team", { try await client.makeStudioSetup() }) {
            snapshot.setup = MakeStudioSetupDTO(answer)
        }
        if let answer = try await attempt("the report", { try await client.makeStudioReport() }) {
            snapshot.report = MakeStudioReportDTO(answer)
        }
        if let answer = try await attempt("the warnings", { try await client.makeStudioWatch() }) {
            snapshot.warnings = MakeStudioWire.rows(MakeStudioRow(answer)?.list("findings") ?? []) { row -> MakeStudioWarningDTO? in
                guard row.str("kind") == "platform_warning", let channel = row.int("channelId"), let message = row.str("message") else { return nil }
                return MakeStudioWarningDTO(channelID: channel, message: message)
            }.rows
        }
        snapshot.missing = missing
        return snapshot
    }

    // MARK: Turning answers into Studio's own rows

    private static let owners = ["producer": "Producer", "researcher": "Researcher", "evaluator": "Evaluator",
                                 "script_writer": "Script Writer", "editor": "Editor", "publisher": "Publisher",
                                 "executor": "Executor", "user": "You"]

    private static func publishState(_ wire: String) -> PublishState {
        switch wire {
        case "drafted": .drafted
        case "awaiting_approval": .awaiting
        case "approved": .approved
        case "prepared": .prepared
        case "waiting_for_you": .waitingForYou
        case "posted": .posted
        case "failed": .failed
        case "rejected": .rejected
        default: .drafted
        }
    }

    private static func stage(step: String?, state: String) -> PipelineStage {
        switch step {
        case "script": return .scripting
        case "render", "queue": return .rendering
        case "approval": return .awaiting
        case "publish": return .approved
        case "tracking": return .posted
        case "rejected": return .rejected
        default: break
        }
        switch state {
        case "awaiting_approval": return .awaiting
        case "approved": return .approved
        case "posted": return .posted
        case "rejected": return .rejected
        default: return .scripting
        }
    }

    private static func prettyPack(_ id: String) -> String {
        if id.isEmpty { return "Motion type (default)" }
        return id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private static func aspectText(_ wire: String) -> String {
        switch wire {
        case "9:16": "9:16 tall"
        case "16:9": "16:9 wide"
        case "1:1": "1:1 square"
        default: "Platform default (9:16)"
        }
    }

    private static func kidsText(_ wire: String) -> String {
        switch wire {
        case "yes": "Yes, made for kids"
        case "no": "No, not made for kids"
        default: "Not set"
        }
    }

    private static func rendererText(_ wire: String) -> String {
        switch wire {
        case "threejs": "three.js (built in)"
        case "blender": "Blender"
        default: "The style pack's choice"
        }
    }

    private func makeChannel(_ dto: MakeStudioChannelDTO, warning: String?) -> StudioChannel {
        let letters = String(dto.handle.drop(while: { $0 == "@" }).prefix(2)).uppercased()
        var channel = StudioChannel(id: String(dto.id), handle: dto.handle, platform: StudioPlatform(rawValue: dto.platform) ?? .youtube,
                                    nicheID: String(dto.nicheID), initials: letters.isEmpty ? "CH" : letters,
                                    hue: Double(dto.id % 12) / 12.0)
        channel.state = dto.archived ? .archived : (dto.paused ? .paused : .live)
        channel.warning = dto.paused ? warning : nil
        channel.pack = Self.prettyPack(dto.stylePack)
        channel.renderer = Self.rendererText(dto.renderer)
        channel.lookID = dto.look.isEmpty ? "default" : dto.look
        channel.aspect = Self.aspectText(dto.aspect)
        channel.frameRate = dto.fps == 60 ? "60" : "30"
        channel.voiceNotes = dto.notes
        channel.narrator = dto.voice.isEmpty ? "not set yet" : dto.voice
        channel.kids = Self.kidsText(dto.madeForKids)
        channel.longPerWeek = dto.longPerWeek ?? (dto.platform == "youtube" ? 1 : 0)
        channel.connection = ""
        return channel
    }

    private static func numbers(_ dto: MakeStudioNumbersDTO) -> PostNumbers {
        let sources = ["manual": "entered by hand", "youtube_api": "youtube", "tiktok_api": "tiktok", "instagram_api": "instagram", "page-read": "page read"]
        return PostNumbers(views: dto.views, averageView: dto.averageView, likes: dto.likes, comments: dto.comments, shares: dto.shares,
                           follows: dto.follows, source: sources[dto.source] ?? dto.source,
                           readAt: MakeStudioWire.time(dto.takenAt)?.studioDayTime ?? "")
    }

    private static let fieldWords = ["file": "Video", "title": "Title", "description": "Description", "tags": "Tags", "caption": "Caption",
                                     "thumbnail": "Thumbnail", "ai_label": "AI label", "made_for_kids": "Audience", "cover": "Cover"]

    private func word(_ key: String) -> String { Self.fieldWords[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized }

    private func posts(_ snapshot: MakeStudioSnapshot) -> [StudioPost] {
        let publishByPost = Dictionary(snapshot.publishing.map { ($0.postID, $0) }, uniquingKeysWith: { first, _ in first })
        var stepByPost: [Int: MakeStudioPipelineDTO] = [:]
        for item in snapshot.pipeline ?? [] where !item.isTopic { stepByPost[item.id] = item }
        let now = Date().timeIntervalSince1970
        var out: [StudioPost] = []
        for dto in snapshot.posts {
            let publishing = publishByPost[dto.id]
            let step = stepByPost[dto.id]
            let publish = Self.publishState(publishing?.state ?? dto.state)
            let stage = Self.stage(step: step?.step, state: dto.state)
            let inStep = step?.inStepH ?? max(0, (now - dto.stepSince) / 3600)
            var post = StudioPost(id: String(dto.id), title: dto.title, channelID: String(dto.channelID), stage: stage, publish: publish,
                                  owner: Self.owners[step?.owner ?? ""] ?? "Team", ageHours: Int(inStep))
            post.ageMinutes = Int(inStep * 60)
            post.desktopOverdue = step?.overdue
            if let window = step?.windowH { post.expectedHours = Int(window) }
            post.renderFailed = step?.status == "failed"
            post.rejectedTimes = dto.rejectionCount
            post.why = dto.pickReason
            var formatBits: [String] = []
            if !dto.formatName.isEmpty { formatBits.append("Format: \(dto.formatName).") }
            if !dto.stylePack.isEmpty { formatBits.append("Style pack: \(Self.prettyPack(dto.stylePack)).") }
            post.format = formatBits.joined(separator: " ")
            post.caption = dto.caption
            post.script = dto.script
            post.tags = dto.tags
            post.kids = dto.madeForKids == "yes" ? "Yes, made for kids" : (dto.madeForKids == "no" ? "No, not made for kids" : "The channel's answer")
            post.longVideo = dto.longForm
            let chapterText = snapshot.approvals.postChapters[dto.id] ?? details[post.id]?.chapters ?? ""
            post.chapters = chapterText.split(whereSeparator: \.isNewline).map { String($0) }
            post.scheduledAt = MakeStudioWire.time(publishing?.scheduledAt)
            post.postedAt = MakeStudioWire.time(publishing?.postedAt ?? dto.postedAt)
            post.posted = post.postedAt?.studioDayTime
            post.link = (publishing?.postedURL ?? dto.postedURL).flatMap { $0.isEmpty ? nil : $0 }
            post.videoID = dto.videoID
            post.rejectReason = dto.rejectReason.isEmpty ? nil : dto.rejectReason
            if publish != .posted, let next = publishing, !next.nextWhat.isEmpty {
                post.nextStep = (next.nextWho == "you" ? "You: " : "Team: ") + next.nextWhat
                post.plainNextWho = next.nextWho
            }
            if let publishing {
                post.problems = publishing.problems
                post.errorText = publishing.error
                post.checklist = publishing.checklist.map { line in
                    let who: ChecklistLine.Who
                    if publishing.missing.contains(line.key) { who = .missing }
                    else if line.by == "you" { who = .you }
                    else if publishing.filled.contains(line.key) { who = .filled }
                    else { who = .kairos }
                    return ChecklistLine(id: "\(dto.id)-\(line.key)", text: line.text, who: who)
                }
                switch publish {
                case .failed:
                    post.fillNote = publishing.error.isEmpty ? publishing.problems.first : publishing.error
                case .prepared, .waitingForYou:
                    var bits: [String] = []
                    if !publishing.filled.isEmpty { bits.append("Kairos filled: " + publishing.filled.map { word($0) }.joined(separator: ", ") + ".") }
                    if !publishing.missing.isEmpty { bits.append("Not found on the page, do these yourself: " + publishing.missing.map { word($0) }.joined(separator: ", ") + ".") }
                    if let first = publishing.problems.first { bits.append("Fix before posting: " + first) }
                    post.fillNote = bits.isEmpty ? nil : bits.joined(separator: " ")
                default:
                    break
                }
            }
            if let detail = details[post.id] {
                post.numberSets = detail.sets
                post.numbers = detail.latest.map(Self.numbers)
            }
            out.append(post)
        }
        out.reverse()
        for item in snapshot.pipeline ?? [] where item.isTopic {
            var topic = StudioPost(id: "t\(item.id)", title: item.title, channelID: "", stage: .topic, publish: .drafted, owner: "Researcher", ageHours: Int(item.ageH))
            topic.ageMinutes = Int(item.ageH * 60)
            topic.desktopOverdue = item.overdue
            if let window = item.windowH { topic.expectedHours = Int(window) }
            out.append(topic)
        }
        return out
    }

    private func decisionTitle(_ dto: MakeStudioDecisionDTO) -> String {
        let thing = dto.subjectType.isEmpty ? "" : dto.subjectType + " "
        switch (dto.kind, dto.subjectType) {
        case ("retire", _): return "Retire \(thing)\(dto.subjectName)"
        case ("add", _): return "Add niche \(dto.subjectName)"
        case ("promote", _): return "Promote \(thing)\(dto.subjectName)"
        case ("replace", "niche"): return "Find a replacement for \(dto.subjectName)"
        case ("replace", _): return "Replace \(thing)\(dto.subjectName)"
        default: return "\(dto.kind.capitalized) \(thing)\(dto.subjectName)"
        }
    }

    private func decisionNumbers(_ dto: MakeStudioDecisionDTO) -> String {
        guard let row = MakeStudioRow(.object(dto.numbers)) else { return "" }
        func one(_ value: Double?) -> String? { value.map { String(format: "%.1f", $0) } }
        var bits: [String] = []
        if let score = one(row.dbl("score")) { bits.append("score \(score)") }
        if let median = one(row.dbl("teamMedian")) { bits.append("team median \(median)") }
        if let posts = row.int("postsScored") { bits.append("\(posts) posts scored") }
        if let days = row.dbl("ageDays") { bits.append("\(Int(days)) days of data") }
        if let slots = row.int("freedSlots") { bits.append(slots == 1 ? "1 slot freed" : "\(slots) slots freed") }
        if let live = row.int("liveNiches"), let cap = row.int("cap") { bits.append("\(live) of \(cap) niches live") }
        return bits.joined(separator: " · ")
    }

    private func scores(_ rows: [MakeStudioScoreRowDTO]) -> [StudioScore] {
        rows.map { row in
            let detail = row.eligible || row.score != nil
                ? "\(row.postsScored) posts scored over \(row.ageDays) days"
                : (row.notYet.isEmpty ? "Needs more data" : row.notYet)
            let tag: String? = row.retired ? "Retired" : (row.available ? nil : "Not built yet")
            return StudioScore(name: row.name, score: row.score, detail: detail, tag: tag)
        }
    }

    private func apply(_ snapshot: MakeStudioSnapshot, to studio: StudioStore) {
        skipped = snapshot.skipped
        problem = snapshot.missing.isEmpty ? nil : "Some of Studio could not be read just now: " + snapshot.missing.joined(separator: ", ") + "."

        let warnings = Dictionary((snapshot.warnings ?? []).map { ($0.channelID, $0.message) }, uniquingKeysWith: { first, _ in first })
        let board = snapshot.scoreboard
        let nicheScores = Dictionary((board?.niches ?? []).map { ($0.name, $0.score) }, uniquingKeysWith: { first, _ in first })
        studio.niches = snapshot.niches.map { dto in
            StudioNiche(id: String(dto.id), name: dto.name, retired: dto.retired, slots: dto.slots, score: nicheScores[dto.name] ?? nil)
        }
        studio.channels = snapshot.channels.map { makeChannel($0, warning: warnings[$0.id]) }
        looks = Dictionary(snapshot.channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // A channel's form is made when it is first read and only refilled after that, so a read never moves
        // a field the person has edited.
        for (id, dto) in looks {
            if let form = forms[id] { form.refill(dto) } else { forms[id] = MakeStudioChannelForm(dto) }
        }
        studio.posts = posts(snapshot)

        // Plans, character sheets and style packs waiting for the person.
        let postChannel = Dictionary(snapshot.posts.map { ($0.id, String($0.channelID)) }, uniquingKeysWith: { first, _ in first })
        var versions: [String: Int] = [:]
        studio.plans = snapshot.approvals.plans.map { plan in
            if let version = plan.version { versions[plan.videoID] = version }
            let shots = plan.text.split(whereSeparator: \.isNewline).map { String($0) }
            return StudioPlan(id: plan.videoID, title: plan.title, channelID: plan.postID.flatMap { postChannel[$0] } ?? "",
                              chapters: plan.chapters, shots: shots)
        }
        planVersions = versions
        studio.liveSheets = snapshot.approvals.characters.map { dto in
            (StudioCharacter(id: dto.id, name: dto.name, family: dto.family, versions: []),
             CharacterVersion(number: dto.version, status: .waiting, note: dto.note, body: 0xCDBFD9, accent: 0x9C7430))
        }
        studio.livePacks = snapshot.approvals.packs.map { dto in
            (StudioPack(id: dto.id, name: dto.name, origin: "", summary: "", brief: "", versions: []),
             PackVersion(number: dto.version, status: .waiting, note: dto.note))
        }

        if let decisions = snapshot.decisions {
            studio.decisions = decisions.map { dto in
                let status: StudioDecision.Status
                switch dto.status {
                case "awaiting_user": status = .needsYou
                case "confirmed": status = .confirmed
                case "rejected": status = .rejected
                default: status = .producer
                }
                return StudioDecision(id: String(dto.id), title: decisionTitle(dto), numbers: decisionNumbers(dto),
                                      evidence: dto.reason.isEmpty ? nil : dto.reason, status: status)
            }
        }
        if let board {
            studio.liveScoreNiches = scores(board.niches)
            studio.liveScoreFormats = scores(board.formats)
            studio.liveScorePacks = scores(board.packs)
            studio.liveTopPosts = board.topPosts.map(String.init)
            studio.livePostsPosted = board.postsPosted
            studio.livePostsScored = board.postsScored
        }
        if let settings = snapshot.settings {
            studio.batchApproval = settings.batchApproval
            let sum = settings.weights.reduce(0, +)
            if sum > 0 { studio.weights = settings.weights.map { Int(($0 / sum * 100).rounded()) } }
            studio.handsOff = settings.handsOff
            studio.teamPaused = settings.teamPaused
        }
        if let hands = snapshot.handsOff {
            studio.handsOff = hands.on
            studio.teamPaused = hands.paused
            studio.liveTaps = hands.taps
        }
        if let setup = snapshot.setup {
            self.setup = setup
            studio.hasTeam = setup.imported
            studio.cycleRunning = setup.cycleRunning
            studio.spendCap = Int(setup.monthlyCap ?? 0)
        }
        if let report = snapshot.report {
            studio.liveReport = report.lines
            if let from = MakeStudioWire.time(report.from), let to = MakeStudioWire.time(report.to) {
                studio.liveReportRange = from.studioDay + " to " + to.studioDay
            }
        }
        // A scope that no longer exists (a channel the desktop dropped) falls back to All channels.
        if case .channel(let id) = studio.scope, studio.channel(id) == nil { studio.scope = .all; studio.tab = .dashboard }
    }

    // MARK: Numbers per post

    private func startNumbers() {
        numbersTask?.cancel()
        guard let studio else { return }
        let key = account
        let ids = studio.posts.filter { $0.publish == .posted && details[$0.id] == nil }
            .sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
            .prefix(8).map(\.id)
        guard !ids.isEmpty else { return }
        numbersTask = Task { [weak self] in
            for id in ids {
                guard let self, !Task.isCancelled, self.stillLive(key) else { return }
                await self.loadDetail(id)
            }
        }
    }

    /// One post's numbers, read when its details open and for the newest posted ones.
    func loadDetail(_ postID: String) async {
        guard isLive, let studio, let id = Int(postID) else { return }
        let key = account
        do {
            let answer = try await client().makeStudioPostDetail(id)
            guard stillLive(key) else { return }
            let detail = MakeStudioDetailDTO(answer)
            details[postID] = detail
            if let index = studio.posts.firstIndex(where: { $0.id == postID }) {
                studio.posts[index].numberSets = detail.sets
                studio.posts[index].numbers = detail.latest.map(Self.numbers)
                if !detail.chapters.isEmpty {
                    studio.posts[index].chapters = detail.chapters.split(whereSeparator: \.isNewline).map { String($0) }
                }
            }
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            Connection.shared.note(error)
        }
    }

    /// The style packs a channel may use, read when a channel's settings open.
    func loadPackChoices() async {
        guard isLive, packChoices.isEmpty else { return }
        let key = account
        do {
            let answer = try await client().makeStudioFormats()
            guard stillLive(key) else { return }
            packChoices = MakeStudioWire.rows(MakeStudioRow(answer)?.list("stylePacks") ?? [], MakeStudioPackChoiceDTO.init).rows
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            Connection.shared.note(error)
        }
    }

    func form(for channelID: String) -> MakeStudioChannelForm? {
        guard let id = Int(channelID) else { return nil }
        return forms[id]
    }

    // MARK: Changes

    /// The desktop refused the request, so it certainly did not do it.
    private static func wasRefused(_ error: Error) -> Bool {
        if error is MakeStudioChanged { return true }
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
    }

    private func perform(_ key: String, done: String, notApplied: String, lostLine: String,
                         verify: @escaping () -> MakeStudioVerdict,
                         send: (APIClient) async throws -> String?) async -> MakeStudioOutcome {
        guard isLive, studio != nil else { return .busy }
        let acct = account
        guard stillLive(acct), pending(key) == nil else { return .busy }
        let slot = Self.slot(acct, key)
        pendingMap[slot] = MakeStudioPending(key: key)
        verifiers[slot] = verify
        inFlight += 1
        writeSerial += 1
        var outcome: MakeStudioOutcome
        do {
            let message = try await send(try client())
            pendingMap[slot] = nil
            verifiers[slot] = nil
            outcome = .done(message ?? done)
        } catch {
            Connection.shared.note(error)
            if Self.wasRefused(error) {
                pendingMap[slot] = nil
                verifiers[slot] = nil
                outcome = .refused((error as? MakeStudioChanged)?.words ?? error.plainWords)
            } else {
                pendingMap[slot]?.lost = true
                pendingMap[slot]?.note = lostLine
                outcome = .unconfirmed(lostLine)
            }
        }
        inFlight -= 1
        writeSerial += 1
        guard stillLive(acct) else { return outcome }
        let read = await loadLive()
        if case .unconfirmed = outcome, read, let check = verifiers[slot] {
            switch check() {
            case .applied:
                pendingMap[slot] = nil
                verifiers[slot] = nil
                return .done(done)
            case .notApplied:
                pendingMap[slot] = nil
                verifiers[slot] = nil
                return .refused(notApplied)
            case .unknown:
                break
            }
        }
        return outcome
    }

    /// Read the desktop again for a change whose answer was lost, and say what it has. Never sends anything.
    func checkAgain(_ key: String) async -> String {
        guard isLive else { return "" }
        let acct = account
        let slot = Self.slot(acct, key)
        guard pendingMap[slot]?.lost == true else { return "" }
        let read = await loadLive()
        guard stillLive(acct), pendingMap[slot]?.lost == true else { return "" }
        guard read else { return "Your desktop did not answer. It is still not confirmed." }
        switch verifiers[slot]?() ?? .unknown {
        case .applied:
            pendingMap[slot] = nil
            verifiers[slot] = nil
            return "Your desktop has it."
        case .notApplied:
            pendingMap[slot] = nil
            verifiers[slot] = nil
            return "Your desktop does not have it, so nothing was changed."
        case .unknown:
            return "Your desktop shows nothing new yet. This stays off so it is not sent twice."
        }
    }

    private func verdict(post id: String, _ decide: (PublishState) -> MakeStudioVerdict) -> MakeStudioVerdict {
        guard let post = studio?.post(id) else { return .unknown }
        return decide(post.publish)
    }

    /// Another change to this post is on its way or unconfirmed (approve, reject, redraft, prepare, or approve all).
    private func postLocked(_ postID: String) -> Bool {
        isBusy("approveAll") || ["approve:", "reject:", "redraft:", "prepare:"].contains { isBusy($0 + postID) }
    }

    private func lostWords(_ what: String) -> String {
        "Your desktop did not confirm \(what). It may already have it. Check again reads your desktop; nothing is sent twice."
    }

    func approve(_ postID: String) async -> MakeStudioOutcome {
        guard !postLocked(postID) else { return .busy }
        guard let id = Int(postID) else { return .refused("That post is not on your desktop.") }
        return await perform("approve:" + postID, done: "Approved. It is in Publishing, ready to prepare.",
                             notApplied: "Your desktop still has this post waiting. It was not approved.",
                             lostLine: lostWords("the approval"),
                             verify: { [weak self] in self?.verdict(post: postID) { $0 == .awaiting ? .notApplied : .applied } ?? .unknown },
                             send: { client in
                                 try await client.makeStudioApprove(id)
                                 return nil
                             })
    }

    func approveAll() async -> MakeStudioOutcome {
        guard let studio else { return .busy }
        let ids = studio.scoped(studio.posts).filter { $0.publish == .awaiting }.map(\.id)
        let numbers = ids.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == ids.count else { return .refused("There are no posts waiting to approve.") }
        guard !ids.contains(where: { postLocked($0) }) else { return .busy }
        return await perform("approveAll", done: "Approved.", notApplied: "Your desktop still has those posts waiting. None was approved.",
                             lostLine: lostWords("the approvals"),
                             verify: { [weak self] in
                                 guard let self, let studio = self.studio else { return .unknown }
                                 let waiting = ids.filter { studio.post($0)?.publish == .awaiting }
                                 return waiting.count == ids.count ? .notApplied : .applied
                             },
                             send: { client in
                                 let answer = try await client.makeStudioApproveBatch(numbers)
                                 let row = MakeStudioRow(answer)
                                 let approved = row?.list("approved").count ?? 0
                                 let skipped = row?.list("skipped").count ?? 0
                                 var line = approved == 1 ? "Approved 1 post." : "Approved \(approved) posts."
                                 if skipped > 0 { line += " \(skipped) could not be approved, usually because the channel is paused or archived." }
                                 return line
                             })
    }

    func reject(_ postID: String, reason: String) async -> MakeStudioOutcome {
        guard !postLocked(postID) else { return .busy }
        guard let id = Int(postID) else { return .refused("That post is not on your desktop.") }
        return await perform("reject:" + postID, done: "Rejected.", notApplied: "Your desktop still has this post as it was. It was not rejected.",
                             lostLine: lostWords("the rejection"),
                             verify: { [weak self] in
                                 self?.verdict(post: postID) { state in
                                     switch state {
                                     case .rejected: .applied
                                     case .awaiting, .approved: .notApplied
                                     default: .unknown
                                     }
                                 } ?? .unknown
                             },
                             send: { client in
                                 try await client.makeStudioReject(id, reason: reason.isEmpty ? "No reason given" : reason)
                                 return nil
                             })
    }

    func redraft(_ postID: String) async -> MakeStudioOutcome {
        guard !postLocked(postID) else { return .busy }
        guard let id = Int(postID) else { return .refused("That post is not on your desktop.") }
        return await perform("redraft:" + postID, done: "Sent back for a new draft.", notApplied: "Your desktop still has this post as rejected.",
                             lostLine: lostWords("the redraft"),
                             verify: { [weak self] in self?.verdict(post: postID) { $0 == .rejected ? .notApplied : .applied } ?? .unknown },
                             send: { client in
                                 try await client.makeStudioRedraft(id)
                                 return nil
                             })
    }

    func prepare(_ postID: String) async -> MakeStudioOutcome {
        guard !postLocked(postID) else { return .busy }
        guard let id = Int(postID) else { return .refused("That post is not on your desktop.") }
        return await perform("prepare:" + postID, done: "Prepared. Open its checklist to see what is ready.",
                             notApplied: "Your desktop did not prepare this post.",
                             lostLine: lostWords("the preparation"),
                             verify: { [weak self] in
                                 self?.verdict(post: postID) { state in
                                     switch state {
                                     case .prepared, .waitingForYou, .posted: .applied
                                     case .approved, .failed: .notApplied
                                     default: .unknown
                                     }
                                 } ?? .unknown
                             },
                             send: { client in
                                 try await client.makeStudioPrepare(id)
                                 return nil
                             })
    }

    /// A long video's plan. The desktop approves "the plan as it is now", so the phone first checks that the plan
    /// is still the one the person read.
    func decidePlan(_ videoID: String, approve: Bool, reason: String = "") async -> MakeStudioOutcome {
        let shown = planVersions[videoID]
        return await perform("plan:" + videoID, done: approve ? "Plan approved. The team can render it now." : "Plan rejected. The Producer plans again.",
                             notApplied: "Your desktop still has this plan waiting.",
                             lostLine: lostWords(approve ? "the approval" : "the rejection"),
                             verify: { [weak self] in
                                 guard let self, let studio = self.studio else { return .unknown }
                                 return studio.plans.contains { $0.id == videoID } ? .notApplied : .applied
                             },
                             send: { client in
                                 let state = MakeStudioRow(try await client.makeStudioPlanState(videoID))
                                 guard state?.str("status") == "awaiting_approval", state?.int("version") == shown else {
                                     throw MakeStudioChanged(words: "This plan changed on your desktop since you read it. It is shown again now. Read it, then decide.")
                                 }
                                 try await client.makeStudioPlanDecide(videoID, approve: approve, reason: reason.isEmpty ? "No reason given" : reason)
                                 return nil
                             })
    }

    func decideSheet(_ key: String, approve: Bool, reason: String = "") async -> MakeStudioOutcome {
        let parts = key.split(separator: "#").map(String.init)
        guard parts.count == 2, let version = Int(parts[1]) else { return .refused("That sheet is not on your desktop.") }
        let id = parts[0]
        return await perform("sheet:" + key, done: approve ? "Character sheet approved." : "Character sheet rejected.",
                             notApplied: "Your desktop still has this sheet waiting.", lostLine: lostWords("the decision"),
                             verify: { [weak self] in
                                 guard let studio = self?.studio else { return .unknown }
                                 return studio.liveSheets.contains { $0.0.id == id && $0.1.number == version } ? .notApplied : .applied
                             },
                             send: { client in
                                 try await client.makeStudioSheetDecide(id, version: version, approve: approve, reason: reason.isEmpty ? "No reason given" : reason)
                                 return nil
                             })
    }

    func decidePack(_ key: String, approve: Bool, reason: String = "") async -> MakeStudioOutcome {
        let parts = key.split(separator: "#").map(String.init)
        guard parts.count == 2, let version = Int(parts[1]) else { return .refused("That style pack is not on your desktop.") }
        let id = parts[0]
        return await perform("pack:" + key, done: approve ? "Style pack approved." : "Style pack rejected.",
                             notApplied: "Your desktop still has this style pack waiting.", lostLine: lostWords("the decision"),
                             verify: { [weak self] in
                                 guard let studio = self?.studio else { return .unknown }
                                 return studio.livePacks.contains { $0.0.id == id && $0.1.number == version } ? .notApplied : .applied
                             },
                             send: { client in
                                 try await client.makeStudioPackDecide(id, version: version, approve: approve, reason: reason.isEmpty ? "No reason given" : reason)
                                 return nil
                             })
    }

    func turnHandsOffOff() async -> MakeStudioOutcome {
        await perform("handsoff", done: "Hands-off posting is off. Every post waits for your OK.",
                      notApplied: "Your desktop still has hands-off posting on.", lostLine: lostWords("the switch"),
                      verify: { [weak self] in self?.studio.map { $0.handsOff ? .notApplied : .applied } ?? .unknown },
                      send: { client in
                          try await client.makeStudioHandsOffTurnOff()
                          return nil
                      })
    }

    func setTeamPause(_ on: Bool) async -> MakeStudioOutcome {
        await perform("pause", done: on ? "Team paused." : "Team resumed.",
                      notApplied: on ? "Your desktop did not pause the team." : "Your desktop did not resume the team.",
                      lostLine: lostWords(on ? "the pause" : "the resume"),
                      verify: { [weak self] in self?.studio.map { $0.teamPaused == on ? .applied : .notApplied } ?? .unknown },
                      send: { client in
                          try await client.makeStudioTeamPause(on)
                          return nil
                      })
    }

    func resumeChannel(_ channelID: String) async -> MakeStudioOutcome {
        guard let id = Int(channelID) else { return .refused("That channel is not on your desktop.") }
        return await perform("resume:" + channelID, done: "Channel resumed.", notApplied: "Your desktop still has this channel paused.",
                             lostLine: lostWords("the resume"),
                             verify: { [weak self] in self?.studio?.channel(channelID).map { $0.state == .paused ? .notApplied : .applied } ?? .unknown },
                             send: { client in
                                 try await client.makeStudioResume(id)
                                 return nil
                             })
    }

    func archiveChannel(_ channelID: String) async -> MakeStudioOutcome {
        guard let id = Int(channelID) else { return .refused("That channel is not on your desktop.") }
        return await perform("archive:" + channelID, done: "Channel archived.", notApplied: "Your desktop did not archive this channel.",
                             lostLine: lostWords("the archive"),
                             verify: { [weak self] in self?.studio?.channel(channelID).map { $0.state == .archived ? .applied : .notApplied } ?? .unknown },
                             send: { client in
                                 try await client.makeStudioArchive(id)
                                 return nil
                             })
    }

    func decide(_ decisionID: String, confirm: Bool) async -> MakeStudioOutcome {
        guard let id = Int(decisionID) else { return .refused("That decision is not on your desktop.") }
        return await perform("decision:" + decisionID, done: confirm ? "Confirmed." : "Rejected. Nothing changed.",
                             notApplied: "Your desktop still has this decision waiting.", lostLine: lostWords("the decision"),
                             verify: { [weak self] in
                                 guard let studio = self?.studio else { return .unknown }
                                 guard let found = studio.decisions.first(where: { $0.id == decisionID }) else { return .unknown }
                                 return found.status == .needsYou ? .notApplied : .applied
                             },
                             send: { client in
                                 if confirm { try await client.makeStudioDecisionConfirm(id) } else { try await client.makeStudioDecisionReject(id) }
                                 return nil
                             })
    }

    // MARK: Channel look

    private static let voicePattern = try? NSRegularExpression(pattern: "^[a-z]{2}_[a-z0-9]{1,30}$")

    /// Why the form cannot be saved as it is, or nil.
    func formProblem(_ changes: [MakeStudioField: String], platform: StudioPlatform) -> String? {
        if let voice = changes[.voice], !voice.isEmpty {
            let range = NSRange(voice.startIndex..., in: voice)
            if Self.voicePattern?.firstMatch(in: voice, range: range) == nil { return "The narrator voice is a voice id like af_heart." }
        }
        if let look = changes[.look], !look.isEmpty {
            if look.count > 80 || !look.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                return "A look id uses letters, digits, - and _."
            }
        }
        if let notes = changes[.notes], notes.count > MakeStudioWire.notesLimit { return "Voice notes can be up to 1000 characters." }
        if let long = changes[.long] {
            guard let value = Int(long), (0...7).contains(value) else { return "Long videos a week is a whole number from 0 to 7." }
            if value > 0, platform != .youtube { return "Long videos are for YouTube channels." }
        }
        return nil
    }

    /// Save the channel's look: only the fields the person changed, with the desktop's own values.
    func saveChannel(_ channelID: String) async -> MakeStudioOutcome {
        guard let id = Int(channelID), let form = forms[id] else { return .refused("That channel is not on your desktop.") }
        let sent = form.changes
        guard !sent.isEmpty else { return .refused("Nothing changed.") }
        var body: [String: Any] = [:]
        for (field, value) in sent {
            switch field {
            case .pack: body["style_pack"] = value
            case .renderer: body["renderer"] = value
            case .look: body["look"] = value
            case .aspect: body["aspect"] = value
            case .fps: body["fps"] = Int(value) ?? 30
            case .voice: body["voice"] = value
            case .kids: body["made_for_kids"] = value
            case .long: body["long_per_week"] = Int(value) ?? 0
            case .notes: body["notes"] = value
            }
        }
        let outcome = await perform("edit:" + channelID, done: "Settings saved.",
                             notApplied: "Your desktop did not save these changes. What you typed is still here.",
                             lostLine: lostWords("the settings"),
                             verify: { [weak self] in
                                 guard let self, let dto = self.looks[id] else { return .unknown }
                                 let now = MakeStudioChannelForm.values(dto)
                                 let same = sent.allSatisfy { now[$0.key] == $0.value }
                                 if same { form.settle(sent) }
                                 return same ? .applied : .notApplied
                             },
                             send: { client in
                                 try await client.makeStudioEditChannel(id, fields: body)
                                 return nil
                             })
        // The desktop has the edits now: the form stops calling them edits.
        if case .done = outcome { form.settle(sent) }
        return outcome
    }

    // MARK: Spending and sending

    /// Run one cycle for one channel. It spends bot money against the monthly cap, and takes no request id, so a lost
    /// answer keeps this off until the desktop shows a run that started after it was sent.
    func runCycle(channelID: String) async -> MakeStudioOutcome {
        guard let id = Int(channelID) else { return .refused("That channel is not on your desktop.") }
        let acct = account
        guard setup?.cycleRunning != true else { return .refused("A cycle is already running on your desktop.") }
        let sentAt = Date()
        cycleSince[acct] = sentAt
        return await perform("cycle", done: "The Producer started a cycle. It takes a few minutes. Its post waits in Approvals.",
                             notApplied: "Your desktop did not start a cycle.",
                             lostLine: "Your desktop did not confirm the cycle. It may be running and spending. Check again reads your desktop; this stays off until it shows a run.",
                             verify: { [weak self] in
                                 guard let self, let setup = self.setup else { return .unknown }
                                 let since = (self.cycleSince[acct] ?? sentAt).timeIntervalSince1970 - 5
                                 return setup.cycleRunning || (setup.lastRunStarted ?? 0) >= since ? .applied : .unknown
                             },
                             send: { client in
                                 let answer = try await client.makeStudioRunCycle(id)
                                 guard MakeStudioRow(answer)?.flag("started") == true else {
                                     throw MakeStudioChanged(words: "Your desktop did not start a new run.")
                                 }
                                 return nil
                             })
    }

    /// Put the weekly report in the Inbox. A message goes out, and the desktop takes no request id, so a lost answer
    /// keeps this off for the rest of this run of the app.
    func sendReport() async -> MakeStudioOutcome {
        let acct = account
        guard !reportSent.contains(acct) else { return .refused("The report was already sent.") }
        let outcome = await perform("report", done: "Report sent to your Inbox.",
                                    notApplied: "Your desktop did not send the report.",
                                    lostLine: "Your desktop did not confirm the report. It may be in your Inbox. This stays off so it is not sent twice. Look in your Inbox on your desktop.",
                                    verify: { .unknown },
                                    send: { client in
                                        let answer = try await client.makeStudioReportSend()
                                        guard MakeStudioRow(answer)?.flag("delivered") == true else {
                                            throw MakeStudioChanged(words: "Your desktop could not send it: the Producer bot that sends it is missing. Nothing was sent.")
                                        }
                                        return nil
                                    })
        if case .done = outcome { reportSent.insert(acct) }
        return outcome
    }
}

// MARK: - Views

/// What is kept on the desktop, said once in plain words.
nonisolated enum MakeStudioWords {
    static let posting = "Posting to YouTube, TikTok or Instagram, scheduling and marking a post as posted are done in Kairos on your desktop."
    static let handsOffOn = "Turn hands-off posting on in Kairos on your desktop."
    static let accounts = "Connecting accounts and setting up social apps is done in Kairos on your desktop."
    static let importNumbers = "Importing numbers is done in Kairos on your desktop."
    static let setup = "Content setup, accounts, connections and daily routines are done in Kairos on your desktop."
    static let addChannel = "Add a channel in Kairos on your desktop."
    static let editPost = "Edit a post's text in Kairos on your desktop."
    static let teamReport = "The team report is in Kairos on your desktop."
    static let restore = "Restore an archived channel in Kairos on your desktop."
}

/// Studio while the desktop is being read, or could not be.
struct MakeStudioStatus: View {
    let state: MakeStudioLoad
    let retry: () -> Void

    var body: some View {
        switch state {
        case .failed(let why): MakeHomeLine(text: why, action: "Try again", perform: retry)
        default: MakeHomeLine(text: "Reading Studio from your desktop.")
        }
    }
}

/// A change on its way to the desktop, or one whose answer was lost, with Check again.
struct MakeStudioPendingLine: View {
    let key: String
    @Environment(MakeToast.self) private var toast
    private let live = MakeStudioLive.shared

    var body: some View {
        if let pending = live.pending(key) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !pending.lost { PulsingDot(color: Palette.working, size: 7) }
                    Text(pending.lost ? pending.note : "Sending to your desktop.")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if pending.lost {
                    MakePillButton(title: "Check again") {
                        Task {
                            let line = await live.checkAgain(key)
                            if !line.isEmpty { toast.say(line) }
                        }
                    }
                }
            }
        }
    }
}

/// A sheet that says where a held thing is done.
struct MakeStudioHeldSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 260) {
            VStack(spacing: 14) {
                MakeSheetTitle(title: "On your desktop")
                Text(text)
                    .font(KFont.ui(15.5))
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                QuietButton(title: "Close") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

/// The team's posting strip while paired: hands-off posting can be turned off here, never on.
struct MakeStudioHandsOffStrip: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    private let live = MakeStudioLive.shared

    var body: some View {
        let studio = make.studio
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: studio.teamPaused ? "pause.circle.fill" : (studio.handsOff ? "bolt.circle.fill" : "hand.raised.circle.fill"))
                    .font(.system(size: 18))
                    .foregroundStyle(studio.teamPaused ? Palette.danger : Palette.goldText)
                    .contentTransition(.symbolEffect(.replace))
                Text(studio.handsOffLine)
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if studio.handsOff {
                    MakePillButton(title: "Turn hands-off posting off", expand: true) {
                        Task { toast.say(await live.turnHandsOffOff().line) }
                    }
                    .disabled(live.isBusy("handsoff"))
                    .opacity(live.isBusy("handsoff") ? 0.5 : 1)
                }
                MakePillButton(title: studio.teamPaused ? "Resume team" : "Pause team", symbol: studio.teamPaused ? "play.fill" : "pause.fill", expand: studio.handsOff == false) {
                    let on = !studio.teamPaused
                    Task { toast.say(await live.setTeamPause(on).line) }
                }
                .disabled(live.isBusy("pause"))
                .opacity(live.isBusy("pause") ? 0.5 : 1)
            }
            if !studio.handsOff { HintLine(text: MakeStudioWords.handsOffOn) }
            MakeStudioPendingLine(key: "handsoff")
            MakeStudioPendingLine(key: "pause")
        }
        .padding(14)
        .background(studio.teamPaused ? Palette.danger.opacity(0.08) : Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(studio.teamPaused ? Palette.danger.opacity(0.4) : Palette.line, lineWidth: 1))
    }
}

/// Run one cycle, and the one line about what stays on the desktop. Shown on the All channels dashboard.
struct MakeStudioCycleTile: View {
    @Environment(MakeStore.self) private var make
    private let live = MakeStudioLive.shared

    var body: some View {
        let studio = make.studio
        VStack(spacing: 12) {
            if let setup = live.setup, setup.imported {
                let running = setup.cycleRunning || studio.cycleRunning
                let busy = live.isBusy("cycle")
                MakeTile(title: "Run one cycle", symbol: "play.circle") {
                    Text("The Producer researches, writes and renders one post for a channel you choose. It spends from your monthly cap, and the post still waits for your OK.")
                        .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                    if running { HintLine(text: "A cycle is running on your desktop now.", symbol: "clock") }
                    MakeStudioPendingLine(key: "cycle")
                    MakePillButton(title: running ? "Cycle running" : "Run one cycle", symbol: "play.fill", filled: !running && !busy) {
                        studio.sheet = .runCycle
                    }
                    .disabled(running || busy || studio.channels.filter { $0.state == .live }.isEmpty)
                    .opacity(running || busy ? 0.5 : 1)
                }
            }
            HintLine(text: MakeStudioWords.setup)
        }
    }
}

/// The channel chooser and the confirm for one cycle. It names the channel and the monthly cap.
struct MakeStudioCycleSheet: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?
    @State private var working = false
    @State private var note: String?
    private let live = MakeStudioLive.shared

    private var capLine: String {
        guard let cap = live.setup?.monthlyCap, cap > 0 else { return "No monthly spend cap is set on your desktop." }
        let spent = live.setup?.spent.map { " $\(String(format: "%.2f", $0)) is spent this month." } ?? ""
        return "Monthly spend cap: $\(String(format: "%.0f", cap)).\(spent)"
    }

    var body: some View {
        let studio = make.studio
        let channels = studio.channels.filter { $0.state == .live }
        FittedSheet(estimate: 520) {
            VStack(alignment: .leading, spacing: 14) {
                if let id = chosen, let channel = studio.channel(id) {
                    MakeSheetTitle(title: "Run one cycle for \(channel.handle)?", detail: capLine)
                    Text("The Producer researches, writes and renders one post. It spends bot money against your monthly cap, and it cannot be taken back once it starts. The post still waits for your OK.")
                        .font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note { Text(note).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
                    GoldButton(title: working ? "Sending" : "Run one cycle now") { start(id) }
                        .disabled(working || live.setup?.cycleRunning == true || live.isBusy("cycle"))
                        .opacity(working ? 0.6 : 1)
                    QuietButton(title: "Back") { chosen = nil }.disabled(working)
                } else {
                    MakeSheetTitle(title: "Run one cycle", detail: "Choose the channel. " + capLine)
                    VStack(spacing: 0) {
                        if channels.isEmpty { EmptyLine(text: "No live channel to run.").padding(16) }
                        ForEach(channels) { channel in
                            Button {
                                Haptics.select()
                                chosen = channel.id
                            } label: {
                                HStack(spacing: 12) {
                                    ChannelAvatar(channel: channel, size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(channel.handle).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                                        Text(channel.platform.name).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 58)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle(scale: 0.99))
                        }
                    }
                    .kCard(radius: 20)
                    QuietButton(title: "Cancel") { dismiss() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled(working)
    }

    private func start(_ id: String) {
        guard !working else { return }
        working = true
        note = nil
        Task {
            let outcome = await live.runCycle(channelID: id)
            working = false
            toast.say(outcome.line)
            switch outcome {
            case .refused, .busy: note = outcome.line
            case .done, .unconfirmed: dismiss()
            }
        }
    }
}

// MARK: Approvals

struct MakeStudioSheetRow: Identifiable {
    let id: String
    let character: StudioCharacter
    let version: CharacterVersion
}

struct MakeStudioPackRow: Identifiable {
    let id: String
    let pack: StudioPack
    let version: PackVersion
}

extension StudioStore {
    var liveSheetRows: [MakeStudioSheetRow] {
        liveSheets.map { MakeStudioSheetRow(id: "\($0.0.id)#\($0.1.number)", character: $0.0, version: $0.1) }
    }

    var livePackRows: [MakeStudioPackRow] {
        livePacks.map { MakeStudioPackRow(id: "\($0.0.id)#\($0.1.number)", pack: $0.0, version: $0.1) }
    }
}

/// Approve, Reject and Details on a post that waits for the person.
struct MakeStudioApprovalButtons: View {
    let post: StudioPost
    @Environment(MakeStore.self) private var make
    private let live = MakeStudioLive.shared

    var body: some View {
        let studio = make.studio
        let busy = live.isBusy("approve:\(post.id)") || live.isBusy("reject:\(post.id)") || live.isBusy("approveAll")
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MakePillButton(title: "Approve", filled: !busy, expand: true) { studio.sheet = .approvePost(post.id) }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                Menu {
                    Button("Reject", systemImage: "xmark") { studio.sheet = .rejectPost(post.id) }
                    Button("Details", systemImage: "info.circle") { studio.sheet = .post(post.id) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44).background(Palette.ink.opacity(0.1), in: Circle())
                }
                .disabled(busy)
                .accessibilityLabel("More actions")
            }
            MakeStudioPendingLine(key: "approve:\(post.id)")
            MakeStudioPendingLine(key: "reject:\(post.id)")
        }
    }
}

struct MakeStudioPlanButtons: View {
    let plan: StudioPlan
    @Environment(MakeStore.self) private var make
    private let live = MakeStudioLive.shared

    var body: some View {
        let studio = make.studio
        let busy = live.isBusy("plan:\(plan.id)")
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MakePillButton(title: "Approve plan", filled: !busy, expand: true) { studio.sheet = .planApprove(plan.id) }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                MakePillButton(title: "Reject") { studio.sheet = .planReject(plan.id) }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
            }
            MakePillButton(title: "Open video", symbol: "film") {
                studio.editorVideoID = plan.id
                studio.pushEditor = true
            }
            MakeStudioPendingLine(key: "plan:\(plan.id)")
        }
    }
}

struct MakeStudioSheetButtons: View {
    let rowID: String
    @Environment(MakeStore.self) private var make
    private let live = MakeStudioLive.shared

    var body: some View {
        let studio = make.studio
        let busy = live.isBusy("sheet:\(rowID)")
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MakePillButton(title: "Approve", filled: !busy, expand: true) { studio.sheet = .sheetApprove(rowID) }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                MakePillButton(title: "Reject") { studio.sheet = .sheetReject(rowID) }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
            }
            MakeStudioPendingLine(key: "sheet:\(rowID)")
        }
    }
}

struct MakeStudioPackButtons: View {
    let rowID: String
    @Environment(MakeStore.self) private var make
    private let live = MakeStudioLive.shared

    var body: some View {
        let studio = make.studio
        let busy = live.isBusy("pack:\(rowID)")
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MakePillButton(title: "Approve", filled: !busy, expand: true) { studio.sheet = .packApprove(rowID) }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                MakePillButton(title: "Reject") { studio.sheet = .packReject(rowID) }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
            }
            MakeStudioPendingLine(key: "pack:\(rowID)")
        }
    }
}

// MARK: Publishing

/// The buttons a post offers in its state while paired. Posting, scheduling and marking posted are not here.
struct MakeStudioPostActions: View {
    let post: StudioPost
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    private let live = MakeStudioLive.shared

    var body: some View {
        let studio = make.studio
        let preparing = live.isBusy("prepare:\(post.id)")
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                switch post.publish {
                case .awaiting:
                    MakePillButton(title: "Go to Approvals", filled: true) { studio.open(.approvals) }
                case .approved, .failed:
                    MakePillButton(title: post.publish == .failed ? "Prepare again" : "Prepare post", filled: !preparing) {
                        Task { toast.say(await live.prepare(post.id).line) }
                    }
                    .disabled(preparing)
                    .opacity(preparing ? 0.5 : 1)
                case .prepared, .waitingForYou:
                    MakePillButton(title: "Checklist", filled: true) { studio.sheet = .checklist(post.id) }
                case .posted:
                    if let link = post.link, let url = URL(string: link), url.scheme == "https" {
                        Link(destination: url) {
                            Text("Open post").font(KFont.ui(14.5, .semibold)).foregroundStyle(Palette.ink)
                                .padding(.horizontal, 14).frame(minHeight: 44).background(Palette.ink.opacity(0.1), in: Capsule())
                        }
                    }
                case .rejected:
                    MakePillButton(title: "Redraft", filled: !live.isBusy("redraft:\(post.id)")) { studio.sheet = .redraftPost(post.id) }
                        .disabled(live.isBusy("redraft:\(post.id)"))
                case .drafted:
                    MakePillButton(title: "Details") { studio.sheet = .post(post.id) }
                }
            }
            .scrollableRow()
            MakeStudioPendingLine(key: "prepare:\(post.id)")
            MakeStudioPendingLine(key: "redraft:\(post.id)")
        }
    }
}

// MARK: Calendar

/// The week calendar with the desktop's real dates.
struct MakeStudioCalendar: View {
    @Environment(MakeStore.self) private var make

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    private static func monday(offset: Int) -> Date {
        let calendar = Self.calendar
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset * 7, to: start) ?? start
    }

    var body: some View {
        let studio = make.studio
        let calendar = Self.calendar
        let first = Self.monday(offset: studio.weekOffset)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        let list = studio.scoped(studio.posts)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                GlassIconButton(symbol: "chevron.left", label: "Previous week", size: 40) { withAnimation(Motion.snappy) { studio.weekOffset -= 1 } }
                Text(weekLabel(first, offset: studio.weekOffset)).font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                GlassIconButton(symbol: "chevron.right", label: "Next week", size: 40) { withAnimation(Motion.snappy) { studio.weekOffset += 1 } }
            }
            if studio.weekOffset != 0 {
                MakePillButton(title: "This week") { withAnimation(Motion.snappy) { studio.weekOffset = 0 } }
            }
            ForEach(days, id: \.self) { day in
                let items = list.filter { post in post.calendarDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
                VStack(alignment: .leading, spacing: 8) {
                    Text(day.studioDay).font(KFont.ui(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(calendar.isDateInToday(day) ? Palette.goldText : Palette.inkDim)
                    if items.isEmpty { Text("Nothing.").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint) }
                    ForEach(items) { post in chip(post) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .kCard(radius: 18)
            }
        }
    }

    private func weekLabel(_ first: Date, offset: Int) -> String {
        let last = Calendar(identifier: .iso8601).date(byAdding: .day, value: 6, to: first) ?? first
        let range = first.studioDay + " to " + last.studioDay
        return offset == 0 ? "This week, " + range : range
    }

    private func chip(_ post: StudioPost) -> some View {
        let studio = make.studio
        let channel = studio.channel(post.channelID)
        return Button {
            studio.sheet = post.publish == .prepared || post.publish == .waitingForYou ? .checklist(post.id) : .post(post.id)
        } label: {
            HStack(spacing: 8) {
                Text(post.calendarDate?.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.goldText)
                Text(channel?.platform.short ?? "").font(.system(size: 10, weight: .heavy)).foregroundStyle(Palette.inkDim)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.title).font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(channel?.handle ?? "").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 0)
                StatePill(text: post.publish.rawValue, tone: post.publish.tone)
            }
            .padding(10)
            .frame(minHeight: 44)
            .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }
}

// MARK: Analytics

/// The team scoreboard while paired: the desktop's decisions and scores. The team settings are read only here.
struct MakeStudioScoreboard: View {
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        let weights = studio.weights.count == 3 ? studio.weights : [40, 40, 20]
        VStack(alignment: .leading, spacing: 12) {
            Text("Score out of 100: views \(weights[0]), watch time \(weights[1]), follows and engagement \(weights[2]). Each part is ranked within its platform.")
                .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            let needs = studio.decisions.filter { $0.status == .needsYou }
            MakeTile(title: "Needs your OK", symbol: "hand.raised") {
                if needs.isEmpty { EmptyLine(text: "No decisions wait for you.") }
                ForEach(needs) { decision in row(decision, actions: true) }
            }
            let withProducer = studio.decisions.filter { $0.status == .producer }
            if !withProducer.isEmpty {
                MakeTile(title: "With the Producer", symbol: "person.crop.circle") {
                    ForEach(withProducer) { decision in row(decision, actions: false) }
                }
            }
            scoreTile("Niches", studio.liveScoreNiches)
            scoreTile("Formats", studio.liveScoreFormats)
            scoreTile("Style packs", studio.liveScorePacks)
            let top = studio.liveTopPosts.compactMap { studio.post($0) }
            MakeTile(title: "Top posts", symbol: "star") {
                if top.isEmpty { EmptyLine(text: "No post has a score yet.") }
                ForEach(top) { post in
                    HStack {
                        Text(post.title).font(KFont.ui(15)).foregroundStyle(Palette.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        MakePillButton(title: "Open post") { studio.sheet = .post(post.id) }
                    }
                }
            }
            let recent = studio.decisions.filter { $0.status == .confirmed || $0.status == .rejected }.prefix(12)
            MakeTile(title: "Recent decisions", symbol: "clock.arrow.circlepath") {
                if recent.isEmpty { EmptyLine(text: "No decision has been settled yet.") }
                ForEach(Array(recent)) { decision in row(decision, actions: false) }
            }
            MakeTile(title: "Team settings", symbol: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(["Views at 7 days", "Watch time", "Follows and engagement"].enumerated()), id: \.offset) { index, name in
                        HStack {
                            Text(name).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(weights[index])%").font(KFont.ui(15, .medium)).foregroundStyle(Palette.inkDim)
                        }
                        .frame(minHeight: 36)
                    }
                    HStack {
                        Text("One-tap batch approval").font(KFont.ui(15)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(studio.batchApproval ? "On" : "Off").font(KFont.ui(15, .medium)).foregroundStyle(Palette.inkDim)
                    }
                    .frame(minHeight: 36)
                    HintLine(text: "Change the weights and batch approval in Kairos on your desktop.")
                }
            }
        }
    }

    private func row(_ decision: StudioDecision, actions: Bool) -> some View {
        let studio = make.studio
        let busy = MakeStudioLive.shared.isBusy("decision:\(decision.id)")
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(decision.title).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink)
                Spacer(minLength: 6)
                StatePill(text: decision.status.rawValue, tone: decision.status == .needsYou ? .gold : (decision.status == .rejected ? .error : (decision.status == .confirmed ? .ok : .working)))
            }
            if !decision.numbers.isEmpty { Text(decision.numbers).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint) }
            if let evidence = decision.evidence { Text(evidence).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim) }
            if actions {
                HStack(spacing: 8) {
                    MakePillButton(title: "Confirm", filled: !busy) { studio.sheet = .decision(decision.id) }
                        .disabled(busy)
                    MakePillButton(title: "Reject") { studio.sheet = .decisionReject(decision.id) }
                        .disabled(busy)
                }
            }
            MakeStudioPendingLine(key: "decision:\(decision.id)")
        }
        .padding(.vertical, 4)
    }

    private func scoreTile(_ title: String, _ rows: [StudioScore]) -> some View {
        MakeTile(title: title, symbol: "list.number") {
            if rows.isEmpty { EmptyLine(text: "Nothing is scored yet.") }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    Text(row.score.map { String(format: "%.1f", $0) } ?? "–")
                        .font(KFont.ui(16, .semibold)).foregroundStyle(row.score == nil ? Palette.inkFaint : Palette.goldText).frame(width: 46, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                        Text(row.detail).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer(minLength: 0)
                    if let tag = row.tag { StatePill(text: tag, tone: .muted) }
                }
                .frame(minHeight: 40)
            }
        }
    }
}

/// One channel's analytics while paired.
struct MakeStudioChannelAnalytics: View {
    let channelID: String
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        let posted = studio.posts.filter { $0.channelID == channelID && $0.publish == .posted }
            .sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
        let channel = studio.channel(channelID)
        VStack(alignment: .leading, spacing: 12) {
            let numbers = posted.compactMap(\.numbers)
            MakeTile(title: "Newest posts with numbers", symbol: "chart.bar") {
                if numbers.isEmpty {
                    EmptyLine(text: "No numbers read yet.")
                } else {
                    numbersGrid(PostNumbers(views: numbers.map(\.views).reduce(0, +), averageView: numbers.map(\.averageView).reduce(0, +) / numbers.count,
                                            likes: numbers.map(\.likes).reduce(0, +), comments: numbers.map(\.comments).reduce(0, +),
                                            shares: numbers.map(\.shares).reduce(0, +), follows: numbers.map(\.follows).reduce(0, +)))
                    Text("From \(numbers.count) of the newest posted posts.").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                }
            }
            MakeTile(title: "Posts", symbol: "list.bullet") {
                if posted.isEmpty { EmptyLine(text: "Nothing posted on this channel yet.") }
                ForEach(posted) { post in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(post.title).font(KFont.ui(15)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(post.numbers.map { "\(compactNumber($0.views)) views, \(durationText($0.averageView)) average" } ?? "Open it to read its numbers.")
                                .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: 6)
                        MakePillButton(title: "Open post") { studio.sheet = .post(post.id) }
                    }
                }
            }
            if let channel {
                let week = Date().addingTimeInterval(-7 * 86400)
                let lastWeek = posted.filter { ($0.postedAt ?? .distantPast) >= week }.count
                let scheduled = studio.posts.filter { $0.channelID == channelID && $0.scheduledAt != nil && $0.publish != .posted }.count
                MakeTile(title: "This week", symbol: "calendar") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Posted in the last 7 days: \(lastWeek) posts.")
                        Text("Scheduled from now on: \(scheduled) posts.")
                        Text("Waiting for your approval: \(studio.waiting(for: channelID)) items.")
                        if let niche = studio.niche(channel.nicheID) {
                            Text(niche.score.map { "Its niche, \(niche.name), scores \(String(format: "%.1f", $0)) on the scoreboard." } ?? "Its niche, \(niche.name), is not scored yet.")
                        }
                    }
                    .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                }
                HintLine(text: "Numbers are read from the platform on your desktop. Syncing them, connecting accounts and importing numbers are done there.")
            }
        }
    }
}

// MARK: Report

struct MakeStudioReport: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    private let live = MakeStudioLive.shared

    var body: some View {
        let studio = make.studio
        let sent = live.reportSent.contains(MakeStudioLive.accountKey)
        let busy = live.isBusy("report")
        VStack(alignment: .leading, spacing: 12) {
            MakeTile(title: "Latest report", symbol: "doc.plaintext") {
                if !studio.liveReportRange.isEmpty {
                    Text(studio.liveReportRange).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                if studio.liveReport.isEmpty { EmptyLine(text: "The report could not be read just now.") }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(studio.liveReport.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Palette.gold).frame(width: 5, height: 5)
                            Text(line).font(KFont.ui(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                MakeStudioPendingLine(key: "report")
                MakePillButton(title: sent ? "Sent to your Inbox" : (busy ? "Not confirmed" : "Send to my Inbox"),
                               symbol: sent ? "checkmark" : "tray.and.arrow.down", filled: !sent && !busy) {
                    studio.sheet = .reportSend
                }
                .disabled(sent || busy || studio.liveReport.isEmpty)
                .opacity(sent || busy ? 0.6 : 1)
            }
            HintLine(text: MakeStudioWords.importNumbers)
        }
    }
}

// MARK: Channel settings

struct MakeStudioChannelSettings: View {
    let channelID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    private let live = MakeStudioLive.shared

    var body: some View {
        let studio = make.studio
        if let channel = studio.channel(channelID) {
            VStack(alignment: .leading, spacing: 12) {
                MakeTile(title: "Channel status", symbol: "dot.radiowaves.left.and.right") {
                    StatePill(text: channel.state.label, tone: channel.state.tone)
                    switch channel.state {
                    case .archived:
                        HintLine(text: MakeStudioWords.restore)
                    case .paused:
                        HStack(spacing: 8) {
                            MakePillButton(title: "Resume channel", filled: true) { studio.sheet = .resolve(channel.id) }
                                .disabled(live.isBusy("resume:\(channel.id)"))
                            MakePillButton(title: "Archive", danger: true) { studio.sheet = .archive(channel.id) }
                                .disabled(live.isBusy("archive:\(channel.id)"))
                        }
                    case .live:
                        MakePillButton(title: "Archive", danger: true) { studio.sheet = .archive(channel.id) }
                            .disabled(live.isBusy("archive:\(channel.id)"))
                    }
                    MakeStudioPendingLine(key: "resume:\(channel.id)")
                    MakeStudioPendingLine(key: "archive:\(channel.id)")
                }
                if channel.state == .archived {
                    EmptyLine(text: "An archived channel keeps its history. Restore it on your desktop to change its settings.")
                } else if let form = live.form(for: channelID) {
                    HintLine(text: MakeStudioWords.accounts)
                    MakeStudioLookForm(channel: channel, form: form)
                }
            }
            .task { await live.loadPackChoices() }
        }
    }
}

/// The channel's look and voice. It sends only what the person changed, with the desktop's own values.
struct MakeStudioLookForm: View {
    let channel: StudioChannel
    let form: MakeStudioChannelForm
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @State private var message: String?
    private let live = MakeStudioLive.shared

    private var packOptions: [(wire: String, label: String)] {
        var out: [(wire: String, label: String)] = [("", "Motion type (default)")]
        for choice in live.packChoices where choice.id != "motion-type" { out.append((choice.id, choice.name)) }
        let current = form.shown[.pack] ?? ""
        if !current.isEmpty, !out.contains(where: { $0.wire == current }) { out.append((current, current)) }
        return out
    }

    private var rendererOptions: [(wire: String, label: String)] {
        var out: [(wire: String, label: String)] = [("", "The style pack's choice"), ("threejs", "three.js (built in)")]
        if form.shown[.renderer] == "blender" { out.append(("blender", "Blender")) }
        return out
    }

    private static let aspects: [(wire: String, label: String)] = [("", "Platform default (9:16)"), ("9:16", "9:16 tall"), ("16:9", "16:9 wide"), ("1:1", "1:1 square")]
    private static let rates: [(wire: String, label: String)] = [("30", "30"), ("60", "60")]
    private static let kids: [(wire: String, label: String)] = [("", "Not set"), ("no", "No, not made for kids"), ("yes", "Yes, made for kids")]
    private static let longs: [(wire: String, label: String)] = (0...7).map { (String($0), String($0)) }

    var body: some View {
        let busy = live.isBusy("edit:\(channel.id)")
        let edited = !form.changes.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Look and voice")
            VStack(spacing: 0) {
                MakeChoiceRow(title: "Style pack", options: packOptions.map(\.label), selection: choice(.pack, packOptions))
                MakeChoiceRow(title: "3D renderer", options: rendererOptions.map(\.label), selection: choice(.renderer, rendererOptions))
                MakeChoiceRow(title: "Aspect", options: Self.aspects.map(\.label), selection: choice(.aspect, Self.aspects))
                MakeChoiceRow(title: "Frame rate", options: Self.rates.map(\.label), selection: choice(.fps, Self.rates))
                MakeChoiceRow(title: "Made for kids", options: Self.kids.map(\.label), selection: choice(.kids, Self.kids), last: channel.platform != .youtube)
                if channel.platform == .youtube {
                    MakeChoiceRow(title: "Long videos a week", options: Self.longs.map(\.label), selection: choice(.long, Self.longs), last: true)
                }
            }
            .kCard(radius: 20)
            MakeField(label: "Look", text: text(.look), prompt: "A look id, like warm", limit: 80)
            MakeField(label: "Narrator voice", text: text(.voice), prompt: "A voice id, like af_heart", limit: 40)
            MakeField(label: "Voice notes", text: text(.notes), prompt: "How the narrator should sound", limit: 1000, lines: 2...5)
            Text("\(make.studio.niche(channel.nicheID)?.slots ?? 1) posting slots a day in this niche")
                .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            if let message { Text(message).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
            MakeStudioPendingLine(key: "edit:\(channel.id)")
            GoldButton(title: busy ? "Saving" : "Save settings") { save() }
                .disabled(busy || !edited)
                .opacity(busy || !edited ? 0.5 : 1)
                .padding(.top, 4)
        }
    }

    private func choice(_ field: MakeStudioField, _ options: [(wire: String, label: String)]) -> Binding<String> {
        Binding(
            get: {
                let wire = form.shown[field] ?? ""
                return options.first { $0.wire == wire }?.label ?? wire
            },
            set: { label in
                if let match = options.first(where: { $0.label == label }) { form.set(field, match.wire) }
            }
        )
    }

    private func text(_ field: MakeStudioField) -> Binding<String> {
        Binding(get: { form.shown[field] ?? "" }, set: { form.set(field, $0) })
    }

    private func save() {
        message = nil
        if let problem = live.formProblem(form.changes, platform: channel.platform) {
            message = problem
            return
        }
        Task {
            let outcome = await live.saveChannel(channel.id)
            Haptics.success()
            toast.say(outcome.line)
            if case .refused(let line) = outcome { message = line }
        }
    }
}

// MARK: Post details and checklist

/// One post's details while paired. Its numbers are read when it opens.
struct MakeStudioPostDetails: View {
    let postID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    private let live = MakeStudioLive.shared

    var body: some View {
        let studio = make.studio
        ScrollView {
            if let post = studio.post(postID) {
                let channel = studio.channel(post.channelID)
                VStack(alignment: .leading, spacing: 14) {
                    MakeSheetTitle(title: post.title)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        StatBox(value: post.stage.rawValue, label: "Step")
                        StatBox(value: post.ageText, label: "Age")
                        if let channel {
                            StatBox(value: studio.niche(channel.nicheID)?.name ?? "", label: "Niche")
                            StatBox(value: channel.handle, label: "Channel")
                        }
                    }
                    if post.overdue { StatePill(text: "Overdue", tone: .error) }
                    if post.stage == .topic {
                        Text("A topic the Researcher found. The Evaluator picks which ones get made.")
                            .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    }
                    if post.publish == .rejected {
                        Text("Rejected: \(post.rejectReason ?? "no reason given")").font(KFont.ui(14.5)).foregroundStyle(Palette.danger)
                    }
                    actions(post)
                    if let id = post.videoID {
                        MakePillButton(title: "Open video", symbol: "film") {
                            studio.editorVideoID = id
                            dismiss()
                            studio.pushEditor = true
                        }
                    }
                    preview(post)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .task { await live.loadDetail(postID) }
    }

    @ViewBuilder
    private func actions(_ post: StudioPost) -> some View {
        let studio = make.studio
        switch post.publish {
        case .awaiting:
            MakePillButton(title: "Go to Approvals", filled: true, expand: true) { studio.open(.approvals); dismiss() }
        case .approved, .failed:
            VStack(alignment: .leading, spacing: 8) {
                if post.publish == .failed, !post.errorText.isEmpty {
                    Text(post.errorText).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.danger)
                }
                MakePillButton(title: post.publish == .failed ? "Prepare again" : "Prepare post", filled: true, expand: true) {
                    Task { toast.say(await live.prepare(post.id).line) }
                }
                .disabled(live.isBusy("prepare:\(post.id)"))
                MakeStudioPendingLine(key: "prepare:\(post.id)")
                HintLine(text: MakeStudioWords.posting)
            }
        case .prepared, .waitingForYou:
            VStack(alignment: .leading, spacing: 8) {
                MakePillButton(title: "Open checklist", filled: true, expand: true) { studio.sheet = .checklist(post.id) }
                HintLine(text: MakeStudioWords.posting)
            }
        case .posted:
            VStack(alignment: .leading, spacing: 6) {
                StatePill(text: "Posted", tone: .ok)
                if let link = post.link { Text(link).font(KFont.ui(14)).foregroundStyle(Palette.goldText).lineLimit(2) }
                Text("\(post.numberSets) number sets read.").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                if let numbers = post.numbers { numbersGrid(numbers) }
            }
        case .rejected:
            VStack(alignment: .leading, spacing: 8) {
                MakePillButton(title: "Redraft", filled: true) { studio.sheet = .redraftPost(post.id) }
                    .disabled(live.isBusy("redraft:\(post.id)"))
                MakeStudioPendingLine(key: "redraft:\(post.id)")
            }
        case .drafted:
            EmptyView()
        }
    }

    private func preview(_ post: StudioPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Post preview")
            field("Why this topic", post.why.isEmpty ? "Not given." : post.why)
            if !post.format.isEmpty { field("Format", post.format) }
            field("Caption", post.caption.isEmpty ? "No caption yet." : post.caption)
            field("Tags", post.tags.isEmpty ? "None" : post.tags)
            field("Made for kids", post.kids)
            if !post.chapters.isEmpty { field("Chapters (added to the YouTube description)", post.chapters.joined(separator: "\n")) }
            field("Script", post.script.isEmpty ? "No script yet." : post.script)
            field("AI label", "Every post carries it. Prepare post turns it on.")
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            Text(value).font(KFont.ui(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .kCard(radius: 14)
    }
}

/// A prepared post's checklist while paired. Posting itself is done on the desktop.
struct MakeStudioChecklist: View {
    let postID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        ScrollView {
            if let post = studio.post(postID), let channel = studio.channel(post.channelID) {
                VStack(alignment: .leading, spacing: 14) {
                    MakeSheetTitle(title: post.title)
                    HStack(spacing: 6) {
                        StatePill(text: channel.platform.name, tone: .muted)
                        StatePill(text: post.publish.rawValue, tone: post.publish.tone)
                        StatePill(text: "AI label on", tone: .ok)
                    }
                    .scrollableRow()
                    copyRow(channel.platform == .youtube ? "Title" : "Caption", channel.platform == .youtube ? post.title : post.caption)
                    if channel.platform == .youtube { copyRow("Description", post.caption) }
                    copyRow("Tags", post.tags)
                    copyRow("Schedule", post.scheduleText ?? "Not scheduled", copyable: false)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Checklist")
                        if post.checklist.isEmpty { EmptyLine(text: "The desktop has no checklist for this post yet.") }
                        ForEach(post.checklist) { line in
                            HStack {
                                Image(systemName: line.who == .missing ? "exclamationmark.circle" : (line.who == .you ? "hand.point.up.left" : "checkmark.circle.fill"))
                                    .foregroundStyle(line.who == .missing ? Palette.danger : (line.who == .you ? Palette.goldText : Palette.success))
                                Text(line.text).font(KFont.ui(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Text(line.who.rawValue).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                            }
                            .frame(minHeight: 36)
                        }
                    }
                    .padding(14)
                    .kCard(radius: 18)
                    ForEach(post.problems, id: \.self) { problem in
                        Text(problem).font(KFont.ui(14, .medium)).foregroundStyle(Palette.danger).fixedSize(horizontal: false, vertical: true)
                    }
                    if let note = post.fillNote, post.problems.isEmpty {
                        Text(note).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                    HintLine(text: MakeStudioWords.posting)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }

    private func copyRow(_ label: String, _ value: String, copyable: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                Text(value.isEmpty ? "None" : value).font(KFont.ui(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                    Haptics.success()
                    toast.say("\(label) copied.")
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Copy \(label)")
            }
        }
        .padding(12)
        .kCard(radius: 14)
    }
}
