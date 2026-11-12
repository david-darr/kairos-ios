import SwiftUI

// The tabs of Studio's Content dashboard, for All channels and for one channel.

func compactNumber(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 10_000 { return "\(value / 1000)K" }
    if value >= 1000 { return String(format: "%.1fK", Double(value) / 1000) }
    return "\(value)"
}

func durationText(_ seconds: Int) -> String {
    if seconds <= 0 { return "no number yet" }
    if seconds < 60 { return "\(seconds) s" }
    return "\(seconds / 60) min \(seconds % 60) s"
}

let weekDayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

// MARK: - Dashboards

struct OverviewDashboard: View {
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        VStack(spacing: 12) {
            NeedsTile(channelID: nil)
            MakeTile(title: "Latest posts", symbol: "play.rectangle", link: "Open publishing", linkAction: { studio.open(.publishing) }) {
                if studio.latestPosted.isEmpty { EmptyLine(text: "Nothing posted yet.") }
                ForEach(studio.latestPosted) { post in
                    Button { studio.sheet = .post(post.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.title).font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(post.numbers.map { "\(compactNumber($0.views)) views, \($0.averageView)s average view, \(compactNumber($0.likes)) likes" } ?? "No numbers yet.")
                                .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
            MakeTile(title: "Analytics", symbol: "chart.bar", link: "Open analytics", linkAction: { studio.open(.analytics) }) {
                HStack(spacing: 8) {
                    StatBox(value: "\(studio.posts.filter { $0.publish == .posted }.count)", label: "Posts posted")
                    StatBox(value: "\(studio.posts.filter { $0.numbers != nil }.count)", label: "With 7-day numbers")
                    StatBox(value: studio.niches.compactMap(\.score).max().map { String(format: "%.1f", $0) } ?? "None yet", label: "Best niche score")
                }
            }
            MakeTile(title: "Weekly report", symbol: "doc.plaintext", link: "Open report", linkAction: { studio.open(.report) }) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(SampleStudio.report.prefix(4), id: \.self) { line in
                        Text(line).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    }
                }
            }
            ComingUpTile()
            PipelineTile()
            MakeTile(title: "Your channels", symbol: "person.crop.square", link: "Add a channel", linkAction: { studio.sheet = .addChannel }) {
                if studio.channels.isEmpty { EmptyLine(text: "No channels yet.") }
                ForEach(studio.channels) { channel in
                    Button { studio.go(.channel(channel.id)) } label: {
                        HStack(spacing: 10) {
                            ChannelAvatar(channel: channel, size: 34)
                            Text(channel.handle).font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                            StatePill(text: channel.state.label, tone: channel.state.tone)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
        }
    }
}

struct NeedsTile: View {
    let channelID: String?
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        let rows = studio.needsYou(for: channelID)
        MakeTile(title: "What needs you", symbol: "bell.badge") {
            if rows.isEmpty { EmptyLine(text: channelID == nil ? "Nothing needs you right now." : "Nothing from this channel is waiting for you.") }
            ForEach(rows) { row in
                Button { studio.open(row.tab, filter: row.filter) } label: {
                    HStack(spacing: 10) {
                        Text("\(row.count)").font(KFont.ui(13, .semibold)).foregroundStyle(Palette.onGold)
                            .frame(minWidth: 24, minHeight: 24).background(Palette.gold, in: Circle())
                        Text(row.text).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.98))
            }
        }
    }
}

struct ComingUpTile: View {
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        MakeTile(title: "Coming up", symbol: "calendar", link: "Open calendar", linkAction: { studio.open(.calendar) }) {
            if studio.upcoming.isEmpty { EmptyLine(text: "Nothing scheduled yet. A post gets a time in Publishing (Schedule).") }
            ForEach(studio.upcoming) { post in
                Button { studio.sheet = post.publish == .prepared || post.publish == .waitingForYou ? .checklist(post.id) : .post(post.id) } label: {
                    HStack(spacing: 10) {
                        Text("\(weekDayNames[post.scheduledDay ?? 0]) \(post.scheduledTime)")
                            .font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.goldText).frame(width: 78, alignment: .leading)
                        Text(post.title).font(KFont.ui(15)).foregroundStyle(Palette.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.98))
            }
        }
    }
}

struct PipelineTile: View {
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        let list = studio.scoped(studio.posts)
        let overdue = list.filter(\.overdue).count
        MakeTile(title: "Pipeline", symbol: "arrow.right.circle", link: "Open pipeline", linkAction: { studio.open(.pipeline) }) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(PipelineStage.allCases.filter { $0 != .rejected }, id: \.self) { stage in
                    StatBox(value: "\(list.filter { $0.stage == stage }.count)", label: stage.rawValue)
                }
            }
            if overdue > 0 { Text("\(overdue) overdue.").font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
        }
    }
}

