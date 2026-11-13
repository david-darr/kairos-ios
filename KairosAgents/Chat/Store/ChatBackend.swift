import Foundation

/// Where Home and the chats get their data and send their actions. Two implementations:
/// `SampleBackend` (made-up content, what "Look around first" shows) and `LiveBackend` (the person's desktop).
/// `ChatStore` stands in front of whichever one is in use; screens only ever talk to the store.
protocol ChatBackend: AnyObject {
    var isSample: Bool { get }
    /// Live news (a reply streaming, a turn ending, a queue changing) goes to this.
    var onEvent: ((StoreEvent) -> Void)? { get set }

    // Home
    func loadHome() async throws -> HomeData
    func loadGlance() async throws -> Glance
    /// The slim poll: nil when nothing changed since the last read.
    func pollHome() async throws -> HomeData?
    /// Pin or unpin a bot. The desktop keeps the same pins for its Bots sidebar.
    func pinBot(_ id: String, pinned: Bool) async throws
    /// Put a model chat in a project (nil takes it out).
    func setChatProject(_ id: String, projectID: String?) async throws
    func createProject(name: String, instructions: String) async throws -> ChatProject

    // Model chats
    func openModelChat(_ id: String) async throws -> ModelChatSnapshot
    /// Makes a new chat on the desktop and answers its id.
    func createModelChat() async throws -> String
    /// Starts a turn. The same `requestID` sent twice starts it once. Answers the turn's id.
    func sendModel(chatID: String, text: String, attachments: [StagedAttachment], requestID: String) async throws -> String?
    func stop(chatID: String, turnID: String?) async throws
    func renameChat(_ id: String, title: String) async throws
    func starChat(_ id: String, starred: Bool) async throws
    func deleteChat(_ id: String) async throws
    /// A new chat that ends at the message with this index. Answers the new chat's id.
    func forkChat(_ id: String, throughIndex: Int) async throws -> String
    func compactChat(_ id: String) async throws
    func chatDetails(_ id: String) async throws -> ChatDetails
    func chatSummary(_ id: String, refresh: Bool) async throws -> String
    func chatFiles(_ id: String) async throws -> [ChatFile]

    // Model, effort, approval
    func modelOptions() async throws -> [ModelOption]
    func modelVersions(modelID: String) async throws -> [ModelVersion]
    /// Saves the choice and answers the settings as the desktop now holds them.
    func saveSettings(chatID: String, settings: ChatSettings) async throws -> ChatSettings
    /// The model of one bot conversation, as the desktop holds it.
    func botModel(threadID: String) async throws -> ChatSettings
    /// Choose the model of one bot conversation. A nil `modelID` follows the bot's own model again.
    func saveBotModel(threadID: String, settings: ChatSettings) async throws -> ChatSettings

    // Approvals and questions
    func answer(_ request: PendingRequest, choice: PendingRequest.Choice) async throws
    func respond(_ request: PendingRequest, answers: [String: QuestionAnswer], skip: Bool) async throws

    // Files
    func upload(_ file: OutgoingFile) async throws -> String
    func fileData(chatID: String, file: ChatFile) async throws -> Data

    // Bot conversations
    func openBotChat(botID: String, threadID: String?) async throws -> BotChatSnapshot
    func olderBotMessages(threadID: String, before: String) async throws -> BotMessagePage
    func newestBotMessages(threadID: String) async throws -> BotMessagePage
    func sendBot(threadID: String, text: String, attachments: [StagedAttachment], sendID: String, leafID: String?) async throws -> BotSendOutcome
    /// Take a waiting message back out of the queue; answers its text for the composer.
    func editQueued(threadID: String, queueID: String) async throws -> String
    func removeQueued(threadID: String, queueID: String) async throws
    /// Send the first waiting message now: the running reply stops first.
    func steer(threadID: String, queueID: String, turnID: String?, revision: Int) async throws
    func resumeQueue(threadID: String) async throws
    func interrupt(threadID: String, turnID: String) async throws
    func markRead(threadID: String, messageID: String?) async throws
    /// The person has seen this model chat as it is now (it is on screen or just left it).
    func markChatSeen(_ chatID: String)
}

/// A plain-words failure from either backend.
nonisolated struct ChatFailure: Error, Sendable {
    var plain: String
    init(_ plain: String) { self.plain = plain }
}

nonisolated extension Error {
    /// This error as one plain sentence for the person.
    var plainWords: String {
        if let failure = self as? ChatFailure { return failure.plain }
        return APIError.plain(self)
    }
}

/// Small shared formatting.
nonisolated enum ChatFormat {
    /// "now", "5m", "9:12", "Tue", "Nov 3": how Home shows when a conversation last moved.
    static func listTime(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if seconds < 6 * 86400 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Fri · Report due" (or the time, for something today).
    static func nextEvent(title: String, start: Date?, allDay: Bool, now: Date = Date()) -> String {
        guard let start else { return title }
        let calendar = Calendar.current
        let when: String
        if calendar.isDate(start, inSameDayAs: now) {
            when = allDay ? "Today" : start.formatted(date: .omitted, time: .shortened)
        } else if start.timeIntervalSince(now) < 6 * 86400 {
            when = start.formatted(.dateTime.weekday(.abbreviated))
        } else {
            when = start.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(when) · \(title)"
    }

    /// One plain line out of a message: no line breaks, no Markdown marks, at most 140 characters.
    static func oneLine(_ text: String) -> String {
        var line = text.replacingOccurrences(of: "\n", with: " ")
        for mark in ["**", "__", "`", "#"] { line = line.replacingOccurrences(of: mark, with: "") }
        while line.contains("  ") { line = line.replacingOccurrences(of: "  ", with: " ") }
        line = line.trimmingCharacters(in: .whitespaces)
        return line.count > 140 ? String(line.prefix(140)) : line
    }

    static func clock(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
