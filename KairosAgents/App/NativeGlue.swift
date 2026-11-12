import SwiftUI
import UserNotifications

/// Where the desktop connection meets the native layer. Each side was built against a seam
/// (`ConnectionSeam` on the connection's side, `NativeBridge` on the native side); this joins them:
/// running turns become Live Activities, the widgets get the real numbers, Stop and Retry on a
/// Live Activity reach the desktop, and a newly paired phone is asked about notifications.
enum NativeGlue {
    private static var joined = false
    /// Turns that are running now, by turn id.
    private static var live: [String: ConnectionSeam.RunInfo] = [:]
    /// Which model chat each turn belongs to, kept after it ends so Retry can find it.
    private static var chats: [String: String] = [:]
    private static var publishQueued = false

    /// Called once at launch, before any screen is up.
    static func join() {
        guard !joined else { return }
        joined = true

        ConnectionSeam.runBegan = { run in follow(run) }
        ConnectionSeam.runChanged = { run in follow(run) }
        ConnectionSeam.runEnded = { run in
            live[run.turnID] = nil
            LiveActivities.shared.finish(run.turnID, state(run))
            publishSoon()
        }
        ConnectionSeam.homeChanged = { _ in publishSoon() }
        ConnectionSeam.paired = { PairedAsk.shared.offer() }

        NativeBridge.stop = { @Sendable id, _ in await NativeGlue.stop(id) }
        NativeBridge.retry = { @Sendable id, _ in await NativeGlue.retry(id) }
    }

    static func stop(_ turnID: String) async {
        await ConnectionSeam.stop(turnID: turnID)
    }

    /// Retry sends a model chat's last question again. A bot's turn has no retry on the desktop yet.
    static func retry(_ turnID: String) async {
        guard let chatID = chats[turnID] else { return }
        await ConnectionSeam.retry(chatID: chatID)
    }

    // MARK: Live Activities

    private static func follow(_ run: ConnectionSeam.RunInfo) {
        live[run.turnID] = run
        if run.botID == nil { chats[run.turnID] = run.chatID }
        LiveActivities.shared.begin(attributes(run), state(run))
        publishSoon()
    }

    private static func attributes(_ run: ConnectionSeam.RunInfo) -> KairosActivityAttributes {
        let who = face(run)
        return KairosActivityAttributes(
            id: run.turnID, kind: .reply, title: title(run), botID: run.botID ?? "", botName: who.name,
            botColor: who.color, botShape: who.shape, link: link(run))
    }

    private static func state(_ run: ConnectionSeam.RunInfo) -> LiveActivities.State {
        // Keep the start time (and anything else already showing) across updates.
        var state = LiveActivities.shared.running[run.turnID] ?? LiveActivities.State(step: "")
        state.step = run.step.isEmpty ? "Working" : run.step
        switch run.status {
        case "done":
            state.phase = .done
        case "failed":
            state.phase = .failed
            state.detail = run.error ?? ""
        case "stopped":
            state.phase = .stopped
        default:
            state.phase = run.waitingOnPerson ? .waiting : .running
        }
        return state
    }

    private static func title(_ run: ConnectionSeam.RunInfo) -> String {
        run.title.isEmpty ? "New chat" : run.title
    }

    private static func link(_ run: ConnectionSeam.RunInfo) -> String {
        if let botID = run.botID { return NativeLink.bot(botID).url.absoluteString }
        return NativeLink.chat(run.chatID).url.absoluteString
    }

    /// The face a turn is drawn with: the bot's own, or Kip's ink body for a model chat.
    private static func face(_ run: ConnectionSeam.RunInfo) -> (name: String, color: UInt32?, shape: String) {
        guard let botID = run.botID else { return ("Kairos", nil, MascotShape.round.rawValue) }
        let bot = ChatStore.shared.bot(botID)
        return (run.botName ?? bot.name, bot.isKip ? nil : bot.colorHex, bot.shape.rawValue)
    }

    // MARK: Widgets

    /// The store calls in while it is still changing (and once while it is being made), so wait a beat.
    private static func publishSoon() {
        guard !publishQueued else { return }
        publishQueued = true
        Task { @MainActor in
            publishQueued = false
            publishWidgets()
        }
    }

    /// Widgets list the work this phone has seen running. The counts on Home can be higher:
    /// they come from the desktop and include work this phone has not opened.
    private static func publishWidgets() {
        let store = ChatStore.shared
        guard !store.isSample else {
            WidgetSync.publish()
            return
        }
        let runs = live.values.sorted { $0.turnID < $1.turnID }
        var snapshot = WidgetSnapshot(updatedAt: .now, connected: true)
        snapshot.running = runs.map { run in
            let who = face(run)
            return WidgetSnapshot.Running(
                id: run.turnID, title: title(run), botName: who.name, botColor: who.color, botShape: who.shape,
                progress: nil, step: run.step, link: link(run))
        }
        snapshot.needsYou = runs.filter(\.waitingOnPerson).map { run in
            let who = face(run)
            let request = store.runs[run.chatID]?.request
            return WidgetSnapshot.Waiting(
                id: request?.id ?? run.turnID, botID: run.botID ?? "", botName: who.name, botColor: who.color, botShape: who.shape,
                kind: request?.kind == .question ? "Question" : "Approval", link: link(run))
        }
        snapshot.usage = store.glance.usage.map {
            WidgetSnapshot.Usage(provider: $0.provider, percent: $0.percent, resetsAt: $0.resetsAt)
        }
        if let title = store.glance.nextEventTitle, let start = store.glance.nextEventStart {
            snapshot.nextEvent = WidgetSnapshot.Event(title: title, startsAt: start, allDay: store.glance.nextEventAllDay)
        }
        WidgetSync.publish(snapshot)
    }
}

/// After pairing, offer notifications once, with the reason first. Only when iOS has not been asked yet.
@Observable
final class PairedAsk {
    static let shared = PairedAsk()

    var showing = false

    func offer() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            try? await Task.sleep(for: .seconds(1.2))
            showing = true
        }
    }
}

extension View {
    /// Put on the shell's root: shows the notification ask after a phone is paired.
    func pairedAsk() -> some View { modifier(PairedAskModifier()) }
}

private struct PairedAskModifier: ViewModifier {
    private var ask = PairedAsk.shared
    private var notifications = NativeNotifications.shared

    func body(content: Content) -> some View {
        @Bindable var ask = ask
        content
            .sheet(isPresented: $ask.showing) {
                FittedSheet(estimate: 300) {
                    VStack(spacing: 10) {
                        NotificationAskCard()
                        QuietButton(title: "Not now") {
                            Haptics.tap()
                            ask.showing = false
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 30)
                    .padding(.bottom, 14)
                }
            }
            .onChange(of: notifications.status) {
                if notifications.status != .notDetermined { ask.showing = false }
            }
    }
}
