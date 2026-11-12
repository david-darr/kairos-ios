import SwiftUI

// The data behind Library documents, chat files and uploads.
// Sample stores stand in until the desktop connection fills them. Everything here is made up.

// MARK: - Library documents

nonisolated struct LibraryDocument: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var body: String
    var updated: Date
}

@Observable
final class LibraryDocumentsStore {
    static let shared = LibraryDocumentsStore(documents: DocSample.documents())

    private var all: [LibraryDocument]

    init(documents: [LibraryDocument]) {
        all = documents
    }

    /// Newest first.
    var documents: [LibraryDocument] {
        all.sorted { $0.updated > $1.updated }
    }

    func document(_ id: String) -> LibraryDocument? {
        all.first { $0.id == id }
    }

    func create() -> LibraryDocument {
        let document = LibraryDocument(id: "doc-\(UUID().uuidString)", title: "Untitled", body: "", updated: .now)
        all.append(document)
        return document
    }

    func save(_ document: LibraryDocument) {
        var saved = document
        saved.updated = .now
        if let index = all.firstIndex(where: { $0.id == document.id }) {
            all[index] = saved
        } else {
            all.append(saved)
        }
    }

    func delete(id: String) {
        all.removeAll { $0.id == id }
    }

    func importText(name: String, text: String) -> LibraryDocument {
        let base = (name as NSString).deletingPathExtension
        let title = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = LibraryDocument(id: "doc-\(UUID().uuidString)", title: title.isEmpty ? "Untitled" : title, body: text, updated: .now)
        all.append(document)
        return document
    }
}

nonisolated enum DocSample {
    static func documents(now: Date = .now) -> [LibraryDocument] {
        [
            LibraryDocument(id: "doc-report", title: "Weekly report", body: "Sales were up on last week, mostly from tune-ups.\n\nThe new repair bench is in and working. Two bikes are waiting on parts from the supplier.\n\nNext week: finish the window display and send the newsletter.", updated: now.addingTimeInterval(-40 * 60)),
            LibraryDocument(id: "doc-launch", title: "Launch plan", body: "Opening day is Saturday. Doors at 9.\n\nBefore then: print the posters, set the prices, test the card reader, and book the van for the delivery.", updated: now.addingTimeInterval(-5 * 3600)),
            LibraryDocument(id: "doc-faq", title: "Shop questions and answers", body: "How long does a tune-up take? Usually one day.\n\nDo you fit tyres you did not sell? Yes, for a small fee.\n\nCan I book a repair online? Not yet. Call the shop.", updated: now.addingTimeInterval(-26 * 3600)),
            LibraryDocument(id: "doc-newsletter", title: "Newsletter draft", body: "Spring is here. Time to pump up those tyres and oil that chain.\n\nThis month: a free safety check with every tune-up.", updated: now.addingTimeInterval(-3 * 86_400)),
            LibraryDocument(id: "doc-ideas", title: "Window display ideas", body: "A row of city bikes in the colours of the season. A small sign with the opening hours. Lights on a timer until 8.", updated: now.addingTimeInterval(-9 * 86_400)),
        ]
    }
}

