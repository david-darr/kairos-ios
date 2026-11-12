import SwiftUI

// Studio's Content data: niches, channels, posts, approvals, libraries and the team switches.
// Everything here is made up. The desktop connection replaces SampleStudio later.

nonisolated enum StudioPlatform: String, CaseIterable, Hashable, Sendable {
    case youtube, tiktok, instagram

    var name: String {
        switch self {
        case .youtube: "YouTube"
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        }
    }

    var short: String {
        switch self {
        case .youtube: "YT"
        case .tiktok: "TT"
        case .instagram: "IG"
        }
    }

    /// The word on the platform's own post button.
    var postButton: String {
        switch self {
        case .youtube: "Publish"
        case .tiktok: "Post"
        case .instagram: "Share"
        }
    }
}

nonisolated enum ChannelState: Hashable, Sendable {
    case live, paused, archived

    var label: String {
        switch self {
        case .live: "Live"
        case .paused: "Paused"
        case .archived: "Archived"
        }
    }

    var tone: PillTone {
        switch self {
        case .live: .ok
        case .paused: .error
        case .archived: .muted
        }
    }
}

nonisolated struct StudioNiche: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var retired = false
    var slots = 1
    var score: Double?
}

nonisolated struct StudioChannel: Identifiable, Hashable, Sendable {
    let id: String
    var handle: String
    var platform: StudioPlatform
    var nicheID: String
    var state: ChannelState = .live
    var initials: String
    var hue: Double
    var warning: String?
    var pack = "Motion type (default)"
    var renderer = "The style pack's choice"
    var lookID = "warm"
    var aspect = "Platform default (9:16)"
    var frameRate = "30"
    var voiceNotes = ""
    var narrator = "Iris"
    var kids = "No, not made for kids"
    var longPerWeek = 0
    var connection = "Not connected"
    var connectedAs: String?
    var posts = 0
    var views = 0
    var follows = 0
    var averageView = 0

    var color: Color { Color(hue: hue, saturation: 0.32, brightness: 0.86) }
}

nonisolated enum PipelineStage: String, CaseIterable, Hashable, Sendable {
    case topic = "Topic", scripting = "Scripting", rendering = "Rendering", awaiting = "Awaiting approval", approved = "Approved", posted = "Posted", rejected = "Rejected"
}

nonisolated enum PublishState: String, CaseIterable, Hashable, Sendable {
    case drafted = "Drafted"
    case awaiting = "Waiting for your approval"
    case approved = "Approved"
    case prepared = "Prepared"
    case waitingForYou = "Waiting for you to press Post"
    case posted = "Posted"
    case failed = "Failed"
    case rejected = "Rejected"

    var tone: PillTone {
        switch self {
        case .drafted: .muted
        case .awaiting, .waitingForYou: .gold
        case .approved, .prepared: .working
        case .posted: .ok
        case .failed, .rejected: .error
        }
    }
}

nonisolated struct PostNumbers: Hashable, Sendable {
    var views: Int
    var averageView: Int
    var likes: Int
    var comments: Int
    var shares: Int
    var follows: Int
    var source = "youtube"
    var readAt = "today 08:00"
}

nonisolated struct ChecklistLine: Identifiable, Hashable, Sendable {
    enum Who: String, Hashable, Sendable { case you = "You", filled = "Filled", missing = "Not found, do it yourself", kairos = "Kairos" }
    let id = UUID()
    var text: String
    var who: Who
}

