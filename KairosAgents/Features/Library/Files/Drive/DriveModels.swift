import SwiftUI

// Plain data for the Google Drive area. Made-up sample content only.

nonisolated enum DriveKind: String, CaseIterable, Hashable, Sendable {
    case folder, doc, sheet, form, slides, pdf, image, text

    var label: String {
        switch self {
        case .folder: "Folder"
        case .doc: "Google Doc"
        case .sheet: "Google Sheet"
        case .form: "Google Form"
        case .slides: "Google Slides"
        case .pdf: "PDF"
        case .image: "Image"
        case .text: "Text file"
        }
    }

    var symbol: String {
        switch self {
        case .folder: "folder.fill"
        case .doc: "doc.text.fill"
        case .sheet: "tablecells.fill"
        case .form: "list.bullet.rectangle"
        case .slides: "rectangle.on.rectangle"
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .text: "doc.plaintext"
        }
    }

    var tint: Color {
        switch self {
        case .folder, .form, .slides: Palette.goldText
        case .doc, .image: Palette.working
        case .sheet: Palette.success
        case .pdf: Palette.danger
        case .text: Palette.inkDim
        }
    }

    /// Google's own kinds have no file size.
    var isGoogle: Bool { self == .doc || self == .sheet || self == .form || self == .slides }

    static func from(fileName: String) -> DriveKind {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "gif", "webp": .image
        case "pdf": .pdf
        default: .text
        }
    }
}

nonisolated enum DriveAccess: String, CaseIterable, Hashable, Sendable {
    case viewer, commenter, editor, owner

    var title: String {
        switch self {
        case .viewer: "Viewer"
        case .commenter: "Commenter"
        case .editor: "Editor"
        case .owner: "Owner"
        }
    }

    static let grantable: [DriveAccess] = [.viewer, .commenter, .editor]
}

nonisolated enum DriveAudience: String, CaseIterable, Hashable, Sendable {
    case person, group, domain, anyone

    var title: String {
        switch self {
        case .person: "Person"
        case .group: "Group"
        case .domain: "Domain"
        case .anyone: "Anyone with the link"
        }
    }
}

nonisolated struct DriveMember: Identifiable, Hashable, Sendable {
    var id = UUID().uuidString
    var audience: DriveAudience
    var address: String
    var access: DriveAccess

    var title: String {
        switch audience {
        case .anyone: "Anyone with the link"
        case .domain: "Anyone at \(address)"
        case .person, .group: address
        }
    }

    var letter: String {
        audience == .anyone ? "*" : String(address.prefix(1)).uppercased()
    }
}

nonisolated struct DriveSheetTab: Hashable, Sendable {
    var title: String
    var cells: [[String]]
}

nonisolated enum DriveQuestionType: String, CaseIterable, Hashable, Sendable {
    case short, paragraph, choice, checkboxes

    var title: String {
        switch self {
        case .short: "Short answer"
        case .paragraph: "Paragraph"
        case .choice: "Multiple choice"
        case .checkboxes: "Checkboxes"
        }
    }

    var needsChoices: Bool { self == .choice || self == .checkboxes }
}

nonisolated struct DriveQuestion: Identifiable, Hashable, Sendable {
    var id = UUID().uuidString
    var text: String
    var type: DriveQuestionType
    var choices: [String] = []
}

nonisolated struct DriveForm: Hashable, Sendable {
    var title: String
    var questions: [DriveQuestion] = []
    var published = false
    var responses: [String] = []
}

