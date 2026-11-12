import Foundation

/// Made-up Tasks content, placed around the current time so the screens always look alive.
/// Nothing here is real, and nothing here is anyone's data.
struct TasksSampleProvider: TasksProviding {
    private func ago(_ minutes: Double) -> Date { Date().addingTimeInterval(-minutes * 60) }
    private func at(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    func loadCards() -> [WorkCard] {
        [
            WorkCard(id: "c-newsletter", name: "Draft the spring newsletter",
                     instructions: "Write a short spring newsletter for the bike shop: new arrivals, the service special and opening hours.",
                     column: .review, agentID: "quill", model: "Claude Opus",
                     result: "Draft ready: 320 words, three sections and a subject line. The service special is at the top.",
                     created: ago(600),
                     runs: [RunRecord(id: "r-news-1", started: ago(52), finished: ago(49), seconds: 184, outcome: "succeeded",
                                      model: "Claude Opus", attempt: 1,
                                      output: "Draft ready: 320 words, three sections and a subject line.",
                                      steps: [RunStep(time: ago(52), label: "Started"),
                                              RunStep(time: ago(51), label: "Read the shop notes", tool: "vault_search", seconds: 2.4),
                                              RunStep(time: ago(49), label: "Finished")])]),
            WorkCard(id: "c-quotes", name: "Compare three rental quotes",
                     instructions: "Compare the three van rental quotes in my notes and pick the best for a two day trip.",
                     column: .ready, agentID: "atlas", created: ago(300)),
            WorkCard(id: "c-poster", name: "Make the sale poster",
                     instructions: "A simple A4 poster for the weekend sale, using the newsletter's wording.",
                     column: .ready, waitsFor: ["c-newsletter"], created: ago(240)),
            WorkCard(id: "c-stock", name: "Count the helmet stock",
                     instructions: "Read the stock sheet and list helmets under five units.",
                     column: .running, agentID: "scout", startedAt: ago(3), created: ago(200)),
            WorkCard(id: "c-reviews", name: "Answer new shop reviews",
                     instructions: "Draft short replies to this week's reviews. Do not post them.",
                     column: .backlog, created: ago(900)),
            WorkCard(id: "c-receipts", name: "File October receipts",
                     instructions: "Match the October receipts to the bank export.",
                     column: .done, agentID: "ledger", result: "All 41 receipts matched. Two were duplicates and are marked.",
                     created: ago(3000)),
            WorkCard(id: "c-issue", name: "Fix the broken booking link",
                     instructions: "The booking page link in the footer is broken. Find the right link and update the page draft.",
                     column: .blocked, agentID: "mason", attempt: 2, fromTrigger: "GitHub pushes",
                     error: "The page draft is locked by another change. Try again once it is saved.",
                     created: ago(400),
                     runs: [RunRecord(id: "r-issue-2", started: ago(90), seconds: 41, outcome: "failed", model: "Claude Sonnet", attempt: 2,
                                      error: "The page draft is locked by another change.", steps: []),
                            RunRecord(id: "r-issue-1", started: ago(160), seconds: 63, outcome: "incomplete", model: "Claude Sonnet", attempt: 1,
                                      output: "Found the right link but could not save.", steps: nil)]),
        ]
    }

    func loadJobs() -> [ScheduledJob] {
        [
            ScheduledJob(id: "j-morning", name: "Morning summary",
                         prompt: "Summarise today's calendar, open notes and anything waiting on me, in five lines.",
                         kind: .daily, dailyHour: 6, dailyMinute: 30, deliver: "Discord",
                         runs: morningRuns()),
            ScheduledJob(id: "j-stock", name: "Check the bike shop stock",
                         prompt: "Read the stock sheet and list anything under five units.",
                         kind: .interval, intervalMinutes: 120, model: "Claude Opus",
                         runs: [RunRecord(id: "r-stock-1", started: ago(70), seconds: 38, outcome: "succeeded", model: "Claude Opus", attempt: 1,
                                          output: "Low: helmets (3), inner tubes 700c (4). Everything else is fine.",
                                          steps: [RunStep(time: ago(70), label: "Started"),
                                                  RunStep(time: ago(70), label: "Opened the stock sheet", tool: "sheets_read", seconds: 3.1),
                                                  RunStep(time: ago(69), label: "Finished")])]),
            ScheduledJob(id: "j-invoice", name: "Weekly invoice reminder",
                         prompt: "Every Friday, list unpaid invoices older than 14 days and draft a polite reminder for each.",
                         kind: .daily, dailyHour: 9, dailyMinute: 0, deliver: "Slack", agentID: "ledger",
                         runs: [RunRecord(id: "r-inv-1", started: at(daysAgo: 1, hour: 9), seconds: 3720, outcome: "failed", model: "Claude Sonnet", attempt: 1,
                                          error: "The invoice folder could not be opened.", delivery: .legacyFailed("channel missing"), steps: nil)]),
            ScheduledJob(id: "j-dentist", name: "Remind me about the dentist",
                         prompt: "Remind me to bring the insurance card.",
                         kind: .once, runAt: at(daysAgo: 3, hour: 8), enabled: false,
                         runs: [RunRecord(id: "r-dent-1", started: at(daysAgo: 3, hour: 8), seconds: 4, outcome: "succeeded", attempt: 1,
                                          output: "Bring the insurance card to the 10:30 appointment.", steps: [])]),
            ScheduledJob(id: "j-garden", name: "Water the garden reminder",
                         prompt: "Remind me to water the raised beds if it did not rain.",
                         kind: .daily, dailyHour: 19, dailyMinute: 0, enabled: false, runs: []),
        ]
    }

    private func morningRuns() -> [RunRecord] {
        var runs: [RunRecord] = [
            RunRecord(id: "r-morning-1", started: at(daysAgo: 0, hour: 6, minute: 30), seconds: 42, outcome: "succeeded",
                      model: "Claude Sonnet", attempt: 1,
                      output: "Three events today: standup at 9, stock check at 2, book club at 7. Two notes are due. Scout is waiting for your answer.",
                      delivery: .delivered("Discord"),
                      steps: [RunStep(time: at(daysAgo: 0, hour: 6, minute: 30), label: "Started"),
                              RunStep(time: at(daysAgo: 0, hour: 6, minute: 30), label: "Read the calendar", tool: "calendar_list", seconds: 1.8),
                              RunStep(time: at(daysAgo: 0, hour: 6, minute: 30), label: "Read open notes", tool: "notes_list", seconds: 0.9),
                              RunStep(time: at(daysAgo: 0, hour: 6, minute: 31), label: "Finished")]),
            RunRecord(id: "r-morning-2", started: at(daysAgo: 1, hour: 6, minute: 34), seconds: 51, outcome: "succeeded",
                      model: "Claude Sonnet", attempt: 1, lateFrom: at(daysAgo: 1, hour: 6, minute: 30),
                      output: "Two events today and one note due. Nothing waiting on you.",
                      delivery: .abandoned("Discord"),
                      steps: [RunStep(time: at(daysAgo: 1, hour: 6, minute: 34), label: "Started"),
                              RunStep(time: at(daysAgo: 1, hour: 6, minute: 34), label: "Read the calendar", tool: "calendar_list", seconds: 2.2),
                              RunStep(time: at(daysAgo: 1, hour: 6, minute: 35), label: "Finished")]),
            RunRecord(id: "r-morning-3", started: at(daysAgo: 2, hour: 6, minute: 30), seconds: 47, outcome: "succeeded",
                      model: "Claude Sonnet", attempt: 1, output: "A quiet day: one event at 4.",
                      delivery: .interrupted("Discord"), steps: []),
            RunRecord(id: "r-morning-4", started: at(daysAgo: 3, hour: 6, minute: 30), seconds: nil, outcome: "incomplete",
                      model: "Claude Sonnet", attempt: 1, delivery: .retrying(next: Date().addingTimeInterval(1500), attempts: 2, to: "Discord"), steps: nil),
            RunRecord(id: "r-morning-5", started: at(daysAgo: 4, hour: 6, minute: 30), seconds: 39, outcome: "succeeded",
                      model: "Claude Sonnet", attempt: 1, output: "Four events. The report is due Friday.", delivery: .delivered(nil), steps: []),
        ]
        for day in 5..<14 {
            runs.append(RunRecord(id: "r-morning-\(day + 1)", started: at(daysAgo: day, hour: 6, minute: 30), seconds: Double(35 + day),
                                  outcome: day == 9 ? "stopped" : "succeeded", model: "Claude Sonnet", attempt: 1,
                                  output: day == 9 ? nil : "A normal day: \(day % 4 + 1) events.",
                                  delivery: .delivered("Discord"), steps: []))
        }
        return runs
    }

    func loadRoutines() -> [JobRoutine] {
        [
            JobRoutine(id: "triage-email", label: "Triage email", about: "Reads unread mail each morning and flags what needs you.",
                       usesModel: true, hour: 5, deliver: TasksOptions.tabOnly, enabled: false),
            JobRoutine(id: "daily-brief", label: "Daily brief", about: "Your day in a few lines: events, notes due and open work.",
                       usesModel: true, hour: 7, enabled: false),
            JobRoutine(id: "backup-vault", label: "Back up the vault", about: "Copies your notes folder to the backup folder.",
                       usesModel: false, everyHours: 6, enabled: false),
            JobRoutine(id: "tidy-downloads", label: "Tidy downloads", about: "Moves old downloads into dated folders.",
                       usesModel: false, everyHours: 24, enabled: false),
        ]
    }

    func loadTriggers() -> [TrigRule] {
        [
            TrigRule(id: "tr-github", name: "GitHub pushes", source: .github, action: .card, agentID: "mason",
                     events: "push, pull_request", cardTitle: "Check {repository.name}: {head_commit.message}",
                     instructions: "Look at what changed and say if the booking page still works.",
                     lastEvent: ago(95), address: "https://your-kairos.example/hooks/t/gh41c2",
                     recent: [TrigEvent(name: "pull_request", at: ago(12), detail: "Fix footer link", outcome: "waiting"),
                              TrigEvent(name: "push", at: ago(95), detail: "main", outcome: "approved"),
                              TrigEvent(name: "issues", at: ago(400), outcome: "filtered"),
                              TrigEvent(name: "push", at: ago(1400), outcome: "duplicate"),
                              TrigEvent(name: "ping", at: ago(5000), outcome: "setup")]),
            TrigRule(id: "tr-orders", name: "Website order form", source: .generic, action: .card,
                     autoRun: true, conditionPath: "order.type", conditionValue: "repair",
                     cardTitle: "Repair booking from {customer.first_name}",
                     instructions: "Add the booking to the calendar and draft a confirmation email. Do not send it.",
                     lastEvent: ago(30), address: "https://your-kairos.example/hooks/t/ord7k9",
                     recent: [TrigEvent(name: "order.created", at: ago(30), detail: "Repair, Saturday", outcome: "started"),
                              TrigEvent(name: "order.created", at: ago(800), outcome: "rejected"),
                              TrigEvent(name: "order.created", at: ago(900), outcome: "too_many"),
                              TrigEvent(name: "order.updated", at: ago(2000), outcome: "replayed")]),
            TrigRule(id: "tr-stock", name: "Supplier price list", source: .generic, action: .task, jobID: "j-stock",
                     enabled: false, address: "https://your-kairos.example/hooks/t/sup3m1"),
            TrigRule(id: "tr-old", name: "Old form", source: .generic, action: .task, jobMissing: true,
                     enabled: false, address: "https://your-kairos.example/hooks/t/old0a0"),
        ]
    }

    func loadRequests() -> [TrigRequest] {
        [TrigRequest(id: "q-1", triggerID: "tr-github", triggerName: "GitHub pushes",
                     summary: "Pull request: Fix footer link", eventType: "pull_request", at: ago(12))]
    }

    func loadActivity() -> [TasksActivityRun] {
        var runs: [TasksActivityRun] = []
        var seed: UInt64 = 7
        func next() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed >> 33
        }
        for day in 0..<360 {
            let perDay = Int(next() % 4)
            for _ in 0..<perDay {
                let hour = [6, 8, 10, 12, 14, 16, 19][Int(next() % 7)]
                runs.append(TasksActivityRun(at: at(daysAgo: day, hour: hour, minute: Int(next() % 50)), ok: next() % 9 != 0))
            }
        }
        return runs.filter { $0.at <= Date() }
    }

    // Helpers the store uses for simulated work.

    static func freshOutput(for name: String) -> String {
        "\(name): done. Everything looked normal, and nothing needs you right now."
    }

    static func makeSecret() -> String {
        let letters = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return "whsec_" + String((0..<24).map { _ in letters.randomElement() ?? "a" })
    }
}
