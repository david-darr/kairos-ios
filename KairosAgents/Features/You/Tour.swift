import SwiftUI
import UIKit

/// The short in-app tour. It floats above the real app in its own window and points at the
/// real controls, one at a time: the tab bar, holding it for Jump to, the gold circle, a bot's face,
/// Search and You. The positions follow the shell's own layout (BottomChrome and Home's header).
enum TourPresenter {
    private static var window: UIWindow?

    static var isShowing: Bool { window != nil }

    static func start(after delay: Double = 0) {
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            show()
        }
    }

    private static func show() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        let style = scene.windows.first(where: \.isKeyWindow)?.traitCollection.userInterfaceStyle ?? .dark
        let host = UIHostingController(rootView: TourOverlay(finish: { end() }))
        host.view.backgroundColor = .clear
        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .alert
        overlay.overrideUserInterfaceStyle = style
        overlay.backgroundColor = .clear
        overlay.rootViewController = host
        overlay.isHidden = false
        window = overlay
        UserDefaults.standard.set(true, forKey: "tourSeen")
    }

    static func end() {
        window?.isHidden = true
        window = nil
    }
}

nonisolated struct TourStop: Sendable {
    enum Target: Sendable { case none, bar, barHold, action, botFace, search, avatar }
    let target: Target
    let title: String
    let body: String
}