nonisolated struct DriveFile: Identifiable, Hashable, Sendable {
    var id: String
    var account: String
    var name: String
    var kind: DriveKind
    var size: Int64 = 0
    var modified: Date
    var starred = false
    var trashed = false
    var parent: String? = nil
    var sharedWithMe = false
    var members: [DriveMember] = []
    var revisions: [Date] = []
    var body: String = ""
    var sheets: [DriveSheetTab] = []
    var form: DriveForm? = nil

    var isFolder: Bool { kind == .folder }

    /// The short tag on rows: the file's extension, or the Google kind.
    var badge: String {
        switch kind {
        case .folder: return ""
        case .doc: return "Doc"
        case .sheet: return "Sheet"
        case .form: return "Form"
        case .slides: return "Slides"
        default:
            let ext = (name as NSString).pathExtension
            return ext.isEmpty ? kind.label : ext
        }
    }

    /// "2.4 MB · Nov 3" or "Google Sheet · Today".
    var meta: String {
        let first = (kind.isGoogle || kind == .folder || size == 0)
            ? kind.label
            : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "\(first) · \(DriveFormat.day(modified))"
    }
}

nonisolated struct DriveAccount: Identifiable, Hashable, Sendable {
    var id: String
    var email: String
    var usedGB: Double
    var totalGB: Double
    var broken = false
    var canSend = true

    var letter: String { String(email.prefix(1)).uppercased() }
    var storage: String { String(format: "%.1f GB used of %.0f GB", usedGB, totalGB) }
    var fraction: Double { totalGB > 0 ? min(1, usedGB / totalGB) : 0 }
}

nonisolated enum DriveSection: String, CaseIterable, Hashable, Sendable {
    case myDrive, shared, starred, recent, trash

    var title: String {
        switch self {
        case .myDrive: "My Drive"
        case .shared: "Shared with me"
        case .starred: "Starred"
        case .recent: "Recent"
        case .trash: "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .myDrive: "externaldrive"
        case .shared: "person.2"
        case .starred: "star"
        case .recent: "clock"
        case .trash: "trash"
        }
    }
}

nonisolated enum DriveFilter: String, CaseIterable, Hashable, Sendable {
    case all, folders, sheets, forms

    var title: String {
        switch self {
        case .all: "All files"
        case .folders: "Folders"
        case .sheets: "Sheets"
        case .forms: "Forms"
        }
    }

    func keeps(_ file: DriveFile) -> Bool {
        switch self {
        case .all: true
        case .folders: file.kind == .folder
        case .sheets: file.kind == .sheet
        case .forms: file.kind == .form
        }
    }
}

/// A block of cells, zero based.
nonisolated struct DriveCellRange: Equatable, Sendable {
    var top: Int
    var left: Int
    var rows: Int
    var columns: Int

    /// Reads "A1:F12". Returns nil when it is not a range.
    static func parse(_ text: String) -> DriveCellRange? {
        let parts = text.trimmingCharacters(in: .whitespaces).uppercased().split(separator: ":")
        guard parts.count == 2, let start = cell(parts[0]), let end = cell(parts[1]) else { return nil }
        return DriveCellRange(
            top: min(start.row, end.row),
            left: min(start.column, end.column),
            rows: abs(end.row - start.row) + 1,
            columns: abs(end.column - start.column) + 1
        )
    }

    private static func cell(_ text: Substring) -> (row: Int, column: Int)? {
        var letters: [UInt8] = []
        var digits = ""
        for character in text {
            if let ascii = character.asciiValue, ascii >= 65, ascii <= 90, digits.isEmpty {
                letters.append(ascii)
            } else if character.isNumber, character.isASCII {
                digits.append(character)
            } else {
                return nil
            }
        }
        guard !letters.isEmpty, letters.count <= 2, let row = Int(digits), row >= 1 else { return nil }
        var column = 0
        for ascii in letters { column = column * 26 + Int(ascii - 64) }
        return (row - 1, column - 1)
    }

    static func columnName(_ index: Int) -> String {
        var number = index + 1
        var name = ""
        while number > 0 {
            let rest = (number - 1) % 26
            name = String(Character(Unicode.Scalar(UInt8(65 + rest)))) + name
            number = (number - 1) / 26
        }
        return name
    }
}

nonisolated enum DriveFormat {
    /// "Today", "Yesterday", "Nov 3".
    static func day(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
