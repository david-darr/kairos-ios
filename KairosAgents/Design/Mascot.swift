import SwiftUI

nonisolated enum MascotShape: String, Hashable, Sendable { case round, squircle, tall }
nonisolated enum MascotAccessory: String, Hashable, Sendable { case none, laurel, spectacles, quill, rays, scarf }
enum MascotPose { case idle, thinking, needs, sleeping }

/// Kip, the Kairos mascot, drawn from the desktop app's own flat design
/// (jarvis-app `static/js/mascot.js`, in its 140 by 140 drawing space):
/// a flat body with the ring's opening bitten out of the upper right, the gold
/// point resting in the bite, and two pill eyes. Kairos itself is the ink round
/// body; every bot is a variant (one of the six pastels, a shape, one accessory).
/// The point, the bite and the eyes are never changed.
struct Mascot: View {
    var shape: MascotShape = .round
    /// nil is Kairos's own ink body (Kip). A value is one of the six bot pastels.
    var colorHex: UInt32? = nil
    var accessory: MascotAccessory = .none
    var pose: MascotPose = .idle
    var size: CGFloat = 72
    /// Live mascots breathe, blink and move. Lists use the still pose.
    var live = false
    /// The colour behind the mascot; it rings the point.
    var stage: Color = Palette.ground

    @State private var eyesShut = false
    @State private var breathing = false
    @State private var bobbing = false
    @State private var glance: CGSize = .zero
    @State private var orbit = 0.0
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bodyColor: Color { colorHex.map { Color(hex: $0) } ?? Palette.kipBody }
    private var eyeColor: Color { colorHex == nil ? Palette.kipEye : Color(hex: 0x3A2A20) }
    private let feet = UnitPoint(x: 0.5, y: 122.0 / 140.0)
    private let middle = UnitPoint(x: 0.5, y: 76.0 / 140.0)
    private let pointSpot = UnitPoint(x: 100.0 / 140.0, y: 36.0 / 140.0)

    var body: some View {
        let scale = size / 108
        ZStack {
            Path(ellipseIn: CGRect(x: 34, y: 124, width: 72, height: 10)).fill(Palette.mascotShadow)
            back
            ZStack {
                Self.bodyPath(shape).fill(bodyColor)
                neck
                face
                front
            }
            .scaleEffect(x: breathing ? 1.015 : 1, y: breathing ? 0.985 : 1, anchor: feet)
            .rotationEffect(.degrees(pose == .sleeping ? 5 : 0), anchor: feet)
            point
        }
        .frame(width: 140, height: 140)
        .scaleEffect(scale)
        .offset(y: -10 * scale)
        .frame(width: size, height: size)
        .task(id: live) { await move() }
        .accessibilityHidden(true)
    }

    // MARK: Body

    static func bodyPath(_ shape: MascotShape) -> Path {
        let whole: Path
        switch shape {
        case .round: whole = Path(ellipseIn: CGRect(x: 26, y: 32, width: 88, height: 88))
        case .squircle: whole = Path(roundedRect: CGRect(x: 27, y: 33, width: 86, height: 86), cornerRadius: 30)
        case .tall: whole = Path(roundedRect: CGRect(x: 33, y: 28, width: 74, height: 96), cornerRadius: 37)
        }
        return whole.subtracting(Path(ellipseIn: CGRect(x: 80, y: 16, width: 40, height: 40)))
    }

    // MARK: Face

