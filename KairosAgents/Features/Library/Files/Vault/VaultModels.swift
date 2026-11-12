import SwiftUI

// The Vault: a folder of Markdown notes on the person's desktop.
// The phone reads it through the desktop; until then it shows made-up sample notes.

nonisolated struct VaultNote: Identifiable, Hashable, Sendable {
    /// The path without ".md", for example "Projects/Bike shop/Launch plan".
    let id: String
    var body: String
    var edited: Date
    var editedBy: String

    var title: String { id.split(separator: "/").last.map(String.init) ?? id }
    var folder: String {
        let parts = id.split(separator: "/").map(String.init)
        return parts.dropLast().joined(separator: "/")
    }
    var topFolder: String { id.split(separator: "/").first.map(String.init) ?? "" }
    var properties: [(key: String, value: String)] { VaultMarkdown.frontmatter(body) }
    func property(_ key: String) -> String? { properties.first { $0.key == key }?.value }
    var content: String { VaultMarkdown.stripFrontmatter(body) }
    var words: Int { content.split { $0.isWhitespace || $0.isNewline }.count }
    var isDaily: Bool { VaultDates.dailyDate(title) != nil }
    var isIndex: Bool { !folder.isEmpty && title == folder.split(separator: "/").last.map(String.init) }
    var wikilink: String { "[[\(title)]]" }
}

nonisolated struct VaultChange: Identifiable, Hashable, Sendable {
    let id = UUID()
    var date: Date
    var label: String
    var by: String
    /// The note as it was before this change.
    var before: String
    var after: String
}

/// A filtered list reached from Vault Home.
nonisolated enum VaultFilter: Hashable, Sendable {
    case orphans
    case missingProperties
    case property(String, String)

    var title: String {
        switch self {
        case .orphans: "Needs a link"
        case .missingProperties: "Missing properties"
        case .property(let key, let value): "\(key): \(value)"
        }
    }
}

nonisolated enum VaultRoute: Hashable, Sendable {
    case folder(String)
    case note(String)
    case list(VaultFilter)
    case map(String?)
}

nonisolated enum VaultDates {
    static func dailyDate(_ title: String) -> Date? {
        guard title.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: title)
    }

    static func dailyTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}

/// What a search finds by name: a note or a folder.
nonisolated enum VaultHit: Identifiable, Hashable, Sendable {
    case note(String)
    case folder(String)
    var id: String {
        switch self {
        case .note(let id): "n-\(id)"
        case .folder(let path): "f-\(path)"
        }
    }
}

protocol VaultProviding: AnyObject {
    var notes: [String: VaultNote] { get }
    func save(_ id: String, body: String)
    func togglePin(_ id: String)
}

/// One loaded vault, shared by Home, Browse, the reader and the Map.
@Observable
final class VaultStore: VaultProviding {
    static let shared = VaultStore()

    var notes: [String: VaultNote] = [:]
    var pins: [String] = []
    var recent: [String] = []
    var history: [String: [VaultChange]] = [:]
    var expanded: Set<String> = []
    let dailyFolder = "Daily notes"
    let templatePath = "Templates/Daily note"

    init() { reload() }

    func reload() {
        notes = Dictionary(uniqueKeysWithValues: VaultSample.notes().map { ($0.id, $0) })
        pins = ["Projects/Bike shop/Launch plan", "Home"]
        recent = ["Projects/Bike shop/Launch plan", "Ideas/Video ideas", VaultDates.dailyTitle(.now.addingTimeInterval(-86_400))]
            .compactMap { title in notes[title] != nil ? title : notes.values.first { $0.title == title }?.id }
        history = VaultSample.history(notes)
    }

    // MARK: Reading

    func note(_ id: String) -> VaultNote? { notes[id] }

