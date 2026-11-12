import SwiftUI

/// Studio: the Content dashboard made for a phone. A channel picker on top (All channels, each
/// channel, the libraries), the team's posting strip, the setup checklist, then the tabs.
struct StudioScreen: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var studio = make.studio
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                scopeButton.arrives(0)
                StudioHead().arrives(1)
                StudioAlerts()
                if studio.hasTeam, studio.tabs.isEmpty == false { HandsOffStrip().arrives(2) }
                if !studio.setupHidden, studio.setupLeft > 0, studio.tabs.isEmpty == false { SetupCard().arrives(3) }
                if !studio.tabs.isEmpty {
                    GlassSwitch(items: studio.tabs, selection: $studio.tab) { tab in
                        if tab == .approvals {
                            let count = studio.waiting(for: studio.currentChannelID)
                            return count > 0 ? "Approvals \(count)" : "Approvals"
                        }
                        return tab.rawValue
                    }
                    .arrives(4)
                }
                content
                    .id(contentKey)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .animation(Motion.snappy, value: contentKey)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            MakeHeader(title: "Studio", subtitle: "Content", backSymbol: "chevron.down", backLabel: "Close Studio", back: { dismiss() }) {
                Button {
                    studio.sheet = .setup
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            if studio.setupLeft > 0 {
                                Text("\(studio.setupLeft)")
                                    .font(KFont.ui(11, .semibold, relativeTo: .caption2))
                                    .foregroundStyle(Palette.onGold)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Palette.gold, in: Circle())
                            }
                        }
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("Content setup, \(studio.setupLeft) steps left")
            }
        }
        .kScreen(glowAt: UnitPoint(x: 0.2, y: -0.05))
        .navigationDestination(isPresented: $studio.pushEditor) { VideoEditorScreen(projectID: "sample") }
        .sheet(item: $studio.sheet) { sheet in
            StudioSheetView(sheet: sheet)
                .environment(make)
                .environment(toast)
        }
    }

    private var contentKey: String {
        let studio = make.studio
        return "\(studio.scope)-\(studio.tab.rawValue)"
    }

    @ViewBuilder
    private var content: some View {
        let studio = make.studio
        switch studio.scope {
        case .library(let library):
            StudioLibraryView(library: library)
        case .all, .channel:
            switch studio.tab {
            case .dashboard:
                if let id = studio.currentChannelID { ChannelDashboard(channelID: id) } else { OverviewDashboard() }
            case .approvals: ApprovalsView()
            case .pipeline: PipelineView()
            case .calendar: StudioCalendarView()
            case .publishing: PublishingView()
            case .analytics:
                if let id = studio.currentChannelID { ChannelAnalyticsView(channelID: id) } else { ScoreboardView() }
            case .report: ReportView()
            case .settings:
                if let id = studio.currentChannelID { ChannelSettingsView(channelID: id) } else { OverviewDashboard() }
            }
        }
    }

    private var scopeButton: some View {
        let studio = make.studio
        return Button {
            Haptics.tap()
            studio.sheet = .picker
        } label: {
            HStack(spacing: 10) {
                switch studio.scope {
                case .all:
                    Image(systemName: "square.stack.3d.up").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.goldText)
                    Text("All channels")
                case .channel(let id):
                    if let channel = studio.channel(id) { ChannelAvatar(channel: channel, size: 28) }
                    Text(studio.channel(id)?.handle ?? "Channel")
                case .library(let library):
                    Image(systemName: library.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.goldText)
                    Text(library.rawValue)
                }
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.inkFaint)
            }
            .font(KFont.ui(16, .medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .kGlass(Capsule(), interactive: true)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Channel or library. Now showing \(scopeName)")
    }

    private var scopeName: String {
        let studio = make.studio
        switch studio.scope {
        case .all: return "All channels"
        case .channel(let id): return studio.channel(id)?.handle ?? "a channel"
        case .library(let library): return library.rawValue
        }
    }
}

