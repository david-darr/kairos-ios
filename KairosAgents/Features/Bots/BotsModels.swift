import Foundation

// The Bots area's own data: everything about a bot beyond the chat itself.
// All of it is made up so every screen can be seen before a desktop is connected.

// MARK: - Levels and choices

nonisolated enum ApprovalLevel: String, CaseIterable, Hashable, Sendable, Identifiable {
    case ask, edits, auto, full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask"
        case .edits: "Edits"
        case .auto: "Auto"
        case .full: "Full"
        }
    }

    var longTitle: String {
        switch self {
        case .ask: "Ask before acting"
        case .edits: "Allow edits"
        case .auto: "Auto"
        case .full: "Full access"
        }
    }

    var hint: String {
        switch self {
        case .ask: "It asks before it changes anything or runs anything."
        case .edits: "It edits files on its own and asks before anything else."
        case .auto: "It goes ahead on safe steps and asks before risky ones."
        case .full: "It acts without asking, including sending on its own. You can stop it at any time."
        }
    }

    var symbol: String {
        switch self {
        case .ask: "hand.raised"
        case .edits: "pencil"
        case .auto: "wand.and.stars"
        case .full: "bolt.shield"
        }
    }

    var rank: Int { ApprovalLevel.allCases.firstIndex(of: self) ?? 0 }
}

nonisolated enum Effort: String, CaseIterable, Hashable, Sendable {
    case low, medium, high, xhigh, max

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        case .xhigh: "XHigh"
        case .max: "Max"
        }
    }
}

nonisolated struct ModelOption: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var source: String
    var about: String
}

nonisolated enum RepeatMode: String, CaseIterable, Hashable, Sendable {
    case once, daily, weekdays, weekly, interval, custom, limitReset

    var title: String {
        switch self {
        case .once: "Once"
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekly: "Weekly"
        case .interval: "Every few minutes"
        case .custom: "Custom schedule"
        case .limitReset: "After a limit reset"
        }
    }

    static let basic: [RepeatMode] = [.once, .daily, .weekdays, .weekly]
    static let more: [RepeatMode] = [.interval, .custom, .limitReset]
}

nonisolated enum Weekday: Int, CaseIterable, Hashable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun

    var short: String { ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][rawValue] }
    var letter: String { ["M", "T", "W", "T", "F", "S", "S"][rawValue] }
}

nonisolated func clockText(_ hour: Int, _ minute: Int) -> String {
    let h12 = hour % 12 == 0 ? 12 : hour % 12
    return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "AM" : "PM")
}

// MARK: - Routines and triggers

nonisolated struct Routine: Identifiable, Hashable, Sendable {
    let id: UUID
    var botID: String
    var name: String
    var instructions: String
    var mode: RepeatMode = .daily
    var days: Set<Weekday> = Set(Weekday.allCases)
    var hour = 9
    var minute = 0
    var intervalMinutes = 60
    var onlyBetween = false
    var startHour = 9
    var endHour = 17
    var cron = "0 9 * * 1-5"
    var limitName = "Claude"
    var afterEveryReset = false
    var on = true
    var lastRun = "Last ran today at 9:00 AM"
    var failedInARow = 0
    var postTo = "Its own conversation each time"
    var readOnly = false
    var runOnStart = false
    var rememberLast = true
    var showAsCall = false
    var queueIfRunning = false
    var runLimit = 30
    var blockMinutes = 30
    var needsYou: String? = nil

    init(id: UUID = UUID(), botID: String, name: String, instructions: String, mode: RepeatMode = .daily, days: Set<Weekday> = Set(Weekday.allCases), hour: Int = 9, minute: Int = 0) {
        self.id = id
        self.botID = botID
        self.name = name
        self.instructions = instructions
        self.mode = mode
        self.days = days
        self.hour = hour
        self.minute = minute
    }

    /// One plain sentence: "Every weekday at 9:00 AM".
    var sentence: String {
        let at = clockText(hour, minute)
        switch mode {
        case .once: return "Once, Friday at \(at)"
        case .daily: return "Every day at \(at)"
        case .weekdays: return "Every weekday at \(at)"
        case .weekly:
            let list = Weekday.allCases.filter { days.contains($0) }.map(\.short).joined(separator: ", ")
            return list.isEmpty ? "Pick the days" : "\(list) at \(at)"
        case .interval:
            let base = intervalMinutes % 60 == 0 ? "Every \(intervalMinutes / 60) h" : "Every \(intervalMinutes) min"
            return onlyBetween ? "\(base), \(clockText(startHour, 0)) to \(clockText(endHour, 0))" : base
        case .custom: return "On a custom schedule (\(cron))"
        case .limitReset: return afterEveryReset ? "After every \(limitName) reset" : "After the next \(limitName) reset"
        }
    }

    /// Does it run on this weekday (0 = Monday)?
    func runs(on day: Weekday) -> Bool {
        switch mode {
        case .daily, .interval, .custom: true
        case .weekdays: day.rawValue < 5
        case .weekly: days.contains(day)
        case .once: day == .fri
        case .limitReset: day == .wed
        }
    }
}

