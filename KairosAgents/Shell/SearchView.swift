import SwiftUI

/// Search finds chats, bots, files, notes, settings and areas, and runs actions
/// ("new note", "call Kip", "pause the content team"). It stands in for the desktop command palette.
struct SearchView: View {
    var startQuery = ""
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var calling: Bot?
    @FocusState private var typing: Bool

    private struct Hit: Identifiable {
        let id: String
        let section: String
        let title: String
        let detail: String
        let symbol: String
        var bot: Bot? = nil
        var keywords = ""
        /// True when running it leaves Search open (a call over it).
        var stays = false
        let run: () -> Void
    }

    private static let order = ["Actions", "Bots", "Chats", "Files", "Notes", "Settings", "Areas", "Added tabs"]

    // MARK: Everything Search knows

    private var all: [Hit] {
        let you = YouStore.shared
        var hits: [Hit] = []

        // Actions
        hits.append(Hit(id: "a-chat", section: "Actions", title: "New chat", detail: "Start a chat with a model", symbol: "plus.bubble", keywords: "start ask") {
            router.push(.newChat, on: .home)
        })
        hits.append(Hit(id: "a-note", section: "Actions", title: "New note", detail: "Opens Notes", symbol: "square.and.pencil", keywords: "write jot") {
            router.open(.notes)
            chrome.say("Notes is open. Tap the gold circle for a new note.")
        })
        for bot in SampleData.allBots where bot.members.isEmpty {
            hits.append(Hit(id: "a-call-\(bot.id)", section: "Actions", title: "Call \(bot.name)", detail: bot.isKip ? "Talk it through" : bot.role, symbol: "phone", keywords: "ring voice talk", stays: true) {
                calling = bot
            })
        }
        let teamPaused = you.pausedTeams.contains(SampleData.contentTeam.id)
        hits.append(Hit(id: "a-pause-team", section: "Actions", title: teamPaused ? "Resume the content team" : "Pause the content team",
                        detail: teamPaused ? "It picks up where it stopped" : "Producer, Scout and Quill stop after this step", symbol: teamPaused ? "play.fill" : "pause.fill", keywords: "stop hold team") {
            you.toggleTeamPause(SampleData.contentTeam.id)
            chrome.say(teamPaused ? "Content team resumed" : "Content team paused")
        })
        hits.append(Hit(id: "a-brief", section: "Actions", title: "Run task: Morning brief", detail: "Calendar and mail, sent to you now", symbol: "bolt", keywords: "task run brief") {
            chrome.say("Running Morning brief...")
            Task {
                try? await Task.sleep(for: .seconds(2.6))
                chrome.say("Morning brief ran and delivered")
            }
        })
        hits.append(Hit(id: "a-forge", section: "Actions", title: "New Forge session", detail: "Code on your desktop", symbol: "hammer", keywords: "code project") {
            router.open(.forge)
        })
        hits.append(Hit(id: "a-settings", section: "Actions", title: "Open settings", detail: "Accounts and every setting", symbol: "gear", keywords: "preferences you", stays: true) {
            router.sheet = .you
        })
        hits.append(Hit(id: "a-tour", section: "Actions", title: "Take the tour", detail: "A short walk past the real controls", symbol: "hand.point.up.left", keywords: "help demo") {
            router.paths[.home] = []
            router.select(.home)
            TourPresenter.start(after: 0.6)
        })
        for account in you.accounts where account.id != you.currentID {
            hits.append(Hit(id: "a-switch-\(account.id)", section: "Actions", title: "Switch to \(account.name)", detail: "Account on this phone", symbol: "arrow.left.arrow.right", keywords: "account user", stays: true) {
                you.pendingRoute = .accounts
                router.sheet = .you
            })
        }

        // Bots
        for bot in SampleData.allBots {
            hits.append(Hit(id: "b-\(bot.id)", section: "Bots", title: bot.name, detail: bot.role, symbol: "", bot: bot) {
                router.push(.bot(bot.id), on: .home)
            })
        }

        // Chats
        for conversation in SampleData.conversations where conversation.kind == .model {
            hits.append(Hit(id: conversation.id, section: "Chats", title: conversation.title, detail: "\(conversation.preview) · \(conversation.time)", symbol: "sparkle") {
                router.open(conversation)
            })
        }

        // Files and notes
        for (index, entry) in SampleData.library(.files).enumerated() {
            hits.append(Hit(id: "f-\(index)", section: "Files", title: entry.title, detail: entry.detail, symbol: entry.symbol) {
                router.open(.vault)
            })
        }
        for document in SampleData.documents {
            hits.append(Hit(id: "d-\(document.id)", section: "Files", title: document.name, detail: document.details.joined(separator: " · "), symbol: "doc.text") {
                router.open(.vault)
            })
        }
        for (index, entry) in SampleData.library(.notes).enumerated() {
            hits.append(Hit(id: "n-\(index)", section: "Notes", title: entry.title, detail: entry.detail, symbol: "note.text") {
                router.open(.notes)
            })
        }

        // Settings
        for entry in YouIndex.all {
            hits.append(Hit(id: "s-\(entry.id)", section: "Settings", title: entry.title, detail: "Settings", symbol: entry.symbol, keywords: entry.keywords, stays: true) {
                you.pendingRoute = entry.route
                router.sheet = .you
            })
        }

        // Areas and added tabs
        for area in JumpArea.allCases {
            hits.append(Hit(id: "j-\(area.rawValue)", section: "Areas", title: area.title, detail: area.about, symbol: area.symbol) {
                router.open(area)
            })
        }
        for tab in SampleData.addedTabs {
            hits.append(Hit(id: "t-\(tab.id)", section: "Added tabs", title: tab.title, detail: "Your tab", symbol: tab.symbol) {
                router.push(.page(tab.title))
            })
        }
        return hits
    }

