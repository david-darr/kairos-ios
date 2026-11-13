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
    /// The sample data shown before pairing. Its times are made again for each moment it is drawn.
    var isSample: Bool? = nil
    /// Set only by `shown(at:)`, never written: the work in it is older than `freshFor`, so it is shown as
    /// last seen, with no timer and no "working".
    var stale: Bool? = nil

    /// How long running work in a snapshot is shown as running. The app rewrites the snapshot on every step,
    /// approval and end while it runs; once iOS suspends it, nothing rewrites it and widget reloads only read the
    /// same file again. Fifteen minutes is the Live Activity's own stale time, and the shortest gap between
    /// reloads iOS allows a widget with the app closed.
    static let freshFor: TimeInterval = 15 * 60

    /// When the running work in this snapshot stops being shown as running.
    var staleAt: Date { updatedAt.addingTimeInterval(Self.freshFor) }

    /// The snapshot as it should read at `date`: an end card older than 30 minutes is gone, and running work
    /// written more than `freshFor` before is last seen, not working. The sample is made again for `date`.
    func shown(at date: Date) -> WidgetSnapshot {
        if isSample == true { return NativeSample.snapshot(now: date) }
        var copy = self
        if let ended, date >= ended.at.addingTimeInterval(Ended.shownFor) { copy.ended = nil }
        if !running.isEmpty, date >= staleAt {
            copy.stale = true
            for index in copy.running.indices {
                copy.running[index].startedAt = nil
                copy.running[index].previousStep = nil
            }
        }
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