nonisolated struct StudioPost: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var channelID: String
    var stage: PipelineStage
    var publish: PublishState
    var owner: String
    var ageHours: Int
    var expectedHours = 24
    var renderFailed = false
    var rejectedTimes = 0
    var why = ""
    var format = ""
    var caption = ""
    var script = ""
    var tags = ""
    var kids = "The channel's answer"
    var longVideo = false
    var chapters: [String] = []
    var scheduledDay: Int?
    var scheduledTime = ""
    var posted: String?
    var link: String?
    var numbers: PostNumbers?
    var numberSets = 0
    var nextStep = ""
    var fillNote: String?
    var rejectReason: String?
    var checklist: [ChecklistLine] = []

    var overdue: Bool { ageHours > expectedHours && stage != .posted && stage != .rejected }

    var flags: [String] {
        var out: [String] = []
        if renderFailed { out.append("Render failed") }
        if overdue { out.append("Overdue") }
        if rejectedTimes >= 2 && stage != .posted { out.append("Rejected \(rejectedTimes) times") }
        return out
    }

    var ageText: String {
        if ageHours < 1 { return "40m" }
        if ageHours < 48 { return "\(ageHours)h" }
        return "\(ageHours / 24)d"
    }
}

nonisolated enum PackStatus: String, Hashable, Sendable {
    case draft = "Draft, no sample yet"
    case rendering = "Rendering its sample"
    case waiting = "Waiting for your OK"
    case approved = "Approved"
    case rejected = "Rejected"
    case failed = "Sample failed"

    var tone: PillTone {
        switch self {
        case .draft: .muted
        case .rendering: .working
        case .waiting: .gold
        case .approved: .ok
        case .rejected, .failed: .error
        }
    }
}

nonisolated struct PackVersion: Identifiable, Hashable, Sendable {
    var id: Int { number }
    var number: Int
    var status: PackStatus
    var note: String
    var sampleNotes: [String] = []
    var rejection: String?
}

nonisolated struct StudioPack: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var origin: String
    var summary: String
    var brief: String
    var music = "Warm"
    var captions = true
    var captionCase = "Sentence"
    var narrator = "Iris"
    var facts: [String: String] = [:]
    var versions: [PackVersion]

    var useText: String {
        if let approved = versions.last(where: { $0.status == .approved }) { return "Channels and videos use version \(approved.number)." }
        return "Not approved yet, so no channel can use it."
    }
}

nonisolated enum CharacterStatus: String, Hashable, Sendable {
    case draft = "Draft, no sheet yet", waiting = "Waiting for your OK", approved = "Approved", rejected = "Rejected"

    var tone: PillTone {
        switch self {
        case .draft: .muted
        case .waiting: .gold
        case .approved: .ok
        case .rejected: .error
        }
    }
}

nonisolated struct CharacterVersion: Identifiable, Hashable, Sendable {
    var id: Int { number }
    var number: Int
    var status: CharacterStatus
    var note: String
    var body: UInt32
    var accent: UInt32
    var accessory = "None"
    var rejection: String?
}

nonisolated struct StudioCharacter: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var family: String
    var versions: [CharacterVersion]

    var castable: String {
        if let approved = versions.last(where: { $0.status == .approved }) { return "Videos can cast version \(approved.number)." }
        return "No approved version yet, so no video can use it."
    }
}

nonisolated struct StudioPlan: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var channelID: String
    var chapters: [String]
    var shots: [String]
    var approved = false
}

nonisolated struct StudioCheck: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var result: String
}

nonisolated struct StudioPort: Identifiable, Hashable, Sendable {
    let id: String
    var from: String
    var to: String
    var status: String
    var reason: String
    var changes: [String]
    var checks: [StudioCheck]
    var cost: String
    var verdict: String
}

nonisolated struct StudioFormat: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var beats: [String]
    var length: String
    var audience: String
    var seenIn: String
    var evidence: [String]
    var ports: [StudioPort]
}

nonisolated struct StudioDecision: Identifiable, Hashable, Sendable {
    enum Status: String, Hashable, Sendable { case needsYou = "Needs you", producer = "With the Producer", confirmed = "Confirmed", rejected = "Rejected" }
    let id: String
    var title: String
    var numbers: String
    var evidence: String?
    var status: Status
}

nonisolated struct StudioScore: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var score: Double?
    var detail: String
    var tag: String?
}

