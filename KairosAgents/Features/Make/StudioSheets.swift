import SwiftUI
import UIKit

/// Opens the sheet Studio asked for.
struct StudioSheetView: View {
    let sheet: StudioSheet
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        if studio.isLive, let content = liveContent(studio) { content } else { sampleBody }
    }

    @ViewBuilder
    private var sampleBody: some View {
        let studio = make.studio
        switch sheet {
        case .picker: StudioPickerSheet()
        case .setup: SetupSheet()
        case .addChannel: AddChannelSheet()
        case .post(let id): PostDetailsSheet(postID: id)
        case .checklist(let id): ChecklistSheet(postID: id)
        case .editPost(let id): EditPostSheet(postID: id)
        case .rejectPost(let id):
            NoteSheet(title: "Reject post", detail: studio.post(id)?.title, label: "Reason", limit: 500, button: "Reject post") { text in
                studio.reject(id, reason: text)
                toast.say("Rejected.")
                return true
            }
        case .redraftPost(let id):
            NoteSheet(title: "Send back for redraft", detail: studio.post(id)?.title, label: "Change note", limit: 500, button: "Send back for redraft") { text in
                studio.redraft(id, note: text)
                toast.say("Sent back for a new draft.")
                return true
            }
        case .approvePost(let id):
            let post = studio.post(id)
            MakeSwipeUpConfirm(
                title: "Approve this post?",
                detail: "\(post?.title ?? "") for \(studio.channel(post?.channelID ?? "")?.handle ?? "").",
                points: ["It moves to Publishing, ready to prepare.", "Nothing is posted until you press Post yourself."],
                confirmLabel: "Swipe up to approve"
            ) {
                studio.approve(id)
                toast.say("Approved. It is in Publishing, ready to prepare.")
            }
        case .approveAll:
            let count = studio.scoped(studio.posts).filter { $0.publish == .awaiting }.count
            MakeSwipeUpConfirm(title: "Approve all \(count) posts?", detail: "Each post is approved as it is. Nothing is posted.", confirmLabel: "Swipe up to approve all") {
                let done = studio.approveAll()
                toast.say(done == 1 ? "Approved 1 post." : "Approved \(done) posts.")
            }
        case .youtube(let id):
            MakeSwipeUpConfirm(
                title: "Post to YouTube?",
                detail: "\(studio.post(id)?.title ?? "") is uploaded exactly as approved.",
                points: ["Privacy: \(studio.uploadPrivacy).", "The AI content label is on.", "It may stay private until your Google project passes YouTube's audit."],
                confirmLabel: "Swipe up to post"
            ) { toast.say(studio.publishNow(id)) }
        case .instagram(let id):
            MakeSwipeUpConfirm(
                title: "Post to Instagram?",
                detail: "\(studio.post(id)?.title ?? "") goes out now as a Reel with Meta's AI label. Instagram has no schedule here.",
                confirmLabel: "Swipe up to post"
            ) { toast.say(studio.publishNow(id)) }
        case .tiktok(let id): TikTokPostSheet(postID: id)
        case .schedule(let id): ScheduleSheet(postID: id)
        case .markPosted(let id):
            NoteSheet(title: "Mark posted", detail: "After you pressed Post on the platform, paste the post's link.", label: "Live link", limit: 400, button: "Mark as posted", required: "Paste the link to the post.") { link in
                studio.markPosted(id, link: link)
                toast.say("Marked as posted. Its numbers can be tracked now.")
                return true
            }
        case .handsOff:
            MakeSwipeUpConfirm(
                title: "Turn on hands-off posting?",
                detail: "The Producer approves the team's posts and Kairos posts them on schedule.",
                points: ["At most the niche's slots a day per channel.", "TikTok still waits for your tap.", "You still get the weekly report and alerts for platform warnings, spend, failures, retirements and TikTok taps."],
                confirmLabel: "Swipe up to turn on"
            ) {
                withAnimation(Motion.snappy) { studio.handsOff = true }
                toast.say("Hands-off posting is on.")
            }
        case .runCycle:
            let channel = studio.liveChannels.first { $0.state == .live }
            MakeConfirmSheet(title: "Run one cycle for \(channel?.handle ?? "")?", detail: "The Producer researches, writes and renders one post. It still waits for your OK.", button: studio.cycleRunning ? "Cycle running" : "Run one cycle now") {
                if studio.cycleRunning {
                    toast.say("That cycle is already running.")
                } else {
                    studio.runCycle()
                    toast.say("The Producer started a cycle. It takes a few minutes.")
                }
            }
        case .resolve(let id):
            let channel = studio.channel(id)
            MakeConfirmSheet(title: "Resume this channel?", detail: channel?.warning ?? "", button: "Resume") {
                studio.setChannel(id) {
                    $0.state = .live
                    $0.warning = nil
                }
                toast.say("Channel resumed.")
            }
        case .archive(let id):
            MakeConfirmSheet(title: "Archive this channel?", detail: "Its history is kept. Nothing is posted from it until you restore it.", button: "Archive", danger: true) {
                studio.setChannel(id) { $0.state = .archived }
                toast.say("Channel archived.")
            }
        case .decision(let id):
            let decision = studio.decisions.first { $0.id == id }
            MakeConfirmSheet(title: "\(decision?.title ?? "")?", detail: decision?.title.hasPrefix("Retire") == true ? "The channel is archived and keeps its history. Its slot goes back to the niche." : "The Producer goes ahead with this.", button: "Confirm") {
                if let index = studio.decisions.firstIndex(where: { $0.id == id }) {
                    withAnimation(Motion.snappy) { studio.decisions[index].status = .confirmed }
                }
                toast.say("Confirmed.")
            }
        case .importNumbers: ImportNumbersSheet()
        case .newBrief: BriefSheet()
        case .editPack(let id): EditPackSheet(packID: id)
        case .duplicatePack(let id):
            NoteSheet(title: "Duplicate style pack", detail: nil, label: "Name", initial: "\(studio.pack(id)?.name ?? "") copy", limit: 80, button: "Duplicate") { name in
                guard var copy = studio.pack(id) else { return true }
                copy = StudioPack(id: UUID().uuidString, name: name.isEmpty ? "\(copy.name) copy" : name, origin: "Duplicated", summary: copy.summary, brief: copy.brief, facts: copy.facts, versions: [PackVersion(number: 1, status: .draft, note: "Duplicated.")])
                withAnimation(Motion.snappy) { studio.packs.append(copy) }
                toast.say("Duplicated as a draft.")
                return true
            }
        case .importPack: ImportPackSheet()
        case .packReject(let key):
            let parts = key.split(separator: "#").map(String.init)
            NoteSheet(title: "Reject pack", detail: nil, label: "Note", limit: 500, button: "Reject pack") { text in
                studio.setPack(parts[0], version: Int(parts.last ?? "") ?? 1, status: .rejected, reason: text)
                toast.say("Rejected.")
                return true
            }
        case .sheetReject(let key):
            let parts = key.split(separator: "#").map(String.init)
            NoteSheet(title: "Reject sheet", detail: nil, label: "Note", limit: 500, button: "Reject sheet") { text in
                studio.setCharacter(parts[0], version: Int(parts.last ?? "") ?? 1, status: .rejected, reason: text)
                toast.say("Rejected.")
                return true
            }
        case .planReject(let id):
            NoteSheet(title: "Reject plan", detail: studio.plans.first { $0.id == id }?.title, label: "Note", limit: 500, button: "Reject plan") { _ in
                withAnimation(Motion.snappy) { studio.plans.removeAll { $0.id == id } }
                toast.say("Rejected. The Producer plans again.")
                return true
            }
        case .newCharacter: NewCharacterSheet()
        case .characterVersion(let id): CharacterVersionSheet(characterID: id)
        case .accountChooser(let id): AccountChooserSheet(channelID: id)
        case .socialApp(let platform): SocialAppSheet(platform: platform)
        case .teamReport: TeamReportSheet()
        case .planApprove, .approveBatch, .resumeTeam, .sheetApprove, .packApprove, .decisionReject, .reportSend: EmptyView()
        }
    }

    /// The sheets while paired. Each change asks the desktop and says what it answered. A sheet that is not
    /// listed here (the libraries') is drawn as it always was.
    private func liveContent(_ studio: StudioStore) -> AnyView? {
        let live = MakeStudioLive.shared
        func held(_ text: String) -> AnyView { AnyView(MakeStudioHeldSheet(text: text)) }
        func say(_ work: @escaping () async -> MakeStudioOutcome) {
            Task { toast.say(await work().line) }
        }
        // Whatever could end in a public post is not offered while hands-off posting is on or not known. The send
        // itself reads the desktop again, so a sheet opened before the state changed still sends nothing.
        let hold = live.postingHeld(studio)
        let holdText = live.heldLine(studio)
        switch sheet {
        case .setup: return held(MakeStudioWords.setup)
        case .addChannel: return held(MakeStudioWords.addChannel)
        case .editPost: return held(MakeStudioWords.editPost)
        case .teamReport: return held(MakeStudioWords.teamReport)
        case .importNumbers: return held(MakeStudioWords.importNumbers)
        case .youtube, .tiktok, .instagram, .schedule, .markPosted: return held(MakeStudioWords.posting)
        case .handsOff: return held(MakeStudioWords.handsOffOn)
        case .accountChooser, .socialApp: return held(MakeStudioWords.accounts)
        case .post(let id): return AnyView(MakeStudioPostDetails(postID: id))
        case .checklist(let id): return AnyView(MakeStudioChecklist(postID: id))
        case .rejectPost(let id):
            return AnyView(NoteSheet(title: "Reject post", detail: studio.post(id)?.title, label: "Reason", limit: 500, button: "Reject post") { text in
                say { await live.reject(id, reason: text) }
                return true
            })
        case .redraftPost(let id):
            if hold { return held(holdText) }
            return AnyView(MakeConfirmSheet(title: "Send back for redraft?", detail: studio.post(id)?.title ?? "", button: "Send back for redraft") {
                say { await live.redraft(id) }
            })
        case .approvePost(let id):
            if hold { return held(holdText) }
            let post = studio.post(id)
            return AnyView(MakeSwipeUpConfirm(
                title: "Approve this post?",
                detail: "\(post?.title ?? "") for \(studio.channel(post?.channelID ?? "")?.handle ?? "").",
                points: ["It moves to Publishing, ready to prepare.", "Nothing is posted by approving. Posting is done in Kairos on your desktop."],
                confirmLabel: "Swipe up to approve"
            ) {
                say { await live.approve(id) }
            })
        case .approveAll:
            // Paired, Approvals opens .approveBatch with the ids it showed. This one is never opened paired.
            return held("Open Approvals to approve what is waiting.")
        case .approveBatch(let ids):
            if hold { return held(holdText) }
            // These ids were taken when the sheet opened: this count is what is sent, and nothing else.
            return AnyView(MakeSwipeUpConfirm(title: "Approve all \(ids.count) posts?",
                                              detail: "Exactly these \(ids.count) posts are approved, each as it is. Nothing is posted by approving.",
                                              confirmLabel: "Swipe up to approve all") {
                say { await live.approveAll(ids) }
            })
        case .runCycle:
            return held(MakeStudioWords.runCycle)
        case .resumeTeam:
            if hold { return held(holdText) }
            return AnyView(MakeConfirmSheet(title: "Resume the team?", detail: "The Producer and its bots start working again on your desktop.", button: "Resume team") {
                say { await live.setTeamPause(false) }
            })
        case .newBrief, .editPack, .duplicatePack, .importPack, .newCharacter, .characterVersion:
            // The libraries are not on live data yet: their sheets would change only the phone's copy.
            if !MakeStudioLive.librariesLive { return held(MakeStudioWords.libraries) }
            return nil
        case .resolve(let id):
            if hold { return held(holdText) }
            let channel = studio.channel(id)
            return AnyView(MakeConfirmSheet(title: "Resume \(channel?.handle ?? "this channel")?", detail: channel?.warning ?? "It starts making posts again.", button: "Resume") {
                say { await live.resumeChannel(id) }
            })
        case .archive(let id):
            return AnyView(MakeConfirmSheet(title: "Archive \(studio.channel(id)?.handle ?? "this channel")?", detail: "Its history is kept. Nothing is posted from it. Restoring it is done in Kairos on your desktop.", button: "Archive", danger: true) {
                say { await live.archiveChannel(id) }
            })
        case .decision(let id):
            let decision = studio.decisions.first { $0.id == id }
            return AnyView(MakeConfirmSheet(title: "\(decision?.title ?? "Confirm this decision")?", detail: "Your desktop goes ahead with this. A retirement archives its channels, which keep their history.", button: "Confirm") {
                say { await live.decide(id, confirm: true) }
            })
        case .decisionReject(let id):
            let decision = studio.decisions.first { $0.id == id }
            return AnyView(MakeConfirmSheet(title: "Reject \(decision?.title ?? "this decision")?", detail: "Nothing changes. The Producer is told it was turned down.", button: "Reject", danger: true) {
                say { await live.decide(id, confirm: false) }
            })
        case .planApprove(let id, let version):
            if hold { return held(holdText) }
            let plan = studio.plans.first { $0.id == id }
            return AnyView(MakeConfirmSheet(title: "Approve the plan for \(plan?.title ?? "this video")?", detail: "Your desktop approves the plan exactly as it read when you opened this, and renders the long video, which takes many minutes of its machine. If the plan changed since, nothing is approved.", button: "Approve plan") {
                say { await live.decidePlan(id, version: version, approve: true) }
            })
        case .planReject(let id):
            return AnyView(NoteSheet(title: "Reject plan", detail: studio.plans.first { $0.id == id }?.title, label: "Note", limit: 500, button: "Reject plan") { text in
                say { await live.decidePlan(id, approve: false, reason: text) }
                return true
            })
        case .sheetApprove(let key):
            if hold { return held(holdText) }
            let row = studio.liveSheetRows.first { $0.id == key }
            return AnyView(MakeConfirmSheet(title: "Approve \(row?.character.name ?? "this sheet"), version \(row?.version.number ?? 0)?", detail: "Videos may cast this version. Its sheet is not shown on this phone: approve it only if you have looked at it on your desktop.", button: "Approve sheet") {
                say { await live.decideSheet(key, approve: true) }
            })
        case .sheetReject(let key):
            return AnyView(NoteSheet(title: "Reject sheet", detail: nil, label: "Note", limit: 500, button: "Reject sheet") { text in
                say { await live.decideSheet(key, approve: false, reason: text) }
                return true
            })
        case .packApprove(let key):
            if hold { return held(holdText) }
            let row = studio.livePackRows.first { $0.id == key }
            return AnyView(MakeConfirmSheet(title: "Approve \(row?.pack.name ?? "this style pack"), version \(row?.version.number ?? 0)?", detail: "Channels and videos may use this version. Its sample is not shown on this phone: approve it only if you have watched it on your desktop.", button: "Approve pack") {
                say { await live.decidePack(key, approve: true) }
            })
        case .packReject(let key):
            return AnyView(NoteSheet(title: "Reject pack", detail: nil, label: "Note", limit: 500, button: "Reject pack") { text in
                say { await live.decidePack(key, approve: false, reason: text) }
                return true
            })
        case .reportSend:
            return AnyView(MakeConfirmSheet(title: "Send the report to your Inbox?", detail: "This puts a message in your Inbox on your desktop. With hands-off posting on, it also reaches you through Reach me. It cannot be taken back.", button: "Send report") {
                say { await live.sendReport() }
            })
        default:
            return nil
        }
    }
}

