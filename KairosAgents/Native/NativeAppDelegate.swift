import SwiftUI
import UIKit
import WidgetKit

/// The native layer's start-up. The shell installs it with
/// `@UIApplicationDelegateAdaptor(NativeAppDelegate.self) var native` in `KairosAgentsApp`,
/// because a ring can wake a closed app before any screen exists.
final class NativeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NativeServices.start()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NativeTokens.shared.apns = LiveActivities.hex(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    /// Quiet pushes: a ring that ended elsewhere, or a widget refresh.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        switch userInfo["kind"] as? String {
        case "bot_call_end":
            CallCenter.shared.ringEnded(userInfo["ring_id"] as? String ?? "", outcome: userInfo["outcome"] as? String ?? "")
            return .newData
        case "widgets":
            WidgetCenter.shared.reloadAllTimelines()
            return .newData
        default:
            return .noData
        }
    }
}

/// Everything the native layer starts once per launch. Safe to call more than once.
enum NativeServices {
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        startConnection()
        NativeNotifications.shared.start()
        CallCenter.shared.start()
        LiveActivities.shared.start()
        WidgetSync.publish()
    }

    /// A ring can launch the app with no screen, and the Lock Screen's Answer or Decline has to reach the
    /// desktop: connect now, not when Home appears. This also fills in `PushBridge`. With no pairing it does
    /// nothing (the app stays on sample data); `Connection.start` runs once however often it is called.
    /// Before the first unlock after a restart it waits and runs again on unlock.
    /// A debug launch that opens one view on its own (`-kDebugView`) stays off the network, as before.
    private static func startConnection() {
        guard !Connection.isDebugViewLaunch else { return }
        Connection.shared.start()
    }
}

