import Foundation

// The desktop routes behind Studio's libraries (Make > Studio > Formats, Styles, Characters, Connections, Templates),
// as the phone reads and writes them. All of them are signed-in account only and work in that account's own data.
// Shapes below are the desktop's own code, not a guess (routes/style_pack_routes.py over core/style_pack_store.py,
// style_pack_brief.py, style_pack_sample.py; routes/character_routes.py over core/character_store.py,
// character_sheet.py; routes/content_studio_routes.py over services/content_studio/*; routes/bot_lifecycle_routes.py).
//
// Reads:
// - GET /api/content-studio/formats {formats: [{id, name, premise, beats, length_min_s, length_max_s, audience {age_band,
//   interests, platform, why}, source_niche, do_not_use, evidence [{url, channel, title, views, age_days, checked, note}],
//   status}], ports: [{id, format_id, niche_name, style_pack, status, premise, subject, audience_match, checks {ok,
//   findings [{check, result, reason}], cost {pack_name, estimate, render_minutes}}, verdict_by, verdict_reason}]}
// - GET /api/style-packs {packs: [{id, name, origin {kind, from, brief}, approved_version, versions [{version, status
//   (draft, awaiting_approval, approved, rejected), note, reason, sample {status, at, waiting}}], spec}], built_in,
//   starters [{id, name, summary}]}. A pack's own "by" names, sample file links and export links are not read.
// - GET /api/characters {characters: [{id, name, family, approved_version, versions [{version, status, note, sheet,
//   reason}]}]}; GET /api/characters/{id} adds spec (name, family, form, accessory, palette.body, palette.accent).
// - Connections, narrow on purpose: only on or off flags are decoded. GET /api/content-studio/analytics/youtube/status
//   (configured, connected, needs_reconnect), /posting/youtube/status (connected, needs_reconnect, privacy),
//   /social/status (apps.<platform>.configured, connections[].platform and .connected), /settings (page_reads). No
//   Google account, email, channel name, key, secret, token or error text is declared, so none is decoded.
// - GET /api/content-studio/niches, GET /api/bot-lifecycle/templates {teams: [{id, name, description, package.bots
//   [{name, role}]}]}: a bot's soul text is not declared, so it is not decoded.
//
// Writes (none takes a request id, so each is kept "unconfirmed" in MakeLibraryLive until the desktop shows it):
// - POST /api/style-packs {source: "brief", brief, name?}: a model run on the desktop's first model connection. The
//   brief is kept on the pack as its origin, which is how a lost answer is checked.
// - POST /api/style-packs {source: "starter", starter}: a draft pack and its starter characters, no model, no render.
// - POST /api/style-packs/{id}/versions {changes, note}: a new draft version on top of the latest one; the desktop has no
//   base check, so the phone sends only the changed fields and reads the pack first.
// - POST /api/style-packs/{id}/versions/{n}/sample: renders on the desktop for minutes. When a character of the pack has no
//   approved sheet the desktop first renders those sheets inside this request.
// - POST /api/characters {family, name?}, POST /api/characters/{id}/versions {changes, note},
//   POST /api/characters/{id}/versions/{n}/sheet (renders a sheet inside the request).
//
// Never called from the phone: pack import, export, duplicate, approve, reject (Approvals owns those), anything on
// connections that writes (privacy, page reads, sync, connect, disconnect, social apps), template install (no route).

// MARK: - Reading one row

/// One JSON object, read with plain accessors. Keys are camelCase because the decoder turns snake_case into it.
nonisolated struct MakeLibraryRow: Sendable {
    let o: [String: JSONValue]

    init?(_ value: JSONValue?) {
        guard let object = value?.object else { return nil }
        o = object
    }

    func value(_ key: String) -> JSONValue? {
        if let found = o[key] { return found }
        var snake = ""
        for character in key {
            if character.isUppercase { snake += "_" + character.lowercased() } else { snake.append(character) }
        }
        return o[snake]
    }

    func str(_ key: String) -> String? { value(key)?.string }
    func int(_ key: String) -> Int? { value(key)?.int }
    func dbl(_ key: String) -> Double? { value(key)?.double }

    /// A switch the desktop stores as true, false, 1 or 0.
    func flag(_ key: String) -> Bool {
        if let found = value(key)?.bool { return found }
        if let number = value(key)?.int { return number != 0 }
        return false
    }

    func row(_ key: String) -> MakeLibraryRow? { MakeLibraryRow(value(key)) }
    func list(_ key: String) -> [JSONValue] { value(key)?.array ?? [] }
    func strings(_ key: String) -> [String] { list(key).compactMap(\.string) }
}

