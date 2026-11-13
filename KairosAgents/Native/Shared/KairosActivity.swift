import ActivityKit
import Foundation

/// The kinds of live work the phone shows on the Lock Screen and in the Dynamic Island (brief section 5).
nonisolated enum ActivityKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// A long chat turn: "Your reply is ready" when it ends.
    case reply
    /// A background task or a routine run.
    case task
    /// A bot team's cycle (the Content team: research, script, render, post).
    case team
    /// A video rendering and uploading to a channel.
    case render
    /// A Forge session building or testing.
    case forge
    /// A call with a bot.
    case call

    var label: String {
        switch self {
        case .reply: "Reply"
        case .task: "Background task"
        case .team: "Team cycle"
        case .render: "Render and upload"
        case .forge: "Forge"
        case .call: "Call"
        }
    }

    /// The action word on the Open button.
    var openLabel: String {
        switch self {
        case .reply: "Open chat"
        case .task: "Open"
        case .team: "Open team"
        case .render: "Open Studio"
        case .forge: "Open session"
        case .call: "Open call"
        }
    }

    var symbol: String {
        switch self {
        case .reply: "text.bubble"
        case .task: "clock.arrow.circlepath"
        case .team: "person.3"
        case .render: "film"
        case .forge: "hammer"
        case .call: "phone.fill"
        }
    }
}

nonisolated enum ActivityPhase: String, Codable, Hashable, Sendable {
    case running, waiting, done, failed, stopped

    var ended: Bool { self == .done || self == .failed || self == .stopped }
}

/// A sub-agent chip: "Scout: finding sources".
nonisolated struct ActivityHelper: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var colorHex: UInt32
    var doing: String
    var id: String { name }
}

nonisolated struct KairosActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var phase: ActivityPhase = .running
        /// What is happening now, in a few words: "Reading your notes".
        var step: String
        /// Where the result goes, or why it could not finish: "Saving to Library".
        var detail: String = ""
        /// 0 to 1 when the work knows how far along it is.
        var progress: Double? = nil
        /// For staged work (team, render, forge): which stage is running.
        var stage: Int = 0
        var helpers: [ActivityHelper] = []
        var startedAt: Date = .now
        /// Calls only.
        var muted: Bool = false
        /// The step before this one, drawn dimmed above it as the line moves on. Set by the phone.
        var previous: String? = nil
        /// Set only by the extension when the activity went stale: drawn as not connected.
        var stale: Bool? = nil
    }

    /// The run, ring or session id the desktop knows it by.
    var id: String
    var kind: ActivityKind
    /// The chat or job title. Hidden when the person turns on Private.
    var title: String
    var botID: String
    var botName: String
    /// nil is Kip's own ink body; a value is the bot's pastel.
    var botColor: UInt32? = nil
    var botShape: String = "round"
    /// Named stages for team, render and forge work.
    var stages: [String] = []
    /// Where tapping the activity goes.
    var link: String

    var url: URL { URL(string: link) ?? NativeLink.home.url }
}

extension KairosActivityAttributes.ContentState {
    /// The state language every surface shares.
    var mood: BotMood { BotMood(phase, stale: stale == true) }

    /// Words for the end states, matching the reference: "Done: ..." and "Couldn't finish: ...".
    func headline(for attributes: KairosActivityAttributes, hidingTitles: Bool) -> String {
        let title = hidingTitles ? attributes.kind.label : attributes.title
        switch phase {
        case .done:
            switch attributes.kind {
            case .reply: return "Your reply is ready"
            case .call: return "Call ended"
            case .render: return "Posted: " + title
            default: return "Done: " + title
            }
        case .failed: return detail.isEmpty ? "Couldn't finish" : "Couldn't finish: " + detail
        case .stopped: return "Stopped"
        case .waiting: return "\(attributes.botName) needs you"
        case .running: return title
        }
    }
}