nonisolated struct StudioTemplate: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var detail: String
    var bots: [String]
    var added = false
}

nonisolated enum StepState: String, Hashable, Sendable {
    case done = "Done", todo = "To do", waiting = "Waiting", fix = "Needs a fix", optional = "Optional"

    var tone: PillTone {
        switch self {
        case .done: .ok
        case .todo: .gold
        case .waiting: .working
        case .fix: .error
        case .optional: .muted
        }
    }
}

nonisolated struct SetupStep: Identifiable, Hashable, Sendable {
    var id: Int { number }
    var number: Int
    var title: String
    var status: String
    var why: String
    var state: StepState
    var required = true
}

nonisolated struct NeedsRow: Identifiable, Hashable, Sendable {
    var id: String { text }
    var count: Int
    var text: String
    var tab: StudioTab
    var filter: String?
}

nonisolated enum StudioLibrary: String, CaseIterable, Hashable, Sendable {
    case formats = "Formats", styles = "Styles", characters = "Characters", connections = "Connections", templates = "Templates"

    var about: String {
        switch self {
        case .formats: "Formats that work, with their sources, and where the team ports them."
        case .styles: "Style packs: how your videos look and sound. You approve each from its sample."
        case .characters: "Characters for the Flat 2D pack. You approve each from its sheet."
        case .connections: "How Kairos reads your numbers and posts for you."
        case .templates: "Ready-made teams for Content Studio."
        }
    }

    var symbol: String {
        switch self {
        case .formats: "square.grid.3x2"
        case .styles: "paintbrush"
        case .characters: "person.2"
        case .connections: "link"
        case .templates: "square.on.square"
        }
    }
}

nonisolated enum StudioScope: Hashable, Sendable {
    case all
    case channel(String)
    case library(StudioLibrary)
}

nonisolated enum StudioTab: String, Hashable, Sendable {
    case dashboard = "Dashboard", approvals = "Approvals", pipeline = "Pipeline", calendar = "Calendar"
    case publishing = "Publishing", analytics = "Analytics", report = "Report", settings = "Settings"

    static let overview: [StudioTab] = [.dashboard, .approvals, .pipeline, .calendar, .publishing, .analytics, .report]
    static let channel: [StudioTab] = [.dashboard, .pipeline, .calendar, .approvals, .publishing, .analytics, .settings]
}

/// Every sheet Studio can open. One at a time, opened from anywhere through the store.
nonisolated enum StudioSheet: Identifiable, Hashable, Sendable {
    case picker
    case setup
    case addChannel
    case post(String)
    case checklist(String)
    case editPost(String)
    case rejectPost(String)
    case redraftPost(String)
    case approvePost(String)
    case approveAll
    case schedule(String)
    case markPosted(String)
    case youtube(String)
    case tiktok(String)
    case instagram(String)
    case handsOff
    case runCycle
    case resolve(String)
    case archive(String)
    case decision(String)
    case importNumbers
    case newBrief
    case editPack(String)
    case duplicatePack(String)
    case importPack
    case packReject(String)
    case newCharacter
    case characterVersion(String)
    case sheetReject(String)
    case planReject(String)
    case accountChooser(String)
    case socialApp(StudioPlatform)
    case teamReport

    var id: String { String(describing: self) }
}

/// Where Studio's data comes from.
protocol StudioProviding {
    func niches() -> [StudioNiche]
    func channels() -> [StudioChannel]
    func posts() -> [StudioPost]
}

/// The Content dashboard's state and every action on it.
@Observable
final class StudioStore {
    var niches: [StudioNiche]
    var channels: [StudioChannel]
    var posts: [StudioPost]
    var packs: [StudioPack] = SampleStudio.packs
    var characters: [StudioCharacter] = SampleStudio.characters
    var plans: [StudioPlan] = SampleStudio.plans
    var formats: [StudioFormat] = SampleStudio.formats
    var decisions: [StudioDecision] = SampleStudio.decisions
    var templates: [StudioTemplate] = SampleStudio.templates

