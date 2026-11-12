import SwiftUI

struct StudioScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Text("Studio")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                MakeHeader(title: "Studio", backSymbol: "chevron.down", backLabel: "Close Studio", back: { dismiss() })
            }
            .kScreen()
    }
}

/// A channel's round avatar: two letters, its own hue, and the platform mark.
struct ChannelAvatar: View {
    let channel: StudioChannel
    var size: CGFloat = 40

    var body: some View {
        Text(channel.initials)
            .font(KFont.ui(size * 0.34, .semibold))
            .foregroundStyle(Palette.night)
            .frame(width: size, height: size)
            .background(channel.color, in: Circle())
            .overlay(Circle().strokeBorder(Palette.ground, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                Text(channel.platform.short)
                    .font(.system(size: max(8, size * 0.2), weight: .heavy))
                    .foregroundStyle(Palette.cream)
                    .padding(.horizontal, 3)
                    .frame(height: max(12, size * 0.3))
                    .background(Palette.night, in: Capsule())
                    .offset(x: 3, y: 2)
            }
            .opacity(channel.state == .archived ? 0.55 : 1)
            .accessibilityHidden(true)
    }
}
