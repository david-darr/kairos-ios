import SwiftUI
import UIKit
import WebKit

// Designs: the list in Library > Designs and the design viewer (boards, canvas, focus, versions,
// compare, comments, tokens, export). Boards are web content, so they render in a web view.
// Selection and comments are native: each selectable element has a known rect in the sample data.
// Paired with a desktop, the list and the design screen hand over to MakeDesignLive.swift, which shows
// the desktop's own designs; everything below is then the sample path only.

// MARK: - Public entry points

nonisolated enum DesignStart: Hashable, Sendable { case boards, canvas, versions, compare, comment, focus }

enum DesignsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "designs": return AnyView(DesignListScreen())
        case "design": return AnyView(DesignScreen(designID: DesignSample.firstID))
        case "design-canvas": return AnyView(DesignScreen(designID: DesignSample.firstID, start: .canvas))
        case "design-versions": return AnyView(DesignScreen(designID: DesignSample.firstID, start: .versions))
        case "design-compare": return AnyView(DesignScreen(designID: DesignSample.firstID, start: .compare))
        case "design-comment": return AnyView(DesignScreen(designID: DesignSample.firstID, start: .comment))
        case "design-focus": return AnyView(DesignScreen(designID: DesignSample.firstID, start: .focus))
        default: return nil
        }
    }
}

// MARK: - Models

nonisolated enum DesignFormat: String, CaseIterable, Hashable, Sendable {
    case website = "Website", phone = "Phone", poster = "Poster", slides = "Slides"
}

nonisolated enum DesignElementStyle: Hashable, Sendable {
    case nav, headline, body, button, list, image, footer, price
    var isText: Bool { self != .list && self != .image }
}

/// One selectable element of a board. The rect is in unit coordinates (0 to 1) of the board.
nonisolated struct DesignElement: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let style: DesignElementStyle
    var text: String
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
}

nonisolated struct DesignBoard: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    let format: DesignFormat
    let sizeText: String
    let pageWidth: CGFloat
    let aspect: CGFloat
    var elements: [DesignElement]
}

nonisolated struct DesignTokens: Hashable, Sendable {
    var accent: UInt32 = 0xC9933A
    var ground: UInt32 = 0xFBF6EE
    var ink: UInt32 = 0x2B211A
    var radius: Double = 12
    var textScale: Double = 1

    static let standard = DesignTokens()
}

nonisolated struct DesignVersion: Identifiable, Hashable, Sendable {
    let id: UUID
    let number: Int
    let author: String
    let summary: String
    let touched: String
    let date: Date
    var name: String?
    let boards: [DesignBoard]
    let tokens: DesignTokens
}

nonisolated enum DesignCommentState: Hashable, Sendable { case open, addressed(Int), resolved }

nonisolated struct DesignComment: Identifiable, Hashable, Sendable {
    let id: UUID
    let number: Int
    let boardID: String
    let boardTitle: String
    let elementID: String
    let elementName: String
    let text: String
    var state: DesignCommentState
    let madeOn: Int
}

nonisolated struct DesignDoc: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var boards: [DesignBoard]
    var tokens: DesignTokens
    var versions: [DesignVersion]
    var comments: [DesignComment]
    var chat: String?
    var edited: Date
    var fresh: Bool

    var current: Int { versions.last?.number ?? 1 }
    var openComments: Int { comments.filter { $0.state == .open }.count }

    mutating func addVersion(author: String, summary: String, touched: String) {
        let number = (versions.last?.number ?? 0) + 1
        versions.append(DesignVersion(id: UUID(), number: number, author: author, summary: summary, touched: touched,
                                      date: Date.now, name: nil, boards: boards, tokens: tokens))
        edited = Date.now
    }
}

nonisolated struct DesignChip: Identifiable, Hashable, Sendable {
    let boardID: String
    let elementID: String
    let boardTitle: String
    let elementName: String
    var id: String { boardID + "/" + elementID }
    var label: String { "Design · \(boardTitle) · \(elementName)" }
}

nonisolated struct DesignTarget: Hashable, Sendable {
    let boardID: String
    let elementID: String
}

nonisolated enum DesignMode: String, CaseIterable, Hashable, Sendable {
    case pan = "Pan", select = "Select", comment = "Comment", text = "Text"

    var symbol: String {
        switch self {
        case .pan: "hand.raised"
        case .select: "cursorarrow"
        case .comment: "text.bubble"
        case .text: "textformat"
        }
    }

    var hint: String {
        switch self {
        case .pan: "Pan: tap a board to open it."
        case .select: "Select: tap an element to add it to your message."
        case .comment: "Comment: tap an element to pin a comment."
        case .text: "Text: tap a text element to edit it."
        }
    }
}

nonisolated enum DesignLayout: String, CaseIterable, Hashable, Sendable { case boards = "Boards", canvas = "Canvas" }

nonisolated enum DesignWidth: String, CaseIterable, Hashable, Sendable {
    case desktop = "Desktop", tablet = "Tablet", phone = "Phone"
    var scale: CGFloat {
        switch self {
        case .desktop: 1
        case .tablet: 820.0 / 1280.0
        case .phone: 390.0 / 1280.0
        }
    }
}

nonisolated enum DesignSheet: String, Identifiable, Hashable, Sendable {
    case versions, compare, comments, comment, text, export, tokens, chat
    var id: String { rawValue }
}

nonisolated enum DesignSendState: Hashable, Sendable { case idle, working, done }

nonisolated struct DesignSwatch: Identifiable, Hashable, Sendable {
    let hex: UInt32
    let name: String
    var id: UInt32 { hex }

    static let accents = [DesignSwatch(hex: 0x2F6F5E, name: "Green"), DesignSwatch(hex: 0xC9933A, name: "Gold"),
                          DesignSwatch(hex: 0x3E5C9A, name: "Blue"), DesignSwatch(hex: 0xB4493A, name: "Red"),
                          DesignSwatch(hex: 0x6B4FA0, name: "Violet")]
    static let grounds = [DesignSwatch(hex: 0xFBF6EE, name: "Cream"), DesignSwatch(hex: 0xFFFFFF, name: "White"),
                          DesignSwatch(hex: 0xEEF2F0, name: "Mist"), DesignSwatch(hex: 0x1F1B18, name: "Night")]
    static let inks = [DesignSwatch(hex: 0x22302B, name: "Pine"), DesignSwatch(hex: 0x2B211A, name: "Bistre"),
                       DesignSwatch(hex: 0x1E2A33, name: "Slate"), DesignSwatch(hex: 0xF4EEE6, name: "Paper")]
}

nonisolated struct DesignRow: Identifiable, Sendable {
    let format: DesignFormat
    var indices: [Int]
    var id: String { format.rawValue }
}

nonisolated struct DesignVersionGroup: Identifiable, Sendable {
    let id: Int
    let author: String
    var versions: [DesignVersion]

    var title: String {
        var seen: [String] = []
        for version in versions {
            for part in version.touched.components(separatedBy: ", ") where !seen.contains(part) { seen.append(part) }
        }
        let edits = versions.count == 1 ? "1 edit" : "\(versions.count) edits"
        return "\(author): \(edits) on \(seen.joined(separator: ", "))"
    }

    /// Newest first, consecutive versions by the same author grouped together.
    static func make(_ versions: [DesignVersion]) -> [DesignVersionGroup] {
        var out: [DesignVersionGroup] = []
        for version in versions.reversed() {
            if let last = out.last, last.author == version.author {
                out[out.count - 1].versions.append(version)
            } else {
                out.append(DesignVersionGroup(id: version.number, author: version.author, versions: [version]))
            }
        }
        return out
    }
}

// MARK: - Store

/// The designs on this phone. The desktop connection replaces the sample data later.
@Observable
final class DesignStore {
    static let shared = DesignStore()
    var designs: [DesignDoc] = DesignSample.designs()
    var drafts: [String: String] = [:]

    func index(of id: String) -> Int? { designs.firstIndex { $0.id == id } }
    func design(_ id: String) -> DesignDoc? { designs.first { $0.id == id } }
    func add(_ doc: DesignDoc) { withAnimation(Motion.snappy) { designs.insert(doc, at: 0) } }
}

// MARK: - HTML for a board