struct ChannelDashboard: View {
    let channelID: String
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        if let channel = studio.channel(channelID) {
            let latest = studio.latestPosted.first
            VStack(spacing: 12) {
                MakeTile(title: "Latest post performance", symbol: "chart.line.uptrend.xyaxis", link: "Open analytics", linkAction: { studio.open(.analytics) }) {
                    if let latest {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(latest.title).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink)
                            Text("Posted \(latest.posted ?? "")" + (latest.numbers.map { ". Read \($0.readAt) (\($0.source))." } ?? ""))
                                .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        if let numbers = latest.numbers {
                            numbersGrid(numbers)
                        } else {
                            EmptyLine(text: "No numbers yet. They come from the platform once it is read (Analytics).")
                        }
                        PillButton(title: "Open post") { studio.sheet = .post(latest.id) }
                    } else {
                        EmptyLine(text: "Nothing posted on this channel yet.")
                    }
                }
                MakeTile(title: "Channel numbers", symbol: "number") {
                    if channel.posts == 0 {
                        EmptyLine(text: "No numbers read yet.")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            StatBox(value: "\(channel.posts)", label: "Posts posted")
                            StatBox(value: compactNumber(channel.views), label: "Views")
                            StatBox(value: compactNumber(channel.follows), label: "Follows gained")
                            StatBox(value: durationText(channel.averageView), label: "Average view")
                        }
                    }
                }
                NeedsTile(channelID: channelID)
                ComingUpTile()
                PipelineTile()
                MakeTile(title: "Look and voice", symbol: "paintbrush", link: "Open settings", linkAction: { studio.open(.settings) }) {
                    Text(lookLine(channel)).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                }
            }
        }
    }

    private func lookLine(_ channel: StudioChannel) -> String {
        if channel.pack.isEmpty { return "No look set" }
        var parts = ["style \(channel.pack)", "look \(channel.lookID)", channel.aspect, "narrator \(channel.narrator)"]
        if !channel.voiceNotes.isEmpty { parts.append("voice notes set") }
        parts.append(channel.kids.hasPrefix("Yes") ? "made for kids" : "not made for kids")
        return parts.joined(separator: ", ")
    }
}

func numbersGrid(_ numbers: PostNumbers) -> some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
        StatBox(value: compactNumber(numbers.views), label: "Views")
        StatBox(value: durationText(numbers.averageView), label: "Average view")
        StatBox(value: compactNumber(numbers.likes), label: "Likes")
        StatBox(value: compactNumber(numbers.comments), label: "Comments")
        StatBox(value: compactNumber(numbers.shares), label: "Shares")
        StatBox(value: compactNumber(numbers.follows), label: "Follows gained")
    }
}

// MARK: - Approvals

struct ApprovalsView: View {
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        let posts = studio.scoped(studio.posts).filter { $0.publish == .awaiting }
        let plans = studio.plans.filter { !$0.approved && (studio.currentChannelID == nil || $0.channelID == studio.currentChannelID) }
        let showLibrary = studio.currentChannelID == nil
        let empty = posts.isEmpty && plans.isEmpty && (!showLibrary || (studio.sheetsWaiting.isEmpty && studio.packsWaiting.isEmpty))
        VStack(alignment: .leading, spacing: 12) {
            Text("Approving marks a post approved. Nothing is posted by approving: the Publisher prepares it, and you post it from Publishing.")
                .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            if studio.batchApproval && posts.count > 1 {
                PillButton(title: "Approve all \(posts.count)", symbol: "checkmark.circle", filled: true, expand: true) { studio.sheet = .approveAll }
            }
            if empty {
                EmptyLine(text: studio.currentChannelID == nil ? "Nothing is waiting for you. Posts appear here when the Producer brings them for approval." : "Nothing from this channel is waiting for you.")
                    .padding(.vertical, 20)
            }
            ForEach(posts) { post in ApprovalPostCard(post: post) }
            ForEach(plans) { plan in PlanCard(plan: plan) }
            if showLibrary {
                ForEach(Array(studio.sheetsWaiting.enumerated()), id: \.offset) { _, pair in SheetApprovalCard(character: pair.0, version: pair.1) }
                ForEach(Array(studio.packsWaiting.enumerated()), id: \.offset) { _, pair in PackApprovalCard(pack: pair.0, version: pair.1) }
            }
        }
    }
}