    var sortedNotes: [VaultNote] { notes.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending } }

    var folders: [String] {
        var set = Set<String>()
        for note in notes.values {
            var parts = note.id.split(separator: "/").map(String.init)
            parts.removeLast()
            while !parts.isEmpty {
                set.insert(parts.joined(separator: "/"))
                parts.removeLast()
            }
        }
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func folderName(_ path: String) -> String { path.split(separator: "/").last.map(String.init) ?? "Vault" }

    /// Folders first, the folder's index note first, natural order; daily folders newest first.
    func children(of folder: String) -> (folders: [String], notes: [VaultNote]) {
        let depth = folder.isEmpty ? 0 : folder.split(separator: "/").count
        let subfolders = folders.filter { path in
            let parts = path.split(separator: "/")
            return parts.count == depth + 1 && (folder.isEmpty || path.hasPrefix(folder + "/"))
        }
        var direct = notes.values.filter { $0.folder == folder }
        let daily = direct.filter(\.isDaily).count
        if direct.count >= 3 && Double(daily) / Double(direct.count) >= 0.6 {
            direct.sort { a, b in
                if a.isDaily != b.isDaily { return !a.isDaily }
                return a.title > b.title
            }
        } else {
            direct.sort { a, b in
                if a.isIndex != b.isIndex { return a.isIndex }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
        return (subfolders, direct)
    }

    func noteCount(in folder: String) -> Int {
        notes.values.filter { folder.isEmpty || $0.id.hasPrefix(folder + "/") }.count
    }

    func indexNote(of folder: String) -> VaultNote? {
        notes.values.first { $0.folder == folder && $0.isIndex }
    }

    func resolve(_ target: String) -> VaultNote? {
        let clean = target.trimmingCharacters(in: .whitespaces)
        if let exact = notes[clean] { return exact }
        let lower = clean.lowercased()
        return notes.values.first { $0.title.lowercased() == lower || $0.id.lowercased() == lower }
    }

    func outlinks(_ id: String) -> (resolved: [VaultNote], unresolved: [String]) {
        guard let note = notes[id] else { return ([], []) }
        var resolved: [VaultNote] = []
        var unresolved: [String] = []
        for target in VaultMarkdown.linkTargets(note.content) {
            if let hit = resolve(target) {
                if hit.id != id && !resolved.contains(hit) { resolved.append(hit) }
            } else if !unresolved.contains(target) {
                unresolved.append(target)
            }
        }
        return (resolved, unresolved)
    }

    func backlinks(_ id: String) -> [(note: VaultNote, snippet: String)] {
        guard let target = notes[id] else { return [] }
        return sortedNotes.compactMap { other in
            guard other.id != id else { return nil }
            let links = VaultMarkdown.linkTargets(other.content)
            guard links.contains(where: { resolve($0)?.id == target.id }) else { return nil }
            let line = other.content.split(separator: "\n").first { $0.contains("[[") && $0.lowercased().contains(target.title.lowercased()) }
            return (other, VaultMarkdown.plain(String(line ?? "")))
        }
    }

    var linkCount: Int { notes.keys.reduce(0) { $0 + outlinks($1).resolved.count } }

    var orphans: [VaultNote] {
        sortedNotes.filter { note in
            let out = outlinks(note.id)
            return out.resolved.isEmpty && out.unresolved.isEmpty && backlinks(note.id).isEmpty
        }
    }

    static let requiredProperties = ["status", "project", "type"]

    var lackingProperties: [VaultNote] {
        sortedNotes.filter { note in !note.isDaily && Self.requiredProperties.contains { note.property($0) == nil } }
    }

    /// Top values per property key, with counts.
    var propertyValues: [(key: String, values: [(value: String, count: Int)])] {
        Self.requiredProperties.compactMap { key in
            var counts: [String: Int] = [:]
            for note in notes.values { if let value = note.property(key) { counts[value, default: 0] += 1 } }
            guard !counts.isEmpty else { return nil }
            let values = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(12).map { (value: $0.key, count: $0.value) }
            return (key, values)
        }
    }

    func notes(for filter: VaultFilter) -> [VaultNote] {
        switch filter {
        case .orphans: orphans
        case .missingProperties: lackingProperties
        case .property(let key, let value): sortedNotes.filter { $0.property(key) == value }
        }
    }

    // MARK: Search

    func nameMatches(_ query: String) -> [VaultHit] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let folderHits = folders.filter { $0.lowercased().contains(q) }.map { VaultHit.folder($0) }
        let noteHits = sortedNotes.filter { $0.id.lowercased().contains(q) }.map { VaultHit.note($0.id) }
        return Array((noteHits + folderHits).prefix(30))
    }

    func textMatches(_ query: String) -> [(note: VaultNote, snippet: String)] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return sortedNotes.compactMap { note in
            let text = VaultMarkdown.plain(note.content)
            guard let range = text.lowercased().range(of: q) else { return nil }
            let lower = text.lowercased()
            let start = lower.index(range.lowerBound, offsetBy: -40, limitedBy: lower.startIndex) ?? lower.startIndex
            let end = lower.index(range.upperBound, offsetBy: 60, limitedBy: lower.endIndex) ?? lower.endIndex
            let startOffset = lower.distance(from: lower.startIndex, to: start)
            let endOffset = lower.distance(from: lower.startIndex, to: end)
            let a = text.index(text.startIndex, offsetBy: startOffset)
            let b = text.index(text.startIndex, offsetBy: endOffset)
            var snippet = String(text[a..<b]).replacingOccurrences(of: "\n", with: " ")
            if start != lower.startIndex { snippet = "..." + snippet }
            if end != lower.endIndex { snippet += "..." }
            return (note, snippet)
        }
    }

    /// Notes that share enough uncommon words with this one.
    func related(_ id: String) -> [VaultNote] {
        guard let note = notes[id] else { return [] }
        let mine = VaultMarkdown.keywords(note.content)
        let linked = Set(outlinks(id).resolved.map(\.id) + backlinks(id).map(\.note.id))
        return sortedNotes
            .filter { $0.id != id && !linked.contains($0.id) }
            .map { ($0, VaultMarkdown.keywords($0.content).intersection(mine).count) }
            .filter { $0.1 >= 3 }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map(\.0)
    }

    /// Neighbours of a note within a number of link steps.
    func neighbourhood(_ id: String, depth: Int) -> [String: Int] {
        var seen: [String: Int] = [id: 0]
        var frontier = [id]
        for step in 1...max(1, depth) {
            var next: [String] = []
            for current in frontier {
                let around = outlinks(current).resolved.map(\.id) + backlinks(current).map(\.note.id)
                for other in around where seen[other] == nil {
                    seen[other] = step
                    next.append(other)
                }
            }
            frontier = next
        }
        return seen
    }

    // MARK: Changing

    func remember(_ id: String) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        if recent.count > 8 { recent.removeLast(recent.count - 8) }
    }

    func togglePin(_ id: String) {
        if pins.contains(id) { pins.removeAll { $0 == id } } else { pins.append(id) }
    }

    func save(_ id: String, body: String) {
        guard var note = notes[id], note.body != body else { return }
        let before = note.body
        note.body = body
        note.edited = .now
        note.editedBy = "you"
        notes[id] = note
        let added = body.split(separator: "\n").count - before.split(separator: "\n").count
        let label = added >= 0 ? "+\(max(1, added)) −\(added == 0 ? 1 : 0)" : "+0 −\(-added)"
        history[id, default: []].insert(VaultChange(date: .now, label: label, by: "you", before: before, after: body), at: 0)
    }

    func restore(_ id: String, to change: VaultChange) {
        guard var note = notes[id] else { return }
        let before = note.body
        note.body = change.before
        note.edited = .now
        note.editedBy = "you (restored)"
        notes[id] = note
        history[id, default: []].insert(VaultChange(date: .now, label: "Restored", by: "you", before: before, after: change.before), at: 0)
    }

    var todayID: String { "\(dailyFolder)/\(VaultDates.dailyTitle(.now))" }
    var hasTemplate: Bool { notes[templatePath] != nil }

    /// Creates today's daily note from the template. Returns false when it already existed.
    @discardableResult
    func createToday() -> Bool {
        guard notes[todayID] == nil else { return false }
        let template = notes[templatePath]?.content ?? "## Notes\n"
        let body = "---\ntype: daily\n---\n# \(VaultDates.dailyTitle(.now))\n\n" + template
        notes[todayID] = VaultNote(id: todayID, body: body, edited: .now, editedBy: "you")
        history[todayID] = [VaultChange(date: .now, label: "Created", by: "you", before: "", after: body)]
        return true
    }

    /// The folder index note and the line that would list this note in it, when the index does not list it yet.
    func indexSuggestion(for id: String) -> (index: VaultNote, line: String)? {
        guard let note = notes[id], let index = indexNote(of: note.folder), index.id != id else { return nil }
        guard !VaultMarkdown.linkTargets(index.content).contains(note.title) else { return nil }
        return (index, "- [[\(note.title)]]")
    }

    /// Adds the line to the folder index, above the first list item. Returns false when the index changed since it was read.
    @discardableResult
    func addToIndex(_ id: String, expecting edited: Date) -> Bool {
        guard let suggestion = indexSuggestion(for: id), suggestion.index.edited == edited else { return false }
        var lines = suggestion.index.body.components(separatedBy: "\n")
        let at = lines.firstIndex { $0.hasPrefix("- ") } ?? lines.count
        lines.insert(suggestion.line, at: at)
        save(suggestion.index.id, body: lines.joined(separator: "\n"))
        return true
    }

    /// Day numbers in a month that have a daily note, mapped to the note.
    func dailyNotes(inMonthOf date: Date) -> [Int: String] {
        let calendar = Calendar.current
        var result: [Int: String] = [:]
        for note in notes.values {
            guard let day = VaultDates.dailyDate(note.title),
                  calendar.isDate(day, equalTo: date, toGranularity: .month) else { continue }
            result[calendar.component(.day, from: day)] = note.id
        }
        return result
    }

    var latestDaily: VaultNote? {
        notes.values.filter(\.isDaily).max { $0.title < $1.title }
    }

    var recentlyChanged: [VaultNote] {
        Array(notes.values.sorted { $0.edited > $1.edited }.prefix(8))
    }
}