nonisolated enum MakeLibraryWire {
    /// Read the rows of a list one by one. A row that cannot be read is counted and left out.
    static func rows<T>(_ list: [JSONValue], _ make: (MakeLibraryRow) -> T?) -> (rows: [T], skipped: Int) {
        var out: [T] = []
        var skipped = 0
        for item in list {
            if let row = MakeLibraryRow(item), let value = make(row) { out.append(value) } else { skipped += 1 }
        }
        return (out, skipped)
    }

    /// A style pack's or character's id: twelve lowercase hex characters, as the desktop makes them.
    static func isID(_ text: String) -> Bool {
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        return text.count == 12 && text.unicodeScalars.allSatisfy { hex.contains($0) }
    }

    static func pathID(_ id: String) throws -> String {
        guard isID(id) else { throw APIError.unreadable("id") }
        return id
    }

    static func time(_ seconds: Double?) -> Date? {
        guard let seconds, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static let briefLimit = 12000
    static let nameLimit = 60
}

// MARK: - Formats

nonisolated struct MakeLibraryEvidenceDTO: Hashable, Sendable {
    var channel: String
    var title: String
    var host: String
    var views: Int?
    var checked: String

    init?(_ row: MakeLibraryRow) {
        guard let channel = row.str("channel") else { return nil }
        self.channel = channel
        title = row.str("title") ?? ""
        host = URL(string: row.str("url") ?? "")?.host ?? ""
        views = row.int("views")
        checked = row.str("checked") ?? ""
    }
}

nonisolated struct MakeLibraryFormatDTO: Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var premise: String
    var beats: [String]
    var lengthMin: Double
    var lengthMax: Double
    var audience: String
    var sourceNiche: String
    var evidence: [MakeLibraryEvidenceDTO]

    init?(_ row: MakeLibraryRow) {
        guard let id = row.int("id"), let name = row.str("name") else { return nil }
        self.id = id
        self.name = name
        premise = row.str("premise") ?? ""
        beats = row.strings("beats")
        lengthMin = row.dbl("lengthMinS") ?? 0
        lengthMax = row.dbl("lengthMaxS") ?? 0
        let audience = row.row("audience")
        var bits: [String] = []
        if let age = audience?.str("ageBand"), !age.isEmpty { bits.append("Ages " + age) }
        if let why = audience?.str("why"), !why.isEmpty { bits.append(why) }
        self.audience = bits.joined(separator: ". ")
        sourceNiche = row.str("sourceNiche") ?? ""
        evidence = MakeLibraryWire.rows(row.list("evidence"), MakeLibraryEvidenceDTO.init).rows
    }
}

nonisolated struct MakeLibraryFindingDTO: Hashable, Sendable {
    var check: String
    var result: String
    var reason: String
}

nonisolated struct MakeLibraryPortDTO: Identifiable, Hashable, Sendable {
    var id: Int
    var formatID: Int
    var niche: String
    var stylePack: String
    var status: String
    var premise: String
    var audienceMatch: String
    var checked: Bool
    var findings: [MakeLibraryFindingDTO]
    var cost: String
    var verdictBy: String
    var verdictReason: String

    init?(_ row: MakeLibraryRow) {
        guard let id = row.int("id"), let format = row.int("formatId") else { return nil }
        self.id = id
        formatID = format
        niche = row.str("nicheName") ?? ""
        stylePack = row.str("stylePack") ?? ""
        status = row.str("status") ?? "proposed"
        premise = row.str("premise") ?? ""
        audienceMatch = row.str("audienceMatch") ?? ""
        let checks = row.row("checks")
        checked = checks?.value("findings") != nil
        findings = (checks?.list("findings") ?? []).compactMap { item in
            guard let found = MakeLibraryRow(item), let check = found.str("check") else { return nil }
            return MakeLibraryFindingDTO(check: check, result: found.str("result") ?? "", reason: found.str("reason") ?? "")
        }
        var cost: [String] = []
        if let name = checks?.row("cost")?.str("packName") { cost.append("Made in " + name) }
        if let minutes = checks?.row("cost")?.dbl("renderMinutes") { cost.append(String(format: "about %.0f minutes of rendering", minutes)) }
        self.cost = cost.joined(separator: ", ")
        verdictBy = row.str("verdictBy") ?? ""
        verdictReason = row.str("verdictReason") ?? ""
    }
}

// MARK: - Style packs

nonisolated struct MakeLibrarySampleDTO: Hashable, Sendable {
    var status: String
    var at: Double?
    var waiting: [String]
}

nonisolated struct MakeLibraryPackVersionDTO: Identifiable, Hashable, Sendable {
    var number: Int
    var status: String
    var note: String
    var reason: String
    var sample: MakeLibrarySampleDTO?
    var id: Int { number }

    init?(_ row: MakeLibraryRow) {
        guard let number = row.int("version"), let status = row.str("status") else { return nil }
        self.number = number
        self.status = status
        note = row.str("note") ?? ""
        reason = row.str("reason") ?? ""
        if let sample = row.row("sample") {
            self.sample = MakeLibrarySampleDTO(status: sample.str("status") ?? "", at: sample.dbl("at"), waiting: sample.strings("waiting"))
        }
    }
}

