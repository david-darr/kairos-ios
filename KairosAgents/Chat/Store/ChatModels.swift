import Foundation

// What Home and the chats show, whichever desktop (the sample one or the real one) it came from.
// Screens read these through `ChatStore`; they never read SampleData or the desktop's own shapes.

// MARK: - Home

nonisolated struct GlanceUsage: Identifiable, Hashable, Sendable {
    var provider: String
    var percent: Int
    /// When the provider's limit starts over, when the desktop says.
    var resetsAt: Date? = nil
    var id: String { provider }
}

/// The slim row at the top of Home.
nonisolated struct Glance: Hashable, Sendable {
    var usage: [GlanceUsage] = []
    /// "Fri · Report due", or nil when nothing is coming up.
    var nextEvent: String?
    /// The same event as the desktop sent it, for widgets.
    var nextEventTitle: String?
    var nextEventStart: Date?
    var nextEventAllDay = false
    var needsYou = 0
    var running = 0

    var isEmpty: Bool { usage.isEmpty && nextEvent == nil && needsYou == 0 && running == 0 }
}

nonisolated struct HomeData: Sendable {
    var bots: [Bot]
    /// The bots the person pinned (on the desktop too). Kip leads Home's row whatever this holds.
    var pinned: [String]
    var conversations: [Conversation]
    var projects: [ChatProject] = []
}

/// A chat project (core/projects.py): shared instructions and documents for the chats in it.
nonisolated struct ChatProject: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var instructions: String = ""
    var documentCount = 0
}

// MARK: - Files

/// A file in a chat: one the person sent, or one the model made.
nonisolated struct ChatFile: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: String, Hashable, Sendable { case image, pdf, sheet, document, deck, text, video, audio, other }

    /// The desktop's own link ("/generated-files/...", "/chat-files/...") or a local id.
    var id: String
    var name: String
    var kind: Kind
    var size: Int?
    /// Bytes already on the phone (a staged attachment, a sample).
    var local: Data?
    /// Sample files are drawn, not loaded.
    var sampleLook: ChatDocument.Look?
    var sampleDetails: [String] = []
    var missing = false

    var ext: String {
        let parts = name.split(separator: ".")
        return parts.count > 1 ? String(parts[parts.count - 1]).uppercased() : ""
    }

    /// "Design 1", "Sheet 2": the kind in a word, then the position.
    func label(at index: Int) -> String {
        let word: String
        switch kind {
        case .image: word = "Picture"
        case .pdf: word = "PDF"
        case .sheet: word = "Sheet"
        case .document: word = "Document"
        case .deck: word = "Deck"
        case .text: word = "Text"
        case .video: word = "Video"
        case .audio: word = "Audio"
        case .other: word = "File"
        }
        if sampleLook == .design { return "Design \(index + 1)" }
        return "\(word) \(index + 1)"
    }

    var details: [String] {
        if !sampleDetails.isEmpty { return sampleDetails }
        var parts: [String] = []
        if !ext.isEmpty { parts.append(ext) }
        if let size { parts.append(ChatFile.sizeText(size)) }
        return parts
    }

    static func sizeText(_ bytes: Int) -> String {
        if bytes < 1000 { return "\(bytes) B" }
        if bytes < 1_000_000 { return "\(bytes / 1000) kB" }
        return String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    static func kind(forName name: String) -> Kind {
        let ext = name.split(separator: ".").last.map { $0.lowercased() } ?? ""
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "svg": return .image
        case "pdf": return .pdf
        case "xlsx", "xls", "csv", "tsv", "numbers": return .sheet
        case "docx", "doc", "rtf", "pages": return .document
        case "pptx", "ppt", "key": return .deck
        case "mp4", "mov", "m4v", "webm": return .video
        case "mp3", "wav", "m4a", "aac", "ogg": return .audio
        case "txt", "md", "markdown", "json", "html", "htm", "js", "ts", "py", "swift", "css", "yaml", "yml", "xml", "log": return .text
        default: return .other
        }
    }

    static func mimeType(forName name: String) -> String {
        let ext = name.split(separator: ".").last.map { $0.lowercased() } ?? ""
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        case "txt", "md", "log": return "text/plain"
        case "csv": return "text/csv"
        case "json": return "application/json"
        case "html", "htm": return "text/html"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "wav": return "audio/wav"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        default: return "application/octet-stream"
        }
    }

    /// The name without the desktop's 12 character id prefix ("1a2b3c4d5e6f_Launch plan.docx").
    static func cleanName(_ raw: String) -> String {
        let name = raw.removingPercentEncoding ?? raw
        guard name.count > 13 else { return name }
        let prefix = name.prefix(12)
        let rest = name.dropFirst(12)
        if rest.first == "_", prefix.allSatisfy({ $0.isHexDigit }) { return String(rest.dropFirst()) }
        return name
    }

    static func sample(_ document: ChatDocument) -> ChatFile {
        let kind: Kind
        switch document.look {
        case .design: kind = .image
        case .sheet: kind = .sheet
        case .page: kind = .document
        }
        return ChatFile(id: document.id, name: document.name, kind: kind, sampleLook: document.look, sampleDetails: document.details)
    }
}

