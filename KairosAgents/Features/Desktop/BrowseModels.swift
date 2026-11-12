import SwiftUI

// MARK: - Plain data

nonisolated struct BrowseTab: Identifiable, Hashable, Sendable {
    let id: String
    /// Empty for a blank tab, which shows Speed Dial.
    var url: String
    var title: String
    var pinned = false
    var muted = false
    var audible = false
    var back: [String] = []
    var forward: [String] = []
    var blocked = 0
    /// Devices the page holds: "camera", "microphone", "screen".
    var holding: [String] = []
    var prompt: BrowsePrompt? = nil
    var notice: String? = nil
    var popup: String? = nil
    var offer: PasswordOffer? = nil

    var host: String { BrowseAddress.host(of: url) }
    var isBlank: Bool { url.isEmpty }
    var shownTitle: String { isBlank ? "New tab" : (title.isEmpty ? host : title) }
    var secure: Bool { url.hasPrefix("https://") }
}

nonisolated struct BrowsePrompt: Hashable, Sendable {
    var site: String
    var devices: [String]
}

nonisolated struct PasswordOffer: Hashable, Sendable {
    var host: String
    var user: String
    var saved = false
}

nonisolated struct SpeedSite: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var url: String
    var colorHex: UInt32
    var host: String { BrowseAddress.host(of: url) }
}

nonisolated struct HistoryVisit: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var url: String
    var when: String
    var minutesAgo: Int
    var host: String { BrowseAddress.host(of: url) }
}

nonisolated enum DownloadState: Hashable, Sendable {
    case downloading(Int), paused(Int), done, cancelled, failed

    var label: String {
        switch self {
        case .downloading(let p): "\(p)%"
        case .paused: "Paused"
        case .done: "Done"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }
}

nonisolated struct BrowseDownload: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var host: String
    var state: DownloadState
}

nonisolated struct BrowseLogin: Identifiable, Hashable, Sendable {
    let id: String
    var host: String
    var user: String
    var lastUsed: String
}

nonisolated struct BotLoginUse: Identifiable, Hashable, Sendable {
    let id: String
    var bot: String
    var host: String
    var user: String
    var when: String
}

nonisolated enum SiteAnswer: String, CaseIterable, Hashable, Sendable {
    case ask = "Ask", allow = "Allow", block = "Block"
}

nonisolated enum SitePermission: String, CaseIterable, Hashable, Sendable {
    case camera = "Camera", microphone = "Microphone", location = "Location"
    case notifications = "Notifications", clipboard = "Read the clipboard", screen = "Screen sharing"

    var symbol: String {
        switch self {
        case .camera: "camera"
        case .microphone: "mic"
        case .location: "location"
        case .notifications: "bell"
        case .clipboard: "doc.on.clipboard"
        case .screen: "rectangle.on.rectangle"
        }
    }

    /// Screen sharing can only be asked or blocked.
    var answers: [SiteAnswer] { self == .screen ? [.ask, .block] : SiteAnswer.allCases }
}

nonisolated struct SiteSettings: Hashable, Sendable {
    var adsBlocked = true
    var answers: [SitePermission: SiteAnswer] = [:]
    var popupsAllowed = false
    var zoom = 100

    func answer(_ p: SitePermission) -> SiteAnswer { answers[p] ?? .ask }
    var remembered: [SitePermission] { SitePermission.allCases.filter { answer($0) != .ask } }
}

nonisolated struct BotPageWork: Identifiable, Hashable, Sendable {
    let id: String
    var botID: String
    var bot: String
    var page: String
}

nonisolated enum SearchEngine: String, CaseIterable, Hashable, Sendable {
    case duckDuckGo = "DuckDuckGo", google = "Google", bing = "Bing", brave = "Brave Search"
}

nonisolated enum BrowseLook: String, CaseIterable, Hashable, Sendable {
    case kairos = "Same as Kairos", parchment = "Parchment", colour = "Colour", glass = "Liquid glass", animated = "Animated", flow = "Flow"
}

nonisolated enum HomeBackground: String, CaseIterable, Hashable, Sendable {
    case kairos = "Kairos background", colour = "Colour", picture = "My picture"
}

nonisolated enum TileSize: String, CaseIterable, Hashable, Sendable {
    case small = "Small", medium = "Medium", large = "Large"
}