nonisolated struct BotTrigger: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case webhook, appEvent }
    let id = UUID()
    var botID: String
    var kind: Kind
    var name: String
    var app: String
    var event: String
    var on = true
    var lastEvent: String
    var instructions: String
    var runStraightAway = false
    var mostAtOnce = 3
}

// MARK: - Inbox

nonisolated enum Settled: Hashable, Sendable {
    case allowedOnce, allowedChat, allowedTeam, denied, answered, skipped, replied(String), notNow

    var text: String {
        switch self {
        case .allowedOnce: "Allowed once."
        case .allowedChat: "Allowed for this chat."
        case .allowedTeam: "Allowed for the team."
        case .denied: "Rejected. The action did not run."
        case .answered: "Answered. It will use this in a new turn."
        case .skipped: "Skipped."
        case .replied(let text): "You replied: \(text)"
        case .notNow: "Not now."
        }
    }

    var good: Bool {
        switch self {
        case .denied, .skipped, .notNow: false
        default: true
        }
    }
}

nonisolated struct QuestionOption: Hashable, Sendable {
    var title: String
    var detail: String = ""
}

nonisolated struct BotQuestion: Hashable, Sendable {
    var tab: String
    var prompt: String
    var options: [QuestionOption]
    var multi = false
}

nonisolated struct NeedsCard: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case approval(title: String, summary: String, covers: String, details: [String])
        case question([BotQuestion])
        case review(title: String, summary: String)
    }
    let id = UUID()
    var botID: String
    var kind: Kind
    var age: String
    var settled: Settled? = nil
}

nonisolated struct WorkItem: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable { case working, review, failed, done }
    let id = UUID()
    var botID: String
    var title: String
    var detail: String
    var state: State
    var progress: Double = 0
    var updated: String
}

nonisolated struct BotNotice: Identifiable, Hashable, Sendable {
    let id = UUID()
    var botID: String
    var kind: String
    var title: String
    var detail: String
    var age: String
    var unread = true
    var pinned = false
    var problem = false
    var symbol: String
}

nonisolated struct ActivityEvent: Identifiable, Hashable, Sendable {
    let id = UUID()
    var day: String
    var time: String
    var title: String
    var detail: String
    var source: String
}

// MARK: - Settings parts

nonisolated struct MemoryNote: Identifiable, Hashable, Sendable {
    let id = UUID()
    var section: String
    var text: String
    var addedBy: String
    var when: String
}

nonisolated struct LearnedFact: Identifiable, Hashable, Sendable {
    let id = UUID()
    var text: String
    var who: String
    var when: String
}

nonisolated struct SkillItem: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable { case on, off, needsReview, changed }
    let id = UUID()
    var name: String
    var origin: String
    var about: String
    var state: State
    var everyBot = false
    var text: String
}

nonisolated struct AppGrant: Identifiable, Hashable, Sendable {
    enum Level: String, CaseIterable, Hashable, Sendable {
        case off = "Off", read = "Read only", change = "Read and change"
    }
    let id = UUID()
    var app: String
    var symbol: String
    var level: Level
    var tools: Int
    var allowedTools: Int
}

nonisolated struct ConnectedApp: Identifiable, Hashable, Sendable {
    enum State: String, Hashable, Sendable {
        case connected = "Connected", reconnect = "Reconnect", notAdded = "Not added", finish = "Finish setup", off = "Off"
    }
    let id = UUID()
    var name: String
    var symbol: String
    var about: String
    var state: State
    var usedBy: [String]
    var category: String
    var isServer = false
}

nonisolated struct BrowserProfile: Identifiable, Hashable, Sendable {
    let id = UUID()
    var name: String
    var usedBy: [String]
}

nonisolated struct SavedLogin: Identifiable, Hashable, Sendable {
    let id = UUID()
    var site: String
    var username: String
    var twoFactor: Bool
    var lastUsed: String
    var allBots: Bool
}

nonisolated struct UsageRun: Identifiable, Hashable, Sendable {
    let id = UUID()
    var title: String
    var model: String
    var duration: String
    var cost: String
    var outcome: String
    var when: String
}

nonisolated struct PlanWindow: Identifiable, Hashable, Sendable {
    let id = UUID()
    var provider: String
    var name: String
    var percent: Int
    var resets: String
}

