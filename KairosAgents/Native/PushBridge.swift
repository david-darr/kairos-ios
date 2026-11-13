import Foundation

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
    /// Answer or decline a ring (`POST /api/rings/{id}/answer` or `/decline`).
    static var ring: (_ ringID: String, _ answer: Bool) async -> Void = { _, _ in }
}