nonisolated struct HomeSettings: Hashable, Sendable {
    var background: HomeBackground = .kairos
    var dim: Double = 0.2
    var tiles: TileSize = .medium
    var showSearch = true
    var showSuggestions = true
}

// MARK: - Addresses

nonisolated enum BrowseAddress {
    static func host(of url: String) -> String {
        var rest = url
        if let range = rest.range(of: "://") { rest = String(rest[range.upperBound...]) }
        if let slash = rest.firstIndex(of: "/") { rest = String(rest[..<slash]) }
        if let query = rest.firstIndex(of: "?") { rest = String(rest[..<query]) }
        return rest
    }

    nonisolated enum Parsed: Equatable, Sendable { case open(String), search(String), refused }

    /// Bare hostnames open over https; localhost and host:port over http; other text is a search.
    static func parse(_ text: String) -> Parsed {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return .refused }
        let lower = input.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return .open(input) }
        if lower.contains("://") || lower.hasPrefix("javascript:") || lower.hasPrefix("file:") || lower.hasPrefix("data:") { return .refused }
        if input.contains(" ") { return .search(input) }
        if lower.hasPrefix("localhost") || lower.range(of: #"^\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) != nil { return .open("http://" + input) }
        if lower.contains(":"), !lower.contains(".") { return .open("http://" + input) }
        if lower.contains(".") { return .open("https://" + input) }
        return .search(input)
    }
}

// MARK: - Store

/// What Browse reads and changes. The sample store keeps everything on the phone;
/// the real one will drive the Browse tabs in the desktop app and keep the same shape.
protocol BrowseProviding: AnyObject {
    var tabs: [BrowseTab] { get }
    var history: [HistoryVisit] { get }
    var downloads: [BrowseDownload] { get }
    var logins: [BrowseLogin] { get }
}

@Observable
final class BrowseStore: BrowseProviding {
    static let shared = BrowseStore()

    var tabs: [BrowseTab] = BrowseSample.tabs
    var activeID = "t-bikes"
    var closed: [BrowseTab] = []
    var speedDial = BrowseSample.speedDial
    var history = BrowseSample.history
    var downloads = BrowseSample.downloads
    var logins = BrowseSample.logins
    var neverSave = ["coupons.example"]
    var botsUseLogins = true
    var botUses = BrowseSample.botUses
    var sites: [String: SiteSettings] = BrowseSample.sites
    var engine: SearchEngine = .google
    var soundOutput = "System default"
    let soundOutputs = ["System default", "Desk speakers", "USB headset (not connected)"]
    var look: BrowseLook = .kairos
    var chameleon = false
    var home = HomeSettings()
    var botWork = BrowseSample.botWork
    var loading = false
    private var loadTask: Task<Void, Never>?

    var active: BrowseTab { tabs.first { $0.id == activeID } ?? tabs.first ?? BrowseTab(id: "t-new", url: "", title: "") }
    var orderedTabs: [BrowseTab] { tabs.filter(\.pinned) + tabs.filter { !$0.pinned } }

    func site(_ host: String) -> SiteSettings { sites[host] ?? SiteSettings() }
    func setSite(_ host: String, _ change: (inout SiteSettings) -> Void) {
        var value = site(host)
        change(&value)
        sites[host] = value
    }