nonisolated struct MakeLibraryCastDTO: Hashable, Sendable {
    var character: String
    var version: Int
}

/// The fields of a pack version the phone can edit, as the desktop names their values.
nonisolated struct MakeLibrarySpecDTO: Hashable, Sendable {
    var name: String
    var summary: String
    var brief: String
    var mood: String
    var captionsOn: Bool
    var captionCase: String
    var voice: String
    var base: String
    var cast: [MakeLibraryCastDTO]

    init?(_ row: MakeLibraryRow?) {
        guard let row, let name = row.str("name") else { return nil }
        self.name = name
        summary = row.str("summary") ?? ""
        brief = row.str("directorBrief") ?? ""
        mood = row.row("music")?.str("mood") ?? "calm"
        let captions = row.row("captions")
        captionsOn = captions?.value("on") == nil ? true : captions?.flag("on") ?? true
        captionCase = captions?.str("case") ?? "sentence"
        voice = row.row("voice")?.str("voice") ?? ""
        base = row.str("base") ?? ""
        cast = (row.list("characters")).compactMap { item in
            guard let entry = MakeLibraryRow(item), let id = entry.str("character"), let version = entry.int("version") else { return nil }
            return MakeLibraryCastDTO(character: id, version: version)
        }
    }
}

nonisolated struct MakeLibraryPackDTO: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var originKind: String
    var originFrom: String
    var originBrief: String
    var approvedVersion: Int?
    var versions: [MakeLibraryPackVersionDTO]
    var spec: MakeLibrarySpecDTO?

    var latest: MakeLibraryPackVersionDTO? { versions.last }

    init?(_ row: MakeLibraryRow) {
        guard let id = row.str("id"), MakeLibraryWire.isID(id), let name = row.str("name") else { return nil }
        self.id = id
        self.name = name
        let origin = row.row("origin")
        originKind = origin?.str("kind") ?? ""
        originFrom = origin?.str("from") ?? ""
        originBrief = origin?.str("brief") ?? ""
        approvedVersion = row.int("approvedVersion")
        versions = MakeLibraryWire.rows(row.list("versions"), MakeLibraryPackVersionDTO.init).rows
        spec = MakeLibrarySpecDTO(row.row("spec"))
    }
}

nonisolated struct MakeLibraryNamedDTO: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var detail: String
    var available: Bool

    init?(_ row: MakeLibraryRow) {
        guard let id = row.str("id"), let name = row.str("name") else { return nil }
        self.id = id
        self.name = name
        detail = row.str("summary") ?? ""
        available = row.value("available") == nil ? true : row.flag("available")
    }
}

nonisolated struct MakeLibraryPackList: Sendable {
    var packs: [MakeLibraryPackDTO] = []
    var builtIn: [MakeLibraryNamedDTO] = []
    var starters: [MakeLibraryNamedDTO] = []
    var skipped = 0

    init(_ root: JSONValue) {
        guard let row = MakeLibraryRow(root) else { return }
        let packs = MakeLibraryWire.rows(row.list("packs"), MakeLibraryPackDTO.init)
        let builtIn = MakeLibraryWire.rows(row.list("builtIn"), MakeLibraryNamedDTO.init)
        let starters = MakeLibraryWire.rows(row.list("starters"), MakeLibraryNamedDTO.init)
        self.packs = packs.rows
        self.builtIn = builtIn.rows
        self.starters = starters.rows
        skipped = packs.skipped + builtIn.skipped + starters.skipped
    }
}

// MARK: - Characters

nonisolated struct MakeLibraryCharVersionDTO: Identifiable, Hashable, Sendable {
    var number: Int
    var status: String
    var note: String
    var reason: String
    var hasSheet: Bool
    var id: Int { number }

    init?(_ row: MakeLibraryRow) {
        guard let number = row.int("version"), let status = row.str("status") else { return nil }
        self.number = number
        self.status = status
        note = row.str("note") ?? ""
        reason = row.str("reason") ?? ""
        hasSheet = row.flag("sheet")
    }
}

/// The fields of a character version the phone can edit, as the desktop names their values.
nonisolated struct MakeLibraryCharSpecDTO: Hashable, Sendable {
    var name: String
    var form: String
    var accessory: String
    var body: String
    var accent: String

    init?(_ row: MakeLibraryRow?) {
        guard let row, let name = row.str("name") else { return nil }
        self.name = name
        form = row.str("form") ?? "2d"
        accessory = row.str("accessory") ?? "none"
        body = (row.row("palette")?.str("body") ?? "").lowercased()
        accent = (row.row("palette")?.str("accent") ?? "").lowercased()
    }
}

