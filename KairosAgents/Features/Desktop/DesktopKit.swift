import SwiftUI

// MARK: - Routes inside the Desktop area

/// Every screen inside the Desktop area. Desktop screens open in their own workspace
/// (a full-screen stack over the tab, like the bot panel), so the tab bar never covers a composer.
nonisolated enum DesktopRoute: Hashable, Sendable {
    case forgeHome
    case forgeProjects
    case project(String)
    case session(String)
    case changes(String)
    case diff(session: String, path: String)
    case explorer(String)
    case file(session: String, path: String)
    case terminal(String)
    case preview(String)
    case repo(String)
    case computer
    case browse
    case localModels
    case pcFiles(String)
}

/// The screen for one desktop route.
struct DesktopRouteView: View {
    let route: DesktopRoute

    var body: some View {
        switch route {
        case .forgeHome: ForgeHomeScreen()
        case .forgeProjects: ForgeProjectsScreen()
        case .project(let id): ForgeProjectScreen(projectID: id)
        case .session(let id): ForgeSessionScreen(sessionID: id)
        case .changes(let id): ForgeChangesScreen(sessionID: id)
        case .diff(let session, let path): ForgeDiffScreen(sessionID: session, path: path)
        case .explorer(let id): ForgeExplorerScreen(sessionID: id)
        case .file(let session, let path): ForgeFileScreen(sessionID: session, path: path)
        case .terminal(let id): ForgeTerminalScreen(sessionID: id)
        case .preview(let id): ForgePreviewScreen(sessionID: id)
        case .repo(let id): ForgeRepoScreen(projectID: id)
        case .computer: ComputerScreen()
        case .browse: BrowseScreen()
        case .localModels: LocalModelsScreen()
        case .pcFiles(let path): PCFilesScreen(path: path)
        }
    }
}

extension View {
    /// Lets `NavigationLink(value: DesktopRoute...)` work in any stack this is attached to.
    func desktopDestinations() -> some View {
        navigationDestination(for: DesktopRoute.self) { route in
            DesktopRouteView(route: route)
        }
    }
}

/// A full-screen stack of desktop screens. Back on its first screen closes it.
struct DesktopWorkspace: View {
    let start: DesktopRoute
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            DesktopRouteView(route: start)
                .desktopDestinations()
        }
    }
}

/// Opens a desktop workspace from anywhere in the area.
@Observable
final class DesktopNav {
    static let shared = DesktopNav()
    var open: DesktopOpen?
}

nonisolated struct DesktopOpen: Identifiable, Hashable, Sendable {
    let id = UUID()
    var route: DesktopRoute
}

// MARK: - Header for pushed screens

/// The top of a pushed desktop screen: back, a title (and a line under it), then round buttons.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var backLabel = "Back"
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 10) {
            GlassIconButton(symbol: "chevron.left", label: backLabel) { dismiss() }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(KFont.ui(18, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background { HeaderFade() }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, backLabel: String = "Back") {
        self.title = title
        self.subtitle = subtitle
        self.backLabel = backLabel
        self.trailing = EmptyView()
    }
}

// MARK: - Small shared pieces

/// "+412 -36" in green and red.
struct DiffCount: View {
    let added: Int
    let removed: Int
    var size: CGFloat = 13.5

    var body: some View {
        HStack(spacing: 5) {
            Text("+\(added)").foregroundStyle(Palette.success)
            Text("-\(removed)").foregroundStyle(Palette.danger)
        }
        .font(KFont.ui(size, .medium, relativeTo: .footnote))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(added) lines added, \(removed) removed")
    }
}

/// A square icon tile like the one in `EntryRow`.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 46
    var tint: Color = Palette.goldText

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.39, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: size * 0.33, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.33, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A row button inside a card: icon, title, detail, chevron. Use inside `VStack(spacing: 0)` with `.kCard()`.
struct CardRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var tint: Color = Palette.goldText
    var last = false
    var chevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                if let detail {
                    Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 54) }
        }
    }
}

/// A small title over a section of content, with an optional action on the right.
struct SectionTitle: View {
    let text: String
    var action: String? = nil
    var perform: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(KFont.ui(20, .semibold, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
            Spacer()
            if let action, let perform {
                Button(action: perform) {
                    Text(action)
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

/// A pill-shaped secondary button with an icon.
struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Palette.ink
    var filled = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(KFont.ui(15, .medium, relativeTo: .subheadline)).lineLimit(1)
            }
            .foregroundStyle(filled ? Palette.onGold : tint)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(filled ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// A plain line of explanation for a state the sample cannot show for real.
struct NoteLine: View {
    let text: String
    var symbol = "info.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
            Text(text).font(KFont.ui(14, relativeTo: .footnote))
        }
        .foregroundStyle(Palette.inkFaint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An empty state inside a screen: an icon, a title, one line and an optional action.
struct EmptyNote: View {
    let symbol: String
    let title: String
    let text: String
    var action: String? = nil
    var perform: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 64, height: 64)
                .background(Palette.surface, in: Circle())
            Text(title).font(KFont.ui(18, .semibold, relativeTo: .headline)).foregroundStyle(Palette.ink)
            Text(text).font(KFont.ui(15, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim).multilineTextAlignment(.center)
            if let action, let perform {
                PillButton(title: action, symbol: nil, action: perform).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }
}

// MARK: - Swipe up to confirm

/// For risky actions (full access, discard, merge): drag the gold knob up to confirm.
/// VoiceOver users get the same action as a plain button.
struct SwipeUpConfirm: View {
    let title: String
    var danger = false
    let onConfirm: () -> Void

    @State private var lift: CGFloat = 0
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let track: CGFloat = 150
    private let knob: CGFloat = 62

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Palette.ink.opacity(0.08))
                    .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.inkFaint.opacity(0.4 + Double(2 - index) * 0.25))
                    }
                }
                .padding(.bottom, knob + 18)
                .opacity(1 - Double(lift / track))
                Image(systemName: done ? "checkmark" : "arrow.up")
                    .font(.system(size: 22, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Palette.onGold)
                    .frame(width: knob, height: knob)
                    .background(
                        LinearGradient(colors: danger ? [Palette.danger, Palette.danger.opacity(0.8)] : [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom),
                        in: Circle()
                    )
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                    .padding(5)
                    .offset(y: -lift)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !done else { return }
                                lift = min(max(0, -value.translation.height), track - knob - 10)
                            }
                            .onEnded { _ in
                                guard !done else { return }
                                if lift > (track - knob - 10) * 0.8 {
                                    done = true
                                    Haptics.success()
                                    withAnimation(Motion.snappy) { lift = track - knob - 10 }
                                    Task {
                                        try? await Task.sleep(for: .seconds(0.35))
                                        onConfirm()
                                    }
                                } else {
                                    withAnimation(reduceMotion ? nil : Motion.bouncy) { lift = 0 }
                                }
                            }
                    )
            }
            .frame(width: knob + 10, height: track)
            Text(done ? "Done" : title)
                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onConfirm() }
    }
}

// MARK: - Code text

/// Monospaced text for code, paths and terminal output.
enum CodeFont {
    static func mono(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
