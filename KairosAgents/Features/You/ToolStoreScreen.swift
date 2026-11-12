import SwiftUI

// The Tool Store: skills, tool servers, add-ons, tabs (with source approval), automations,
// community items, design systems and the shared library. Sample data only.

// MARK: - Sample catalogue

nonisolated enum StoreKind: String, CaseIterable, Hashable, Sendable {
    case skill, tool, addon, tab, automation, community, design, shared

    var label: String {
        switch self {
        case .skill: "Skill"
        case .tool: "Tool"
        case .addon: "Add-on"
        case .tab: "Tab"
        case .automation: "Automation"
        case .community: "Community"
        case .design: "Design system"
        case .shared: "Shared"
        }
    }

    var symbol: String {
        switch self {
        case .skill: "bookmark"
        case .tool: "server.rack"
        case .addon: "puzzlepiece.extension"
        case .tab: "square.grid.2x2"
        case .automation: "bolt"
        case .community: "person.2"
        case .design: "paintpalette"
        case .shared: "tray"
        }
    }
}

nonisolated struct StoreItem: Identifiable, Hashable, Sendable {
    let id: String
    var kind: StoreKind
    var name: String
    var summary: String
    var origin: String
    var version = "1.0.0"
    var author = ""
    var added: Bool
    var on: Bool = true
    var prebuilt = false
    var needsApproval = false
    var needsSignIn = false
    var updateAvailable = false
    var revoked = false
    var unreadable = false
    var health = "Not checked yet"
    var heldTools: [String] = []
    var files: [String] = []
    var body = ""
    var symbol = "square.grid.2x2"
}

extension StoreItem {
    /// The short status word on the row.
    @MainActor var status: (text: String, tone: StatusPill.Tone) {
        if unreadable { return ("Can't be read", .bad) }
        if revoked { return ("Revoked", .bad) }
        if updateAvailable { return ("Update", .warn) }
        if needsApproval { return ("Needs approval", .warn) }
        if needsSignIn { return ("Needs sign-in", .warn) }
        if !added { return (kind == .community ? "Community" : "Not added", .muted) }
        if !on { return ("Off", .muted) }
        switch kind {
        case .tool: return ("Connected", .ok)
        case .addon: return ("Add-on", .ok)
        case .skill: return (origin == "Built into Kairos" ? "Built in" : "On", .ok)
        default: return ("On", .ok)
        }
    }
}

nonisolated struct StoreSubmission: Identifiable, Hashable, Sendable {
    let id: Int
    var title: String
    var state: String
}

@Observable
final class StoreSample {
    static let shared = StoreSample()