    private func edit(_ id: String, _ change: (inout BrowseTab) -> Void) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        change(&tabs[i])
    }

    func editActive(_ change: (inout BrowseTab) -> Void) { edit(activeID, change) }

    // MARK: Navigation

    /// Returns a message when the address cannot be opened.
    @discardableResult
    func go(_ text: String, newTab: Bool = false) -> String? {
        let url: String
        switch BrowseAddress.parse(text) {
        case .refused: return "That address can't be opened here."
        case .open(let address): url = address
        case .search(let query):
            let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            url = "https://search.example/?engine=\(engine.rawValue.replacingOccurrences(of: " ", with: "+"))&q=\(q)"
        }
        if newTab || tabs.isEmpty { openNewTab(select: true) }
        let previous = active.url
        editActive { tab in
            if !previous.isEmpty { tab.back.append(previous) }
            tab.forward = []
            tab.url = url
            tab.title = BrowseSample.title(for: url)
            tab.blocked = BrowseSample.blockedCount(for: url, on: self.site(BrowseAddress.host(of: url)).adsBlocked)
            tab.notice = nil
            tab.holding = []
            tab.prompt = nil
        }
        visit(url)
        startLoading()
        return nil
    }

    private func visit(_ url: String) {
        history.insert(HistoryVisit(id: UUID().uuidString, title: BrowseSample.title(for: url), url: url, when: "Just now", minutesAgo: 0), at: 0)
    }

    func goBack() {
        editActive { tab in
            guard let last = tab.back.popLast() else { return }
            tab.forward.append(tab.url)
            tab.url = last
            tab.title = BrowseSample.title(for: last)
            tab.holding = []
        }
        startLoading()
    }

    func goForward() {
        editActive { tab in
            guard let next = tab.forward.popLast() else { return }
            tab.back.append(tab.url)
            tab.url = next
            tab.title = BrowseSample.title(for: next)
            tab.holding = []
        }
        startLoading()
    }

    func reload() {
        editActive { tab in
            tab.notice = nil
            tab.holding = []
        }
        startLoading()
    }

    func stopLoading() {
        loadTask?.cancel()
        withAnimation(Motion.gentle) { loading = false }
    }

    private func startLoading() {
        loadTask?.cancel()
        loading = true
        loadTask = Task {
            try? await Task.sleep(for: .seconds(0.9))
            if !Task.isCancelled { withAnimation(Motion.gentle) { loading = false } }
        }
    }

    // MARK: Tabs

    func openNewTab(select: Bool = true) {
        let tab = BrowseTab(id: UUID().uuidString, url: "", title: "")
        if let i = tabs.firstIndex(where: { $0.id == activeID }) {
            tabs.insert(tab, at: i + 1)
        } else {
            tabs.append(tab)
        }
        if select { activeID = tab.id }
    }

    /// Home: an existing blank tab, or a new one.
    func goHome() {
        if let blank = tabs.first(where: \.isBlank) { activeID = blank.id } else { openNewTab() }
    }

    func select(_ id: String) { activeID = id }

    func close(_ id: String) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: i)
        if !tab.isBlank {
            closed.append(tab)
            if closed.count > 25 { closed.removeFirst() }
        }
        if tabs.isEmpty { openNewTab() }
        if activeID == id { activeID = tabs[min(i, tabs.count - 1)].id }
    }

    func reopenClosed() {
        guard var tab = closed.popLast() else { return }
        tab.holding = []
        tab.prompt = nil
        tabs.append(tab)
        activeID = tab.id
    }

    func togglePin(_ id: String) { edit(id) { $0.pinned.toggle() } }
    func toggleMute(_ id: String) { edit(id) { $0.muted.toggle() } }

    func duplicate(_ id: String) {
        guard let i = tabs.firstIndex(where: { $0.id == id }), !tabs[i].isBlank else { return }
        let source = tabs[i]
        let copy = BrowseTab(id: UUID().uuidString, url: source.url, title: source.title, blocked: source.blocked)
        tabs.insert(copy, at: i + 1)
    }

    func move(from: IndexSet, to: Int) { tabs.move(fromOffsets: from, toOffset: to) }

    // MARK: Prompts and devices

    func answerPrompt(_ answer: SiteAnswer, always: Bool) {
        let tab = active
        guard let prompt = tab.prompt else { return }
        editActive { tab in
            tab.prompt = nil
            if answer == .allow { tab.holding = prompt.devices }
        }
        if answer == .block || always {
            setSite(prompt.site) { settings in
                for device in prompt.devices {
                    if let p = SitePermission(rawValue: device.capitalized) { settings.answers[p] = answer }
                }
            }
        }
    }

    /// Stop reloads the page to end its use of the devices.
    func stopDevices() {
        editActive { $0.holding = [] }
        startLoading()
    }

    func answerOffer(save: Bool, never: Bool) {
        guard let offer = active.offer else { return }
        if never, !neverSave.contains(offer.host) { neverSave.append(offer.host) }
        if save {
            logins.insert(BrowseLogin(id: UUID().uuidString, host: offer.host, user: offer.user, lastUsed: "Just now"), at: 0)
            editActive { $0.offer?.saved = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(Motion.gentle) { self.editActive { $0.offer = nil } }
            }
        } else {
            editActive { $0.offer = nil }
        }
    }

    func openPopup() {
        guard let url = active.popup else { return }
        editActive { $0.popup = nil }
        go(url, newTab: true)
    }

    // MARK: Speed Dial

    func suggestions(for text: String) -> [(title: String, url: String)] {
        let q = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [(title: String, url: String)] = []
        for site in speedDial where site.name.lowercased().contains(q) || site.url.lowercased().contains(q) {
            if seen.insert(site.url).inserted { out.append((site.name, site.url)) }
        }
        for visit in history where visit.title.lowercased().contains(q) || visit.url.lowercased().contains(q) {
            if seen.insert(visit.url).inserted { out.append((visit.title, visit.url)) }
        }
        return Array(out.prefix(8))
    }

    /// Most-visited sites that are not on Speed Dial, one per site.
    var topSites: [HistoryVisit] {
        let pinned = Set(speedDial.map(\.host))
        var seen = Set<String>()
        return history.filter { !pinned.contains($0.host) && !$0.host.hasPrefix("search.") && seen.insert($0.host).inserted }.prefix(6).map { $0 }
    }

    func isPinned(_ host: String) -> Bool { speedDial.contains { $0.host == host } }

    func pinSite(name: String, url: String) -> Bool {
        guard case .open(let address) = BrowseAddress.parse(url) else { return false }
        let tones: [UInt32] = [Palette.botPowder, Palette.botSand, Palette.botRose, Palette.botSage, Palette.botLilac, Palette.botGold]
        let seed = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let tone = tones[seed % tones.count]
        speedDial.append(SpeedSite(id: UUID().uuidString, name: name.isEmpty ? BrowseAddress.host(of: address) : name, url: address, colorHex: tone))
        return true
    }

    func unpin(host: String) { speedDial.removeAll { $0.host == host } }

    func editSite(_ id: String, name: String, url: String) -> Bool {
        guard case .open(let address) = BrowseAddress.parse(url), let i = speedDial.firstIndex(where: { $0.id == id }) else { return false }
        speedDial[i].name = name.isEmpty ? BrowseAddress.host(of: address) : name
        speedDial[i].url = address
        return true
    }

    func removeSite(_ id: String) { speedDial.removeAll { $0.id == id } }

    // MARK: History

    func deleteVisit(_ id: String) { history.removeAll { $0.id == id } }
    func clearLastHour() { history.removeAll { $0.minutesAgo < 60 } }

    // MARK: Downloads

    func pause(_ id: String) {
        guard let i = downloads.firstIndex(where: { $0.id == id }), case .downloading(let p) = downloads[i].state else { return }
        downloads[i].state = .paused(p)
    }

    func resume(_ id: String) {
        guard let i = downloads.firstIndex(where: { $0.id == id }), case .paused(let p) = downloads[i].state else { return }
        downloads[i].state = .downloading(p)
    }

    func cancel(_ id: String) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].state = .cancelled
    }

    func removeDownload(_ id: String) { downloads.removeAll { $0.id == id } }

    /// Moves running downloads along a little. Called on a timer while the list is open.
    func tickDownloads() {
        for i in downloads.indices {
            if case .downloading(let p) = downloads[i].state {
                downloads[i].state = p >= 96 ? .done : .downloading(min(100, p + 4))
            }
        }
    }

    // MARK: Passwords

    func deleteLogin(_ id: String) { logins.removeAll { $0.id == id } }
    func removeNever(_ host: String) { neverSave.removeAll { $0 == host } }
}

