import SwiftUI

// Shared pieces for the Calendar, Mail and Tasks sections of Library.
// Everything here is built from the design system; nothing restyles around it.

// MARK: - Sheet title

/// The title row at the top of a planner sheet: optional buttons left and right, title centred.
/// Leaves room under the grab bar.
struct PlannerSheetTitle<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(title)
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 56)
            HStack {
                leading
                Spacer()
                trailing
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

extension PlannerSheetTitle where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.leading = EmptyView()
        self.trailing = EmptyView()
    }
}

extension PlannerSheetTitle where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.leading = EmptyView()
        self.trailing = trailing()
    }
}

/// A small round button for inside content and sheets (not chrome, so no glass).
struct PlannerRoundButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 44
    var tint: Color = Palette.ink
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Palette.ink.opacity(0.09), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

// MARK: - Buttons

enum PlannerPillStyle { case gold, quiet, danger, outline }

/// A compact capsule button for actions inside a card ("Approve", "Not now", "Run now").
struct PlannerPill: View {
    let title: String
    var symbol: String? = nil
    var style: PlannerPillStyle = .quiet
    var expand = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(KFont.ui(15, .semibold, relativeTo: .subheadline)).lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: 44)
            .background { background }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.96))
    }

    private var foreground: Color {
        switch style {
        case .gold: Palette.onGold
        case .quiet: Palette.ink
        case .danger: Palette.danger
        case .outline: Palette.ink
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .gold:
            Capsule().fill(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
        case .quiet:
            Capsule().fill(Palette.ink.opacity(0.1))
        case .danger:
            Capsule().fill(Palette.danger.opacity(0.12))
        case .outline:
            Capsule().strokeBorder(Palette.lineStrong, lineWidth: 1)
        }
    }
}

// MARK: - Fields

/// A labelled text field on a quiet card.
struct PlannerTextField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var multiline = false
    var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)
            Group {
                if multiline {
                    TextField(label, text: $text, prompt: prompt, axis: .vertical)
                        .lineLimit(3...8)
                } else {
                    TextField(label, text: $text, prompt: prompt)
                }
            }
            .font(KFont.ui(16))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .kCard(radius: 16)
            .overlay {
                if error != nil {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.danger, lineWidth: 1.5)
                }
            }
            if let error {
                Text(error)
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.danger)
                    .transition(.opacity)
            }
        }
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(Palette.inkFaint)
    }
}

/// One row with a title, an optional line under it and a gold switch.
struct PlannerToggleRow: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    @Binding var isOn: Bool
    var last = false

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { value in
            Haptics.select()
            withAnimation(Motion.snappy) { isOn = value }
        })) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    if let detail {
                        Text(detail)
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(Palette.gold)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, symbol == nil ? 16 : 54) }
        }
    }
}

/// A row that opens a menu of choices, showing the current one on the right.
struct PlannerMenuRow<Value: Hashable>: View {
    let title: String
    var symbol: String? = nil
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var last = false

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { selection = option }
                } label: {
                    if option == selection {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 26)
                }
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(label(selection))
                    .font(KFont.ui(15))
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, symbol == nil ? 16 : 54) }
        }
        .accessibilityLabel("\(title): \(label(selection))")
    }
}

// MARK: - Small displays

enum PlannerTone: Hashable {
    case gold, success, danger, working, muted

    var color: Color {
        switch self {
        case .gold: Palette.goldText
        case .success: Palette.success
        case .danger: Palette.danger
        case .working: Palette.working
        case .muted: Palette.inkFaint
        }
    }
}

/// A small coloured pill for a state: "Waiting for you", "Succeeded", "Asks first".
struct TonePill: View {
    let text: String
    var tone: PlannerTone = .muted
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text).font(KFont.ui(12.5, .medium, relativeTo: .caption)).lineLimit(1)
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 9)
        .frame(minHeight: 24)
        .background(tone.color.opacity(0.13), in: Capsule())
    }
}

/// A number with a small label under it.
struct PlannerStat: View {
    let value: String
    let label: String
    var tone: PlannerTone? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(KFont.ui(26, .semibold, relativeTo: .title2))
                .foregroundStyle(tone?.color ?? Palette.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(radius: 18)
    }
}

