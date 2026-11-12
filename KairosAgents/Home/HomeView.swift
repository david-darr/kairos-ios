import SwiftUI

/// Home feels like Messages: a slim glance row, pinned bots as big round faces,
/// then one list of every conversation. A bot waiting on you is an unread conversation.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                glanceRow.arrives(0)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(SampleData.pinned.enumerated()), id: \.element.id) { index, bot in
                        Button {
                            Haptics.tap()
                            router.push(.bot(bot.id), on: .home)
                        } label: {
                            VStack(spacing: 7) {
                                BotFace(bot: bot, size: 82, showStatus: true, blinks: true)
                                Text(bot.name)
                                    .font(KFont.ui(13.5, relativeTo: .footnote))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PressStyle(scale: 0.92))
                        .accessibilityLabel("\(bot.name), \(statusWord(bot.status))")
                        .arrives(index + 1)
                    }
                }
                .padding(.top, 2)

                LazyVStack(spacing: 0) {
                    ForEach(Array(SampleData.conversations.enumerated()), id: \.element.id) { index, conversation in
                        Button {
                            router.open(conversation)
                        } label: {
                            ConversationRow(conversation: conversation)
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .arrives(index + 4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        .shrinksBar(chrome)
        .safeAreaInset(edge: .top, spacing: 0) {
            TabHeader(title: "Home") {
                GlassIconButton(symbol: "magnifyingglass", label: "Search") { router.sheet = .search }
                Button { router.sheet = .you } label: {
                    Text("Y")
                        .font(KFont.ui(16, .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .background(Palette.surface2, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.gold, lineWidth: 2))
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .accessibilityLabel("You, settings and accounts")
            }
        }
        .kScreen()
    }

    private var glanceRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(SampleData.usage, id: \.provider) { item in
                        HStack(spacing: 6) {
                            UsageRing(percent: item.percent)
                            Text(item.provider).foregroundStyle(Palette.ink)
                            Text("\(item.percent)%").foregroundStyle(Palette.inkFaint)
                        }
                    }
                }
                .glancePill()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Model usage this week")

                HStack(spacing: 7) {
                    Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.goldText)
                    Text(SampleData.nextEvent).foregroundStyle(Palette.ink)
                }
                .glancePill()
            }
            .font(KFont.ui(13.5, relativeTo: .footnote))
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func statusWord(_ status: BotStatus) -> String {
        switch status {
        case .online: "ready"
        case .working: "working"
        case .needsYou: "waiting for you"
        case .offline: "asleep"
        }
    }
}

private extension View {
    func glancePill() -> some View {
        padding(.horizontal, 13)
            .frame(height: 36)
            .kGlass(Capsule())
    }
}

struct UsageRing: View {
    let percent: Int

    var body: some View {
        ZStack {
            Circle().stroke(Palette.ink.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(percent > 80 ? Palette.danger : Palette.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.title)
                        .font(KFont.ui(16.5, conversation.unread ? .semibold : .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(conversation.time)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(conversation.unread ? Palette.goldText : Palette.inkFaint)
                }
                HStack(spacing: 6) {
                    if conversation.working { PulsingDot(color: Palette.working, size: 6) .padding(.horizontal, 2) }
                    Text(conversation.preview)
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(conversation.unread ? Palette.ink.opacity(0.9) : Palette.inkFaint)
                        .lineLimit(1)
                }
            }
            if conversation.unread {
                Circle().fill(Palette.gold).frame(width: 10, height: 10)
                    .accessibilityLabel("Waiting for you")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 74) }
    }

    @ViewBuilder
    private var avatar: some View {
        switch conversation.kind {
        case .bot(let id):
            BotFace(bot: SampleData.bot(id), size: 58)
        case .model:
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.inkDim)
                .frame(width: 46, height: 46)
                .background(Palette.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
                .frame(width: 58, height: 58)
        }
    }
}
