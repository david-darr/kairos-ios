import SwiftUI

/// A chat with a model: a title pill, steps as a live checklist, live work as cards in the
/// conversation, and a composer with the model chip and the approval chip.
/// Everything comes from `ChatStore`: the sample desktop until one is paired, the person's desktop after.
struct ModelChatView: View {
    /// The chat's id on the desktop (or in the sample data). nil means a brand new chat.
    let chatID: String?
    /// A new chat made from a project's page joins that project at its first message.
    var projectID: String? = nil

    @State private var chat: ModelChatState?

    var body: some View {
        Group {
            if let chat {
                ModelChatScreen(chat: chat)
            } else {
                Color.clear.kScreen()
            }
        }
        .onAppear {
            guard chat == nil else { return }
            if chatID == nil, let projectID {
                chat = ChatStore.shared.newModelChat(inProject: projectID)
            } else {
                chat = ChatStore.shared.modelChat(chatID)
            }
        }
    }
}

private struct ModelChatScreen: View {
    let chat: ModelChatState

    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showModel = false
    @State private var showTools = false
    @State private var viewer: ViewerStart?
    @State private var showDetails = false
    @State private var confirmFull = false
    @FocusState private var typing: Bool

    private var store: ChatStore { ChatStore.shared }

    var body: some View {
        let transcript = chat.transcript
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content(transcript)
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(chat.id == nil ? .top : .bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: transcript.last?.text.count) {
                proxy.scrollTo("end", anchor: .bottom)
            }
            .onChange(of: transcript.count) {
                withAnimation(Motion.snappy) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        .kScreen(glowAt: UnitPoint(x: 0.8, y: -0.05))
        .sheet(isPresented: $showModel) {
            ChatModelSheet(chat: chat) {
                showModel = false
                Task {
                    try? await Task.sleep(for: .seconds(0.35))
                    showDetails = true
                }
            }
        }
        .sheet(isPresented: $showDetails) {
            ChatDetailsSheet(chat: chat)
        }
        .confirmationDialog("Give this chat full access?", isPresented: $confirmFull, titleVisibility: .visible) {
            Button("Give full access", role: .destructive) {
                Haptics.thud()
                chat.apply { $0.approval = "Full access" }
            }
            Button("Keep asking first", role: .cancel) {}
        } message: {
            Text("The model will act on your desktop without asking, also after reading outside content. You can switch back at any time.")
        }
        .sheet(isPresented: $showTools) {
            ToolsSheet()
        }
        .sheet(item: $viewer) { start in
            let files = chat.files
            if files.isEmpty {
                DocumentViewer(documents: SampleData.documents, index: 0).kSheet()
            } else {
                FileViewer(files: files, index: min(start.id, files.count - 1), load: chat.fileData, thumbChat: chat.thumbKey).kSheet()
            }
        }
        .task { await chat.load() }
        .readsWhileOpen(chat)
        .onAppear {
            switch router.debugScreen {
            case "modelsheet": router.debugScreen = nil; showModel = true
            case "tools": router.debugScreen = nil; showTools = true
            case "docviewer": router.debugScreen = nil; viewer = ViewerStart(id: 0)
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            GlassIconButton(symbol: "chevron.left", label: "Back to Home") { dismiss() }
            Spacer(minLength: 8)
            VStack(spacing: 5) {
                Text(chat.title)
                    .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 15)
                    .frame(height: 44)
                    .kGlass(Capsule())
                if let line = statusLine {
                    HStack(spacing: 6) {
                        PulsingDot(color: Palette.working, size: 6)
                        Text(line).font(KFont.ui(12.5, .medium, relativeTo: .caption)).foregroundStyle(Palette.ink)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .kGlass(Capsule())
                }
            }
            Spacer(minLength: 8)
            Menu {
                Button("Documents", systemImage: "doc.on.doc") {
                    if chat.files.isEmpty && !chat.isSample {
                        chrome.say("This chat has no files yet.")
                    } else {
                        viewer = ViewerStart(id: 0)
                    }
                }
                Button("Model and details", systemImage: "chart.bar") { showModel = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .kGlass(Circle(), interactive: true)
            }
            .accessibilityLabel("More: documents, model and details")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background { HeaderFade() }
    }

    /// "Waiting for you", "Stopping", "2 running".
    private var statusLine: String? {
        if let activity = chat.activity { return activity }
        let count = chat.runningCount
        return count > 0 ? "\(count) running" : nil
    }

    // MARK: Transcript

    @ViewBuilder
    private func content(_ transcript: [TranscriptEntry]) -> some View {
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
            if chat.isEmpty {
                emptyState
            } else {
                ForEach(Array(transcript.enumerated()), id: \.element.id) { offset, entry in
                    line(entry).arrives(offset)
                }
                if let request = chat.request {
                    RequestCard(
                        request: request,
                        onChoice: { chat.answer(request, choice: $0) },
                        onRespond: { chat.respond(request, answers: $0, skip: $1) })
                        .id(request.id)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            BotFace(bot: SampleData.kip, size: 104, blinks: true)
            Text("What should we work on?")
                .font(KFont.display(32))
                .foregroundStyle(Palette.ink)
            Text("Ask anything, or tap + to add a file, browse the web or use your computer.")
                .font(KFont.ui(15.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func line(_ entry: TranscriptEntry) -> some View {
        switch entry.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                UserLine(text: entry.text)
                if !entry.files.isEmpty {
                    SentFiles(files: entry.files) { open($0) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            reply(entry)
        case .note:
            Text(entry.text)
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity)
        case .browser(let site):
            BrowserCard(site: site, onTakeOver: { router.open(.computer) }, onFullScreen: { router.open(.browse) })
        case .backgroundTask(let progress):
            BackgroundTaskCard(title: entry.text, progress: progress)
        }
    }

    private func reply(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let caption = entry.caption {
                Text(caption)
                    .font(KFont.ui(12.5, .medium, relativeTo: .caption))
                    .foregroundStyle(Palette.inkFaint)
            }
            if !entry.steps.isEmpty {
                StepList(steps: entry.steps)
                    .animation(Motion.snappy, value: entry.steps)
            }
            if !entry.text.isEmpty {
                MarkdownText(text: entry.text, streaming: entry.streaming)
            }
            if !entry.files.isEmpty {
                FileStack(files: entry.files, load: chat.fileData, thumbChat: chat.thumbKey) { open($0) }
            }
            let designs = chat.designCards(for: entry)
            if let key = chat.thumbKey, !designs.isEmpty {
                ChatThumbCards(designs: designs, chat: key)
            }
            ForEach(entry.sources) { source in
                SourceCard(site: source.site, title: source.title)
            }
            if let failure = entry.failure {
                HStack(spacing: 10) {
                    Text(failure)
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                    if !chat.isBusy, entry.id == chat.transcript.last?.id {
                        Button("Try again") { chat.retryLast() }
                            .font(KFont.ui(14.5, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Palette.goldText)
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ file: ChatFile) {
        let index = chat.files.firstIndex(where: { $0.id == file.id }) ?? 0
        viewer = ViewerStart(id: index)
    }

    // MARK: Composer

    private var bottom: some View {
        VStack(spacing: 8) {
            if !chat.queue.isEmpty {
                QueueStrip(
                    items: chat.queue, paused: chat.queuePaused,
                    sendNow: chat.isBusy ? nil : { _ in chat.sendNextQueued() },
                    edit: { chat.editQueued($0) },
                    remove: { chat.removeQueued($0) })
            }
            composer
        }
    }

    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var showsStop: Bool { chat.isBusy && !hasDraft && chat.run?.isRunning == true }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Reply", text: $draft, axis: .vertical)
                .font(KFont.ui(16.5))
                .foregroundStyle(Palette.ink)
                .lineLimit(1...6)
                .focused($typing)
                .padding(.top, 4)
            HStack(spacing: 8) {
                Button { showTools = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Palette.inkDim)
                        .frame(width: 34, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add files and tools")
                Button { showModel = true } label: { Chip(text: chat.settings.chip) }
                    .accessibilityLabel("Model: \(chat.settings.chip)")
                Button {
                    Haptics.select()
                    cycleApproval()
                } label: {
                    Chip(text: chat.settings.approval, filled: false)
                        .contentTransition(.numericText())
                }
                .accessibilityLabel("Approval: \(chat.settings.approval)")
                Spacer(minLength: 0)
                Button(action: showsStop ? stop : send) {
                    Image(systemName: showsStop ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: 36, height: 36)
                        .background(Palette.gold, in: Circle())
                        .opacity(chat.isStopping ? 0.5 : 1)
                        .frame(width: 44, height: 44)
                }
                .disabled(chat.isStopping)
                .accessibilityLabel(showsStop ? "Stop the reply" : (chat.isBusy ? "Add to the queue" : "Send"))
            }
            .buttonStyle(PressStyle(scale: 0.93))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .kGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(Motion.snappy, value: chat.settings.approval)
        .animation(Motion.snappy, value: showsStop)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            typing = true
            return
        }
        Haptics.tap()
        draft = ""
        withAnimation(Motion.bouncy) { chat.send(text) }
    }

    /// The approval chip steps through what the desktop allows; full access asks first.
    private func cycleApproval() {
        let all = chat.settings.approvals
        guard all.count > 1 else {
            chrome.say("Only an admin of the desktop can give a chat full access.")
            return
        }
        let index = all.firstIndex(of: chat.settings.approval) ?? 0
        let next = all[(index + 1) % all.count]
        if next == "Full access" {
            confirmFull = true
        } else {
            chat.apply { $0.approval = next }
        }
    }

    private func stop() {
        Haptics.thud()
        chat.stop()
    }
}