    @ViewBuilder
    private var face: some View {
        if pose == .needs {
            Path { path in
                path.move(to: CGPoint(x: 48, y: 54)); path.addLine(to: CGPoint(x: 61, y: 52))
                path.move(to: CGPoint(x: 73, y: 52)); path.addLine(to: CGPoint(x: 86, y: 54))
            }
            .stroke(eyeColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            .offset(y: -4)
        }
        if pose == .sleeping {
            Path { path in
                path.move(to: CGPoint(x: 48, y: 78)); path.addLine(to: CGPoint(x: 62, y: 78))
                path.move(to: CGPoint(x: 72, y: 78)); path.addLine(to: CGPoint(x: 86, y: 78))
            }
            .stroke(eyeColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        } else {
            Path { path in
                path.addRoundedRect(in: CGRect(x: 49, y: 62, width: 12, height: 26), cornerSize: CGSize(width: 6, height: 6))
                path.addRoundedRect(in: CGRect(x: 73, y: 62, width: 12, height: 26), cornerSize: CGSize(width: 6, height: 6))
            }
            .fill(eyeColor)
            .scaleEffect(x: 1, y: eyesShut ? 0.08 : 1, anchor: UnitPoint(x: 0.5, y: 75.0 / 140.0))
            .offset(pose == .thinking ? CGSize(width: 4, height: -2) : glance)
        }
        if accessory == .spectacles {
            Path { path in
                path.addEllipse(in: CGRect(x: 44, y: 64, width: 22, height: 22))
                path.addEllipse(in: CGRect(x: 68, y: 64, width: 22, height: 22))
                path.move(to: CGPoint(x: 66, y: 73))
                path.addQuadCurve(to: CGPoint(x: 68, y: 73), control: CGPoint(x: 67, y: 70))
            }
            .stroke(Palette.goldText, lineWidth: 2.6)
        }
    }

    // MARK: The point

    private var point: some View {
        ZStack {
            if pose == .needs {
                Path(ellipseIn: CGRect(x: 90, y: 26, width: 20, height: 20))
                    .stroke(Palette.goldHi, lineWidth: 2)
                    .scaleEffect(pulse ? 2.4 : 1.6, anchor: pointSpot)
                    .opacity(pulse ? 0 : 0.6)
            }
            Path(ellipseIn: CGRect(x: 91, y: 27, width: 18, height: 18)).fill(Palette.gold)
            Path(ellipseIn: CGRect(x: 91, y: 27, width: 18, height: 18)).stroke(stage, lineWidth: 2.5)
        }
        .offset(x: pose == .sleeping ? -2 : 0, y: pose == .sleeping ? 10 : (bobbing ? -3 : 0))
        .scaleEffect(pose == .sleeping ? 0.75 : 1, anchor: pointSpot)
        .opacity(pose == .sleeping ? 0.5 : 1)
        .rotationEffect(.degrees(pose == .thinking ? 40 + orbit : 0), anchor: middle)
    }

    // MARK: Accessories

    @ViewBuilder
    private var back: some View {
        if accessory == .rays {
            Path { path in
                for step in 0..<5 {
                    let angle = Double(198 + step * 19) * .pi / 180
                    path.move(to: CGPoint(x: 70 + 52 * cos(angle), y: 76 + 52 * sin(angle)))
                    path.addLine(to: CGPoint(x: 70 + 62 * cos(angle), y: 76 + 62 * sin(angle)))
                }
            }
            .stroke(Palette.gold, style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        }
        if accessory == .quill {
            Self.quillVane.fill(Palette.goldHi)
            Self.quillVane.stroke(Palette.goldText, lineWidth: 1.2)
            Path { path in
                path.move(to: CGPoint(x: 31, y: 112))
                path.addCurve(to: CGPoint(x: 18, y: 46), control1: CGPoint(x: 24, y: 90), control2: CGPoint(x: 20, y: 66))
            }
            .stroke(Palette.inkDim, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    @ViewBuilder
    private var neck: some View {
        if accessory == .scarf {
            Self.scarf.fill(Color(hex: 0xD99A92))
            Self.scarf.stroke(Palette.ink.opacity(0.35), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var front: some View {
        if accessory == .laurel {
            Self.laurel.fill(Palette.goldHi)
            Self.laurel.stroke(Palette.goldText, lineWidth: 1)
        }
    }

    private static let quillVane: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 30, y: 108))
        path.addCurve(to: CGPoint(x: 18, y: 44), control1: CGPoint(x: 14, y: 92), control2: CGPoint(x: 10, y: 66))
        path.addCurve(to: CGPoint(x: 30, y: 108), control1: CGPoint(x: 28, y: 62), control2: CGPoint(x: 34, y: 86))
        path.closeSubpath()
        return path
    }()

    private static let scarf: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 34, y: 98))
        path.addQuadCurve(to: CGPoint(x: 106, y: 98), control: CGPoint(x: 70, y: 110))
        path.addLine(to: CGPoint(x: 104, y: 107))
        path.addQuadCurve(to: CGPoint(x: 36, y: 107), control: CGPoint(x: 70, y: 119))
        path.closeSubpath()
        path.move(to: CGPoint(x: 44, y: 104))
        path.addLine(to: CGPoint(x: 40, y: 124))
        path.addLine(to: CGPoint(x: 50, y: 124))
        path.addLine(to: CGPoint(x: 53, y: 107))
        path.closeSubpath()
        return path
    }()

    private static let laurel: Path = {
        var path = Path()
        for step in 0..<7 {
            let degrees = Double(200 + step * 12)
            let angle = degrees * .pi / 180
            let leaf = Path(ellipseIn: CGRect(x: -6, y: -3, width: 12, height: 6))
            let place = CGAffineTransform(translationX: 70 + 48 * cos(angle), y: 76 + 48 * sin(angle))
                .rotated(by: (degrees + 90) * .pi / 180)
            path.addPath(leaf.applying(place))
        }
        return path
    }()

    // MARK: Movement (the desktop's idle: breathe, blink, glance, and the point bobbing)

    private func move() async {
        guard live, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) { breathing = true }
        switch pose {
        case .idle:
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { bobbing = true }
        case .thinking:
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) { orbit = 360 }
        case .needs:
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        case .sleeping:
            return
        }
        var beat = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(pose == .needs ? 3.0 : 4.3))
            if Task.isCancelled { break }
            withAnimation(.easeIn(duration: 0.08)) { eyesShut = true }
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.easeOut(duration: 0.14)) { eyesShut = false }
            beat += 1
            if pose == .idle, beat.isMultiple(of: 2) {
                try? await Task.sleep(for: .seconds(0.9))
                withAnimation(.easeInOut(duration: 0.3)) { glance = CGSize(width: 4, height: -1) }
                try? await Task.sleep(for: .seconds(1.3))
                withAnimation(.easeInOut(duration: 0.3)) { glance = CGSize(width: -2, height: 0) }
                try? await Task.sleep(for: .seconds(0.9))
                withAnimation(.easeInOut(duration: 0.3)) { glance = .zero }
            }
        }
    }
}

