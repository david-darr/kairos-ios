import Foundation
import Intents
import SwiftUI
import UIKit
import UserNotifications

/// Every kind of notification the phone shows, one per row of the brief's catalogue.
nonisolated enum NoticeKind: String, CaseIterable, Codable, Hashable, Sendable {
    case approval, question, replyReady, workDone, workFailed, teamUpdate, posted, needsTap
    case channelWarning, spendNear, spendCap, spendUnknown, event, morningBrief, forgeWaiting, usage, missedCall

    var category: String { "kairos." + rawValue }

    /// The setting row this kind falls under (Notifications settings and the desktop's device preferences).
    var group: NoticeGroup {
        switch self {
        case .approval, .question: .needsYou
        case .replyReady: .replies
        case .workDone, .workFailed: .work
        case .teamUpdate, .posted, .needsTap, .channelWarning: .content
        case .spendNear, .spendCap, .spendUnknown: .spend
        case .event, .morningBrief: .calendar
        case .forgeWaiting: .forge
        case .usage: .usage
        case .missedCall: .calls
        }
    }

    /// Time-sensitive breaks through Focus for things that will not wait.
    var level: UNNotificationInterruptionLevel {
        switch self {
        case .approval, .question, .channelWarning, .spendCap, .event: .timeSensitive
        case .morningBrief, .usage: .passive
        default: .active
        }
    }

    /// Kinds that come from a bot read as a message from that bot (communication style).
    var fromBot: Bool {
        switch self {
        case .approval, .question, .teamUpdate, .missedCall, .morningBrief: true
        default: false
        }
    }
}

/// The rows in Notifications settings. Raw values match the desktop's device preference names where one exists.
nonisolated enum NoticeGroup: String, CaseIterable, Codable, Hashable, Sendable {
    case needsYou = "bot_needs_you", replies = "completed", work = "bot_results", content = "content"
    case spend = "spend", calendar = "calendar", forge = "forge", usage = "usage", calls = "bot_calls"

    var title: String {
        switch self {
        case .needsYou: "A bot needs you"
        case .replies: "Replies ready"
        case .work: "Tasks and routines"
        case .content: "Team and posts"
        case .spend: "Spend"
        case .calendar: "Events and morning brief"
        case .forge: "Forge sessions"
        case .usage: "Model usage"
        case .calls: "Calls from bots"
        }
    }

    var symbol: String {
        switch self {
        case .needsYou: "hand.raised"
        case .replies: "text.bubble"
        case .work: "clock.arrow.circlepath"
        case .content: "film.stack"
        case .spend: "creditcard"
        case .calendar: "calendar"
        case .forge: "hammer"
        case .usage: "gauge.with.dots.needle.33percent"
        case .calls: "phone"
        }
    }

    var isOn: Bool {
        get { NativeSettings.store.object(forKey: "notice." + rawValue) as? Bool ?? true }
        nonmutating set { NativeSettings.store.set(newValue, forKey: "notice." + rawValue) }
    }
}

/// One notification, before it is turned into iOS content. The desktop's push carries the same fields
/// (see docs/coverage/native.md, "Push payload").
nonisolated struct Notice: Hashable, Sendable {
    var kind: NoticeKind
    var botID: String = "kip"
    var botName: String = "Kip"
    /// The chat, job, channel or event title. Hidden when the person turns on Private.
    var title: String = ""
    /// Words only shown when the person opts in to previews.
    var preview: String = ""
    /// Numbers and names that are not message content: a platform, a percent, a time.
    var fact: String = ""
    var link: NativeLink = .home
    var requestID: String = ""
    var activityID: String = ""
    var activityKind: String = ""
    /// The gallery draws each privacy level; real notices follow the person's setting.
    var detailOverride: NoticeDetail? = nil

    var detail: NoticeDetail { detailOverride ?? NativeSettings.detail }

    /// What kind. Never the message itself, and never the sender's name: the title already says who.
    var headline: String {
        let named = detail == .hideTitles || title.isEmpty
        switch kind {
        case .approval: return "Wants your approval"
        case .question: return "Is waiting for your answer"
        case .replyReady: return "Your reply is ready"
        case .workDone: return "Finished a task"
        case .workFailed: return "Couldn't finish"
        case .teamUpdate: return "Sent the team's update"
        case .posted: return fact.isEmpty ? "Your post is up" : "Posted to \(fact)"
        case .needsTap: return fact.isEmpty ? "A TikTok post needs your tap" : fact
        case .channelWarning: return "A channel is paused"
        case .spendNear: return "Spend is near your cap"
        case .spendCap: return "Spend reached your cap"
        case .spendUnknown: return "Some spend is unknown"
        case .event: return named ? "An event is coming up" : title
        case .morningBrief: return "Your morning brief is ready"
        case .forgeWaiting: return "Session waiting for you"
        case .usage: return "\(fact.isEmpty ? "A provider" : fact) is near its limit"
        case .missedCall: return "Missed call"
        }
    }

    /// The line under the headline: what to do next.
    var hint: String {
        switch kind {
        case .approval: "Allow, deny or reply from here."
        case .question: "Tap to answer in Kairos."
        case .replyReady: "Tap to open the chat."
        case .workDone: "Tap to see what it made."
        case .workFailed: "Tap to see why, or try again."
        case .teamUpdate: "One update for the whole cycle. Tap to read it."
        case .posted: "Tap to see it in Studio."
        case .needsTap: "TikTok asks you to post it yourself."
        case .channelWarning: "Posting stopped. Tap to see what to do."
        case .spendNear: fact.isEmpty ? "Tap to see what is spending." : "\(fact) of this month's cap is used."
        case .spendCap: "Paid work is paused until you raise the cap."
        case .spendUnknown: "A provider did not report its cost. Tap to check."
        case .event: fact.isEmpty ? "Tap to open your calendar." : "Starts \(fact)."
        case .morningBrief: "Kip has today's plan."
        case .forgeWaiting: "A Forge session needs a look before it goes on."
        case .usage: "Tap to see your usage."
        case .missedCall: "Tap to call back."
        }
    }

    var subtitle: String {
        guard detail != .hideTitles, !title.isEmpty else { return "" }
        switch kind {
        case .event, .channelWarning, .spendNear, .spendCap, .spendUnknown, .usage: return ""
        default: return title
        }
    }

    var body: String {
        if detail == .preview, !preview.isEmpty { return preview }
        return hint
    }
}

