import SwiftUI

/// The welcome: a short carousel, the permission moments (each on its own page, with a clear Not now),
/// then connecting to your desktop. Finishing it starts the short tour the first time.
struct OnboardingFlow: View {
    /// Debug pictures can open on a permission page (0, 1 or 2).
    var startPermission: Int? = nil
    @Environment(AppModel.self) private var app
    @State private var page = 0
    @State private var connecting = false
    @State private var permission: Int?

    private let pages: [(title: String, body: String)] = [
        ("Meet Kairos", "Your own AI team, running on your desktop and reachable from your pocket."),
        ("Bots you can text", "Kip and your other bots work like contacts. Message them, call them, and they come back when they need you."),
        ("Everything it makes", "Documents, designs and videos arrive as cards you can swipe, open and share."),
        ("Your desktop, anywhere", "Start coding sessions, steer your screen and reach your files while your PC does the heavy work."),
        ("It finds you", "Live Activities show work in progress. Notifications ask only when a bot needs an answer."),
    ]

    var body: some View {
        ZStack {
            if connecting {
                ConnectView(back: { withAnimation(Motion.sheet) { connecting = false; permission = PermissionMoment.all.count - 1 } })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let permission {
                PermissionPage(moment: PermissionMoment.all[permission], index: permission) {
                    advance(from: permission)
                } back: {
                    withAnimation(Motion.sheet) { self.permission = permission == 0 ? nil : permission - 1 }
                }
                .id(permission)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                carousel.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear {
            if let startPermission { permission = startPermission }
            switch app.debugScreen {
            case "onboarding2": page = 1
            case "connect": connecting = true
            default: break
            }
        }
        .onDisappear {
            // The first time the welcome ends, walk through the real controls once.
            guard app.onboarded, app.debugScreen == nil, app.debugView == nil,
                  !UserDefaults.standard.bool(forKey: "tourSeen") else { return }
            TourPresenter.start(after: 0.9)
        }
    }

    private var carousel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= page ? Palette.gold : Palette.ink.opacity(0.15))
                        .frame(width: index == page ? 26 : 12, height: 4)
                }
                Spacer()
                Button("Skip") { withAnimation(Motion.sheet) { permission = 0 } }
                    .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .animation(Motion.snappy, value: page)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 26) {
                        OnboardingArt(page: index, active: page == index)
                            .frame(maxWidth: .infinity)
                            .frame(height: 370)
                            .kCard(radius: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                        VStack(spacing: 10) {
                            Text(pages[index].title)
                                .font(KFont.display(40))
                                .foregroundStyle(Palette.ink)
                            Text(pages[index].body)
                                .font(KFont.ui(16.5))
                                .foregroundStyle(Palette.inkDim)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                        .padding(.horizontal, 8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 4) {
                GoldButton(title: page == pages.count - 1 ? "Connect your desktop" : "Continue") {
                    Haptics.tap()
                    if page == pages.count - 1 {
                        withAnimation(Motion.sheet) { permission = 0 }
                    } else {
                        withAnimation(Motion.sheet) { page += 1 }
                    }
                }
                QuietButton(title: "Look around first") {
                    app.finishOnboarding()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private func advance(from index: Int) {
        withAnimation(Motion.sheet) {
            if index + 1 < PermissionMoment.all.count {
                permission = index + 1
            } else {
                permission = nil
                connecting = true
            }
        }
    }
}

/// The picture on each welcome page, drawn from the app's own pieces.
private struct OnboardingArt: View {
    let page: Int
    let active: Bool

    var body: some View {
        ZStack {
            RadialGradient(colors: [Palette.glow, Palette.glow.opacity(0)], center: .top, startRadius: 0, endRadius: 330)
            switch page {
            case 0:
                VStack(spacing: 18) {
                    BotFace(bot: SampleData.kip, size: 184, blinks: true)
                        .scaleEffect(active ? 1 : 0.8)
                    HStack(spacing: 10) {
                        ForEach([SampleData.producer, SampleData.scout, SampleData.quill, SampleData.ledger]) { bot in
                            BotFace(bot: bot, size: 60)
                        }
                    }
                    .opacity(active ? 1 : 0)
                    .offset(y: active ? 0 : 16)
                }
            case 1:
                VStack(spacing: 10) {
                    BotFace(bot: SampleData.kip, size: 76, blinks: true)
                    MessageBubble(message: ChatMessage(kind: .theirs("Your report is due Friday. Want a draft?")))
                    MessageBubble(message: ChatMessage(kind: .mine("Yes please.")))
                    MessageBubble(message: ChatMessage(kind: .status("Kip is reading your notes")))
                }
                .padding(.horizontal, 22)
            case 2:
                DocumentStack(documents: SampleData.documents) { _ in }
                    .allowsHitTesting(false)
                    .padding(.leading, 26)
            case 3:
                VStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 8) {
                        PulsingDot(color: Palette.success)
                        Text("Your PC is online").font(KFont.ui(15.5, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .kGlass(Capsule())
                    HStack(spacing: 8) {
                        Chip(text: "Forge", symbol: "hammer")
                        Chip(text: "Computer", symbol: "cursorarrow.rays")
                        Chip(text: "Browse", symbol: "globe")
                    }
                }
            default:
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        BotFace(bot: SampleData.kip, size: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Reading your vault").font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.cream.opacity(0.6))
                            Text("Drafting the summary").font(KFont.ui(15.5, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.cream)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: Palette.botPowder)).frame(width: 9, height: 9)
                            Circle().fill(Color(hex: Palette.botSand)).frame(width: 9, height: 9)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 62)
                    .background(Color.black.opacity(0.82), in: Capsule())
                    .environment(\.colorScheme, .dark)
                    notification("Scout is waiting for your answer", "Tap to answer in Kairos.")
                    notification("Your reply is ready", "Private mode hides the chat title.")
                }
                .padding(.horizontal, 20)
            }
        }
        .animation(Motion.bouncy, value: active)
    }

    private func notification(_ title: String, _ detail: String) -> some View {
        HStack(spacing: 11) {
            BotFace(bot: SampleData.kip, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(14.5, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .kCard(radius: 20, raised: true)
    }
}