/// A bot's face wherever the app shows one. A team shows two of its members together.
struct BotFace: View {
    let bot: Bot
    var size: CGFloat = 56
    var showStatus = false
    /// Live faces breathe, blink and show what the bot is doing.
    var blinks = false
    var stage: Color = Palette.ground

    var body: some View {
        Group {
            if bot.members.isEmpty {
                Mascot(
                    shape: bot.shape,
                    colorHex: bot.isKip ? nil : bot.colorHex,
                    accessory: bot.accessory,
                    pose: blinks ? pose : .idle,
                    size: size,
                    live: blinks,
                    stage: stage
                )
            } else {
                ZStack {
                    Circle().fill(Palette.surfaceRaised)
                    Circle().strokeBorder(Palette.lineStrong, lineWidth: 1)
                    ForEach(Array(SampleData.bots(bot.members).prefix(2).enumerated()), id: \.offset) { index, member in
                        BotFace(bot: member, size: size * 0.56)
                            .offset(x: index == 0 ? -size * 0.14 : size * 0.15, y: index == 0 ? -size * 0.06 : size * 0.08)
                    }
                }
                .frame(width: size * 0.84, height: size * 0.84)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if showStatus {
                StatusDot(status: bot.status, size: max(11, size * 0.19))
                    .offset(x: size * 0.3, y: size * 0.31)
            }
        }
        .accessibilityHidden(true)
    }

    private var pose: MascotPose {
        switch bot.status {
        case .online: .idle
        case .working: .thinking
        case .needsYou: .needs
        case .offline: .sleeping
        }
    }
}
