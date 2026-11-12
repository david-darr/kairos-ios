import SwiftUI

/// A chat with a model: a title pill, steps as a live checklist, live work as cards in the
/// conversation, and a composer with the model chip and the approval chip.
struct ModelChatView: View {
    /// nil means a brand new chat.
    let conversation: Conversation?

    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var sent: [String] = []
    @State private var showModel = false
    @State private var showTools = false
    @State private var viewer: ViewerStart?
    @State private var model = ModelChoice()
    @FocusState private var typing: Bool

    private var isLive: Bool { conversation?.id == "c-bike" }
    private var title: String { conversation?.title ?? "New chat" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if conversation == nil && sent.isEmpty {
                    emptyState
                } else if isLive {
                    liveTranscript
                } else if conversation != nil {
                    stepsTranscript
                }
                ForEach(sent, id: \.self) { text in
                    UserLine(text: text)
                    Text("This is sample data. Connect your desktop to get a real answer.")
                        .font(KFont.ui(16.5))
                        .foregroundStyle(Palette.inkDim)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(conversation == nil ? .top : .bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .kScreen(glowAt: UnitPoint(x: 0.8, y: -0.05))
        .sheet(isPresented: $showModel) {
            ModelSheet(choice: $model)
        }
        .sheet(isPresented: $showTools) {
            ToolsSheet()
        }
        .sheet(item: $viewer) { start in
            DocumentViewer(documents: SampleData.documents, index: start.id).kSheet()
        }
        .onAppear {
            switch router.debugScreen {
            case "modelsheet": router.debugScreen = nil; showModel = true
            case "tools": router.debugScreen = nil; showTools = true
            case "docviewer": router.debugScreen = nil; viewer = ViewerStart(id: 0)
            default: break
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            GlassIconButton(symbol: "chevron.left", label: "Back to Home") { dismiss() }
            Spacer(minLength: 8)
            VStack(spacing: 5) {
                Text(title)
                    .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 15)
                    .frame(height: 44)
                    .kGlass(Capsule())
                if isLive {
                    HStack(spacing: 6) {
                        PulsingDot(color: Palette.working, size: 6)
                        Text("2 running").font(KFont.ui(12.5, .medium, relativeTo: .caption)).foregroundStyle(Palette.ink)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .kGlass(Capsule())
                }
            }
            Spacer(minLength: 8)
            Menu {
                Button("Documents", systemImage: "doc.on.doc") { viewer = ViewerStart(id: 0) }
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

    // MARK: Transcripts (sample)

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

    private var stepsTranscript: some View {
        Group {
            UserLine(text: "Find 8 inch black zip ties in stock near me today.").arrives(0)
            StepList(steps: SampleData.zipSteps.enumerated().map { StepLine(id: String($0.offset), text: $0.element.text, done: $0.element.done) }).arrives(1)
            Text("Two stores have them in stock within 5 miles. One has a 100 pack for $6.98, ready for pickup in 2 hours.")
                .font(KFont.ui(16.5))
                .lineSpacing(4)
                .foregroundStyle(Palette.ink)
                .arrives(2)
        }
    }

    private var liveTranscript: some View {
        Group {
            UserLine(text: "Find three rivals' prices, design a booking page, and write a one-page plan.").arrives(0)
            BrowserCard().arrives(1)
            BackgroundTaskCard(title: "Writing the one-page plan", progress: 0.58).arrives(2)
            Text("I found three rival price lists and made the booking page. Sending both.")
                .font(KFont.ui(16.5))
                .lineSpacing(4)
                .foregroundStyle(Palette.ink)
                .arrives(3)
            DocumentStack(documents: SampleData.documents) { index in viewer = ViewerStart(id: index) }
                .arrives(4)
            SourceCard(site: "cyclerepair.example", title: "Tune-up prices, 2026").arrives(5)
        }
    }

    // MARK: Composer

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
                Button { showModel = true } label: { Chip(text: "\(model.name) · \(model.level)") }
                    .accessibilityLabel("Model: \(model.name), thinking \(model.level)")
                Button {
                    Haptics.select()
                    model.cycleApproval()
                } label: {
                    Chip(text: model.approval, filled: false)
                        .contentTransition(.numericText())
                }
                .accessibilityLabel("Approval: \(model.approval)")
                Spacer(minLength: 0)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: 36, height: 36)
                        .background(Palette.gold, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Send")
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
        .animation(Motion.snappy, value: model.approval)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            typing = true
            return
        }
        Haptics.tap()
        draft = ""
        withAnimation(Motion.bouncy) { sent.append(text) }
    }
}
