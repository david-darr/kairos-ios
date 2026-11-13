import Foundation

/// Made-up live work and widget numbers, so every design can be seen before a desktop is paired.
/// Generic on purpose: a bike shop, a weekly report. Nobody's real data.
nonisolated enum NativeSample {
    static let scoutColor: UInt32 = 0xE8C39E
    static let quillColor: UInt32 = 0xCDBFD9
    static let producerColor: UInt32 = 0xB9D2E3
    static let masonColor: UInt32 = 0xD9B260
    static let ledgerColor: UInt32 = 0xB5C7A5

    static let scout = ActivityHelper(name: "Scout", colorHex: scoutColor, doing: "finding sources")
    static let quill = ActivityHelper(name: "Quill", colorHex: quillColor, doing: "writing")

    // MARK: Live Activities, one per kind

    static func attributes(_ kind: ActivityKind) -> KairosActivityAttributes {
        switch kind {
        case .reply:
            KairosActivityAttributes(id: "run_reply", kind: .reply, title: "Bike shop launch", botID: "kip", botName: "Kip",
                                     link: NativeLink.chat("c-bike").url.absoluteString)
        case .task:
            KairosActivityAttributes(id: "run_task", kind: .task, title: "File this week's receipts", botID: "ledger", botName: "Ledger",
                                     botColor: ledgerColor, botShape: "dome", link: NativeLink.bot("ledger").url.absoluteString)
        case .team:
            KairosActivityAttributes(id: "cycle_1", kind: .team, title: "Content team", botID: "producer", botName: "Producer",
                                     botColor: producerColor, botShape: "squircle", stages: ["Research", "Script", "Render", "Post"],
                                     link: NativeLink.bot("content-team").url.absoluteString)
        case .render:
            KairosActivityAttributes(id: "render_1", kind: .render, title: "Five tools for small shops", botID: "producer", botName: "Producer",
                                     botColor: producerColor, botShape: "squircle", stages: ["Render", "Upload"],
                                     link: NativeLink.area("studio").url.absoluteString)
        case .forge:
            KairosActivityAttributes(id: "forge_1", kind: .forge, title: "Mobile layout prototype", botID: "mason", botName: "Mason",
                                     botColor: masonColor, botShape: "hex", stages: ["Build", "Test"],
                                     link: NativeLink.area("forge").url.absoluteString)
        case .call:
            KairosActivityAttributes(id: "ring_1", kind: .call, title: "Call with Kip", botID: "kip", botName: "Kip",
                                     link: NativeLink.call("kip").url.absoluteString)
        }
    }

    static func running(_ kind: ActivityKind, startedAt: Date = Date(timeIntervalSinceNow: -134)) -> KairosActivityAttributes.ContentState {
        switch kind {
        case .reply:
            .init(step: "Reading your notes", detail: "Saving to Library", helpers: [scout, quill], startedAt: startedAt,
                  previous: "Searching your files")
        case .task:
            .init(step: "Filing 12 of 27 receipts", detail: "Routine · every Friday", progress: 0.44, startedAt: startedAt)
        case .team:
            .init(step: "Rendering today's video", detail: "Posts at 6:00", progress: 0.6, stage: 2,
                  helpers: [ActivityHelper(name: "Producer", colorHex: producerColor, doing: "rendering"), quill], startedAt: startedAt)
        case .render:
            .init(step: "Uploading to YouTube", detail: "YouTube · Private", progress: 0.62, stage: 1, startedAt: startedAt)
        case .forge:
            .init(step: "Running 48 tests", detail: "shop-site · +412 −36", progress: 0.7, stage: 1, startedAt: startedAt)
        case .call:
            .init(step: "On a call", detail: "Kairos call", startedAt: startedAt)
        }
    }

    static func done(_ kind: ActivityKind) -> KairosActivityAttributes.ContentState {
        var state = running(kind)
        state.phase = .done
        state.progress = 1
        state.stage = max(0, attributes(kind).stages.count - 1)
        state.detail = kind == .reply ? "Saved to Library" : state.detail
        return state
    }

    static func failed(_ kind: ActivityKind) -> KairosActivityAttributes.ContentState {
        var state = running(kind)
        state.phase = .failed
        state.detail = kind == .render ? "upload refused" : "model offline"
        return state
    }

    /// One kind of activity in each state, for the gallery. Sample states only: the phone shows these before pairing.
    static func state(_ kind: ActivityKind, _ mood: BotMood) -> KairosActivityAttributes.ContentState {
        switch mood {
        case .working: return running(kind)
        case .needsYou:
            var state = running(kind)
            state.phase = .waiting
            state.previous = nil
            return state
        case .done: return done(kind)
        case .failed: return failed(kind)
        case .idle:
            var state = running(kind)
            state.phase = .stopped
            return state
        case .offline:
            var state = running(kind)
            state.step = "Open Kairos to refresh"
            state.previous = nil
            state.stale = true
            return state
        }
    }

    // MARK: Widgets

    /// The sample widgets in one state, for the gallery.
    static func snapshot(_ mood: BotMood, now: Date = .now) -> WidgetSnapshot {
        var sample = snapshot(now: now)
        switch mood {
        case .working:
            sample.needsYou = []
        case .needsYou:
            sample.running[0].waiting = true
        case .done, .failed:
            sample.running = []
            sample.needsYou = []
            sample.ended = .init(title: "Drafting your report", botName: "Kip", botColor: nil, failed: mood == .failed,
                                   at: now.addingTimeInterval(-4 * 60), link: NativeLink.bot(NativeLink.kip).url.absoluteString, isKip: true)
            sample.team?.stage = 3
            sample.team?.note = mood == .failed ? "Posting stopped" : "Today's video is up"
        case .idle:
            sample.running = []
            sample.needsYou = []
            sample.team?.paused = true
        case .offline:
            return WidgetSnapshot(updatedAt: now, connected: false)
        }
        return sample
    }

    /// The sample widgets as a paired phone shows work it last saw 20 minutes ago, for the gallery.
    static func staleSnapshot(now: Date = .now) -> WidgetSnapshot {
        var sample = snapshot(now: now.addingTimeInterval(-20 * 60))
        sample.isSample = nil
        sample.needsYou = []
        return sample.shown(at: now)
    }

    static func snapshot(now: Date = .now) -> WidgetSnapshot {
        let calendar = Calendar.current
        let friday = calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 6), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        return WidgetSnapshot(
            updatedAt: now,
            connected: true,
            needsYou: [
                .init(id: "q1", botID: "scout", botName: "Scout", botColor: scoutColor, kind: "Question",
                      link: NativeLink.bot("scout").url.absoluteString),
                .init(id: "a1", botID: "kip", botName: "Kip", botColor: nil, kind: "Approval",
                      link: NativeLink.approval(requestID: "a1", botID: "kip").url.absoluteString),
            ],
            running: [
                .init(id: "r1", title: "Drafting your report", botName: "Kip", botColor: nil, progress: 0.58, step: "Writing",
                      link: NativeLink.bot("kip").url.absoluteString, botID: "kip", isKip: true,
                      startedAt: now.addingTimeInterval(-134), previousStep: "Reading your notes"),
                .init(id: "r2", title: "Check zip tie availability", botName: "Claude", botColor: nil, progress: nil, step: "Searching",
                      link: NativeLink.chat("c-zip").url.absoluteString, startedAt: now.addingTimeInterval(-48)),
                .init(id: "r3", title: "File this week's receipts", botName: "Ledger", botColor: ledgerColor, botShape: "dome", progress: 0.44,
                      step: "12 of 27", link: NativeLink.bot("ledger").url.absoluteString, botID: "ledger",
                      startedAt: now.addingTimeInterval(-610), previousStep: "11 of 27"),
            ],
            team: .init(id: "content-team", name: "Content team", stages: ["Research", "Script", "Render", "Post"], stage: 2,
                        note: "Rendering today's video", memberColors: [producerColor, scoutColor, quillColor]),
            post: .init(title: "Five tools for small shops", platform: "YouTube", views: 1240, likes: 86, comments: 12,
                        postedAt: now.addingTimeInterval(-3 * 3600), needsTap: 1),
            spend: .init(spent: 18.4, cap: 40),
            nextEvent: .init(title: "Report due", startsAt: friday, allDay: false),
            usage: [
                .init(provider: "Claude", percent: 64, resetsAt: now.addingTimeInterval(2 * 86_400)),
                .init(provider: "Codex", percent: 22, resetsAt: now.addingTimeInterval(5 * 86_400)),
                .init(provider: "Gemini", percent: 8, resetsAt: nil),
            ],
            desktop: .init(name: "Your PC", online: true, sessions: [
                .init(id: "f1", title: "Mobile layout prototype", project: "shop-site", added: 412, removed: 36, waiting: true),
                .init(id: "f2", title: "Faster image loading", project: "shop-site", added: 88, removed: 120, waiting: false),
            ]),
            pinned: .init(title: "CRM", symbol: "person.2"),
            isSample: true
        )
    }
}