/// A file picked on the phone and waiting to go with the next message.
nonisolated struct StagedAttachment: Identifiable, Hashable, Sendable {
    nonisolated enum Phase: Hashable, Sendable { case uploading, ready, failed(String) }
    let id: String
    var file: ChatFile
    /// The desktop's id for it, once uploaded.
    var remoteID: String?
    var phase: Phase
}

nonisolated struct SourceLink: Identifiable, Hashable, Sendable {
    var site: String
    var title: String
    var url: String
    var id: String { url }
}

// MARK: - Transcript

/// One step of a tool the model used, as a line of the live checklist.
nonisolated struct StepLine: Identifiable, Hashable, Sendable {
    var id: String
    var text: String
    var done: Bool
    var failed = false
}

/// One thing in a model chat's transcript.
nonisolated struct TranscriptEntry: Identifiable, Hashable, Sendable {
    nonisolated enum Role: Hashable, Sendable {
        case user
        case assistant
        /// A quiet centred line: "Stopped", "Background command finished".
        case note
        /// Live work drawn as cards (sample data and background work).
        case browser(site: String)
        case backgroundTask(progress: Double)
    }

    var id: String
    var role: Role
    var text: String
    var time: Date?
    var steps: [StepLine] = []
    var files: [ChatFile] = []
    var sources: [SourceLink] = []
    /// Why a reply failed, in one plain line. nil for a good reply.
    var failure: String?
    /// The reply is still being written.
    var streaming = false
    /// Where the message sits in the saved chat, for fork and edit. nil for anything not saved yet.
    var index: Int?
    /// "After background work", above a follow-up.
    var caption: String?

    var isUser: Bool { role == .user }
    var isAssistant: Bool { role == .assistant }
}

// MARK: - Approvals and questions

/// Something waiting on the person: an approval with choices, or one or more questions.
nonisolated struct PendingRequest: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable { case approval, question }
    /// How it is answered on the desktop.
    nonisolated enum Channel: Hashable, Sendable {
        /// `/api/permissions/{id}/answer` and `/respond`.
        case permission
        /// `/api/bot-cards/{id}/respond`, with the revision that was read.
        case botCard(revision: Int)
        /// Sample data: answered on the phone only.
        case sample
    }

    nonisolated struct Choice: Identifiable, Hashable, Sendable {
        var id: String
        var label: String
        var allows: Bool
        /// "once", "session", "forever" or "team", for a bot card's `remember`.
        var scope: String = "once"
    }

    nonisolated struct Question: Identifiable, Hashable, Sendable {
        /// The key the answer is sent under (the question's text, or a bot card's question id).
        var id: String
        var text: String
        var header: String
        var multiple: Bool
        var options: [Option]
    }

    nonisolated struct Option: Hashable, Sendable {
        var label: String
        var detail: String
    }

    var id: String
    var kind: Kind
    var channel: Channel
    var title: String
    var detail: String
    /// The command, path or address it is about.
    var target: String?
    var choices: [Choice] = []
    var questions: [Question] = []
    var expiresAt: Date?
}