/// Builds a small self-contained page for a board. Every size is in vw, so the page scales to any
/// preview width, and every element sits at its rect, so native outlines line up with it.
nonisolated enum DesignHTML {
    static func page(_ board: DesignBoard, _ tokens: DesignTokens) -> String {
        let unitHeight = 100 / Double(board.aspect)
        let body = board.elements.map { element($0, board: board, tokens: tokens, unitHeight: unitHeight) }.joined()
        let ground = css(tokens.ground)
        let ink = css(tokens.ink)
        let head = "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no'>"
        let style = "<style>html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:\(ground);color:\(ink);font-family:-apple-system,'Helvetica Neue',Helvetica,sans-serif;-webkit-text-size-adjust:100%;}.k{position:absolute;box-sizing:border-box;overflow:hidden;}.row{display:flex;justify-content:space-between;align-items:center;box-sizing:border-box;border-bottom:0.12vw solid \(ink)22;}</style></head>"
        return head + style + "<body>" + body + "</body></html>"
    }

    private static func element(_ el: DesignElement, board: DesignBoard, tokens: DesignTokens, unitHeight: Double) -> String {
        let left = Double(el.x) * 100
        let top = Double(el.y) * unitHeight
        let width = Double(el.w) * 100
        let height = Double(el.h) * unitHeight
        let scale = tokens.textScale
        let radius = tokens.radius / Double(board.pageWidth) * 100
        let accent = css(tokens.accent)
        let ink = css(tokens.ink)
        let serif = board.format == .poster || board.format == .slides
        var style = "left:\(n(left))vw;top:\(n(top))vw;width:\(n(width))vw;height:\(n(height))vw;"
        var inner = escape(el.text)

        switch el.style {
        case .nav:
            let parts = el.text.split(separator: "|", maxSplits: 1).map(String.init)
            let size = fit(el.text, width: width, height: height, lines: 1, lineHeight: 1.2) * scale
            style += "display:flex;align-items:center;justify-content:space-between;font-size:\(n(size))vw;border-bottom:0.12vw solid \(ink)22;"
            let brand = escape(parts.first ?? "")
            let links = parts.count > 1 ? escape(parts[1]) : ""
            inner = "<b>\(brand)</b><span style='opacity:0.7'>\(links)</span>"
        case .headline:
            let size = fit(el.text, width: width, height: height, lines: 3, lineHeight: 1.1) * scale
            let family = serif ? "font-family:Georgia,serif;font-style:italic;" : ""
            style += "font-size:\(n(size))vw;line-height:1.1;font-weight:700;letter-spacing:-0.01em;" + family
        case .body:
            let size = min(fit(el.text, width: width, height: height, lines: 4, lineHeight: 1.35), height * 0.4) * scale
            style += "font-size:\(n(size))vw;line-height:1.35;opacity:0.78;"
        case .button:
            let size = min(fit(el.text, width: width * 0.8, height: height * 0.6, lines: 1, lineHeight: 1), height * 0.42) * scale
            style += "display:flex;align-items:center;justify-content:center;text-align:center;background:\(accent);color:\(onAccent(tokens.accent));border-radius:\(n(radius))vw;font-weight:600;font-size:\(n(size))vw;"
        case .list:
            let lines = el.text.split(separator: "\n").map(String.init)
            let rowHeight = height / Double(max(1, lines.count))
            inner = lines.map { (line: String) -> String in
                let cells = line.split(separator: "|", maxSplits: 1).map(String.init)
                let size = min(fit(line, width: width * 0.9, height: rowHeight * 0.6, lines: 1, lineHeight: 1), rowHeight * 0.4) * scale
                let name = escape(cells.first ?? "")
                let price = cells.count > 1 ? escape(cells[1]) : ""
                return "<div class='row' style='height:\(n(rowHeight))vw;font-size:\(n(size))vw'><span>\(name)</span><b style='color:\(accent)'>\(price)</b></div>"
            }.joined()
        case .image:
            let size = height * 0.08 * scale
            style += "background:linear-gradient(135deg,\(accent),\(ink));border-radius:\(n(radius))vw;color:#ffffff;display:flex;align-items:flex-end;padding:\(n(height * 0.07))vw;font-weight:600;font-size:\(n(size))vw;"
            let sun = "<div style='position:absolute;right:10%;top:12%;width:28%;padding-top:28%;border-radius:50%;background:rgba(255,255,255,0.3)'></div>"
            inner = sun + "<span style='position:relative'>\(escape(el.text))</span>"
        case .footer:
            let size = min(fit(el.text, width: width * 0.9, height: height * 0.5, lines: 1, lineHeight: 1), height * 0.34) * scale
            style += "display:flex;align-items:center;padding:0 4vw;background:\(ink)12;font-size:\(n(size))vw;opacity:0.85;"
        case .price:
            let size = fit(el.text, width: width, height: height, lines: 1, lineHeight: 1.05) * scale
            style += "font-size:\(n(size))vw;line-height:1.05;font-weight:800;color:\(accent);"
        }
        return "<div class='k' data-k='\(el.id)' style='\(style)'>\(inner)</div>"
    }

    /// The largest font size (in vw) that fits the text into the box on up to `lines` lines.
    private static func fit(_ text: String, width: Double, height: Double, lines: Int, lineHeight: Double) -> Double {
        let count = Double(max(1, text.count))
        var best = 0.0
        for lineCount in 1...max(1, lines) {
            let byHeight = height / (Double(lineCount) * lineHeight)
            let perLine = (count / Double(lineCount)).rounded(.up) * 1.15 + 1
            let byWidth = width / (0.55 * perLine)
            best = max(best, min(byHeight, byWidth))
        }
        return best
    }

    static func css(_ hex: UInt32) -> String {
        let digits = String(hex, radix: 16)
        return "#" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    private static func onAccent(_ hex: UInt32) -> String {
        let red = Double((hex >> 16) & 0xFF)
        let green = Double((hex >> 8) & 0xFF)
        let blue = Double(hex & 0xFF)
        return (red * 0.299 + green * 0.587 + blue * 0.114) > 160 ? "#1b1612" : "#ffffff"
    }

    private static func n(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Sample data (made up: a bike shop, a bakery)

nonisolated enum DesignSample {
    static let firstID = "booking"
    static let chats = ["Bike shop website", "Spring sale ideas", "Bakery menu refresh"]

    static let bikeTokens = DesignTokens(accent: 0x2F6F5E, ground: 0xFBF6EE, ink: 0x22302B, radius: 10, textScale: 1)
    static let posterTokens = DesignTokens(accent: 0xB4493A, ground: 0xFFF4E2, ink: 0x2B211A, radius: 0, textScale: 1)
    static let bakeryTokens = DesignTokens(accent: 0xA4552F, ground: 0xFFF8EE, ink: 0x3A2418, radius: 18, textScale: 1)
    static let slideTokens = DesignTokens(accent: 0x3E5C9A, ground: 0xFFFFFF, ink: 0x1E2A33, radius: 14, textScale: 1)
    static let appTokens = DesignTokens(accent: 0x6B4FA0, ground: 0xF7F5FB, ink: 0x231F2E, radius: 22, textScale: 1)

    static func e(_ id: String, _ name: String, _ style: DesignElementStyle, _ text: String,
                  _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> DesignElement {
        DesignElement(id: id, name: name, style: style, text: text, x: x, y: y, w: w, h: h)
    }

    static func website(_ id: String, _ title: String, _ elements: [DesignElement]) -> DesignBoard {
        DesignBoard(id: id, title: title, format: .website, sizeText: "Website · Desktop · 1440 wide", pageWidth: 1440, aspect: 1.6, elements: elements)
    }

    static func phone(_ id: String, _ title: String, _ elements: [DesignElement]) -> DesignBoard {
        DesignBoard(id: id, title: title, format: .phone, sizeText: "Phone · 390x844", pageWidth: 390, aspect: 390.0 / 844.0, elements: elements)
    }

    static func poster(_ id: String, _ title: String, _ elements: [DesignElement]) -> DesignBoard {
        DesignBoard(id: id, title: title, format: .poster, sizeText: "Poster · 2:3 portrait · 1200x1800", pageWidth: 1200, aspect: 2.0 / 3.0, elements: elements)
    }

    static func posterWide(_ id: String, _ title: String, _ elements: [DesignElement]) -> DesignBoard {
        DesignBoard(id: id, title: title, format: .poster, sizeText: "Poster · 3:2 landscape · 1800x1200", pageWidth: 1800, aspect: 1.5, elements: elements)
    }

    static func slide(_ id: String, _ title: String, _ elements: [DesignElement]) -> DesignBoard {
        DesignBoard(id: id, title: title, format: .slides, sizeText: "Slides · 16:9 · 1920x1080", pageWidth: 1920, aspect: 16.0 / 9.0, elements: elements)
    }

    static let topBar = e("top", "Top bar", .nav, "Spoke and Chain|Shop   Service   Visit", 0.05, 0.03, 0.9, 0.08)
    static let footer = e("footer", "Footer", .footer, "Open Tuesday to Saturday, 9 to 6 · 12 Harbor Lane", 0, 0.88, 1, 0.12)

    static func home() -> DesignBoard {
        website("home", "Home", [
            topBar,
            e("headline", "Headline", .headline, "Tune-ups that keep you rolling", 0.06, 0.19, 0.46, 0.25),
            e("intro", "Intro", .body, "Same-week service for road, city and kids' bikes. A free safety check comes with every visit.", 0.06, 0.47, 0.44, 0.13),
            e("book", "Book button", .button, "Book a service", 0.06, 0.64, 0.2, 0.09),
            e("hero", "Hero image", .image, "Spring tune-up week", 0.57, 0.17, 0.37, 0.58),
            footer,
        ])
    }

    static func book() -> DesignBoard {
        website("book", "Book a service", [
            topBar,
            e("headline", "Headline", .headline, "Pick your service", 0.06, 0.17, 0.5, 0.12),
            e("prices", "Price list", .list, "Basic tune-up|$45\nFull service|$95\nBrake bleed|$30\nWheel true|$25", 0.06, 0.34, 0.44, 0.44),
            e("note", "Note", .body, "Drop off before 10 and ride home the same day.", 0.56, 0.34, 0.38, 0.12),
            e("book", "Book button", .button, "Choose a time", 0.56, 0.52, 0.22, 0.09),
            footer,
        ])
    }

    static func phoneHome() -> DesignBoard {
        phone("phone-home", "Phone home", [
            e("top", "Top bar", .nav, "Spoke and Chain|Menu", 0.06, 0.05, 0.88, 0.05),
            e("hero", "Hero image", .image, "Spring tune-up week", 0.06, 0.12, 0.88, 0.27),
            e("headline", "Headline", .headline, "Tune-ups that keep you rolling", 0.06, 0.42, 0.88, 0.13),
            e("intro", "Intro", .body, "Same-week service for road, city and kids' bikes.", 0.06, 0.56, 0.88, 0.09),
            e("book", "Book button", .button, "Book a service", 0.06, 0.69, 0.88, 0.065),
            e("footer", "Footer", .footer, "12 Harbor Lane", 0, 0.92, 1, 0.08),
        ])
    }

    static func posterBoard() -> DesignBoard {
        poster("poster", "Spring tune-up poster", [
            e("headline", "Headline", .headline, "Spring tune-up week", 0.08, 0.07, 0.84, 0.2),
            e("art", "Picture", .image, "", 0.08, 0.29, 0.84, 0.38),
            e("price", "Price", .price, "$45", 0.08, 0.7, 0.4, 0.1),
            e("details", "Details", .body, "Full check of gears, brakes and tyres. Bring your bike in by Friday.", 0.08, 0.81, 0.84, 0.08),
            e("footer", "Footer", .footer, "Spoke and Chain · 12 Harbor Lane", 0, 0.93, 1, 0.07),
        ])
    }

    static func menuBoard() -> DesignBoard {
        posterWide("menu", "Morning menu", [
            e("title", "Title", .headline, "Morning bakes", 0.06, 0.07, 0.6, 0.14),
            e("breads", "Bread list", .list, "Sourdough loaf|$7\nSeeded rye|$6\nBaguette|$4", 0.06, 0.27, 0.41, 0.48),
            e("pastries", "Pastry list", .list, "Butter croissant|$3.50\nCinnamon bun|$4\nAlmond tart|$5", 0.53, 0.27, 0.41, 0.48),
            e("footer", "Footer", .footer, "Baked fresh from 7 every morning", 0, 0.86, 1, 0.14),
        ])
    }

    static func slideTitle() -> DesignBoard {
        slide("s1", "Title slide", [
            e("band", "Colour band", .image, "", 0, 0, 1, 0.07),
            e("headline", "Headline", .headline, "Our new repair club", 0.08, 0.3, 0.84, 0.2),
            e("subtitle", "Subtitle", .body, "Spring launch plan for Spoke and Chain", 0.08, 0.53, 0.7, 0.08),
        ])
    }

    static func slidePerks() -> DesignBoard {
        slide("s2", "What members get", [
            e("headline", "Headline", .headline, "What members get", 0.08, 0.1, 0.84, 0.14),
            e("perks", "Perk list", .list, "Free tune-up|Once a year\nParts discount|15%\nPriority booking|Always", 0.08, 0.3, 0.55, 0.5),
            e("photo", "Picture", .image, "Sunday rides", 0.68, 0.3, 0.24, 0.5),
        ])
    }

    static func slidePrice() -> DesignBoard {
        slide("s3", "Pricing", [
            e("headline", "Headline", .headline, "Simple pricing", 0.08, 0.12, 0.84, 0.14),
            e("price", "Price", .price, "$12 a month", 0.08, 0.34, 0.6, 0.18),
            e("note", "Note", .body, "Cancel any time. Your first tune-up is on us.", 0.08, 0.56, 0.6, 0.1),
            e("join", "Join button", .button, "Join the club", 0.08, 0.72, 0.26, 0.1),
        ])
    }

    static func onboarding() -> [DesignBoard] {
        [
            phone("welcome", "Welcome", [
                e("hero", "Picture", .image, "Ride Log", 0.1, 0.1, 0.8, 0.36),
                e("headline", "Headline", .headline, "Welcome to Ride Log", 0.08, 0.5, 0.84, 0.1),
                e("intro", "Intro", .body, "Track every ride and every service in one place.", 0.08, 0.62, 0.84, 0.08),
                e("start", "Start button", .button, "Get started", 0.08, 0.84, 0.84, 0.065),
            ]),
            phone("bike", "Pick your bike", [
                e("headline", "Headline", .headline, "Which bike do you ride?", 0.08, 0.08, 0.84, 0.1),
                e("bikes", "Bike list", .list, "Road|›\nCity|›\nMountain|›\nKids|›", 0.08, 0.22, 0.84, 0.4),
                e("next", "Continue button", .button, "Continue", 0.08, 0.84, 0.84, 0.065),
            ]),
            phone("remind", "Reminders", [
                e("hero", "Picture", .image, "Service due in 12 days", 0.1, 0.1, 0.8, 0.3),
                e("headline", "Headline", .headline, "Get service reminders", 0.08, 0.45, 0.84, 0.1),
                e("intro", "Intro", .body, "We nudge you when your bike is due for a check.", 0.08, 0.57, 0.84, 0.08),
                e("remind", "Reminder button", .button, "Turn on reminders", 0.08, 0.78, 0.84, 0.065),
                e("skip", "Skip link", .body, "Not now", 0.36, 0.87, 0.3, 0.04),
            ]),
        ]
    }

    static func blankPhone() -> DesignBoard {
        phone("phone-1", "Phone 1", [
            e("headline", "Headline", .headline, "New screen", 0.08, 0.1, 0.84, 0.08),
            e("intro", "Intro", .body, "Describe this screen in the composer and Kairos builds it.", 0.08, 0.2, 0.84, 0.08),
        ])
    }

    static func starter(_ format: DesignFormat, title: String) -> DesignBoard {
        switch format {
        case .website: return edit(home(), "headline", title)
        case .phone: return edit(phoneHome(), "headline", title)
        case .poster: return edit(posterBoard(), "headline", title)
        case .slides: return edit(slideTitle(), "headline", title)
        }
    }

    static func edit(_ board: DesignBoard, _ elementID: String, _ text: String) -> DesignBoard {
        var copy = board
        if let index = copy.elements.firstIndex(where: { $0.id == elementID }) { copy.elements[index].text = text }
        return copy
    }

    static func version(_ number: Int, _ author: String, _ summary: String, _ touched: String, hoursAgo: Double,
                        _ boards: [DesignBoard], _ tokens: DesignTokens) -> DesignVersion {
        DesignVersion(id: UUID(), number: number, author: author, summary: summary, touched: touched,
                      date: Date.now.addingTimeInterval(-hoursAgo * 3600), name: nil, boards: boards, tokens: tokens)
    }

    static func newID() -> String { "design-" + String(UUID().uuidString.prefix(8)).lowercased() }

    static func makeDoc(title: String, boards: [DesignBoard], tokens: DesignTokens, chat: String?, author: String,
                        summary: String, fresh: Bool) -> DesignDoc {
        let touched = boards.map(\.title).joined(separator: ", ")
        let first = DesignVersion(id: UUID(), number: 1, author: author, summary: summary, touched: touched,
                                  date: Date.now, name: nil, boards: boards, tokens: tokens)
        return DesignDoc(id: newID(), title: title, boards: boards, tokens: tokens, versions: [first], comments: [],
                         chat: chat, edited: Date.now, fresh: fresh)
    }

    static func simple(_ id: String, _ title: String, _ boards: [DesignBoard], _ tokens: DesignTokens, chat: String?,
                       hoursAgo: Double, fresh: Bool) -> DesignDoc {
        let touched = boards.map(\.title).joined(separator: ", ")
        let first = version(1, "Kairos", "Kairos made the first boards", touched, hoursAgo: hoursAgo, boards, tokens)
        return DesignDoc(id: id, title: title, boards: boards, tokens: tokens, versions: [first], comments: [],
                         chat: chat, edited: Date.now.addingTimeInterval(-hoursAgo * 3600), fresh: fresh)
    }

    static func designs() -> [DesignDoc] {
        let homeBoard = home()
        let bookBoard = book()
        let phoneBoard = phoneHome()
        let firstHome = edit(edit(homeBoard, "headline", "Bike service, done right"), "book", "Book now")
        let thirdHome = edit(homeBoard, "book", "Book now")
        let tokens = bikeTokens
        let versions = [
            version(1, "Kairos", "Kairos made the first boards", "Home", hoursAgo: 72, [firstHome], tokens),
            version(2, "Kairos", "Kairos added Book a service", "Book a service", hoursAgo: 50, [firstHome, bookBoard], tokens),
            version(3, "Kairos", "Kairos changed Headline", "Home", hoursAgo: 26, [thirdHome, bookBoard], tokens),
            version(4, "You", "You changed Book button and added Phone home", "Home, Phone home", hoursAgo: 2, [homeBoard, bookBoard, phoneBoard], tokens),
        ]
        let comments = [
            DesignComment(id: UUID(), number: 1, boardID: "home", boardTitle: "Home", elementID: "headline", elementName: "Headline",
                          text: "Make the headline shorter and warmer.", state: .addressed(3), madeOn: 2),
            DesignComment(id: UUID(), number: 2, boardID: "book", boardTitle: "Book a service", elementID: "prices", elementName: "Price list",
                          text: "Add a line for e-bike service.", state: .open, madeOn: 4),
            DesignComment(id: UUID(), number: 3, boardID: "phone-home", boardTitle: "Phone home", elementID: "book", elementName: "Book button",
                          text: "Make this button easier to reach with a thumb.", state: .open, madeOn: 4),
        ]
        let booking = DesignDoc(id: "booking", title: "Booking page", boards: [homeBoard, bookBoard, phoneBoard], tokens: tokens,
                                versions: versions, comments: comments, chat: chats[0],
                                edited: Date.now.addingTimeInterval(-2 * 3600), fresh: false)
        return [
            booking,
            simple("slides", "Launch slides", [slideTitle(), slidePerks(), slidePrice()], slideTokens, chat: chats[1], hoursAgo: 0.4, fresh: true),
            simple("poster", "Shop poster", [posterBoard()], posterTokens, chat: chats[1], hoursAgo: 26, fresh: false),
            simple("menu", "Menu board", [menuBoard()], bakeryTokens, chat: chats[2], hoursAgo: 75, fresh: false),
            simple("onboarding", "Phone onboarding", onboarding(), appTokens, chat: nil, hoursAgo: 150, fresh: false),
        ]
    }

    static func ago(_ date: Date) -> String {
        let seconds = max(0, Date.now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}

// MARK: - Board rendering

/// A board's page in a web view. Previews never scroll and never take touches; selection is native.
struct DesignWebView: UIViewRepresentable {
    let html: String
    /// Where the page's own pictures and fonts hang from. The sample pages need none.
    var base: URL? = nil

    func makeCoordinator() -> DesignWebCoordinator { DesignWebCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.dataDetectorTypes = []
        // Nothing this view loads, the token in a picture's address included, is written to disk.
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isUserInteractionEnabled = false
        context.coordinator.html = html
        view.loadHTMLString(html, baseURL: base)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        view.loadHTMLString(html, baseURL: base)
    }
}

final class DesignWebCoordinator {
    var html = ""
}

/// Sizes its content to the board's aspect: as wide as it can be, no taller than `maxHeight`.
struct DesignFitted<Content: View>: View {
    let aspect: CGFloat
    let maxHeight: CGFloat
    let widthScale: CGFloat
    let content: (CGSize) -> Content
    @State private var width: CGFloat = 0

    init(aspect: CGFloat, maxHeight: CGFloat, widthScale: CGFloat = 1, @ViewBuilder content: @escaping (CGSize) -> Content) {
        self.aspect = aspect
        self.maxHeight = maxHeight
        self.widthScale = widthScale
        self.content = content
    }

    private var size: CGSize {
        let available = (width > 0 ? width : 320) * widthScale
        let height = max(40, min(maxHeight, available / max(0.1, aspect)))
        return CGSize(width: height * aspect, height: height)
    }

    var body: some View {
        let fitted = size
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: fitted.height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay { content(fitted).frame(width: fitted.width, height: fitted.height) }
    }
}

/// A live board: the page, outlines on the chosen elements, comment pins, and native taps.
struct DesignBoardView: View {
    let board: DesignBoard
    let tokens: DesignTokens
    var highlights: [String] = []
    var pins: [DesignComment] = []
    var onTap: ((DesignElement?) -> Void)? = nil
    var onPin: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                DesignWebView(html: DesignHTML.page(board, tokens))
                    .allowsHitTesting(false)
                outlines(geo.size)
                if let onTap {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { point in onTap(hit(point, in: geo.size)) }
                }
                pinLayer(geo.size)
            }
        }
        .background(Color(hex: tokens.ground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(board.title)
    }

    private func outlines(_ size: CGSize) -> some View {
        ForEach(board.elements.filter { highlights.contains($0.id) }) { el in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Palette.gold, lineWidth: 2)
                .background { RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.gold.opacity(0.14)) }
                .frame(width: max(8, el.w * size.width), height: max(8, el.h * size.height))
                .offset(x: el.x * size.width, y: el.y * size.height)
                .allowsHitTesting(false)
        }
    }

    private func pinLayer(_ size: CGSize) -> some View {
        ForEach(pins) { pin in
            let point = pinPoint(pin, size)
            Button {
                Haptics.tap()
                onPin?()
            } label: {
                Text("\(pin.number)")
                    .font(KFont.ui(11, .semibold, relativeTo: .caption2))
                    .foregroundStyle(Palette.onGold)
                    .frame(width: 22, height: 22)
                    .background(pin.state == .open ? Palette.gold : Palette.success, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.cream.opacity(0.85), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .allowsHitTesting(onPin != nil)
            .offset(x: point.x - 17, y: point.y - 17)
            .accessibilityLabel("Comment \(pin.number): \(pin.text)")
        }
    }

    private func pinPoint(_ pin: DesignComment, _ size: CGSize) -> CGPoint {
        guard let el = board.elements.first(where: { $0.id == pin.elementID }) else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let x = min(size.width - 12, (el.x + el.w) * size.width - 6)
        let y = max(12, el.y * size.height + 6)
        return CGPoint(x: x, y: y)
    }

    private func hit(_ point: CGPoint, in size: CGSize) -> DesignElement? {
        let inside = board.elements.filter { el in
            CGRect(x: el.x * size.width, y: el.y * size.height, width: el.w * size.width, height: el.h * size.height).contains(point)
        }
        return inside.min { $0.w * $0.h < $1.w * $1.h }
    }
}

/// A drawn thumbnail for the list, so the grid needs no web views.
struct DesignThumb: View {
    let board: DesignBoard?
    let tokens: DesignTokens

    var body: some View {
        ZStack {
            Palette.surface2
            if let board {
                GeometryReader { geo in
                    let size = fittedSize(board.aspect, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Color(hex: tokens.ground)
                        ForEach(board.elements) { el in
                            mark(el, size).offset(x: el.x * size.width, y: el.y * size.height)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func fittedSize(_ aspect: CGFloat, in box: CGSize) -> CGSize {
        let width = max(1, box.width - 20)
        let height = max(1, box.height - 20)
        if width / height > aspect { return CGSize(width: height * aspect, height: height) }
        return CGSize(width: width, height: width / aspect)
    }

    @ViewBuilder
    private func mark(_ el: DesignElement, _ size: CGSize) -> some View {
        let w = el.w * size.width
        let h = el.h * size.height
        let ink = Color(hex: tokens.ink)
        let accent = Color(hex: tokens.accent)
        switch el.style {
        case .headline:
            VStack(alignment: .leading, spacing: max(1, h * 0.12)) {
                Capsule().fill(ink.opacity(0.85)).frame(width: w * 0.95, height: max(1.5, h * 0.24))
                Capsule().fill(ink.opacity(0.85)).frame(width: w * 0.6, height: max(1.5, h * 0.24))
            }
            .frame(width: w, height: h, alignment: .topLeading)
        case .body, .footer, .nav:
            Capsule().fill(ink.opacity(0.28))
                .frame(width: w * 0.8, height: max(1, h * 0.22))
                .frame(width: w, height: h, alignment: .leading)
        case .button:
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(accent).frame(width: w, height: h)
        case .price:
            Capsule().fill(accent).frame(width: w * 0.6, height: max(1.5, h * 0.5)).frame(width: w, height: h, alignment: .leading)
        case .image:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(LinearGradient(colors: [accent, ink], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: w, height: h)
        case .list:
            VStack(spacing: max(1, h * 0.1)) {
                ForEach(0..<4, id: \.self) { _ in Capsule().fill(ink.opacity(0.2)).frame(height: max(1, h * 0.1)) }
            }
            .frame(width: w, height: h)
        }
    }
}

// MARK: - Designs list

struct DesignListScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MakeToast.self) private var toast
    @State private var query = ""
    @State private var starting = false
    @State private var openID: String?

    init() {}

    private var store: DesignStore { DesignStore.shared }

    private var shown: [DesignDoc] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.designs }
        return store.designs.filter { doc in
            doc.title.lowercased().contains(q) || doc.boards.contains { $0.title.lowercased().contains(q) }
        }
    }

    var body: some View {
        // Paired: the desktop's own designs, never a sample one. Not paired: the sample list below.
        if Connection.shared.usesSampleData {
            sampleBody
        } else {
            MakeDesignListLive()
        }
    }

    private var sampleBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Screens, pages and slides on a canvas, made and changed with any model.")
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                searchField
                HStack(spacing: 10) {
                    MakePillButton(title: "New design", symbol: "plus", filled: true, expand: true) { newDesign() }
                    MakePillButton(title: "Design with a model", symbol: "sparkles", expand: true) { starting = true }
                }
                results
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            MakeHeader(title: "Designs", subtitle: store.designs.count == 1 ? "1 design" : "\(store.designs.count) designs", back: { dismiss() })
        }
        .sheet(isPresented: $starting) {
            DesignStartSheet { prompt, format in start(prompt, format) }
        }
        .navigationDestination(item: $openID) { id in DesignScreen(designID: id) }
        .kScreen()
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.inkFaint)
            TextField("Search designs", text: $query)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { withAnimation(Motion.snappy) { query = "" } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 48)
        .kCard(radius: 16, raised: true)
    }

    @ViewBuilder
    private var results: some View {
        if store.designs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No designs yet").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                EmptyLine(text: "Start a blank design, or ask a model in a Design chat to build one.")
                MakePillButton(title: "New design", symbol: "plus") { newDesign() }
            }
            .padding(16)
            .kCard(radius: 22)
        } else if shown.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No designs match").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                MakePillButton(title: "Clear search") { withAnimation(Motion.snappy) { query = "" } }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 22)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, doc in
                    NavigationLink(value: MakeRoute.design(doc.id)) {
                        DesignCard(doc: doc)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Open \(doc.title)")
                    .arrives(index)
                }
            }
        }
    }

    private func newDesign() {
        let doc = DesignSample.makeDoc(title: "Untitled design", boards: [DesignSample.blankPhone()], tokens: .standard,
                                       chat: nil, author: "You", summary: "You started the design", fresh: false)
        store.add(doc)
        Haptics.tap()
        openID = doc.id
    }

    private func start(_ prompt: String, _ format: DesignFormat) {
        let words = prompt.split(separator: " ").prefix(5).joined(separator: " ")
        let title = words.isEmpty ? "New design" : words.prefix(1).uppercased() + String(words.dropFirst())
        let board = DesignSample.starter(format, title: title)
        let doc = DesignSample.makeDoc(title: title, boards: [board], tokens: DesignSample.bikeTokens, chat: "Design chat",
                                       author: "Kairos", summary: "Kairos made the first board", fresh: true)
        store.add(doc)
        Haptics.success()
        toast.say("Kairos made \(title). It is marked Just made.")
    }
}

struct DesignCard: View {
    let doc: DesignDoc

    private var detail: String {
        let boards = doc.boards.count == 1 ? "1 board" : "\(doc.boards.count) boards"
        return "\(boards) · edited \(DesignSample.ago(doc.edited))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DesignThumb(board: doc.boards.first, tokens: doc.tokens)
                .frame(height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if doc.fresh {
                        Text("Just made")
                            .font(KFont.ui(11.5, .semibold, relativeTo: .caption2))
                            .foregroundStyle(Palette.onGold)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Palette.gold, in: Capsule())
                            .padding(7)
                    }
                }
            Text(doc.title)
                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(detail)
                .font(KFont.ui(12.5, relativeTo: .caption))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
            Text(doc.chat.map { "From \($0)" } ?? "No chat linked")
                .font(KFont.ui(12.5, relativeTo: .caption))
                .foregroundStyle(doc.chat == nil ? Palette.inkFaint : Palette.goldText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 22)
    }
}

