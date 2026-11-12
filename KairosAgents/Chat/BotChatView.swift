import SwiftUI

/// Talking to a bot feels like texting a person: its face and name top centre, Call top right,
/// bubbles, and small status chips while it works. Tap the face for its Inbox and Settings.
struct BotChatView: View {
    let bot: Bot

    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Namespace private var faceSpace
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var showPanel = false
    @State private var panelTab: BotPanelView.Tab = .inbox
    @State private var showCall = false
    @State private var showTools = false
    @FocusState private var typing: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .transition(.asymmetric(insertion: .scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity), removal: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                guard let last = messages.last else { return }
                withAnimation(Motion.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .kScreen(glowAt: UnitPoint(x: 0.5, y: -0.05))
        .fullScreenCover(isPresented: $showPanel) {
            BotPanelView(bot: bot, tab: panelTab)
                .navigationTransition(.zoom(sourceID: "face", in: faceSpace))
        }
        .fullScreenCover(isPresented: $showCall) {
            CallView(bot: bot)
        }
        .sheet(isPresented: $showTools) {
            ToolsSheet()
        }
        .onAppear {
            if messages.isEmpty { messages = SampleData.thread(for: bot) }
            switch router.debugScreen {
            case "botpanel": router.debugScreen = nil; showPanel = true
            case "botsettings": router.debugScreen = nil; panelTab = .settings; showPanel = true
            case "call": router.debugScreen = nil; showCall = true
            default: break
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            GlassIconButton(symbol: "chevron.left", label: "Back to Home") { dismiss() }
            Spacer()
            Button {
                Haptics.tap()
                panelTab = .inbox
                showPanel = true
            } label: {
                VStack(spacing: 5) {
                    BotFace(bot: bot, size: 72, blinks: true)
                        .matchedTransitionSource(id: "face", in: faceSpace)
                    HStack(spacing: 4) {
                        Text(bot.name).font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.inkFaint)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .kGlass(Capsule())
                }
            }
            .buttonStyle(PressStyle(scale: 0.93))
            .accessibilityLabel("\(bot.name). Open inbox and settings")
            Spacer()
            GlassIconButton(symbol: "phone", label: "Call \(bot.name)") { showCall = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background { HeaderFade() }
    }

    private var composer: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                GlassIconButton(symbol: "plus", label: "Add a photo, file or tool", size: 46) { showTools = true }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message \(bot.name)", text: $draft, axis: .vertical)
                        .font(KFont.ui(16.5))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1...5)
                        .focused($typing)
                        .padding(.vertical, 12)
                    Button {
                        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { typing = true } else { send() }
                    } label: {
                        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Image(systemName: hasText ? "arrow.up" : "mic")
                            .font(.system(size: 15, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(hasText ? Palette.onGold : Palette.inkDim)
                            .frame(width: 32, height: 32)
                            .background(hasText ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Color.clear), in: Circle())
                            .frame(width: 36, height: 46)
                    }
                    .buttonStyle(PressStyle(scale: 0.88))
                    .accessibilityLabel(draft.isEmpty ? "Dictate" : "Send")
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .kGlass(RoundedRectangle(cornerRadius: 23, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(Motion.snappy, value: draft.isEmpty)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Haptics.tap()
        draft = ""
        withAnimation(Motion.bouncy) { messages.append(ChatMessage(kind: .mine(text))) }
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(Motion.snappy) { messages.append(ChatMessage(kind: .status("\(bot.name) is thinking"))) }
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(Motion.bouncy) {
                messages.removeAll { if case .status = $0.kind { return true } else { return false } }
                messages.append(ChatMessage(kind: .theirs("This is sample data. Connect your desktop and I will answer for real.")))
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.kind {
        case .mine(let text):
            Text(text)
                .font(KFont.ui(16.5))
                .foregroundStyle(Palette.onGold)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(colors: [Palette.goldHi, Palette.gold], startPoint: .top, endPoint: .bottom),
                    in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 8, topTrailingRadius: 22, style: .continuous)
                )
                .frame(maxWidth: 300, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .theirs(let text):
            Text(text)
                .font(KFont.ui(16.5))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.surfaceRaised, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 8, bottomTrailingRadius: 22, topTrailingRadius: 22, style: .continuous))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 8, bottomTrailingRadius: 22, topTrailingRadius: 22, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .frame(maxWidth: 310, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .status(let text):
            HStack(spacing: 8) {
                PulsingDot(color: Palette.working, size: 6)
                Text(text).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        case .receipt(let text):
            Text(text)
                .font(KFont.ui(12, relativeTo: .caption))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, -4)
        }
    }
}

/// A bot's own page: Inbox (needs you, working, done, its report) and Settings.
struct BotPanelView: View {
    enum Tab: String, CaseIterable { case inbox = "Inbox", settings = "Settings" }

    let bot: Bot
    @State var tab: Tab
    @Environment(\.dismiss) private var dismiss
    @State private var answered = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    BotFace(bot: bot, size: 140, blinks: true)
                    Text(bot.name).font(KFont.display(40)).foregroundStyle(Palette.ink)
                    Text("\(bot.role) · \(bot.model) · \(bot.approval)")
                        .font(KFont.ui(14, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)

                GlassSwitch(items: Tab.allCases, selection: $tab) { $0.rawValue }
                    .fixedSize()

                if tab == .inbox { inbox.transition(.opacity.combined(with: .move(edge: .leading))) }
                else { settings.transition(.opacity.combined(with: .move(edge: .trailing))) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                GlassIconButton(symbol: "chevron.down", label: "Back to the chat") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .background { Ground(glowAt: UnitPoint(x: 0.5, y: 0.12)) }
        .animation(Motion.snappy, value: tab)
    }

    private var inbox: some View {
        VStack(spacing: 10) {
            ForEach(Array(SampleData.inbox(for: bot).enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if item.state == .working { PulsingDot(color: Palette.working, size: 6) }
                        Text(label(item.state)).font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(color(item.state))
                    }
                    Text(item.text).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    if item.state == .needsYou {
                        if answered {
                            Label("Answered", systemImage: "checkmark.circle.fill")
                                .font(KFont.ui(14, .medium, relativeTo: .footnote))
                                .foregroundStyle(Palette.success)
                                .padding(.top, 4)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        } else {
                            HStack(spacing: 8) {
                                inboxButton("Not now", filled: false)
                                inboxButton("Approve", filled: true)
                            }
                            .padding(.top, 6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .kCard(radius: 20, raised: item.state == .needsYou)
                .arrives(index)
            }
            GroupRow(title: "\(bot.name)'s report", symbol: "chart.bar.doc.horizontal", last: true)
                .kCard(radius: 20)
                .arrives(3)
        }
        .animation(Motion.bouncy, value: answered)
    }

    private func inboxButton(_ title: String, filled: Bool) -> some View {
        Button {
            Haptics.success()
            answered = true
        } label: {
            Text(title)
                .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(filled ? Palette.onGold : Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(filled ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private var settings: some View {
        VStack(spacing: 0) {
            GroupRow(title: "Model", symbol: "cpu", value: bot.model)
            GroupRow(title: "Approval", symbol: "checkmark.shield", value: "Ask")
            GroupRow(title: "Voice", symbol: "waveform", value: bot.voice)
            GroupRow(title: "Routines", symbol: "clock.arrow.circlepath", value: "3")
            GroupRow(title: "Memory and skills", symbol: "brain")
            GroupRow(title: "Look and name", symbol: "paintbrush", last: true)
        }
        .kCard(radius: 20)
    }

    private func label(_ state: InboxItem.State) -> String {
        switch state {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .done: "Done"
        }
    }

    private func color(_ state: InboxItem.State) -> Color {
        switch state {
        case .needsYou: Palette.goldText
        case .working: Palette.working
        case .done: Palette.success
        }
    }
}

/// The call screen: a night ground in every look, the bot's face, three round keys.
struct CallView: View {
    let bot: Bot
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false
    @State private var speaker = true
    @State private var started = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Minimize the call")
                Spacer()
                Text("KAIROS CALL").font(KFont.label).tracking(2.2)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.cream.opacity(0.8))
            .padding(.horizontal, 12)

            Spacer()

            ZStack {
                Circle().fill(Color(hex: 0x1F3A40))
                Circle().strokeBorder(Palette.cream.opacity(0.22), lineWidth: 3)
                BotFace(bot: bot, size: 156, blinks: true, stage: Color(hex: 0x1F3A40))
            }
            .frame(width: 196, height: 196)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 18)

            Text(bot.name).font(KFont.display(44)).foregroundStyle(Palette.cream).padding(.top, 22)
            LevelBars(color: Palette.cream.opacity(0.75)).padding(.top, 6)
            TimelineView(.periodic(from: started, by: 1)) { context in
                Text(timer(context.date))
                    .font(KFont.ui(16).monospacedDigit())
                    .foregroundStyle(Palette.cream.opacity(0.7))
            }
            .padding(.top, 10)

            Spacer()
            Spacer()

            HStack(spacing: 34) {
                callKey("speaker.wave.2.fill", "Speaker", on: speaker) { speaker.toggle() }
                callKey(muted ? "mic.slash.fill" : "mic.fill", "Mute", on: muted) { muted.toggle() }
                VStack(spacing: 8) {
                    Button {
                        Haptics.thud()
                        dismiss()
                    } label: {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(Palette.hangUp, in: Circle())
                    }
                    .buttonStyle(PressStyle(scale: 0.9))
                    Text("End").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.cream.opacity(0.7))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("End call")
            }
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(colors: [Palette.callTop, Palette.callBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private func callKey(_ symbol: String, _ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { action() }
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(on ? Color(hex: 0x2B2119) : Palette.cream)
                    .frame(width: 72, height: 72)
                    .background(on ? Palette.cream : Color(hex: 0x3E322A), in: Circle())
            }
            .buttonStyle(PressStyle(scale: 0.9))
            Text(title).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.cream.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func timer(_ now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
