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

    /// Widgets and some pushes name Kip as "kip" and the sample team as "content-team". On a paired phone a link
    /// is resolved against the paired desktop's own bots when it is followed: "kip" is the desktop's Kip, and a bot
    /// the desktop does not have opens Home instead of a screen for nothing. On a cold start this waits for the
    /// bot list first. Not paired, every link goes where it always went.
    func open(_ link: NativeLink) {
        waiting?.cancel()
        waiting = nil
        let store = ChatStore.shared
        guard !store.isSample, Self.namesBot(link) else {
            deliver(link)
            return
        }
        if store.homeLoaded {
            deliver(Self.resolve(link, in: store) ?? .home)
            return
        }
        waiting = Task { [weak self] in
            let deadline = Date().addingTimeInterval(20)
            while !Task.isCancelled, !store.isSample, !store.homeLoaded, store.homeError == nil, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled, let self else { return }
            self.waiting = nil
            if store.isSample {
                self.deliver(link)
            } else if store.homeLoaded {
                self.deliver(Self.resolve(link, in: store) ?? .home)
            } else {
                // The bot list never came: never push a screen for a bot that may not exist.
                self.deliver(.home)
            }
        }
    }

    private func deliver(_ link: NativeLink) {
        switch link {
        case .ring(let ring, let bot):
            CallCenter.shared.answerFromLink(ringID: ring, botID: bot)
        case .call(let bot):
            // The same path a call from the bot's own screen takes: CallCenter with the bot itself.
            let store = ChatStore.shared
            CallCenter.shared.startCall(with: store.isSample ? SampleData.bot(bot) : store.bot(bot))
        default:
            pending = link
        }
    }

    /// Links that carry a bot id. A ring's bot comes from the ring itself and is left to `CallCenter`.
    private static func namesBot(_ link: NativeLink) -> Bool {
        switch link {
        case .bot, .ask, .call, .approval: true
        default: false
        }
    }

    /// The link with its bot id swapped for the paired desktop's own, or nil when that bot is not there.
    static func resolve(_ link: NativeLink, in store: ChatStore) -> NativeLink? {
        func real(_ id: String) -> String? {
            if id == NativeLink.kip { return store.kip?.id }
            return store.bots.contains { $0.id == id } ? id : nil
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
