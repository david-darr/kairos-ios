import SwiftUI

/// The signed-in app: four tabs under one floating glass bar.
struct ShellView: View {
    @Environment(AppModel.self) private var app
    @State private var router = AppRouter()
    @State private var chrome = ChromeState()

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            ForEach(AppTab.allCases) { tab in
                if router.visited.contains(tab) {
                    TabRoot(tab: tab)
                        .opacity(router.tab == tab ? 1 : 0)
                        .scaleEffect(router.tab == tab ? 1 : 0.985)
                        .allowsHitTesting(router.tab == tab)
                        .accessibilityHidden(router.tab != tab)
                        .zIndex(router.tab == tab ? 1 : 0)
                }
            }

            if chrome.jumpOpen {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { chrome.closeJump() }
                    .transition(.opacity)
                    .zIndex(2)
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)
            }

            BottomChrome()
                .offset(y: router.barHidden ? 170 : 0)
                .opacity(router.barHidden ? 0 : 1)
                .allowsHitTesting(!router.barHidden)
                .zIndex(3)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(Motion.gentle, value: router.tab)
        .animation(Motion.snappy, value: router.barHidden)
        .animation(Motion.gentle, value: chrome.jumpOpen)
        .sheet(item: $router.sheet) { sheet in
            Group {
                switch sheet {
                case .search: SearchView()
                case .you: YouView()
                }
            }
            .environment(router)
            .environment(chrome)
            .environment(app)
        }
        .environment(router)
        .environment(chrome)
        .onAppear { DebugScreens.open(app.debugScreen, router: router, chrome: chrome) }
    }
}

private struct TabRoot: View {
    let tab: AppTab
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack(path: router.path(tab)) {
            Group {
                switch tab {
                case .home: HomeView()
                case .make: MakeView()
                case .library: LibraryView()
                case .desktop: DesktopView()
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .bot(let id): BotChatView(bot: SampleData.bot(id))
                case .chat(let id): ModelChatView(conversation: SampleData.conversation(id))
                case .newChat: ModelChatView(conversation: nil)
                case .area(let area): AreaView(title: area.title, symbol: area.symbol, about: area.about)
                case .page(let title): AreaView(title: title, symbol: "square.dashed", about: "")
                }
            }
        }
    }
}

/// A plain page for an area whose own screens are not built yet.
struct AreaView: View {
    let title: String
    let symbol: String
    let about: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 84, height: 84)
                .kGlass(Circle())
            Text(title).font(KFont.display(34)).foregroundStyle(Palette.ink)
            if !about.isEmpty {
                Text(about).font(KFont.ui(16)).foregroundStyle(Palette.inkDim).multilineTextAlignment(.center)
            }
            Text("This screen is not built yet.")
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .padding(.top, 2)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                GlassIconButton(symbol: "chevron.left", label: "Back") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .kScreen()
    }
}

/// Debug builds only: open straight onto one screen so the build can take its picture.
enum DebugScreens {
    static func open(_ name: String?, router: AppRouter, chrome: ChromeState) {
        guard let name else { return }
        router.debugScreen = name
        switch name {
        case "collapsed":
            chrome.held = true
            chrome.collapsed = true
        case "jump": chrome.openJump()
        case "bot", "botpanel", "botsettings", "call": router.push(.bot("kip"), on: .home)
        case "chat": router.push(.chat("c-zip"), on: .home)
        case "chatlive", "modelsheet", "tools", "docviewer": router.push(.chat("c-bike"), on: .home)
        case "make": router.select(.make)
        case "library": router.select(.library)
        case "desktop": router.select(.desktop)
        case "you": router.sheet = .you
        case "search", "bots": router.sheet = .search
        default: break
        }
    }
}