/// A section heading inside a planner section, with an optional text link on the right.
struct PlannerHeading: View {
    let title: String
    var link: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(KFont.ui(19, .semibold, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
            Spacer()
            if let link, let action {
                Button {
                    Haptics.tap()
                    action()
                } label: {
                    Text(link)
                        .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.goldText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

/// The empty state: Kip resting, a title, one line and an optional action.
struct PlannerEmpty: View {
    let title: String
    let hint: String
    var pose: MascotPose = .sleeping
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Mascot(pose: pose, size: 64)
                .padding(.bottom, 4)
            Text(title)
                .font(KFont.ui(17, .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(hint)
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                PlannerPill(title: actionTitle, style: .quiet, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .kCard(radius: 22)
    }
}

// MARK: - Swipe up to confirm

/// The "swipe up to send" control for risky actions (send an email, run straight away, approve).
/// Drag the gold knob up past the line to confirm. VoiceOver gets a plain action.
struct SwipeUpToConfirm: View {
    let title: String
    var doneTitle: String = "Done"
    var symbol: String = "arrow.up"
    let action: () -> Void

    @State private var lift: CGFloat = 0
    @State private var done = false
    @State private var nudge = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let travel: CGFloat = 86

    var body: some View {
        let progress = min(1, max(0, -lift / travel))
        ZStack {
            Capsule()
                .fill(Palette.surfaceRaised)
                .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
            Capsule()
                .fill(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                .opacity(done ? 1 : progress * 0.9)
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    Image(systemName: done ? "checkmark" : symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .contentTransition(.symbolEffect(.replace))
                        .offset(y: nudge && !done && !reduceMotion ? -3 : 0)
                }
                .frame(width: 48, height: 48)
                Text(done ? doneTitle : title)
                    .font(KFont.ui(16.5, .semibold))
                    .foregroundStyle(done || progress > 0.55 ? Palette.onGold : Palette.ink)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
                if !done {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(progress > 0.55 ? Palette.onGold : Palette.inkFaint)
                        .padding(.trailing, 20)
                }
            }
            .padding(.leading, 6)
        }
        .frame(height: 60)
        .offset(y: done ? 0 : lift)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard !done else { return }
                    let previous = lift
                    lift = max(-travel - 14, min(0, value.translation.height))
                    if previous > -travel && lift <= -travel { Haptics.select() }
                }
                .onEnded { _ in
                    guard !done else { return }
                    if lift <= -travel {
                        confirm()
                    } else {
                        withAnimation(Motion.bouncy) { lift = 0 }
                    }
                }
        )
        .padding(.top, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(done ? doneTitle : title)
        .accessibilityHint(done ? "" : "Swipe up with one finger, or use the action")
        .accessibilityAction(named: title) { confirm() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { nudge = true }
        }
    }

    private func confirm() {
        Haptics.success()
        withAnimation(Motion.bouncy) {
            done = true
            lift = 0
        }
        action()
    }
}

// MARK: - A short notice inside a sheet

/// The tab bar's toast cannot be seen under a sheet, so sheets show their own short glass notice.
struct PlannerNoticeModifier: ViewModifier {
    @Binding var text: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let text {
                Text(text)
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .kGlass(Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation(Motion.snappy) { self.text = nil }
                    }
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(Motion.snappy, value: text)
    }
}

extension View {
    /// Show `text` as a short glass notice at the bottom of a sheet, then clear it.
    func plannerNotice(_ text: Binding<String?>) -> some View {
        modifier(PlannerNoticeModifier(text: text))
    }
}

// MARK: - Debug host

/// Opens the real Library tab on one planner section, in a named state, for the build's pictures.
/// The section reads `router.debugScreen` when it appears and opens the matching sheet or view.
struct PlannerDebugHost: View {
    let section: LibrarySection
    let state: String
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                LibraryView()
            } else {
                Color.clear.kScreen()
            }
        }
        .onAppear {
            chrome.held = true
            router.librarySection = section
            router.debugScreen = state
            ready = true
        }
    }
}