struct ApprovalPostCard: View {
    let post: StudioPost
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        let channel = studio.channel(post.channelID)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let channel { ChannelAvatar(channel: channel, size: 30) }
                Text("\(channel?.platform.name ?? "") · \(channel?.handle ?? "") · \(studio.niche(channel?.nicheID ?? "")?.name ?? "")")
                    .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            if post.rejectedTimes > 0 {
                StatePill(text: "Rejected \(post.rejectedTimes) x before", tone: .warn)
            }
            Text(post.title).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
            ZStack {
                LinearGradient(colors: [channel?.color.opacity(0.85) ?? Palette.gold, Palette.night], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.night)
                        .frame(width: 44, height: 44).background(Palette.cream.opacity(0.9), in: Circle())
                    Text(post.caption).font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.cream)
                        .multilineTextAlignment(.center).lineLimit(2).padding(.horizontal, 20)
                }
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Video preview")
            if !post.why.isEmpty {
                Text(post.why).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            }
            HStack(spacing: 8) {
                PillButton(title: "Approve", filled: true, expand: true) { studio.sheet = .approvePost(post.id) }
                PillButton(title: "Edit") { studio.sheet = .editPost(post.id) }
                Menu {
                    Button("Reject", systemImage: "xmark") { studio.sheet = .rejectPost(post.id) }
                    Button("Redraft", systemImage: "arrow.uturn.backward") { studio.sheet = .redraftPost(post.id) }
                    Button("Details", systemImage: "info.circle") { studio.sheet = .post(post.id) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44).background(Palette.ink.opacity(0.1), in: Circle())
                }
                .accessibilityLabel("More actions")
            }
            Text("After you approve, Publishing prepares it and opens the upload page; you press Post yourself.")
                .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .kCard(radius: 22, raised: true)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

struct PlanCard: View {
    let plan: StudioPlan
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @State private var showShots = false

    var body: some View {
        let studio = make.studio
        VStack(alignment: .leading, spacing: 10) {
            StatePill(text: "Long video plan", tone: .gold)
            Text(plan.title).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
            Text("For \(studio.channel(plan.channelID)?.handle ?? "")").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(plan.chapters, id: \.self) { Text($0).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim) }
            }
            DisclosureGroup("Every shot", isExpanded: $showShots) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.shots, id: \.self) { Text($0).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            .font(KFont.ui(15, .medium))
            .foregroundStyle(Palette.ink)
            .tint(Palette.goldText)
            HStack(spacing: 8) {
                PillButton(title: "Approve plan", filled: true, expand: true) {
                    if let index = studio.plans.firstIndex(where: { $0.id == plan.id }) {
                        withAnimation(Motion.snappy) { studio.plans[index].approved = true }
                    }
                    toast.say("Plan approved. The team can render it now.")
                }
                PillButton(title: "Reject") { studio.sheet = .planReject(plan.id) }
            }
        }
        .padding(14)
        .kCard(radius: 22, raised: true)
    }
}

struct SheetApprovalCard: View {
    let character: StudioCharacter
    let version: CharacterVersion
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        VStack(alignment: .leading, spacing: 10) {
            StatePill(text: "Character sheet", tone: .gold)
            Text("\(character.name), version \(version.number)").font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
            CharacterSheetArt(version: version, family: character.family).frame(height: 120)
            Text(version.note).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            HStack(spacing: 8) {
                PillButton(title: "Approve", filled: true, expand: true) {
                    studio.setCharacter(character.id, version: version.number, status: .approved)
                    toast.say("\(character.name) version \(version.number) approved.")
                }
                PillButton(title: "Reject") { studio.sheet = .sheetReject("\(character.id)#\(version.number)") }
            }
        }
        .padding(14)
        .kCard(radius: 22, raised: true)
    }
}

struct PackApprovalCard: View {
    let pack: StudioPack
    let version: PackVersion
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        VStack(alignment: .leading, spacing: 10) {
            StatePill(text: "Style pack", tone: .gold)
            Text("\(pack.name), version \(version.number)").font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
            HStack(spacing: 8) {
                PackSampleArt(name: pack.name).frame(height: 110)
                ContactSheetArt().frame(width: 110, height: 110)
            }
            VStack(alignment: .leading, spacing: 4) {
                if version.sampleNotes.isEmpty {
                    Text("The sample passed its checks.").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.success)
                }
                ForEach(version.sampleNotes.prefix(6), id: \.self) { note in
                    Text("· \(note)").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                }
            }
            HStack(spacing: 8) {
                PillButton(title: "Approve", filled: true, expand: true) {
                    studio.setPack(pack.id, version: version.number, status: .approved)
                    toast.say("\(pack.name) version \(version.number) approved.")
                }
                PillButton(title: "Reject") { studio.sheet = .packReject("\(pack.id)#\(version.number)") }
            }
        }
        .padding(14)
        .kCard(radius: 22, raised: true)
    }
}

// MARK: - Pipeline

struct PipelineView: View {
    @Environment(MakeStore.self) private var make
    @State private var stage: PipelineStage = .awaiting

