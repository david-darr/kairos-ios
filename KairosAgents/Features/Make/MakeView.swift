import SwiftUI

/// One place for everything Kairos creates: describe it, pick a kind and a look, watch it being made,
/// open the result. Studio, the designs and every made file are one tap away.
struct MakeView: View {
    var debugState: String? = nil

    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var store = MakeStore()
    @State private var toast = MakeToast()
    @State private var prompt = ""
    @State private var kind: MadeKind = .design
    @State private var look = MadeKind.design.looks[0]
    @State private var cover: MakeRoute?
    @State private var viewer: MakeViewerStart?
    @FocusState private var typing: Bool
    /// Paired: the kind the describe box asks the desktop for, and a real made file open in the viewer.
    @State private var liveKind: MakeHomeKind = .design
    @State private var liveFile: MakeHomeFileViewing?
    private let live = MakeHomeLive.shared

    /// Paired with a desktop: only the desktop's real work and items show, never a sample.
    private var paired: Bool { MakeHomeLive.paired }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if paired {
                    liveSections
                } else {
                    describeBox.arrives(0)

                    if !store.jobs.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(store.jobs) { job in
                                MakeJobCard(job: job, item: store.item(job.resultID), store: store, open: { open(job) }, again: { again(job) })
                                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                            }
                        }
                    }

                    studioCard.arrives(1)

                    shelf(.video, index: 2)
                    shelf(.design, index: 3)
                    shelf(.document, index: 4)
                    shelf(.deck, index: 5)
                    shelf(.sheet, index: 6)
                    shelf(.image, index: 7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .animation(Motion.bouncy, value: store.jobs)
            .animation(Motion.bouncy, value: live.cards)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .shrinksBar(chrome)
        .safeAreaInset(edge: .top, spacing: 0) {
            TabHeader(title: "Make") {
                GlassIconButton(symbol: "film.stack", label: "Studio") { cover = .studio }
                GlassIconButton(symbol: "magnifyingglass", label: "Search") { router.sheet = .search }
            }
        }
        .kScreen(glowAt: UnitPoint(x: 0.15, y: -0.05))
        .fullScreenCover(item: $cover) { route in
            MakeCover(start: route, store: store, toast: toast)
                .environment(router)
                .environment(chrome)
        }
        .sheet(item: $viewer) { start in
            DocumentViewer(documents: start.items.map(\.document), index: start.index)
                .kSheet()
        }
        .sheet(item: $liveFile) { start in
            DocsLiveViewer(files: start.files, index: start.index)
                .kSheet()
        }
        .task(id: MakeHomeLive.connectionKey) {
            live.followConnection()
            guard live.isLive else { return }
            await live.loadLive()
            // While something is being made, read the desktop again every few seconds, as its own page does.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                if live.needsPolling { await live.poll() }
            }
        }
        .onAppear {
            switch debugState {
            case "making": store.seedJob(done: false)
            case "result": store.seedJob(done: true)
            case "typed": prompt = "A booking page for the bike shop with prices"
            default: break
            }
        }
    }

    // MARK: Describe

    private var describeBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(kind.prompt, text: $prompt, axis: .vertical)
                .font(KFont.ui(17))
                .foregroundStyle(Palette.ink)
                .lineLimit(2...6)
                .focused($typing)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(MadeKind.makeable) { item in
                        Button {
                            Haptics.select()
                            withAnimation(Motion.snappy) {
                                kind = item
                                look = item.looks[0]
                            }
                        } label: {
                            Chip(text: item.title, symbol: item.symbol, filled: kind == item)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityAddTraits(kind == item ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                Menu {
                    ForEach(kind.looks, id: \.self) { option in
                        Button {
                            Haptics.select()
                            look = option
                        } label: {
                            if option == look { Label(option, systemImage: "checkmark") } else { Text(option) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paintbrush").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.goldText)
                        Text(look).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.inkFaint)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Palette.ink.opacity(0.08), in: Capsule())
                }
                .accessibilityLabel("Look: \(look)")

                Spacer(minLength: 0)

                Button(action: make) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                        Text("Make").font(KFont.ui(16, .semibold))
                    }
                    .foregroundStyle(canMake ? Palette.onGold : Palette.inkFaint)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(canMake ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(!canMake)
                .accessibilityLabel("Make this \(kind.title.lowercased())")
            }
        }
        .padding(16)
        .kGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(Motion.snappy, value: canMake)
    }

    private var canMake: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func make() {
        guard canMake else { return }
        Haptics.thud()
        typing = false
        store.start(prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, look: look)
        prompt = ""
        chrome.say("Making your \(kind.title.lowercased())")
    }

    private func again(_ job: MakeJob) {
        store.dismiss(job.id)
        store.start(prompt: job.prompt, kind: job.kind, look: job.look)
        chrome.say("Making another version")
    }

    private func open(_ job: MakeJob) {
        guard let item = store.item(job.resultID) else { return }
        open(item)
    }

    private func open(_ item: MakeItem) {
        Haptics.tap()
        switch item.kind {
        case .video: cover = .editor(item.id)
        case .design: cover = .design(DesignSample.firstID)
        default:
            let list = store.items(item.kind)
            viewer = MakeViewerStart(items: list, index: list.firstIndex(of: item) ?? 0)
        }
    }

    // MARK: Studio

    private var studioCard: some View {
        let studio = store.studio
        let waiting = studio.waiting(for: nil)
        let niches = studio.niches.filter { !$0.retired }.count
        let running = studio.cycleRunning || studio.posts.contains { $0.stage == .rendering }
        return VStack(spacing: 10) {
            sectionHead("Studio", trailing: "Content dashboard") { cover = .studio }
            Button { cover = .studio } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: -10) {
                        ForEach(Array(studio.liveChannels.prefix(4))) { channel in
                            ChannelAvatar(channel: channel, size: 42)
                        }
                        Spacer(minLength: 0)
                        if waiting > 0 {
                            Text("\(waiting) need you")
                                .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                                .foregroundStyle(Palette.onGold)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(Palette.gold, in: Capsule())
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(studio.liveChannels.count) channels · \(niches) niches")
                            .font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                        HStack(spacing: 6) {
                            if running { PulsingDot(color: Palette.working, size: 6) }
                            Text(studio.handsOff ? "Hands-off posting is on" : "Today's video is waiting for your review")
                                .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: 22)
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .accessibilityLabel("Studio. \(waiting) items need you")
        }
    }

    // MARK: Shelves

    @ViewBuilder
    private func shelf(_ kind: MadeKind, index: Int) -> some View {
        let items = store.items(kind)
        if !items.isEmpty {
            VStack(spacing: 10) {
                sectionHead("\(kind.plural)  \(items.count)", trailing: "All") {
                    cover = kind == .design ? .designs : .made(kind)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            Button { open(item) } label: { MadeCard(item: item) }
                                .buttonStyle(PressStyle(scale: 0.97))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .arrives(index)
        }
    }

    private func sectionHead(_ title: String, trailing: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
            Spacer()
            Button {
                Haptics.tap()
                action()
            } label: {
                HStack(spacing: 3) {
                    Text(trailing)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }

    // MARK: Paired

    @ViewBuilder
    private var liveSections: some View {
        if live.showing {
            liveDescribe.arrives(0)

            if let send = live.send {
                MakeHomeSendCard(send: send, retry: retrySend, leave: { live.leaveSend() })
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if let problem = live.sendProblem {
                MakeHomeLine(text: problem)
            }

            if !live.cards.isEmpty {
                VStack(spacing: 10) {
                    ForEach(live.cards) { job in
                        MakeHomeJobCard(job: job, result: live.result(for: job), busy: live.againBusy.contains(job.id),
                                        problem: live.jobProblems[job.id], canMake: live.send == nil && !live.notYours,
                                        open: { openLive($0) }, makeAnother: { makeAnother(job) },
                                        again: { Task { await live.again(job.id) } }, hide: { live.hide(job.id) })
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                }
            }

            if live.load == .loading && live.items.isEmpty {
                MakeHomeLine(text: "Reading what you made from your desktop.")
            }
            if case .failed(let why) = live.load {
                MakeHomeLine(text: why, action: "Try again") { Task { await live.loadLive() } }
            }
            if let problem = live.videosProblem {
                MakeHomeLine(text: problem, action: "Try again") { Task { await live.loadLive() } }
            }

            liveStudioCard.arrives(1)

            liveShelf(.video, index: 2)
            liveShelf(.design, index: 3)
            liveShelf(.deck, index: 4)
            liveShelf(.document, index: 5)

            if live.load == .loaded && live.items.isEmpty && live.cards.isEmpty {
                MakeHomeLine(text: "Nothing made yet. What you make here, and what your assistant makes for you, shows up here.")
            }
            if live.skipped > 0 {
                HintLine(text: live.skipped == 1 ? "1 item could not be read by this app." : "\(live.skipped) items could not be read by this app.")
            }
        } else {
            MakeHomeLine(text: "Reading what you made from your desktop.")
        }
    }

    private var liveText: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var liveTooLong: Bool { liveText.unicodeScalars.count > MakeHomeWire.textLimit }

    private var canMakeLive: Bool { !liveText.isEmpty && !liveTooLong && live.send == nil && !live.notYours }

    @ViewBuilder
    private var liveDescribe: some View {
        if live.notYours {
            MakeHomeLine(text: MakeHomeLive.notYoursLine)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                TextField(liveKind.prompt, text: $prompt, axis: .vertical)
                    .font(KFont.ui(17))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2...6)
                    .focused($typing)
                    .disabled(live.send != nil)

                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(MakeHomeKind.allCases) { item in
                            Button {
                                Haptics.select()
                                withAnimation(Motion.snappy) { liveKind = item }
                            } label: {
                                Chip(text: item.title, symbol: item.symbol, filled: liveKind == item)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .disabled(live.send != nil)
                            .accessibilityAddTraits(liveKind == item ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if liveTooLong {
                    HintLine(text: "One request can be up to 4,000 characters.")
                }

                HStack(spacing: 10) {
                    Text("Made on your desktop")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Button(action: makeLive) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                            Text(live.send == nil ? "Make" : "Sending").font(KFont.ui(16, .semibold))
                        }
                        .foregroundStyle(canMakeLive ? Palette.onGold : Palette.inkFaint)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(canMakeLive ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!canMakeLive)
                    .accessibilityLabel("Make this \(liveKind.title.lowercased()) on your desktop")
                }
            }
            .padding(16)
            .kGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .animation(Motion.snappy, value: canMakeLive)
        }
    }

    /// One tap, one send: the button is off until the desktop answers.
    private func makeLive() {
        let text = liveText
        guard canMakeLive else { return }
        Haptics.thud()
        typing = false
        let kind = liveKind
        Task { finishLive(await live.start(text: text, kind: kind), text: text) }
    }

    /// The unconfirmed tap again, with its own send id.
    private func retrySend() {
        guard let text = live.send?.text else { return }
        Task { finishLive(await live.retrySend(), text: text) }
    }

    /// A new request with the same words and kind: a new tap, so a new send id, as the desktop's own page sends it.
    private func makeAnother(_ job: MakeHomeJob) {
        guard let ask = job.ask, let kind = job.kind, live.send == nil else { return }
        Haptics.thud()
        Task { finishLive(await live.start(text: ask, kind: kind, fresh: true), text: ask) }
    }

    private func finishLive(_ outcome: MakeHomeOutcome, text: String) {
        guard outcome == .started else { return }
        if liveText == text { prompt = "" }
        chrome.say("Making it on your desktop")
    }

    private func openLive(_ item: MakeItem) {
        switch live.opens[item.id] {
        case .some(.design(let id)):
            Haptics.tap()
            cover = .design(id)
        case .some(.video):
            // The video editor does not read the desktop yet. Until it does, a paired phone never opens the sample one.
            chrome.say("Open this video in Kairos on your desktop")
        case .some(.file):
            Haptics.tap()
            liveFile = live.fileViewing(item)
        case .none:
            break
        }
    }

    private var liveStudioCard: some View {
        VStack(spacing: 10) {
            sectionHead("Studio", trailing: "Content dashboard") { cover = .studio }
            Button { cover = .studio } label: {
                HStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 42, height: 42)
                        .background(Palette.ink.opacity(0.08), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your content channels").font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                        Text("Approvals, posts and numbers in one place")
                            .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: 22)
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .accessibilityLabel("Studio")
        }
    }

    @ViewBuilder
    private func liveShelf(_ kind: MadeKind, index: Int) -> some View {
        let items = live.items(kind)
        if !items.isEmpty {
            VStack(spacing: 10) {
                sectionHead("\(MakeHomeLive.shelfTitle(kind))  \(items.count)", trailing: "All") {
                    cover = kind == .design ? .designs : .made(kind)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            Button { openLive(item) } label: { MadeCard(item: item) }
                                .buttonStyle(PressStyle(scale: 0.97))
                                .disabled(live.opens[item.id] == nil)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .arrives(index)
        }
    }
}

nonisolated struct MakeViewerStart: Identifiable, Hashable, Sendable {
    var id: String { items.map(\.id).joined() + "\(index)" }
    var items: [MakeItem]
    var index: Int
}

/// A made thing on a shelf: its picture, title and when, with "Just made" on new ones.
struct MadeCard: View {
    let item: MakeItem
    var width: CGFloat = 188

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MadeArt(item: item)
                .frame(width: width - 20, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) { if item.fresh { JustMadeMark().padding(7) } }
            Text(item.title).font(KFont.ui(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink).lineLimit(1)
            Text("\(item.kind.title) · \(item.when)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
        }
        .padding(10)
        .frame(width: width, alignment: .leading)
        .kCard(radius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.kind.title), \(item.when)\(item.fresh ? ", just made" : "")")
    }
}

struct JustMadeMark: View {
    var body: some View {
        Text("Just made")
            .font(KFont.ui(11.5, .semibold, relativeTo: .caption2))
            .foregroundStyle(Palette.onGold)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Palette.gold, in: Capsule())
    }
}

/// The drawn picture of a made thing. Videos get a play mark and their length.
struct MadeArt: View {
    let item: MakeItem

    var body: some View {
        ZStack {
            switch item.kind {
            case .video:
                LinearGradient(colors: [Color(hex: 0x5A4030), Color(hex: 0x241A14)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(hex: 0xE8C39E)).frame(width: 46, height: 46).offset(x: -34, y: 8)
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.night)
                    .frame(width: 38, height: 38)
                    .background(Palette.cream.opacity(0.9), in: Circle())
                Text(item.detail.components(separatedBy: " ").first ?? "")
                    .font(KFont.ui(11.5, .semibold, relativeTo: .caption2))
                    .foregroundStyle(Palette.cream)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
            case .image:
                LinearGradient(colors: [Color(hex: 0xD9B260), Color(hex: 0x8C5A2E)], startPoint: .top, endPoint: .bottom)
                Circle().fill(Palette.cream.opacity(0.85)).frame(width: 54, height: 54)
                Circle().strokeBorder(Palette.night.opacity(0.5), lineWidth: 3).frame(width: 40, height: 40)
            case .deck:
                Color(hex: 0x2E3A44)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(Palette.goldHi).frame(width: 90, height: 10)
                    Capsule().fill(Palette.cream.opacity(0.35)).frame(width: 120, height: 7)
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3).fill(Palette.cream.opacity(0.2)).frame(width: 30, height: 22)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            default:
                DocumentArt(look: item.kind.look)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A job being made: its steps with a live progress line and Stop or Resume; when done, the result card.
struct MakeJobCard: View {
    let job: MakeJob
    let item: MakeItem?
    let store: MakeStore
    let open: () -> Void
    let again: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: job.kind.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.goldText)
                Text(job.state == .done ? "Made" : (job.state == .stopped ? "Stopped" : "Making"))
                    .font(KFont.label).tracking(1.2).textCase(.uppercase).foregroundStyle(Palette.inkFaint)
                Spacer(minLength: 0)
                Text(job.look).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                Button {
                    store.dismiss(job.id)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkFaint).frame(width: 44, height: 32)
                }
                .accessibilityLabel(job.state == .done ? "Hide this card" : "Cancel")
            }

            if job.state == .done, let item {
                HStack(spacing: 12) {
                    MadeArt(item: item)
                        .frame(width: 96, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                        Text("\(item.kind.title) · \(item.detail)").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        JustMadeMark().padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    MakePillButton(title: "Open", filled: true, expand: true, action: open)
                    MakePillButton(title: "Make another", expand: true, action: again)
                    ShareLink(item: "\(item.title).\(item.kind.fileType.lowercased())") {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 44, height: 44)
                            .background(Palette.ink.opacity(0.1), in: Circle())
                    }
                    .accessibilityLabel("Share")
                }
            } else {
                Text(job.title).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(job.kind.steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 9) {
                            Group {
                                if index < job.step {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
                                } else if index == job.step && job.state == .running {
                                    PulsingDot(color: Palette.working, size: 7).frame(width: 16)
                                } else {
                                    Image(systemName: "circle").foregroundStyle(Palette.inkFaint)
                                }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 18)
                            Text(step)
                                .font(KFont.ui(14.5, relativeTo: .subheadline))
                                .foregroundStyle(index <= job.step ? Palette.ink : Palette.inkFaint)
                        }
                    }
                }
                ProgressLine(value: job.progress)
                HStack {
                    Text(job.state == .stopped ? "Stopped at \(Int(job.progress * 100))%" : "\(Int(job.progress * 100))%")
                        .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                        .contentTransition(.numericText())
                    Spacer()
                    if job.state == .running {
                        MakePillButton(title: "Stop", symbol: "stop.fill") { store.stop(job.id) }
                    } else {
                        MakePillButton(title: "Resume", symbol: "play.fill", filled: true) { store.resume(job.id) }
                    }
                }
            }
        }
        .padding(16)
        .kCard(radius: 24, raised: true)
        .animation(Motion.snappy, value: job.step)
        .animation(Motion.bouncy, value: job.state)
    }
}

/// A thin gold progress line.
struct ProgressLine: View {
    let value: Double
    var tint: Color = Palette.gold

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.1))
                Capsule().fill(tint).frame(width: max(6, geometry.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 6)
        .animation(Motion.gentle, value: value)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
