import SwiftUI

/// The welcome: a short carousel, then connecting to your desktop.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var app
    @State private var page = 0
    @State private var connecting = false

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
                ConnectView(back: { withAnimation(Motion.sheet) { connecting = false } })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                carousel.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear {
            switch app.debugScreen {
            case "onboarding2": page = 1
            case "connect": connecting = true
            default: break
            }
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
                Button("Skip") { withAnimation(Motion.sheet) { connecting = true } }
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
                        withAnimation(Motion.sheet) { connecting = true }
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
                    BotFace(bot: SampleData.kip, size: 150, blinks: true)
                        .scaleEffect(active ? 1 : 0.8)
                    HStack(spacing: 10) {
                        ForEach([SampleData.producer, SampleData.scout, SampleData.quill, SampleData.ledger]) { bot in
                            BotFace(bot: bot, size: 46)
                        }
                    }
                    .opacity(active ? 1 : 0)
                    .offset(y: active ? 0 : 16)
                }
            case 1:
                VStack(spacing: 10) {
                    BotFace(bot: SampleData.kip, size: 60, blinks: true)
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
                        BotFace(bot: SampleData.kip, size: 34)
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
            BotFace(bot: SampleData.kip, size: 34)
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

/// Connect to your own desktop: its address and the pairing code from Kairos Settings.
struct ConnectView: View {
    let back: () -> Void
    @Environment(AppModel.self) private var app
    @State private var address = ""
    @State private var code = ""
    @State private var note: String?
    @FocusState private var field: Field?

    private enum Field { case address, code }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassIconButton(symbol: "chevron.left", label: "Back", action: back)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("Connect your desktop")
                    .font(KFont.display(38))
                    .foregroundStyle(Palette.ink)
                Text("On your PC, open Kairos, then Settings, then Phone. It shows an address and a 6 digit code.")
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.inkDim)
                    .lineSpacing(3)
            }
            .padding(.top, 26)

            VStack(spacing: 12) {
                entry("Address", symbol: "link") {
                    TextField("yourname.kairos-agents.com", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($field, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { field = .code }
                }
                entry("Pairing code", symbol: "number") {
                    TextField("6 digits", text: $code)
                        .keyboardType(.numberPad)
                        .focused($field, equals: .code)
                        .onChange(of: code) { code = String(code.filter(\.isNumber).prefix(6)) }
                }
            }
            .font(KFont.ui(17))
            .foregroundStyle(Palette.ink)
            .padding(.top, 28)

            if let note {
                Text(note)
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            VStack(spacing: 4) {
                GoldButton(title: "Connect") {
                    field = nil
                    withAnimation(Motion.snappy) {
                        if address.trimmingCharacters(in: .whitespaces).isEmpty || code.count < 6 {
                            note = "Enter the address and the 6 digit code from your PC."
                        } else {
                            note = "Pairing is not in this build yet. You can look around with sample data."
                        }
                    }
                }
                QuietButton(title: "Look around first") { app.finishOnboarding() }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .scrollDismissesKeyboard(.interactively)
    }

    private func entry<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.goldText).frame(width: 22)
                content()
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .kGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