    var scope: StudioScope = .all
    var tab: StudioTab = .dashboard
    var publishFilter = "All"
    var weekOffset = 0
    var sheet: StudioSheet?
    var pushEditor = false

    var hasTeam = true
    var handsOff = false
    var teamPaused = false
    var batchApproval = true
    var routinesOn = 3
    let routinesTotal = 3
    var cycleRunning = false
    var lastCycle = "finished at 06:10"
    var setupHidden = false
    var spendCap = 40
    var weights = [50, 30, 20]
    var youtubeConfigured = true
    var analyticsConnected = true
    var postingConnected = true
    var uploadPrivacy = "Private"
    var tiktokAppSaved = false
    var tiktokAudited = false
    var instagramAppSaved = true
    var pageReads: [StudioPlatform: Bool] = [.tiktok: true, .instagram: false]
    var reportSent = false

    init(provider: StudioProviding = SampleStudio()) {
        niches = provider.niches()
        channels = provider.channels()
        posts = provider.posts()
    }

    // MARK: Lookups

    func channel(_ id: String) -> StudioChannel? { channels.first { $0.id == id } }
    func post(_ id: String) -> StudioPost? { posts.first { $0.id == id } }
    func niche(_ id: String) -> StudioNiche? { niches.first { $0.id == id } }
    func pack(_ id: String) -> StudioPack? { packs.first { $0.id == id } }
    func character(_ id: String) -> StudioCharacter? { characters.first { $0.id == id } }

    var currentChannelID: String? {
        if case .channel(let id) = scope { return id }
        return nil
    }

    var tabs: [StudioTab] {
        switch scope {
        case .all: StudioTab.overview
        case .channel: StudioTab.channel
        case .library: []
        }
    }

    func scoped(_ list: [StudioPost]) -> [StudioPost] {
        guard let id = currentChannelID else { return list }
        return list.filter { $0.channelID == id }
    }

    var liveChannels: [StudioChannel] { channels.filter { $0.state != .archived } }

    func waiting(for channelID: String?) -> Int {
        let list = channelID == nil ? posts : posts.filter { $0.channelID == channelID }
        let postCount = list.filter { $0.publish == .awaiting }.count
        let planCount = plans.filter { !$0.approved && (channelID == nil || $0.channelID == channelID) }.count
        if channelID != nil { return postCount + planCount }
        return postCount + planCount + sheetsWaiting.count + packsWaiting.count
    }

    var sheetsWaiting: [(StudioCharacter, CharacterVersion)] {
        characters.flatMap { character in character.versions.filter { $0.status == .waiting }.map { (character, $0) } }
    }

    var packsWaiting: [(StudioPack, PackVersion)] {
        packs.flatMap { pack in pack.versions.filter { $0.status == .waiting }.map { (pack, $0) } }
    }