// MARK: - Design screen

struct DesignScreen: View {
    let designID: String
    let start: DesignStart

    @Environment(\.dismiss) private var dismiss
    @Environment(MakeToast.self) private var toast
    @Namespace private var modeSpace

    @State private var layout: DesignLayout = .boards
    @State private var mode: DesignMode = .pan
    @State private var chips: [DesignChip] = []
    @State private var sheet: DesignSheet?
    @State private var pending: DesignTarget?
    @State private var previewing: Int?
    @State private var compareNumber = 1
    @State private var focusIndex: Int?
    @State private var focusWidth: DesignWidth = .desktop
    @State private var undoStack: [DesignDoc] = []
    @State private var redoStack: [DesignDoc] = []
    @State private var sendState: DesignSendState = .idle
    @State private var liveTokens: DesignTokens?
    @State private var confirmDelete = false
    @State private var openID: String?
    @State private var started = false

    init(designID: String, start: DesignStart = .boards) {
        self.designID = designID
        self.start = start
    }

    private var store: DesignStore { DesignStore.shared }
    private var doc: DesignDoc? { store.design(designID) }

    private var previewVersion: DesignVersion? {
        guard let number = previewing, let current = doc else { return nil }
        return current.versions.first { $0.number == number }
    }

    private var shownBoards: [DesignBoard] { previewVersion?.boards ?? doc?.boards ?? [] }
    private var shownTokens: DesignTokens { liveTokens ?? previewVersion?.tokens ?? doc?.tokens ?? .standard }

