import Foundation

/// Every place a notification, a Live Activity or a widget can open, as one deep-link type.
/// URLs look like `kairos-agents://bot/scout` or `kairos-agents://approval/req_1?bot=scout`.
/// Compiled into the app and the widget extension.
nonisolated enum NativeLink: Hashable, Sendable {
    /// A model chat by its conversation id.
    case chat(String)
    /// A bot's conversation.
    case bot(String)
    /// An approval or a question waiting in a bot's inbox (or a chat's permission request).
    case approval(requestID: String, botID: String)
    /// A ring: opens the call screen once answered.
    case ring(ringID: String, botID: String)
    /// Start a call with a bot (the "Call Kip" quick action).
    case call(String)
    /// Ask a bot something new (the "Ask Kip" quick action).
    case ask(String)
    case newChat
    /// One of the areas that live in exactly one place (vault, calendar, studio, forge ...).
    case area(String)
    /// A tab the person added (CRM and the like), by its title.
    case addedTab(String)
    /// Home, where usage, spend and the glance row live.
    case home
    case desktop
    /// Every bot and team (the team widget when it cannot know which team).
    case allBots

    /// The id a widget or a push uses for Kip when it cannot know the desktop's own id.
    /// On a paired phone it means the paired desktop's Kip, found when the link is followed, unless the desktop
    /// has a bot whose own id is "kip" (desktop ids are generated, so that is not expected).
    static let kip = "kip"

    static let scheme = "kairos-agents"

    var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .chat(let id): parts.host = "chat"; parts.path = "/" + id
        case .bot(let id): parts.host = "bot"; parts.path = "/" + id
        case .approval(let request, let bot):
            parts.host = "approval"; parts.path = "/" + request
            parts.queryItems = [URLQueryItem(name: "bot", value: bot)]
        case .ring(let ring, let bot):
            parts.host = "ring"; parts.path = "/" + ring
            parts.queryItems = [URLQueryItem(name: "bot", value: bot)]
        case .call(let bot): parts.host = "call"; parts.path = "/" + bot
        case .ask(let bot): parts.host = "ask"; parts.path = "/" + bot
        case .newChat: parts.host = "new-chat"
        case .area(let area): parts.host = "area"; parts.path = "/" + area
        case .addedTab(let title): parts.host = "tab"; parts.path = "/" + title
        case .home: parts.host = "home"
        case .desktop: parts.host = "desktop"
        case .allBots: parts.host = "bots"
        }
        return parts.url ?? URL(string: "kairos-agents://home")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host else { return nil }
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let value = url.path.split(separator: "/").first.map(String.init) ?? ""
        let bot = parts?.queryItems?.first { $0.name == "bot" }?.value ?? "kip"
        // Ids come from pushes and widgets: keep them short and plain.
        let safe = value.count <= 128 && value.allSatisfy { $0.isLetter || $0.isNumber || "-_ .".contains($0) }
        guard safe else { return nil }
        switch host {
        case "chat" where !value.isEmpty: self = .chat(value)
        case "bot" where !value.isEmpty: self = .bot(value)
        case "approval" where !value.isEmpty: self = .approval(requestID: value, botID: bot)
        case "ring" where !value.isEmpty: self = .ring(ringID: value, botID: bot)
        case "call": self = .call(value.isEmpty ? "kip" : value)
        case "ask": self = .ask(value.isEmpty ? "kip" : value)
        case "new-chat": self = .newChat
        case "area" where !value.isEmpty: self = .area(value)
        case "tab" where !value.isEmpty: self = .addedTab(value)
        case "home": self = .home
        case "desktop": self = .desktop
        case "bots": self = .allBots
        default: return nil
        }
    }
}
