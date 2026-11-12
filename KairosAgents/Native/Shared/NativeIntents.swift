import AppIntents
import Foundation

// Buttons on Live Activities and widgets. A LiveActivityIntent runs in the app's process, so the
// app-only work sits behind `KAIROS_EXTENSION` (set only for the widget extension target).

nonisolated struct StopWorkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop this work"
    static let description = IntentDescription("Stops the work this Live Activity is following.")

    @Parameter(title: "Activity") var activityID: String
    @Parameter(title: "Kind") var kind: String

    init() {}
    init(activityID: String, kind: ActivityKind) {
        self.activityID = activityID
        self.kind = kind.rawValue
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await NativeBridge.stop(activityID, kind)
        #if !KAIROS_EXTENSION
        await LiveActivities.shared.markStopped(activityID)
        #endif
        return .result()
    }
}

nonisolated struct RetryWorkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Try again"
    static let description = IntentDescription("Asks your desktop to run the work again.")

    @Parameter(title: "Activity") var activityID: String
    @Parameter(title: "Kind") var kind: String

    init() {}
    init(activityID: String, kind: ActivityKind) {
        self.activityID = activityID
        self.kind = kind.rawValue
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await NativeBridge.retry(activityID, kind)
        #if !KAIROS_EXTENSION
        await LiveActivities.shared.markRetrying(activityID)
        #endif
        return .result()
    }
}

nonisolated struct MuteCallIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mute the call"
    static let description = IntentDescription("Turns your microphone on or off during a call.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !KAIROS_EXTENSION
        CallCenter.shared.toggleMute()
        #endif
        return .result()
    }
}

nonisolated struct EndCallIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End the call"
    static let description = IntentDescription("Hangs up the call with your bot.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !KAIROS_EXTENSION
        CallCenter.shared.endCall()
        #endif
        return .result()
    }
}
