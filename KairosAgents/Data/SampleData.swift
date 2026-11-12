import Foundation

/// Made-up content so every screen can be seen before a desktop is connected.
/// Nothing here is real, and nothing here is anyone's data.
nonisolated enum SampleData {
    static let kip = Bot(id: "kip", name: "Kip", role: "Your front desk", colorHex: 0xF2E8D8, status: .online, isKip: true)
    static let producer = Bot(id: "producer", name: "Producer", role: "Runs the content team", colorHex: Palette.botPowder, status: .working, shape: .squircle, accessory: .spectacles, model: "Claude Opus")
    static let scout = Bot(id: "scout", name: "Scout", role: "Research", colorHex: Palette.botSand, status: .needsYou, shape: .round, accessory: .rays, voice: "Ryan")
    static let quill = Bot(id: "quill", name: "Quill", role: "Writing", colorHex: Palette.botLilac, status: .online, shape: .tall, accessory: .quill)
    static let ledger = Bot(id: "ledger", name: "Ledger", role: "Bills and receipts", colorHex: Palette.botSage, status: .offline, shape: .squircle, accessory: .laurel)
    static let contentTeam = Bot(id: "content-team", name: "Content team", role: "Producer, Scout and Quill", colorHex: Palette.botPowder, status: .working, members: ["producer", "scout", "quill"])

    static let allBots = [kip, producer, scout, quill, ledger, contentTeam]
    static let pinned = [kip, producer, scout, contentTeam]

    static func bot(_ id: String) -> Bot { allBots.first { $0.id == id } ?? kip }
    static func bots(_ ids: [String]) -> [Bot] { ids.map(bot) }

    static let usage: [(provider: String, percent: Int)] = [("Claude", 64), ("Codex", 22)]
    static let nextEvent = "Fri · Report due"

    static let conversations: [Conversation] = [
        Conversation(id: "c-scout", kind: .bot("scout"), title: "Scout", preview: "Which topic should I start with?", time: "now", unread: true),
        Conversation(id: "c-zip", kind: .model, title: "Check zip tie availability", preview: "Searching three stores...", time: "2m", working: true),
        Conversation(id: "c-team", kind: .bot("content-team"), title: "Content team", preview: "Producer: today's video is rendering", time: "9:12", working: true),
        Conversation(id: "c-kip", kind: .bot("kip"), title: "Kip", preview: "Morning. Your report is due Friday.", time: "8:00"),
        Conversation(id: "c-bike", kind: .model, title: "Bike shop launch", preview: "Three files ready: prices, page and plan", time: "Tue"),
        Conversation(id: "c-quill", kind: .bot("quill"), title: "Quill", preview: "Second draft is in your Library.", time: "Tue"),
        Conversation(id: "c-inbox", kind: .model, title: "Summarise my inbox", preview: "Four need a reply. One is from the landlord.", time: "Mon"),
        Conversation(id: "c-trip", kind: .model, title: "Weekend trip plan", preview: "Two routes, both under four hours.", time: "Mon"),
        Conversation(id: "c-ledger", kind: .bot("ledger"), title: "Ledger", preview: "October receipts are filed.", time: "Sun"),
        Conversation(id: "c-garden", kind: .model, title: "Raised bed layout", preview: "A 4 by 8 plan with spacing for tomatoes.", time: "Sat"),
    ]

    static func conversation(_ id: String) -> Conversation {
        conversations.first { $0.id == id } ?? conversations[1]
    }

    static func thread(for bot: Bot) -> [ChatMessage] {
        if bot.isKip {
            return [
                ChatMessage(kind: .theirs("Morning. Your report is due Friday. Want me to draft it from this week's notes?")),
                ChatMessage(kind: .mine("Yes, and ask Scout for two sources on the project.")),
                ChatMessage(kind: .receipt("Read 9:41")),
                ChatMessage(kind: .status("Kip is reading your notes")),
                ChatMessage(kind: .theirs("On it. Scout is looking for sources now. I'll text you when the draft is ready.")),
            ]
        }
        if bot.id == "scout" {
            return [
                ChatMessage(kind: .theirs("I found five topics that fit this week's theme.")),
                ChatMessage(kind: .theirs("Which topic should I start with?")),
            ]
        }
        return [
            ChatMessage(kind: .theirs("Here when you need me.")),
        ]
    }

    static func inbox(for bot: Bot) -> [InboxItem] {
        [
            InboxItem(state: .needsYou, text: bot.isKip ? "Approve: send the report draft to your professor?" : "Pick a topic so I can start."),
            InboxItem(state: .working, text: bot.isKip ? "Drafting the report with Scout" : "Reading this week's sources"),
            InboxItem(state: .done, text: bot.isKip ? "Morning brief sent at 8:00" : "Yesterday's summary filed"),
        ]
    }

    static let zipSteps = [
        ChatStep(text: "Searched the first hardware store", done: true),
        ChatStep(text: "Searched the second hardware store", done: true),
        ChatStep(text: "Checking the corner shop", done: false),
    ]

    static let documents: [ChatDocument] = [
        ChatDocument(id: "d-page", name: "Booking page", label: "Design 1", details: ["PNG", "1920 x 1080 px", "906 kB"], look: .design),
        ChatDocument(id: "d-prices", name: "Rival prices.xlsx", label: "Sheet 2", details: ["XLSX", "3 rows", "14 kB"], look: .sheet),
        ChatDocument(id: "d-plan", name: "Launch plan.docx", label: "Document 3", details: ["DOCX", "1 page", "22 kB"], look: .page),
    ]

    static let liveWork = LiveWork(botID: "kip", text: "Kip is drafting your report", others: 1)

    static let designs = [
        MadeItem(title: "Booking page", when: "today", look: .design, fresh: true),
        MadeItem(title: "Shop poster", when: "yesterday", look: .design),
        MadeItem(title: "Menu board", when: "last week", look: .design),
    ]
    static let madeDocuments = [
        MadeItem(title: "Weekly report", when: "draft", look: .page),
        MadeItem(title: "Launch plan", when: "yesterday", look: .page),
        MadeItem(title: "Rival prices", when: "yesterday", look: .sheet),
    ]

    static func library(_ section: LibrarySection) -> [ListEntry] {
        switch section {
        case .files:
            [
                ListEntry(title: "Vault", detail: "Folders, notes and the map", symbol: "archivebox"),
                ListEntry(title: "Chat documents", detail: "Everything sent or made in chats", symbol: "bubble.left.and.text.bubble.right"),
                ListEntry(title: "Google Drive", detail: "Connected · 412 files", symbol: "externaldrive"),
                ListEntry(title: "Uploads", detail: "38 files", symbol: "arrow.up.doc"),
                ListEntry(title: "Weekly report.docx", detail: "From a chat with Kip · today", symbol: "doc.text"),
            ]
        case .notes:
            [
                ListEntry(title: "Shopping list", detail: "Edited 9:40", symbol: "note.text"),
                ListEntry(title: "Ideas for the content team", detail: "Yesterday", symbol: "note.text"),
                ListEntry(title: "Questions for the landlord", detail: "Monday · due Friday", symbol: "note.text"),
            ]
        case .calendar:
            [
                ListEntry(title: "Today", detail: "No meetings", symbol: "sun.max"),
                ListEntry(title: "Friday", detail: "Report due", symbol: "calendar"),
                ListEntry(title: "Your calendars", detail: "Kairos, Google, Notes", symbol: "list.bullet"),
            ]
        case .mail:
            [
                ListEntry(title: "Important today", detail: "3 messages", symbol: "envelope.badge"),
                ListEntry(title: "Needs a reply", detail: "1 from the landlord", symbol: "arrowshape.turn.up.left"),
                ListEntry(title: "Accounts", detail: "2 connected", symbol: "person.crop.circle"),
            ]
        case .tasks:
            [
                ListEntry(title: "Work board", detail: "4 in progress", symbol: "rectangle.split.3x1"),
                ListEntry(title: "Scheduled", detail: "Morning brief at 8:00", symbol: "clock"),
                ListEntry(title: "Triggers and automations", detail: "6 active", symbol: "bolt"),
                ListEntry(title: "Run history", detail: "Last run 2 minutes ago", symbol: "list.bullet.rectangle"),
            ]
        }
    }

    static let forgeSessions = [
        ForgeSession(title: "Mobile layout prototype", project: "shop-site", added: 412, removed: 36, note: "waiting for you", waiting: true),
        ForgeSession(title: "Faster image loading", project: "shop-site", added: 88, removed: 120, note: "done today", waiting: false),
    ]

    static let desktopAreas = [
        ListEntry(title: "Computer", detail: "See and steer your screen", symbol: "cursorarrow.rays"),
        ListEntry(title: "Browse", detail: "Your desktop browser", symbol: "globe"),
        ListEntry(title: "Local models", detail: "3 installed", symbol: "cpu"),
        ListEntry(title: "Files on this PC", detail: "Projects and folders", symbol: "folder"),
    ]

    static let addedTabs = [
        AddedTab(id: "crm", title: "CRM", symbol: "person.2"),
        AddedTab(id: "board", title: "Team board", symbol: "sportscourt"),
        AddedTab(id: "game", title: "Game studio", symbol: "cube"),
    ]
}