    func needsYou(for channelID: String?) -> [NeedsRow] {
        let list = channelID == nil ? posts : posts.filter { $0.channelID == channelID }
        var rows: [NeedsRow] = []
        let approve = list.filter { $0.publish == .awaiting }.count
        if approve > 0 { rows.append(NeedsRow(count: approve, text: approve == 1 ? "1 post to approve" : "\(approve) posts to approve", tab: .approvals)) }
        let planCount = plans.filter { !$0.approved && (channelID == nil || $0.channelID == channelID) }.count
        if planCount > 0 { rows.append(NeedsRow(count: planCount, text: planCount == 1 ? "1 long video plan to approve" : "\(planCount) long video plans to approve", tab: .approvals)) }
        let toPost = list.filter { $0.publish == .prepared || $0.publish == .waitingForYou }.count
        if toPost > 0 { rows.append(NeedsRow(count: toPost, text: toPost == 1 ? "1 prepared post waiting for you to post it" : "\(toPost) prepared posts waiting for you to post them", tab: .publishing, filter: "To post")) }
        let failed = list.filter { $0.publish == .failed }.count
        if failed > 0 { rows.append(NeedsRow(count: failed, text: failed == 1 ? "1 preparation that failed" : "\(failed) preparations that failed", tab: .publishing, filter: PublishState.failed.rawValue)) }
        if channelID == nil {
            let sheets = sheetsWaiting.count
            if sheets > 0 { rows.append(NeedsRow(count: sheets, text: sheets == 1 ? "1 character sheet to approve" : "\(sheets) character sheets to approve", tab: .approvals)) }
            let packCount = packsWaiting.count
            if packCount > 0 { rows.append(NeedsRow(count: packCount, text: packCount == 1 ? "1 style pack to approve" : "\(packCount) style packs to approve", tab: .approvals)) }
            let decisionCount = decisions.filter { $0.status == .needsYou }.count
            if decisionCount > 0 { rows.append(NeedsRow(count: decisionCount, text: decisionCount == 1 ? "1 team decision to confirm" : "\(decisionCount) team decisions to confirm", tab: .analytics)) }
        }
        return rows
    }

    var latestPosted: [StudioPost] { Array(scoped(posts).filter { $0.publish == .posted }.prefix(4)) }

    var upcoming: [StudioPost] {
        Array(scoped(posts).filter { $0.scheduledDay != nil && $0.publish != .posted }.sorted { ($0.scheduledDay ?? 0) < ($1.scheduledDay ?? 0) }.prefix(5))
    }

    var approvalLine: String {
        handsOff ? "Hands-off posting is on: the Producer approves posts and Kairos posts them." : "Nothing is posted without your OK."
    }

    var handsOffLine: String {
        if teamPaused { return "The team is paused. Nothing is posted and its bots only read until you resume it." }
        if handsOff {
            let taps = posts.filter { channel($0.channelID)?.platform == .tiktok && $0.publish == .waitingForYou }.count
            let tail = taps == 0 ? "" : (taps == 1 ? " 1 TikTok post needs your tap." : " \(taps) TikTok posts need your tap.")
            return "Hands-off posting is on. The Producer approves posts and Kairos posts them to YouTube and Instagram." + tail
        }
        return "Every post waits for your OK."
    }

    // MARK: Setup

