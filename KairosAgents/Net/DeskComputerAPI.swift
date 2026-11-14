import Foundation
import CoreGraphics

// The desktop's computer routes (routes/computer_routes.py over core/computer.py and
// core/computer_trajectory.py), as the phone WATCHES a computer. The phone never steers one.
//
// - GET /api/computer lists the running computers the account may see: a chat's computer to its owner or an
//   admin, a bot's computer to admins only. Each row carries `lease_id` and the last recorded `steps`: neither is
//   ever decoded here (the first is a control token; the second can hold what a person typed while recording).
// - GET /api/computer/{owner}/frames is a server-sent stream: `event: frame` with a JSON state and, when the
//   picture changed, `image` (a base64 JPEG), then `event: closed` when the computer stops. 404 when closed.
// - GET /api/computer/{owner}/last answers the last picture a closed computer kept, for a short while.
// - POST /api/computer/{owner}/stop closes the computer. It takes no request id, so it is sent once.
// - GET /api/computer/{owner}/steps lists the runs kept for a computer; GET /api/computer/steps/{run} reads one
//   run's steps; GET /api/computer/steps/{run}/{number}/{name} is one kept picture (before, after, marker).
//   Step text is what the desktop recorded: typed text appears as typed, except a private field ("(private field)").
// - The phone never calls: takeover, handback, input, record start and stop, local-apps revoke, the steps zip
//   export or the steps skill route. There is no function here for any of them.

// MARK: - Plain lists

/// A JSON list of text read item by item: one odd item is skipped, never the whole list.
nonisolated struct DeskComputerNames: Decodable, Hashable, Sendable {
    var items: [String] = []

    init(from decoder: Decoder) throws {
        var list = try decoder.unkeyedContainer()
        while !list.isAtEnd {
            if let text = try? list.decode(String.self) {
                items.append(text)
            } else {
                _ = try list.decode(JSONValue.self)
            }
        }
    }
}

// MARK: - Running computers and frames

/// One row of GET /api/computer. `lease_id` and `steps` are left out on purpose.
nonisolated struct DeskComputerRunningDTO: Decodable, Hashable, Sendable {
    /// "chat:<id>" or "agent:<id>".
    var owner: String
    /// The page address. Shown without its query.
    var url: String?
    var title: String?
    /// Epoch seconds.
    var lastAction: Double?
    var takenOver: Bool?
    var waitingModel: Bool?
    var desktop: Bool?
    var recording: Bool?
    var startedAt: Double?

    private enum CodingKeys: String, CodingKey {
        case owner, url, title, lastAction, takenOver, waitingModel, desktop, recording, startedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decode(String.self, forKey: .owner)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        lastAction = try? container.decodeIfPresent(Double.self, forKey: .lastAction)
        takenOver = try? container.decodeIfPresent(Bool.self, forKey: .takenOver)
        waitingModel = try? container.decodeIfPresent(Bool.self, forKey: .waitingModel)
        desktop = try? container.decodeIfPresent(Bool.self, forKey: .desktop)
        recording = try? container.decodeIfPresent(Bool.self, forKey: .recording)
        startedAt = try? container.decodeIfPresent(Double.self, forKey: .startedAt)
    }
}

/// One `frame` event of the stream, or the answer of /last (which adds `closed_at`). `image` is a base64 JPEG
/// and is missing when the picture has not changed since the last event.
nonisolated struct DeskComputerFrameDTO: Decodable, Sendable {
    var owner: String?
    var url: String?
    var title: String?
    var lastAction: Double?
    var desktop: Bool?
    var recording: Bool?
    var takenOver: Bool?
    var waitingModel: Bool?
    var image: String?
    var closedAt: Double?

    private enum CodingKeys: String, CodingKey {
        case owner, url, title, lastAction, desktop, recording, takenOver, waitingModel, image, closedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try? container.decodeIfPresent(String.self, forKey: .owner)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        lastAction = try? container.decodeIfPresent(Double.self, forKey: .lastAction)
        desktop = try? container.decodeIfPresent(Bool.self, forKey: .desktop)
        recording = try? container.decodeIfPresent(Bool.self, forKey: .recording)
        takenOver = try? container.decodeIfPresent(Bool.self, forKey: .takenOver)
        waitingModel = try? container.decodeIfPresent(Bool.self, forKey: .waitingModel)
        image = try? container.decodeIfPresent(String.self, forKey: .image)
        closedAt = try? container.decodeIfPresent(Double.self, forKey: .closedAt)
    }
}