/// The line under the picker: what this scope is.
struct StudioHead: View {
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        switch studio.scope {
        case .all:
            VStack(alignment: .leading, spacing: 3) {
                Text("All channels").font(KFont.display(32)).foregroundStyle(Palette.ink)
                Text("\(studio.liveChannels.filter { $0.state == .live }.count) live channels in \(studio.niches.filter { !$0.retired }.count) live niches. \(studio.approvalLine)")
                    .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .channel(let id):
            if let channel = studio.channel(id) {
                HStack(spacing: 12) {
                    ChannelAvatar(channel: channel, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.handle).font(KFont.display(28)).foregroundStyle(Palette.ink)
                        HStack(spacing: 6) {
                            StatePill(text: channel.platform.name, tone: .muted)
                            StatePill(text: channel.state.label, tone: channel.state.tone)
                            Text("Niche \(studio.niche(channel.nicheID)?.name ?? "")")
                                .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                        }
                    }
                }
            }
        case .library(let library):
            VStack(alignment: .leading, spacing: 3) {
                Text(library.rawValue).font(KFont.display(32)).foregroundStyle(Palette.ink)
                Text(library.about).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Platform warnings for paused channels, each with Resolve warning.
struct StudioAlerts: View {
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        let paused = studio.channels.filter { $0.state == .paused && (studio.currentChannelID == nil || studio.currentChannelID == $0.id) }
        if !paused.isEmpty, studio.tabs.isEmpty == false {
            VStack(spacing: 8) {
                ForEach(paused) { channel in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15)).foregroundStyle(Palette.danger)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Platform warning.").font(KFont.ui(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                            Text(channel.warning ?? "\(channel.handle) is paused.").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                                .fixedSize(horizontal: false, vertical: true)
                            MakePillButton(title: "Resolve warning") { studio.sheet = .resolve(channel.id) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.danger.opacity(0.35), lineWidth: 1))
                }
            }
        }
    }
}

/// The team's posting strip: one sentence, hands-off posting and Pause team.
struct HandsOffStrip: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

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
                    .contentTransition(.opacity)
            }
            HStack(spacing: 8) {
                MakePillButton(title: studio.handsOff ? "Turn hands-off posting off" : "Turn on hands-off posting", filled: !studio.handsOff, expand: true) {
                    if studio.handsOff {
                        withAnimation(Motion.snappy) { studio.handsOff = false }
                        toast.say("Hands-off posting is off. Every post waits for your OK.")
                    } else {
                        studio.sheet = .handsOff
                    }
                }
                MakePillButton(title: studio.teamPaused ? "Resume team" : "Pause team", symbol: studio.teamPaused ? "play.fill" : "pause.fill") {
                    withAnimation(Motion.snappy) { studio.teamPaused.toggle() }
                    toast.say(studio.teamPaused ? "Team paused." : "Team resumed.")
                }
            }
        }
        .padding(14)
        .background(studio.teamPaused ? Palette.danger.opacity(0.08) : Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(studio.teamPaused ? Palette.danger.opacity(0.4) : Palette.line, lineWidth: 1))
    }
}

/// The compact Content setup card: progress, the next step, and Hide.
struct SetupCard: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        let done = studio.setupRequired - studio.setupLeft
        let next = studio.setupSteps.first { $0.required && $0.state != .done }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Content setup").font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Button {
                    withAnimation(Motion.snappy) { studio.setupHidden = true }
                    toast.say("Setup hidden. The checklist button at the top brings it back.")
                } label: {
                    Text("Hide").font(KFont.ui(14, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).frame(minWidth: 44, minHeight: 36)
                }
            }
            Text("\(done) of \(studio.setupRequired) required steps done").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            ProgressLine(value: Double(done) / Double(max(1, studio.setupRequired)))
            if let next {
                Button { studio.sheet = .setup } label: {
                    HStack(spacing: 10) {
                        Text("\(next.number)").font(KFont.ui(13, .semibold)).foregroundStyle(Palette.onGold).frame(width: 24, height: 24).background(Palette.gold, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(next.title).font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                            Text(next.status).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.98))
            }
            Text("Kairos never creates accounts.").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
        }
        .padding(14)
        .kCard(radius: 22)
    }
}