// MARK: - Generic sheets

/// A sheet with one text box and one button.
struct NoteSheet: View {
    let title: String
    let detail: String?
    let label: String
    var initial = ""
    var limit = 500
    let button: String
    var required: String? = nil
    /// Return true to close the sheet.
    let save: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        FittedSheet(estimate: 380) {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: title, detail: detail)
                MakeField(label: label, text: $text, limit: limit, lines: 2...6)
                if let error { Text(error).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
                GoldButton(title: button) {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let required, value.isEmpty {
                        error = required
                        return
                    }
                    Haptics.success()
                    if save(value) { dismiss() }
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear { text = initial }
    }
}

/// A plain confirm: a question, one sentence, the button.
struct MakeConfirmSheet: View {
    let title: String
    let detail: String
    let button: String
    var danger = false
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 300) {
            VStack(spacing: 14) {
                MakeSheetTitle(title: title, detail: detail)
                if danger {
                    MakePillButton(title: button, danger: true, expand: true) {
                        action()
                        dismiss()
                    }
                } else {
                    GoldButton(title: button) {
                        Haptics.success()
                        action()
                        dismiss()
                    }
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Setup

struct SetupSheet: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let studio = make.studio
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MakeSheetTitle(title: "Content setup", detail: "\(studio.setupRequired - studio.setupLeft) of \(studio.setupRequired) required steps done. \(studio.approvalLine)")
                ForEach(studio.setupSteps) { step in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("\(step.number)").font(KFont.ui(13, .semibold)).foregroundStyle(step.state == .done ? Palette.onGold : Palette.ink)
                                .frame(width: 26, height: 26)
                                .background(step.state == .done ? AnyShapeStyle(Palette.success) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Circle())
                            Text(step.title).font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink)
                            Spacer(minLength: 4)
                            StatePill(text: step.state.rawValue, tone: step.state.tone)
                        }
                        Text(step.status).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink.opacity(0.9))
                        Text(step.why).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).fixedSize(horizontal: false, vertical: true)
                        actions(step)
                    }
                    .padding(14)
                    .kCard(radius: 20, raised: step.state == .todo || step.state == .fix)
                    .arrives(step.number)
                }
                Text(studio.spendCap > 0 ? "Monthly spend cap: $\(studio.spendCap). The team stops when it is reached." : "No monthly spend cap is set yet (Bots > Usage).")
                    .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                Text("Kairos never creates accounts.").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                if studio.setupHidden {
                    MakePillButton(title: "Show setup on the dashboard") {
                        studio.setupHidden = false
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }

    @ViewBuilder
    private func actions(_ step: SetupStep) -> some View {
        let studio = make.studio
        HStack(spacing: 8) {
            switch step.number {
            case 1:
                if !studio.hasTeam {
                    MakePillButton(title: "Add the Content Studio team", filled: true) { studio.hasTeam = true; toast.say("Team added. Its routines start paused.") }
                } else {
                    MakePillButton(title: "Templates") { go(.library(.templates)) }
                }
            case 2:
                MakePillButton(title: studio.liveChannels.isEmpty ? "Add your first channel" : "Add another channel") { studio.sheet = .addChannel }
            case 3:
                if let channel = studio.liveChannels.first(where: { $0.pack.isEmpty }) ?? studio.liveChannels.first {
                    MakePillButton(title: "Open \(channel.handle) settings") {
                        studio.go(.channel(channel.id))
                        studio.tab = .settings
                        dismiss()
                    }
                }
            case 4:
                if step.state == .waiting { MakePillButton(title: "Review in Approvals", filled: true) { studio.open(.approvals); dismiss() } }
                MakePillButton(title: "Styles") { go(.library(.styles)) }
                MakePillButton(title: "Characters") { go(.library(.characters)) }
            case 5:
                if step.state == .fix, let channel = studio.channels.first(where: { $0.platform == .youtube && $0.connection != "Connected" }) {
                    MakePillButton(title: "Choose \(channel.handle)'s Google account", filled: true) { studio.sheet = .accountChooser(channel.id) }
                } else {
                    MakePillButton(title: "Open Connections") { go(.library(.connections)) }
                }
            case 6:
                MakePillButton(title: "Open Connections") { go(.library(.connections)) }
            case 7:
                MakePillButton(title: studio.cycleRunning ? "Cycle running" : "Run one cycle now", filled: !studio.cycleRunning) { studio.sheet = .runCycle }
                MakePillButton(title: studio.routinesOn == studio.routinesTotal ? "Pause routines" : "Turn on daily routines") {
                    if studio.routinesOn == studio.routinesTotal {
                        studio.routinesOn = 0
                        toast.say("Routines paused.")
                    } else {
                        studio.routinesOn = studio.routinesTotal
                        toast.say("Routines on: research at 6:00, render at 7:00, report on Mondays.")
                    }
                }
            default:
                if studio.posts.contains(where: { $0.publish == .awaiting }) {
                    MakePillButton(title: "Go to Approvals", filled: true) { studio.open(.approvals); dismiss() }
                }
                MakePillButton(title: "Open Publishing") { studio.open(.publishing); dismiss() }
            }
        }
        .scrollableRow()
    }

    private func go(_ scope: StudioScope) {
        make.studio.go(scope)
        dismiss()
    }
}

