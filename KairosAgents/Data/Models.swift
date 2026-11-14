import Foundation

nonisolated enum BotStatus: Hashable, Sendable { case online, working, needsYou, offline }

nonisolated struct Bot: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var role: String
    var colorHex: UInt32
    var status: BotStatus
    var shape: MascotShape = .round
    var accessory: MascotAccessory = .none
    var isKip = false
    /// A team lists its member bots here; a single bot leaves it empty.
    var members: [String] = []
    var model = "Claude Sonnet"
    var approval = "Ask before acting"
    var voice = "Iris"
}

nonisolated enum ConversationKind: Hashable, Sendable {
    case bot(String)
    case model
}

nonisolated struct Conversation: Identifiable, Hashable, Sendable {
    let id: String
    var kind: ConversationKind
    var title: String
    var preview: String
    var time: String
    var unread = false
    var working = false
    /// A starred model chat sorts to the top of Home.
    var starred = false
    /// The chat project this model chat belongs to, or nil.
    var projectID: String? = nil
}

nonisolated struct ChatMessage: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case mine(String)
        case theirs(String)
        case status(String)
        case receipt(String)
    }

    let id = UUID()
    var kind: Kind
}

nonisolated struct InboxItem: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable { case needsYou, working, done }
    let id = UUID()
    var state: State
    var text: String
}

nonisolated struct ChatStep: Identifiable, Hashable, Sendable {
    let id = UUID()
    var text: String
    var done: Bool
}

nonisolated struct ChatDocument: Identifiable, Hashable, Sendable {
    enum Look: Hashable, Sendable { case design, sheet, page }
    let id: String
    var name: String
    var label: String
    var details: [String]
    var look: Look
}

nonisolated struct LiveWork: Hashable, Sendable {
    var botID: String
    var text: String
    var others: Int
}

nonisolated struct MadeItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    var title: String
    var when: String
    var look: ChatDocument.Look
    var fresh = false
}

nonisolated struct ListEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    var title: String
    var detail: String
    var symbol: String
}

nonisolated struct ForgeSession: Identifiable, Hashable, Sendable {
    let id = UUID()
    var title: String
    var project: String
    var added: Int
    var removed: Int
    var note: String
    var waiting: Bool
}

/// Every area of Kairos. Each one has exactly one home in the app.
nonisolated enum JumpArea: String, CaseIterable, Identifiable, Hashable, Sendable {
    case vault, notes, calendar, mail, tasks, studio, designs, forge, computer, browse, toolStore, addTab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vault: "Vault"
        case .notes: "Notes"
        case .calendar: "Calendar"
        case .mail: "Mail"
        case .tasks: "Tasks"
        case .studio: "Studio"
        case .designs: "Designs"
        case .forge: "Forge"
        case .computer: "Computer"
        case .browse: "Browse"
        case .toolStore: "Tool Store"
        case .addTab: "Add a tab"
        }
    }

    var symbol: String {
        switch self {
        case .vault: "archivebox"
        case .notes: "note.text"
        case .calendar: "calendar"
        case .mail: "envelope"
        case .tasks: "checklist"
        case .studio: "film.stack"
        case .designs: "paintpalette"
        case .forge: "hammer"
        case .computer: "cursorarrow.rays"
        case .browse: "globe"
        case .toolStore: "bag"
        case .addTab: "plus.square.dashed"
        }
    }

    var about: String {
        switch self {
        case .vault: "Your notes folder, with its folders and map."
        case .notes: "Quick Kairos notes."
        case .calendar: "Your events and due dates."
        case .mail: "Important mail and your accounts."
        case .tasks: "The work board, schedules and automations."
        case .studio: "The Content dashboard and your channels."
        case .designs: "Everything made on the design canvas."
        case .forge: "Coding sessions on your desktop."
        case .computer: "Watch a computer Kairos is using."
        case .browse: "The browser in Kairos on your desktop."
        case .toolStore: "Skills, tools, tabs and add-ons."
        case .addTab: "Add a tab from the Tool Store."
        }
    }
}

nonisolated struct AddedTab: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var symbol: String
}

nonisolated enum Route: Hashable, Sendable {
    case bot(String)
    case chat(String)
    case newChat
    /// A new model chat that joins this project at its first message.
    case newChatInProject(String)
    /// Every bot and team, laid out like Home.
    case allBots
    /// One chat project and its chats.
    case project(String)
    case area(JumpArea)
    case page(String)
}

nonisolated enum LibrarySection: String, CaseIterable, Hashable, Sendable {
    case files = "Files", notes = "Notes", calendar = "Calendar", mail = "Mail", tasks = "Tasks"

    var addLabel: String {
        switch self {
        case .files: "New document"
        case .notes: "New note"
        case .calendar: "New event"
        case .mail: "Check mail"
        case .tasks: "New card"
        }
    }

    var addSymbol: String {
        switch self {
        case .files: "doc.badge.plus"
        case .notes: "square.and.pencil"
        case .calendar: "calendar.badge.plus"
        case .mail: "arrow.clockwise"
        case .tasks: "plus"
        }
    }
}