/// Writes what the widgets show into the App Group, then asks WidgetKit to redraw.
/// On sample data until a desktop is paired; the connection calls `publish(_:)` with real numbers.
enum WidgetSync {
    static func publish(_ snapshot: WidgetSnapshot? = nil) {
        guard NativeSettings.widgetsShareData else {
            WidgetSnapshotStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        WidgetSnapshotStore.write(snapshot ?? NativeSample.snapshot())
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Where a notification, a widget or a Live Activity asked to go. The shell's `.nativeLinks()` follows it.
@Observable
final class NativeLinks {
    static let shared = NativeLinks()

    var pending: NativeLink?
    var showSettings = false
    @ObservationIgnored private var waiting: Task<Void, Never>?
    /// The bot whose chat an Ask link just opened, so that chat can bring the keyboard up (`takeAskFocus`).
    @ObservationIgnored private var askFocus: (botID: String, at: Date)?

    /// Widgets and some pushes name Kip as "kip" and the sample team as "content-team". On a paired phone a link
    /// is resolved against the paired desktop's own bots when it is followed: "kip" is the desktop's Kip, and a bot
    /// the desktop does not have opens Home instead of a screen for nothing. Not paired, every link goes where it
    /// always went.
    ///
    /// Which links may wait for the bot list (paired only):
    /// - ring: never. Answered at once by `CallCenter`.
    /// - call: never. With a call already running it only shows that call. With the list there it dials at once;
    ///   without it, it waits as the bot's own screen (Call is one tap there) and never dials later.
    /// - bot, ask, approval: may wait, up to 20 seconds, for the list (or for one fresh read when the list there
    ///   does not have the bot). The wait is dropped the moment the person moves, a sheet or cover comes up,
    ///   another link is tapped or the account changes; when it runs out nothing happens.
    /// - chat, new chat, area, tab, home, desktop, all bots: never. They name no bot.
    func open(_ link: NativeLink) {
        cancelWaiting()
        // A call that is already running is only ever shown: a link never hangs it up and never dials anyone else.
        if case .call = link, CallCenter.shared.session != nil {
            CallCenter.shared.showingCall = true
            return
        }
        let store = ChatStore.shared
        guard !store.isSample, Self.namesBot(link) else {
            deliver(link)
            return
        }
        if store.homeLoaded, let resolved = Self.resolve(link, in: store) {
            deliver(resolved)
            return
        }
        wait(for: link, in: store)
    }

    /// The person moved (another screen, tab or sheet): a link still waiting for the bot list is dropped.
    func cancelWaiting() {
        waiting?.cancel()
        waiting = nil
    }

    /// Wait for the bot list, then follow the link as a screen only. A call never dials from here.
    private func wait(for link: NativeLink, in store: ChatStore) {
        let generation = store.generation
        let presenting = Self.presenting
        let readAgain = store.homeLoaded
        let screen = Self.asScreen(link)
        let task = Task { [weak self] in
            // The list is there but does not have this bot: it may be older than the desktop's, so read it once more.
            if readAgain { await store.refreshHome() }
            let deadline = Date().addingTimeInterval(20)
            while !Task.isCancelled, !store.homeLoaded, Date() < deadline, Self.stillTrying,
                  store.generation == generation, Self.presenting == presenting {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled, let self else { return }
            self.waiting = nil
            // Another account, a sheet or cover that came up, or no list in time: nothing happens.
            guard !store.isSample, store.generation == generation, Self.presenting == presenting, store.homeLoaded else { return }
            self.deliver(Self.resolve(screen, in: store) ?? .home)
        }
        waiting = task
    }

    private func deliver(_ link: NativeLink) {
        switch link {
        case .ring(let ring, let bot):
            CallCenter.shared.answerFromLink(ringID: ring, botID: bot)
        case .call(let bot):
            // The same path a call from the bot's own screen takes: CallCenter with the bot itself.
            let store = ChatStore.shared
            CallCenter.shared.startCall(with: store.isSample ? SampleData.bot(bot) : store.bot(bot))
        case .ask(let bot):
            askFocus = (bot, Date())
            pending = link
        default:
            pending = link
        }
    }

    /// True once, when the chat of `botID` opens right after an Ask link: that chat brings the keyboard up.
    /// Any other way of opening a chat answers false.
    func takeAskFocus(for botID: String) -> Bool {
        guard let askFocus, askFocus.botID == botID, Date().timeIntervalSince(askFocus.at) < 5 else { return false }
        self.askFocus = nil
        return true
    }

    /// Links that carry a bot id. A ring's bot comes from the ring itself and is left to `CallCenter`.
    private static func namesBot(_ link: NativeLink) -> Bool {
        switch link {
        case .bot, .ask, .call, .approval: true
        default: false
        }
    }

    /// What a link shows when it had to wait: a call becomes its bot's screen, where Call is one tap.
    private static func asScreen(_ link: NativeLink) -> NativeLink {
        if case .call(let id) = link { return .bot(id) }
        return link
    }

    /// The connection is still on its way (or there), so the bot list can still come.
    private static var stillTrying: Bool {
        switch Connection.shared.state {
        case .signedOut, .sample: false
        default: true
        }
    }

    /// Whether any sheet or full-screen cover is up, in any window. A change while a link waits drops the link.
    private static var presenting: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }

    /// The link with its bot id swapped for the paired desktop's own, or nil when that bot is not there.
    /// A real bot whose id is "kip" keeps its own links; only otherwise does "kip" mean the desktop's Kip.
    static func resolve(_ link: NativeLink, in store: ChatStore) -> NativeLink? {
        func real(_ id: String) -> String? {
            if store.bots.contains(where: { $0.id == id }) { return id }
            if id == NativeLink.kip { return store.kip?.id }
            return nil
        }
        switch link {
        case .bot(let id): return real(id).map { NativeLink.bot($0) }
        case .ask(let id): return real(id).map { NativeLink.ask($0) }
        case .call(let id): return real(id).map { NativeLink.call($0) }
        case .approval(let request, let id): return real(id).map { NativeLink.approval(requestID: request, botID: $0) }
        default: return link
        }
    }
}

extension View {
    /// Put on the shell's root, inside the router's environment: follows deep links from notifications,
    /// widgets and Live Activities, shows the call screen and its minimize pill, and the notification settings.
    func nativeLinks() -> some View { modifier(NativeLinksModifier()) }
}

private struct NativeLinksModifier: ViewModifier {
    @Environment(AppRouter.self) private var router
    private var links = NativeLinks.shared
    private var calls = CallCenter.shared

    func body(content: Content) -> some View {
        @Bindable var calls = calls
        @Bindable var links = links
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                // The pill takes its own row so it never covers a screen's header.
                if calls.minimized, let session = calls.session {
                    CallPill(session: session) { calls.showingCall = true }
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Motion.snappy, value: calls.minimized)
            .onOpenURL { url in
                if let link = NativeLink(url: url) { links.open(link) }
            }
            .onChange(of: links.pending) {
                guard let link = links.pending else { return }
                links.pending = nil
                follow(link)
            }
            // The person moved on their own: a link still waiting for the bot list must not move them again.
            .onChange(of: router.paths) { links.cancelWaiting() }
            .onChange(of: router.tab) { links.cancelWaiting() }
            .onChange(of: router.sheet) { links.cancelWaiting() }
            .onChange(of: calls.showingCall) { links.cancelWaiting() }
            .onChange(of: links.showSettings) { links.cancelWaiting() }
            .onAppear {
                NativeServices.start()
                if let link = links.pending { links.pending = nil; follow(link) }
            }
            .fullScreenCover(isPresented: $calls.showingCall) {
                if let session = calls.session { CallView(bot: session.bot) }
            }
            .sheet(isPresented: $links.showSettings) {
                NavigationStack { NotificationSettingsScreen() }
                    .environment(router)
            }
    }

    private func follow(_ link: NativeLink) {
        router.sheet = nil
        switch link {
        case .chat(let id): router.paths[.home] = []; router.push(.chat(id), on: .home)
        case .bot(let id), .ask(let id), .approval(_, let id): router.paths[.home] = []; router.push(.bot(id), on: .home)
        case .newChat: router.push(.newChat, on: .home)
        case .area(let raw):
            if let area = JumpArea(rawValue: raw) { router.open(area) }
        case .addedTab(let title): router.push(.page(title))
        case .home: router.paths[.home] = []; router.select(.home)
        case .desktop: router.paths[.desktop] = []; router.select(.desktop)
        case .allBots: router.paths[.home] = []; router.push(.allBots, on: .home)
        case .ring, .call: break
        }
    }
}
