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
                        Text("2 running").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.working)
                    }
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
            StepList(steps: SampleData.zipSteps).arrives(1)
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

/// Which file the viewer opens on.
struct ViewerStart: Identifiable {
    let id: Int
}

/// What the model sheet edits.
struct ModelChoice: Equatable {
    static let levels = ["Low", "Med", "High", "XHigh", "Max"]
    static let approvals = ["Ask first", "Edits", "Auto", "Full access"]

    var name = "Claude Opus"
    var source = "Claude subscription"
    var level = "High"
    var fast = false
    var approval = "Ask first"

    mutating func cycleApproval() {
        let index = Self.approvals.firstIndex(of: approval) ?? 0
        approval = Self.approvals[(index + 1) % Self.approvals.count]
    }
}

struct UserLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(KFont.ui(16.5))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: 310, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Steps the model has taken, as a checklist that fills in while it works.
struct StepList: View {
    let steps: [ChatStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(steps) { step in
                HStack(spacing: 10) {
                    if step.done {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.success)
                    } else {
                        PulsingDot(color: Palette.working, size: 8).frame(width: 16, height: 16)
                    }
                    Text(step.text)
                        .font(KFont.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(step.done ? Palette.inkDim : Palette.ink)
                }
            }
        }
    }
}

// MARK: - Live work cards

struct BrowserCard: View {
    @State private var pointer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: 0xEFE6D6), Color(hex: 0xD9CDB8)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 9) {
                    Capsule().fill(Palette.night.opacity(0.15)).frame(height: 12)
                    Capsule().fill(Palette.night.opacity(0.22)).frame(width: 190, height: 10)
                    Capsule().fill(Palette.night.opacity(0.12)).frame(width: 130, height: 10)
                    Capsule().fill(Palette.night.opacity(0.12)).frame(width: 160, height: 10)
                }
                .padding(12)
                Circle()
                    .fill(Palette.gold)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Palette.gold.opacity(0.3)).frame(width: 30, height: 30))
                    .offset(x: pointer ? 210 : 150, y: pointer ? 52 : 84)
            }
            .frame(height: 122)
            .clipped()

            HStack(spacing: 8) {
                PulsingDot(color: Palette.working, size: 6)
                Text("Browsing · cyclerepair.example")
                    .font(KFont.ui(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(1)
                Spacer(minLength: 4)
                smallButton("Take over")
                smallButton("Full screen")
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .kCard(radius: 20)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pointer = true }
        }
    }

    private func smallButton(_ title: String) -> some View {
        Text(title)
            .font(KFont.ui(12.5, .medium, relativeTo: .caption))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Palette.ink.opacity(0.1), in: Capsule())
    }
}

struct BackgroundTaskCard: View {
    let title: String
    let progress: Double
    @State private var shown = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Background task", systemImage: "clock")
                    .font(KFont.ui(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkDim)
                Spacer()
                Text("keeps going if you leave").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            }
            Text(title).font(KFont.ui(15.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.1))
                    Capsule().fill(Palette.gold).frame(width: geometry.size.width * shown)
                }
            }
            .frame(height: 6)
        }
        .padding(13)
        .kCard(radius: 20)
        .onAppear { withAnimation(.easeOut(duration: 1.1).delay(0.25)) { shown = progress } }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

struct SourceCard: View {
    let site: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(site).font(KFont.ui(11.5, relativeTo: .caption2)).foregroundStyle(Palette.inkFaint)
                Text(title).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.ink)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xEFE6D6), Color(hex: 0xD9CDB8)], startPoint: .top, endPoint: .bottom))
                .frame(width: 46, height: 34)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .kCard(radius: 16)
    }
}

/// A drawn stand-in for a file's preview, until real files arrive from the desktop.
struct DocumentArt: View {
    let look: ChatDocument.Look

    var body: some View {
        ZStack {
            switch look {
            case .design:
                LinearGradient(colors: [Color(hex: 0x2E3A44), Color(hex: 0x1D252C)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(Palette.goldHi).frame(width: 96, height: 10)
                    Capsule().fill(Palette.cream.opacity(0.3)).frame(width: 150, height: 9)
                    Capsule().fill(Palette.cream.opacity(0.2)).frame(width: 116, height: 9)
                    Capsule().fill(Palette.goldHi.opacity(0.85)).frame(width: 64, height: 22).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(20)
            case .sheet:
                Color.white
                VStack(spacing: 7) {
                    Rectangle().fill(Color(hex: 0xD8E6D4)).frame(height: 16)
                    ForEach(0..<5, id: \.self) { _ in
                        Rectangle().fill(Palette.night.opacity(0.1)).frame(height: 12)
                    }
                }
                .padding(18)
            case .page:
                Palette.paper
                VStack(alignment: .leading, spacing: 9) {
                    Capsule().fill(Palette.night.opacity(0.4)).frame(width: 120, height: 10)
                    ForEach([0.95, 0.88, 0.92, 0.6, 0.85], id: \.self) { width in
                        Capsule().fill(Palette.night.opacity(0.14)).frame(height: 8).scaleEffect(x: width, anchor: .leading)
                    }
                }
                .padding(20)
            }
        }
    }
}

/// Files arrive as a fanned stack. Swipe the top card and it goes to the back; tap to open the viewer.
struct DocumentStack: View {
    let documents: [ChatDocument]
    let open: (Int) -> Void

    @State private var top = 0
    @State private var drag: CGSize = .zero

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                ForEach((0..<min(3, documents.count)).reversed(), id: \.self) { depth in
                    let index = (top + depth) % documents.count
                    DocumentArt(look: documents[index].look)
                        .frame(width: 236, height: 178)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 14, y: 9)
                        .rotationEffect(.degrees(depth == 0 ? Double(drag.width) / 22 : Double(depth) * 3.6))
                        .offset(x: depth == 0 ? drag.width : CGFloat(depth) * 11, y: depth == 0 ? drag.height * 0.3 : CGFloat(depth) * 3)
                        .zIndex(Double(3 - depth))
                }
            }
            .frame(width: 262, height: 196, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { open(top) }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        if abs(value.translation.width) > 70 {
                            Haptics.select()
                            withAnimation(Motion.bouncy) {
                                top = (top + 1) % documents.count
                                drag = .zero
                            }
                        } else {
                            withAnimation(Motion.bouncy) { drag = .zero }
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("\(documents[top].name), \(top + 1) of \(documents.count). Swipe for the next file")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(top) }

            Text("\(top + 1) of \(documents.count)")
                .font(KFont.ui(12.5, relativeTo: .caption))
                .foregroundStyle(Palette.inkFaint)
                .contentTransition(.numericText())
                .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }
}
