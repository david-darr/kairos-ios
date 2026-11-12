import SwiftUI

/// Round, squircle and tall are the desktop's shapes. Dome, wide, hex, scallop and ghost are new
/// on the phone (David, 2026-11-12); the desktop cannot store them yet.
nonisolated enum MascotShape: String, Hashable, Sendable, CaseIterable {
    case round, squircle, tall, dome, wide, hex, scallop, ghost
}
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
                bodyFill
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

    /// Kip is flat. A bot is cel shaded: one hard shadow along the lower right and one highlight.
    @ViewBuilder
    private var bodyFill: some View {
        let body = Self.bodyPath(shape)
        if let colorHex {
            body.fill(Palette.celShade(colorHex))
            Self.shapePath(shape).offsetBy(dx: -6, dy: -7).intersection(body).fill(Color(hex: colorHex))
            Self.highlight(shape).intersection(body).fill(Color.white.opacity(0.55))
        } else {
            body.fill(bodyColor)
        }
    }

    /// The whole shape, before the bite.
    static func shapePath(_ shape: MascotShape) -> Path {
        switch shape {
        case .round:
            return Path(ellipseIn: CGRect(x: 26, y: 32, width: 88, height: 88))
        case .squircle:
            return Path(roundedRect: CGRect(x: 27, y: 33, width: 86, height: 86), cornerRadius: 30)
        case .tall:
            return Path(roundedRect: CGRect(x: 33, y: 28, width: 74, height: 96), cornerRadius: 37)
        case .dome:
            let top = Path(ellipseIn: CGRect(x: 28, y: 32, width: 84, height: 84))
            let base = Path(
                roundedRect: CGRect(x: 28, y: 74, width: 84, height: 46),
                cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: 14, bottomTrailing: 14, topTrailing: 0)
            )
            return top.union(base)
        case .wide:
            return Path(roundedRect: CGRect(x: 16, y: 44, width: 108, height: 76), cornerRadius: 38)
        case .hex:
            let corners = [
                CGPoint(x: 70, y: 28), CGPoint(x: 111.6, y: 52), CGPoint(x: 111.6, y: 100),
                CGPoint(x: 70, y: 124), CGPoint(x: 28.4, y: 100), CGPoint(x: 28.4, y: 52),
            ]
            var path = Path()
            path.move(to: CGPoint(x: 49.2, y: 40))
            for index in corners.indices {
                path.addArc(tangent1End: corners[index], tangent2End: corners[(index + 1) % corners.count], radius: 10)
            }
            path.closeSubpath()
            return path
        case .scallop:
            var path = Path(ellipseIn: CGRect(x: 36, y: 42, width: 68, height: 68))
            for step in 0..<8 {
                let angle = (22.5 + Double(step) * 45) * .pi / 180
                let centre = CGPoint(x: 70 + 32 * cos(angle), y: 76 + 32 * sin(angle))
                path = path.union(Path(ellipseIn: CGRect(x: centre.x - 15, y: centre.y - 15, width: 30, height: 30)))
            }
            return path
        case .ghost:
            let top = Path(ellipseIn: CGRect(x: 28, y: 32, width: 84, height: 84))
            var hem = Path()
            hem.move(to: CGPoint(x: 28, y: 74))
            hem.addLine(to: CGPoint(x: 112, y: 74))
            hem.addLine(to: CGPoint(x: 112, y: 110))
            hem.addQuadCurve(to: CGPoint(x: 84, y: 110), control: CGPoint(x: 98, y: 128))
            hem.addQuadCurve(to: CGPoint(x: 56, y: 110), control: CGPoint(x: 70, y: 128))
            hem.addQuadCurve(to: CGPoint(x: 28, y: 110), control: CGPoint(x: 42, y: 128))
            hem.closeSubpath()
            return top.union(hem)
        }
    }

    /// The shape with the ring's opening bitten out of the upper right.
    static func bodyPath(_ shape: MascotShape) -> Path {
        shapePath(shape).subtracting(Path(ellipseIn: CGRect(x: 80, y: 16, width: 40, height: 40)))
    }

    /// The one hard highlight, upper left.
    static func highlight(_ shape: MascotShape) -> Path {
        let spot: CGPoint
        switch shape {
        case .round: spot = CGPoint(x: 53, y: 52)
        case .squircle: spot = CGPoint(x: 51, y: 50)
        case .tall: spot = CGPoint(x: 52, y: 46)
        case .dome: spot = CGPoint(x: 53, y: 50)
        case .wide: spot = CGPoint(x: 43, y: 60)
        case .hex: spot = CGPoint(x: 52, y: 52)
        case .scallop: spot = CGPoint(x: 52, y: 51)
        case .ghost: spot = CGPoint(x: 53, y: 50)
        }
        let pill = Path(roundedRect: CGRect(x: -11, y: -4.5, width: 22, height: 9), cornerRadius: 4.5)
        return pill.applying(CGAffineTransform(translationX: spot.x, y: spot.y).rotated(by: -24 * .pi / 180))
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
            .stroke(Palette.goldText, lineWidth: 3.2)
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
            if colorHex == nil {
                Path(ellipseIn: CGRect(x: 91, y: 27, width: 18, height: 18)).fill(Palette.gold)
            } else {
                Path(ellipseIn: CGRect(x: 91, y: 27, width: 18, height: 18)).fill(Color(hex: 0xB8842F))
                Path(ellipseIn: CGRect(x: 91.2, y: 27.2, width: 14.4, height: 14.4)).fill(Color(hex: 0xEBC06A))
            }
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
            .stroke(Palette.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        if accessory == .quill {
            Self.quillVane.fill(Palette.goldHi)
            Self.quillVane.stroke(Palette.goldDeep, lineWidth: 2)
            Path { path in
                path.move(to: CGPoint(x: 31, y: 112))
                path.addCurve(to: CGPoint(x: 18, y: 46), control1: CGPoint(x: 24, y: 90), control2: CGPoint(x: 20, y: 66))
            }
            .stroke(Palette.inkDim, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
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
