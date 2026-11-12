import Foundation

/// Made-up content for the Bots area. Nothing here is real, and nothing here is anyone's data.
nonisolated enum BotsSample {
    static let models: [BotModelOption] = [
        BotModelOption(name: "Claude Sonnet", source: "Claude subscription", about: "Fast and careful. The default for most bots."),
        BotModelOption(name: "Claude Opus", source: "Claude subscription", about: "The strongest. Slower and uses more of your plan."),
        BotModelOption(name: "Claude Haiku", source: "Claude subscription", about: "Quick and light. Good for reminders and sorting."),
        BotModelOption(name: "GPT-6.1 Sol", source: "Codex", about: "Strong at code and long tasks."),
        BotModelOption(name: "Qwen local", source: "This PC", about: "Runs on your desktop. Free and private, slower."),
    ]

    static let voices = ["Iris", "Ryan", "Nova", "Sage", "Device voice"]
    static let liveVoices = ["marin", "cedar", "coral", "sage", "ash"]
    static let channels = ["In the app only", "Telegram", "Email", "Text message"]

    static func settings(for bot: Bot) -> BotSettings {
        var s = BotSettings()
        s.model = bot.model
        s.voice = bot.voice
        s.approval = bot.isKip ? .auto : (bot.id == "scout" ? .ask : .edits)
        s.introduction = "\(bot.name) helps with \(bot.role.lowercased())."
        s.notes = [
            MemoryNote(section: "Preferences", text: "Short summaries first, details after.", addedBy: "you", when: "2 weeks ago"),
            MemoryNote(section: "About this work", text: "The shop is closed on Mondays.", addedBy: "the bot", when: "last week"),
            MemoryNote(section: "Corrections", text: "Prices are listed without tax.", addedBy: "a conversation", when: "Tuesday"),
        ]
        s.skills = [
            SkillItem(name: "weekly-report", origin: "Written by you", about: "Turns the week's notes into the Friday report.", state: .on, text: "Collect this week's notes. Group them by topic. Write five short sections and a list of open questions."),
            SkillItem(name: "price-check", origin: "Library", about: "Compares prices across three shops.", state: .on, everyBot: true, text: "Search three shops for the item. Make a small table with price, stock and link."),
            SkillItem(name: "tidy-inbox", origin: "Learned", about: "Sorts new mail into four folders.", state: .needsReview, text: "Read new mail. Move receipts to Receipts, news to Later, and flag anything from suppliers."),
            SkillItem(name: "trip-plan", origin: "Tool Store", about: "Plans a short trip with a budget.", state: .off, text: "Ask for dates and budget. Offer two routes. Keep it under four hours of travel."),
        ]
        s.grants = [
            AppGrant(app: "Mail", symbol: "envelope", level: .read, tools: 12, allowedTools: 6),
            AppGrant(app: "Calendar", symbol: "calendar", level: .change, tools: 8, allowedTools: 8),
            AppGrant(app: "Google Drive", symbol: "externaldrive", level: .read, tools: 15, allowedTools: 9),
            AppGrant(app: "Shop orders", symbol: "cart", level: .off, tools: 5, allowedTools: 0),
        ]
        s.conversations = [
            BotConversation(title: "Main", updated: "now", main: true, working: bot.status == .working),
            BotConversation(title: "Friday report", updated: "9:12", folder: "Reports", pinned: true),
            BotConversation(title: "Rival prices", updated: "Tue", folder: "Reports", unread: true),
            BotConversation(title: "New window display", updated: "Mon", folder: "Ideas"),
            BotConversation(title: "Supplier email draft", updated: "Sun"),
            BotConversation(title: "Old stock list", updated: "Oct 28", archived: true),
        ]
        s.history = [
            HistoryChange(who: "You", what: "changed the model: Claude Haiku to \(bot.model)", when: "Yesterday"),
            HistoryChange(who: bot.name, what: "added a note about opening hours", when: "Tuesday"),
            HistoryChange(who: "You", what: "changed the job: Helper to \(bot.role)", when: "Last week"),
        ]
        return s
    }

    static let routines: [Routine] = {
        var brief = Routine(botID: "kip", name: "Morning brief", instructions: "Read my calendar and mail. Tell me the three things that matter today.", mode: .weekdays, hour: 8)
        brief.lastRun = "Last ran today at 8:00 AM"
        var report = Routine(botID: "kip", name: "Friday report", instructions: "Draft the weekly report from this week's notes and send it to me for a look.", mode: .weekly, days: [.fri], hour: 15)
        report.lastRun = "Has not run yet"
        var prices = Routine(botID: "scout", name: "Rival prices", instructions: "Check the three rival shops for bike lock prices and note any change.", mode: .interval, hour: 9)
        prices.intervalMinutes = 180
        prices.onlyBetween = true
        prices.lastRun = "Last run failed"
        prices.failedInARow = 2
        prices.needsYou = "Sign in to the second shop again."
        var sources = Routine(botID: "scout", name: "New sources", instructions: "Look for two new sources on this week's topic.", mode: .daily, hour: 10, minute: 30)
        sources.on = false
        sources.lastRun = "Last ran Monday"
        var receipts = Routine(botID: "ledger", name: "File receipts", instructions: "File new receipts from mail into the month's folder.", mode: .daily, hour: 18)
        let watch = Routine(botID: "wisp", name: "Night watch", instructions: "Check the shop's order inbox every hour overnight. Wake me only for something urgent.", mode: .interval, hour: 22)
        var watch2 = watch
        watch2.intervalMinutes = 60
        watch2.onlyBetween = true
        watch2.startHour = 22
        watch2.endHour = 6
        receipts.showAsCall = false
        var standup = Routine(botID: "producer", name: "Team stand-up", instructions: "Ask each team member what they did and post a short summary.", mode: .weekdays, hour: 9, minute: 15)
        standup.showAsCall = true
        standup.blockMinutes = 20
        var plan = Routine(botID: "atlas", name: "Weekend plan", instructions: "Suggest one short weekend trip with a budget.", mode: .weekly, days: [.thu], hour: 17)
        plan.lastRun = "Last ran Thursday"
        let reminder = Routine(botID: "posy", name: "Water the plants", instructions: "Remind me to water the shop plants.", mode: .weekly, days: [.mon, .thu], hour: 11)
        return [brief, report, prices, sources, receipts, watch2, standup, plan, reminder]
    }()

    static let triggers: [BotTrigger] = [
        BotTrigger(botID: "ledger", kind: .webhook, name: "New orders", app: "Webhook", event: "Any call", lastEvent: "Last event 2 h ago", instructions: "Log each new order in the month's sheet."),
        BotTrigger(botID: "kip", kind: .appEvent, name: "Mail from suppliers", app: "Mail", event: "A new message arrives", lastEvent: "Checked, nothing new", instructions: "If a supplier writes, summarise it and tell me."),
        BotTrigger(botID: "scout", kind: .appEvent, name: "New calendar event", app: "Calendar", event: "An event is added", on: false, lastEvent: "Last event Monday", instructions: "Find background on whoever the meeting is with."),
    ]

    static let needs: [NeedsCard] = [
        NeedsCard(botID: "kip", kind: .approval(title: "Send the report draft", summary: "Email the weekly report draft to the shop partner.", covers: "Mail: send one message", details: ["To: partner at the shop", "Subject: Weekly report, draft", "1 attachment, 22 kB"]), age: "now"),
        NeedsCard(botID: "kip", kind: .question([
            BotQuestion(tab: "Tone", prompt: "How should the report sound?", options: [QuestionOption(title: "Plain and short", detail: "Five sections, no extras"), QuestionOption(title: "Warm", detail: "A friendly opening line"), QuestionOption(title: "Formal", detail: "For the bank")]),
            BotQuestion(tab: "Sections", prompt: "Which sections should it keep?", options: [QuestionOption(title: "Sales"), QuestionOption(title: "Repairs"), QuestionOption(title: "Stock"), QuestionOption(title: "Open questions")], multi: true),
            BotQuestion(tab: "Due", prompt: "When do you want the final copy?", options: [QuestionOption(title: "Thursday evening"), QuestionOption(title: "Friday morning"), QuestionOption(title: "Friday noon")]),
            BotQuestion(tab: "Send to", prompt: "Who else should get a copy?", options: [QuestionOption(title: "Nobody else"), QuestionOption(title: "The accountant"), QuestionOption(title: "The whole team")]),
        ]), age: "2m"),
        NeedsCard(botID: "scout", kind: .question([
            BotQuestion(tab: "Topic", prompt: "Which topic should I start with?", options: [QuestionOption(title: "Winter bike care", detail: "Most searched this week"), QuestionOption(title: "Commuting on a budget"), QuestionOption(title: "Kids' first bike"), QuestionOption(title: "E-bike batteries"), QuestionOption(title: "Locks that work")]),
        ]), age: "now"),
        NeedsCard(botID: "scout", kind: .approval(title: "Open a new site", summary: "Visit a parts supplier's site to read its price list.", covers: "Browser: one new site", details: ["Site: a parts supplier", "Reads only, signs in to nothing"]), age: "5m"),
        NeedsCard(botID: "producer", kind: .review(title: "Script for Friday's video", summary: "A 60 second script about winter bike care. Ready for your look."), age: "12m"),
        NeedsCard(botID: "quill", kind: .approval(title: "Replace the shop's About page text", summary: "Rewrite the About page with the new opening hours.", covers: "Files: change one file", details: ["about.md, 14 lines changed"]), age: "1h"),
    ]

    static let work: [WorkItem] = [
        WorkItem(botID: "kip", title: "Drafting the report with Scout", detail: "Step 3 of 5 · reading this week's notes", state: .working, progress: 0.55, updated: "just now"),
        WorkItem(botID: "kip", title: "Booking the van for Saturday", detail: "Waiting for the rental site", state: .working, progress: 0.2, updated: "4 min ago"),
        WorkItem(botID: "kip", title: "Morning brief sent at 8:00", detail: "3 things today, 1 reply needed", state: .done, updated: "8:00"),
        WorkItem(botID: "kip", title: "Receipts sorted for October", detail: "41 receipts in 3 folders", state: .done, updated: "Yesterday"),
        WorkItem(botID: "kip", title: "Shop hours page", detail: "Ready for review", state: .review, updated: "1 h ago"),
        WorkItem(botID: "scout", title: "Reading this week's sources", detail: "6 of 9 read", state: .working, progress: 0.66, updated: "just now"),
        WorkItem(botID: "scout", title: "Rival prices check", detail: "Could not sign in to the second shop", state: .failed, updated: "20 min ago"),
        WorkItem(botID: "scout", title: "Yesterday's summary filed", detail: "Saved to Library", state: .done, updated: "Yesterday"),
        WorkItem(botID: "producer", title: "Rendering today's video", detail: "Render 70%", state: .working, progress: 0.7, updated: "just now"),
        WorkItem(botID: "producer", title: "Posted to the channel", detail: "Private, waiting for your OK to publish", state: .done, updated: "9:12"),
    ]

    static let notices: [BotNotice] = [
        BotNotice(botID: "kip", kind: "Approval", title: "Kip needs your OK to send a message", detail: "The report draft", age: "now", symbol: "checkmark.shield"),
        BotNotice(botID: "kip", kind: "Finished", title: "Morning brief is ready", detail: "3 things today", age: "8:00", unread: false, symbol: "sun.max"),
        BotNotice(botID: "kip", kind: "Missed call", title: "Kip called you", detail: "About the van booking", age: "Yesterday", symbol: "phone.arrow.down.left"),
        BotNotice(botID: "kip", kind: "Routine failed", title: "Rival prices did not finish", detail: "Sign-in needed at the second shop", age: "20m", problem: true, symbol: "exclamationmark.triangle"),
        BotNotice(botID: "kip", kind: "Handoff settled", title: "Scout finished the sources", detail: "Two sources added to the report", age: "1h", unread: false, symbol: "arrow.left.arrow.right"),
        BotNotice(botID: "kip", kind: "Spend", title: "This month is at 26% of the cap", detail: "$6.40 of $25", age: "Mon", unread: false, symbol: "dollarsign.circle"),
    ]

    static func activity(for bot: Bot) -> [ActivityEvent] {
        [
            ActivityEvent(day: "Today", time: "9:41", title: "Asked for your OK", detail: "Send the report draft", source: "Run timeline"),
            ActivityEvent(day: "Today", time: "9:30", title: "Handed work to Scout", detail: "Find two sources on winter bike care", source: "Runtime event"),
            ActivityEvent(day: "Today", time: "9:12", title: "Read 14 notes", detail: "This week's notes folder", source: "Run timeline"),
            ActivityEvent(day: "Today", time: "8:00", title: "Routine ran: Morning brief", detail: "Finished in 42 s", source: "Record"),
            ActivityEvent(day: "Yesterday", time: "18:02", title: "Saved a memory", detail: "The shop is closed on Mondays", source: "Record"),
            ActivityEvent(day: "Yesterday", time: "14:20", title: "Used a skill", detail: "/price-check", source: "Run timeline"),
            ActivityEvent(day: "Yesterday", time: "9:00", title: "Model changed", detail: "Claude Haiku to \(bot.model)", source: "Record"),
        ]
    }

    static func runs(for bot: Bot) -> [UsageRun] {
        [
            UsageRun(title: "Drafting the report", model: bot.model, duration: "2m 14s", cost: "$0.18", outcome: "Running", when: "now"),
            UsageRun(title: "Morning brief", model: bot.model, duration: "42s", cost: "$0.04", outcome: "Done", when: "8:00"),
            UsageRun(title: "Rival prices", model: "Claude Haiku", duration: "1m 3s", cost: "$0.02", outcome: "Failed", when: "Yesterday"),
            UsageRun(title: "Receipts", model: bot.model, duration: "3m 50s", cost: "$0.31", outcome: "Done", when: "Yesterday"),
            UsageRun(title: "Supplier email", model: bot.model, duration: "58s", cost: "$0.06", outcome: "Done", when: "Mon"),
        ]
    }

    static let learned: [LearnedFact] = [
        LearnedFact(text: "Prefers short replies with the answer first.", who: "Kip", when: "3 days ago"),
        LearnedFact(text: "The shop opens at 10 on Saturdays.", who: "Posy", when: "last week"),
        LearnedFact(text: "Uses metric sizes for frames.", who: "Mason", when: "2 weeks ago"),
    ]

    static let apps: [ConnectedApp] = [
        ConnectedApp(name: "Mail", symbol: "envelope", about: "Read, sort and draft mail.", state: .connected, usedBy: ["Kip", "Ledger"], category: "Mail and calendar"),
        ConnectedApp(name: "Calendar", symbol: "calendar", about: "Events and reminders.", state: .connected, usedBy: ["Kip", "Posy", "Atlas"], category: "Mail and calendar"),
        ConnectedApp(name: "Google Drive", symbol: "externaldrive", about: "Files and folders.", state: .reconnect, usedBy: ["Quill"], category: "Files"),
        ConnectedApp(name: "Shop orders", symbol: "cart", about: "Orders from the web shop.", state: .finish, usedBy: [], category: "Business"),
        ConnectedApp(name: "Notes server", symbol: "server.rack", about: "A tool server on this PC.", state: .connected, usedBy: ["Kip", "Scout", "Quill"], category: "Tool servers", isServer: true),
        ConnectedApp(name: "Weather", symbol: "cloud.sun", about: "Forecasts for trips.", state: .notAdded, usedBy: [], category: "Everyday"),
    ]

    static let profiles: [BrowserProfile] = [
        BrowserProfile(name: "Shop accounts", usedBy: ["Scout", "Ledger"]),
        BrowserProfile(name: "Research", usedBy: []),
    ]

    static let logins: [SavedLogin] = [
        SavedLogin(site: "parts-supplier.example", username: "shop", twoFactor: true, lastUsed: "Used yesterday", allBots: false),
        SavedLogin(site: "rental-vans.example", username: "orders", twoFactor: false, lastUsed: "Never used", allBots: true),
    ]

    static let planWindows: [PlanWindow] = [
        PlanWindow(provider: "Claude", name: "5 hour window", percent: 64, resets: "Resets at 2:00 PM"),
        PlanWindow(provider: "Claude", name: "This week", percent: 41, resets: "Resets Monday"),
        PlanWindow(provider: "Codex", name: "This week", percent: 22, resets: "Resets Thursday"),
    ]

    static let skills: [SkillItem] = [
        SkillItem(name: "price-check", origin: "Library", about: "Compares prices across three shops.", state: .on, everyBot: true, text: "Search three shops for the item. Make a small table."),
        SkillItem(name: "meeting-notes", origin: "Shared", about: "Turns a call into notes and tasks.", state: .on, text: "Write the decisions, then the tasks with owners."),
        SkillItem(name: "receipt-filer", origin: "Imported", about: "Files receipts by month.", state: .needsReview, text: "Find receipts in mail. Save each to the month's folder."),
    ]

    static let teams: [BotTeam] = [
        BotTeam(id: "content", name: "Content team", department: "Marketing", members: ["producer", "scout", "quill"], chief: "producer", instructions: "Make one short video a day about bike care. Producer decides what gets posted. Everything waits for an OK before it goes public.", memory: [
            MemoryNote(section: "Decisions", text: "Videos stay under 60 seconds.", addedBy: "Producer", when: "last week"),
            MemoryNote(section: "Terms", text: "\"Drop\" means a new product post.", addedBy: "you", when: "2 weeks ago"),
        ]),
        BotTeam(id: "office", name: "Back office", department: "Operations", members: ["ledger", "posy"], chief: nil, instructions: "Keep the books tidy and remind me of anything due.", memory: []),
        BotTeam(id: "workshop", name: "Workshop", department: "Operations", members: ["mason"], chief: "mason", paused: true, instructions: "Plan repairs and builds.", memory: []),
    ]

    static let rooms: [BotRoom] = [
        BotRoom(id: "launch", name: "Spring launch", context: "Content", members: ["producer", "scout", "quill"], instructions: "Plan the spring sale posts. Keep it to three posts.", messages: [
            RoomMessage(from: "you", text: "We need three posts for the spring sale. Ideas?", time: "9:02"),
            RoomMessage(from: "scout", text: "Searches for spring tune-ups are up this week. I'd lead with that.", time: "9:03"),
            RoomMessage(from: "quill", text: "I can draft the captions once we pick the three.", time: "9:03"),
            RoomMessage(from: "producer", text: "Plan: tune-up, commuter kit, kids' bikes. Quill, draft captions for all three.", time: "9:05", pinned: true, handoff: Handoff(from: "producer", to: "quill", verb: "Delegated", reason: "Draft captions for three posts", status: "Working", doneWhen: "Three captions under 120 characters")),
            RoomMessage(from: "quill", text: "On it. First draft in ten minutes.", time: "9:06"),
        ], working: ["quill"], unread: 2),
        BotRoom(id: "books", name: "Month end", context: "Operations", members: ["ledger", "kip"], whoAnswers: "Only mentioned bots answer", instructions: "Close the month's books.", messages: [
            RoomMessage(from: "ledger", text: "October receipts are filed. Two are missing a total.", time: "Mon"),
            RoomMessage(from: "you", text: "@Kip can you find those two in mail?", time: "Mon"),
            RoomMessage(from: "kip", text: "Found both. Totals added.", time: "Mon"),
        ]),
    ]

    static let handoffs: [Handoff] = [
        Handoff(from: "producer", to: "quill", verb: "Delegated", reason: "Draft captions for three posts", status: "Working", doneWhen: "Three captions under 120 characters"),
        Handoff(from: "kip", to: "scout", verb: "Asked", reason: "Two sources for the weekly report", status: "Done"),
        Handoff(from: "producer", to: "scout", verb: "Asked", reason: "What is trending in bike care", status: "Waiting for you"),
        Handoff(from: "ledger", to: "kip", verb: "Notified", reason: "October books are closed", status: "Done"),
    ]

    static let readyBots: [ReadyBot] = [
        ReadyBot(name: "Researcher", role: "Finds and checks sources", blurb: "Looks things up, reads the pages and gives you a short answer with links.", tryAsking: "Find three reviews of this lock and sum them up.", category: "Work", colorHex: Palette.botSand, shape: .round, accessory: .spectacles, routines: 0),
        ReadyBot(name: "Inbox triage", role: "Sorts your mail", blurb: "Reads new mail, files the noise and tells you what needs a reply.", tryAsking: "What needs a reply today?", category: "Work", colorHex: Palette.botPowder, shape: .squircle, accessory: .none, routines: 1),
        ReadyBot(name: "Writer", role: "Drafts and edits", blurb: "Writes posts, emails and pages in your voice.", tryAsking: "Draft a post about our spring tune-up.", category: "Writing", colorHex: Palette.botLilac, shape: .tall, accessory: .quill, routines: 0),
        ReadyBot(name: "Watcher", role: "Keeps an eye on things", blurb: "Checks a page or a feed on a schedule and tells you when something changes.", tryAsking: "Tell me when this price drops.", category: "Everyday", colorHex: Palette.botSage, shape: .ghost, accessory: .none, routines: 2),
        ReadyBot(name: "Bookkeeper", role: "Receipts and bills", blurb: "Files receipts, tracks bills and warns you before something is due.", tryAsking: "What bills are due this week?", category: "Money", colorHex: Palette.botGold, shape: .dome, accessory: .laurel, routines: 1),
        ReadyBot(name: "Trip planner", role: "Plans short trips", blurb: "Plans a trip with routes, times and a budget.", tryAsking: "Plan a weekend by the lake under $300.", category: "Everyday", colorHex: Palette.botRose, shape: .wide, accessory: .scarf, routines: 0),
        ReadyBot(name: "Coach", role: "Habits and goals", blurb: "Checks in each morning and keeps you to your plan.", tryAsking: "Help me ride to work three days a week.", category: "Everyday", colorHex: Palette.botPowder, shape: .scallop, accessory: .rays, routines: 1),
        ReadyBot(name: "Builder", role: "Code and fixes", blurb: "Works on code in a folder you choose and explains each change.", tryAsking: "Fix the broken link on the shop page.", category: "Work", colorHex: Palette.botGold, shape: .hex, accessory: .none, routines: 0),
    ]

    static let packageParts: [PackagePart] = [
        PackagePart(kind: "Bot", name: "Producer"),
        PackagePart(kind: "Bot", name: "Scout"),
        PackagePart(kind: "Bot", name: "Quill"),
        PackagePart(kind: "Skill", name: "price-check"),
        PackagePart(kind: "Connection", name: "Notes server", include: false),
        PackagePart(kind: "Preset", name: "Shop helper"),
    ]
}
