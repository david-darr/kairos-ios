import SwiftUI
import UIKit

// Pieces both kinds of chat share: formatted replies, requests answered inline, the queue,
// staged attachments and the find bar.

// MARK: - Formatted text

/// A reply's Markdown as native text: headings, lists, quotes, code and tables, with inline bold, italic,
/// code and links. Nothing is a web view.
struct MarkdownText: View {
    let text: String
    var streaming = false
    var size: CGFloat = 16.5

    nonisolated enum Block: Hashable, Sendable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case bullet(text: String, depth: Int, checked: Bool?)
        case numbered(mark: String, text: String)
        case code(language: String, text: String)
        case quote(String)
        case rule
    }

    var body: some View {
        let blocks = MarkdownText.parse(text)
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                view(for: block, last: offset == blocks.count - 1)
            }
            if blocks.isEmpty && streaming {
                Text("▍").font(KFont.ui(size)).foregroundStyle(Palette.goldText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: Block, last: Bool) -> some View {
        switch block {
        case .paragraph(let text):
            Text(MarkdownText.inline(text + (last && streaming ? " ▍" : "")))
                .font(KFont.ui(size))
                .lineSpacing(4)
                .foregroundStyle(Palette.ink)
                .tint(Palette.goldText)
                .textSelection(.enabled)
        case .heading(let level, let text):
            Text(MarkdownText.inline(text))
                .font(KFont.ui(level <= 1 ? size + 5 : (level == 2 ? size + 3 : size + 1), .semibold, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
        case .bullet(let text, let depth, let checked):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                if let checked {
                    Image(systemName: checked ? "checkmark.square" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(checked ? Palette.success : Palette.inkFaint)
                } else {
                    Circle().fill(Palette.goldText).frame(width: 5, height: 5).offset(y: -3)
                }
                Text(MarkdownText.inline(text))
                    .font(KFont.ui(size))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.goldText)
            }
            .padding(.leading, CGFloat(depth) * 16 + 2)
        case .numbered(let mark, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mark).font(KFont.ui(size, .medium)).foregroundStyle(Palette.goldText).monospacedDigit()
                Text(MarkdownText.inline(text))
                    .font(KFont.ui(size))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.goldText)
            }
        case .code(let language, let text):
            CodeBlock(language: language, text: text)
        case .quote(let text):
            HStack(spacing: 10) {
                Capsule().fill(Palette.gold.opacity(0.7)).frame(width: 3)
                Text(MarkdownText.inline(text))
                    .font(KFont.ui(size - 0.5))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.inkDim)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Palette.line.frame(height: 1).padding(.vertical, 3)
        }
    }

    nonisolated static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    nonisolated static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        var language = ""

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(language: language, text: lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix("#") {
                let hashes = line.prefix { $0 == "#" }.count
                let rest = line.dropFirst(hashes)
                if hashes <= 6, rest.hasPrefix(" ") {
                    flush()
                    blocks.append(.heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }
            if line == "---" || line == "***" || line == "___" {
                flush()
                blocks.append(.rule)
                continue
            }
            if line.hasPrefix("> ") || line == ">" {
                flush()
                blocks.append(.quote(String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flush()
                let indent = raw.prefix { $0 == " " || $0 == "\t" }.count
                var item = String(line.dropFirst(2))
                var checked: Bool?
                if item.hasPrefix("[ ] ") {
                    checked = false
                    item = String(item.dropFirst(4))
                } else if item.lowercased().hasPrefix("[x] ") {
                    checked = true
                    item = String(item.dropFirst(4))
                }
                blocks.append(.bullet(text: item, depth: min(3, indent / 2), checked: checked))
                continue
            }
            let digits = line.prefix { $0.isNumber }
            if !digits.isEmpty, digits.count <= 3 {
                let rest = line.dropFirst(digits.count)
                if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                    flush()
                    blocks.append(.numbered(mark: String(digits) + ".", text: String(rest.dropFirst(2))))
                    continue
                }
            }
            if line.hasPrefix("|") && line.hasSuffix("|") {
                // A table row: keep rows together as one fixed-width block, without the divider row.
                let cells = line.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 == "-" || $0 == ":" } }) { continue }
                flush()
                let row = cells.joined(separator: "   ")
                if case .code(let kind, let existing)? = blocks.last, kind == "table" {
                    blocks[blocks.count - 1] = .code(language: "table", text: existing + "\n" + row)
                } else {
                    blocks.append(.code(language: "table", text: row))
                }
                continue
            }
            paragraph.append(line)
        }
        if let lines = code { blocks.append(.code(language: language, text: lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}

/// A block of code with its language and a Copy button.
struct CodeBlock: View {
    let language: String
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if language != "table" {
                HStack {
                    Text(language.isEmpty ? "code" : language)
                        .font(KFont.ui(12, .medium, relativeTo: .caption))
                        .foregroundStyle(Palette.inkFaint)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = text
                        Haptics.success()
                        withAnimation(Motion.snappy) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.4))
                            withAnimation(Motion.snappy) { copied = false }
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(KFont.ui(12, .medium, relativeTo: .caption))
                            .foregroundStyle(Palette.inkDim)
                            .frame(minHeight: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Copy code")
                }
                .padding(.horizontal, 12)
            }
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 11)
                    .padding(.top, language == "table" ? 11 : 0)
            }
            .scrollIndicators(.hidden)
        }
        .kCard(radius: 14)
    }
}