    private var draft: Binding<String> {
        let id = designID
        return Binding(get: { DesignStore.shared.drafts[id] ?? "" }, set: { DesignStore.shared.drafts[id] = $0 })
    }

    var body: some View {
        // Paired: the desktop's own design by its own id. Not paired: the sample design below.
        if Connection.shared.usesSampleData {
            sampleBody
        } else {
            MakeDesignScreenLive(designID: designID, start: start)
        }
    }

    private var sampleBody: some View {
        ZStack {
            if let current = doc {
                mainArea(current)
            } else {
                EmptyLine(text: "This design was deleted.")
                    .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .overlay { focusLayer }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sheet(item: $sheet, onDismiss: { pending = nil }) { which in sheetView(which) }
        .confirmationDialog("Delete this design?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteDesign() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its boards, versions and comments are removed. This cannot be undone.")
        }
        .navigationDestination(item: $openID) { id in DesignScreen(designID: id) }
        .onAppear { begin() }
        .kScreen()
    }

    // MARK: Header and controls

    private var header: some View {
        VStack(spacing: 8) {
            MakeHeader(title: doc?.title ?? "Design", subtitle: subtitle, back: { dismiss() }) {
                GlassIconButton(symbol: "arrow.uturn.backward", label: "Undo") { undo() }
                    .disabled(undoStack.isEmpty)
                    .opacity(undoStack.isEmpty ? 0.45 : 1)
                GlassIconButton(symbol: "arrow.uturn.forward", label: "Redo") { redo() }
                    .disabled(redoStack.isEmpty)
                    .opacity(redoStack.isEmpty ? 0.45 : 1)
                optionsMenu
            }
            if let current = doc {
                controls(current)
                if let number = previewing {
                    previewBanner(number)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.bottom, 6)
        .background { HeaderFade() }
    }

    private var subtitle: String? {
        guard let current = doc else { return nil }
        if let number = previewing { return "v\(current.current) · previewing v\(number)" }
        return "v\(current.current)"
    }

    private var optionsMenu: some View {
        Menu {
            Button { duplicateDesign() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { sheet = .export } label: { Label("Export", systemImage: "square.and.arrow.up") }
            Button { openTokens() } label: { Label("Tokens", systemImage: "paintpalette") }
            Button { sheet = .chat } label: { Label("Linked chat", systemImage: "bubble.left.and.bubble.right") }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .kGlass(Circle(), interactive: true)
        .accessibilityLabel("Design options")
    }

    private func controls(_ current: DesignDoc) -> some View {
        HStack(spacing: 8) {
            GlassSwitch(items: DesignLayout.allCases, selection: $layout) { $0.rawValue }
            Spacer(minLength: 0)
            GlassIconButton(symbol: "clock.arrow.circlepath", label: "Versions") { sheet = .versions }
            GlassIconButton(symbol: "text.bubble", label: "Comments, \(current.openComments) open") { sheet = .comments }
                .overlay(alignment: .topTrailing) {
                    if current.openComments > 0 {
                        Text("\(current.openComments)")
                            .font(KFont.ui(11, .semibold, relativeTo: .caption2))
                            .foregroundStyle(Palette.onGold)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Palette.gold, in: Capsule())
                            .offset(x: 4, y: -4)
                            .allowsHitTesting(false)
                            .contentTransition(.numericText())
                    }
                }
            GlassIconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Focus") { openFocus(0) }
        }
        .padding(.horizontal, 16)
    }

    private func previewBanner(_ number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Previewing version \(number), read only.")
                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 8) {
                MakePillButton(title: "Restore this version", filled: true) { restore(number) }
                MakePillButton(title: "Back to current") { withAnimation(Motion.snappy) { previewing = nil } }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: Boards and canvas

    @ViewBuilder
    private func mainArea(_ current: DesignDoc) -> some View {
        if layout == .boards {
            boardsList
        } else {
            DesignCanvasView(
                boards: shownBoards,
                tokens: shownTokens,
                highlights: { highlights($0) },
                pins: { pins($0) },
                onTap: { index, element in tapped(index, element, inFocus: false) },
                onPin: { sheet = .comments },
                onFocus: { openFocus($0) },
                onMove: { id, delta in move(id, by: delta) }
            )
        }
    }

    private var boardsList: some View {
        let boards = shownBoards
        return ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(Array(boards.enumerated()), id: \.element.id) { index, board in
                    boardCard(index, board, total: boards.count)
                        .arrives(index)
                }
                if boards.isEmpty { EmptyLine(text: "This design has no boards yet.") }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func boardCard(_ index: Int, _ board: DesignBoard, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(index + 1). \(board.title)")
                        .font(KFont.ui(16, .semibold, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(board.sizeText)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                boardMenu(index, board, total: total)
            }
            DesignFitted(aspect: board.aspect, maxHeight: 340) { _ in
                DesignBoardView(board: board, tokens: shownTokens, highlights: highlights(board), pins: pins(board),
                                onTap: { element in tapped(index, element, inFocus: false) },
                                onPin: { sheet = .comments })
            }
            if mode != .pan { elementChips(board) }
        }
        .padding(12)
        .kCard(radius: 22)
    }

    private func boardMenu(_ index: Int, _ board: DesignBoard, total: Int) -> some View {
        Menu {
            Button { openFocus(index) } label: { Label("Open in focus", systemImage: "arrow.up.left.and.arrow.down.right") }
            Button { move(board.id, by: -1) } label: { Label("Move earlier", systemImage: "arrow.up") }
                .disabled(index == 0)
            Button { move(board.id, by: 1) } label: { Label("Move later", systemImage: "arrow.down") }
                .disabled(index >= total - 1)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.inkDim)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Options for \(board.title)")
    }

    private func elementChips(_ board: DesignBoard) -> some View {
        let lit = highlights(board)
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(board.elements) { element in
                    let on = lit.contains(element.id)
                    Button { act(element, on: board) } label: {
                        Chip(text: element.name, filled: on)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func highlights(_ board: DesignBoard) -> [String] {
        var ids = chips.filter { $0.boardID == board.id }.map(\.elementID)
        if let pending, pending.boardID == board.id { ids.append(pending.elementID) }
        return ids
    }

    private func pins(_ board: DesignBoard) -> [DesignComment] {
        (doc?.comments ?? []).filter { $0.boardID == board.id && $0.state != .resolved }
    }

    // MARK: Focus

    @ViewBuilder
    private var focusLayer: some View {
        if focusIndex != nil, !shownBoards.isEmpty {
            let count = shownBoards.count
            DesignFocusView(
                boards: shownBoards,
                tokens: shownTokens,
                index: Binding(get: { min(focusIndex ?? 0, count - 1) }, set: { focusIndex = $0 }),
                width: $focusWidth,
                mode: mode,
                highlights: { highlights($0) },
                pins: { pins($0) },
                onTap: { index, element in tapped(index, element, inFocus: true) },
                onPin: { sheet = .comments },
                close: { withAnimation(Motion.snappy) { focusIndex = nil } }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    // MARK: Mode bar and composer

    @ViewBuilder
    private var bottomBar: some View {
        if let current = doc {
            VStack(spacing: 8) {
                modeBar
                composer(current)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    private var modeBar: some View {
        HStack(spacing: 2) {
            ForEach(DesignMode.allCases, id: \.self) { item in
                let on = item == mode
                Button { setMode(item) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol).font(.system(size: 15, weight: .semibold))
                        Text(item.rawValue).font(KFont.ui(11.5, .medium, relativeTo: .caption2))
                    }
                    .foregroundStyle(on ? Palette.ink : Palette.inkDim)
                    .opacity(previewing != nil && item != .pan ? 0.45 : 1)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background {
                        if on { Capsule().fill(Palette.ink.opacity(0.15)).matchedGeometryEffect(id: "mode", in: modeSpace) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .kGlass(Capsule())
    }

    private func composer(_ current: DesignDoc) -> some View {
        let canSend = current.chat != nil && sendState != .working
            && (!draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chips.isEmpty)
        return VStack(alignment: .leading, spacing: 6) {
            if !chips.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(chips) { chip in
                            HStack(spacing: 0) {
                                Text(chip.label)
                                    .font(KFont.ui(13, .medium, relativeTo: .footnote))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Button {
                                    Haptics.tap()
                                    withAnimation(Motion.snappy) { chips.removeAll { $0.id == chip.id } }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Palette.inkDim)
                                        .frame(width: 40, height: 40)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Remove \(chip.elementName)")
                            }
                            .padding(.leading, 12)
                            .background(Palette.ink.opacity(0.1), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            statusLine(current)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Describe the change", text: draft, axis: .vertical)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1...5)
                    .padding(.vertical, 11)
                Button { send(current) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: 38, height: 38)
                        .background(Palette.gold, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressStyle())
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .kGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func statusLine(_ current: DesignDoc) -> some View {
        HStack(spacing: 6) {
            switch sendState {
            case .working:
                PulsingDot(color: Palette.working)
                Text("Working...")
            case .done:
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.success)
                Text("Done")
            case .idle:
                if let chat = current.chat {
                    Text("Sends to \(chat)").lineLimit(1)
                } else {
                    Text("Link a chat to ask a model for changes.").lineLimit(1)
                    Button("Link a chat") { sheet = .chat }
                        .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.goldText)
                        .frame(minHeight: 44)
                }
            }
            Spacer(minLength: 4)
            if !chips.isEmpty {
                Text("\(chips.count)/10").contentTransition(.numericText())
            }
        }
        .font(KFont.ui(13, relativeTo: .footnote))
        .foregroundStyle(Palette.inkFaint)
        .padding(.top, 2)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ which: DesignSheet) -> some View {
        switch which {
        case .versions:
            DesignVersionsSheet(
                designID: designID,
                previewing: previewing,
                onPreview: { preview($0) },
                onCompare: { number in
                    compareNumber = number
                    sheet = .compare
                },
                onRestore: { restore($0) },
                onRename: { number, name in rename(number, name) },
                onDuplicate: { duplicateVersion($0) }
            )
        case .compare:
            DesignCompareSheet(designID: designID, number: compareNumber)
        case .comments:
            DesignCommentsSheet(
                designID: designID,
                onState: { id, state in setCommentState(id, state) },
                onDelete: { deleteComment($0) },
                onSend: { sendComments($0) },
                onLink: { sheet = .chat }
            )
        case .comment:
            DesignCommentSheet(detail: targetLabel, onPin: { pinComment($0) })
        case .text:
            DesignTextSheet(detail: targetLabel, initial: targetElement?.text ?? "", onSave: { saveText($0) })
        case .export:
            DesignExportSheet(onExport: { exportHTML() })
        case .tokens:
            DesignTokensSheet(board: doc?.boards.first, saved: doc?.tokens ?? .standard, live: $liveTokens, onSave: { saveTokens($0) })
        case .chat:
            DesignChatSheet(current: doc?.chat, onPick: { linkChat($0) })
        }
    }

    private var targetBoard: DesignBoard? {
        guard let pending else { return nil }
        return shownBoards.first { $0.id == pending.boardID }
    }

    private var targetElement: DesignElement? {
        guard let pending, let board = targetBoard else { return nil }
        return board.elements.first { $0.id == pending.elementID }
    }

    private var targetLabel: String {
        guard let board = targetBoard, let element = targetElement else { return "Pick an element first" }
        return "\(board.title) · \(element.name)"
    }

    // MARK: Actions

    private func begin() {
        guard !started else { return }
        started = true
        if let index = store.index(of: designID), store.designs[index].fresh { store.designs[index].fresh = false }
        switch start {
        case .boards:
            break
        case .canvas:
            layout = .canvas
        case .versions:
            sheet = .versions
        case .compare:
            compareNumber = doc?.versions.first?.number ?? 1
            sheet = .compare
        case .comment:
            mode = .select
            if let board = doc?.boards.first,
               let element = board.elements.first(where: { $0.style == .headline }) ?? board.elements.first {
                chips = [DesignChip(boardID: board.id, elementID: element.id, boardTitle: board.title, elementName: element.name)]
                pending = DesignTarget(boardID: board.id, elementID: element.id)
                sheet = .comment
            }
        case .focus:
            focusIndex = 0
        }
    }

    /// Every change goes through here so it can be undone.
    private func change(_ apply: (inout DesignDoc) -> Void) {
        guard let index = store.index(of: designID) else { return }
        undoStack.append(store.designs[index])
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
        withAnimation(Motion.snappy) {
            apply(&store.designs[index])
            store.designs[index].edited = Date.now
        }
    }

    private func undo() {
        guard let previous = undoStack.popLast(), let index = store.index(of: designID) else { return }
        redoStack.append(store.designs[index])
        withAnimation(Motion.snappy) { store.designs[index] = previous }
        dropStalePreview()
        Haptics.tap()
        toast.say("Undone")
    }

    private func redo() {
        guard let next = redoStack.popLast(), let index = store.index(of: designID) else { return }
        undoStack.append(store.designs[index])
        withAnimation(Motion.snappy) { store.designs[index] = next }
        dropStalePreview()
        Haptics.tap()
        toast.say("Redone")
    }

    private func dropStalePreview() {
        guard let number = previewing else { return }
        let exists = doc?.versions.contains(where: { $0.number == number }) ?? false
        if !exists { previewing = nil }
    }

    private func setMode(_ item: DesignMode) {
        if previewing != nil && item != .pan {
            toast.say("Return to the current version to edit.")
            return
        }
        guard item != mode else { return }
        Haptics.select()
        withAnimation(Motion.snappy) {
            mode = item
            pending = nil
        }
        if item != .pan { toast.say(item.hint) }
    }

    private func openFocus(_ index: Int) {
        guard !shownBoards.isEmpty else { return }
        Haptics.tap()
        withAnimation(Motion.snappy) { focusIndex = min(max(0, index), shownBoards.count - 1) }
    }

    private func tapped(_ index: Int, _ element: DesignElement?, inFocus: Bool) {
        let boards = shownBoards
        guard boards.indices.contains(index) else { return }
        if mode == .pan {
            if !inFocus { openFocus(index) }
            return
        }
        guard let element else { return }
        act(element, on: boards[index])
    }

    private func act(_ element: DesignElement, on board: DesignBoard) {
        if previewing != nil {
            toast.say("Return to the current version to edit.")
            return
        }
        let target = DesignTarget(boardID: board.id, elementID: element.id)
        switch mode {
        case .pan:
            break
        case .select:
            let chip = DesignChip(boardID: board.id, elementID: element.id, boardTitle: board.title, elementName: element.name)
            if chips.contains(where: { $0.id == chip.id }) {
                Haptics.tap()
                withAnimation(Motion.snappy) { chips.removeAll { $0.id == chip.id } }
            } else if chips.count >= 10 {
                toast.say("At most 10 selections or comments per message")
            } else {
                Haptics.select()
                withAnimation(Motion.snappy) { chips.append(chip) }
                UIAccessibility.post(notification: .announcement, argument: "\(element.name) selected. Type what to change.")
            }
        case .comment:
            Haptics.tap()
            pending = target
            sheet = .comment
        case .text:
            guard element.style.isText else {
                toast.say("Pick a text element to edit.")
                return
            }
            Haptics.tap()
            pending = target
            sheet = .text
        }
    }

    private func send(_ current: DesignDoc) {
        if previewing != nil {
            toast.say("Return to the current version to edit.")
            return
        }
        guard current.chat != nil else {
            sheet = .chat
            return
        }
        let text = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !chips.isEmpty else { return }
        let element = chips.first?.elementName ?? "the design"
        let board = chips.first?.boardTitle ?? current.boards.first?.title ?? "All boards"
        Haptics.tap()
        draft.wrappedValue = ""
        withAnimation(Motion.snappy) {
            chips.removeAll()
            sendState = .working
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            change { $0.addVersion(author: "Kairos", summary: "Kairos changed \(element)", touched: board) }
            withAnimation(Motion.snappy) { sendState = .done }
            Haptics.success()
            try? await Task.sleep(for: .seconds(2.2))
            if sendState == .done { withAnimation(Motion.gentle) { sendState = .idle } }
        }
    }

    private func pinComment(_ text: String) {
        guard let board = targetBoard, let element = targetElement, !text.isEmpty else { return }
        change { doc in
            let number = (doc.comments.map(\.number).max() ?? 0) + 1
            doc.comments.append(DesignComment(id: UUID(), number: number, boardID: board.id, boardTitle: board.title,
                                              elementID: element.id, elementName: element.name, text: text,
                                              state: .open, madeOn: doc.current))
        }
        pending = nil
        Haptics.success()
        toast.say("Comment pinned")
    }

    private func saveText(_ text: String) {
        guard let board = targetBoard, let element = targetElement else { return }
        change { doc in
            guard let b = doc.boards.firstIndex(where: { $0.id == board.id }),
                  let e = doc.boards[b].elements.firstIndex(where: { $0.id == element.id }) else { return }
            doc.boards[b].elements[e].text = text
        }
        pending = nil
        Haptics.success()
        toast.say("Text saved")
    }

    private func move(_ boardID: String, by delta: Int) {
        if previewing != nil {
            toast.say("Return to the current version to edit.")
            return
        }
        change { doc in
            guard let from = doc.boards.firstIndex(where: { $0.id == boardID }) else { return }
            let to = from + delta
            guard doc.boards.indices.contains(to) else { return }
            doc.boards.swapAt(from, to)
            let title = doc.boards[to].title
            doc.addVersion(author: "You", summary: "You moved \(title)", touched: title)
        }
        Haptics.tap()
        toast.say("Board moved")
    }

    private func preview(_ number: Int) {
        sheet = nil
        withAnimation(Motion.snappy) {
            previewing = number == doc?.current ? nil : number
            mode = .pan
            pending = nil
            chips.removeAll()
        }
    }

    private func restore(_ number: Int) {
        guard let current = doc, let version = current.versions.first(where: { $0.number == number }) else { return }
        change { doc in
            doc.boards = version.boards
            doc.tokens = version.tokens
            doc.addVersion(author: "You", summary: "Restored version \(number)", touched: version.touched)
        }
        sheet = nil
        withAnimation(Motion.snappy) { previewing = nil }
        Haptics.success()
        toast.say("Restored version \(number) as a new version")
    }

    private func rename(_ number: Int, _ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        change { doc in
            guard let index = doc.versions.firstIndex(where: { $0.number == number }) else { return }
            doc.versions[index].name = clean.isEmpty ? nil : clean
        }
        toast.say(clean.isEmpty ? "Name removed" : "Version named")
    }

    private func duplicateVersion(_ number: Int) {
        guard let current = doc, let version = current.versions.first(where: { $0.number == number }) else { return }
        let title = "\(current.title) v\(number)"
        let copy = DesignSample.makeDoc(title: title, boards: version.boards, tokens: version.tokens, chat: current.chat,
                                        author: "You", summary: "Copied from version \(number)", fresh: false)
        store.add(copy)
        sheet = nil
        toast.say("Created \"\(title)\"")
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            openID = copy.id
        }
    }

    private func duplicateDesign() {
        guard let current = doc else { return }
        let title = "\(current.title) copy"
        let copy = DesignSample.makeDoc(title: title, boards: current.boards, tokens: current.tokens, chat: current.chat,
                                        author: "You", summary: "Copied from \(current.title)", fresh: false)
        store.add(copy)
        Haptics.success()
        toast.say("Created \"\(title)\"")
        openID = copy.id
    }

    private func deleteDesign() {
        withAnimation(Motion.snappy) { store.designs.removeAll { $0.id == designID } }
        Haptics.thud()
        toast.say("Design deleted")
        dismiss()
    }

    private func openTokens() {
        if previewing != nil {
            toast.say("Return to the current version to edit.")
            return
        }
        sheet = .tokens
    }

    private func saveTokens(_ tokens: DesignTokens) {
        change { doc in
            doc.tokens = tokens
            doc.addVersion(author: "You", summary: "Tokens saved", touched: "All boards")
        }
        liveTokens = nil
        Haptics.success()
        toast.say("Tokens saved as a new version")
    }

    private func exportHTML() {
        let slug = (doc?.title ?? "design").lowercased().split(separator: " ").joined(separator: "-")
        toast.say("Exporting...")
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            Haptics.success()
            toast.say("Exported \(slug).zip")
        }
    }

    private func linkChat(_ chat: String?) {
        guard let index = store.index(of: designID) else { return }
        withAnimation(Motion.snappy) { store.designs[index].chat = chat }
        Haptics.success()
        toast.say(chat.map { "Linked to \($0)" } ?? "No chat linked")
    }

    private func setCommentState(_ id: UUID, _ state: DesignCommentState) {
        change { doc in
            guard let index = doc.comments.firstIndex(where: { $0.id == id }) else { return }
            doc.comments[index].state = state
        }
        Haptics.tap()
        toast.say(state == .resolved ? "Comment resolved" : "Comment reopened")
    }

    private func deleteComment(_ id: UUID) {
        change { doc in doc.comments.removeAll { $0.id == id } }
        Haptics.tap()
        toast.say("Comment deleted")
    }

    private func sendComments(_ ids: Set<UUID>) {
        guard let current = doc, current.chat != nil, !ids.isEmpty else { return }
        let picked = current.comments.filter { ids.contains($0.id) }
        var boards: [String] = []
        for comment in picked where !boards.contains(comment.boardTitle) { boards.append(comment.boardTitle) }
        let touched = boards.joined(separator: ", ")
        let count = picked.count
        sheet = nil
        withAnimation(Motion.snappy) { sendState = .working }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            change { doc in
                doc.addVersion(author: "Kairos", summary: count == 1 ? "Kairos addressed 1 comment" : "Kairos addressed \(count) comments", touched: touched)
                let number = doc.current
                for index in doc.comments.indices where ids.contains(doc.comments[index].id) {
                    doc.comments[index].state = .addressed(number)
                }
            }
            withAnimation(Motion.snappy) { sendState = .done }
            Haptics.success()
            toast.say(count == 1 ? "Kairos addressed 1 comment" : "Kairos addressed \(count) comments")
            try? await Task.sleep(for: .seconds(2.2))
            if sendState == .done { withAnimation(Motion.gentle) { sendState = .idle } }
        }
    }
}

// MARK: - Canvas

/// Boards in rows by format. Pinch to zoom, drag to pan, Fit, and plus or minus.
struct DesignCanvasView: View {
    let boards: [DesignBoard]
    let tokens: DesignTokens
    let highlights: (DesignBoard) -> [String]
    let pins: (DesignBoard) -> [DesignComment]
    let onTap: (Int, DesignElement?) -> Void
    let onPin: () -> Void
    let onFocus: (Int) -> Void
    let onMove: (String, Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var contentSize: CGSize = .zero
    @State private var viewSize: CGSize = .zero
    @State private var fitted = false
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    /// Boards sit on the canvas at a fifth of their real width when the zoom is 1.
    private let unit: CGFloat = 0.2

    private var scale: CGFloat { clamp(zoom * pinch) }

    private var rows: [DesignRow] {
        var out: [DesignRow] = []
        for (index, board) in boards.enumerated() {
            if let row = out.firstIndex(where: { $0.format == board.format }) {
                out[row].indices.append(index)
            } else {
                out.append(DesignRow(format: board.format, indices: [index]))
            }
        }
        return out
    }

    var body: some View {
        ZStack {
            layer
        }
        // The minimums matter: without them the frame grows to the boards' full size and pushes the whole screen wide.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .contentShape(Rectangle())
        .clipped()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            viewSize = size
            fitOnce()
        }
        .gesture(panGesture)
        .simultaneousGesture(zoomGesture)
        .overlay(alignment: .top) { controls }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Design canvas")
    }

    private var layer: some View {
        VStack(alignment: .leading, spacing: 36) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 10) {
                    Text(row.format.rawValue.uppercased())
                        .font(KFont.label)
                        .tracking(1.4)
                        .foregroundStyle(Palette.inkFaint)
                    HStack(alignment: .top, spacing: 28) {
                        ForEach(row.indices, id: \.self) { index in tile(index) }
                    }
                }
            }
        }
        .padding(24)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            contentSize = size
            fitOnce()
        }
        .scaleEffect(scale)
        .offset(x: pan.width + drag.width, y: pan.height + drag.height)
    }

    private func tile(_ index: Int) -> some View {
        let board = boards[index]
        let width = board.pageWidth * unit
        let height = width / board.aspect
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(index + 1). \(board.title)")
                .font(KFont.ui(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .lineLimit(1)
            Text(board.sizeText)
                .font(KFont.ui(10.5, relativeTo: .caption2))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
            DesignBoardView(board: board, tokens: tokens, highlights: highlights(board), pins: pins(board),
                            onTap: { element in onTap(index, element) }, onPin: onPin)
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                .contextMenu {
                    Button { onFocus(index) } label: { Label("Open in focus", systemImage: "arrow.up.left.and.arrow.down.right") }
                    Button { onMove(board.id, -1) } label: { Label("Move earlier", systemImage: "arrow.left") }
                        .disabled(index == 0)
                    Button { onMove(board.id, 1) } label: { Label("Move later", systemImage: "arrow.right") }
                        .disabled(index >= boards.count - 1)
                }
        }
        .frame(width: max(width, 120), alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button { setZoom(zoom / 1.25) } label: {
                Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Zoom out")
            Text("\(Int((scale * unit * 100).rounded()))%")
                .monospacedDigit()
                .frame(minWidth: 54)
                .contentTransition(.numericText())
            Button { setZoom(zoom * 1.25) } label: {
                Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Zoom in")
            Button { fit(animated: true) } label: {
                Text("Fit").frame(minWidth: 52, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Fit all boards")
        }
        .font(KFont.ui(14.5, .semibold, relativeTo: .subheadline))
        .foregroundStyle(Palette.ink)
        .buttonStyle(PressStyle())
        .padding(.horizontal, 4)
        .kGlass(Capsule())
        .padding(.top, 8)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                pan.width += value.translation.width
                pan.height += value.translation.height
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in zoom = clamp(zoom * value.magnification) }
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(20, max(0.2, value)) }

    private func setZoom(_ value: CGFloat) {
        Haptics.tap()
        if reduceMotion { zoom = clamp(value) } else { withAnimation(Motion.snappy) { zoom = clamp(value) } }
    }

    private func fitOnce() {
        guard !fitted, contentSize.width > 0, viewSize.width > 0 else { return }
        fitted = true
        fit(animated: false)
    }

    private func fit(animated: Bool) {
        guard contentSize.width > 0, contentSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return }
        let byWidth = (viewSize.width - 24) / contentSize.width
        let byHeight = (viewSize.height - 80) / contentSize.height
        let target = clamp(min(byWidth, byHeight))
        if animated && !reduceMotion {
            withAnimation(Motion.sheet) {
                zoom = target
                pan = .zero
            }
        } else {
            zoom = target
            pan = .zero
        }
    }
}

// MARK: - Focus

/// One board large: "n / total · title", Previous, Next, Close, width presets for websites, and swipes.
struct DesignFocusView: View {
    let boards: [DesignBoard]
    let tokens: DesignTokens
    @Binding var index: Int
    @Binding var width: DesignWidth
    let mode: DesignMode
    let highlights: (DesignBoard) -> [String]
    let pins: (DesignBoard) -> [DesignComment]
    let onTap: (Int, DesignElement?) -> Void
    let onPin: () -> Void
    let close: () -> Void

    private var board: DesignBoard { boards[min(max(0, index), boards.count - 1)] }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                GlassIconButton(symbol: "xmark", label: "Close", action: close)
                Text("\(index + 1) / \(boards.count) · \(board.title)")
                    .font(KFont.ui(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            if board.format == .website {
                GlassSwitch(items: DesignWidth.allCases, selection: $width) { $0.rawValue }
            }

            TabView(selection: $index) {
                ForEach(Array(boards.enumerated()), id: \.element.id) { offset, item in
                    GeometryReader { geo in
                        DesignFitted(aspect: item.aspect, maxHeight: max(80, geo.size.height - 8),
                                     widthScale: item.format == .website ? width.scale : 1) { _ in
                            DesignBoardView(board: item, tokens: tokens, highlights: highlights(item), pins: pins(item),
                                            onTap: { element in onTap(offset, element) }, onPin: onPin)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if mode != .pan {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(board.elements) { element in
                            let on = highlights(board).contains(element.id)
                            Button { onTap(index, element) } label: {
                                Chip(text: element.name, filled: on).frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 10) {
                MakePillButton(title: "Previous", symbol: "chevron.left", expand: true) { step(-1) }
                    .disabled(index <= 0)
                    .opacity(index <= 0 ? 0.45 : 1)
                MakePillButton(title: "Next", symbol: "chevron.right", expand: true) { step(1) }
                    .disabled(index >= boards.count - 1)
                    .opacity(index >= boards.count - 1 ? 0.45 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background { Palette.ground.ignoresSafeArea(edges: .top) }
    }

    private func step(_ delta: Int) {
        withAnimation(Motion.snappy) { index = max(0, min(boards.count - 1, index + delta)) }
    }
}

// MARK: - Sheets

struct DesignStartSheet: View {
    let onStart: (String, DesignFormat) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var format: DesignFormat = .website

    private var blank: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        FittedSheet(estimate: 520) {
            VStack(alignment: .leading, spacing: 18) {
                MakeSheetTitle(title: "Design with a model", detail: "Describe what you want and the model builds the boards.")
                MakeField(label: "Describe it", text: $prompt, prompt: "A booking page for a bike shop", limit: 2000, lines: 3...6)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Format")
                    HStack(spacing: 6) {
                        ForEach(DesignFormat.allCases, id: \.self) { item in
                            Button {
                                Haptics.select()
                                withAnimation(Motion.snappy) { format = item }
                            } label: {
                                Chip(text: item.rawValue, filled: format == item).frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityAddTraits(format == item ? .isSelected : [])
                        }
                    }
                }
                GoldButton(title: "Start") {
                    onStart(prompt.trimmingCharacters(in: .whitespacesAndNewlines), format)
                    dismiss()
                }
                .disabled(blank)
                .opacity(blank ? 0.5 : 1)
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }
}

struct DesignCommentSheet: View {
    let detail: String
    let onPin: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var blank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        FittedSheet(estimate: 440) {
            VStack(spacing: 16) {
                MakeSheetTitle(title: "What should change?", detail: detail)
                MakeField(label: "Comment", text: $text, prompt: "Say what to change", limit: 4000, lines: 3...8)
                GoldButton(title: "Pin comment") {
                    onPin(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .disabled(blank)
                .opacity(blank ? 0.5 : 1)
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }
}

struct DesignTextSheet: View {
    let detail: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(detail: String, initial: String, onSave: @escaping (String) -> Void) {
        self.detail = detail
        self.onSave = onSave
        self._text = State(initialValue: initial)
    }

    private var blank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        FittedSheet(estimate: 400) {
            VStack(spacing: 16) {
                MakeSheetTitle(title: "Edit text", detail: detail)
                MakeField(label: "Text", text: $text, limit: 400, lines: 2...6)
                GoldButton(title: "Save") {
                    onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .disabled(blank)
                .opacity(blank ? 0.5 : 1)
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }
}

struct DesignVersionsSheet: View {
    let designID: String
    let previewing: Int?
    let onPreview: (Int) -> Void
    let onCompare: (Int) -> Void
    let onRestore: (Int) -> Void
    let onRename: (Int, String) -> Void
    let onDuplicate: (Int) -> Void
    @State private var renaming: Int?
    @State private var nameDraft = ""

    var body: some View {
        let doc = DesignStore.shared.design(designID)
        let current = doc?.current ?? 1
        let groups = DesignVersionGroup.make(doc?.versions ?? [])
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MakeSheetTitle(title: "Versions", detail: "Version \(current) is current")
                ForEach(Array(groups.enumerated()), id: \.element.id) { offset, group in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: group.title)
                        ForEach(group.versions) { version in row(version, current: current) }
                    }
                    .arrives(offset)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .alert("Name this version", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                if let number = renaming { onRename(number, nameDraft) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("A named version is kept when old versions are cleared.")
        }
    }

    private func row(_ version: DesignVersion, current: Int) -> some View {
        let isCurrent = version.number == current
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(version.name ?? "Version \(version.number)")
                    .font(KFont.ui(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if isCurrent { StatePill(text: "Current", tone: .ok) }
                if previewing == version.number { StatePill(text: "Previewing", tone: .working) }
                Spacer(minLength: 4)
                Text(version.date.formatted(date: .abbreviated, time: .shortened))
                    .font(KFont.ui(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
            Text(version.name == nil ? version.summary : "v\(version.number) · \(version.summary)")
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    MakePillButton(title: "Preview") { onPreview(version.number) }
                    MakePillButton(title: "Compare") { onCompare(version.number) }
                        .disabled(isCurrent)
                        .opacity(isCurrent ? 0.4 : 1)
                    MakePillButton(title: "Restore") { onRestore(version.number) }
                        .disabled(isCurrent)
                        .opacity(isCurrent ? 0.4 : 1)
                    MakePillButton(title: version.name == nil ? "Name" : "Rename") {
                        nameDraft = version.name ?? ""
                        renaming = version.number
                    }
                    MakePillButton(title: "Duplicate as new design") { onDuplicate(version.number) }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .kCard(radius: 20, raised: isCurrent)
    }
}

struct DesignCompareSheet: View {
    let designID: String
    let number: Int
    @State private var picked: String?

    var body: some View {
        let doc = DesignStore.shared.design(designID)
        let old = doc?.versions.first { $0.number == number }
        let currentBoards = doc?.boards ?? []
        let oldBoards = old?.boards ?? []
        let shared = currentBoards.filter { board in oldBoards.contains { $0.id == board.id } }
        let chosenID = picked ?? shared.first?.id
        let newer = currentBoards.first { $0.id == chosenID }
        let older = oldBoards.first { $0.id == chosenID }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Compare v\(number) with current", detail: "Version \(number) above, the current design below.")
                if shared.isEmpty {
                    EmptyLine(text: "That version shares no boards with the current design.")
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(shared) { board in
                                Button {
                                    Haptics.select()
                                    withAnimation(Motion.snappy) { picked = board.id }
                                } label: {
                                    Chip(text: board.title, filled: board.id == chosenID).frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityAddTraits(board.id == chosenID ? .isSelected : [])
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    if let older, let newer, let old, let doc {
                        SectionLabel(text: "Version \(number)")
                        DesignFitted(aspect: older.aspect, maxHeight: 300) { _ in
                            DesignBoardView(board: older, tokens: old.tokens)
                        }
                        SectionLabel(text: "Current")
                        DesignFitted(aspect: newer.aspect, maxHeight: 300) { _ in
                            DesignBoardView(board: newer, tokens: doc.tokens)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }
}

struct DesignCommentsSheet: View {
    let designID: String
    let onState: (UUID, DesignCommentState) -> Void
    let onDelete: (UUID) -> Void
    let onSend: (Set<UUID>) -> Void
    let onLink: () -> Void
    @State private var picks: Set<UUID> = []
    @State private var seeded = false

    var body: some View {
        let doc = DesignStore.shared.design(designID)
        let comments = doc?.comments ?? []
        let current = doc?.current ?? 1
        let chat = doc?.chat
        let openIDs = Set(comments.filter { $0.state == .open }.map(\.id))
        let chosen = picks.intersection(openIDs)
        let canSend = !chosen.isEmpty && chat != nil
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MakeSheetTitle(title: "Comments", detail: openIDs.count == 1 ? "1 open" : "\(openIDs.count) open")
                if comments.isEmpty { EmptyLine(text: "No comments yet.") }
                ForEach(Array(comments.enumerated()), id: \.element.id) { offset, comment in
                    row(comment, current: current).arrives(offset)
                }
                if chat == nil {
                    EmptyLine(text: "Link this design to a chat to send comments to a model.")
                    MakePillButton(title: "Link a chat", symbol: "link") { onLink() }
                }
                GoldButton(title: chosen.count == 1 ? "Send 1 comment" : "Send \(chosen.count) comments") { onSend(chosen) }
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.5)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .onAppear {
            guard !seeded else { return }
            seeded = true
            picks = openIDs
        }
    }

    private func row(_ comment: DesignComment, current: Int) -> some View {
        let isOpen = comment.state == .open
        let picked = isOpen && picks.contains(comment.id)
        return HStack(alignment: .top, spacing: 6) {
            Button {
                Haptics.select()
                if picks.contains(comment.id) { picks.remove(comment.id) } else { picks.insert(comment.id) }
            } label: {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(picked ? Palette.goldText : Palette.inkFaint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(!isOpen)
            .opacity(isOpen ? 1 : 0.35)
            .accessibilityLabel("Include comment \(comment.number)")
            .accessibilityAddTraits(picked ? .isSelected : [])

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(comment.number). \(comment.boardTitle)")
                        .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    statePill(comment.state)
                }
                Text(comment.text)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(comment.madeOn < current ? "\(comment.elementName) · made on v\(comment.madeOn)" : comment.elementName)
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                HStack(spacing: 6) {
                    if comment.state == .resolved {
                        MakePillButton(title: "Reopen") { onState(comment.id, .open) }
                    } else {
                        MakePillButton(title: "Resolve") { onState(comment.id, .resolved) }
                    }
                    MakePillButton(title: "Delete", danger: true) { onDelete(comment.id) }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.trailing, 12)
        .padding(.leading, 2)
        .kCard(radius: 20)
    }

    private func statePill(_ state: DesignCommentState) -> StatePill {
        switch state {
        case .open: return StatePill(text: "Open", tone: .warn)
        case .addressed(let number): return StatePill(text: "Addressed in v\(number)", tone: .ok)
        case .resolved: return StatePill(text: "Resolved", tone: .muted)
        }
    }
}

struct DesignExportSheet: View {
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let rows: [(symbol: String, title: String, detail: String, ready: Bool)] = [
        ("doc.zipper", "HTML zip", "Opens offline in any browser", true),
        ("photo", "PNG images", "Needs the Kairos desktop app", false),
        ("doc.richtext", "PDF", "Needs the Kairos desktop app", false),
        ("rectangle.on.rectangle", "PowerPoint", "Needs the Kairos desktop app", false),
    ]

    var body: some View {
        FittedSheet(estimate: 460) {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Export")
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                        Button {
                            Haptics.tap()
                            onExport()
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: row.symbol)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(row.ready ? Palette.goldText : Palette.inkFaint)
                                    .frame(width: 40, height: 40)
                                    .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.title).font(KFont.ui(16.5)).foregroundStyle(row.ready ? Palette.ink : Palette.inkFaint)
                                    Text(row.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if offset < rows.count - 1 { Palette.line.frame(height: 1).padding(.leading, 68) }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .disabled(!row.ready)
                        .arrives(offset)
                    }
                }
                .kCard(radius: 20)
                EmptyLine(text: "PNG, PDF and PowerPoint need the Kairos desktop app.")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
    }
}

struct DesignTokensSheet: View {
    let board: DesignBoard?
    let saved: DesignTokens
    @Binding var live: DesignTokens?
    let onSave: (DesignTokens) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DesignTokens

    init(board: DesignBoard?, saved: DesignTokens, live: Binding<DesignTokens?>, onSave: @escaping (DesignTokens) -> Void) {
        self.board = board
        self.saved = saved
        self._live = live
        self.onSave = onSave
        self._draft = State(initialValue: saved)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MakeSheetTitle(title: "Tokens", detail: "Changes show on every board right away.")
                if let board {
                    DesignFitted(aspect: board.aspect, maxHeight: 170) { _ in
                        DesignBoardView(board: board, tokens: draft)
                    }
                }
                swatchRow("Accent", options: DesignSwatch.accents, value: $draft.accent)
                swatchRow("Background", options: DesignSwatch.grounds, value: $draft.ground)
                swatchRow("Text colour", options: DesignSwatch.inks, value: $draft.ink)
                sliderRow("Corner radius", value: $draft.radius, range: 0...32, step: 1, text: "\(Int(draft.radius)) px")
                sliderRow("Text size", value: $draft.textScale, range: 0.8...1.3, step: 0.05, text: "\(Int((draft.textScale * 100).rounded()))%")
                GoldButton(title: "This design only") {
                    onSave(draft)
                    dismiss()
                }
                .disabled(draft == saved)
                .opacity(draft == saved ? 0.5 : 1)
                HStack(spacing: 8) {
                    QuietButton(title: "Discard") { withAnimation(Motion.snappy) { draft = saved } }
                    QuietButton(title: "Use system values") { withAnimation(Motion.snappy) { draft = .standard } }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .onChange(of: draft) { live = draft }
        .onDisappear { live = nil }
    }

    private func swatchRow(_ title: String, options: [DesignSwatch], value: Binding<UInt32>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: title)
            HStack(spacing: 4) {
                ForEach(options) { swatch in
                    let on = value.wrappedValue == swatch.hex
                    Button {
                        Haptics.select()
                        value.wrappedValue = swatch.hex
                    } label: {
                        Circle()
                            .fill(Color(hex: swatch.hex))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Palette.lineStrong, lineWidth: 1))
                            .padding(4)
                            .overlay(Circle().strokeBorder(on ? Palette.gold : Color.clear, lineWidth: 2.5))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(title): \(swatch.name)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionLabel(text: title)
                Text(text)
                    .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
                .tint(Palette.gold)
                .frame(minHeight: 44)
                .accessibilityLabel(title)
                .accessibilityValue(text)
        }
    }
}

struct DesignChatSheet: View {
    let current: String?
    let onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let options: [String?] = [nil] + DesignSample.chats.map { Optional($0) }
        FittedSheet(estimate: 420) {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "Chat that changes this design", detail: "Your selections, comments and messages go to this chat.")
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                        Button {
                            Haptics.select()
                            onPick(option)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option == nil ? "slash.circle" : "bubble.left")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Palette.goldText)
                                    .frame(width: 26)
                                Text(option ?? "No chat").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                Spacer(minLength: 0)
                                if option == current {
                                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if offset < options.count - 1 { Palette.line.frame(height: 1).padding(.leading, 54) }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                        .accessibilityAddTraits(option == current ? .isSelected : [])
                    }
                }
                .kCard(radius: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
    }
}