// MARK: - Sample data

nonisolated enum BrowseSample {
    static let tabs: [BrowseTab] = [
        BrowseTab(id: "t-bikes", url: "https://riverside-bikes.example/", title: "Riverside Bikes", pinned: true,
                  back: ["https://search.example/?engine=Google&q=bike+shop"], blocked: 7, popup: "https://riverside-bikes.example/offer"),
        BrowseTab(id: "t-weather", url: "https://trail-weather.example/", title: "Trail weather", blocked: 2),
        BrowseTab(id: "t-call", url: "https://team-call.example/room/friday", title: "Friday call", audible: true,
                  prompt: BrowsePrompt(site: "team-call.example", devices: ["camera", "microphone"])),
        BrowseTab(id: "t-news", url: "https://daily-news.example/", title: "Daily news", muted: true, blocked: 23,
                  offer: PasswordOffer(host: "daily-news.example", user: "reader")),
        BrowseTab(id: "t-blank", url: "", title: ""),
    ]

    static let speedDial: [SpeedSite] = [
        SpeedSite(id: "sd-1", name: "Riverside Bikes", url: "https://riverside-bikes.example/", colorHex: Palette.botSand),
        SpeedSite(id: "sd-2", name: "Trail weather", url: "https://trail-weather.example/", colorHex: Palette.botPowder),
        SpeedSite(id: "sd-3", name: "Recipes", url: "https://recipes.example/", colorHex: Palette.botRose),
        SpeedSite(id: "sd-4", name: "Daily news", url: "https://daily-news.example/", colorHex: Palette.botSage),
        SpeedSite(id: "sd-5", name: "Map", url: "https://maps.example/", colorHex: Palette.botLilac),
    ]

    static let history: [HistoryVisit] = [
        HistoryVisit(id: "h1", title: "Daily news", url: "https://daily-news.example/", when: "Today 9:38", minutesAgo: 3),
        HistoryVisit(id: "h2", title: "Friday call", url: "https://team-call.example/room/friday", when: "Today 9:30", minutesAgo: 11),
        HistoryVisit(id: "h3", title: "Riverside Bikes", url: "https://riverside-bikes.example/", when: "Today 9:12", minutesAgo: 29),
        HistoryVisit(id: "h4", title: "Gravel tyres compared", url: "https://tyre-review.example/gravel", when: "Today 8:02", minutesAgo: 99),
        HistoryVisit(id: "h5", title: "Trail weather", url: "https://trail-weather.example/", when: "Yesterday 18:40", minutesAgo: 900),
        HistoryVisit(id: "h6", title: "Bike fit guide", url: "https://fit-guide.example/start", when: "Yesterday 17:05", minutesAgo: 995),
        HistoryVisit(id: "h7", title: "Lentil soup", url: "https://recipes.example/lentil-soup", when: "Mon 19:20", minutesAgo: 3000),
    ]

    static let downloads: [BrowseDownload] = [
        BrowseDownload(id: "d1", name: "spring-catalogue.pdf", host: "riverside-bikes.example", state: .downloading(42)),
        BrowseDownload(id: "d2", name: "route-map.gpx", host: "maps.example", state: .paused(63)),
        BrowseDownload(id: "d3", name: "invoice-1042.pdf", host: "riverside-bikes.example", state: .done),
        BrowseDownload(id: "d4", name: "setup-old.zip", host: "files.example", state: .failed),
    ]

    static let logins: [BrowseLogin] = [
        BrowseLogin(id: "l1", host: "riverside-bikes.example", user: "shop-owner", lastUsed: "Last used today"),
        BrowseLogin(id: "l2", host: "trail-weather.example", user: "rider", lastUsed: "Last used Mon"),
        BrowseLogin(id: "l3", host: "recipes.example", user: "home-cook", lastUsed: "Never used"),
    ]

    static let botUses: [BotLoginUse] = [
        BotLoginUse(id: "u1", bot: "Scout", host: "riverside-bikes.example", user: "shop-owner", when: "Today 8:15"),
    ]

    static let sites: [String: SiteSettings] = [
        "team-call.example": SiteSettings(answers: [.notifications: .allow]),
        "daily-news.example": SiteSettings(answers: [.location: .block, .notifications: .block]),
    ]

    static let botWork: [BotPageWork] = [
        BotPageWork(id: "w1", botID: "scout", bot: "Scout", page: "Tyre prices, three shops"),
        BotPageWork(id: "w2", botID: "producer", bot: "Producer", page: "Video upload page"),
    ]

    static func title(for url: String) -> String {
        let host = BrowseAddress.host(of: url)
        if host.hasPrefix("search.") {
            return "Search: " + query(in: url)
        }
        switch host {
        case "riverside-bikes.example": return "Riverside Bikes"
        case "trail-weather.example": return "Trail weather"
        case "team-call.example": return "Friday call"
        case "daily-news.example": return "Daily news"
        case "recipes.example": return "Recipes"
        default: return host
        }
    }

    static func query(in url: String) -> String {
        guard let range = url.range(of: "q=") else { return "" }
        let raw = String(url[range.upperBound...])
        return (raw.removingPercentEncoding ?? raw).replacingOccurrences(of: "+", with: " ")
    }

    static func blockedCount(for url: String, on: Bool) -> Int {
        guard on else { return 0 }
        return BrowseAddress.host(of: url).count % 9 + 1
    }

    /// The words on a page, for Find and Ask Kairos.
    static func text(for url: String) -> String {
        let host = BrowseAddress.host(of: url)
        switch host {
        case "riverside-bikes.example":
            return "Riverside Bikes. Spring service week. Bikes, parts and repairs since 2009. City bike 480. Gravel bike 1240. Kids bike 220. Book a service. Open Tuesday to Saturday. Free tyre check with every service."
        case "trail-weather.example":
            return "Trail weather. Today: dry, 14 degrees, light wind. Tomorrow: showers after noon. The river trail is open. The hill loop is muddy."
        case "team-call.example":
            return "Friday call. Waiting for others to join. Camera and microphone are off."
        case "daily-news.example":
            return "Daily news. Town opens a new bike lane on Main Street. Market moves to Saturdays. Library extends evening hours."
        default:
            if host.hasPrefix("search.") {
                let q = query(in: url)
                return "Results for \(q). \(q) near you. More about \(q). Pictures of \(q)."
            }
            return "A page on \(host). This is a sample page while your PC is not connected."
        }
    }

    static func html(for url: String) -> String {
        let host = BrowseAddress.host(of: url)
        let body: String
        switch host {
        case "riverside-bikes.example":
            body = """
            <header style="background:#2f5d50;color:#fff;padding:22px 18px"><div style="font-size:13px;opacity:.8">RIVERSIDE BIKES</div>
            <h1 style="margin:6px 0 0;font-size:26px">Spring service week</h1><p style="margin:6px 0 0;opacity:.9">Bikes, parts and repairs since 2009.</p></header>
            <main style="padding:16px 18px">
            <div class="card"><b>City bike</b><span>480</span></div>
            <div class="card"><b>Gravel bike</b><span>1240</span></div>
            <div class="card"><b>Kids bike</b><span>220</span></div>
            <a class="btn">Book a service</a>
            <p class="small">Open Tuesday to Saturday. Free tyre check with every service.</p></main>
            """
        case "trail-weather.example":
            body = """
            <main style="padding:22px 18px"><div class="small">TRAIL WEATHER</div><h1 style="font-size:44px;margin:4px 0">14&deg;</h1>
            <p>Today: dry, 14 degrees, light wind.</p><p>Tomorrow: showers after noon.</p>
            <div class="card"><b>River trail</b><span style="color:#2f7d4f">Open</span></div>
            <div class="card"><b>Hill loop</b><span style="color:#a8642f">Muddy</span></div></main>
            """
        case "team-call.example":
            body = """
            <main style="padding:22px 18px;background:#1e2430;color:#eef;min-height:100vh"><div class="small" style="color:#aab">FRIDAY CALL</div>
            <div style="height:180px;border-radius:14px;background:#2c3442;margin:14px 0;display:flex;align-items:center;justify-content:center">Waiting for others to join</div>
            <p class="small" style="color:#aab">Camera and microphone are off.</p></main>
            """
        case "daily-news.example":
            body = """
            <main style="padding:20px 18px"><div class="small">DAILY NEWS</div>
            <h2>Town opens a new bike lane on Main Street</h2><p>The lane runs from the station to the market.</p><hr>
            <h3>Market moves to Saturdays</h3><hr><h3>Library extends evening hours</h3>
            <div class="card"><b>Sign in</b><span>reader</span></div></main>
            """
        default:
            if host.hasPrefix("search.") {
                let q = query(in: url)
                body = """
                <main style="padding:18px"><div class="small">RESULTS FOR</div><h2 style="margin-top:4px">\(escape(q))</h2>
                <div class="res"><b>\(escape(q)) near you</b><div class="small">local.example</div></div>
                <div class="res"><b>More about \(escape(q))</b><div class="small">guide.example</div></div>
                <div class="res"><b>Pictures of \(escape(q))</b><div class="small">photos.example</div></div></main>
                """
            } else {
                body = """
                <main style="padding:22px 18px"><div class="small">\(escape(host.uppercased()))</div><h2>A page on \(escape(host))</h2>
                <p>This is a sample page while your PC is not connected.</p></main>
                """
            }
        }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0;font-family:-apple-system,Helvetica,sans-serif;color:#222;background:#fff;font-size:16px}
        .card{display:flex;justify-content:space-between;padding:14px;border:1px solid #e3e3e3;border-radius:12px;margin:10px 0}
        .btn{display:inline-block;margin-top:10px;padding:12px 18px;border-radius:24px;background:#2f5d50;color:#fff}
        .small{font-size:12px;color:#777;letter-spacing:.06em}.res{padding:12px 0;border-bottom:1px solid #eee}
        h2,h3{line-height:1.25}</style></head><body>\(body)</body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