// MARK: - Steps

/// One row of GET /api/computer/{owner}/steps (the run's meta.json). The byte count and owner are left out.
nonisolated struct DeskComputerRunDTO: Decodable, Hashable, Sendable {
    var runId: String
    var started: Double?
    var updated: Double?
    var steps: Int?

    private enum CodingKeys: String, CodingKey { case runId, started, updated, steps }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runId = try container.decode(String.self, forKey: .runId)
        started = try? container.decodeIfPresent(Double.self, forKey: .started)
        updated = try? container.decodeIfPresent(Double.self, forKey: .updated)
        steps = try? container.decodeIfPresent(Int.self, forKey: .steps)
    }
}

nonisolated struct DeskComputerPointDTO: Decodable, Hashable, Sendable {
    var x: Double?
    var y: Double?

    private enum CodingKeys: String, CodingKey { case x, y }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try? container.decodeIfPresent(Double.self, forKey: .x)
        y = try? container.decodeIfPresent(Double.self, forKey: .y)
    }
}

/// One step's action.json plus the kept picture names and the reasons the others were not kept
/// (core/computer_trajectory.py: steps). The element and the page state are left out.
nonisolated struct DeskComputerStepDTO: Decodable, Sendable {
    var step: Int
    var action: String?
    var arguments: JSONValue?
    var point: DeskComputerPointDTO?
    var result: String?
    var ok: Bool?
    var url: String?
    var time: Double?
    var images: DeskComputerNames?
    /// evidence.not_kept: a picture name and why it was not kept.
    var notKept: [String: String]?

    private enum CodingKeys: String, CodingKey { case step, action, arguments, point, result, ok, url, time, images, evidence }
    private enum EvidenceKeys: String, CodingKey { case notKept }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step = try container.decode(Int.self, forKey: .step)
        action = try? container.decodeIfPresent(String.self, forKey: .action)
        arguments = try? container.decodeIfPresent(JSONValue.self, forKey: .arguments)
        point = try? container.decodeIfPresent(DeskComputerPointDTO.self, forKey: .point)
        result = try? container.decodeIfPresent(String.self, forKey: .result)
        ok = try? container.decodeIfPresent(Bool.self, forKey: .ok)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        time = try? container.decodeIfPresent(Double.self, forKey: .time)
        images = try? container.decodeIfPresent(DeskComputerNames.self, forKey: .images)
        if let evidence = try? container.nestedContainer(keyedBy: EvidenceKeys.self, forKey: .evidence),
           let reasons = try? evidence.decodeIfPresent([String: JSONValue].self, forKey: .notKept) {
            var found: [String: String] = [:]
            for (name, reason) in reasons { if let text = reason.string { found[name] = text } }
            notKept = found
        }
    }
}

/// GET /api/computer/steps/{run}: the run's meta with its steps.
nonisolated struct DeskComputerStepsDTO: Decodable, Sendable {
    var runId: String?
    var steps: DeskForgeList<DeskComputerStepDTO>?
    /// How many days the desktop keeps steps.
    var days: Int?
    /// A bot's computer: the bot's name.
    var agentName: String?

    private enum CodingKeys: String, CodingKey { case runId, steps, days, agentName }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runId = try? container.decodeIfPresent(String.self, forKey: .runId)
        steps = try? container.decodeIfPresent(DeskForgeList<DeskComputerStepDTO>.self, forKey: .steps)
        days = try? container.decodeIfPresent(Int.self, forKey: .days)
        agentName = try? container.decodeIfPresent(String.self, forKey: .agentName)
    }
}

// MARK: - What the screens show

/// One running computer, as the list or the stream last said.
nonisolated struct DeskComputer: Identifiable, Hashable, Sendable {
    var id: String { owner }
    var owner: String
    var isBot: Bool
    var title: String
    /// The page address without its query, fragment or sign-in.
    var address: String
    var lastAction: Date?
    var takenOver: Bool
    var waitingModel: Bool
    var recording: Bool
    var desktop: Bool
    /// When this computer was opened (epoch seconds). Owner ids are reused, so this tells a computer from the one
    /// that replaced it. Only the list carries it; a stream state has none.
    var startedAt: Double?

    var kindName: String { isBot ? "A bot's computer" : "A chat's computer" }
    var heading: String { title.isEmpty ? kindName : title }
    /// The page, or what kind of computer this is when it shows no page.
    var detail: String {
        if !address.isEmpty { return address }
        return desktop ? "A full desktop" : "No page open"
    }
}

