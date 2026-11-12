import SwiftUI

/// A bot's round face: two eyes on its colour. Kip is cream with the gold point.
/// A team shows two of its members side by side on glass.
struct BotFace: View {
    let bot: Bot
    var size: CGFloat = 50
    var showStatus = false
    var blinks = false

    @State private var eyesShut = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if bot.members.isEmpty { single } else { team }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if showStatus { StatusDot(status: bot.status, size: max(11, size * 0.23)) }
        }
        .task(id: blinks) {
            guard blinks, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.4...5.6)))
                withAnimation(.easeIn(duration: 0.08)) { eyesShut = true }
                try? await Task.sleep(for: .milliseconds(130))
                withAnimation(.easeOut(duration: 0.14)) { eyesShut = false }
            }
        }
        .accessibilityHidden(true)
    }

    private var single: some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: max(0.5, size * 0.012))
            eyes(scale: 1)
            if bot.isKip {
                Circle()
                    .fill(Palette.goldHi)
                    .frame(width: size * 0.19, height: size * 0.19)
                    .overlay(Circle().strokeBorder(Palette.night.opacity(0.85), lineWidth: size * 0.028))
                    .offset(x: size * 0.31, y: -size * 0.31)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: size * 0.12, y: size * 0.07)
    }

    private var team: some View {
        ZStack {
            Circle().fill(Palette.surfaceRaised)
            Circle().strokeBorder(Palette.lineStrong, lineWidth: 1)
            ForEach(Array(SampleData.bots(bot.members).prefix(2).enumerated()), id: \.offset) { index, member in
                BotFace(bot: member, size: size * 0.5)
                    .offset(x: index == 0 ? -size * 0.15 : size * 0.15, y: index == 0 ? -size * 0.05 : size * 0.07)
            }
        }
    }

    private func eyes(scale: CGFloat) -> some View {
        HStack(spacing: size * 0.115) {
            ForEach(0..<2, id: \.self) { _ in
                Capsule()
                    .fill(Palette.night)
                    .frame(width: size * 0.105, height: size * 0.25)
                    .scaleEffect(x: 1, y: eyesShut ? 0.12 : 1)
            }
        }
        .offset(y: size * 0.02)
    }

    private var fill: AnyShapeStyle {
        if bot.isKip { return AnyShapeStyle(Palette.cream) }
        let base = Color(hex: bot.colorHex)
        return AnyShapeStyle(LinearGradient(colors: [base.mix(with: .white, by: 0.22), base.mix(with: .black, by: 0.12)], startPoint: .top, endPoint: .bottom))
    }
}

struct StatusDot: View {
    let status: BotStatus
    var size: CGFloat = 13

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Palette.ground, lineWidth: max(1.5, size * 0.16)))
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch status {
        case .online: Palette.success
        case .working: Palette.working
        case .needsYou: Palette.gold
        case .offline: Palette.inkFaint
        }
    }
}

/// The level bars under a name on the call screen and in the live pill.
struct LevelBars: View {
    var color: Color = Palette.ink
    var active = true
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let heights: [CGFloat] = [0.35, 0.6, 1, 0.6, 0.35]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 14 * heights[index] * (phase && active ? (index.isMultiple(of: 2) ? 1.25 : 0.55) : 1))
            }
        }
        .frame(height: 18)
        .onAppear {
            guard active, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { phase = true }
        }
        .accessibilityHidden(true)
    }
}