/// The channel picker: All channels, each channel by niche, the libraries, Add channel and Set up.
struct StudioPickerSheet: View {
    @Environment(MakeStore.self) private var make
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let studio = make.studio
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MakeSheetTitle(title: "Channel or library")
                VStack(spacing: 0) {
                    pickRow(title: "All channels", detail: "Every niche and channel", count: studio.waiting(for: nil), selected: studio.scope == .all) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.goldText).frame(width: 36, height: 36)
                    } action: { go(.all) }
                }
                .kCard(radius: 20)

                ForEach(studio.niches) { niche in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: niche.retired ? "\(niche.name), retired" : niche.name)
                        let channels = studio.channels.filter { $0.nicheID == niche.id }
                        VStack(spacing: 0) {
                            if channels.isEmpty {
                                EmptyLine(text: "No channels yet.").padding(16)
                            }
                            ForEach(channels) { channel in
                                let sub = channel.state == .live ? studio.niche(channel.nicheID)?.name ?? "" : channel.state.label
                                pickRow(title: channel.handle, detail: "\(channel.platform.name) · \(sub)", count: studio.waiting(for: channel.id), selected: studio.scope == .channel(channel.id), danger: channel.state == .paused) {
                                    ChannelAvatar(channel: channel, size: 36)
                                } action: { go(.channel(channel.id)) }
                            }
                        }
                        .kCard(radius: 20)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Libraries")
                    VStack(spacing: 0) {
                        ForEach(StudioLibrary.allCases, id: \.self) { library in
                            pickRow(title: library.rawValue, detail: library.about, count: 0, selected: studio.scope == .library(library)) {
                                Image(systemName: library.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.goldText).frame(width: 36, height: 36)
                            } action: { go(.library(library)) }
                        }
                        pickRow(title: "Editor", detail: "Open the video editor", count: 0, selected: false) {
                            Image(systemName: "film").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.goldText).frame(width: 36, height: 36)
                        } action: {
                            dismiss()
                            studio.pushEditor = true
                        }
                        if studio.hasTeam {
                            pickRow(title: "Bot reports", detail: "The Content Studio team's report", count: 0, selected: false) {
                                Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.goldText).frame(width: 36, height: 36)
                            } action: { studio.sheet = .teamReport }
                        }
                    }
                    .kCard(radius: 20)
                }

                HStack(spacing: 10) {
                    MakePillButton(title: "Add channel", symbol: "plus", expand: true) { studio.sheet = .addChannel }
                    MakePillButton(title: "Set up", symbol: "checklist", expand: true) { studio.sheet = .setup }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }

    private func go(_ scope: StudioScope) {
        Haptics.select()
        make.studio.go(scope)
        dismiss()
    }

    private func pickRow<Icon: View>(title: String, detail: String, count: Int, selected: Bool, danger: Bool = false, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowBody(title: title, detail: detail, count: count, selected: selected, danger: danger, icon: icon)
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func rowBody<Icon: View>(title: String, detail: String, count: Int, selected: Bool, danger: Bool, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 12) {
            icon()
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(danger ? Palette.danger : Palette.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)").font(KFont.ui(12.5, .semibold, relativeTo: .caption)).foregroundStyle(Palette.onGold)
                    .frame(minWidth: 22, minHeight: 22).background(Palette.gold, in: Capsule())
            }
            if selected { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.goldText) }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 62) }
    }
}

/// A channel's round avatar: two letters, its own hue, and the platform mark.
struct ChannelAvatar: View {
    let channel: StudioChannel
    var size: CGFloat = 40

    var body: some View {
        Text(channel.initials)
            .font(KFont.ui(size * 0.34, .semibold))
            .foregroundStyle(Palette.night)
            .frame(width: size, height: size)
            .background(channel.color, in: Circle())
            .overlay(Circle().strokeBorder(Palette.ground, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                Text(channel.platform.short)
                    .font(.system(size: max(8, size * 0.2), weight: .heavy))
                    .foregroundStyle(Palette.cream)
                    .padding(.horizontal, 3)
                    .frame(height: max(12, size * 0.3))
                    .background(Palette.night, in: Capsule())
                    .offset(x: 3, y: 2)
            }
            .opacity(channel.state == .archived ? 0.55 : 1)
            .accessibilityHidden(true)
    }
}