nonisolated struct DeskComputerRun: Identifiable, Hashable, Sendable {
    var id: String
    var started: Date?
    var updated: Date?
    var count: Int
}

nonisolated struct DeskComputerStep: Identifiable, Hashable, Sendable {
    var id: Int { number }
    var number: Int
    var title: String
    var result: String
    var failed: Bool
    /// What was typed or pressed, as the desktop recorded it. A private field reads "(private field)".
    var typed: String?
    var address: String
    var isClick: Bool
    var kept: Set<String>
    var reasons: [String: String]
    var time: Date?

    /// The picture file behind a choice.
    func name(for shot: ComputerShot) -> String {
        switch shot {
        case .before: "before.jpg"
        case .after: "after.jpg"
        case .click: "marker.jpg"
        }
    }
}

// MARK: - Wire helpers

nonisolated enum DeskComputerWire {
    static let imageNames = ["before.jpg", "after.jpg", "marker.jpg"]
    /// A frame text longer than this is not read (a base64 picture of about 6 MB).
    static let maxImageText = 8_000_000

    /// "chat:<id>" or "agent:<id>", as it goes into a path. Anything that could leave its path is refused.
    static func ownerPath(_ owner: String) throws -> String {
        guard let split = owner.firstIndex(of: ":") else { throw APIError.unreadable("computer owner") }
        let kind = String(owner[..<split])
        let ident = String(owner[owner.index(after: split)...])
        guard kind == "chat" || kind == "agent", !ident.isEmpty, ident.count <= 64,
              ident.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else {
            throw APIError.unreadable("computer owner")
        }
        return owner
    }

    static func runPath(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 64,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else {
            throw APIError.unreadable("run id")
        }
        return id
    }

    static func isBot(_ owner: String) -> Bool { owner.hasPrefix("agent:") }

    /// A page address as shown: the host and path, with no sign-in, query or fragment (they can carry a session).
    static func shownAddress(_ text: String?) -> String {
        guard let text, !text.isEmpty, text != "about:blank" else { return "" }
        if let parts = URLComponents(string: text), let host = parts.host, !host.isEmpty {
            var path = hidingTokens(parts.path)
            if path == "/" { path = "" }
            return String((host + path).prefix(80))
        }
        // Not readable as an address: keep only what is before a `?` or `#`, and nothing before an `@` in the host part.
        var rest = Substring(text)
        if let cut = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) { rest = rest[..<cut] }
        if let scheme = rest.range(of: "://") { rest = rest[scheme.upperBound...] }
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        if let at = rest[..<slash].lastIndex(of: "@") { rest = rest[rest.index(after: at)...] }
        var path = hidingTokens(String(rest))
        if path == "/" { path = "" }
        return String(path.prefix(80))
    }

    /// A path with each long token-like part (20 or more letters, digits, `_` or `-`: a reset or sign-in code) hidden.
    private static func hidingTokens(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).map { part -> String in
            let token = part.count >= 20 && part.unicodeScalars.allSatisfy {
                ($0.value < 128 && CharacterSet.alphanumerics.contains($0)) || $0 == "_" || $0 == "-"
            }
            return token ? "..." : String(part)
        }.joined(separator: "/")
    }

    /// An address in text: after `URL:`, with a scheme, or a host with a path, query or fragment.
    private static let addressInText = try? NSRegularExpression(
        pattern: #"(?<=URL: )\S+|[A-Za-z][A-Za-z0-9+.\-]*://\S+|\b[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}(?::\d+)?[/?#]\S*"#,
        options: [.caseInsensitive])

    /// Text from the desktop as shown: every address in it goes through `shownAddress`, so no query, fragment,
    /// sign-in or long code is shown from a result line, a title or any other text.
    static func cleanText(_ text: String) -> String {
        guard let regex = addressInText else {
            // Never shown as it came: cut at the first `?`.
            return String(text.prefix { $0 != "?" })
        }
        let whole = text as NSString
        var out = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: whole.length)).reversed() {
            var piece = whole.substring(with: match.range)
            var tail = ""
            while let last = piece.last, ".,;:)]}'\"!>".contains(last) {
                tail = String(last) + tail
                piece.removeLast()
            }
            let shown = shownAddress(piece)
            guard let range = Range(match.range, in: out) else { continue }
            out.replaceSubrange(range, with: (shown.isEmpty ? "a blank page" : shown) + tail)
        }
        return out
    }

    static func date(_ seconds: Double?) -> Date? {
        guard let seconds, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func computer(_ row: DeskComputerRunningDTO) -> DeskComputer {
        DeskComputer(owner: row.owner, isBot: isBot(row.owner), title: cleanText((row.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)),
                     address: shownAddress(row.url), lastAction: date(row.lastAction), takenOver: row.takenOver ?? false,
                     waitingModel: row.waitingModel ?? false, recording: row.recording ?? false, desktop: row.desktop ?? false,
                     startedAt: row.startedAt)
    }

    static func computer(_ frame: DeskComputerFrameDTO, owner: String) -> DeskComputer {
        DeskComputer(owner: owner, isBot: isBot(owner), title: cleanText((frame.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)),
                     address: shownAddress(frame.url), lastAction: date(frame.lastAction), takenOver: frame.takenOver ?? false,
                     waitingModel: frame.waitingModel ?? false, recording: frame.recording ?? false, desktop: frame.desktop ?? false,
                     startedAt: nil)
    }

    /// The running computers, one row per owner, the newest action first. Rows of another kind are dropped.
    static func computers(_ list: DeskForgeList<DeskComputerRunningDTO>) -> [DeskComputer] {
        var seen = Set<String>()
        var rows: [DeskComputer] = []
        for item in list.items where (try? ownerPath(item.owner)) != nil {
            if seen.insert(item.owner).inserted { rows.append(computer(item)) }
        }
        return rows.sorted { ($0.lastAction ?? .distantPast) > ($1.lastAction ?? .distantPast) }
    }

    /// The picture bytes of a frame's base64 text, or nil when there is none or it is too large to read.
    static func imageData(_ text: String?) -> Data? {
        guard let text, !text.isEmpty, text.count <= maxImageText else { return nil }
        guard let data = Data(base64Encoded: text), !data.isEmpty else { return nil }
        return data
    }

    static func runs(_ list: DeskForgeList<DeskComputerRunDTO>) -> [DeskComputerRun] {
        var seen = Set<String>()
        var rows: [DeskComputerRun] = []
        for item in list.items where (try? runPath(item.runId)) != nil && seen.insert(item.runId).inserted {
            rows.append(DeskComputerRun(id: item.runId, started: date(item.started), updated: date(item.updated), count: item.steps ?? 0))
        }
        return rows.sorted { ($0.updated ?? $0.started ?? .distantPast) > ($1.updated ?? $1.started ?? .distantPast) }
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "..." : text
    }

    static func step(_ dto: DeskComputerStepDTO) -> DeskComputerStep {
        let args = dto.arguments
        let x = dto.point?.x ?? args?["x"]?.double
        let y = dto.point?.y ?? args?["y"]?.double
        let spot = (x != nil && y != nil) ? " at \(Int(x ?? 0)), \(Int(y ?? 0))" : ""
        let action = (dto.action ?? "").lowercased()
        var title: String
        var typed: String?
        switch action {
        case "click": title = "Click" + spot
        case "type":
            title = "Type"
            typed = args?["text"]?.string
        case "key":
            title = "Press a key"
            typed = args?["key"]?.string
        case "scroll":
            let down = (args?["dy"]?.double ?? 0) >= 0
            title = down ? "Scroll down" : "Scroll up"
        case "open": title = "Open a page"
        case "launch":
            let app = args?["app"]?.string ?? ""
            title = "Open " + (app.isEmpty ? "an app" : app)
        case "": title = "A step"
        default: title = action.prefix(1).uppercased() + String(action.dropFirst())
        }
        // Every text of the step goes through cleanText before it is clipped: an address in it loses its query,
        // fragment, sign-in and long codes, wherever the desktop wrote it.
        let result = cleanText((dto.result ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        let names = (dto.images?.items ?? []).filter { imageNames.contains($0) }
        return DeskComputerStep(number: dto.step, title: clip(cleanText(title), 120), result: clip(result, 300), failed: dto.ok == false,
                                typed: typed.map { clip(cleanText($0), 400) }, address: shownAddress(dto.url ?? args?["url"]?.string),
                                isClick: action == "click", kept: Set(names), reasons: dto.notKept ?? [:], time: date(dto.time))
    }

    /// One run's steps in order, one row per step number.
    static func steps(_ dto: DeskComputerStepsDTO) -> (steps: [DeskComputerStep], skipped: Int) {
        var seen = Set<Int>()
        var rows: [DeskComputerStep] = []
        for item in dto.steps?.items ?? [] where seen.insert(item.step).inserted { rows.append(step(item)) }
        return (rows.sorted { $0.number < $1.number }, dto.steps?.skipped ?? 0)
    }

    /// A refusal or failure as one plain sentence for a person.
    static func words(_ error: Error) -> String {
        if case .server(let status, let detail) = (error as? APIError) ?? .notPaired {
            let lower = detail.lowercased()
            switch status {
            case 403:
                return "Your account on the desktop is not allowed to see this computer. A chat's computer is for its owner or an admin, and a bot's computer is for admins."
            case 404:
                if lower.contains("closed") { return "This computer is closed." }
                if lower.contains("no retained") { return "No last picture was kept for this computer." }
                if lower.contains("steps") { return "No steps were kept for this run." }
                return "That computer is not on your desktop any more."
            default:
                break
            }
        }
        return error.plainWords
    }

    /// Reads a stream's lines into events. A blank line is not relied on (the system line reader may drop them):
    /// an `event:` line names the next `data:` line, which ends the event.
    nonisolated struct EventReader {
        private var name = "message"

        mutating func feed(_ line: String) -> (name: String, data: String)? {
            if line.hasPrefix("event:") {
                name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                return nil
            }
            guard line.hasPrefix("data:") else { return nil }
            let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let event = name
            name = "message"
            return (event, data)
        }
    }
}

// MARK: - Calls

extension APIClient {

    /// GET /api/computer: the running computers this account may see.
    func deskComputerList() async throws -> DeskForgeList<DeskComputerRunningDTO> {
        try await get("/api/computer")
    }

    /// GET /api/computer/{owner}/frames: the live stream. The caller reads its lines.
    func deskComputerFrames(_ owner: String) async throws -> URLSession.AsyncBytes {
        try await openStream("/api/computer/" + (try DeskComputerWire.ownerPath(owner)) + "/frames")
    }

    /// GET /api/computer/{owner}/last: the last picture of a closed computer, 404 when none is kept.
    func deskComputerLast(_ owner: String) async throws -> DeskComputerFrameDTO {
        try await get("/api/computer/" + (try DeskComputerWire.ownerPath(owner)) + "/last")
    }

    /// POST /api/computer/{owner}/stop: {"ok": true}; 404 "computer is closed" when it already stopped.
    func deskComputerStop(_ owner: String) async throws -> DeskForgeOkDTO {
        try await post("/api/computer/" + (try DeskComputerWire.ownerPath(owner)) + "/stop")
    }

    /// GET /api/computer/{owner}/steps: the runs kept for this computer, newest first (at most 20).
    func deskComputerRuns(_ owner: String) async throws -> DeskForgeList<DeskComputerRunDTO> {
        try await get("/api/computer/" + (try DeskComputerWire.ownerPath(owner)) + "/steps")
    }

    /// GET /api/computer/steps/{run}.
    func deskComputerSteps(_ runID: String) async throws -> DeskComputerStepsDTO {
        try await get("/api/computer/steps/" + (try DeskComputerWire.runPath(runID)))
    }

    /// GET /api/computer/steps/{run}/{number}/{name}: one kept picture (JPEG bytes).
    func deskComputerStepImage(_ runID: String, number: Int, name: String) async throws -> Data {
        guard DeskComputerWire.imageNames.contains(name), number > 0, number <= 200 else { throw APIError.unreadable("step picture") }
        return try await bytes("/api/computer/steps/" + (try DeskComputerWire.runPath(runID)) + "/\(number)/" + name)
    }
}

// MARK: - Samples

/// Sample answers for every computer route the phone reads, shaped like the desktop's own (made-up content).
nonisolated enum DeskComputerSamples {

    /// A 1 by 1 picture, so a sample frame has a real image to decode.
    static let tinyImage = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

    /// Rows carry `lease_id` and recorded `steps` (with typed text): neither is read. One row has no owner.
    static let list = #"""
    [{"owner": "chat:5b9e2f0a4c18", "url": "https://shop.example/products?session=abc123#top", "title": "Bike shop",
      "last_action": 1793100800.5, "taken_over": false, "waiting_model": false, "desktop": false, "recording": false,
      "lease_id": "0123456789abcdef", "started_at": 1793100000.0, "steps": [{"kind": "type", "text": "hunter2"}]},
     {"owner": "agent:7c1d9e22", "url": "about:blank", "title": "", "last_action": 1793100900.0,
      "taken_over": true, "waiting_model": true, "desktop": true, "recording": true, "lease_id": "fedcba9876543210",
      "started_at": 1793100100.0, "steps": []},
     {"url": "https://nowhere.example/"},
     {"owner": "../etc", "title": "bad owner"},
     {"owner": "chat:5b9e2f0a4c18", "title": "A repeat row"}]
    """#

    static let frameEvents = [
        "event: frame",
        #"data: {"owner": "chat:5b9e2f0a4c18", "url": "https://shop.example/cart", "title": "Cart", "last_action": 1793101000.25, "desktop": false, "recording": false, "taken_over": false, "waiting_model": true, "image": "\#(tinyImage)"}"#,
        "event: frame",
        #"data: {"owner": "chat:5b9e2f0a4c18", "url": "https://shop.example/cart", "title": "Cart", "last_action": 1793101001.0, "desktop": false, "recording": false, "taken_over": false, "waiting_model": false}"#,
        ": a comment line",
        "event: closed",
        "data: {}",
    ]

    static let last = #"""
    {"owner": "chat:5b9e2f0a4c18", "url": "https://shop.example/cart", "title": "Cart", "last_action": 1793101001.0,
     "closed_at": 1793101100.0, "taken_over": false, "waiting_model": false, "desktop": false, "recording": false,
     "image": "\#(tinyImage)"}
    """#

    static let runs = #"""
    [{"run_id": "run_a1", "owner": "chat:5b9e2f0a4c18", "started": 1793100000.0, "updated": 1793100500.0, "steps": 4, "bytes": 90210},
     {"run_id": "run_b2", "owner": "chat:5b9e2f0a4c18", "started": 1793000000.0, "updated": 1793000400.0, "steps": 1, "bytes": 1200},
     {"owner": "chat:5b9e2f0a4c18", "steps": 2},
     {"run_id": "bad/run", "updated": 1793100600.0}]
    """#

    static let steps = #"""
    {"run_id": "run_a1", "owner": "agent:7c1d9e22", "started": 1793100000.0, "updated": 1793100500.0, "steps": [
      {"step": 1, "action": "open", "arguments": {"url": "https://shop.example/products?token=zzz"}, "element": null, "point": null,
       "result": "The page loaded", "code": null, "ok": true, "url": "https://shop.example/products", "time": 1793100001.0,
       "run_id": "run_a1", "owner": "agent:7c1d9e22", "images": ["before.jpg", "after.jpg"],
       "evidence": {"kept": ["action.json", "before.jpg", "after.jpg"], "not_kept": {}}, "state": null},
      {"step": 2, "action": "click", "arguments": {"x": 412, "y": 268}, "element": {"label": "Add to cart"}, "point": {"x": 412, "y": 268},
       "result": "The cart shows 1 item", "code": null, "ok": true, "url": "https://shop.example/products", "time": 1793100010.0,
       "images": ["before.jpg", "after.jpg", "marker.jpg"], "evidence": {"kept": [], "not_kept": {}}, "state": {"rows": []}},
      {"step": 3, "action": "type", "arguments": {"text": "(private field)"}, "element": {"label": "Password", "private": true},
       "point": null, "result": "Typed into the field", "code": null, "ok": true, "url": "https://shop.example/login", "time": 1793100020.0,
       "images": [], "evidence": {"kept": ["action.json"], "not_kept": {"before.jpg": "private field", "after.jpg": "private field"}}},
      {"step": 4, "action": "type", "arguments": {"text": "two blue bells"}, "point": null, "result": "The save window did not open",
       "code": "no_window", "ok": false, "url": null, "time": 1793100030.0, "images": ["after.jpg"],
       "evidence": {"kept": ["action.json", "after.jpg"], "not_kept": {"before.jpg": "this action returned no screenshot"}}},
      {"step": 5, "action": "type", "arguments": {"text": "hello"}, "point": null,
       "result": "Not typed: no field is focused. URL: https://shop.example/login?token=zzz", "code": "no_focus", "ok": false,
       "url": "https://user:pw@shop.example/reset/abcdefghijklmnopqrstuvwxyz0123?code=zzz#top", "time": 1793100040.0, "images": []},
      {"action": "click"},
      {"step": 2, "action": "scroll", "arguments": {"dy": -300}}
    ], "days": 7, "agent_id": "7c1d9e22", "agent_name": "Shop helper"}
    """#

    static let forbidden = #"{"detail": "admin privileges required"}"#
    static let closed = #"{"detail": "computer is closed"}"#

    static let checks: [DecodeCheck] = [
        DecodeCheck("deskcomputer.list") {
            let read = try KJSON.decode(DeskForgeList<DeskComputerRunningDTO>.self, from: DeskComputerSamples.list)
            let rows = DeskComputerWire.computers(read)
            // Four rows decode (one has an owner that cannot go in a path, one repeats), one has no owner.
            guard read.items.count == 4, read.skipped == 1, rows.count == 2 else { throw SampleMismatch("rows") }
            // The newest action first. A bot's computer with no page shows its kind and a full desktop.
            guard rows[0].owner == "agent:7c1d9e22", rows[0].isBot, rows[0].takenOver, rows[0].recording, rows[0].desktop,
                  rows[0].heading == "A bot's computer", rows[0].detail == "A full desktop", rows[0].waitingModel else {
                throw SampleMismatch("bot row")
            }
            // The page address loses its query and fragment.
            guard rows[1].owner == "chat:5b9e2f0a4c18", !rows[1].isBot, rows[1].title == "Bike shop",
                  rows[1].address == "shop.example/products", rows[1].lastAction != nil, !rows[1].takenOver,
                  rows[1].startedAt == 1793100000.0, rows[0].startedAt == 1793100100.0 else {
                throw SampleMismatch("chat row")
            }
            guard (try? DeskComputerWire.ownerPath("chat:5b9e2f0a4c18")) != nil, (try? DeskComputerWire.ownerPath("agent:7c1d9e22")) != nil,
                  (try? DeskComputerWire.ownerPath("chat:../x")) == nil, (try? DeskComputerWire.ownerPath("user:abc")) == nil,
                  (try? DeskComputerWire.ownerPath("chat:")) == nil, (try? DeskComputerWire.ownerPath("chat")) == nil else {
                throw SampleMismatch("owner path")
            }
            return "2 computers, 1 odd row skipped, no lease or steps read"
        },
        DecodeCheck("deskcomputer.frames") {
            var reader = DeskComputerWire.EventReader()
            var events: [(name: String, data: String)] = []
            for line in DeskComputerSamples.frameEvents { if let event = reader.feed(line) { events.append(event) } }
            guard events.count == 3, events[0].name == "frame", events[1].name == "frame", events[2].name == "closed",
                  events[2].data == "{}" else { throw SampleMismatch("events") }
            let first = try KJSON.decode(DeskComputerFrameDTO.self, from: events[0].data)
            let second = try KJSON.decode(DeskComputerFrameDTO.self, from: events[1].data)
            guard first.owner == "chat:5b9e2f0a4c18", first.waitingModel == true, first.takenOver == false,
                  first.lastAction == 1793101000.25, second.image == nil, second.waitingModel == false else {
                throw SampleMismatch("frame fields")
            }
            guard let bytes = DeskComputerWire.imageData(first.image), bytes.count > 8, bytes[0] == 0x89, bytes[1] == 0x50,
                  DeskComputerWire.imageData(second.image) == nil, DeskComputerWire.imageData("not base64 !") == nil,
                  DeskComputerWire.imageData(String(repeating: "A", count: DeskComputerWire.maxImageText + 4)) == nil else {
                throw SampleMismatch("picture bytes")
            }
            let state = DeskComputerWire.computer(first, owner: "chat:5b9e2f0a4c18")
            guard state.address == "shop.example/cart", state.title == "Cart" else { throw SampleMismatch("state") }
            let last = try KJSON.decode(DeskComputerFrameDTO.self, from: DeskComputerSamples.last)
            guard last.closedAt == 1793101100.0, DeskComputerWire.imageData(last.image) != nil else { throw SampleMismatch("last frame") }
            return "frame, state only, closed, last picture"
        },
        DecodeCheck("deskcomputer.steps") {
            let runs = DeskComputerWire.runs(try KJSON.decode(DeskForgeList<DeskComputerRunDTO>.self, from: DeskComputerSamples.runs))
            guard runs.count == 2, runs[0].id == "run_a1", runs[0].count == 4, runs[1].id == "run_b2" else { throw SampleMismatch("runs") }
            let read = try KJSON.decode(DeskComputerStepsDTO.self, from: DeskComputerSamples.steps)
            let mapped = DeskComputerWire.steps(read)
            guard mapped.steps.count == 5, mapped.skipped == 1, read.days == 7, read.agentName == "Shop helper" else {
                throw SampleMismatch("step rows")
            }
            let open = mapped.steps[0], click = mapped.steps[1], hidden = mapped.steps[2], typed = mapped.steps[3]
            guard open.title == "Open a page", open.address == "shop.example/products", open.kept == ["before.jpg", "after.jpg"],
                  click.title == "Click at 412, 268", click.isClick, click.kept.contains("marker.jpg"), !click.failed,
                  hidden.typed == "(private field)", hidden.kept.isEmpty, hidden.reasons["before.jpg"] == "private field",
                  typed.typed == "two blue bells", typed.failed, typed.kept == ["after.jpg"],
                  typed.reasons["before.jpg"] == "this action returned no screenshot", typed.address == "" else {
                throw SampleMismatch("step fields")
            }
            guard click.name(for: .click) == "marker.jpg", click.name(for: .before) == "before.jpg" else { throw SampleMismatch("names") }
            // A result line that carries an address with a code in its query shows the address without it.
            let refused = mapped.steps[4]
            guard refused.result == "Not typed: no field is focused. URL: shop.example/login",
                  !refused.result.contains("?"), !refused.result.contains("zzz"),
                  refused.address == "shop.example/reset/...", !refused.address.contains("zzz"), !refused.address.contains("pw") else {
                throw SampleMismatch("step address text")
            }
            return "2 runs, 5 steps, private text kept as marked, addresses in text cleaned"
        },
        DecodeCheck("deskcomputer.addresses") {
            let one = DeskComputerWire.cleanText("Go to https://a.example/x?code=zzz#frag, then (http://b.example/y/reset?t=1).")
            let two = DeskComputerWire.cleanText("Not typed. URL: about:blank")
            let three = DeskComputerWire.cleanText("Opened shop.example/cart?session=zzz and docs.example/a/abcdefghijklmnopqrstuvwxyz1234")
            let four = DeskComputerWire.cleanText("Page https://me:secret@c.example/p/abcdefghij-klmnopqrst_uvwxyz")
            guard one == "Go to a.example/x, then (b.example/y/reset).", two == "Not typed. URL: a blank page",
                  three == "Opened shop.example/cart and docs.example/a/...", four == "Page c.example/p/...",
                  DeskComputerWire.cleanText("Plain words, no address.") == "Plain words, no address.",
                  DeskComputerWire.cleanText("Node.js and file.txt") == "Node.js and file.txt" else {
                throw SampleMismatch("text")
            }
            // An address that cannot be read keeps nothing from a `?`, a `#` or before an `@` in its host part.
            let odd = DeskComputerWire.shownAddress("https://us er@shop example/a?token=zzz")
            let long = DeskComputerWire.shownAddress("https://shop.example/reset/abcdefghijklmnopqrstuvwxyz0123?x=1")
            guard odd.hasSuffix("/a"), !odd.contains("zzz"), !odd.contains("er@"), !odd.contains("?"), long == "shop.example/reset/...",
                  DeskComputerWire.shownAddress("https://shop.example/short-slug") == "shop.example/short-slug" else {
                throw SampleMismatch("address")
            }
            return "addresses in text lose query, fragment, sign-in and long codes"
        },
        DecodeCheck("deskcomputer.errors") {
            let forbidden = try KJSON.decode(APIErrorBody.self, from: DeskComputerSamples.forbidden)
            let closed = try KJSON.decode(APIErrorBody.self, from: DeskComputerSamples.closed)
            let no = DeskComputerWire.words(APIError.server(status: 403, detail: forbidden.text))
            let gone = DeskComputerWire.words(APIError.server(status: 404, detail: closed.text))
            let other = DeskComputerWire.words(APIError.server(status: 404, detail: "agent not found"))
            guard forbidden.text == "admin privileges required", no.hasPrefix("Your account on the desktop is not allowed"),
                  gone == "This computer is closed.", other == "That computer is not on your desktop any more." else {
                throw SampleMismatch("sentences")
            }
            return "403 and 404 as plain sentences"
        },
    ]
}
