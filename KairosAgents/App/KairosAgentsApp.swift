import SwiftUI
import UIKit

@main
struct KairosAgentsApp: App {
    @State private var app = AppModel()
    /// Calls and notifications have to be listening from launch, before any screen is up.
    @UIApplicationDelegateAdaptor(NativeAppDelegate.self) private var native

    init() {
        // A finished render is watched from one temporary file. Any left behind by an app that was closed
        // mid-play is removed at launch, before a screen is up.
        MakeVideoWatchFiles.clearAll()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.appearance.colorScheme)
                .tint(Palette.gold)
        }
    }
}

enum AppLook: String, CaseIterable, Identifiable {
    case night, light, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .night: "Night"
        case .light: "Light"
        case .system: "Match iPhone"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .night: .dark
        case .light: .light
        case .system: nil
        }
    }
}

/// What the whole app knows: whether the welcome is done and which look is on.
@Observable
final class AppModel {
    private(set) var onboarded: Bool
    private(set) var appearance: AppLook
    /// Debug builds can open straight onto one screen ("-kScreen home"), for the build's screenshots.
    let debugScreen: String?
    /// Debug builds can also open one named view on its own ("-kDebugView library.vault").
    let debugView: String?

    init() {
        NativeGlue.join()
        let defaults = UserDefaults.standard
        onboarded = defaults.bool(forKey: "onboarded")
        var look = AppLook(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .night
        #if DEBUG
        debugScreen = defaults.string(forKey: "kScreen")
        debugView = defaults.string(forKey: "kDebugView")
        if let forced = defaults.string(forKey: "kAppearance"), let value = AppLook(rawValue: forced) { look = value }
        #else
        debugScreen = nil
        debugView = nil
        #endif
        appearance = look
    }

    func finishOnboarding() {
        onboarded = true
        UserDefaults.standard.set(true, forKey: "onboarded")
    }

    func replayOnboarding() {
        onboarded = false
        UserDefaults.standard.set(false, forKey: "onboarded")
    }

    func setAppearance(_ value: AppLook) {
        appearance = value
        UserDefaults.standard.set(value.rawValue, forKey: "appearance")
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Ground()
            if let name = app.debugView {
                DebugHost(name: name)
            } else if app.onboarded {
                ShellView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: app.onboarded)
    }
}

/// Screens hide the system bar and draw their own header, so keep the swipe from the left edge working.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