/// What the person picked for one question: options, and optionally their own words.
nonisolated struct QuestionAnswer: Hashable, Sendable {
    var picked: Set<String> = []
    var typed = ""

    var isEmpty: Bool { picked.isEmpty && typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// One text, or a list when several were picked.
    func value(multiple: Bool) -> Any {
        let own = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        var all = picked.sorted()
        if !own.isEmpty { all.append(own) }
        if multiple { return all }
        return all.first ?? ""
    }
}

// MARK: - A running turn

/// A turn the desktop is running for a chat or a bot conversation.
nonisolated struct RunState: Hashable, Sendable {
    nonisolated enum Status: String, Hashable, Sendable { case processing, done, failed, stopped }

    var turnID: String
    var title = ""
    var prompt = ""
    var text = ""
    var status: Status = .processing
    var stopping = false
    var request: PendingRequest?
    var steps: [StepLine] = []
    var error: String?
    var startedAt: Date?
    var provider = ""
    var providerDetail: String?
    var revision = 0

    var isRunning: Bool { status == .processing }
}

/// A change to a running turn. Only what is set changes.
nonisolated struct RunChange: Hashable, Sendable {
    var status: RunState.Status?
    var stopping: Bool?
    var requestChanged = false
    var request: PendingRequest?
    var errorChanged = false
    var error: String?
    var providerDetailChanged = false
    var providerDetail: String?
}

/// A message typed while a reply runs, waiting its turn.
nonisolated struct QueuedMessage: Identifiable, Hashable, Sendable {
    var id: String
    var text: String
    var attachments: [StagedAttachment] = []
    /// A bot's queue is kept by the desktop; this is its state there ("pending", "interrupted").
    var state = "pending"
}

/// Work going on behind a chat.
nonisolated struct BackgroundItem: Identifiable, Hashable, Sendable {
    var id: String
    var kind: String
    var label: String
    var status: String
    var activity: String
    var startedAt: Date?
    var endedAt: Date?

    var isRunning: Bool { status == "running" || status == "queued" || status == "waiting" || status == "scheduled" }

    var kindWord: String {
        switch kind {
        case "subagent": return "Subagent"
        case "command": return "Command"
        case "agent": return "Agent"
        case "helper": return "Helper"
        case "computer": return "Computer"
        case "app_server": return "App server"
        case "scheduled": return "Scheduled"
        default: return "Task"
        }
    }

    var statusWord: String {
        switch status {
        case "running": return "Running"
        case "queued": return "Queued"
        case "waiting": return "Waiting on you"
        case "scheduled": return "Scheduled"
        case "done": return "Done"
        case "failed": return "Failed"
        case "stopped": return "Stopped"
        default: return status.capitalized
        }
    }
}

// MARK: - Model, effort, approval

/// A model connection the person can pick for a chat.
nonisolated struct ModelOption: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    /// "Claude subscription", "This PC", a model id.
    var source: String
    var takesImages = true
}

/// One version a connection offers, with the thinking levels it supports.
nonisolated struct ModelVersion: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var efforts: [String]
}

/// A chat's model, how hard it thinks and how it asks before acting.
nonisolated struct ChatSettings: Hashable, Sendable {
    var modelID: String?
    var modelName = "Choose a model"
    var source = ""
    var versionID: String?
    var versionName: String?
    /// The level in force, as the desktop names it ("high"), or nil for the model's own default.
    var effort: String?
    var efforts: [String] = []
    var fast: Bool?
    /// The approval in force, as one of `approvals`.
    var approval = "Ask first"
    var approvals: [String] = ["Ask first", "Full access"]
    /// A bot conversation only: true while it follows its bot's own model. nil in a model chat.
    var followsBot: Bool?

    /// The chip under the composer: the model, then the level when one is set.
    var chip: String {
        let name = versionName ?? modelName
        guard let effort else { return name }
        return "\(name) · \(ChatSettings.effortWord(effort))"
    }

    static func effortWord(_ effort: String) -> String {
        switch effort.lowercased() {
        case "minimal": return "Min"
        case "low": return "Low"
        case "medium", "med": return "Med"
        case "high": return "High"
        case "xhigh": return "XHigh"
        case "max": return "Max"
        default: return effort.capitalized
        }
    }
}