    var setupSteps: [SetupStep] {
        let live = liveChannels
        let handles = live.map(\.handle).joined(separator: ", ")
        let unlooked = live.filter { $0.pack.isEmpty }
        let waitingCount = sheetsWaiting.count + packsWaiting.count
        let approvedPacks = packs.filter { $0.versions.contains { $0.status == .approved } }
        let social = channels.filter { $0.platform != .youtube }
        let socialConnected = social.filter { $0.connection == "Connected" }.count
        let postedCount = posts.filter { $0.publish == .posted }.count
        let awaiting = posts.filter { $0.publish == .awaiting }.count
        let ytProblem = channels.first { $0.platform == .youtube && $0.connection != "Connected" }
        return [
            SetupStep(number: 1, title: "Import the Content Studio team", status: hasTeam ? "7 bots, all at Ask. \(routinesOn) of \(routinesTotal) routines on." : "Not imported yet.", why: "Seven bots and the Producer who runs them.", state: hasTeam ? .done : .todo),
            SetupStep(number: 2, title: "Add your first channel", status: live.isEmpty ? "No channel yet." : "\(live.count) channels: \(handles).", why: "Create the channel on the platform yourself, then add it here. Kairos never creates accounts.", state: live.isEmpty ? .todo : .done),
            SetupStep(number: 3, title: "Choose the channel's look", status: live.isEmpty ? "Add a channel first." : (unlooked.isEmpty ? "Every channel has its look." : "Not set for \(unlooked.map(\.handle).joined(separator: ", ")))."), why: "The style pack, narrator voice and aspect the Editor makes this channel's videos in.", state: unlooked.isEmpty && !live.isEmpty ? .done : .todo),
            SetupStep(number: 4, title: "Approve a style pack and a sample", status: waitingCount > 0 ? "\(waitingCount) items waiting for your OK in Approvals." : "\(approvedPacks.count) packs approved: \(approvedPacks.map(\.name).joined(separator: ", ")).", why: "You approve a pack from its sample video, and each character from its sheet, before any channel uses them.", state: waitingCount > 0 ? .waiting : .done),
            SetupStep(number: 5, title: "Connect YouTube", status: !youtubeConfigured ? "Kairos has no Google project yet." : (ytProblem.map { "\($0.handle): \($0.connection)." } ?? "Every YouTube channel reads its numbers."), why: "Your own Google project reads numbers and, if you want, posts approved videos.", state: !youtubeConfigured ? .todo : (ytProblem == nil ? .done : .fix)),
            SetupStep(number: 6, title: "TikTok and Instagram", status: social.isEmpty ? "No TikTok or Instagram channel." : "\(socialConnected) of \(social.count) channels connected through an official app.", why: "Optional. Your own TikTok or Meta app lets Kairos post and read numbers; without one, Prepare post fills the upload page and page reads bring the numbers.", state: .optional, required: false),
            SetupStep(number: 7, title: "Start the team", status: (cycleRunning ? "A cycle is running now. " : "Last cycle: \(lastCycle). ") + (routinesOn == 0 ? "Daily routines paused." : "\(routinesOn) of \(routinesTotal) routines on."), why: handsOff ? "Hands-off posting is on, so the Producer approves posts." : "Every post still waits for your OK.", state: routinesOn > 0 ? .done : .todo),
            SetupStep(number: 8, title: "Approve and publish your first post", status: postedCount > 0 ? "\(postedCount) posts published." : (awaiting > 0 ? "\(awaiting) posts waiting for your approval." : "No post yet: the team brings one after its first cycle."), why: "Approving marks a post approved. You post it from Publishing.", state: postedCount > 0 ? .done : .todo),
        ]
    }

    var setupLeft: Int { setupSteps.filter { $0.required && $0.state != .done }.count }
    var setupRequired: Int { setupSteps.filter(\.required).count }

    // MARK: Navigation

    func go(_ scope: StudioScope) {
        withAnimation(Motion.snappy) {
            self.scope = scope
            tab = .dashboard
            publishFilter = "All"
        }
    }

    func open(_ tab: StudioTab, filter: String? = nil) {
        withAnimation(Motion.snappy) {
            if case .library = scope { scope = .all }
            self.tab = tab
            if let filter { publishFilter = filter }
        }
    }

    // MARK: Post actions

