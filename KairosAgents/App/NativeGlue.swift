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
    /// Which chat or bot thread each turn belongs to, kept after it ends so opening that thread ends its card.
    private static var threads: [String: String] = [:]
    private static var publishQueued = false
    /// Turns whose chat the person opened: their Live Activity was ended and does not come back.
    private static var opened: Set<String> = []
    /// Each running turn's step and the one before it, so a widget can move the line on.
    private static var steps: [String: (now: String, before: String?)] = [:]
    /// The newest turn that finished or failed, for the widgets' end card. Only an end the desktop reported:
    /// a turn the phone saw disappear while it was away reaches `runEnded` still "processing" and leaves no card.
    private static var lastEnded: WidgetSnapshot.Ended?
    /// `ChatStore.generation` when the widgets were last written, so another account's work is dropped.
    private static var accountGeneration: Int?

    /// Called once at launch, before any screen is up.
    static func join() {
        guard !joined else { return }
        joined = true

        ConnectionSeam.runBegan = { run in follow(run) }
        ConnectionSeam.runChanged = { run in follow(run) }
        ConnectionSeam.runEnded = { run in
            live[run.turnID] = nil
            steps[run.turnID] = nil
            opened.remove(run.turnID)
            if run.status == "done" || run.status == "failed" {
                let who = face(run)
                lastEnded = WidgetSnapshot.Ended(
                    title: title(run), botName: who.name, botColor: who.color, botShape: who.shape,
                    failed: run.status == "failed", at: .now, link: link(run), isKip: isKip(run))
            }
            LiveActivities.shared.finish(run.turnID, state(run))
            publishSoon()
        }
        ConnectionSeam.chatOpened = { chatID, botID in chatOpened(chatID: chatID, botID: botID) }
        ConnectionSeam.homeChanged = { _ in publishSoon() }
        ConnectionSeam.paired = { PairedAsk.shared.offer() }

        NativeBridge.stop = { @Sendable id, _ in await NativeGlue.stop(id) }
        NativeBridge.retry = { @Sendable id, _ in await NativeGlue.retry(id) }
        NativeBridge.canRetry = { @Sendable id in await NativeGlue.canRetry(id) }
    }

    static func stop(_ turnID: String) async {
        await ConnectionSeam.stop(turnID: turnID)
    }

    /// Whether Retry knows this turn's chat. A failure the phone did not watch is not here,
    /// so the notification's Try again opens its chat instead (`NativeNotifications.handle`).
    static func canRetry(_ turnID: String) -> Bool {
        chats[turnID] != nil
    }

    /// Retry sends a model chat's last question again. A bot's turn has no retry on the desktop yet.
    static func retry(_ turnID: String) async {
        guard let chatID = chats[turnID] else { return }
        await ConnectionSeam.retry(chatID: chatID)
    }

    // MARK: Live Activities

    private static func follow(_ run: ConnectionSeam.RunInfo) {
        live[run.turnID] = run
        threads[run.turnID] = run.chatID
        if !run.step.isEmpty {
            let known = steps[run.turnID]
            if known?.now != run.step { steps[run.turnID] = (now: run.step, before: known?.now) }
        }
        if run.botID == nil { chats[run.turnID] = run.chatID }
        if !opened.contains(run.turnID) { LiveActivities.shared.begin(attributes(run), state(run)) }
        publishSoon()
    }

    /// A chat or bot thread is on screen: end its Live Activities now, with no card left behind, including one
    /// for a turn still running there (the person is watching it). Only that thread's: a bot's other threads keep
    /// theirs, and an activity whose thread this phone cannot tell is left to time out by itself.
    private static func chatOpened(chatID: String?, botID: String?) {
        guard let chatID, !chatID.isEmpty else { return }
        opened.formUnion(LiveActivities.shared.dismiss { thread(of: $0) == chatID })
        for run in live.values where run.chatID == chatID {
            opened.insert(run.turnID)
        }
    }

    /// The chat or bot thread an activity follows, or nil when this phone cannot tell.
    private static func thread(of attributes: KairosActivityAttributes) -> String? {
        if let thread = threads[attributes.id] { return thread }
        // A model chat's card links to the chat itself; a bot's links only to the bot.
        if let url = URL(string: attributes.link), case .chat(let chatID)? = NativeLink(url: url) { return chatID }
        return nil
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
        if LiveActivities.shared.running[run.turnID] == nil, let started = ChatStore.shared.runs[run.chatID]?.startedAt {
            // The desktop's own start time, so the timer is true from the first frame.
            state.startedAt = started
        }
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

    private static func isKip(_ run: ConnectionSeam.RunInfo) -> Bool {
        guard let botID = run.botID else { return false }
        return ChatStore.shared.kip?.id == botID
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
        if let seen = accountGeneration, seen != store.generation {
            // Unpaired, or paired with another desktop: nothing of the last account may show or be tapped.
            live = [:]
            steps = [:]
            lastEnded = nil
        }
        accountGeneration = store.generation
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
                progress: nil, step: run.step, link: link(run), botID: run.botID, isKip: isKip(run),
                waiting: run.waitingOnPerson, startedAt: store.runs[run.chatID]?.startedAt,
                previousStep: steps[run.turnID]?.before)
        }
        if let ended = lastEnded, Date() < ended.at.addingTimeInterval(WidgetSnapshot.Ended.shownFor) {
            snapshot.ended = ended
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