nonisolated struct MakeLibraryCharacterDTO: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var family: String
    var approvedVersion: Int?
    var versions: [MakeLibraryCharVersionDTO]
    var spec: MakeLibraryCharSpecDTO?

    var latest: MakeLibraryCharVersionDTO? { versions.last }

    init?(_ row: MakeLibraryRow) {
        guard let id = row.str("id"), MakeLibraryWire.isID(id), let name = row.str("name") else { return nil }
        self.id = id
        self.name = name
        family = row.str("family") ?? "round"
        approvedVersion = row.int("approvedVersion")
        versions = MakeLibraryWire.rows(row.list("versions"), MakeLibraryCharVersionDTO.init).rows
        spec = MakeLibraryCharSpecDTO(row.row("spec"))
    }
}

// MARK: - Niches, templates

nonisolated struct MakeLibraryNicheDTO: Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var retired: Bool
    var slots: Int

    init?(_ row: MakeLibraryRow) {
        guard let id = row.int("id"), let name = row.str("name") else { return nil }
        self.id = id
        self.name = name
        retired = row.str("status") == "retired"
        slots = row.int("slots") ?? 1
    }
}

nonisolated struct MakeLibraryTemplateDTO: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var detail: String
    var bots: [String]
}

// MARK: - Connections (on or off only)

/// A switch the desktop writes as true, false, 1 or 0. Anything else reads as not known.
nonisolated struct MakeLibraryFlag: Decodable, Hashable, Sendable {
    var value: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let number = try? container.decode(Int.self) {
            value = number != 0
        } else {
            value = nil
        }
    }
}