/// Registers categories, asks for permission at the right moment, builds and handles notifications.
@Observable
final class NativeNotifications {
    static let shared = NativeNotifications()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    private let relay = NotificationRelay()

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = relay
        center.setNotificationCategories(Self.categories)
        Task { await refresh() }
    }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
        if status == .authorized || status == .provisional || status == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Ask once the person has a reason to say yes: after pairing, when they start background work,
    /// or from the explanation card. Never on first launch.
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings])) ?? false
        await refresh()
        return granted
    }

    // MARK: Categories and actions

    static let approveAction = "kairos.approve"
    static let denyAction = "kairos.deny"
    static let replyAction = "kairos.reply"
    static let openAction = "kairos.open"
    static let retryAction = "kairos.retry"
    static let snoozeAction = "kairos.snooze"
    static let callBackAction = "kairos.callback"

    static var categories: Set<UNNotificationCategory> {
        let approve = UNNotificationAction(identifier: approveAction, title: "Allow", options: [.authenticationRequired],
                                           icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let deny = UNNotificationAction(identifier: denyAction, title: "Deny", options: [.destructive, .authenticationRequired],
                                        icon: UNNotificationActionIcon(systemImageName: "xmark"))
        let reply = UNTextInputNotificationAction(identifier: replyAction, title: "Reply", options: [.authenticationRequired],
                                                  icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Your answer")
        let open = UNNotificationAction(identifier: openAction, title: "Open", options: [.foreground],
                                        icon: UNNotificationActionIcon(systemImageName: "arrow.up.forward.app"))
        let retry = UNNotificationAction(identifier: retryAction, title: "Try again", options: [.authenticationRequired, .foreground],
                                         icon: UNNotificationActionIcon(systemImageName: "arrow.clockwise"))
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Remind me in 10 minutes", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "clock"))
        let callBack = UNNotificationAction(identifier: callBackAction, title: "Call back", options: [.foreground],
                                            icon: UNNotificationActionIcon(systemImageName: "phone.fill"))

        return Set(NoticeKind.allCases.map { kind in
            let actions: [UNNotificationAction]
            switch kind {
            case .approval: actions = [approve, deny, reply]
            case .question: actions = [reply, open]
            case .workFailed: actions = [open, retry]
            case .event: actions = [open, snooze]
            case .missedCall: actions = [callBack]
            default: actions = [open]
            }
            return UNNotificationCategory(identifier: kind.category, actions: actions,
                                          intentIdentifiers: kind.fromBot ? [INSendMessageIntentIdentifier] : [],
                                          hiddenPreviewsBodyPlaceholder: "Kairos", options: [.hiddenPreviewsShowTitle])
        })
    }

    // MARK: Building content

    /// The iOS content for a notice, with the privacy rules applied. Bot notices read as a message from that bot.
    func content(for notice: Notice) async -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notice.headline
        content.subtitle = notice.subtitle
        content.body = notice.body
        content.categoryIdentifier = notice.kind.category
        content.interruptionLevel = notice.kind.level
        content.relevanceScore = notice.kind.level == .timeSensitive ? 1 : 0.4
        content.threadIdentifier = notice.kind.fromBot ? "bot-" + notice.botID : notice.kind.group.rawValue
        content.targetContentIdentifier = notice.link.url.absoluteString
        content.sound = notice.kind.level == .passive ? nil : .default
        content.userInfo = [
            "link": notice.link.url.absoluteString,
            "request_id": notice.requestID,
            "activity_id": notice.activityID,
            "activity_kind": notice.activityKind,
            "kind": notice.kind.rawValue,
        ]
        guard notice.kind.fromBot else { return content }
        return (try? content.updating(from: messageIntent(for: notice))) ?? content
    }

    /// Show a notice now (used for work the app watches itself, and by the gallery's "Send a test").
    func post(_ notice: Notice, after seconds: TimeInterval = 0.5, id: String = UUID().uuidString) async {
        guard notice.kind.group.isOn else { return }
        let content = await content(for: notice)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.5, seconds), repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func messageIntent(for notice: Notice) -> INSendMessageIntent {
        let bot = INPerson(personHandle: INPersonHandle(value: "kairos-bot-" + notice.botID, type: .unknown),
                           nameComponents: nil, displayName: notice.botName, image: faceImage(notice.botID),
                           contactIdentifier: nil, customIdentifier: notice.botID)
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: nil,
                                         speakableGroupName: nil, conversationIdentifier: "bot-" + notice.botID,
                                         serviceName: "Kairos", sender: bot, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)
        return intent
    }

    /// The bot's own face as the notification picture (Kip from `Mascot`, never redrawn).
    private func faceImage(_ botID: String) -> INImage? {
        let bot = SampleData.bot(botID)
        let renderer = ImageRenderer(content:
            BotFace(bot: bot, size: 120, stage: Palette.night)
                .frame(width: 160, height: 160)
                .background(Palette.night)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { return nil }
        return INImage(imageData: data)
    }

    // MARK: Handling a tap or an action

    func handle(action: String, text: String?, info: [String: String]) async {
        let link = info["link"].flatMap(URL.init(string:)).flatMap(NativeLink.init(url:)) ?? .home
        let request = info["request_id"] ?? ""
        // An answer needs the request it answers; without one, open the approval or chat instead.
        if request.isEmpty, [Self.approveAction, Self.denyAction, Self.replyAction].contains(action) {
            NativeLinks.shared.open(link)
            return
        }
        switch action {
        case Self.approveAction:
            await PushBridge.answer(request, "once", nil)
        case Self.denyAction:
            await PushBridge.answer(request, "reject", nil)
        case Self.replyAction:
            let words = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty { await PushBridge.answer(request, "reply", words) }
        case Self.retryAction:
            // Retry only works for a turn the phone watched; otherwise open the chat so the button still does something.
            let turn = info["activity_id"] ?? ""
            if !turn.isEmpty, await NativeBridge.canRetry(turn) {
                await NativeBridge.retry(turn, info["activity_kind"] ?? "")
            } else {
                NativeLinks.shared.open(link)
            }
        case Self.snoozeAction:
            if let kind = info["kind"].flatMap(NoticeKind.init(rawValue:)) {
                await post(Notice(kind: kind, link: link), after: 600)
            }
        case Self.callBackAction:
            NativeLinks.shared.open(.call(link.botID ?? "kip"))
        default:
            NativeLinks.shared.open(link)
        }
    }
}