extension View {
    /// A row of buttons that scrolls sideways when it does not fit.
    func scrollableRow() -> some View {
        ScrollView(.horizontal) { self }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
    }
}

// MARK: - Add a channel

struct AddChannelSheet: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var niche = ""
    @State private var newNiche = ""
    @State private var platform: StudioPlatform = .youtube
    @State private var handle = ""
    @State private var error: String?

    var body: some View {
        let studio = make.studio
        let options = studio.niches.filter { !$0.retired }.map(\.name) + ["A new niche"]
        FittedSheet(estimate: 560) {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Add a channel", detail: "Kairos never creates accounts. Make the channel on the platform first.")
                VStack(spacing: 0) {
                    MakeChoiceRow(title: "Niche", options: options, selection: $niche, last: true)
                }
                .kCard(radius: 18)
                if niche == "A new niche" {
                    MakeField(label: "Niche name", text: $newNiche, prompt: "Commuter tips", limit: 60)
                }
                GlassSwitch(items: StudioPlatform.allCases, selection: $platform) { $0.name }
                MakeField(label: "Handle", text: $handle, prompt: "@yourchannel", limit: 60)
                if let error { Text(error).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
                GoldButton(title: "Add channel") { add() }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear { if niche.isEmpty { niche = options.first ?? "A new niche" } }
    }

    private func add() {
        let studio = make.studio
        var nicheID = studio.niches.first { $0.name == niche }?.id
        if niche == "A new niche" {
            let name = newNiche.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { error = "Name the niche first."; return }
            let created = StudioNiche(id: UUID().uuidString, name: name)
            studio.niches.append(created)
            nicheID = created.id
        }
        var name = handle.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let nicheID else { error = "Enter the channel handle."; return }
        if !name.hasPrefix("@") { name = "@" + name }
        let letters = String(name.dropFirst().prefix(2)).uppercased()
        let channel = StudioChannel(id: UUID().uuidString, handle: name, platform: platform, nicheID: nicheID, initials: letters.isEmpty ? "CH" : letters, hue: Double(studio.channels.count) * 0.17)
        withAnimation(Motion.snappy) { studio.channels.append(channel) }
        Haptics.success()
        toast.say("Channel added.")
        dismiss()
    }
}

// MARK: - Post details and checklist

struct PostDetailsSheet: View {
    let postID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss

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
                        StatBox(value: studio.niche(channel?.nicheID ?? "")?.name ?? "", label: "Niche")
                        StatBox(value: channel?.handle ?? "", label: "Channel")
                    }
                    if post.overdue { StatePill(text: "Overdue", tone: .error) }
                    if post.stage == .topic {
                        Text("A topic the Researcher found. The Evaluator picks which ones get made.")
                            .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    }
                    if post.publish == .rejected {
                        Text("Rejected: \(post.rejectReason ?? "")").font(KFont.ui(14.5)).foregroundStyle(Palette.danger)
                        MakePillButton(title: "Redraft", filled: true) {
                            studio.redraft(post.id, note: "")
                            toast.say("Sent back to drafting.")
                        }
                    }
                    stateActions(post, channel: channel)
                    preview(post, channel: channel)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
    }

    @ViewBuilder
    private func stateActions(_ post: StudioPost, channel: StudioChannel?) -> some View {
        let studio = make.studio
        switch post.publish {
        case .awaiting:
            MakePillButton(title: "Go to Approvals", filled: true, expand: true) { studio.open(.approvals); dismiss() }
        case .approved, .prepared, .waitingForYou, .failed:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if post.publish == .approved || post.publish == .failed {
                        MakePillButton(title: "Prepare post", filled: true, expand: true) { toast.say(studio.prepare(post.id)) }
                    } else {
                        MakePillButton(title: "Open in Publishing", filled: true, expand: true) { studio.open(.publishing); dismiss() }
                    }
                    MakePillButton(title: "Mark as posted", expand: true) { studio.sheet = .markPosted(post.id) }
                }
                if channel?.platform == .youtube {
                    if studio.postingConnected {
                        MakePillButton(title: "Post to YouTube", expand: true) { studio.sheet = .youtube(post.id) }
                    } else {
                        Text("Posting straight to YouTube: connect posting in Connections first.").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                }
            }
        case .posted:
            VStack(alignment: .leading, spacing: 6) {
                StatePill(text: "Posted", tone: .ok)
                if let link = post.link { Text(link).font(KFont.ui(14)).foregroundStyle(Palette.goldText) }
                Text("\(post.numberSets) number sets read.").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                if let numbers = post.numbers { numbersGrid(numbers) }
            }
        case .drafted, .rejected:
            EmptyView()
        }
    }

    private func preview(_ post: StudioPost, channel: StudioChannel?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Post preview")
            field("Why this topic", post.why.isEmpty ? "Not given." : post.why)
            if !post.format.isEmpty { field("Format", post.format) }
            field("Caption", post.caption.isEmpty ? "No caption yet." : post.caption)
            field("Tags", post.tags.isEmpty ? "None" : post.tags)
            field("Thumbnail", "A still from the second beat")
            field("Made for kids", post.kids)
            if !post.chapters.isEmpty { field("Chapters (added to the YouTube description)", post.chapters.joined(separator: "\n")) }
            field("Script", post.script.isEmpty ? "No script yet." : post.script)
            field("Video", post.stage == .rendering || post.stage == .topic || post.stage == .scripting ? "No render yet" : "Open in Studio")
            field("AI label", channel?.platform == .instagram ? "Not needed here; Prepare post turns it on anyway." : "Required. Prepare post turns it on.")
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

struct ChecklistSheet: View {
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
                    copyRow("Video", "spring-ride.mp4 · \(channel.aspect) · 0:42. This is the approved file.", copyable: false)
                    copyRow(channel.platform == .youtube ? "Title" : "Caption", channel.platform == .youtube ? post.title : post.caption)
                    if channel.platform == .youtube { copyRow("Description", post.caption) }
                    copyRow("Tags", post.tags)
                    Text("Hashtags are left out of the caption on purpose.").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    copyRow("Cover", "A still from the second beat", copyable: false)
                    copyRow("Schedule", post.scheduledDay.map { "\(weekDayNames[$0]) \(post.scheduledTime)" } ?? "Not scheduled", copyable: false)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Checklist")
                        ForEach(post.checklist) { line in
                            HStack {
                                Image(systemName: line.who == .missing ? "exclamationmark.circle" : (line.who == .you ? "hand.point.up.left" : "checkmark.circle.fill"))
                                    .foregroundStyle(line.who == .missing ? Palette.danger : (line.who == .you ? Palette.goldText : Palette.success))
                                Text(line.text).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(line.who.rawValue).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                            }
                            .frame(minHeight: 36)
                        }
                    }
                    .padding(14)
                    .kCard(radius: 18)
                    if post.checklist.contains(where: { $0.who == .missing }) {
                        Text("Fix before posting: add the thumbnail yourself.").font(KFont.ui(14, .medium)).foregroundStyle(Palette.danger)
                    }
                    PostActions(post: post)
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

struct EditPostSheet: View {
    let postID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var caption = ""
    @State private var script = ""
    @State private var kids = "The channel's answer"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Edit post")
                MakeField(label: "Title", text: $title, limit: 200, lines: 1...3)
                MakeField(label: "Caption", text: $caption, limit: 5000, lines: 2...6)
                MakeField(label: "Script", text: $script, limit: 20000, lines: 3...10)
                VStack(spacing: 0) {
                    MakeChoiceRow(title: "Made for kids", options: ["The channel's answer", "No, not made for kids", "Yes, made for kids"], selection: $kids, last: true)
                }
                .kCard(radius: 18)
                GoldButton(title: "Save changes") {
                    make.studio.change(postID) {
                        $0.title = title
                        $0.caption = caption
                        $0.script = script
                        $0.kids = kids
                    }
                    toast.say("Saved.")
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet()
        .onAppear {
            guard let post = make.studio.post(postID) else { return }
            title = post.title
            caption = post.caption
            script = post.script
            kids = post.kids
        }
    }
}

struct TikTokPostSheet: View {
    let postID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var visibility = ""
    @State private var comments = true
    @State private var duet = false
    @State private var stitch = false
    @State private var consent = false

    var body: some View {
        let studio = make.studio
        let post = studio.post(postID)
        let canPost = !visibility.isEmpty && consent && studio.tiktokAppSaved
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Post to TikTok", detail: post?.title)
                Text("Posting as \(studio.channel(post?.channelID ?? "")?.handle ?? ""). Until your app passes TikTok's audit, posts stay visible only to you.")
                    .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                if !studio.tiktokAppSaved {
                    Text("Cannot post through the API now: your TikTok app is not set up. Use the checklist and post it by hand.")
                        .font(KFont.ui(14, .medium)).foregroundStyle(Palette.danger)
                }
                VStack(spacing: 0) {
                    MakeChoiceRow(title: "Who can see this video", options: ["Everyone", "Friends", "Only me"], selection: Binding(get: { visibility.isEmpty ? "Choose" : visibility }, set: { visibility = $0 }))
                    MakeToggleRow(title: "Allow comments", isOn: $comments)
                    MakeToggleRow(title: "Allow Duet", isOn: $duet)
                    MakeToggleRow(title: "Allow Stitch", isOn: $stitch, last: true)
                }
                .kCard(radius: 18)
                Text(post?.caption ?? "").font(KFont.ui(15)).foregroundStyle(Palette.ink).padding(12).frame(maxWidth: .infinity, alignment: .leading).kCard(radius: 14)
                Text("AI-generated content: On").font(KFont.ui(14, .medium)).foregroundStyle(Palette.inkDim)
                Toggle(isOn: $consent) {
                    Text("I agree to TikTok's Music Usage Confirmation.").font(KFont.ui(14.5)).foregroundStyle(Palette.ink)
                }
                .tint(Palette.gold)
                GoldButton(title: "Post to TikTok") {
                    guard canPost else {
                        toast.say(visibility.isEmpty ? "Choose who can see this video first." : (consent ? "Set up your TikTok app first." : "Agree to the Music Usage Confirmation first."))
                        return
                    }
                    toast.say(studio.publishNow(postID))
                    dismiss()
                }
                .opacity(canPost ? 1 : 0.5)
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet()
    }
}

// MARK: - Schedule and mark posted

struct ScheduleSheet: View {
    let postID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var day: Int?
    @State private var time = "18:00"

    var body: some View {
        let studio = make.studio
        let post = studio.post(postID)
        let platform = studio.channel(post?.channelID ?? "")?.platform ?? .youtube
        FittedSheet(estimate: 520) {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Schedule", detail: post?.title)
                SectionLabel(text: "When")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        Button {
                            Haptics.select()
                            day = index
                        } label: {
                            Chip(text: "\(weekDayNames[index]) \(10 + index)", filled: day == index).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                VStack(spacing: 0) {
                    MakeChoiceRow(title: "Time", options: ["08:00", "09:30", "12:30", "15:00", "18:00", "20:30"], selection: $time, last: true)
                }
                .kCard(radius: 18)
                Text(note(platform)).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).fixedSize(horizontal: false, vertical: true)
                GoldButton(title: "Save schedule") {
                    guard let day else { toast.say("Choose a date and time."); return }
                    studio.schedule(postID, day: day, time: time)
                    toast.say("Scheduled for \(weekDayNames[day]) \(time).")
                    dismiss()
                }
                if post?.scheduledDay != nil {
                    QuietButton(title: "Clear schedule") {
                        studio.schedule(postID, day: nil, time: "")
                        toast.say("Schedule cleared.")
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear {
            day = post?.scheduledDay
            if let saved = post?.scheduledTime, !saved.isEmpty { time = saved }
        }
    }

    private func note(_ platform: StudioPlatform) -> String {
        switch platform {
        case .youtube: "YouTube sets the time when posting is connected."
        case .tiktok: "TikTok schedules on its own page."
        case .instagram: "Instagram posts at once, or schedule it in Meta Business Suite."
        }
    }
}

// MARK: - Import numbers

struct ImportNumbersSheet: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var text = "post,views,average view\nBrake pads: when to swap,12400,0:34\nSaddle height in one step,34100,15\nMuffins in one bowl,2,1:00\nA video we never made,10,0:20"
    @State private var read = false
    @State private var length = "45"
    @State private var mapping = ["post", "views", "average view"]

    private var rows: [[String]] {
        text.split(whereSeparator: \.isNewline).map { $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
    }

    private var problems: [String] {
        let posted = make.studio.posts.filter { $0.publish == .posted }.map(\.title)
        return rows.dropFirst().enumerated().compactMap { (index, row) -> String? in
            guard let name = row.first else { return "line \(index + 2): no post named" }
            if !posted.contains(name) { return "line \(index + 2): no posted post matches \"\(name)\"" }
            if row.count > 1, Int(row[1].replacingOccurrences(of: " ", with: "")) == nil { return "line \(index + 2): views is not a number" }
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Import numbers", detail: "Numbers attach to posted posts.")
                MakeField(label: "Paste rows", text: $text, limit: 20000, lines: 4...10)
                MakePillButton(title: "Read columns", filled: !read) {
                    guard rows.count > 1 else { toast.say("Add a header row and at least one row of numbers."); return }
                    withAnimation(Motion.snappy) { read = true }
                }
                if read, let header = rows.first {
                    VStack(spacing: 0) {
                        ForEach(Array(["Post (id, link or title)", "Views", "Average view duration"].enumerated()), id: \.offset) { index, field in
                            MakeChoiceRow(title: field, options: header, selection: $mapping[index], last: index == 2)
                        }
                    }
                    .kCard(radius: 18)
                    MakeField(label: "Video length if the file has none (seconds)", text: $length, limit: 5)
                    let ready = rows.count - 1 - problems.count
                    Text("\(ready) of \(rows.count - 1) rows ready.").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                    ForEach(problems.prefix(8), id: \.self) { Text($0).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
                    if problems.count > 8 { Text("And \(problems.count - 8) more.").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint) }
                    GoldButton(title: "Import \(ready) rows") {
                        toast.say("Imported \(ready) rows.")
                        dismiss()
                    }
                    .disabled(ready == 0)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet()
    }
}

// MARK: - Accounts and apps

struct AccountChooserSheet: View {
    let channelID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var choice: String?

    private let accounts: [(String, String)] = [("Shop account", "In use for this channel"), ("Studio account", "Added for YouTube only"), ("Old account", "Needs signing in again"), ("Use another Google account", "A new account is added for YouTube only")]

    var body: some View {
        let channel = make.studio.channel(channelID)
        FittedSheet(estimate: 520) {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Google account for \(channel?.handle ?? "")")
                VStack(spacing: 0) {
                    ForEach(accounts, id: \.0) { account in
                        Button {
                            Haptics.select()
                            choice = account.0
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: choice == account.0 ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(choice == account.0 ? Palette.goldText : Palette.inkFaint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.0).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                    Text(account.1).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                    }
                }
                .kCard(radius: 18)
                GoldButton(title: "Continue") {
                    guard let choice else { toast.say("Choose a Google account first."); return }
                    make.studio.setChannel(channelID) {
                        $0.connection = "Connected"
                        $0.connectedAs = choice == "Use another Google account" ? "New account" : choice
                    }
                    toast.say("Finish in Google's window on your desktop. Connected for this sample.")
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

struct SocialAppSheet: View {
    let platform: StudioPlatform
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var secret = ""
    @State private var audited = false
    @State private var returnMode = "Back to Kairos on this computer"

    var body: some View {
        let studio = make.studio
        let saved = platform == .tiktok ? studio.tiktokAppSaved : studio.instagramAppSaved
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: platform == .tiktok ? "Your TikTok app" : "Your Instagram (Meta) app", detail: "Your own app lets Kairos post and read numbers. Keys stay on your desktop.")
                MakeField(label: platform == .tiktok ? "Client key" : "App ID", text: $key, prompt: saved ? "Saved. Paste a new one to replace it." : "")
                VStack(alignment: .leading, spacing: 6) {
                    Text(platform == .tiktok ? "Client secret" : "App secret").font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    SecureField(saved ? "Saved. Paste a new one to replace it." : "", text: $secret)
                        .font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 12).kCard(radius: 16, raised: true)
                }
                VStack(spacing: 0) {
                    if platform == .tiktok {
                        MakeToggleRow(title: "My app passed TikTok's audit", isOn: $audited, last: true)
                    } else {
                        MakeChoiceRow(title: "Sign-in return", options: ["Back to Kairos on this computer", "Paste the address from Facebook"], selection: $returnMode, last: true)
                    }
                }
                .kCard(radius: 18)
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Redirect URI to register").font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        Text("http://localhost/callback").font(KFont.ui(14.5)).foregroundStyle(Palette.ink)
                    }
                    Spacer()
                    MakePillButton(title: "Copy") {
                        UIPasteboard.general.string = "http://localhost/callback"
                        toast.say("Redirect URI copied.")
                    }
                }
                .padding(12).kCard(radius: 14)
                GoldButton(title: "Save app") {
                    if !saved && key.isEmpty { toast.say("Enter the client key first."); return }
                    if !key.isEmpty && secret.isEmpty { toast.say("Paste the client secret too."); return }
                    if platform == .tiktok {
                        studio.tiktokAppSaved = true
                        studio.tiktokAudited = audited
                    } else {
                        studio.instagramAppSaved = true
                    }
                    toast.say("\(platform.name) app saved.")
                    dismiss()
                }
                if saved {
                    MakePillButton(title: "Remove app", danger: true, expand: true) {
                        if platform == .tiktok { studio.tiktokAppSaved = false } else { studio.instagramAppSaved = false }
                        toast.say("\(platform.name) app removed. Its channel connections are forgotten.")
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet()
        .onAppear { audited = studio.tiktokAudited }
    }
}

struct TeamReportSheet: View {
    private let members: [(String, String)] = [("Producer", "14 runs · 0 failed · $3.10"), ("Researcher", "21 runs · 1 failed · $2.40"), ("Script Writer", "9 runs · 0 failed · $1.90"), ("Editor", "9 runs · 1 failed · $4.20"), ("Publisher", "6 runs · 0 failed · $0.40")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MakeSheetTitle(title: "Team report", detail: "Content Studio team, this week. Asked you 4 times.")
                MakeTile(title: "What the team made", symbol: "film") {
                    Text("6 videos posted, 3 waiting for approval, 1 long video plan.").font(KFont.ui(15)).foregroundStyle(Palette.ink)
                }
                MakeTile(title: "Bots", symbol: "person.3") {
                    ForEach(members, id: \.0) { member in
                        HStack {
                            Text(member.0).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(member.1).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        .frame(minHeight: 36)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet([.medium, .large])
    }
}
