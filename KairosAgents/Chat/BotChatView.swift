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
