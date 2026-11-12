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
        NativeNotifications.shared.start()
        CallCenter.shared.start()
        LiveActivities.shared.start()
        WidgetSync.publish()
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

    func open(_ link: NativeLink) {
        switch link {
        case .ring(let ring, let bot):
            CallCenter.shared.answerFromLink(ringID: ring, botID: bot)
        case .call(let bot):
            CallCenter.shared.startCall(with: SampleData.bot(bot))
        default:
            pending = link
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
        case .ring, .call: break
        }
    }
}