// MARK: - Requests

/// An approval or a question from the model or a bot, answered right in the conversation.
struct RequestCard: View {
    let request: PendingRequest
    let onChoice: (PendingRequest.Choice) -> Void
    let onRespond: (_ answers: [String: QuestionAnswer], _ skip: Bool) -> Void

    @State private var answers: [String: QuestionAnswer] = [:]
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: request.kind == .question ? "questionmark.bubble" : "checkmark.shield")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.goldText)
                Text(request.title)
                    .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 6)
                if let expires = request.expiresAt {
                    Text("until \(expires.formatted(date: .omitted, time: .shortened))")
                        .font(KFont.ui(12, relativeTo: .caption))
                        .foregroundStyle(Palette.inkFaint)
                        .accessibilityLabel("Waits until \(expires.formatted(date: .omitted, time: .shortened))")
                }
            }

            if !request.detail.isEmpty {
                Text(request.detail)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let target = request.target, !target.isEmpty {
                Text(target)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(4)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if sent {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.success)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else if request.kind == .question {
                questions
            } else {
                choices
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 22, raised: true)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.gold.opacity(0.45), lineWidth: 1))
        .animation(Motion.bouncy, value: sent)
        .onChange(of: request.id) { sent = false; answers = [:] }
    }

    private var choices: some View {
        VStack(spacing: 8) {
            let allow = request.choices.filter(\.allows)
            let deny = request.choices.filter { !$0.allows }
            ForEach(Array(allow.enumerated()), id: \.element.id) { index, choice in
                choiceButton(choice, filled: index == 0)
            }
            ForEach(deny) { choice in
                choiceButton(choice, filled: false)
            }
        }
    }

    private func choiceButton(_ choice: PendingRequest.Choice, filled: Bool) -> some View {
        Button {
            Haptics.success()
            sent = true
            onChoice(choice)
        } label: {
            Text(choice.label)
                .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(filled ? Palette.onGold : (choice.allows ? Palette.ink : Palette.danger))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(filled ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.97))
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    if !question.header.isEmpty { Chip(text: question.header, filled: false) }
                    Text(question.text)
                        .font(KFont.ui(16, .medium))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(question.options, id: \.self) { option in
                        optionRow(question, option)
                    }
                    TextField(question.options.isEmpty ? "Your answer" : "Other: type your own answer", text: typed(question), axis: .vertical)
                        .font(KFont.ui(15.5))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Palette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("Your own answer to: \(question.text)")
                }
            }
            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    sent = true
                    onRespond([:], true)
                } label: {
                    Text("Skip")
                        .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Palette.ink.opacity(0.1), in: Capsule())
                }
                .buttonStyle(PressStyle(scale: 0.97))
                Button {
                    Haptics.success()
                    sent = true
                    onRespond(answers, false)
                } label: {
                    Text("Send answer")
                        .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.onGold)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Palette.gold, in: Capsule())
                        .opacity(complete ? 1 : 0.45)
                }
                .buttonStyle(PressStyle(scale: 0.97))
                .disabled(!complete)
            }
        }
    }

    /// Every question has an answer.
    private var complete: Bool {
        request.questions.allSatisfy { !(answers[$0.id]?.isEmpty ?? true) }
    }

    private func typed(_ question: PendingRequest.Question) -> Binding<String> {
        Binding(
            get: { answers[question.id]?.typed ?? "" },
            set: { answers[question.id, default: QuestionAnswer()].typed = $0 }
        )
    }

    private func optionRow(_ question: PendingRequest.Question, _ option: PendingRequest.Option) -> some View {
        let on = answers[question.id]?.picked.contains(option.label) ?? false
        return Button {
            Haptics.select()
            var answer = answers[question.id] ?? QuestionAnswer()
            if question.multiple {
                if on { answer.picked.remove(option.label) } else { answer.picked.insert(option.label) }
            } else {
                answer.picked = on ? [] : [option.label]
            }
            withAnimation(Motion.snappy) { answers[question.id] = answer }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: question.multiple ? (on ? "checkmark.square.fill" : "square") : (on ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 18))
                    .foregroundStyle(on ? Palette.goldText : Palette.inkFaint)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                    if !option.detail.isEmpty {
                        Text(option.detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(on ? Palette.gold.opacity(0.16) : Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - The queue

/// Messages typed while a reply runs, above the composer: edit one, remove one, send the next now.
struct QueueStrip: View {
    let items: [QueuedMessage]
    let paused: Bool
    /// "Send now": the first waiting message. nil hides the button.
    var sendNow: ((QueuedMessage) -> Void)?
    var sendNowTitle = "Send next now"
    let edit: (QueuedMessage) -> Void
    let remove: (QueuedMessage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(paused ? "Queue paused · \(items.count) waiting" : "Queued · sends when the reply finishes")
                    .font(KFont.ui(12.5, .medium, relativeTo: .caption))
                    .foregroundStyle(paused ? Palette.goldText : Palette.inkFaint)
                Spacer(minLength: 6)
                if let sendNow, let first = items.first {
                    Button { sendNow(first) } label: {
                        Text(sendNowTitle)
                            .font(KFont.ui(12.5, .semibold, relativeTo: .caption))
                            .foregroundStyle(Palette.goldText)
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.inkFaint)
                    Text(item.text.isEmpty ? "(attachment)" : item.text)
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button { edit(item) } label: {
                        Image(systemName: "pencil").font(.system(size: 14, weight: .medium)).frame(width: 38, height: 38).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Edit this queued message")
                    Button { remove(item) } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 38, height: 38).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Remove this queued message")
                }
                .foregroundStyle(Palette.inkDim)
                .buttonStyle(PressStyle())
                .padding(.leading, 12)
                .padding(.trailing, 2)
                .frame(minHeight: 44)
                .kCard(radius: 15)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .animation(Motion.snappy, value: items)
    }
}

// MARK: - Attachments

/// Files picked for the next message, inside the composer.
struct StagedStrip: View {
    let items: [StagedAttachment]
    let remove: (StagedAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        thumbnail(item)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.file.name)
                                .font(KFont.ui(13, .medium, relativeTo: .footnote))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text(item.phase == .uploading ? "Uploading" : (item.file.size.map(ChatFile.sizeText) ?? item.file.ext))
                                .font(KFont.ui(11.5, relativeTo: .caption2))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .frame(maxWidth: 120, alignment: .leading)
                        Button { remove(item) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.inkDim)
                                .frame(width: 30, height: 36)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Remove \(item.file.name)")
                    }
                    .padding(.leading, 6)
                    .frame(height: 46)
                    .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func thumbnail(_ item: StagedAttachment) -> some View {
        ZStack {
            if let data = item.file.local, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Palette.surface2
                Text(item.file.ext.isEmpty ? "FILE" : String(item.file.ext.prefix(4)))
                    .font(KFont.ui(9.5, .semibold, relativeTo: .caption2))
                    .foregroundStyle(Palette.inkDim)
            }
            if item.phase == .uploading {
                Color.black.opacity(0.35)
                ProgressView().controlSize(.small).tint(.white)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Files sent with one of the person's messages, as small tiles under the bubble.
struct SentFiles: View {
    let files: [ChatFile]
    let open: (ChatFile) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(files) { file in
                Button { open(file) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: file.kind == .image ? "photo" : "doc")
                            .font(.system(size: 12, weight: .medium))
                        Text(file.name).font(KFont.ui(12.5, relativeTo: .caption)).lineLimit(1)
                    }
                    .foregroundStyle(Palette.inkDim)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(Palette.ink.opacity(0.08), in: Capsule())
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Open \(file.name)")
            }
        }
        .frame(maxWidth: 310, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Find

/// Find in chat: a field, "n of m", previous and next.
struct FindBar: View {
    @Binding var query: String
    let position: Int
    let count: Int
    let previous: () -> Void
    let next: () -> Void
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.inkFaint)
            TextField("Find in chat", text: $query)
                .font(KFont.ui(15.5))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onSubmit(next)
            Text(query.isEmpty ? "" : (count == 0 ? "No matches" : "\(position) of \(count)"))
                .font(KFont.ui(12.5, relativeTo: .caption))
                .foregroundStyle(Palette.inkFaint)
                .monospacedDigit()
            Button(action: previous) { Image(systemName: "chevron.up").frame(width: 34, height: 40).contentShape(Rectangle()) }
                .disabled(count == 0)
                .accessibilityLabel("Previous match")
            Button(action: next) { Image(systemName: "chevron.down").frame(width: 34, height: 40).contentShape(Rectangle()) }
                .disabled(count == 0)
                .accessibilityLabel("Next match")
            Button(action: close) { Image(systemName: "xmark").frame(width: 34, height: 40).contentShape(Rectangle()) }
                .accessibilityLabel("Close find")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Palette.ink)
        .buttonStyle(PressStyle())
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 46)
        .kGlass(Capsule())
        .onAppear { focused = true }
    }
}