    var items: [StoreItem] = [
        StoreItem(id: "sk-report", kind: .skill, name: "weekly-report", summary: "Drafts the Friday report from this week's notes", origin: "Written in Kairos", added: true,
                  body: "# Weekly report\n\n1. Read this week's daily notes.\n2. List what shipped, what slipped and what is next.\n3. Keep it under one page."),
        StoreItem(id: "sk-pdf", kind: .skill, name: "pdf-tools", summary: "Split, merge and read PDFs", origin: "Built into Kairos", added: true, body: "# PDF tools\n\nUse these steps to read, split and merge PDF files."),
        StoreItem(id: "sk-price", kind: .skill, name: "price-check", summary: "Compares three shops for one item", origin: "Imported skill", version: "1.2.0", added: true, needsApproval: true,
                  body: "# Price check\n\nSearch three shops, note price and stock, and return a table.\n\nRuns a shell command to save the table."),
        StoreItem(id: "sk-broken", kind: .skill, name: "old-notes", summary: "", origin: "Local skill", added: true, unreadable: true),
        StoreItem(id: "tl-github", kind: .tool, name: "GitHub", summary: "Issues, pull requests and code search", origin: "Tool server", added: true, health: "Working · 24 tools · checked 9:30", heldTools: ["create_release", "delete_branch"]),
        StoreItem(id: "tl-maps", kind: .tool, name: "Maps", summary: "Places, routes and travel times", origin: "Tool server", added: false),
        StoreItem(id: "tl-cal", kind: .tool, name: "Team calendar", summary: "Shared events over OAuth", origin: "Tool server", added: true, needsSignIn: true, health: "Not signed in"),
        StoreItem(id: "tl-rea", kind: .tool, name: "REA", summary: "Lets models use apps on your desktop", origin: "Runs on your desktop", added: false),
        StoreItem(id: "ad-roblox", kind: .addon, name: "Game studio", summary: "A workspace for building games, with its own skills", origin: "Tool Store add-on", added: true, on: true,
                  files: ["game-scripting", "level-design"]),
        StoreItem(id: "ad-video", kind: .addon, name: "Video tools", summary: "Cut, caption and render videos", origin: "Tool Store add-on", added: false, files: ["captions", "render"]),
        StoreItem(id: "tb-studio", kind: .tab, name: "Studio", summary: "Make videos, edit them beat by beat and render them", origin: "Prebuilt", added: true, prebuilt: true, symbol: "film.stack"),
        StoreItem(id: "tb-crm", kind: .tab, name: "CRM", summary: "Keep track of people and deals", origin: "Prebuilt", added: true, prebuilt: true, symbol: "person.2"),
        StoreItem(id: "tb-habits", kind: .tab, name: "Habit tracker", summary: "Daily habits with streaks", origin: "Prebuilt", added: false, prebuilt: true, symbol: "checkmark.circle"),
        StoreItem(id: "tb-board", kind: .tab, name: "Team board", summary: "A small kanban for the shop", origin: "Yours", added: true, files: ["tab.json", "view.html", "style.css"], symbol: "sportscourt"),
        StoreItem(id: "tb-game", kind: .tab, name: "Game studio", summary: "Tracks game builds and tests", origin: "Yours", added: true, symbol: "cube"),
        StoreItem(id: "tb-stock", kind: .tab, name: "Stock count", summary: "Counts shelves with the camera", origin: "Yours", added: true, needsApproval: true, files: ["tab.json", "view.html", "count.js"], symbol: "shippingbox"),
        StoreItem(id: "au-brief", kind: .automation, name: "Morning brief", summary: "Calendar and mail at 8:00", origin: "Prebuilt", added: true),
        StoreItem(id: "au-backup", kind: .automation, name: "Weekly backup", summary: "Backs up every Sunday night", origin: "Prebuilt", added: false),
        StoreItem(id: "cm-recipes", kind: .community, name: "Recipe box", summary: "A tab for recipes and shopping lists", origin: "Community · tab", version: "2.1.0", author: "kitchen-tools", added: false),
        StoreItem(id: "cm-invoice", kind: .community, name: "invoice-writer", summary: "Turns notes into invoices", origin: "Community · skill", version: "1.4.0", author: "small-biz", added: true, updateAvailable: true),
        StoreItem(id: "cm-old", kind: .community, name: "feed-reader", summary: "Reads news feeds", origin: "Community · tool", version: "0.9.0", author: "reader-dev", added: true, revoked: true),
        StoreItem(id: "ds-kairos", kind: .design, name: "Kairos", summary: "Parchment, bistre and gold. Jost and Cormorant.", origin: "Default", added: true),
        StoreItem(id: "ds-shop", kind: .design, name: "Shop style", summary: "Made from three photos of the shop", origin: "Yours - private", added: true),
        StoreItem(id: "sh-trip", kind: .shared, name: "trip-budget", summary: "A skill Robin shared with this Kairos", origin: "Shared by Robin", added: false),
    ]
    var githubUser: String?
    var submissions: [StoreSubmission] = [StoreSubmission(id: 214, title: "Add invoice-writer 1.4.0", state: "Open")]

    func item(_ id: String) -> StoreItem? { items.first { $0.id == id } }