private extension NativeLink {
    var botID: String? {
        switch self {
        case .bot(let id), .call(let id), .ask(let id): id
        case .approval(_, let id), .ring(_, let id): id
        default: nil
        }
    }
}

/// The notification centre calls in on its own queue; this hops to the main actor.
nonisolated final class NotificationRelay: NSObject, UNUserNotificationCenterDelegate {
    /// iOS asks this only while the app is in front. When it is open and on screen, show nothing:
    /// no banner, no sound. The app itself shows what needs the person (Home, the card in the chat).
    /// The completion handler form, answered on the main actor, for the same reason as below.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let onScreen = UIApplication.shared.applicationState == .active
            completionHandler(onScreen ? [] : [.banner, .list, .sound])
        }
    }

    /// The completion handler form, on purpose. iOS requires "done" to be said on the main thread.
    /// The async form of this method says it from whichever thread the function ends on, and iOS
    /// ends the app for that: every tap on a notification crashed on a real phone.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        var info: [String: String] = [:]
        for (key, value) in response.notification.request.content.userInfo {
            if let key = key as? String, let value = value as? String { info[key] = value }
        }
        let snapshot = info
        Task { @MainActor in
            await NativeNotifications.shared.handle(action: action, text: text, info: snapshot)
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        Task { @MainActor in NativeLinks.shared.showSettings = true }
    }
}
