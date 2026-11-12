import SwiftUI

// The pieces a model chat is drawn from: lines, the live checklist, live work cards and the file stack.

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
    let steps: [StepLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(steps) { step in
                HStack(spacing: 10) {
                    if step.failed {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.danger)
                    } else if step.done {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.success)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
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
    var site = "cyclerepair.example"
    /// Take over and Full screen open the desktop's own pages.
    var onTakeOver: () -> Void = {}
    var onFullScreen: () -> Void = {}
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
                Text("Browsing · \(site)")
                    .font(KFont.ui(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(1)
                Spacer(minLength: 4)
                smallButton("Take over", action: onTakeOver)
                smallButton("Full screen", action: onFullScreen)
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

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(KFont.ui(12.5, .medium, relativeTo: .caption))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Palette.ink.opacity(0.1), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
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
