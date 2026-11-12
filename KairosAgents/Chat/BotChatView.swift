import SwiftUI

/// Talking to a bot feels like texting a person: its face and name top centre, Call top right,
/// bubbles, and small status chips while it works. Tap the face for its Inbox and Settings.
/// Everything comes from `ChatStore`: the sample desktop until one is paired, the person's desktop after.
struct BotChatView: View {
    /// The bot's id on the desktop (or in the sample data).
    let botID: String

    @State private var chat: BotChatState?

    var body: some View {
        Group {
            if let chat {
                BotChatScreen(chat: chat)
            } else {
                Color.clear.kScreen()
            }
        }
        .onAppear {
            guard chat == nil else { return }
            chat = ChatStore.shared.botChat(botID)
        }
    }
}

private struct BotChatScreen: View {
    let chat: BotChatState

    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @Environment(\.dismiss) private var dismiss
    @Namespace private var faceSpace
    @State private var draft = ""
    @State private var showPanel = false
    @State private var panelTab: BotPanelView.Tab = .inbox
    @State private var showCall = false
    @State private var showTools = false
    @State private var showModel = false
    @State private var modelAfterLoad = false
    @State private var viewer: ViewerStart?
    @FocusState private var typing: Bool

    private var bot: Bot { chat.bot }
    private var store: ChatStore { ChatStore.shared }

    var body: some View {
        let transcript = chat.transcript
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    content(transcript)
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: transcript.count) {
                withAnimation(Motion.snappy) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: transcript.last?.text.count) {
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
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
        .sheet(isPresented: $showModel) {
            BotModelSheet(chat: chat)
        }
        .sheet(item: $viewer) { start in
            let files = chat.files
            if !files.isEmpty {
                FileViewer(files: files, index: min(start.id, files.count - 1), load: chat.fileData).kSheet()
            }
        }
        .task { await chat.load() }
        .onChange(of: chat.phase) {
            // Debug screenshots: open the model drawer once the conversation is read.
            if modelAfterLoad && chat.phase == .loaded {
                modelAfterLoad = false
                showModel = true
            }
        }
        .onAppear {
            switch router.debugScreen {
            case "botmodel":
                router.debugScreen = nil
                if chat.phase == .loaded { showModel = true } else { modelAfterLoad = true }
            case "botpanel": router.debugScreen = nil; showPanel = true
            case "botsettings": router.debugScreen = nil; panelTab = .settings; showPanel = true
            case "call": router.debugScreen = nil; showCall = true
            default: break
            }
        }
        .onChange(of: chat.notice) {
            guard let notice = chat.notice else { return }
            chrome.say(notice)
            chat.notice = nil
        }
        .onChange(of: chat.restoredDraft) {
            guard let text = chat.restoredDraft else { return }
            draft = text
            chat.restoredDraft = nil
        }
        .onChange(of: store.generation) { dismiss() }
    }

    // MARK: Transcript

    @ViewBuilder
    private func content(_ transcript: [BotEntry]) -> some View {
        switch chat.phase {
        case .loading where transcript.isEmpty:
            ProgressView()
                .tint(Palette.inkDim)
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
        case .failed(let reason) where transcript.isEmpty:
            VStack(spacing: 12) {
                Text(reason)
                    .font(KFont.ui(15.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await chat.load() } }
                    .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
            .padding(.horizontal, 20)
        default:
            if chat.hasOlder {
                Button {
                    Task { await chat.loadOlder() }
                } label: {
                    Text(chat.loadingOlder ? "Loading" : "Show earlier messages")
                        .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.goldText)
                        .frame(minHeight: 44)
                }
                .buttonStyle(PressStyle())
                .disabled(chat.loadingOlder)
            }
            ForEach(transcript) { entry in
                row(entry)
                    .id(entry.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity), removal: .opacity))
            }
            ForEach(chat.requests) { request in
                RequestCard(
                    request: request,
                    onChoice: { chat.answer(request, choice: $0) },
                    onRespond: { chat.respond(request, answers: $0, skip: $1) })
                    .id(request.id)
            }
            if let status = chat.statusLine {
                MessageBubble(message: ChatMessage(kind: .status(status)))
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: BotEntry) -> some View {
        switch entry.kind {
        case .mine:
            VStack(alignment: .trailing, spacing: 6) {
                if !entry.text.isEmpty { MessageBubble(message: ChatMessage(kind: .mine(entry.text))) }
                if !entry.files.isEmpty { SentFiles(files: entry.files) { open($0) } }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .theirs:
            VStack(alignment: .leading, spacing: 6) {
                if !entry.text.isEmpty { MessageBubble(message: ChatMessage(kind: .theirs(entry.text))) }
                if !entry.files.isEmpty { SentFiles(files: entry.files) { open($0) } }
                if entry.failed {
                    Text("This reply did not finish.")
                        .font(KFont.ui(12.5, relativeTo: .caption))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .receipt:
            MessageBubble(message: ChatMessage(kind: .receipt(entry.text)))
        case .status:
            MessageBubble(message: ChatMessage(kind: .status(entry.text)))
        case .note:
            Text(entry.text)
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        case .card(let title):
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                if !entry.text.isEmpty {
                    MarkdownText(text: entry.text, size: 15)
                }
            }
            .padding(14)
            .frame(maxWidth: 320, alignment: .leading)
            .kCard(radius: 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func open(_ file: ChatFile) {
        let index = chat.files.firstIndex(where: { $0.id == file.id }) ?? 0
        viewer = ViewerStart(id: index)
    }

    // MARK: Header

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

    // MARK: Composer

    private var bottom: some View {
        VStack(spacing: 8) {
            if !chat.queue.isEmpty {
                QueueStrip(
                    items: chat.queue, paused: chat.queuePaused,
                    sendNow: { chat.steer($0) }, sendNowTitle: "Send now",
                    edit: { chat.editQueued($0) },
                    remove: { chat.removeQueued($0) })
            }
            if chat.phase == .loaded {
                HStack {
                    Button { showModel = true } label: {
                        Chip(text: modelChip)
                    }
                    .buttonStyle(PressStyle(scale: 0.95))
                    .accessibilityLabel("Model for this conversation: \(modelChip)")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
            }
            composer
        }
    }

    /// The conversation's model, then its thinking level when one is set.
    private var modelChip: String {
        if let model = chat.model, model.modelID != nil { return model.chip }
        return chat.modelLine ?? "Model"
    }

    private var hasText: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var showsStop: Bool { !hasText && chat.isBusy }

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
                        if showsStop {
                            Haptics.thud()
                            chat.interrupt()
                        } else if hasText {
                            send()
                        } else {
                            typing = true
                        }
                    } label: {
                        let filled = hasText || showsStop
                        Image(systemName: showsStop ? "stop.fill" : (hasText ? "arrow.up" : "mic"))
                            .font(.system(size: 15, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(filled ? Palette.onGold : Palette.inkDim)
                            .frame(width: 32, height: 32)
                            .background(filled ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Color.clear), in: Circle())
                            .frame(width: 36, height: 46)
                    }
                    .buttonStyle(PressStyle(scale: 0.88))
                    .accessibilityLabel(showsStop ? "Stop the reply" : (hasText ? (chat.isBusy ? "Add to the queue" : "Send") : "Dictate"))
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
        .animation(Motion.snappy, value: showsStop)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Haptics.tap()
        draft = ""
        withAnimation(Motion.bouncy) { chat.send(text) }
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