/// The dimmed screen with one lit hole and the card that explains it.
struct TourOverlay: View {
    var startStep = 0
    let finish: () -> Void
    @State private var step = 0
    @State private var holding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let stops: [TourStop] = [
        TourStop(target: .none, title: "A quick tour", body: "Six things worth knowing on your phone. Tap Next, or end it any time."),
        TourStop(target: .bar, title: "The tab bar", body: "Home, Make, Library and Desktop. It shrinks while you read and comes back when you scroll up or tap it."),
        TourStop(target: .barHold, title: "Hold it for Jump to", body: "Press and hold the bar to see every area. Drag one onto the bar to keep it there."),
        TourStop(target: .action, title: "The gold circle", body: "The main action for the tab you are on. On Home it starts a new chat; in Library it adds to the section you are in."),
        TourStop(target: .botFace, title: "A bot's face", body: "Tap a face to text that bot. In its chat, tap the face at the top for its inbox and settings."),
        TourStop(target: .search, title: "Search", body: "Find chats, bots, files, notes and settings, or run an action like call Kip."),
        TourStop(target: .avatar, title: "You", body: "Switch accounts and change any setting. Take this tour again from Help."),
    ]

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let stop = Self.stops[step]
            let local = spot(for: stop.target, size: proxy.size)
            let lit = local.map { $0.offsetBy(dx: insets.leading, dy: insets.top) }
            ZStack(alignment: .topLeading) {
                TourDim(spot: lit ?? CGRect(x: proxy.size.width / 2, y: proxy.size.height / 2, width: 0, height: 0),
                        corner: corner(for: stop.target))
                    .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { next() }
                    .accessibilityHidden(true)

                if let local {
                    RoundedRectangle(cornerRadius: corner(for: stop.target), style: .continuous)
                        .strokeBorder(Palette.gold, lineWidth: 2)
                        .frame(width: local.width, height: local.height)
                        .scaleEffect(holding && stop.target == .barHold ? 1.06 : 1)
                        .offset(x: local.minX, y: local.minY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    if stop.target == .barHold {
                        holdHint(at: local)
                    }
                }

                card(stop)
                    .frame(width: min(proxy.size.width - 32, 380))
                    .position(x: proxy.size.width / 2, y: cardY(for: local, size: proxy.size))
            }
            .animation(reduceMotion ? nil : Motion.sheet, value: step)
        }
        .onAppear {
            step = min(startStep, Self.stops.count - 1)
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { holding = true }
        }
    }

    // MARK: Card

    private func card(_ stop: TourStop) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(step + 1) of \(Self.stops.count)")
                    .font(KFont.label)
                    .tracking(1.2)
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
                Button("End tour") { finish() }
                    .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .frame(minHeight: 44)
            }
            Text(stop.title)
                .font(KFont.display(30))
                .foregroundStyle(Palette.ink)
            Text(stop.body)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.inkDim)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if step > 0 {
                    Button {
                        Haptics.select()
                        step -= 1
                    } label: {
                        Text("Back")
                            .font(KFont.ui(16, .medium))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Palette.ink.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
                Button { next() } label: {
                    Text(step == Self.stops.count - 1 ? "Done" : "Next")
                        .font(KFont.ui(16, .semibold))
                        .foregroundStyle(Palette.onGold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom), in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(Palette.surfaceSolid, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func holdHint(at rect: CGRect) -> some View {
        Circle()
            .fill(Palette.gold.opacity(0.35))
            .overlay(Circle().strokeBorder(Palette.gold, lineWidth: 2))
            .frame(width: 44, height: 44)
            .scaleEffect(holding ? 1.25 : 0.85)
            .opacity(holding ? 0.4 : 1)
            .position(x: rect.minX + 32, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func next() {
        Haptics.tap()
        if step == Self.stops.count - 1 {
            finish()
        } else {
            step += 1
        }
    }

    // MARK: Where the real controls are

    /// Rectangles in the safe-area space, matching BottomChrome and Home's TabHeader.
    private func spot(for target: TourStop.Target, size: CGSize) -> CGRect? {
        let barWidth: CGFloat = 4 * 52 + 3 * 2 + 12
        let barHeight: CGFloat = 56
        let bottom = size.height - 4
        switch target {
        case .none:
            return nil
        case .bar, .barHold:
            return CGRect(x: 16, y: bottom - barHeight, width: barWidth, height: barHeight).insetBy(dx: -5, dy: -5)
        case .action:
            return CGRect(x: size.width - 16 - 56, y: bottom - 56, width: 56, height: 56).insetBy(dx: -6, dy: -6)
        case .botFace:
            let column = (size.width - 32 - 24) / 4
            let top: CGFloat = 60 + 4 + 36 + 18 + 2
            return CGRect(x: 16 + column / 2 - 50, y: top - 6, width: 100, height: 100)
        case .search:
            return CGRect(x: size.width - 20 - 44 - 8 - 44, y: 4, width: 44, height: 44).insetBy(dx: -6, dy: -6)
        case .avatar:
            return CGRect(x: size.width - 20 - 44, y: 4, width: 44, height: 44).insetBy(dx: -6, dy: -6)
        }
    }

    private func corner(for target: TourStop.Target) -> CGFloat {
        switch target {
        case .bar, .barHold: 33
        case .none: 0
        default: 60
        }
    }

    private func cardY(for spot: CGRect?, size: CGSize) -> CGFloat {
        guard let spot else { return size.height * 0.45 }
        let estimate: CGFloat = 250
        if spot.midY > size.height / 2 {
            return max(estimate / 2 + 8, spot.minY - 24 - estimate / 2)
        }
        return min(size.height - estimate / 2 - 8, spot.maxY + 24 + estimate / 2)
    }
}

/// A full-screen dim with one rounded hole, animatable as the hole moves.
struct TourDim: Shape {
    var spot: CGRect
    var corner: CGFloat

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(spot.animatableData, corner) }
        set {
            spot.animatableData = newValue.first
            corner = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if spot.width > 0 {
            path.addRoundedRect(in: spot, cornerSize: CGSize(width: min(corner, spot.width / 2), height: min(corner, spot.height / 2)), style: .continuous)
        }
        return path
    }
}

/// The tour over the real shell, for its pictures.
struct TourDebugView: View {
    let step: Int

    var body: some View {
        ZStack {
            ShellView()
            TourOverlay(startStep: step, finish: {})
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