nonisolated struct BotConversation: Identifiable, Hashable, Sendable {
    let id = UUID()
    var title: String
    var updated: String
    var folder: String? = nil
    var pinned = false
    var unread = false
    var main = false
    var archived = false
    var snoozed = false
    var working = false
}

nonisolated struct HistoryChange: Identifiable, Hashable, Sendable {
    let id = UUID()
    var who: String
    var what: String
    var when: String
    var undone = false
}

/// Everything in one bot's Settings.
nonisolated struct BotSettings: Hashable, Sendable {
    var model = "Claude Sonnet"
    var connection = "Claude (default)"
    var effort: Effort = .high
    var keepWarm = "Follow default"
    var fallbacks: [String] = ["GPT-6.1 Sol"]
    var approval: ApprovalLevel = .ask
    var conversationApproval: ApprovalLevel? = nil
    var outsideAllow = false
    var outsidePerDay = 20
    var outsideUsed = 3
    var alwaysAllowed: [String] = ["npm test", "git status"]
    // voice and calls
    var voice = "Iris"
    var liveVoice = "marin"
    var callMode = "Same as Settings"
    var readTypedReplies = true
    var idleEndMinutes = 5
    var tellMeWhenNeeded = true
    var speakReplies = false
    var voiceProvider = "Same as the Voice"
    // delivery
    var reportTo = "In the app only"
    // memory
    var useMemory = true
    var tidyNotes = true
    var learnFromRooms = false
    var notes: [MemoryNote] = []
    var topics: [String] = ["Suppliers", "Weekly report"]
    // skills
    var skills: [SkillItem] = []
    var lookForSkills = true
    var shareLearned = "Ask"
    // access
    var grants: [AppGrant] = []
    var reach = "All visible bots"
    var askBeforeContacting = true
    var everyToolServer = true
    var staySignedIn = true
    var place = "Auto"
    // browser
    var browserEnabled = true
    var browserProfile = "Own profile"
    // limits
    var botOn = true
    var runsPerDay = 40
    var runsToday = 12
    var monthlyCap: Int? = 25
    var spentThisMonth = 6.4
    // conversations
    var conversations: [BotConversation] = []
    var folders: [String] = ["Reports", "Ideas"]
    // identity
    var standingInstructions = "Be brief. Ask before spending money. Keep a running list of open questions."
    var introduction = ""
    var replyStyle = "Default"
    var history: [HistoryChange] = []
}

// MARK: - Teams and rooms

nonisolated struct BotTeam: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var department: String
    var members: [String]
    var chief: String?
    var paused = false
    var instructions: String
    var memory: [MemoryNote] = []
}

nonisolated struct RoomMessage: Identifiable, Hashable, Sendable {
    let id = UUID()
    var from: String   // a bot id, or "you"
    var text: String
    var time: String
    var pinned = false
    var handoff: Handoff? = nil
}

nonisolated struct BotRoom: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var context: String
    var members: [String]
    var whoAnswers = "Auto chooses who answers"
    var turnLimit = 30
    var instructions: String
    var messages: [RoomMessage]
    var held: [String] = []
    var working: [String] = []
    var unread = 0
}

nonisolated struct Handoff: Identifiable, Hashable, Sendable {
    let id = UUID()
    var from: String
    var to: String
    var verb: String      // Delegated, Asked, Notified
    var reason: String
    var status: String    // Queued, Working, Waiting for you, Done, Failed
    var doneWhen: String = ""
}

// MARK: - Making bots

nonisolated struct ReadyBot: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var role: String
    var blurb: String
    var tryAsking: String
    var category: String
    var colorHex: UInt32
    var shape: MascotShape
    var accessory: MascotAccessory
    var routines: Int
}

nonisolated struct StartingNote: Identifiable, Hashable, Sendable {
    let id = UUID()
    var heading = "About this work"
    var text = ""
}

nonisolated struct NewBotDraft: Hashable, Sendable {
    var name = ""
    var job = ""
    var introduction = ""
    var group = ""
    var colorHex: UInt32 = Palette.botPowder
    var shape: MascotShape = .round
    var accessory: MascotAccessory = .none
    var instructions = ""
    var notes: [StartingNote] = []
    var model = "Claude Sonnet"
    var effort: Effort = .high
    var routines: [Routine] = []
    var everyToolServer = true
    var staySignedIn = true
    var tidyNotes = true
    var fullAccess = false
    var tellMeOn = "In the app only"
}

nonisolated struct PackagePart: Identifiable, Hashable, Sendable {
    let id = UUID()
    var kind: String
    var name: String
    var include = true
}