/// One element of a list that never fails the whole list when it is odd.
nonisolated struct MakeLibraryLenient<T: Decodable & Sendable>: Decodable, Sendable {
    var value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

nonisolated struct MakeLibraryYouTubeAnswer: Decodable, Sendable {
    var configured: MakeLibraryFlag?
    var connected: MakeLibraryFlag?
    var needsReconnect: MakeLibraryFlag?
    var privacy: String?
}

nonisolated struct MakeLibraryAppAnswer: Decodable, Sendable {
    var configured: MakeLibraryFlag?
}

nonisolated struct MakeLibrarySocialLink: Decodable, Sendable {
    var platform: String?
    var connected: MakeLibraryFlag?
}

nonisolated struct MakeLibrarySocialAnswer: Decodable, Sendable {
    var apps: [String: MakeLibraryLenient<MakeLibraryAppAnswer>]?
    var connections: [MakeLibraryLenient<MakeLibrarySocialLink>]?
}

nonisolated struct MakeLibrarySettingsAnswer: Decodable, Sendable {
    var pageReads: [String: MakeLibraryFlag]?
}

/// What the phone shows of Connections. A nil part could not be read this time.
nonisolated struct MakeLibraryConnections: Hashable, Sendable {
    nonisolated struct Part: Hashable, Sendable {
        var configured: Bool?
        var connected: Bool?
        var needsSignIn = false
    }

    var youtubeAnalytics: Part?
    var youtubePosting: Part?
    var uploadPrivacy: String?
    var tiktokApp: Bool?
    var instagramApp: Bool?
    var tiktokConnected: Bool?
    var instagramConnected: Bool?
    var tiktokPageReads: Bool?
    var instagramPageReads: Bool?

    init() {}

    init(youtube: MakeLibraryYouTubeAnswer?, posting: MakeLibraryYouTubeAnswer?, social: MakeLibrarySocialAnswer?, settings: MakeLibrarySettingsAnswer?) {
        func part(_ answer: MakeLibraryYouTubeAnswer?) -> Part? {
            guard let answer else { return nil }
            return Part(configured: answer.configured?.value, connected: answer.connected?.value, needsSignIn: answer.needsReconnect?.value == true)
        }
        youtubeAnalytics = part(youtube)
        youtubePosting = part(posting)
        uploadPrivacy = posting?.privacy
        if let social {
            let links = (social.connections ?? []).compactMap(\.value)
            func linked(_ platform: String) -> Bool { links.contains { $0.platform == platform && $0.connected?.value == true } }
            tiktokApp = social.apps?["tiktok"]?.value?.configured?.value
            instagramApp = social.apps?["instagram"]?.value?.configured?.value
            tiktokConnected = linked("tiktok")
            instagramConnected = linked("instagram")
        }
        if let settings {
            tiktokPageReads = settings.pageReads?["tiktok"]?.value
            instagramPageReads = settings.pageReads?["instagram"]?.value
        }
    }
}

nonisolated struct MakeLibraryBotAnswer: Decodable, Sendable {
    var name: String?
}

nonisolated struct MakeLibraryBundleAnswer: Decodable, Sendable {
    var bots: [MakeLibraryLenient<MakeLibraryBotAnswer>]?
}

nonisolated struct MakeLibraryTeamAnswer: Decodable, Sendable {
    var id: String?
    var name: String?
    var blurb: String?
    var bundle: MakeLibraryBundleAnswer?

    enum CodingKeys: String, CodingKey {
        case id, name
        case blurb = "description"
        case bundle = "package"
    }
}

nonisolated struct MakeLibraryTemplatesAnswer: Decodable, Sendable {
    var teams: [MakeLibraryLenient<MakeLibraryTeamAnswer>]?

    var templates: [MakeLibraryTemplateDTO] {
        (teams ?? []).compactMap { item in
            guard let team = item.value, let id = team.id, let name = team.name else { return nil }
            return MakeLibraryTemplateDTO(id: id, name: name, detail: team.blurb ?? "",
                                          bots: (team.bundle?.bots ?? []).compactMap { $0.value?.name })
        }
    }
}

// MARK: - Calls

extension APIClient {
    private static let libraryStudio = "/api/content-studio"

    func makeLibraryFormats() async throws -> JSONValue { try await get(Self.libraryStudio + "/formats") }
    func makeLibraryNiches() async throws -> JSONValue { try await get(Self.libraryStudio + "/niches") }
    func makeLibraryPacks() async throws -> JSONValue { try await get("/api/style-packs") }
    func makeLibraryPack(_ id: String) async throws -> JSONValue { try await get("/api/style-packs/" + MakeLibraryWire.pathID(id)) }
    func makeLibraryCharacters() async throws -> JSONValue { try await get("/api/characters") }
    func makeLibraryCharacter(_ id: String) async throws -> JSONValue { try await get("/api/characters/" + MakeLibraryWire.pathID(id)) }
    func makeLibraryYouTube() async throws -> MakeLibraryYouTubeAnswer { try await get(Self.libraryStudio + "/analytics/youtube/status") }
    func makeLibraryPosting() async throws -> MakeLibraryYouTubeAnswer { try await get(Self.libraryStudio + "/posting/youtube/status") }
    func makeLibrarySocial() async throws -> MakeLibrarySocialAnswer { try await get(Self.libraryStudio + "/social/status") }
    func makeLibrarySettings() async throws -> MakeLibrarySettingsAnswer { try await get(Self.libraryStudio + "/settings") }
    func makeLibraryTemplates() async throws -> MakeLibraryTemplatesAnswer { try await get("/api/bot-lifecycle/templates") }

    // Writes. None takes a request id.

    /// The longest one call can take on this client (its whole-call limit is 180 seconds), so a normal run answers
    /// before the phone gives up.
    static let makeLibraryLongTimeout: TimeInterval = 175

    private func makeLibraryLongPost(_ path: String, json: [String: Any]) async throws {
        var request = try urlRequest("POST", path)
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.makeLibraryLongTimeout
        _ = try await send(request)
    }

    /// A model run on the desktop. The desktop picks the model connection (none is sent).
    func makeLibraryCreateFromBrief(brief: String, name: String) async throws {
        var body: [String: Any] = ["source": "brief", "brief": brief]
        if !name.isEmpty { body["name"] = name }
        try await makeLibraryLongPost("/api/style-packs", json: body)
    }

    func makeLibraryInstallStarter(_ id: String) async throws {
        try await call("POST", "/api/style-packs", json: ["source": "starter", "starter": id])
    }

    /// Only the changed fields (`changes`), merged by the desktop over the pack's latest version.
    func makeLibraryNewPackVersion(_ id: String, changes: [String: Any], note: String) async throws {
        try await call("POST", "/api/style-packs/" + (try MakeLibraryWire.pathID(id)) + "/versions", json: ["changes": changes, "note": note])
    }

    func makeLibraryMakeSample(_ id: String, version: Int) async throws {
        try await makeLibraryLongPost("/api/style-packs/" + (try MakeLibraryWire.pathID(id)) + "/versions/\(version)/sample", json: [:])
    }

    func makeLibraryCreateCharacter(family: String, name: String) async throws {
        var body: [String: Any] = ["family": family]
        if !name.isEmpty { body["name"] = name }
        try await call("POST", "/api/characters", json: body)
    }

    func makeLibraryNewCharacterVersion(_ id: String, changes: [String: Any], note: String) async throws {
        try await call("POST", "/api/characters/" + (try MakeLibraryWire.pathID(id)) + "/versions", json: ["changes": changes, "note": note])
    }

    func makeLibraryMakeSheet(_ id: String, version: Int) async throws {
        try await makeLibraryLongPost("/api/characters/" + (try MakeLibraryWire.pathID(id)) + "/versions/\(version)/sheet", json: [:])
    }
}

// MARK: - Samples

/// A sample answer for every library route this app reads, shaped like the desktop's own (made-up content).
nonisolated enum MakeLibrarySamples {

    static let formats = #"""
    {"formats": [
      {"id": 1, "name": "One fix, one minute", "premise": "One small fix, shown start to finish.", "beats": ["Hook", "The problem", "The fix", "Payoff"],
       "length_min_s": 25, "length_max_s": 60, "audience": {"age_band": "25-40", "interests": "bikes", "platform": "youtube", "why": "They want quick answers."},
       "source_niche": "bike repair", "do_not_use": ["Some Channel"], "status": "active",
       "evidence": [{"url": "https://example.com/watch/abc", "channel": "Some Channel", "title": "Fix a flat", "views": 120000, "age_days": 30, "checked": "2026-11-01", "note": null}, {"title": "no channel"}]},
      {"name": "No id"}
    ],
    "ports": [
      {"id": 4, "format_id": 1, "niche_id": 2, "niche_name": "Small gardens", "style_pack": "flat-2d", "status": "proposed", "premise": "One fix for a garden.",
       "subject": "Mending a hose", "audience_match": "Gardeners watch short fixes too.", "verdict_by": null, "verdict_reason": "",
       "checks": {"ok": true, "findings": [{"check": "cost", "result": "warn", "reason": "Costs about 3 times the cheapest pack."}],
                  "cost": {"pack_name": "Flat 2D explainer", "estimate": "planning units", "render_minutes": 2.4, "units": 3.0}}},
      {"id": 5, "format_id": 1, "niche_name": "Small gardens", "style_pack": "motion-type", "status": "accepted", "checks": {}},
      {"id": 6}
    ],
    "style_packs": []}
    """#

    static let packs = #"""
    {"packs": [
      {"id": "a1b2c3d4e5f6", "name": "Warm paper", "created": 1792000000, "updated": 1792100000,
       "origin": {"kind": "brief", "from": "alex", "brief": "Warm paper colours, hand-drawn arrows."}, "approved_version": 1,
       "versions": [
         {"version": 1, "status": "approved", "created": 1792000000, "by": "alex", "note": "From a brief.", "sample": {"status": "ready", "at": 1792050000, "video_id": "0123456789ab"},
          "submitted_at": 1792050000, "decided_at": 1792060000, "decided_by": "alex", "reason": "", "sample_url": "/api/style-packs/a1b2c3d4e5f6/versions/1/sample.mp4"},
         {"version": 2, "status": "draft", "note": "Softer colours.", "sample": {"status": "rendering", "at": 1792200000}, "reason": ""},
         {"status": "draft"}],
       "spec": {"name": "Warm paper", "summary": "Calm and warm.", "renderer": "2d-engine", "base": "flat-2d", "director_brief": "Warm paper colours.",
                "look": {"palette": "dawn"}, "characters": [{"character": "0f1e2d3c4b5a", "version": 1}],
                "captions": {"on": true, "case": "sentence"}, "music": {"mood": "calm", "volume": 0.6}, "voice": {"voice": "af_heart"}}},
      {"id": "b2c3d4e5f6a1", "name": "Blocky story", "origin": {"kind": "starter", "from": "classic-block-story", "brief": ""}, "approved_version": null,
       "versions": [{"version": 1, "status": "rejected", "note": "The starter pack.", "reason": "Too busy.", "sample": {"status": "failed: the render ran out of memory", "at": 1792300000}}],
       "spec": null},
      {"id": "bad", "name": "Bad id"}
    ],
    "built_in": [{"id": "motion-type", "name": "Motion type", "available": true, "renderer": "2d-engine"}, {"id": "flat-2d", "name": "Flat 2D explainer", "available": false}, {"name": "no id"}],
    "starters": [{"id": "flat-science-explainer", "name": "Flat science explainer", "summary": "Flat vector science."}, {"id": "classic-block-story", "name": "Classic block story", "summary": "Story Shorts."}],
    "renderers": {}, "available": [], "pending": []}
    """#

    static let characters = #"""
    {"characters": [
      {"id": "0f1e2d3c4b5a", "name": "Pip", "family": "round", "created": 1792000000, "updated": 1792100000, "approved_version": null,
       "versions": [{"version": 1, "status": "rejected", "created": 1792000000, "by": "alex", "note": "First version.", "sheet": true, "metrics": null, "reason": "Eyes too small."},
                    {"version": 2, "status": "draft", "note": "Bigger eyes.", "sheet": false, "reason": ""}]},
      {"id": "1e2d3c4b5a6f", "name": "Bo", "family": "square", "approved_version": 1, "versions": [{"version": 1, "status": "approved", "note": "", "sheet": true}]},
      {"name": "No id"}
    ], "pending": [], "families": ["round", "square", "triangle"], "starters": {}}
    """#

    static let character = #"""
    {"id": "0f1e2d3c4b5a", "name": "Pip", "family": "round", "approved_version": null,
     "versions": [{"version": 1, "status": "rejected", "note": "First version.", "sheet": true, "reason": "Eyes too small."}, {"version": 2, "status": "draft", "note": "Bigger eyes.", "sheet": false}],
     "spec": {"name": "Pip", "family": "round", "accessory": "leaf", "outline": 7,
              "palette": {"body": "#F4A259", "body_shade": "#e0843d", "head": "#f7c08a", "limb": "#5b4a6b", "eye": "#231b2e", "mouth": "#8c3b4a", "outline": "#2e2438", "accent": "#7cc6a4", "cheek": "#f08a8a"}}}
    """#

    static let youtube = #"""
    {"configured": true, "project": {"number": "123"}, "connected": true, "pending": false, "needs_reconnect": false,
     "google_account": "someone@example.com", "channels": [{"id": 7, "handle": "@trailtips", "google_account": "someone@example.com"}],
     "google_accounts": [{"id": "g1", "email": "someone@example.com"}], "last_sync": 1792000000, "last_error": null}
    """#

    static let posting = #"""
    {"configured": true, "connected": false, "needs_reconnect": 1, "privacy": "unlisted", "privacy_choices": ["private", "unlisted", "public"],
     "google_account": null, "channels": [], "last_upload": null}
    """#

    static let social = #"""
    {"apps": {"tiktok": {"configured": false, "key": "", "has_secret": false, "audited": false}, "instagram": {"configured": true, "key": "abc", "has_secret": true, "redirect": "loopback"}},
     "connections": [{"channel_id": 8, "platform": "tiktok", "account": "@spokeshorts", "connected": true, "error": ""}, {"channel_id": 9, "platform": "instagram", "connected": 0}, "odd"]}
    """#

    static let settings = #"""
    {"weights": {"views": 0.4}, "page_reads": {"tiktok": true, "instagram": null}, "hands_off": false}
    """#

    static let niches = #"""
    {"niches": [{"id": 1, "name": "Bike care", "status": "live", "slots": 2}, {"id": 2, "name": "Small gardens", "status": "retired", "slots": 1}, {"name": "No id"}], "max_live": 5}
    """#

    static let templates = #"""
    {"teams": [
      {"id": "content-studio", "name": "Content Studio", "description": "A team that makes short videos.",
       "package": {"manifest": {"name": "Content Studio"}, "bots": [{"key": "p", "name": "Producer", "role": "Leads", "soul": "private instructions"}, {"name": "Editor"}, "odd"]}},
      {"id": "research-desk", "name": "Research desk", "package": {"bots": []}},
      {"name": "No id"}
    ], "ready": []}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("makelibrary.formats") {
            let root = MakeLibraryRow(try KJSON.decode(JSONValue.self, from: MakeLibrarySamples.formats))
            let formats = MakeLibraryWire.rows(root?.list("formats") ?? [], MakeLibraryFormatDTO.init)
            let ports = MakeLibraryWire.rows(root?.list("ports") ?? [], MakeLibraryPortDTO.init)
            guard formats.rows.count == 1, formats.skipped == 1, formats.rows[0].beats.count == 4, formats.rows[0].lengthMax == 60,
                  formats.rows[0].evidence.count == 1, formats.rows[0].evidence[0].host == "example.com", formats.rows[0].evidence[0].views == 120000,
                  formats.rows[0].audience.hasPrefix("Ages 25-40"),
                  ports.rows.count == 2, ports.skipped == 1, ports.rows[0].checked, ports.rows[0].findings.count == 1,
                  ports.rows[0].findings[0].result == "warn", ports.rows[0].cost.hasPrefix("Made in Flat 2D"),
                  ports.rows[0].verdictBy.isEmpty, !ports.rows[1].checked, ports.rows[1].status == "accepted" else {
                throw SampleMismatch("format or port fields")
            }
            return "1 format, 2 ports, odd rows skipped"
        },
        DecodeCheck("makelibrary.packs") {
            let list = MakeLibraryPackList(try KJSON.decode(JSONValue.self, from: MakeLibrarySamples.packs))
            guard list.packs.count == 2, list.skipped == 2, list.builtIn.count == 2, list.starters.count == 2,
                  !list.builtIn[1].available, list.builtIn[0].available else {
                throw SampleMismatch("pack list counts")
            }
            let warm = list.packs[0]
            guard warm.id == "a1b2c3d4e5f6", warm.approvedVersion == 1, warm.originKind == "brief", warm.originBrief.hasPrefix("Warm paper"),
                  warm.versions.count == 2, warm.versions[1].sample?.status == "rendering", warm.versions[1].sample?.at == 1_792_200_000,
                  warm.versions[0].sample?.waiting.isEmpty == true,
                  warm.spec?.mood == "calm", warm.spec?.captionsOn == true, warm.spec?.captionCase == "sentence", warm.spec?.voice == "af_heart",
                  warm.spec?.brief == "Warm paper colours.", warm.spec?.cast.count == 1, warm.spec?.cast[0].character == "0f1e2d3c4b5a" else {
                throw SampleMismatch("pack fields")
            }
            let blocky = list.packs[1]
            guard blocky.approvedVersion == nil, blocky.spec == nil, blocky.originFrom == "classic-block-story",
                  blocky.versions[0].reason == "Too busy.", blocky.versions[0].sample?.status.hasPrefix("failed") == true else {
                throw SampleMismatch("starter pack fields")
            }
            return "2 packs, 2 built in, 2 starters, odd rows skipped"
        },
        DecodeCheck("makelibrary.characters") {
            let root = MakeLibraryRow(try KJSON.decode(JSONValue.self, from: MakeLibrarySamples.characters))
            let list = MakeLibraryWire.rows(root?.list("characters") ?? [], MakeLibraryCharacterDTO.init)
            let oneRow = MakeLibraryRow(try KJSON.decode(JSONValue.self, from: MakeLibrarySamples.character))
            let one = oneRow.flatMap(MakeLibraryCharacterDTO.init)
            guard list.rows.count == 2, list.skipped == 1, list.rows[0].approvedVersion == nil, list.rows[1].approvedVersion == 1,
                  list.rows[0].versions.count == 2, list.rows[0].versions[0].hasSheet, !list.rows[0].versions[1].hasSheet,
                  list.rows[0].versions[0].reason == "Eyes too small.", list.rows[0].spec == nil,
                  one?.spec?.accessory == "leaf", one?.spec?.body == "#f4a259", one?.spec?.accent == "#7cc6a4", one?.spec?.form == "2d" else {
                throw SampleMismatch("character fields")
            }
            return "2 characters, one with its spec"
        },
        DecodeCheck("makelibrary.connections") {
            let youtube = try KJSON.decode(MakeLibraryYouTubeAnswer.self, from: MakeLibrarySamples.youtube)
            let posting = try KJSON.decode(MakeLibraryYouTubeAnswer.self, from: MakeLibrarySamples.posting)
            let social = try KJSON.decode(MakeLibrarySocialAnswer.self, from: MakeLibrarySamples.social)
            let settings = try KJSON.decode(MakeLibrarySettingsAnswer.self, from: MakeLibrarySamples.settings)
            let all = MakeLibraryConnections(youtube: youtube, posting: posting, social: social, settings: settings)
            let none = MakeLibraryConnections(youtube: nil, posting: nil, social: nil, settings: nil)
            guard all.youtubeAnalytics?.connected == true, all.youtubeAnalytics?.configured == true, all.youtubeAnalytics?.needsSignIn == false,
                  all.youtubePosting?.connected == false, all.youtubePosting?.needsSignIn == true, all.uploadPrivacy == "unlisted",
                  all.tiktokApp == false, all.instagramApp == true, all.tiktokConnected == true, all.instagramConnected == false,
                  all.tiktokPageReads == true, all.instagramPageReads == nil,
                  none.youtubeAnalytics == nil, none.tiktokApp == nil, none.uploadPrivacy == nil else {
                throw SampleMismatch("connection flags")
            }
            return "on and off flags only, no account or key read"
        },
        DecodeCheck("makelibrary.niches-templates") {
            let niches = MakeLibraryWire.rows(MakeLibraryRow(try KJSON.decode(JSONValue.self, from: MakeLibrarySamples.niches))?.list("niches") ?? [], MakeLibraryNicheDTO.init)
            let templates = try KJSON.decode(MakeLibraryTemplatesAnswer.self, from: MakeLibrarySamples.templates).templates
            guard niches.rows.count == 2, niches.skipped == 1, niches.rows[1].retired, niches.rows[0].slots == 2,
                  templates.count == 2, templates[0].id == "content-studio", templates[0].bots == ["Producer", "Editor"],
                  templates[0].detail == "A team that makes short videos.", templates[1].detail.isEmpty, templates[1].bots.isEmpty else {
                throw SampleMismatch("niche or template fields")
            }
            return "2 niches, 2 templates, bot names only"
        },
        DecodeCheck("makelibrary.ids") {
            guard MakeLibraryWire.isID("a1b2c3d4e5f6"), !MakeLibraryWire.isID("A1B2C3D4E5F6"), !MakeLibraryWire.isID("short"),
                  (try? MakeLibraryWire.pathID("a1b2c3d4e5f6")) != nil, (try? MakeLibraryWire.pathID("../x")) == nil else {
                throw SampleMismatch("id checks")
            }
            return "ids are twelve lowercase hex characters"
        },
    ]
}
