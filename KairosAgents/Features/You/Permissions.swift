import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - Permission moments in the welcome

/// One thing the app asks iOS for, explained before iOS asks.
nonisolated struct PermissionMoment: Sendable {
    enum Kind: Sendable { case notifications, microphone, camera }
    let kind: Kind
    let symbol: String
    let title: String
    let body: String
    let reasons: [String]
    let allow: String

    static let all: [PermissionMoment] = [
        PermissionMoment(kind: .notifications, symbol: "bell.badge", title: "Know when a bot needs you",
                         body: "Kairos only taps you when there is something to answer or something finished.",
                         reasons: ["A bot asks a question or wants your approval", "A long reply or a background task is done", "A bot calls you"],
                         allow: "Allow notifications"),
        PermissionMoment(kind: .microphone, symbol: "mic", title: "Talk to your bots",
                         body: "Your voice goes to your own desktop, which turns it into words.",
                         reasons: ["Call Kip or any bot", "Dictate a message instead of typing", "Open Mic, hands free"],
                         allow: "Allow the microphone"),
        PermissionMoment(kind: .camera, symbol: "camera", title: "Show your bots things",
                         body: "Take a photo straight into a chat. Nothing is taken unless you press the shutter.",
                         reasons: ["Snap a receipt for Ledger", "Photograph a page to summarise", "Scan a whiteboard into a note"],
                         allow: "Allow the camera"),
    ]
}

/// A welcome page that explains one permission, with Allow and a clear Not now.
struct PermissionPage: View {
    let moment: PermissionMoment
    let index: Int
    let next: () -> Void
    let back: () -> Void
    @State private var state: PermissionState = .unknown
    @State private var note: String?
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                GlassIconButton(symbol: "chevron.left", label: "Back", action: back)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(PermissionMoment.all.indices, id: \.self) { dot in
                        Capsule()
                            .fill(dot <= index ? Palette.gold : Palette.ink.opacity(0.15))
                            .frame(width: dot == index ? 22 : 10, height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.top, 4)

            ZStack {
                RadialGradient(colors: [Palette.glow, Palette.glow.opacity(0)], center: .top, startRadius: 0, endRadius: 300)
                VStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Palette.gold.opacity(0.16)).frame(width: 150, height: 150)
                            .scaleEffect(shown ? 1 : 0.7)
                        Image(systemName: moment.symbol)
                            .font(.system(size: 54, weight: .medium))
                            .foregroundStyle(Palette.goldText)
                            .symbolEffect(.bounce, value: shown)
                        BotFace(bot: SampleData.kip, size: 64, blinks: true)
                            .offset(x: 74, y: 54)
                    }
                    .frame(height: 180)
                    if state == .granted {
                        Chip(text: "Already on", symbol: "checkmark")
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .kCard(radius: 38)
            .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 10) {
                Text(moment.title)
                    .font(KFont.display(36))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(moment.body)
                    .font(KFont.ui(16.5))
                    .foregroundStyle(Palette.inkDim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(moment.reasons.enumerated()), id: \.offset) { offset, reason in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.goldText)
                            Text(reason).font(KFont.ui(15.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                        }
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown || reduceMotion ? 0 : 8)
                        .animation(Motion.sheet.delay(0.1 + Double(offset) * 0.06), value: shown)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.top, 24)

            if let note {
                Text(note)
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            Spacer(minLength: 12)

            VStack(spacing: 4) {
                GoldButton(title: state == .granted ? "Continue" : moment.allow) { allow() }
                if state != .granted {
                    QuietButton(title: "Not now") {
                        Haptics.tap()
                        next()
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .animation(Motion.snappy, value: state)
        .animation(Motion.snappy, value: note)
        .task {
            state = await PermissionCheck.state(moment.kind)
            withAnimation(Motion.bouncy) { shown = true }
        }
    }

    private func allow() {
        Haptics.tap()
        if state == .granted {
            next()
            return
        }
        if state == .denied {
            note = "It is off in iOS Settings. You can turn it on there any time."
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                next()
            }
            return
        }
        Task {
            let result = await PermissionCheck.request(moment.kind)
            switch result {
            case .granted:
                Haptics.success()
                state = .granted
                try? await Task.sleep(for: .seconds(0.5))
                next()
            case .unavailable:
                note = "This build cannot ask for this yet. You can turn it on later in Settings."
                try? await Task.sleep(for: .seconds(1.6))
                next()
            default:
                next()
            }
        }
    }
}

/// One permission step of the welcome. The notifications step is a slot for the native layer.
struct WelcomePermissionStep: View {
    let index: Int
    let next: () -> Void
    let back: () -> Void

    var body: some View {
        if index == 0 {
            WelcomeNotificationSlot(next: next, back: back)
        } else {
            PermissionPage(moment: PermissionMoment.all[index], index: index, next: next, back: back)
        }
    }
}

/// Lead: at merge, fill this slot with the native layer's `NotificationAskCard()` (keeping Back and
/// the step dots if they fit). Until then it uses the plain permission page.
struct WelcomeNotificationSlot: View {
    let next: () -> Void
    let back: () -> Void

    var body: some View {
        PermissionPage(moment: PermissionMoment.all[0], index: 0, next: next, back: back)
    }
}

// MARK: - Asking iOS

nonisolated enum PermissionState: Sendable { case unknown, notAsked, granted, denied, unavailable }

/// Reads and asks for the iOS permissions the app uses. Microphone and camera ask only when the
/// build carries the usage text iOS requires, so a build without it never crashes on the question.
enum PermissionCheck {
    static func state(_ kind: PermissionMoment.Kind) async -> PermissionState {
        switch kind {
        case .notifications:
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined: return .notAsked
            case .denied: return .denied
            default: return .granted
            }
        case .microphone:
            return capture(AVCaptureDevice.authorizationStatus(for: .audio))
        case .camera:
            return capture(AVCaptureDevice.authorizationStatus(for: .video))
        }
    }

    static func request(_ kind: PermissionMoment.Kind) async -> PermissionState {
        switch kind {
        case .notifications:
            // The shared ask also registers for remote notifications once allowed, so push works from here on.
            return await NativeNotifications.shared.requestPermission() ? .granted : .denied
        case .microphone:
            guard hasUsageText("NSMicrophoneUsageDescription") else { return .unavailable }
            return await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
        case .camera:
            guard hasUsageText("NSCameraUsageDescription") else { return .unavailable }
            return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        }
    }

    private static func hasUsageText(_ key: String) -> Bool {
        Bundle.main.object(forInfoDictionaryKey: key) != nil
    }

    private static func capture(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notAsked
        }
    }
}
