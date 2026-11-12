import SwiftUI

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