    func update(_ id: String, _ change: (inout StoreItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
}

// MARK: - The store

nonisolated enum StoreCategory: String, CaseIterable, Hashable, Sendable {
    case all = "All", skills = "Skills", tools = "Tools", tabs = "Tabs", automations = "Automations", designs = "Design systems", shared = "Shared library"
}

enum StoreSheet: String, Identifiable {
    case skillManager, customServer, githubSkill, installTab, github, brief
    var id: String { rawValue }
}

struct ToolStoreScreen: View {
    var startCategory: StoreCategory = .all
    var startSheet: StoreSheet? = nil
    @Bindable private var store = StoreSample.shared
    @State private var query = ""
    @State private var category: StoreCategory = .all
    @State private var addedOnly = false
    @State private var sheet: StoreSheet?
    @State private var refreshing = false
    @State private var buildTab = false

    var body: some View {
        SettingsPage("Tool Store", subtitle: "Find skills, connect tools and add tabs.") {
            addMenu
        } content: {
            HStack(spacing: 8) {
                SearchField(prompt: "Search skills, tools and tabs", text: $query)
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { addedOnly.toggle() }
                } label: {
                    Image(systemName: addedOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(addedOnly ? Palette.goldText : Palette.inkDim)
                        .frame(width: 46, height: 46)
                        .kCard(radius: 23, raised: true)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Show added items only")
                .accessibilityAddTraits(addedOnly ? .isSelected : [])
            }
            YouChipPicker(items: StoreCategory.allCases, selection: $category) { $0.rawValue }

            if let update = store.items.first(where: { $0.updateAvailable }) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle").foregroundStyle(Palette.goldText)
                    Text("\(update.name) has a community update.").font(KFont.ui(15)).foregroundStyle(Palette.ink)
                    Spacer()
                    NavigationLink(value: YouRoute.storeItem(update.id)) {
                        Text("Review update").font(KFont.ui(14, .medium, relativeTo: .footnote)).foregroundStyle(Palette.goldText).frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 16)
                .kCard(radius: 20, raised: true)
            }

            if category == .all && query.isEmpty && !addedOnly {
                Button { buildTab = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Palette.onGold)
                            .frame(width: 52, height: 52)
                            .background(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FEATURED").font(KFont.label).tracking(1.2).foregroundStyle(Palette.goldText)
                            Text("Build a custom tab").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                            Text("Describe it, and Kairos builds it.").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        }
                        Spacer()
                        Text("Start").font(KFont.ui(14, .semibold)).foregroundStyle(Palette.goldText)
                    }
                    .padding(14)
                    .kCard(radius: 22, raised: true)
                }
                .buttonStyle(PressStyle(scale: 0.98))
            }

            Text("\(results.count) \(results.count == 1 ? "result" : "results")")
                .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).padding(.horizontal, 8)

            if results.isEmpty {
                VStack(spacing: 10) {
                    Text(query.isEmpty ? "Nothing here yet" : "No matches").font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                    Text("Try another search or category.").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    YouPillButton(title: "Show all") {
                        withAnimation(Motion.snappy) {
                            query = ""
                            category = .all
                            addedOnly = false
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .kCard(radius: 22)
            }

            ForEach(sections, id: \.title) { section in
                SettingsGroup("\(section.title) · \(section.items.count)") {
                    ForEach(section.items) { item in
                        StoreRow(item: item)
                    }
                }
            }

            if category == .all || category == .tabs {
                YouNavRow(title: "Add a tab", detail: "Prebuilt tabs, your own, or build one", symbol: "plus.square.dashed", to: .addTab)
                    .kCard(radius: 22)
            }

            githubStrip
        }
        .sheet(item: $sheet) { which in
            StoreSheetView(which: which)
        }
        .navigationDestination(isPresented: $buildTab) { BuildTabScreen() }
        .youDestinations()
        .onAppear {
            category = startCategory
            if let startSheet { sheet = startSheet }
        }
    }

    private var addMenu: some View {
        Menu {
            if category != .tabs && category != .automations {
                Button("Manage skills", systemImage: "bookmark") { sheet = .skillManager }
            }
            Button("Add MCP server", systemImage: "server.rack") { sheet = .customServer }
            Button("Install a skill from GitHub", systemImage: "square.and.arrow.down") { sheet = .githubSkill }
            Button("Build with Kairos", systemImage: "wand.and.stars") { sheet = .brief }
            Button("Build a tab", systemImage: "plus.square.dashed") { buildTab = true }
            Button("Install a tab", systemImage: "tray.and.arrow.down") { sheet = .installTab }
            Button(refreshing ? "Refreshing..." : "Refresh community", systemImage: "arrow.clockwise") {
                refreshing = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    refreshing = false
                    YouStore.shared.say("The community list is up to date")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .kGlass(Circle(), interactive: true)
        }
        .accessibilityLabel("Add or manage")
    }

    private var githubStrip: some View {
        SettingsGroup("Sharing to the store", footer: "Submissions are public on GitHub and are reviewed before they appear.") {
            if let user = store.githubUser {
                ValueRow(title: "GitHub", value: user)
                ForEach(store.submissions) { submission in
                    StatusRow(title: "#\(submission.id) \(submission.title)", status: submission.state, tone: submission.state == "Merged" ? .ok : .working)
                }
                ActionRow(title: "Sign out of GitHub", symbol: "rectangle.portrait.and.arrow.right", tone: .danger) {
                    withAnimation(Motion.snappy) { store.githubUser = nil }
                }
            } else {
                Text("Sign in to see your submissions.").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                ActionRow(title: "Sign in with GitHub", symbol: "person.crop.circle", tone: .gold) { sheet = .github }
            }
        }
    }

    // MARK: Filtering

    private var results: [StoreItem] {
        let needle = query.lowercased()
        return store.items.filter { item in
            let inCategory: Bool
            switch category {
            case .all: inCategory = item.kind != .design && item.kind != .shared
            case .skills: inCategory = item.kind == .skill || (item.kind == .community && item.origin.hasSuffix("skill"))
            case .tools: inCategory = item.kind == .tool || item.kind == .addon
            case .tabs: inCategory = item.kind == .tab
            case .automations: inCategory = item.kind == .automation
            case .designs: inCategory = item.kind == .design
            case .shared: inCategory = item.kind == .shared
            }
            let matches = needle.isEmpty || item.name.lowercased().contains(needle) || item.summary.lowercased().contains(needle) || item.author.contains(needle)
            let addedOK = !addedOnly || item.added || item.kind == .skill || (item.kind == .tab && !item.prebuilt)
            return inCategory && matches && addedOK
        }
    }

    private var sections: [(title: String, items: [StoreItem])] {
        let all = results
        let parts: [(String, [StoreItem])] = [
            ("Skills", all.filter { $0.kind == .skill }),
            ("Tools", all.filter { ($0.kind == .tool || $0.kind == .addon) && $0.on }),
            ("Prebuilt", all.filter { $0.kind == .tab && $0.prebuilt && $0.on }),
            ("Yours", all.filter { $0.kind == .tab && !$0.prebuilt && $0.on }),
            ("Automations", all.filter { $0.kind == .automation }),
            ("Community", all.filter { $0.kind == .community }),
            ("Design systems", all.filter { $0.kind == .design }),
            ("Shared library", all.filter { $0.kind == .shared }),
            ("Turned off", all.filter { ($0.kind == .tool || $0.kind == .addon || $0.kind == .tab) && !$0.on }),
        ]
        return parts.filter { !$0.1.isEmpty }.map { (title: $0.0, items: $0.1) }
    }
}

/// One dense row: icon tile, name, status pill.
struct StoreRow: View {
    let item: StoreItem

    var body: some View {
        NavigationLink(value: YouRoute.storeItem(item.id)) {
            HStack(spacing: 12) {
                Group {
                    if item.kind == .skill || item.kind == .community {
                        Text(String(item.name.prefix(1)).uppercased()).font(KFont.ui(16, .semibold))
                    } else {
                        Image(systemName: item.kind == .tab ? item.symbol : item.kind.symbol).font(.system(size: 16, weight: .medium))
                    }
                }
                .foregroundStyle(Palette.goldText)
                .frame(width: 38, height: 38)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(pretty(item.name)).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(item.summary.isEmpty ? "No description provided." : item.summary).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                Spacer(minLength: 4)
                StatusPill(text: item.status.text, tone: item.status.tone)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .accessibilityLabel("\(pretty(item.name)), \(item.status.text). Open details")
    }

    private func pretty(_ name: String) -> String {
        guard item.kind == .skill || item.kind == .community || item.kind == .shared else { return name }
        let spaced = name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
