import Foundation

/// What became of an answer or a decline the phone sent for a ring.
nonisolated enum RingReply: Equatable, Sendable {
    /// Not paired: there is no desktop to tell, and the sample call goes on as before.
    case sample
    /// The desktop took it. For an answer, the bot it named in its reply and the conversation the call belongs to
    /// (any may be missing).
    case sent(botID: String?, botName: String?, chatID: String?)
    /// The ring had already ended on the desktop: "answered" (somewhere else), "declined" or "expired".
    case ended(String)
    /// It could not be sent before the ring ran out (signed out, or the desktop never answered).
    case failed
}

/// The seam between the native layer (notifications, calls, Live Activities) and the desktop connection.
/// The Native team calls these; the Home and chats team's connection sets them once a desktop is paired.
/// Until then they do nothing, so the app works on sample data.
enum PushBridge {
    /// Send this phone's push tokens to the desktop (`POST /api/phone/push/register`).
    static var registerTokens: (_ apns: String, _ voip: String?) async -> Void = { _, _ in }
    /// The person changed what a notification may say: send the registration again with the new level.
    static var detailChanged: () async -> Void = {}
    /// Send a Live Activity's push token to the desktop (`POST /api/phone/push/activity`).
    static var registerActivity: (_ activityID: String, _ kind: String, _ token: String) async -> Void = { _, _, _ in }
    /// Answer an approval or a question from a notification action (`POST /api/permissions/{id}/answer`).
    static var answer: (_ requestID: String, _ choice: String, _ text: String?) async -> Void = { _, _, _ in }
    /// Answer or decline a ring (`POST /api/rings/{id}/answer` or `/decline`). Sent once; when the connection
    /// is not up yet it is started, and the send waits for it until `deadline` (the ring's end).
    static var ring: (_ ringID: String, _ answer: Bool, _ deadline: Date) async -> RingReply = { _, _, _ in .sample }
    /// Where a ring stands on the desktop (`GET /api/rings/{id}`): "ringing", "answered", "declined" or
    /// "expired". nil when it could not be read.
    static var ringState: (_ ringID: String) async -> String? = { _ in nil }
    /// A desktop is paired and the phone has a token for it.
    static var isPaired: () -> Bool = { false }
    /// The saved pairing cannot be read yet (a ring launched the app before the first unlock after a restart).
    /// Only a paired phone gets rings, so a ring in this state is treated as paired.
    static var awaitingUnlock: () -> Bool = { false }
    /// One of the paired desktop's bots, when the phone already has it.
    static var liveBot: (_ botID: String) -> Bot? = { _ in nil }
}
