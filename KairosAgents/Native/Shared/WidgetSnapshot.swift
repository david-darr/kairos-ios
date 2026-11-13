import Foundation

/// What the widgets show. The app writes it to the App Group; the widget extension only reads it.
/// No message text, no tokens, no addresses: just counts, titles and numbers.
nonisolated struct WidgetSnapshot: Codable, Hashable, Sendable {
    nonisolated struct Waiting: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var botID: String
        var botName: String
        var botColor: UInt32?
        var botShape: String = "round"
        /// "Question" or "Approval".
        var kind: String
        var link: String
    }

    nonisolated struct Running: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var title: String
        var botName: String
        var botColor: UInt32?
        var botShape: String = "round"
        var progress: Double?
        var step: String
        var link: String
        // Added for state and motion. Optional so a snapshot written by an older build still reads.
        var botID: String? = nil
        /// True when this is the paired desktop's Kip (the quick actions widget follows Kip's own state).
        var isKip: Bool? = nil
        /// The bot is waiting on the person (an approval or a question).
        var waiting: Bool? = nil
        /// When the desktop started the turn; drawn as timer text that ticks by itself.
        var startedAt: Date? = nil
        /// The step before this one, drawn dimmed above it.
        var previousStep: String? = nil
    }

    /// The newest piece of work that finished or failed, shown until it is 30 minutes old.
    nonisolated struct Ended: Codable, Hashable, Sendable {
        var title: String
        var botName: String
        var botColor: UInt32?
        var botShape: String = "round"
        var failed: Bool
        var at: Date
        var link: String
        var isKip: Bool? = nil

        /// How long an end card stays on a widget.
        static let shownFor: TimeInterval = 30 * 60
    }

    nonisolated struct Team: Codable, Hashable, Sendable {
        /// The team's own id on the desktop, so a tap opens it. nil when not known: the tap opens All bots.
        var id: String? = nil
        var name: String
        var stages: [String]
        var stage: Int
        var note: String
        var memberColors: [UInt32]
        var paused: Bool = false
    }

    nonisolated struct Post: Codable, Hashable, Sendable {
        var title: String
        var platform: String
        var views: Int
        var likes: Int
        var comments: Int
        var postedAt: Date
        var needsTap: Int = 0
    }

    nonisolated struct Spend: Codable, Hashable, Sendable {
        var spent: Double
        var cap: Double
        var currency: String = "$"
        var unknown: Bool = false
    }

    nonisolated struct Event: Codable, Hashable, Sendable {
        var title: String
        var startsAt: Date
        var allDay: Bool
    }

    nonisolated struct Usage: Codable, Hashable, Sendable, Identifiable {
        var provider: String
        var percent: Int
        var resetsAt: Date?
        var id: String { provider }
    }

    nonisolated struct Session: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var title: String
        var project: String
        var added: Int
        var removed: Int
        var waiting: Bool
    }

    nonisolated struct Desktop: Codable, Hashable, Sendable {
        var name: String
        var online: Bool
        var sessions: [Session]
    }

    nonisolated struct Pinned: Codable, Hashable, Sendable {
        var title: String
        var symbol: String
    }

    var updatedAt: Date
    var connected: Bool
    var needsYou: [Waiting] = []
    var running: [Running] = []
    var team: Team?
    var post: Post?
    var spend: Spend?
    var nextEvent: Event?
    var usage: [Usage] = []
    var desktop: Desktop?
    var pinned: Pinned?
    var ended: Ended? = nil

    /// The snapshot as it should read at `date`: an end card older than 30 minutes is gone.
    func shown(at date: Date) -> WidgetSnapshot {
        guard let ended, date >= ended.at.addingTimeInterval(Ended.shownFor) else { return self }
        var copy = self
        copy.ended = nil
        return copy
    }

    static let empty = WidgetSnapshot(updatedAt: .distantPast, connected: false)
}

nonisolated enum WidgetSnapshotStore {
    static func read() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: NativeIDs.appGroup),
              let data = defaults.data(forKey: NativeIDs.snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: NativeIDs.appGroup)?.set(data, forKey: NativeIDs.snapshotKey)
    }

    static func clear() {
        UserDefaults(suiteName: NativeIDs.appGroup)?.removeObject(forKey: NativeIDs.snapshotKey)
    }
}
