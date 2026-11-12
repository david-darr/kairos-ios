import SwiftUI

/// You: accounts, every setting, the Tool Store, your added tabs, the look, and help.
struct YouView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private let rows: [(String, String)] = [
        ("Models and voice", "cpu"),
        ("Notifications and Reach me", "bell"),
        ("Channels", "bubble.left.and.bubble.right"),
        ("Permissions", "checkmark.shield"),
        ("Connections and Google", "link"),
        ("Tool Store", "bag"),
        ("Your tabs", "square.grid.2x2"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Y")
                        .font(KFont.ui(34, .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 92, height: 92)
                        .background(Palette.surface2, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.gold, lineWidth: 3))
                    Text("You").font(KFont.display(36)).foregroundStyle(Palette.ink)
                    Text("Switch account").font(KFont.ui(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.goldText)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Look")
                    GlassSwitch(items: AppLook.allCases, selection: Binding(get: { app.appearance }, set: { app.setAppearance($0) })) { $0.title }
                }

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        GroupRow(title: row.0, symbol: row.1, last: index == rows.count - 1)
                    }
                }
                .kCard(radius: 22)

                VStack(spacing: 0) {
                    Button {
                        dismiss()
                        app.replayOnboarding()
                    } label: {
                        GroupRow(title: "Replay the welcome", symbol: "play.circle", last: true)
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                }
                .kCard(radius: 22)

                Text("Kairos Agents 0.1 · sample data")
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }
}
