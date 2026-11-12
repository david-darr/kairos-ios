import SwiftUI

/// One block of a rendered note.
nonisolated enum VaultBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(indent: Int, text: String)
    case numbered(indent: Int, number: String, text: String)
    case task(indent: Int, done: Bool, text: String, line: Int)
    case quote(String)
    case callout(kind: String, title: String, text: String)
    case code(String)
    case table([[String]])
    case embed(String)
    case rule
}

/// A small Markdown reader for vault notes: frontmatter, headings, lists, checkboxes, code,
/// tables, quotes, callouts, embeds and wikilinks.
nonisolated enum VaultMarkdown {
    static let scheme = "kvault"

    // MARK: Frontmatter

    static func frontmatter(_ body: String) -> [(key: String, value: String)] {
        let lines = body.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [] }
        var result: [(key: String, value: String)] = []
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !value.isEmpty { result.append((key, value)) }
        }
        return result
    }

    static func hasFrontmatter(_ body: String) -> Bool {
        body.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) == "---"
    }

    static func stripFrontmatter(_ body: String) -> String {
        frontmatterSplit(body).content
    }

    /// The frontmatter lines (with fences) and the rest, plus how many lines the frontmatter used.
    static func frontmatterSplit(_ body: String) -> (content: String, offset: Int) {
        let lines = body.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (body, 0) }
        if let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            return (lines[(end + 1)...].joined(separator: "\n"), end + 1)
        }
        return (body, 0)
    }

    // MARK: Links

    /// Every [[target]] in the text (aliases and headings removed), embeds included.
    static func linkTargets(_ text: String) -> [String] {
        var result: [String] = []
        var rest = Substring(text)
        while let open = rest.range(of: "[[") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "]]") else { break }
            let inner = after[..<close.lowerBound]
            let target = inner.split(separator: "|").first.map { $0.split(separator: "#").first.map(String.init) ?? "" } ?? ""
            let clean = target.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty { result.append(clean) }
            rest = after[close.upperBound...]
        }
        return result
    }

    static func noteURL(_ id: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "note"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }

    static func noteID(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
    }

    /// Turns wikilinks into Markdown links the app can open; unresolved ones become italic text.
    static func linkify(_ text: String, resolve: (String) -> String?) -> String {
        var output = ""
        var rest = Substring(text)
        while let open = rest.range(of: "[[") {
            output += rest[..<open.lowerBound]
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "]]") else {
                output += rest[open.lowerBound...]
                rest = ""
                break
            }
            let inner = String(after[..<close.lowerBound])
            let pieces = inner.split(separator: "|", maxSplits: 1).map(String.init)
            let targetPart = pieces.first ?? inner
            let heading = targetPart.split(separator: "#", maxSplits: 1).dropFirst().first.map(String.init)
            let target = targetPart.split(separator: "#").first.map(String.init) ?? targetPart
            let label = pieces.count > 1 ? pieces[1] : (heading.map { "\(target) > \($0)" } ?? target)
            if let id = resolve(target.trimmingCharacters(in: .whitespaces)), let url = noteURL(id) {
                output += "[\(label)](\(url.absoluteString))"
            } else {
                output += "*\(label)*"
            }
            rest = after[close.upperBound...]
        }
        output += rest
        return output
    }

    /// Inline Markdown (bold, italic, code, links) as styled text.
    static func inline(_ text: String, resolve: (String) -> String?) -> AttributedString {
        let source = linkify(text, resolve: resolve)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(text)
    }

    /// Plain text: Markdown marks and link brackets removed.
    static func plain(_ text: String) -> String {
        var result = text
        for mark in ["**", "__", "`", "[[", "]]", "# ", "> ", "- [ ] ", "- [x] "] {
            result = result.replacingOccurrences(of: mark, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let stopWords: Set<String> = ["the", "and", "for", "with", "this", "that", "from", "into", "are", "was", "but", "not", "you", "our", "has", "have", "will", "all", "its", "out", "one", "two", "see", "use"]

    static func keywords(_ text: String) -> Set<String> {
        let words = plain(text).lowercased().split { !$0.isLetter }.map(String.init)
        return Set(words.filter { $0.count > 3 && !stopWords.contains($0) })
    }

    // MARK: Blocks

    /// Parses note content (frontmatter already removed). Task lines report their line number in `body`,
    /// counting from `lineOffset`, so the reader can tick them.
    static func blocks(_ content: String, lineOffset: Int = 0, hideTitle: String? = nil) -> [VaultBlock] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [VaultBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indent = (raw.prefix { $0 == " " || $0 == "\t" }.count) / 2

            if line.isEmpty {
                flush()
                index += 1
                continue
            }
            if line.hasPrefix("```") {
                flush()
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                index += 1
                continue
            }
            if line.hasPrefix("#") {
                let level = line.prefix { $0 == "#" }.count
                let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                if level <= 6 && line.dropFirst(level).first == " " {
                    flush()
                    if !(level == 1 && blocks.isEmpty && text == hideTitle) {
                        blocks.append(.heading(level: level, text: text))
                    }
                    index += 1
                    continue
                }
            }
            if line == "---" || line == "***" {
                flush()
                blocks.append(.rule)
                index += 1
                continue
            }
            if line.hasPrefix("![[") && line.hasSuffix("]]") {
                flush()
                blocks.append(.embed(String(line.dropFirst(3).dropLast(2))))
                index += 1
                continue
            }
            if line.lowercased().hasPrefix("- [ ]") || line.lowercased().hasPrefix("- [x]") {
                flush()
                let done = line.lowercased().hasPrefix("- [x]")
                blocks.append(.task(indent: indent, done: done, text: line.dropFirst(5).trimmingCharacters(in: .whitespaces), line: index + lineOffset))
                index += 1
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flush()
                blocks.append(.bullet(indent: indent, text: String(line.dropFirst(2))))
                index += 1
                continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
               line[line.index(after: dot)...].hasPrefix(" ") {
                flush()
                blocks.append(.numbered(indent: indent, number: String(line[..<dot]), text: line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }
            if line.hasPrefix(">") {
                flush()
                var quoted: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoted.append(lines[index].trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                if let first = quoted.first, first.hasPrefix("[!"), let end = first.firstIndex(of: "]") {
                    let kind = String(first[first.index(first.startIndex, offsetBy: 2)..<end]).lowercased()
                    let title = first[first.index(after: end)...].trimmingCharacters(in: .whitespaces)
                    blocks.append(.callout(kind: kind, title: title.isEmpty ? kind.capitalized : title, text: quoted.dropFirst().joined(separator: " ")))
                } else {
                    blocks.append(.quote(quoted.joined(separator: " ")))
                }
                continue
            }
            if line.hasPrefix("|") {
                flush()
                var rows: [[String]] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let cells = lines[index].trimmingCharacters(in: .whitespaces)
                        .split(separator: "|", omittingEmptySubsequences: false)
                        .dropFirst().dropLast()
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    let isRule = cells.allSatisfy { cell in !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" } }
                    if !isRule { rows.append(cells) }
                    index += 1
                }
                if !rows.isEmpty { blocks.append(.table(rows)) }
                continue
            }
            paragraph.append(line)
            index += 1
        }
        flush()
        return blocks
    }

    /// Ticks or unticks the checkbox on one line of the full note body.
    static func toggleTask(in body: String, line: Int) -> String {
        var lines = body.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return body }
        let current = lines[line]
        if let range = current.range(of: "[ ]") {
            lines[line] = current.replacingCharacters(in: range, with: "[x]")
        } else if let range = current.range(of: "[x]") ?? current.range(of: "[X]") {
            lines[line] = current.replacingCharacters(in: range, with: "[ ]")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Rendering

/// A note's Markdown drawn with the Kairos type. Wikilinks open notes; checkboxes can be ticked.
struct VaultMarkdownView: View {
    let blocks: [VaultBlock]
    var store: VaultStore = .shared
    var onOpen: (String) -> Void = { _ in }
    var onToggle: ((Int) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Palette.goldText)
        .environment(\.openURL, OpenURLAction { url in
            if let id = VaultMarkdown.noteID(from: url) {
                Haptics.tap()
                onOpen(id)
                return .handled
            }
            return .systemAction
        })
    }

    private func text(_ source: String) -> Text {
        Text(VaultMarkdown.inline(source) { store.resolve($0)?.id })
    }

    @ViewBuilder
    private func blockView(_ block: VaultBlock) -> some View {
        switch block {
        case .heading(let level, let value):
            text(value)
                .font(level == 1 ? KFont.display(30) : KFont.ui(level == 2 ? 21 : 18, .semibold, relativeTo: level == 2 ? .title3 : .headline))
                .foregroundStyle(Palette.ink)
                .padding(.top, level <= 2 ? 10 : 4)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let value):
            text(value)
                .font(KFont.ui(16.5))
                .foregroundStyle(Palette.ink.opacity(0.92))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let indent, let value):
            listRow(indent: indent, marker: Text("•").foregroundStyle(Palette.goldText), value: value)
        case .numbered(let indent, let number, let value):
            listRow(indent: indent, marker: Text("\(number).").foregroundStyle(Palette.goldText), value: value)
        case .task(let indent, let done, let value, let line):
            taskRow(indent: indent, done: done, value: value, line: line)
        case .quote(let value):
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(Palette.gold.opacity(0.6)).frame(width: 3)
                text(value).font(KFont.ui(16.5)).italic().foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .callout(let kind, let title, let value):
            callout(kind: kind, title: title, value: value)
        case .code(let value):
            ScrollView(.horizontal) {
                Text(value)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .padding(14)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        case .table(let rows):
            VaultTableView(rows: rows, store: store)
        case .embed(let target):
            embed(target)
        case .rule:
            Palette.line.frame(height: 1).padding(.vertical, 6)
        }
    }

    private func listRow(indent: Int, marker: Text, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            marker.font(KFont.ui(16.5, .semibold)).frame(minWidth: 14, alignment: .leading)
            text(value).font(KFont.ui(16.5)).foregroundStyle(Palette.ink.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(indent) * 18)
    }

    private func taskRow(indent: Int, done: Bool, value: String, line: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Haptics.select()
                onToggle?(line)
            } label: {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(done ? Palette.goldText : Palette.inkFaint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(onToggle == nil)
            .accessibilityLabel(done ? "Done: \(VaultMarkdown.plain(value))" : "To do: \(VaultMarkdown.plain(value))")
            text(value)
                .font(KFont.ui(16.5))
                .strikethrough(done, color: Palette.inkFaint)
                .foregroundStyle(done ? Palette.inkFaint : Palette.ink.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.leading, CGFloat(indent) * 18)
    }

    private func callout(kind: String, title: String, value: String) -> some View {
        let tint: Color = switch kind {
        case "warning", "caution", "danger": Palette.danger
        case "tip", "success", "done": Palette.success
        case "info", "todo": Palette.working
        default: Palette.goldText
        }
        let symbol = switch kind {
        case "warning", "caution", "danger": "exclamationmark.triangle"
        case "tip", "success", "done": "checkmark.circle"
        case "info", "todo": "info.circle"
        default: "pencil"
        }
        return VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                .foregroundStyle(tint)
            if !value.isEmpty {
                text(value).font(KFont.ui(16)).foregroundStyle(Palette.ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, style: .continuous)
                .fill(tint)
                .frame(width: 4)
        }
    }

    @ViewBuilder
    private func embed(_ target: String) -> some View {
        if let note = store.resolve(target) {
            Button {
                Haptics.tap()
                onOpen(note.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 38, height: 38)
                        .background(Palette.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                        Text(note.folder.isEmpty ? "Vault" : note.folder).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                }
                .padding(12)
                .kCard(radius: 16, raised: true)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .accessibilityLabel("Embedded note \(note.title). Open")
        } else {
            HStack(spacing: 10) {
                Image(systemName: "paperclip").foregroundStyle(Palette.inkFaint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Attachment").font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    Text(target).font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .kCard(radius: 16)
        }
    }
}

/// A Markdown table that scrolls sideways when it is wide.
struct VaultTableView: View {
    let rows: [[String]]
    let store: VaultStore

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(VaultMarkdown.inline(cell) { store.resolve($0)?.id })
                                .font(KFont.ui(15, rowIndex == 0 ? .semibold : .regular, relativeTo: .subheadline))
                                .foregroundStyle(rowIndex == 0 ? Palette.ink : Palette.ink.opacity(0.88))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .frame(minWidth: 84, alignment: .leading)
                        }
                    }
                    .background(rowIndex == 0 ? Palette.ink.opacity(0.07) : Color.clear)
                    if rowIndex < rows.count - 1 {
                        Palette.line.frame(height: 1).gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .kCard(radius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
