import SwiftUI

// Small pieces shared by every Make screen: toasts, headers, pills, tiles and the swipe-up confirm.

/// A short message for screens that cover the tab bar (Studio, the editor, a design).
@Observable
final class MakeToast {
    var text: String?
    private var task: Task<Void, Never>?

    func say(_ text: String) {
        task?.cancel()
        withAnimation(Motion.bouncy) { self.text = text }
        task = Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { withAnimation(Motion.gentle) { self.text = nil } }
        }
    }
}

private struct MakeToastHost: ViewModifier {
    let toast: MakeToast

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let text = toast.text {
                Text(text)
                    .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .kGlass(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
                    .onTapGesture { withAnimation(Motion.gentle) { toast.text = nil } }
            }
        }
    }
}

extension View {
    func makeToasts(_ toast: MakeToast) -> some View { modifier(MakeToastHost(toast: toast)) }
}

/// The header of a pushed Make screen: back on the left, a title in the middle, buttons on the right.
struct MakeHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var backSymbol = "chevron.left"
    var backLabel = "Back"
    let back: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            GlassIconButton(symbol: backSymbol, label: backLabel, action: back)
            VStack(spacing: 1) {
                Text(title)
                    .font(KFont.ui(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(KFont.ui(12.5, relativeTo: .caption))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) { trailing }
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background { HeaderFade() }
    }
}

extension MakeHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, backSymbol: String = "chevron.left", backLabel: String = "Back", back: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, backSymbol: backSymbol, backLabel: backLabel, back: back) { EmptyView() }
    }
}

/// A coloured state word: Live, Paused, Approved, Waiting for your OK ...
nonisolated enum PillTone: Hashable, Sendable { case ok, warn, error, muted, working, gold }

struct StatePill: View {
    typealias Tone = PillTone
    let text: String
    var tone: Tone = .muted

    var body: some View {
        Text(text)
            .font(KFont.ui(12, .medium, relativeTo: .caption))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var color: Color {
        switch tone {
        case .ok: Palette.success
        case .warn: Palette.goldText
        case .error: Palette.danger
        case .muted: Palette.inkDim
        case .working: Palette.working
        case .gold: Palette.goldText
        }
    }
}

/// A dashboard tile: a small heading, its content, and an optional link at the foot.
struct MakeTile<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var link: String? = nil
    var linkAction: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.goldText)
                }
                Text(title).font(KFont.ui(15.5, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
            }
            content
            if let link, let linkAction {
                Button {
                    Haptics.tap()
                    linkAction()
                } label: {
                    HStack(spacing: 4) {
                        Text(link)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(KFont.ui(14, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(radius: 22)
    }
}

/// One number with its label, for stat grids.
struct StatBox: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(KFont.ui(20, .semibold, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Text(label).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A compact capsule button. Filled is gold (the main choice); otherwise a quiet ink wash.
struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var filled = false
    var danger = false
    var expand = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).lineLimit(1)
            }
            .font(KFont.ui(14.5, .semibold, relativeTo: .subheadline))
            .foregroundStyle(filled ? Palette.onGold : (danger ? Palette.danger : Palette.ink))
            .padding(.horizontal, 14)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: 44)
            .background(filled ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// A labelled text box for sheets.
struct MakeField: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    var limit: Int? = nil
    var lines: ClosedRange<Int> = 1...1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                Spacer()
                if let limit {
                    Text("\(text.count)/\(limit)")
                        .font(KFont.ui(12, relativeTo: .caption))
                        .foregroundStyle(text.count > limit ? Palette.danger : Palette.inkFaint)
                        .contentTransition(.numericText())
                }
            }
            TextField(prompt, text: $text, axis: .vertical)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .lineLimit(lines)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .kCard(radius: 16, raised: true)
                .onChange(of: text) {
                    if let limit, text.count > limit { text = String(text.prefix(limit)) }
                }
        }
    }
}

/// A row with a switch, in the gold tint.
struct MakeToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var last = false

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                if let detail { Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint) }
            }
        }
        .tint(Palette.gold)
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { if !last { Palette.line.frame(height: 1).padding(.leading, 16) } }
    }
}

/// A row that picks one of a few words (Aspect, Frame rate ...) by tapping through them, or from a menu.
struct MakeChoiceRow: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    var last = false

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    Haptics.select()
                    selection = option
                } label: {
                    if option == selection { Label(option, systemImage: "checkmark") } else { Text(option) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(selection).font(KFont.ui(15)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { if !last { Palette.line.frame(height: 1).padding(.leading, 16) } }
        }
        .accessibilityLabel("\(title): \(selection)")
    }
}

/// The "Swipe up to buy" pattern, for risky actions: approve a post, turn on hands-off posting.
/// Drag the gold knob to the top to confirm. VoiceOver gets a plain Confirm action.
struct SwipeUpConfirm: View {
    let title: String
    let detail: String
    var points: [String] = []
    var confirmLabel = "Swipe up to confirm"
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lift: CGFloat = 0
    @State private var done = false
    private let track: CGFloat = 176
    private let knob: CGFloat = 64

    var body: some View {
        FittedSheet(estimate: 560) {
            VStack(spacing: 16) {
                Text(title)
                    .font(KFont.ui(21, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 34)
                Text(detail)
                    .font(KFont.ui(15.5))
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !points.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(points, id: \.self) { point in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.goldText)
                                Text(point).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kCard(radius: 18)
                }

                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Palette.ink.opacity(0.08))
                        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold))
                        Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold)).opacity(0.5)
                    }
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 18)
                    .opacity(1 - Double(lift / (track - knob)))
                    Circle()
                        .fill(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                        .overlay(
                            Image(systemName: done ? "checkmark" : "arrow.up")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Palette.onGold)
                                .contentTransition(.symbolEffect(.replace))
                        )
                        .frame(width: knob - 8, height: knob - 8)
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                        .padding(4)
                        .offset(y: -lift)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard !done else { return }
                                    lift = min(max(0, -value.translation.height), track - knob)
                                }
                                .onEnded { _ in
                                    guard !done else { return }
                                    if lift > (track - knob) * 0.82 { confirm() } else { withAnimation(Motion.bouncy) { lift = 0 } }
                                }
                        )
                }
                .frame(width: knob, height: track)
                .accessibilityElement()
                .accessibilityLabel(confirmLabel)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { confirm() }

                Text(done ? "Done" : confirmLabel)
                    .font(KFont.ui(14, .medium, relativeTo: .footnote))
                    .foregroundStyle(done ? Palette.success : Palette.inkFaint)
                    .contentTransition(.opacity)

                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
    }

    private func confirm() {
        Haptics.success()
        withAnimation(Motion.snappy) {
            lift = track - knob
            done = true
        }
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            onConfirm()
            dismiss()
        }
    }
}

/// A small label in a sheet title area, leaving room under the grab bar.
struct SheetTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(KFont.ui(20, .semibold, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

/// A plain sentence for an empty list.
struct EmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(KFont.ui(14.5, relativeTo: .subheadline))
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