// MARK: - Chat details

/// Context and usage for the "Chat details" sheet. A figure nobody reported is nil, never 0.
nonisolated struct ChatDetails: Hashable, Sendable {
    nonisolated struct Part: Identifiable, Hashable, Sendable {
        var id: String
        var label: String
        var tokens: Int
        var estimated: Bool
    }

    var usedTokens: Int?
    var windowTokens: Int?
    var percent: Double?
    var windowEstimated = false
    var parts: [Part] = []
    var model: String?
    var provider: String?
    var rows: [Row] = []
    var note: String?

    nonisolated struct Row: Identifiable, Hashable, Sendable {
        var id: String
        var value: String
    }

    static func tokens(_ value: Int) -> String {
        if value < 1000 { return "\(value)" }
        if value < 1_000_000 {
            let thousands = Double(value) / 1000
            return thousands < 100 ? String(format: "%.1fK", thousands).replacingOccurrences(of: ".0K", with: "K") : "\(Int(thousands.rounded()))K"
        }
        return String(format: "%.1fM", Double(value) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
    }
}

// MARK: - A model chat, as loaded

nonisolated struct ModelChatSnapshot: Sendable {
    var title: String
    var entries: [TranscriptEntry]
    var settings: ChatSettings
    var starred = false
    var contextPercent: Double?
    var background: [BackgroundItem] = []
}

// MARK: - A bot conversation

/// One thing in a bot conversation.
nonisolated struct BotEntry: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        case mine
        case theirs
        /// A quiet centred line ("Stopped", a handoff, a routine note).
        case note
        /// "Read 9:41" under the person's last message.
        case receipt
        /// A small pulsing chip while the bot works ("Kip is reading your notes").
        case status
        /// A card the bot posted (a brief, a reminder, a call summary): a title and lines.
        case card(title: String)
    }

    var id: String
    var kind: Kind
    var text: String
    var time: Date?
    var files: [ChatFile] = []
    var failed = false
}

nonisolated struct BotThreadSummary: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var preview: String
    var time: String
    var unread: Bool
    var working: Bool
    var isMain: Bool
}

nonisolated struct BotChatSnapshot: Sendable {
    /// The conversation shown (a session id on the desktop).
    var threadID: String
    var threads: [BotThreadSummary]
    var entries: [BotEntry]
    var hasOlder: Bool
    /// The id to page back from.
    var firstID: String?
    /// The newest message, to send against.
    var leafID: String?
    var queue: [QueuedMessage] = []
    var queueRevision = 0
    var queuePaused = false
    var requests: [PendingRequest] = []
    var modelLine: String?
    /// The id of the newest message, for the read mark.
    var lastID: String?
}

nonisolated struct BotMessagePage: Sendable {
    var entries: [BotEntry]
    var hasOlder: Bool
    var firstID: String?
    var leafID: String?
    var lastID: String?
}

/// What happened to a message sent to a bot.
nonisolated struct BotSendOutcome: Sendable {
    var queued: Bool
    var turnID: String?
    var leafID: String?
}

// MARK: - Events from the desktop

/// Everything the live stream (or the sample desktop's timers) can tell the store.
nonisolated enum StoreEvent: Sendable {
    /// Every turn running right now. A turn not listed is over.
    case snapshot([String: RunState])
    case started(chatID: String, run: RunState)
    case chunk(chatID: String, turnID: String, text: String)
    case step(chatID: String, turnID: String, id: String, text: String, finished: Bool, failed: Bool)
    case changed(chatID: String, turnID: String, change: RunChange)
    case background(chatID: String, items: [BackgroundItem])
    case followup(chatID: String, entry: TranscriptEntry)
    case botQueue(threadID: String, items: [QueuedMessage], revision: Int, paused: Bool)
    case botRequest(threadID: String, request: PendingRequest, open: Bool)
    /// Something in a bot conversation changed that is not a run: reload its newest messages.
    case botChanged(threadID: String)
}
