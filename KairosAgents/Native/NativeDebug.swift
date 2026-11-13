import SwiftUI

/// Debug views for the Native area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView native.<name>` (see docs/DEV-GUIDE.md).
enum NativeDebug {
    static func view(_ name: String) -> AnyView? {
        if name.hasPrefix("activity-"), let kind = ActivityKind(rawValue: String(name.dropFirst("activity-".count))) {
            return AnyView(ActivityKindPage(kind: kind))
        }
        if let view = stateView(name) { return view }
        switch name {
        case "activity-ends": return AnyView(ActivityEndsPage())
        case "activity-private": return AnyView(ActivityPrivatePage())
        case "widgets-small":
            return AnyView(WidgetGridPage(title: "Home Screen widgets, small", kinds: [.needsYou, .running, .team, .posts, .spend, .nextEvent], family: .systemSmall))
        case "widgets-small-2":
            return AnyView(WidgetGridPage(title: "Home Screen widgets, small", kinds: [.usage, .desktop, .quickActions], family: .systemSmall))
        case "widgets-medium":
            return AnyView(WidgetGridPage(title: "Home Screen widgets, medium", kinds: [.needsYou, .running, .team, .posts], family: .systemMedium))
        case "widgets-medium-2":
            return AnyView(WidgetGridPage(title: "Home Screen widgets, medium", kinds: [.usage, .desktop, .quickActions], family: .systemMedium))
        case "widgets-large":
            return AnyView(WidgetGridPage(title: "Home Screen widget, large", kinds: [.running], family: .systemLarge))
        case "widgets-lock": return AnyView(LockWidgetsPage())
        case "notifications": return AnyView(NoticesPage(title: "Notifications", notices: Array(NoticeSamples.all[0..<6])))
        case "notifications-2": return AnyView(NoticesPage(title: "Notifications", notices: Array(NoticeSamples.all[6..<12])))
        case "notifications-3": return AnyView(NoticesPage(title: "Notifications", notices: Array(NoticeSamples.all[12...])))
        case "notification-actions": return AnyView(NoticeActionsPage())
        case "settings": return AnyView(NotificationSettingsScreen())
        case "call": return AnyView(CallView(bot: SampleData.kip))
        case "call-pill": return AnyView(CallPillPage())
        default: return nil
        }
    }

    /// One picture per state: `activity-state-<state>`, `widgets-<small|medium|large|lock>-<state>`,
    /// where the state is working, needs, done, failed, idle or offline.
    private static func stateView(_ name: String) -> AnyView? {
        let parts = name.split(separator: "-").map(String.init)
        guard parts.count == 3, let mood = BotMood(galleryName: parts[2]) else { return nil }
        switch (parts[0], parts[1]) {
        case ("activity", "state"): return AnyView(ActivityStatePage(mood: mood))
        case ("widgets", "small"): return AnyView(WidgetStatePage(family: .systemSmall, mood: mood))
        case ("widgets", "medium"): return AnyView(WidgetStatePage(family: .systemMedium, mood: mood))
        case ("widgets", "large"): return AnyView(WidgetStatePage(family: .systemLarge, mood: mood))
        case ("widgets", "lock"): return AnyView(LockWidgetStatePage(mood: mood))
        default: return nil
        }
    }
}