/// A short piece of a document around a search match.
nonisolated enum DocSnippet {
    static func make(_ body: String, query: String) -> String? {
        guard let range = body.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = body.index(range.lowerBound, offsetBy: -30, limitedBy: body.startIndex) ?? body.startIndex
        let end = body.index(range.upperBound, offsetBy: 60, limitedBy: body.endIndex) ?? body.endIndex
        let piece = String(body[start..<end]).replacingOccurrences(of: "\n", with: " ")
        let lead = start > body.startIndex ? "…" : ""
        let tail = end < body.endIndex ? "…" : ""
        return lead + piece.trimmingCharacters(in: .whitespaces) + tail
    }

    static func words(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

// MARK: - Chat files

nonisolated enum ChatDocsOrigin: Hashable, Sendable {
    case sent, created, generated

    var label: String {
        switch self {
        case .sent: "Sent to chat"
        case .created: "Created by model"
        case .generated: "Generated"
        }
    }
}

nonisolated struct ChatDocsFile: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var bytes: Int
    var origin: ChatDocsOrigin
    var look: ChatDocument.Look
    var available = true

    var ext: String { (name as NSString).pathExtension }
    var size: String { Int64(bytes).formatted(.byteCount(style: .file)) }

    var kind: String {
        switch look {
        case .design: "Design"
        case .sheet: "Sheet"
        case .page: "Document"
        }
    }
}

nonisolated struct ChatDocsGroup: Identifiable, Hashable, Sendable {
    /// The conversation's id.
    let id: String
    var title: String
    var files: [ChatDocsFile]
}

@Observable
final class ChatDocsStore {
    static let shared = ChatDocsStore(groups: ChatDocsSample.groups())

    var groups: [ChatDocsGroup]
    /// Remembered while browsing, like the desktop.
    var openGroups: Set<String> = ["c-bike"]
    var documentsOpen = true
    var filesOpen = true

    init(groups: [ChatDocsGroup]) {
        self.groups = groups
    }

    var fileCount: Int { groups.reduce(0) { $0 + $1.files.count } }

    func toggle(_ groupID: String) {
        if openGroups.contains(groupID) {
            openGroups.remove(groupID)
        } else {
            openGroups.insert(groupID)
        }
    }
}

nonisolated enum ChatDocsSample {
    static func groups() -> [ChatDocsGroup] {
        func title(_ id: String) -> String { SampleData.conversation(id).title }
        return [
            ChatDocsGroup(id: "c-bike", title: title("c-bike"), files: [
                ChatDocsFile(id: "f-booking", name: "Booking page.png", bytes: 906_000, origin: .created, look: .design),
                ChatDocsFile(id: "f-prices", name: "Rival prices.xlsx", bytes: 14_200, origin: .generated, look: .sheet),
                ChatDocsFile(id: "f-plan", name: "Launch plan.docx", bytes: 22_400, origin: .created, look: .page),
                ChatDocsFile(id: "f-hours", name: "Opening hours.txt", bytes: 1_200, origin: .sent, look: .page),
            ]),
            ChatDocsGroup(id: "c-kip", title: title("c-kip"), files: [
                ChatDocsFile(id: "f-weekly", name: "Weekly report.docx", bytes: 31_800, origin: .generated, look: .page),
                ChatDocsFile(id: "f-outline", name: "Report outline.md", bytes: 2_900, origin: .created, look: .page),
            ]),
            ChatDocsGroup(id: "c-quill", title: title("c-quill"), files: [
                ChatDocsFile(id: "f-draft", name: "Second draft.docx", bytes: 27_500, origin: .created, look: .page),
                ChatDocsFile(id: "f-intro", name: "Old intro.txt", bytes: 3_100, origin: .sent, look: .page, available: false),
            ]),
            ChatDocsGroup(id: "c-atlas", title: title("c-atlas"), files: [
                ChatDocsFile(id: "f-budget", name: "Trip budget.xlsx", bytes: 18_600, origin: .generated, look: .sheet),
            ]),
            ChatDocsGroup(id: "c-ledger", title: title("c-ledger"), files: [
                ChatDocsFile(id: "f-receipts", name: "October receipts.pdf", bytes: 412_000, origin: .sent, look: .page),
            ]),
        ]
    }
}

// MARK: - Uploads

nonisolated struct UploadedFile: Identifiable, Hashable, Sendable {
    let id: String
    /// The name without its extension.
    var name: String
    var ext: String
    var bytes: Int
    var added: Date

    var fileName: String { ext.isEmpty ? name : "\(name).\(ext)" }
    var size: String { Int64(bytes).formatted(.byteCount(style: .file)) }
}

nonisolated enum UploadsSort: String, CaseIterable, Hashable, Sendable {
    case newest = "Newest"
    case name = "Name"
    case size = "Size"
}

@Observable
final class UploadsStore {
    static let shared = UploadsStore(files: UploadsSample.files())

    var files: [UploadedFile]
    var sort: UploadsSort = .newest

    init(files: [UploadedFile]) {
        self.files = files
    }

    func shown(matching query: String) -> [UploadedFile] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let picked = needle.isEmpty ? files : files.filter { $0.fileName.localizedCaseInsensitiveContains(needle) }
        switch sort {
        case .newest: return picked.sorted { $0.added > $1.added }
        case .name: return picked.sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
        case .size: return picked.sorted { $0.bytes > $1.bytes }
        }
    }

    func add(name: String, ext: String, bytes: Int) {
        files.append(UploadedFile(id: "up-\(UUID().uuidString)", name: name, ext: ext, bytes: bytes, added: .now))
    }

    func rename(_ id: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].name = clean
    }

    func delete(_ id: String) {
        files.removeAll { $0.id == id }
    }
}

nonisolated enum UploadsSample {
    static func files(now: Date = .now) -> [UploadedFile] {
        let day: TimeInterval = 86_400
        return [
            UploadedFile(id: "up-floor", name: "Shop floor plan", ext: "pdf", bytes: 1_240_000, added: now.addingTimeInterval(-2 * 3600)),
            UploadedFile(id: "up-logo", name: "Shop logo", ext: "png", bytes: 284_000, added: now.addingTimeInterval(-8 * 3600)),
            UploadedFile(id: "up-stock", name: "Stock count", ext: "csv", bytes: 18_400, added: now.addingTimeInterval(-1 * day)),
            UploadedFile(id: "up-lease", name: "Lease summary", ext: "docx", bytes: 46_000, added: now.addingTimeInterval(-2 * day)),
            UploadedFile(id: "up-poster", name: "Opening day poster", ext: "jpg", bytes: 2_310_000, added: now.addingTimeInterval(-3 * day)),
            UploadedFile(id: "up-notes", name: "Meeting notes", ext: "md", bytes: 4_100, added: now.addingTimeInterval(-5 * day)),
            UploadedFile(id: "up-prices", name: "Price list", ext: "xlsx", bytes: 22_700, added: now.addingTimeInterval(-9 * day)),
            UploadedFile(id: "up-tour", name: "Shop tour", ext: "mov", bytes: 48_600_000, added: now.addingTimeInterval(-14 * day)),
        ]
    }
}
