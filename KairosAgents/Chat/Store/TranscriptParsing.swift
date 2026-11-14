import Foundation

/// Turns what the desktop saved into what the phone shows: a reply's text with its files and sources
/// taken out as cards, plain failure lines, and requests the person can answer.
nonisolated enum TranscriptParsing {

    // MARK: A reply's body

    nonisolated struct Body: Hashable, Sendable {
        var text: String
        var files: [ChatFile]
        var sources: [SourceLink]
        /// Designs the reply links, each drawn as a card.
        var designs: [ChatThumbRef] = []
    }

    /// `[Design: title](/designs/<12 hex>)`, the link a chat writes for a design (the desktop's `DESIGN_URL`).
    private static let designLink = try? NSRegularExpression(
        pattern: #"\[([^\]]*)\]\(/designs/([a-f0-9]{12})\)"#)
    private static let fileLink = try? NSRegularExpression(
        pattern: #"!?\[([^\]]*)\]\((/(?:generated-files|generated-images|chat-files)/[^)\s]+)\)"#)
    private static let bareLink = try? NSRegularExpression(
        pattern: #"(?<![\w(/])/(?:generated-files|generated-images)/[^\s)\]>"']+"#)
    private static let webLink = try? NSRegularExpression(
        pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#)
    private static let goalBlock = try? NSRegularExpression(
        pattern: #"<kairos-goal>[\s\S]*?(</kairos-goal>|$)"#)

    /// Fenced blocks and backtick spans.
    private static let codeSpan = try? NSRegularExpression(pattern: #"(?s)```.*?(?:```|\z)|`[^`\n]+`"#)

    private static func codeRanges(in text: String) -> [NSRange] {
        guard let codeSpan else { return [] }
        return codeSpan.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
    }

    /// Nothing but blanks around the match on its line.
    private static func onItsOwnLine(_ range: NSRange, in text: NSString) -> Bool {
        var before = range.location
        while before > 0 {
            let c = text.character(at: before - 1)
            if c == 10 || c == 13 { break }
            guard let scalar = Unicode.Scalar(c), CharacterSet.whitespaces.contains(scalar) else { return false }
            before -= 1
        }
        var after = range.location + range.length
        while after < text.length {
            let c = text.character(at: after)
            if c == 10 || c == 13 { break }
            guard let scalar = Unicode.Scalar(c), CharacterSet.whitespaces.contains(scalar) else { return false }
            after += 1
        }
        return true
    }

    /// Split a saved or streaming reply into its words, the files it links and its sources.
    /// `takeDesigns` also lifts `[Design: title](/designs/id)` links out of the text as `designs`, for the places that
    /// draw a card in their place. It is off by default, so a link stays in the text exactly as written (Forge, previews).
    static func body(_ raw: String, takeDesigns: Bool = false) -> Body {
        var text = raw
        if let goalBlock {
            text = goalBlock.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        var files: [ChatFile] = []
        var seen = Set<String>()

        if let fileLink {
            let matches = fileLink.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard let labelRange = Range(match.range(at: 1), in: text), let urlRange = Range(match.range(at: 2), in: text) else { continue }
                let url = String(text[urlRange])
                guard seen.insert(url).inserted else { continue }
                files.append(file(url: url, label: String(text[labelRange])))
            }
            text = fileLink.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        if let bareLink {
            let matches = bareLink.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                let url = String(text[range])
                guard seen.insert(url).inserted else { continue }
                files.append(file(url: url, label: ""))
            }
        }

        // Only where a card is drawn in the link's place (saved replies of a chat). Everywhere else, and for the reply
        // being streamed, the text is left exactly as written and no extra work is done.
        var designs: [ChatThumbRef] = []
        if takeDesigns, let designLink {
            let ns = text as NSString
            let matches = designLink.matches(in: text, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                let code = codeRanges(in: text)
                var seenDesigns = Set<String>()
                var edits: [(range: NSRange, with: String)] = []
                for match in matches {
                    // A link shown inside a code block or a backtick span is not a link.
                    if code.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
                    let title = ChatThumbWire.linkTitle(ns.substring(with: match.range(at: 1)))
                    let id = ns.substring(with: match.range(at: 2))
                    if seenDesigns.insert(id).inserted { designs.append(ChatThumbRef(id: id, title: title)) }
                    // On its own line the card replaces it; inside a sentence the title stays so the sentence reads whole.
                    edits.append((match.range, onItsOwnLine(match.range, in: ns) ? "" : title))
                }
                if !edits.isEmpty {
                    let changed = NSMutableString(string: text)
                    for edit in edits.reversed() { changed.replaceCharacters(in: edit.range, with: edit.with) }
                    text = changed as String
                }
            }
        }

        var sources: [SourceLink] = []
        var kept: [String] = []
        for paragraph in text.components(separatedBy: "\n\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if sources.isEmpty, lower.hasPrefix("sources:") || lower.hasPrefix("**sources:**") || lower.hasPrefix("**sources**") {
                sources = links(in: trimmed)
                if !sources.isEmpty { continue }
            }
            if !trimmed.isEmpty { kept.append(paragraph.trimmingCharacters(in: .newlines)) }
        }
        return Body(text: kept.joined(separator: "\n\n"), files: files, sources: Array(sources.prefix(6)), designs: designs)
    }

    static func file(url: String, label: String) -> ChatFile {
        let last = url.split(separator: "/").last.map(String.init) ?? url
        var name = ChatFile.cleanName(last)
        // A chat file's link is only an id; the label carries its name.
        if url.hasPrefix("/chat-files/"), !label.isEmpty { name = label }
        return ChatFile(id: url, name: name, kind: ChatFile.kind(forName: name))
    }

    static func links(in text: String) -> [SourceLink] {
        guard let webLink else { return [] }
        var result: [SourceLink] = []
        for match in webLink.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let titleRange = Range(match.range(at: 1), in: text), let urlRange = Range(match.range(at: 2), in: text) else { continue }
            let url = String(text[urlRange])
            let site = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
            if !result.contains(where: { $0.url == url }) {
                result.append(SourceLink(site: site, title: String(text[titleRange]), url: url))
            }
        }
        return result
    }

    // MARK: Saved messages

    /// A model chat's saved messages as transcript entries.
    static func entries(_ messages: [ChatMessageDTO], modelName: String) -> [TranscriptEntry] {
        var result: [TranscriptEntry] = []
        for (index, message) in messages.enumerated() {
            let time = message.ts.map { Date(timeIntervalSince1970: $0) }
            let content = message.content ?? ""
            if message.role == "user" {
                var entry = TranscriptEntry(id: "m\(index)", role: .user, text: content, time: time)
                entry.index = index
                entry.files = (message.attachments ?? []).map { attachment in
                    let name = attachment.filename ?? "File"
                    return ChatFile(id: attachment.url ?? "attachment-\(attachment.id ?? name)", name: name,
                                    kind: ChatFile.kind(forName: name), size: attachment.size.map { Int($0) })
                }
                if content.isEmpty && entry.files.isEmpty { entry.text = "(attachment)" }
                result.append(entry)
                continue
            }
            let parsed = body(content, takeDesigns: true)
            var entry = TranscriptEntry(id: "m\(index)", role: .assistant, text: parsed.text, time: time)
            entry.index = index
            entry.files = parsed.files
            entry.sources = parsed.sources
            entry.designs = parsed.designs
            if let followup = message.backgroundFollowup, !followup.isNull, followup.bool != false {
                entry.caption = "After background work"
            }
            switch message.status ?? "complete" {
            case "failed":
                entry.failure = failureLine(kind: message.failureKind, model: message.failureModelName ?? modelName, partial: !content.isEmpty)
            case "stopped":
                entry.failure = content.isEmpty ? "Stopped before a response started." : "Stopped. The partial reply was saved."
            case "interrupted":
                entry.failure = content.isEmpty ? "The response was interrupted." : "The response was interrupted. The partial reply was saved."
            default:
                if content.isEmpty && parsed.files.isEmpty && parsed.designs.isEmpty { entry.failure = "No text response was returned." }
            }
            result.append(entry)
        }
        return result
    }

    static func failureLine(kind: String?, model: String, partial: Bool) -> String {
        let name = model.isEmpty ? "The model" : model
        let saved = partial ? " The partial reply was saved." : ""
        switch kind {
        case "rate_limited":
            return "\(name) is rate limited. Wait a little, or pick another model and send again.\(saved)"
        case "request_error":
            return "The message could not be completed. Check its attachments before sending again."
        default:
            return "\(name) failed. Check its connection, or pick another model.\(saved)"
        }
    }

    // MARK: Runs and requests

    static func request(_ dto: ChatPermissionDTO?) -> PendingRequest? {
        guard let dto, let id = dto.id, !id.isEmpty else { return nil }
        let expires = dto.expiresAt.map { Date(timeIntervalSince1970: $0) }
        if dto.kind == "question" {
            let questions = (dto.questions ?? []).compactMap { question -> PendingRequest.Question? in
                guard let text = question.question, !text.isEmpty else { return nil }
                return PendingRequest.Question(
                    id: text, text: text, header: question.header ?? "", multiple: question.multiSelect ?? false,
                    options: (question.options ?? []).compactMap { option -> PendingRequest.Option? in
                        guard let label = option.label, !label.isEmpty else { return nil }
                        return PendingRequest.Option(label: label, detail: option.description ?? "")
                    })
            }
            return PendingRequest(id: id, kind: .question, channel: .permission, title: "Waiting for your answer",
                                  detail: "", target: nil, questions: questions, expiresAt: expires)
        }
        let choices = (dto.choices ?? []).compactMap { choice -> PendingRequest.Choice? in
            guard let choiceID = choice.id, !choiceID.isEmpty else { return nil }
            return PendingRequest.Choice(id: choiceID, label: choice.label ?? choiceID.capitalized,
                                         allows: choice.behavior == "allow", scope: choice.scope ?? "once")
        }
        return PendingRequest(id: id, kind: .approval, channel: .permission, title: dto.title ?? "Allow this?",
                              detail: dto.description ?? "", target: dto.target, choices: choices, expiresAt: expires)
    }

    static func run(_ dto: ChatRunDTO) -> RunState? {
        guard let turnID = dto.turnId, !turnID.isEmpty else { return nil }
        var run = RunState(turnID: turnID)
        run.title = dto.sessionTitle ?? ""
        run.prompt = dto.prompt ?? ""
        run.text = dto.text ?? ""
        run.status = RunState.Status(rawValue: dto.status ?? "processing") ?? .processing
        run.stopping = dto.stopping ?? false
        run.request = request(dto.permission)
        run.error = dto.error
        run.startedAt = dto.startedAt.map { Date(timeIntervalSince1970: $0) }
        run.provider = dto.provider ?? ""
        run.providerDetail = dto.providerDetail
        run.revision = dto.revision ?? 0
        for step in dto.toolSteps ?? [] {
            apply(step: step, to: &run.steps)
        }
        return run
    }

    /// A "started" step adds a line; its "finished" twin ticks the same line.
    static func apply(step: ChatToolStepDTO, to steps: inout [StepLine]) {
        let id = step.id ?? "step-\(steps.count)"
        let finished = step.phase == "finished"
        apply(id: id, text: stepText(name: step.name, summary: step.summary), finished: finished, failed: finished && step.ok == false, to: &steps)
    }

    static func apply(id: String, text: String, finished: Bool, failed: Bool, to steps: inout [StepLine]) {
        if let index = steps.firstIndex(where: { $0.id == id }) {
            steps[index].done = finished || steps[index].done
            steps[index].failed = failed
            if steps[index].text.isEmpty { steps[index].text = text }
        } else {
            steps.append(StepLine(id: id, text: text, done: finished, failed: failed))
        }
    }

    /// The step's own summary when it has one, else the tool's name in plain words.
    static func stepText(name: String?, summary: String?) -> String {
        if let summary, !summary.trimmingCharacters(in: .whitespaces).isEmpty { return ChatFormat.oneLine(summary) }
        let raw = (name ?? "tool").replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "mcp  ", with: "")
        return "Using " + raw
    }

    static func change(_ dto: ChatRunChangesDTO) -> RunChange {
        var change = RunChange()
        change.status = dto.status.flatMap { RunState.Status(rawValue: $0) }
        change.stopping = dto.stopping
        change.requestChanged = dto.hasPermission
        change.request = request(dto.permission)
        change.errorChanged = dto.hasError
        change.error = dto.error
        change.providerDetailChanged = dto.hasProviderDetail
        change.providerDetail = dto.providerDetail
        return change
    }

    static func background(_ dto: ChatBackgroundItemDTO) -> BackgroundItem {
        BackgroundItem(
            id: dto.id, kind: dto.kind ?? "task", label: dto.label ?? "Background work", status: dto.status ?? "running",
            activity: dto.activity ?? "",
            startedAt: dto.startedAt.map { Date(timeIntervalSince1970: $0) },
            endedAt: dto.endedAt.map { Date(timeIntervalSince1970: $0) })
    }

    // MARK: Bot conversations

    static func botEntries(_ messages: [BotMessageDTO], botName: String) -> [BotEntry] {
        var result: [BotEntry] = []
        for message in messages {
            let time = message.ts.map { Date(timeIntervalSince1970: $0) }
            let content = (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let files = (message.attachments ?? []).map { attachment -> ChatFile in
                let name = attachment.filename ?? "File"
                return ChatFile(id: attachment.url ?? "attachment-\(attachment.id ?? name)", name: name, kind: ChatFile.kind(forName: name))
            }
            let kind = message.kind ?? ""
            if message.callSummaryId != nil {
                result.append(BotEntry(id: message.id, kind: .card(title: "Call summary"), text: content, time: time))
                continue
            }
            switch kind {
            case "":
                break
            case "stopped":
                result.append(BotEntry(id: message.id, kind: .note, text: content.isEmpty ? "Stopped" : content, time: time))
                continue
            case "compaction":
                result.append(BotEntry(id: message.id, kind: .note, text: "Earlier messages were summarised", time: time))
                continue
            case "handoff":
                let text = message.note ?? content
                result.append(BotEntry(id: message.id, kind: .note, text: text.isEmpty ? "Handed to a teammate" : ChatFormat.oneLine(text), time: time))
                continue
            case "fd_card":
                let title = frontDeskTitle(message.fdKind)
                let text = content.isEmpty ? (message.fdData?["text"]?.string ?? message.fdData?["title"]?.string ?? "") : content
                if !text.isEmpty { result.append(BotEntry(id: message.id, kind: .card(title: title), text: text, time: time)) }
                continue
            case "bot_created":
                let name = message.botCreated?["name"]?.string ?? "A new bot"
                result.append(BotEntry(id: message.id, kind: .card(title: "New bot"), text: content.isEmpty ? "\(name) was made. Open Bots to see it." : content, time: time))
                continue
            default:
                if !content.isEmpty {
                    result.append(BotEntry(id: message.id, kind: .card(title: kind.replacingOccurrences(of: "_", with: " ").capitalized), text: content, time: time))
                }
                continue
            }
            if message.displayOnly == true {
                if !content.isEmpty { result.append(BotEntry(id: message.id, kind: .note, text: ChatFormat.oneLine(content), time: time)) }
                continue
            }
            let mine = message.role == "user"
            if mine {
                guard !content.isEmpty || !files.isEmpty else { continue }
                result.append(BotEntry(id: message.id, kind: .mine, text: content, time: time, files: files))
            } else {
                let parsed = body(content, takeDesigns: true)
                let failed = message.status == "failed"
                var text = parsed.text
                if failed && text.isEmpty {
                    text = failureLine(kind: message.failureKind, model: message.failureModelName ?? botName, partial: false)
                }
                guard !text.isEmpty || !parsed.files.isEmpty || !parsed.designs.isEmpty else { continue }
                result.append(BotEntry(id: message.id, kind: .theirs, text: text, time: time, files: parsed.files, failed: failed,
                                       designs: parsed.designs))
            }
        }
        return result
    }

    static func frontDeskTitle(_ kind: String?) -> String {
        switch kind {
        case "brief": return "Morning brief"
        case "prep": return "Prep"
        case "reminder": return "Reminder"
        case "task_link": return "Task"
        case "suggestion": return "Suggestion"
        case "checkin": return "Check-in"
        case "welcome": return "Welcome"
        case "reach": return "Reach me"
        case "watching": return "Watching"
        default: return "From the front desk"
        }
    }

    static func queued(_ items: [BotQueueItemDTO]?) -> [QueuedMessage] {
        (items ?? []).filter { $0.state != "cancelled" }.map {
            QueuedMessage(id: $0.id, text: $0.text ?? "", state: $0.state ?? "pending")
        }
    }

    /// A bot's card as something the person can answer inline.
    static func request(card: BotCardDTO) -> PendingRequest? {
        let expires = card.expiresAt.map { Date(timeIntervalSince1970: $0) }
        let channel = PendingRequest.Channel.botCard(revision: card.revision ?? 0)
        let title = card.title ?? "Waiting for you"
        let detail = card.details?.summary ?? ""
        switch card.kind {
        case "question":
            let questions = (card.questions ?? []).compactMap { question -> PendingRequest.Question? in
                guard let id = question.id ?? question.question, let text = question.question else { return nil }
                return PendingRequest.Question(
                    id: id, text: text, header: question.header ?? "", multiple: question.multiSelect ?? false,
                    options: (question.options ?? []).compactMap { option -> PendingRequest.Option? in
                        guard let label = option.label else { return nil }
                        return PendingRequest.Option(label: label, detail: option.description ?? "")
                    })
            }
            return PendingRequest(id: card.id, kind: .question, channel: channel, title: title, detail: detail,
                                  target: nil, questions: questions, expiresAt: expires)
        case "approval":
            let choices = (card.choices ?? []).compactMap { choice -> PendingRequest.Choice? in
                guard let id = choice.id else { return nil }
                return PendingRequest.Choice(id: id, label: choice.label ?? id.capitalized, allows: choice.behavior == "allow", scope: choice.scope ?? "once")
            }
            return PendingRequest(id: card.id, kind: .approval, channel: channel, title: title, detail: detail,
                                  target: card.details?.target, choices: choices, expiresAt: expires)
        default:
            // A sign-in, a connector or a computer step: it is finished on the desktop, then marked here.
            let choices = [
                PendingRequest.Choice(id: "resume:done", label: "Done", allows: true),
                PendingRequest.Choice(id: "resume:skipped", label: "Skip", allows: false),
            ]
            let hint = detail.isEmpty ? "Finish this step on your desktop, then mark it done." : detail
            return PendingRequest(id: card.id, kind: .approval, channel: channel, title: title, detail: hint,
                                  target: card.details?.target, choices: choices, expiresAt: expires)
        }
    }
}
