import SwiftUI

/// A bot's own page: Inbox (needs you, working, done, its report) and Settings.
struct BotPanelView: View {
    enum Tab: String, CaseIterable { case inbox = "Inbox", settings = "Settings" }

    let bot: Bot
    @State var tab: Tab
    @Environment(\.dismiss) private var dismiss
    @State private var answered = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    BotFace(bot: bot, size: 140, blinks: true)
                    Text(bot.name).font(KFont.display(40)).foregroundStyle(Palette.ink)
                    Text("\(bot.role) · \(bot.model) · \(bot.approval)")
                        .font(KFont.ui(14, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)

                GlassSwitch(items: Tab.allCases, selection: $tab) { $0.rawValue }
                    .fixedSize()

                if tab == .inbox { inbox.transition(.opacity.combined(with: .move(edge: .leading))) }
                else { settings.transition(.opacity.combined(with: .move(edge: .trailing))) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                GlassIconButton(symbol: "chevron.down", label: "Back to the chat") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .background { Ground(glowAt: UnitPoint(x: 0.5, y: 0.12)) }
        .animation(Motion.snappy, value: tab)
    }

    private var inbox: some View {
        VStack(spacing: 10) {
            ForEach(Array(SampleData.inbox(for: bot).enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if item.state == .working { PulsingDot(color: Palette.working, size: 6) }
                        Text(label(item.state)).font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(color(item.state))
                    }
                    Text(item.text).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    if item.state == .needsYou {
                        if answered {
                            Label("Answered", systemImage: "checkmark.circle.fill")
                                .font(KFont.ui(14, .medium, relativeTo: .footnote))
                                .foregroundStyle(Palette.success)
                                .padding(.top, 4)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        } else {
                            HStack(spacing: 8) {
                                inboxButton("Not now", filled: false)
                                inboxButton("Approve", filled: true)
                            }
                            .padding(.top, 6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .kCard(radius: 20, raised: item.state == .needsYou)
                .arrives(index)
            }
            GroupRow(title: "\(bot.name)'s report", symbol: "chart.bar.doc.horizontal", last: true)
                .kCard(radius: 20)
                .arrives(3)
        }
        .animation(Motion.bouncy, value: answered)
    }

    private func inboxButton(_ title: String, filled: Bool) -> some View {
        Button {
            Haptics.success()
            answered = true
        } label: {
            Text(title)
                .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(filled ? Palette.onGold : Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(filled ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private var settings: some View {
        VStack(spacing: 0) {
            GroupRow(title: "Model", symbol: "cpu", value: bot.model)
            GroupRow(title: "Approval", symbol: "checkmark.shield", value: "Ask")
            GroupRow(title: "Voice", symbol: "waveform", value: bot.voice)
            GroupRow(title: "Routines", symbol: "clock.arrow.circlepath", value: "3")
            GroupRow(title: "Memory and skills", symbol: "brain")
            GroupRow(title: "Look and name", symbol: "paintbrush", last: true)
        }
        .kCard(radius: 20)
    }

    private func label(_ state: InboxItem.State) -> String {
        switch state {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .done: "Done"
        }
    }

    private func color(_ state: InboxItem.State) -> Color {
        switch state {
        case .needsYou: Palette.goldText
        case .working: Palette.working
        case .done: Palette.success
        }
    }
}
