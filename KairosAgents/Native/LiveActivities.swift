import ActivityKit
import Foundation

/// Starts, updates and ends Live Activities, and sends each one's push token to the desktop
/// so it keeps updating while the app is closed.
@Observable
final class LiveActivities {
    static let shared = LiveActivities()

    typealias State = KairosActivityAttributes.ContentState

    private(set) var running: [String: KairosActivityAttributes.ContentState] = [:]
    @ObservationIgnored private var tokenTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var callActivityID: String?

    /// Off when the person turned them off, when iOS has them off, or in a build without the Info.plist key.
    var enabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true
            && NativeSettings.liveActivitiesOn && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Pick up activities that outlived the app, and listen for the push-to-start token.
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true else { return }
        for activity in Activity<KairosActivityAttributes>.activities {
            running[activity.attributes.id] = activity.content.state
            watchToken(activity)
        }
        Task {
            for await data in Activity<KairosActivityAttributes>.pushToStartTokenUpdates {
                await PushBridge.registerActivity("push-to-start", "start", Self.hex(data))
            }
        }
    }

    /// Follow a piece of work. Returns false when Live Activities are off.
    @discardableResult
    func begin(_ attributes: KairosActivityAttributes, _ state: State) -> Bool {
        guard enabled else { return false }
        if activity(attributes.id) != nil { update(attributes.id, state); return true }
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60), relevanceScore: relevance(attributes.kind)),
                pushType: .token
            )
            running[attributes.id] = state
            watchToken(activity)
            return true
        } catch {
            return false
        }
    }

    func update(_ id: String, _ state: State) {
        guard let activity = activity(id) else { return }
        var state = state
        // The step line moves on: the step it replaces stays, dimmed, above it.
        if let old = running[id], !old.step.isEmpty, old.step != state.step, state.phase == .running {
            state.previous = old.step
        }
        running[id] = state
        Task {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60),
                                                  relevanceScore: relevance(activity.attributes.kind)))
        }
    }

    /// End with the Done or Couldn't finish card, which leaves the Lock Screen on its own: five minutes
    /// for done or stopped, thirty for failed. The desktop's end push uses the same times.
    func finish(_ id: String, _ state: State) {
        guard let activity = activity(id) else { return }
        running[id] = nil
        tokenTasks[id]?.cancel()
        tokenTasks[id] = nil
        let linger: TimeInterval = state.phase == .failed ? 30 * 60 : 5 * 60
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(linger))) }
    }

    /// The person opened the chat or thread these activities follow (`matches` says which): they end and leave
    /// at once, running or done. A call's activity is never one of them. Answers the ids it ended.
    @discardableResult
    func dismiss(where matches: (KairosActivityAttributes) -> Bool) -> [String] {
        let found = Activity<KairosActivityAttributes>.activities.filter { $0.attributes.kind != .call && matches($0.attributes) }
        for activity in found {
            let id = activity.attributes.id
            running[id] = nil
            tokenTasks[id]?.cancel()
            tokenTasks[id] = nil
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        return found.map(\.attributes.id)
    }

    func markStopped(_ id: String) async {
        guard let activity = activity(id) else { return }
        var state = activity.content.state
        state.phase = .stopped
        finish(id, state)
    }

    func markRetrying(_ id: String) async {
        guard let activity = activity(id) else { return }
        var state = activity.content.state
        state.phase = .running
        state.step = "Trying again"
        state.detail = ""
        update(id, state)
    }

    // MARK: Calls

    func startCall(bot: Bot, ringID: String) {
        let attributes = KairosActivityAttributes(
            id: ringID, kind: .call, title: "Call with \(bot.name)", botID: bot.id, botName: bot.name,
            botColor: bot.isKip ? nil : bot.colorHex, botShape: bot.shape.rawValue, link: NativeLink.call(bot.id).url.absoluteString)
        if begin(attributes, State(step: "On a call", detail: "Kairos call", startedAt: .now)) { callActivityID = ringID }
    }

    func updateCall(muted: Bool) {
        guard let id = callActivityID, var state = running[id] else { return }
        state.muted = muted
        update(id, state)
    }

    func endCall() {
        guard let id = callActivityID, var state = running[id] else { return }
        callActivityID = nil
        state.phase = .done
        guard let activity = activity(id) else { return }
        running[id] = nil
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60))) }
    }

    // MARK: Pieces

    private func activity(_ id: String) -> Activity<KairosActivityAttributes>? {
        Activity<KairosActivityAttributes>.activities.first { $0.attributes.id == id }
    }

    private func watchToken(_ activity: Activity<KairosActivityAttributes>) {
        let id = activity.attributes.id
        let kind = activity.attributes.kind.rawValue
        tokenTasks[id]?.cancel()
        tokenTasks[id] = Task {
            for await data in activity.pushTokenUpdates {
                await PushBridge.registerActivity(id, kind, Self.hex(data))
            }
        }
    }

    /// When several run at once, the one that needs the person most leads the island.
    private func relevance(_ kind: ActivityKind) -> Double {
        switch kind {
        case .call: 100
        case .reply: 60
        case .forge: 50
        case .task: 40
        case .render: 30
        case .team: 20
        }
    }

    nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