    /// What to show: a short start list when empty, every match when typing.
    private var sections: [(name: String, hits: [Hit])] {
        if router.debugScreen == "bots" {
            return [("Bots", Array(all.filter { $0.bot != nil }.reversed()))]
        }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let everything = all
        let chosen: [Hit]
        if needle.isEmpty {
            let starters: Set<String> = ["a-chat", "a-note", "a-call-kip", "a-pause-team", "a-brief"]
            chosen = everything.filter { starters.contains($0.id) || $0.section == "Bots" || $0.section == "Chats" || $0.section == "Areas" }
        } else {
            chosen = everything.filter { hit in
                hit.title.lowercased().contains(needle) || hit.detail.lowercased().contains(needle) || hit.keywords.contains(needle)
                    || needle.split(separator: " ").allSatisfy { word in hit.title.lowercased().contains(word) || hit.keywords.contains(word) }
            }
        }
        return Self.order.compactMap { name in
            let hits = chosen.filter { $0.section == name }
            let limit = needle.isEmpty && (name == "Chats") ? 4 : hits.count
            return hits.isEmpty ? nil : (name, Array(hits.prefix(limit)))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.inkFaint)
                TextField("Search or do something", text: $query)
                    .font(KFont.ui(17))
                    .foregroundStyle(Palette.ink)
                    .focused($typing)
                    .submitLabel(.go)
                    .autocorrectionDisabled()
                    .onSubmit { if let first = sections.first?.hits.first { run(first) } }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkFaint).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .frame(height: 50)
            .kCard(radius: 25, raised: true)
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(sections, id: \.name) { section in
                        if router.debugScreen != "bots" {
                            SectionLabel(text: section.name)
                                .padding(.top, 16)
                                .padding(.bottom, 4)
                        }
                        ForEach(section.hits) { hit in
                            row(hit)
                        }
                    }
                    if sections.isEmpty {
                        VStack(spacing: 6) {
                            Text("Nothing matches \"\(query)\".")
                                .font(KFont.ui(15.5, relativeTo: .subheadline))
                                .foregroundStyle(Palette.inkFaint)
                            Text("Try a bot's name, a chat, a setting, or an action like call Kip.")
                                .font(KFont.ui(14, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkFaint)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .kSheet()
        .fullScreenCover(item: $calling) { bot in
            CallView(bot: bot)
        }
        .onAppear {
            if !startQuery.isEmpty { query = startQuery }
            if router.debugScreen != "search" && router.debugScreen != "bots" && startQuery.isEmpty { typing = true }
        }
    }

    private func row(_ hit: Hit) -> some View {
        Button { run(hit) } label: {
            HStack(spacing: 13) {
                if let bot = hit.bot {
                    BotFace(bot: bot, size: router.debugScreen == "bots" ? 78 : 50, showStatus: true)
                } else {
                    Image(systemName: hit.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(hit.section == "Actions" ? Palette.onGold : Palette.goldText)
                        .frame(width: 40, height: 40)
                        .background(hit.section == "Actions" ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Circle())
                        .frame(width: 50, height: 50)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(hit.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
    }

    private func run(_ hit: Hit) {
        Haptics.select()
        if hit.stays {
            hit.run()
        } else {
            dismiss()
            hit.run()
        }
    }
}
