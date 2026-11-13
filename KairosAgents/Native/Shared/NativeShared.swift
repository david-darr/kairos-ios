import Foundation

/// The identifiers both the app and the widget extension share. They are App IDs, not secrets.
nonisolated enum NativeIDs {
    static let appGroup = "group.app.kairos-agents.mobile"
    static let snapshotKey = "widgetSnapshot.v1"
}

/// How much a notification, a Live Activity or a widget may say on a locked phone.
/// Generic is the default (who and what kind, plus the chat title). Private also hides titles.
/// Preview would add a short line of the message itself. It is not offered yet: the relay never
/// reads message text, so it cannot be delivered. A stored preview value reads as generic.
nonisolated enum NoticeDetail: String, CaseIterable, Codable, Hashable, Sendable {
    case generic, hideTitles, preview

    var title: String {
        switch self {
        case .generic: "Who and what kind"
        case .hideTitles: "Private"
        case .preview: "Show a preview"
        }
    }

    var about: String {
        switch self {
        case .generic: "Says which bot and what happened, with the chat's title. Never the message."
        case .hideTitles: "Hides chat titles too. A Live Activity shows only the bot and the step."
        case .preview: "Adds one short line of the message. Anyone who sees your screen can read it."
        }
    }

    /// The levels the settings screen lists. Preview stays out until it can be delivered.
    static let offered: [NoticeDetail] = [.generic, .hideTitles]
}

/// Settings the extension needs too, kept in the App Group so both read the same values.
nonisolated enum NativeSettings {
    static var store: UserDefaults { UserDefaults(suiteName: NativeIDs.appGroup) ?? .standard }

    static var detail: NoticeDetail {
        get {
            let stored = NoticeDetail(rawValue: store.string(forKey: "noticeDetail") ?? "") ?? .generic
            return NoticeDetail.offered.contains(stored) ? stored : .generic
        }
        set { store.set(newValue.rawValue, forKey: "noticeDetail") }
    }

    static var hidesTitles: Bool { detail == .hideTitles }

    static var liveActivitiesOn: Bool {
        get { store.object(forKey: "liveActivitiesOn") as? Bool ?? true }
        set { store.set(newValue, forKey: "liveActivitiesOn") }
    }

    static var widgetsShareData: Bool {
        get { store.object(forKey: "widgetsShareData") as? Bool ?? true }
        set { store.set(newValue, forKey: "widgetsShareData") }
    }
}

/// What the native layer asks of the desktop beyond `PushBridge` (whose shape is fixed).
/// The connection fills these in once a desktop is paired; until then they do nothing.
/// Requested routes: `POST /api/chat/live/stop` for Stop, a retry of the same turn for Retry.
nonisolated enum NativeBridge {
    nonisolated(unsafe) static var stop: @Sendable (_ activityID: String, _ kind: String) async -> Void = { _, _ in }
    nonisolated(unsafe) static var retry: @Sendable (_ activityID: String, _ kind: String) async -> Void = { _, _ in }
    /// Whether Retry can resend this turn from here (the phone watched it). When not, a notification opens its chat.
    nonisolated(unsafe) static var canRetry: @Sendable (_ activityID: String) async -> Bool = { _ in false }
}