    var body: some View {
        let studio = make.studio
        let list = studio.scoped(studio.posts)
        let stages = PipelineStage.allCases.filter { $0 != .rejected || list.contains { $0.stage == .rejected } }
        VStack(alignment: .leading, spacing: 12) {
            if list.isEmpty {
                EmptyLine(text: "No ideas in the pipeline yet. Topics and posts appear here as the team works.")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(stages, id: \.self) { item in
                        let count = list.filter { $0.stage == item }.count
                        Button {
                            Haptics.select()
                            withAnimation(Motion.snappy) { stage = item }
                        } label: {
                            Chip(text: "\(item.rawValue) \(count)", filled: stage == item)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityAddTraits(stage == item ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            let cards = list.filter { $0.stage == stage }.sorted { $0.ageHours > $1.ageHours }
            if cards.isEmpty { EmptyLine(text: "Nothing here.").padding(.vertical, 12) }
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, post in
                Button { studio.sheet = .post(post.id) } label: { PipelineCard(post: post) }
                    .buttonStyle(PressStyle(scale: 0.98))
                    .arrives(index)
            }
        }
    }
}

struct PipelineCard: View {
    let post: StudioPost
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        let channel = studio.channel(post.channelID)
        VStack(alignment: .leading, spacing: 6) {
            Text(post.title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
            Text("\(studio.niche(channel?.nicheID ?? "")?.name ?? "") · \(channel?.platform.name ?? "")")
                .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            HStack(spacing: 6) {
                Text("\(post.owner) · \(post.ageText)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                ForEach(post.flags, id: \.self) { flag in
                    StatePill(text: flag, tone: flag == "Render failed" ? .error : .warn)
                }
                Spacer(minLength: 0)
            }
            if post.overdue {
                Text("\(post.ageText) in this step, expected within \(post.expectedHours)h.").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(post.overdue ? Palette.danger.opacity(0.06) : Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(post.overdue ? Palette.danger.opacity(0.35) : Palette.line, lineWidth: 1))
    }
}

// MARK: - Calendar

struct StudioCalendarView: View {
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        let list = studio.scoped(studio.posts)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                GlassIconButton(symbol: "chevron.left", label: "Previous week", size: 40) { withAnimation(Motion.snappy) { studio.weekOffset -= 1 } }
                Text(weekLabel(studio.weekOffset)).font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                GlassIconButton(symbol: "chevron.right", label: "Next week", size: 40) { withAnimation(Motion.snappy) { studio.weekOffset += 1 } }
            }
            if studio.weekOffset != 0 {
                PillButton(title: "This week") { withAnimation(Motion.snappy) { studio.weekOffset = 0 } }
            }
            ForEach(0..<7, id: \.self) { day in
                let items = studio.weekOffset == 0 ? list.filter { $0.scheduledDay == day } : []
                let posted = studio.weekOffset == 0 ? list.filter { $0.publish == .posted && $0.posted?.hasPrefix(weekDayNames[day]) == true } : []
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(weekDayNames[day]) \(10 + day + studio.weekOffset * 7) Nov").font(KFont.ui(14, .semibold, relativeTo: .footnote)).foregroundStyle(day == 3 && studio.weekOffset == 0 ? Palette.goldText : Palette.inkDim)
                    if items.isEmpty && posted.isEmpty {
                        Text("Nothing.").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                    ForEach(items + posted) { post in calendarChip(post) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .kCard(radius: 18)
            }
        }
    }

    private func weekLabel(_ offset: Int) -> String {
        let start = 10 + offset * 7
        if offset == 0 { return "This week, \(start) to \(start + 6) Nov" }
        return "Week of \(start) Nov"
    }

    private func calendarChip(_ post: StudioPost) -> some View {
        let studio = make.studio
        let channel = studio.channel(post.channelID)
        return Button {
            studio.sheet = post.publish == .prepared || post.publish == .waitingForYou ? .checklist(post.id) : .post(post.id)
        } label: {
            HStack(spacing: 8) {
                Text(post.publish == .posted ? (post.posted?.components(separatedBy: " ").last ?? "") : post.scheduledTime)
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

// MARK: - Publishing

struct PublishingView: View {
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        let list = studio.scoped(studio.posts).filter { $0.publish != .drafted || $0.stage != .topic }
        let filters = ["All"] + (list.contains { $0.publish == .prepared || $0.publish == .waitingForYou } ? ["To post"] : []) + PublishState.allCases.filter { state in list.contains { $0.publish == state } }.map(\.rawValue)
        let shown = list.filter { post in
            switch studio.publishFilter {
            case "All": return true
            case "To post": return post.publish == .prepared || post.publish == .waitingForYou
            default: return post.publish.rawValue == studio.publishFilter
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            if let id = studio.currentChannelID, let channel = studio.channel(id) { RoutesPanel(channel: channel) }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.self) { filter in
                        let count = filter == "All" ? list.count : (filter == "To post" ? list.filter { $0.publish == .prepared || $0.publish == .waitingForYou }.count : list.filter { $0.publish.rawValue == filter }.count)
                        Button {
                            Haptics.select()
                            withAnimation(Motion.snappy) { studio.publishFilter = filter }
                        } label: {
                            Chip(text: "\(filter) \(count)", filled: studio.publishFilter == filter).frame(minHeight: 44)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            if list.isEmpty { EmptyLine(text: "No posts yet. They appear here from the first draft to the live link.") }
            else if shown.isEmpty { EmptyLine(text: "No posts in this state.") }
            ForEach(shown) { post in PublishRow(post: post) }
        }
    }
}

struct PublishRow: View {
    let post: StudioPost
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        let channel = studio.channel(post.channelID)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Button { studio.sheet = .post(post.id) } label: {
                    Text(post.title).font(KFont.ui(16.5, .semibold)).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                }
                .buttonStyle(PressStyle(scale: 0.98))
                Spacer(minLength: 8)
                StatePill(text: post.publish.rawValue, tone: post.publish.tone)
            }
            HStack(spacing: 6) {
                StatePill(text: channel?.platform.name ?? "", tone: .muted)
                Text(channel?.handle ?? "").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                if post.longVideo { StatePill(text: "Long video", tone: .working) }
            }
            Text(whenText).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            if !post.nextStep.isEmpty {
                Text(post.nextStep).font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(post.nextStep.hasPrefix("You") ? Palette.goldText : Palette.working)
            }
            if let fill = post.fillNote, post.publish == .waitingForYou || post.publish == .prepared || post.publish == .failed {
                Text(fill).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(post.publish == .failed ? Palette.danger : Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let link = post.link { Text(link).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.goldText).lineLimit(1) }
            PostActions(post: post)
        }
        .padding(14)
        .kCard(radius: 20)
    }

    private var whenText: String {
        if let posted = post.posted { return "Posted \(posted)" }
        if let day = post.scheduledDay { return "Scheduled for \(weekDayNames[day]) \(10 + day) Nov, \(post.scheduledTime)" }
        if post.publish == .approved || post.publish == .prepared { return "Approved, not scheduled" }
        return "Made \(post.ageText) ago"
    }
}

/// The actions a post offers in its state.
struct PostActions: View {
    let post: StudioPost
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        let platform = studio.channel(post.channelID)?.platform ?? .youtube
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                switch post.publish {
                case .awaiting:
                    PillButton(title: "Go to Approvals", filled: true) { studio.open(.approvals) }
                case .approved:
                    PillButton(title: "Prepare post", filled: true) { toast.say(studio.prepare(post.id)) }
                    PillButton(title: "Schedule") { studio.sheet = .schedule(post.id) }
                case .prepared, .waitingForYou:
                    PillButton(title: "Checklist", filled: true) { studio.sheet = .checklist(post.id) }
                    if platform == .youtube, studio.postingConnected {
                        PillButton(title: "Post to YouTube") { studio.sheet = .youtube(post.id) }
                    }
                    if platform == .tiktok {
                        PillButton(title: "Post to TikTok") { studio.sheet = .tiktok(post.id) }
                    }
                    if platform == .instagram, studio.instagramAppSaved {
                        PillButton(title: "Post to Instagram") { studio.sheet = .instagram(post.id) }
                    }
                    PillButton(title: post.publish == .waitingForYou ? "Open upload page again" : "Open upload page") {
                        toast.say("Open upload page needs the Kairos desktop app. The checklist has everything to post it by hand.")
                    }
                    PillButton(title: "Schedule") { studio.sheet = .schedule(post.id) }
                    PillButton(title: "Mark posted") { studio.sheet = .markPosted(post.id) }
                case .failed:
                    PillButton(title: "Prepare again", filled: true) { toast.say(studio.prepare(post.id)) }
                    PillButton(title: "Mark posted") { studio.sheet = .markPosted(post.id) }
                case .posted:
                    if let link = post.link, let url = URL(string: link) {
                        Link(destination: url) {
                            Text("Open post").font(KFont.ui(14.5, .semibold)).foregroundStyle(Palette.ink)
                                .padding(.horizontal, 14).frame(minHeight: 44).background(Palette.ink.opacity(0.1), in: Capsule())
                        }
                    }
                case .rejected:
                    PillButton(title: "Redraft", filled: true) { studio.sheet = .redraftPost(post.id) }
                case .drafted:
                    PillButton(title: "Details") { studio.sheet = .post(post.id) }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

struct RoutesPanel: View {
    let channel: StudioChannel
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        MakeTile(title: "How posts go out", symbol: "paperplane") {
            route("Prepare post", state: "Every post", button: nil) {}
            switch channel.platform {
            case .youtube:
                route("Post straight to YouTube", state: studio.postingConnected ? "Connected" : "Not connected", button: "Settings") { studio.open(.settings) }
            case .tiktok:
                route("Post straight to TikTok", state: studio.tiktokAppSaved ? (channel.connection == "Connected" ? "Connected as \(channel.connectedAs ?? "")" : "Not connected") : "No app yet", button: "Connections") { studio.go(.library(.connections)) }
            case .instagram:
                route("Post straight to Instagram", state: studio.instagramAppSaved ? "Connected as \(channel.connectedAs ?? "")" : "No app yet", button: "Connections") { studio.go(.library(.connections)) }
            }
            if channel.platform != .youtube {
                route("Page reads", state: studio.pageReads[channel.platform] == true ? "On" : "Off", button: "Connections") { studio.go(.library(.connections)) }
            }
        }
    }

    private func route(_ title: String, state: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                Text(state).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 0)
            if let button { PillButton(title: button, action: action) }
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Analytics

struct ScoreboardView: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @State private var weightText = ["50", "30", "20"]

    var body: some View {
        @Bindable var studio = make.studio
        VStack(alignment: .leading, spacing: 12) {
            Text("Score out of 100: views \(studio.weights[0]), watch time \(studio.weights[1]), follows and engagement \(studio.weights[2]). Each part is ranked within its platform.")
                .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            let needs = studio.decisions.filter { $0.status == .needsYou }
            MakeTile(title: "Needs your OK", symbol: "hand.raised") {
                if needs.isEmpty { EmptyLine(text: "No decisions wait for you.") }
                ForEach(needs) { decision in decisionRow(decision, actions: true) }
            }
            let withProducer = studio.decisions.filter { $0.status == .producer }
            if !withProducer.isEmpty {
                MakeTile(title: "With the Producer", symbol: "person.crop.circle") {
                    ForEach(withProducer) { decision in decisionRow(decision, actions: false) }
                }
            }
            scoreTile("Niches", SampleStudio.scores)
            scoreTile("Formats", SampleStudio.formatScores)
            scoreTile("Style packs", SampleStudio.packScores)
            MakeTile(title: "Top posts", symbol: "star") {
                ForEach(studio.posts.filter { $0.numbers != nil }.sorted { ($0.numbers?.views ?? 0) > ($1.numbers?.views ?? 0) }.prefix(5)) { post in
                    HStack {
                        Text(post.title).font(KFont.ui(15)).foregroundStyle(Palette.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        PillButton(title: "Open post") { studio.sheet = .post(post.id) }
                    }
                }
            }
            MakeTile(title: "Recent decisions", symbol: "clock.arrow.circlepath") {
                ForEach(studio.decisions.filter { $0.status == .confirmed || $0.status == .rejected }.prefix(12)) { decision in
                    decisionRow(decision, actions: false)
                }
            }
            MakeTile(title: "Team settings", symbol: "slider.horizontal.3") {
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        HStack {
                            Text(["Views at 7 days", "Watch time", "Follows and engagement"][index]).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                            Spacer()
                            TextField("0", text: $weightText[index])
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(KFont.ui(16, .medium))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 60, height: 40)
                                .padding(.horizontal, 8)
                                .background(Palette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text("%").foregroundStyle(Palette.inkFaint)
                        }
                    }
                    PillButton(title: "Save weights", filled: true, expand: true) { saveWeights() }
                    Toggle(isOn: Binding(get: { studio.batchApproval }, set: { value in
                        studio.batchApproval = value
                        toast.say(value ? "One-tap batch approval is on." : "One-tap batch approval is off.")
                    })) {
                        Text("One-tap batch approval").font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                    }
                    .tint(Palette.gold)
                    .frame(minHeight: 44)
                }
            }
        }
        .onAppear { weightText = studio.weights.map(String.init) }
    }

    private func saveWeights() {
        let labels = ["Views at 7 days", "Watch time", "Follows and engagement"]
        var values: [Int] = []
        for (index, text) in weightText.enumerated() {
            guard let value = Int(text), (0...100).contains(value) else {
                toast.say("\(labels[index]) must be between 0 and 100.")
                return
            }
            values.append(value)
        }
        guard values.contains(where: { $0 > 0 }) else {
            toast.say("At least one weight must be above 0.")
            return
        }
        make.studio.weights = values
        toast.say("Weights saved. Scores use them from now on.")
    }

    private func decisionRow(_ decision: StudioDecision, actions: Bool) -> some View {
        let studio = make.studio
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(decision.title).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink)
                Spacer(minLength: 6)
                StatePill(text: decision.status.rawValue, tone: decision.status == .needsYou ? .gold : (decision.status == .rejected ? .error : (decision.status == .confirmed ? .ok : .working)))
            }
            Text(decision.numbers).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            if let evidence = decision.evidence { Text(evidence).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim) }
            if actions {
                HStack(spacing: 8) {
                    PillButton(title: "Confirm", filled: true) { studio.sheet = .decision(decision.id) }
                    PillButton(title: "Reject") {
                        if let index = studio.decisions.firstIndex(where: { $0.id == decision.id }) {
                            withAnimation(Motion.snappy) { studio.decisions[index].status = .rejected }
                        }
                        toast.say("Rejected. Nothing changed.")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreTile(_ title: String, _ rows: [StudioScore]) -> some View {
        MakeTile(title: title, symbol: "list.number") {
            ForEach(rows) { row in
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

struct ChannelAnalyticsView: View {
    let channelID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        let posts = studio.posts.filter { $0.channelID == channelID && $0.publish == .posted }
        let channel = studio.channel(channelID)
        VStack(alignment: .leading, spacing: 12) {
            MakeTile(title: "Newest 12 posts", symbol: "chart.bar") {
                let numbers = posts.compactMap(\.numbers)
                if numbers.isEmpty {
                    EmptyLine(text: "No numbers read yet.")
                } else {
                    numbersGrid(PostNumbers(views: numbers.map(\.views).reduce(0, +), averageView: numbers.map(\.averageView).reduce(0, +) / numbers.count, likes: numbers.map(\.likes).reduce(0, +), comments: numbers.map(\.comments).reduce(0, +), shares: numbers.map(\.shares).reduce(0, +), follows: numbers.map(\.follows).reduce(0, +)))
                }
            }
            MakeTile(title: "Posts", symbol: "list.bullet") {
                if posts.isEmpty { EmptyLine(text: "Nothing posted on this channel yet.") }
                ForEach(posts) { post in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(post.title).font(KFont.ui(15)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(post.numbers.map { "\(compactNumber($0.views)) views, \(durationText($0.averageView)) average" } ?? "No numbers yet.")
                                .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: 6)
                        PillButton(title: "Open post") { studio.sheet = .post(post.id) }
                    }
                }
            }
            if let channel, let niche = studio.niche(channel.nicheID) {
                MakeTile(title: "This week", symbol: "calendar") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Posted in the last 7 days: \(posts.count) posts.")
                        Text("Scheduled from now on: \(studio.posts.filter { $0.channelID == channelID && $0.scheduledDay != nil && $0.publish != .posted }.count) posts.")
                        Text("Waiting for your approval: \(studio.waiting(for: channelID)) posts.")
                        Text(niche.score.map { "Its niche, \(niche.name), scores \(String(format: "%.1f", $0)) on the scoreboard." } ?? "Its niche, \(niche.name), is not scored yet.")
                    }
                    .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                }
                MakeTile(title: "Where the numbers come from", symbol: "arrow.down.circle") {
                    if channel.platform == .youtube {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("YouTube analytics").font(KFont.ui(15)).foregroundStyle(Palette.ink)
                                StatePill(text: channel.connection, tone: channel.connection == "Connected" ? .ok : .warn)
                            }
                            Spacer()
                            if channel.connection == "Connected" {
                                PillButton(title: "Sync now") { toast.say("Stored numbers for 2 posts.") }
                            } else {
                                PillButton(title: "Connections") { studio.go(.library(.connections)) }
                            }
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Page reads").font(KFont.ui(15)).foregroundStyle(Palette.ink)
                                Text(studio.pageReads[channel.platform] == true ? "On" : "Off").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                            }
                            Spacer()
                            PillButton(title: "Connections") { studio.go(.library(.connections)) }
                        }
                    }
                    HStack {
                        Text("Import numbers").font(KFont.ui(15)).foregroundStyle(Palette.ink)
                        Spacer()
                        PillButton(title: "Open") { studio.sheet = .importNumbers }
                    }
                }
            }
        }
    }
}

// MARK: - Report

struct ReportView: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        VStack(alignment: .leading, spacing: 12) {
            MakeTile(title: "Latest report", symbol: "doc.plaintext") {
                Text("3 to 9 Nov").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SampleStudio.report, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Palette.gold).frame(width: 5, height: 5)
                            Text(line).font(KFont.ui(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                PillButton(title: studio.reportSent ? "Sent to your Inbox" : "Send to my Inbox", symbol: studio.reportSent ? "checkmark" : "tray.and.arrow.down", filled: !studio.reportSent) {
                    guard !studio.reportSent else { return }
                    withAnimation(Motion.snappy) { studio.reportSent = true }
                    toast.say("Report sent to your Inbox.")
                }
            }
            MakeTile(title: "Import numbers", symbol: "square.and.arrow.down") {
                Text("Paste rows from a CSV file to attach numbers to posted posts.").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                PillButton(title: "Import numbers") { studio.sheet = .importNumbers }
            }
        }
    }
}

// MARK: - Channel settings

struct ChannelSettingsView: View {
    let channelID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @State private var draft: StudioChannel?
    @State private var longText = "0"

    var body: some View {
        let studio = make.studio
        if let channel = studio.channel(channelID) {
            VStack(alignment: .leading, spacing: 12) {
                MakeTile(title: "Channel status", symbol: "dot.radiowaves.left.and.right") {
                    StatePill(text: channel.state.label, tone: channel.state.tone)
                    HStack(spacing: 8) {
                        switch channel.state {
                        case .archived:
                            PillButton(title: "Restore", filled: true) {
                                studio.setChannel(channel.id) { $0.state = .live }
                                toast.say("Channel restored.")
                            }
                        case .paused:
                            PillButton(title: "Resolve warning", filled: true) { studio.sheet = .resolve(channel.id) }
                            PillButton(title: "Archive", danger: true) { studio.sheet = .archive(channel.id) }
                        case .live:
                            PillButton(title: "Archive", danger: true) { studio.sheet = .archive(channel.id) }
                        }
                    }
                }
                if channel.state == .archived {
                    EmptyLine(text: "An archived channel keeps its history. Restore it to change its settings.")
                } else {
                    connectionTile(channel)
                    lookForm(channel)
                }
            }
            .onAppear {
                draft = channel
                longText = "\(channel.longPerWeek)"
            }
        }
    }

    private func connectionTile(_ channel: StudioChannel) -> some View {
        let studio = make.studio
        return MakeTile(title: "\(channel.platform.name) connection", symbol: "link") {
            HStack {
                StatePill(text: channel.connection == "Connected" ? "Connected as \(channel.connectedAs ?? "")" : channel.connection, tone: channel.connection == "Connected" ? .ok : .warn)
                Spacer()
            }
            if channel.platform == .youtube {
                Text(channel.connection == "Connected" ? "Uses \(channel.connectedAs ?? "") for analytics and posting. Last synced today." : "Not connected. Choose the Google account that owns this channel.")
                    .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                HStack(spacing: 8) {
                    PillButton(title: channel.connection == "Connected" ? "Change" : "Connect", filled: channel.connection != "Connected") { studio.sheet = .accountChooser(channel.id) }
                    if channel.connection == "Connected" {
                        PillButton(title: "Disconnect", danger: true) {
                            studio.setChannel(channel.id) { $0.connection = "Not connected"; $0.connectedAs = nil }
                            toast.say("\(channel.handle) disconnected from YouTube.")
                        }
                    }
                }
            } else {
                let appReady = channel.platform == .tiktok ? studio.tiktokAppSaved : studio.instagramAppSaved
                if !appReady {
                    Text("Your \(channel.platform.name) app first.").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    PillButton(title: "Connections") { studio.go(.library(.connections)) }
                } else if channel.connection == "Connected" {
                    HStack(spacing: 8) {
                        PillButton(title: "Sync numbers now") { toast.say("Stored 3 number sets; 1 post now has its link.") }
                        PillButton(title: "Disconnect", danger: true) {
                            studio.setChannel(channel.id) { $0.connection = "Not connected"; $0.connectedAs = nil }
                            toast.say("\(channel.handle) disconnected.")
                        }
                    }
                } else {
                    PillButton(title: "Connect", filled: true) {
                        studio.setChannel(channel.id) { $0.connection = "Connected"; $0.connectedAs = "Shop page" }
                        toast.say("Finish signing in on your desktop. Connected for this sample.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lookForm(_ channel: StudioChannel) -> some View {
        let studio = make.studio
        let packOptions = ["Motion type (default)"] + studio.packs.filter { $0.versions.contains { $0.status == .approved } }.map(\.name)
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Look and voice")
            VStack(spacing: 0) {
                MakeChoiceRow(title: "Style pack", options: packOptions, selection: binding(\.pack, fallback: channel.pack))
                MakeChoiceRow(title: "3D renderer", options: ["The style pack's choice", "three.js (built in)", "Blender (not installed)"], selection: binding(\.renderer, fallback: channel.renderer))
                MakeChoiceRow(title: "Look", options: ["warm", "cool", "night", "paper"], selection: binding(\.lookID, fallback: channel.lookID))
                MakeChoiceRow(title: "Aspect", options: ["Platform default (9:16)", "9:16 tall", "16:9 wide", "1:1 square"], selection: binding(\.aspect, fallback: channel.aspect))
                MakeChoiceRow(title: "Frame rate", options: ["30", "60"], selection: binding(\.frameRate, fallback: channel.frameRate))
                MakeChoiceRow(title: "Narrator voice", options: ["Iris", "Ryan", "Wren", "Theo"], selection: binding(\.narrator, fallback: channel.narrator))
                MakeChoiceRow(title: "Made for kids", options: ["Not set", "No, not made for kids", "Yes, made for kids"], selection: binding(\.kids, fallback: channel.kids), last: channel.platform != .youtube)
                if channel.platform == .youtube {
                    HStack {
                        Text("Long videos a week").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        Spacer()
                        TextField("0", text: $longText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(KFont.ui(16, .medium))
                            .frame(width: 50, height: 40)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                }
            }
            .kCard(radius: 20)
            MakeField(label: "Voice notes", text: binding(\.voiceNotes, fallback: channel.voiceNotes), prompt: "How the narrator should sound", limit: 1000, lines: 2...5)
            HStack(spacing: 8) {
                Text("Cadence").font(KFont.ui(14, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                StatePill(text: "Once a day", tone: .muted)
                Text("\(studio.niche(channel.nicheID)?.slots ?? 1) posting slots in this niche").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            GoldButton(title: "Save settings") { save(channel) }
                .padding(.top, 4)
        }
    }

    private func binding(_ path: WritableKeyPath<StudioChannel, String>, fallback: String) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: path] ?? fallback },
            set: { value in draft?[keyPath: path] = value }
        )
    }

    private func save(_ channel: StudioChannel) {
        guard var draft else { return }
        if channel.platform == .youtube {
            guard let long = Int(longText), (0...7).contains(long) else {
                toast.say("Long videos a week is a whole number from 0 to 7.")
                return
            }
            draft.longPerWeek = long
        }
        make.studio.setChannel(channel.id) { $0 = draft }
        Haptics.success()
        toast.say("Settings saved.")
    }
}