    func change(_ id: String, _ edit: (inout StudioPost) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.snappy) { edit(&posts[index]) }
    }

    func approve(_ id: String) {
        change(id) {
            $0.publish = .approved
            $0.stage = .approved
            $0.nextStep = "You: prepare it"
        }
    }

    func approveAll() -> Int {
        let ids = scoped(posts).filter { $0.publish == .awaiting }.map(\.id)
        ids.forEach(approve)
        return ids.count
    }

    func reject(_ id: String, reason: String) {
        change(id) {
            $0.publish = .rejected
            $0.stage = .rejected
            $0.rejectedTimes += 1
            $0.rejectReason = reason.isEmpty ? "No reason given" : reason
            $0.nextStep = "Team: waiting for a redraft"
        }
    }

    func redraft(_ id: String, note: String) {
        change(id) {
            $0.publish = .drafted
            $0.stage = .scripting
            if !note.isEmpty { $0.rejectReason = note }
            $0.rejectedTimes += 1
            $0.ageHours = 0
            $0.nextStep = "Team: writing a new draft"
        }
    }

    func prepare(_ id: String) -> String {
        guard let post = post(id), let channel = channel(post.channelID) else { return "Prepared." }
        change(id) {
            $0.publish = .prepared
            $0.nextStep = "You: open the upload page and press \(channel.platform.postButton)"
            $0.checklist = SampleStudio.checklist(for: channel.platform)
            $0.fillNote = "Kairos filled: Video, Title, Description, Tags, AI label. Not found on the page, do these yourself: Thumbnail."
        }
        return channel.platform == .youtube ? "Prepared for YouTube. Post to YouTube, or open the upload page." : "Prepared for \(channel.platform.name). Open the upload page when you are ready."
    }

    func markPosted(_ id: String, link: String) {
        change(id) {
            $0.publish = .posted
            $0.stage = .posted
            $0.link = link
            $0.posted = "just now"
            $0.scheduledDay = nil
            $0.nextStep = ""
        }
    }

    func publishNow(_ id: String) -> String {
        guard let post = post(id), let channel = channel(post.channelID) else { return "Posted." }
        markPosted(id, link: "https://example.com/watch/\(id)")
        switch channel.platform {
        case .youtube: return "Posted to YouTube as \(uploadPrivacy)."
        case .tiktok: return "Posted on TikTok."
        case .instagram: return "Posted on Instagram."
        }
    }

    func schedule(_ id: String, day: Int?, time: String) {
        change(id) {
            $0.scheduledDay = day
            $0.scheduledTime = day == nil ? "" : time
        }
    }

    // MARK: Library actions

    func setPack(_ id: String, version: Int, status: PackStatus, reason: String? = nil) {
        guard let p = packs.firstIndex(where: { $0.id == id }), let v = packs[p].versions.firstIndex(where: { $0.number == version }) else { return }
        withAnimation(Motion.snappy) {
            packs[p].versions[v].status = status
            packs[p].versions[v].rejection = reason
        }
    }

    func setCharacter(_ id: String, version: Int, status: CharacterStatus, reason: String? = nil) {
        guard let c = characters.firstIndex(where: { $0.id == id }), let v = characters[c].versions.firstIndex(where: { $0.number == version }) else { return }
        withAnimation(Motion.snappy) {
            characters[c].versions[v].status = status
            characters[c].versions[v].rejection = reason
        }
    }

    func makeSample(_ id: String, version: Int) {
        setPack(id, version: version, status: .rendering)
        Task {
            try? await Task.sleep(for: .seconds(3))
            setPack(id, version: version, status: .waiting)
        }
    }

    func setChannel(_ id: String, _ edit: (inout StudioChannel) -> Void) {
        guard let index = channels.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.snappy) { edit(&channels[index]) }
    }

    func runCycle() {
        cycleRunning = true
        Task {
            try? await Task.sleep(for: .seconds(6))
            cycleRunning = false
            lastCycle = "finished just now"
        }
    }

    /// Debug pictures open on a given place.
    func debugOpen(_ name: String) {
        switch name {
        case "studio-channel": scope = .channel("ch-trail")
        case "studio-approvals": tab = .approvals
        case "studio-pipeline": tab = .pipeline
        case "studio-calendar": tab = .calendar
        case "studio-publishing": tab = .publishing
        case "studio-analytics": tab = .analytics
        case "studio-report": tab = .report
        case "studio-settings": scope = .channel("ch-trail"); tab = .settings
        case "studio-formats": scope = .library(.formats)
        case "studio-styles": scope = .library(.styles)
        case "studio-characters": scope = .library(.characters)
        case "studio-connections": scope = .library(.connections)
        case "studio-templates": scope = .library(.templates)
        case "studio-picker": sheet = .picker
        case "studio-setup": sheet = .setup
        case "studio-confirm": sheet = .approvePost("p-chain")
        case "studio-handsoff": sheet = .handsOff
        case "studio-post": sheet = .post("p-gears")
        case "studio-checklist": sheet = .checklist("p-lights")
        default: break
        }
    }
}
