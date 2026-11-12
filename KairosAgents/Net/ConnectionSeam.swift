import Foundation

/// The seam between the desktop connection and the native layer (Live Activities, widgets, the
/// notification ask). The connection and the data store call these as things happen; the native layer
/// is connected to them where the two meet (see docs/coverage/chats.md, "Native glue").
/// Until then they do nothing, so the app works without the native layer.
enum ConnectionSeam {
    /// One running turn, as much as a Live Activity needs.
    nonisolated struct RunInfo: Hashable, Sendable {
        /// The chat or bot conversation (a session id on the desktop).
        var chatID: String
        /// The turn's id. Use it as the activity id; `stop` takes it back.
        var turnID: String
        var title: String
        /// Set when the turn belongs to a bot.
        var botID: String?
        var botName: String?
        /// The step in progress, in plain words ("Searching the first hardware store"), or "".
        var step: String
        /// "processing", "done", "failed" or "stopped".
        var status: String
        /// An approval or a question is waiting.
        var waitingOnPerson: Bool
        var error: String?
    }

    nonisolated struct Usage: Hashable, Sendable {
        var provider: String
        var percent: Int
    }

    /// The real Home numbers, for widgets.
    nonisolated struct HomeNumbers: Hashable, Sendable {
        var needsYou: Int
        var running: Int
        var usage: [Usage]
        /// "Fri · Report due", or nil.
        var nextEvent: String?
    }

    /// A turn started (`LiveActivities.shared.begin`).
    static var runBegan: (RunInfo) -> Void = { _ in }
    /// A step, an approval or a stop request changed a running turn (`LiveActivities.shared.update`).
    static var runChanged: (RunInfo) -> Void = { _ in }
    /// A turn ended: done, failed or stopped (`LiveActivities.shared.finish`).
    static var runEnded: (RunInfo) -> Void = { _ in }
    /// Home's numbers changed (`WidgetSync.publish`).
    static var homeChanged: (HomeNumbers) -> Void = { _ in }
    /// This phone was just paired: a good moment to ask for notifications (`NotificationAskCard`).
    static var paired: () -> Void = {}

    /// Stop a turn by its id, for `NativeBridge.stop`.
    static func stop(turnID: String) async {
        await ChatStore.shared.stopRun(turnID: turnID)
    }

    /// Send a chat's last question again, for `NativeBridge.retry`. `chatID` is `RunInfo.chatID`.
    static func retry(chatID: String) async {
        let chat = ChatStore.shared.modelChat(chatID)
        await chat.load()
        chat.retryLast()
    }
}
