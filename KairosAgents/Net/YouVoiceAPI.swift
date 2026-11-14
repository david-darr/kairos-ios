import Foundation

// The desktop routes behind You > Models, Voice, Bot call voice and Reach me, as the phone reads them. Read from
// the desktop's own code:
//
// - GET /api/models (routes/model_routes.py over core/model_endpoints.py: _masked, list_endpoints): the account's
//   connections and those shared with it. Only "has a key" (a yes or no) is read: no key, and no address beyond its
//   host. A shared connection comes with an empty address and no key flag.
// - GET /api/models/stats (core/model_stats.py): measured speed per connection id, read from the raw answer because
//   the ids are dictionary keys.
// - POST /api/models/{id}/test: runs one tiny model turn: {"ok", "latency_ms", "detail"}.
// - PATCH /api/models/{id}/image-support {"enabled"}: own local and API connections only.
// - GET /api/settings (routes/settings_routes.py): only auto_compact and helper_endpoint_id are read (vault_dir, a
//   personal path, is left out). POST /api/settings/auto-compact {"enabled"}, POST /api/settings/helpers
//   {"endpoint_id": null | "off" | id}.
// - GET /api/voice-engines and PUT /choice, /quality, /hd/voice (routes/voice_engine_routes.py over
//   core/call_voices.py and core/hd_voice.py). The answer is the whole state; no key and no server address is read
//   except the host of a voice server already chosen. POST /hd/preview answers a WAV file.
// - GET and PUT /api/voice-engines/pronunciations: PUT replaces the whole list ({"items": [...]}).
// - GET /api/speech/status (routes/speech_routes.py over core/speech.py): which listening models are on disk.
// - GET /api/models/free-voice: whether a free Gemini key is connected (core/free_voice.py: status, never the key).
// - GET and PUT /api/bot-voice/live-settings (routes/bot_voice_routes.py over services/bot_voice.py): ONE setting
//   per account. PUT takes all three fields (a missing one is reset to its default), so all three are always sent.
// - GET and PUT /api/reach-me, POST /api/reach-me/pause (routes/reach_me_routes.py over core/reach_me.py and
//   services/reach_me.py: view). PUT is a patch of message, call, quiet and bots; quiet and bots are replaced whole.
//   Read from the raw answer, since a bot id is a dictionary key.

/// A change stopped before anything was sent to the desktop.
nonisolated struct YouVoiceNotSent: Error, Sendable {
    let plain: String
}

// MARK: - Models

/// One connection (core/model_endpoints.py: _masked and list_endpoints). Whether it has a key is a yes or no.
nonisolated struct YouVoiceModelDTO: Decodable, Sendable {
    var id: String
    var name: JSONValue?
    /// An address as the desktop keeps it. Only its host is ever kept or shown on the phone.
    var baseUrl: JSONValue?
    var model: JSONValue?
    var hasApiKey: JSONValue?
    /// "api", "local", "claude_cli", "codex_cli" or "antigravity_cli".
    var kind: JSONValue?
    var numCtx: JSONValue?
    var supportsImages: JSONValue?
    var shared: JSONValue?
    var sharedBy: JSONValue?
}

/// GET /api/models: a JSON list, read connection by connection so one odd row does not empty it.
nonisolated struct YouVoiceModelListDTO: Decodable, Sendable {
    var models: [YouVoiceModelDTO] = []
    var skipped = 0

    init(from decoder: Decoder) throws {
        var list = try decoder.unkeyedContainer()
        while !list.isAtEnd {
            if let item = try? list.decode(YouVoiceModelDTO.self) {
                models.append(item)
            } else {
                _ = try list.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

/// POST /api/models/{id}/test: {"ok": bool, "latency_ms": int, "detail": text}.
nonisolated struct YouVoiceTestDTO: Decodable, Sendable {
    var ok: JSONValue?
    var latencyMs: JSONValue?
    var detail: JSONValue?
}

/// GET /api/settings (two fields) and the answers of POST /auto-compact and /helpers.
nonisolated struct YouVoiceSettingsDTO: Decodable, Sendable {
    var autoCompact: JSONValue?
    /// null: automatic (the first local model). "off". Or a connection id.
    var helperEndpointId: JSONValue?
}

/// One connection's measured speed (core/model_stats.py: summarize), for one line of words.
nonisolated struct YouVoiceStat: Hashable, Sendable {
    var runs: Int
    var enoughData: Bool
    var failed: Int
    var stopped: Int
    var firstOutputSeconds: Double?
    var tokensPerSecond: Double?
}

nonisolated enum YouVoiceStats {
    /// The answer of GET /api/models/stats: connection id to its stat. Read from the raw answer.
    static func parse(_ data: Data) throws -> [String: YouVoiceStat] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let endpoints = root["endpoints"] as? [String: Any] else { throw APIError.unreadable("model stats") }
        var found: [String: YouVoiceStat] = [:]
        for (id, value) in endpoints {
            guard let row = value as? [String: Any] else { continue }
            let runs = (row["runs"] as? NSNumber)?.intValue ?? 0
            found[id] = YouVoiceStat(runs: runs, enoughData: (row["enough_data"] as? Bool) ?? false,
                                     failed: (row["failed"] as? NSNumber)?.intValue ?? 0,
                                     stopped: (row["stopped"] as? NSNumber)?.intValue ?? 0,
                                     firstOutputSeconds: (row["ttft_median_s"] as? NSNumber)?.doubleValue,
                                     tokensPerSecond: (row["tokens_per_second_median"] as? NSNumber)?.doubleValue)
        }
        return found
    }

    /// The desktop's own one-line summary (static/js/modelStats.js: speedLine), nil when there were no runs.
    static func line(_ stat: YouVoiceStat) -> String? {
        guard stat.runs > 0 else { return nil }
        guard stat.enoughData else {
            return "Not enough data yet: \(stat.runs) run\(stat.runs == 1 ? "" : "s") in the last 7 days"
        }
        var parts: [String] = []
        if let first = stat.firstOutputSeconds { parts.append("first output " + seconds(first)) }
        if let rate = stat.tokensPerSecond { parts.append("\(Int(rate.rounded())) tok/s") }
        parts.append(stat.failed == 0 ? "none failed of \(stat.runs)" : "\(stat.failed) failed of \(stat.runs)")
        if stat.stopped > 0 { parts.append("\(stat.stopped) stopped") }
        return "Last 7 days: " + parts.joined(separator: " · ")
    }

    private static func seconds(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f s", value) : "\(Int(value.rounded())) s"
    }
}

// MARK: - Voice

/// One HD voice (core/hd_voice.py: VOICES). The description is left out.
nonisolated struct YouVoiceHDVoiceDTO: Decodable, Sendable {
    var id: String
    var name: JSONValue?
}

/// core/hd_voice.py: status. The sizes, sources and graphics card name are left out.
nonisolated struct YouVoiceHDDTO: Decodable, Sendable {
    var offered: JSONValue?
    var installed: JSONValue?
    var ready: JSONValue?
    var notReadyReason: JSONValue?
    var voices: [YouVoiceHDVoiceDTO] = []

    private enum Keys: String, CodingKey { case offered, installed, ready, notReadyReason, voices }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        offered = try? keyed.decodeIfPresent(JSONValue.self, forKey: .offered)
        installed = try? keyed.decodeIfPresent(JSONValue.self, forKey: .installed)
        ready = try? keyed.decodeIfPresent(JSONValue.self, forKey: .ready)
        notReadyReason = try? keyed.decodeIfPresent(JSONValue.self, forKey: .notReadyReason)
        if keyed.contains(.voices), (try? keyed.decodeNil(forKey: .voices)) == false,
           var list = try? keyed.nestedUnkeyedContainer(forKey: .voices) {
            while !list.isAtEnd {
                if let voice = try? list.decode(YouVoiceHDVoiceDTO.self) {
                    voices.append(voice)
                } else {
                    _ = try list.decode(JSONValue.self)
                }
            }
        }
    }
}

nonisolated struct YouVoiceKairosDTO: Decodable, Sendable {
    var kokoroReady: JSONValue?
    var kokoroReason: JSONValue?
}

nonisolated struct YouVoiceGPTLiveDTO: Decodable, Sendable {
    /// An OpenAI connection exists on the desktop that offers GPT-Live.
    var available: JSONValue?
    var pricePerMinute: JSONValue?
}

nonisolated struct YouVoiceElevenDTO: Decodable, Sendable {
    /// A yes or no. The key itself is never sent by the desktop and never read here.
    var hasKey: JSONValue?
    var pricePer1k: JSONValue?
}

/// A voice server on the desktop's own computer. Only the address is read, to show its host.
nonisolated struct YouVoiceServerDTO: Decodable, Sendable {
    var url: JSONValue?
}

/// GET /api/voice-engines, and the answer of every PUT under it (routes/voice_engine_routes.py: _state).
nonisolated struct YouVoiceEngineStateDTO: Decodable, Sendable {
    /// "kairos", "gpt_live", "elevenlabs", "voicebox" or "compatible".
    var choice: JSONValue?
    /// "standard" or "hd".
    var quality: JSONValue?
    var hdVoice: JSONValue?
    var hd: YouVoiceHDDTO?
    var kairos: YouVoiceKairosDTO?
    var gptLive: YouVoiceGPTLiveDTO?
    var elevenlabs: YouVoiceElevenDTO?
    var voicebox: YouVoiceServerDTO?
    var compatible: YouVoiceServerDTO?

    private enum Keys: String, CodingKey { case choice, quality, hdVoice, hd, kairos, gptLive, elevenlabs, voicebox, compatible }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        choice = try? keyed.decodeIfPresent(JSONValue.self, forKey: .choice)
        quality = try? keyed.decodeIfPresent(JSONValue.self, forKey: .quality)
        hdVoice = try? keyed.decodeIfPresent(JSONValue.self, forKey: .hdVoice)
        hd = try? keyed.decodeIfPresent(YouVoiceHDDTO.self, forKey: .hd)
        kairos = try? keyed.decodeIfPresent(YouVoiceKairosDTO.self, forKey: .kairos)
        gptLive = try? keyed.decodeIfPresent(YouVoiceGPTLiveDTO.self, forKey: .gptLive)
        elevenlabs = try? keyed.decodeIfPresent(YouVoiceElevenDTO.self, forKey: .elevenlabs)
        voicebox = try? keyed.decodeIfPresent(YouVoiceServerDTO.self, forKey: .voicebox)
        compatible = try? keyed.decodeIfPresent(YouVoiceServerDTO.self, forKey: .compatible)
    }
}

/// One saved pronunciation (core/pronunciations.py). `phonemes` is the desktop's own spelling of the sound; it is
/// sent back for a word the person did not touch, so the sound is kept.
nonisolated struct YouVoicePronDTO: Decodable, Sendable {
    var word: String
    var say: JSONValue?
    var phonemes: JSONValue?
}

/// GET and PUT /api/voice-engines/pronunciations: {"items": [...]}, read word by word.
nonisolated struct YouVoicePronListDTO: Decodable, Sendable {
    var items: [YouVoicePronDTO] = []
    var skipped = 0

    private enum Keys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        guard keyed.contains(.items), (try? keyed.decodeNil(forKey: .items)) == false else { return }
        var list = try keyed.nestedUnkeyedContainer(forKey: .items)
        while !list.isAtEnd {
            if let item = try? list.decode(YouVoicePronDTO.self) {
                items.append(item)
            } else {
                _ = try list.decode(JSONValue.self)
                skipped += 1
            }
        }
    }
}

nonisolated struct YouVoiceSpeechModelDTO: Decodable, Sendable {
    var name: String
    var label: JSONValue?
    var sizeMb: JSONValue?
    var downloaded: JSONValue?
}

nonisolated struct YouVoiceSpeechOptionalDTO: Decodable, Sendable {
    var name: String
    var label: JSONValue?
    var ready: JSONValue?
    var status: JSONValue?
}

/// GET /api/speech/status (core/speech.py: status): which listening models are on disk. Nothing in it is private.
nonisolated struct YouVoiceSpeechDTO: Decodable, Sendable {
    var engineAvailable: JSONValue?
    var activeModel: JSONValue?
    var models: [YouVoiceSpeechModelDTO] = []
    var optionalModels: [YouVoiceSpeechOptionalDTO] = []

    private enum Keys: String, CodingKey { case engineAvailable, activeModel, models, optionalModels = "optional" }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        engineAvailable = try? keyed.decodeIfPresent(JSONValue.self, forKey: .engineAvailable)
        activeModel = try? keyed.decodeIfPresent(JSONValue.self, forKey: .activeModel)
        if keyed.contains(.models), (try? keyed.decodeNil(forKey: .models)) == false,
           var list = try? keyed.nestedUnkeyedContainer(forKey: .models) {
            while !list.isAtEnd {
                if let item = try? list.decode(YouVoiceSpeechModelDTO.self) {
                    models.append(item)
                } else {
                    _ = try list.decode(JSONValue.self)
                }
            }
        }
        if keyed.contains(.optionalModels), (try? keyed.decodeNil(forKey: .optionalModels)) == false,
           var list = try? keyed.nestedUnkeyedContainer(forKey: .optionalModels) {
            while !list.isAtEnd {
                if let item = try? list.decode(YouVoiceSpeechOptionalDTO.self) {
                    optionalModels.append(item)
                } else {
                    _ = try list.decode(JSONValue.self)
                }
            }
        }
    }
}

/// GET /api/models/free-voice: {"configured": bool, ...}. The key is never in it.
nonisolated struct YouVoiceFreeVoiceDTO: Decodable, Sendable {
    var configured: JSONValue?
}

/// GET and PUT /api/bot-voice/live-settings: {"voice", "read_typed", "idle_minutes"}.
nonisolated struct YouVoiceBotVoiceDTO: Decodable, Sendable {
    var voice: JSONValue?
    var readTyped: JSONValue?
    var idleMinutes: JSONValue?
}

// MARK: - Reach me

nonisolated struct YouVoiceChannelRow: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var ready: Bool
}

/// One bot's own choice. Nil is "your order"; an empty list is "never".
nonisolated struct YouVoiceBotWay: Hashable, Sendable {
    var message: [String]?
    var call: [String]?

    var isEmpty: Bool { message == nil && call == nil }
}

nonisolated struct YouVoiceLogLine: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String
    var delivered: Bool
}

/// What GET /api/reach-me answers (services/reach_me.py: view), as the phone uses it. The way each channel is
/// reached (its detail text can name a number or an address) is left out.
nonisolated struct YouVoiceReachView: Hashable, Sendable {
    var message: [String]
    var call: [String]
    var quietEnabled: Bool
    var quietStart: String
    var quietEnd: String
    var quietNow: Bool
    var bots: [String: YouVoiceBotWay]
    var isPaused: Bool
    var pausedAt: Date?
    /// "settings" for the switch, or the channel a STOP came in on.
    var pausedBy: String?
    var messageChannels: [YouVoiceChannelRow]
    var callChannels: [YouVoiceChannelRow]
    var log: [YouVoiceLogLine]
}

nonisolated enum YouVoiceReach {
    static func parse(_ data: Data) throws -> YouVoiceReachView {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.unreadable("reach me")
        }
        guard let message = names(root["message"]), let call = names(root["call"]) else { throw APIError.unreadable("reach me orders") }
        let quiet = root["quiet"] as? [String: Any] ?? [:]
        var bots: [String: YouVoiceBotWay] = [:]
        for (id, value) in (root["bots"] as? [String: Any]) ?? [:] {
            guard let entry = value as? [String: Any] else { continue }
            let way = YouVoiceBotWay(message: names(entry["message"]), call: names(entry["call"]))
            if !way.isEmpty { bots[id] = way }
        }
        let messageChannels = channels(root["message_channels"])
        let callChannels = channels(root["call_channels"])
        let labels = Dictionary((messageChannels + callChannels).map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        var paused: [String: Any]?
        if let state = root["paused"] as? [String: Any] { paused = state }
        var log: [YouVoiceLogLine] = []
        for (index, value) in ((root["log"] as? [Any]) ?? []).enumerated() {
            if let entry = value as? [String: Any] { log.append(logLine(entry, index: index, labels: labels)) }
        }
        return YouVoiceReachView(
            message: message, call: call,
            quietEnabled: (quiet["enabled"] as? Bool) ?? false,
            quietStart: (quiet["start"] as? String) ?? "22:00", quietEnd: (quiet["end"] as? String) ?? "07:00",
            quietNow: (root["quiet_now"] as? Bool) ?? false, bots: bots,
            isPaused: paused != nil,
            pausedAt: (paused?["at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
            pausedBy: paused?["by"] as? String,
            messageChannels: messageChannels, callChannels: callChannels, log: log)
    }

    /// A list of text, or nil when it is missing or not a list of text (null is "no value").
    private static func names(_ value: Any?) -> [String]? {
        guard let list = value as? [Any] else { return nil }
        let text = list.compactMap { $0 as? String }
        return text.count == list.count ? text : nil
    }

    private static func channels(_ value: Any?) -> [YouVoiceChannelRow] {
        ((value as? [Any]) ?? []).compactMap { item in
            guard let row = item as? [String: Any], let id = row["id"] as? String else { return nil }
            return YouVoiceChannelRow(id: id, label: (row["label"] as? String) ?? id, ready: (row["ready"] as? Bool) ?? false)
        }
    }

    /// One line of the log. A phone number shows only its last four digits; what looks secret is masked.
    private static func logLine(_ entry: [String: Any], index: Int, labels: [String: String]) -> YouVoiceLogLine {
        let call = (entry["kind"] as? String) == "call"
        let name = ((entry["bot_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }) ?? "A bot"
        let delivered = (entry["ok"] as? Bool) ?? false
        let channel = entry["channel"] as? String
        var title: String
        if delivered {
            title = "\(name) \(call ? "called" : "messaged") you"
            if let channel { title += ": " + (labels[channel] ?? channel) } else { title += ": waiting" }
        } else {
            title = "\(name) tried to \(call ? "call" : "message") you: not delivered"
        }
        var detail: [String] = []
        let at = (entry["at"] as? NSNumber)?.doubleValue
        if let at, let when = YouVoiceWire.time(at) { detail.append(when.formatted(date: .abbreviated, time: .shortened)) }
        if let note = entry["note"] as? String, !note.isEmpty { detail.append(YouVoiceWire.safe(note)) }
        for item in ((entry["tried"] as? [Any]) ?? []) {
            guard let tried = item as? [String: Any], let id = tried["channel"] as? String else { continue }
            let reason = (tried["reason"] as? String).map { ": " + YouVoiceWire.safe($0) } ?? ""
            detail.append("skipped \(labels[id] ?? id)" + reason)
        }
        return YouVoiceLogLine(id: "\(at ?? 0)|\(index)", title: YouVoiceWire.safe(title), detail: String(detail.joined(separator: " · ").prefix(300)),
                               delivered: delivered)
    }
}

// MARK: - Wire helpers

nonisolated enum YouVoiceWire {
    static let botVoices = ["marin", "cedar", "coral", "sage", "ash"]

    /// The host of an address, or nil. Never the user, password, port, path or query.
    static func host(_ address: String?) -> String? {
        guard let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else { return nil }
        let host = URLComponents(string: address)?.host
        return (host?.isEmpty == false) ? host : nil
    }

    /// Text with every web address cut down to its host, so a failure never repeats a server address in full.
    static func hostsOnly(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9+.\-]*://[^\s'"<>)\]]+"#) else { return text }
        let whole = text as NSString
        var out = ""
        var at = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: whole.length)) {
            out += whole.substring(with: NSRange(location: at, length: match.range.location - at))
            out += host(whole.substring(with: match.range)) ?? "an address"
            at = match.range.location + match.range.length
        }
        return out + whole.substring(from: at)
    }

    /// A phone number (seven digits or more, with spaces, dots, brackets or dashes between) shows its last four.
    /// A date or an IPv4 address is left as it is.
    static func phoneMasked(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\+?\d[\d\s().\-]{5,}\d"#) else { return text }
        let whole = text as NSString
        var out = ""
        var at = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: whole.length)) {
            out += whole.substring(with: NSRange(location: at, length: match.range.location - at))
            let run = whole.substring(with: match.range)
            let digits = run.filter(\.isNumber)
            let plain = run.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
                || run.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
            out += (digits.count >= 7 && !plain) ? "•••• " + digits.suffix(4) : run
            at = match.range.location + match.range.length
        }
        return out + whole.substring(from: at)
    }

    /// Free text from the desktop, made safe to show: addresses to hosts, numbers to their last four, secrets masked.
    static func safe(_ text: String) -> String {
        phoneMasked(youAccessMasked(hostsOnly(text)))
    }

    /// The desktop sends 0 for a time it does not have, so anything before the year 2000 is not known.
    static func time(_ seconds: Double) -> Date? {
        YouAccessWire.known(Date(timeIntervalSince1970: seconds))
    }

    /// A connection id (12 hex on the desktop) goes into the path as it is; anything that could leave the path is refused.
    static func modelID(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 80,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else {
            throw YouVoiceNotSent(plain: "This model's id could not be read, so nothing was sent.")
        }
        return id
    }

    /// An HD voice id (lower-case letters, as core/hd_voice.py: VOICE_IDS).
    static func hdVoiceID(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 20, id.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) else {
            throw YouVoiceNotSent(plain: "This voice's id could not be read, so nothing was sent.")
        }
        return id
    }

    /// A bot id as core/reach_me.py: save accepts it.
    static func botID(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 80,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "." || $0 == ":" || $0 == "-" }) else {
            throw YouVoiceNotSent(plain: "This bot's id could not be read, so nothing was sent.")
        }
        return id
    }

    /// "07:00" as the desktop keeps a quiet hour.
    static func clock(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    static func clockText(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// One bot's choices as the PUT sends them.
    static func botsBody(_ bots: [String: YouVoiceBotWay]) throws -> [String: Any] {
        var body: [String: Any] = [:]
        for (id, way) in bots {
            var entry: [String: Any] = [:]
            if let message = way.message { entry["message"] = message }
            if let call = way.call { entry["call"] = call }
            if !entry.isEmpty { body[try botID(id)] = entry }
        }
        return body
    }
}

// MARK: - Calls

extension APIClient {

    /// Any call whose answer is read from the raw bytes (a dictionary keyed by an id, or a file).
    private func youVoiceRaw(_ method: String, _ path: String, json: [String: Any]? = nil, timeout: TimeInterval? = nil) async throws -> Data {
        var request = try urlRequest(method, path)
        if let json {
            guard JSONSerialization.isValidJSONObject(json) else { throw APIError.unreadable("request") }
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let timeout { request.timeoutInterval = timeout }
        return try await send(request)
    }

    func youVoiceModels() async throws -> YouVoiceModelListDTO {
        try await get("/api/models")
    }

    func youVoiceModelStats() async throws -> [String: YouVoiceStat] {
        try YouVoiceStats.parse(try await youVoiceRaw("GET", "/api/models/stats"))
    }

    /// POST /api/models/{id}/test: one tiny model turn on the desktop. A CLI can take a while.
    func youVoiceTest(_ id: String) async throws -> YouVoiceTestDTO {
        let data = try await youVoiceRaw("POST", "/api/models/" + YouVoiceWire.modelID(id) + "/test", timeout: 90)
        do {
            return try KJSON.decode(YouVoiceTestDTO.self, from: data)
        } catch {
            throw APIError.unreadable("model test")
        }
    }

    /// PATCH /api/models/{id}/image-support: the connection as the desktop now has it.
    func youVoiceSetImages(_ id: String, _ on: Bool) async throws -> YouVoiceModelDTO {
        try await request("PATCH", "/api/models/" + YouVoiceWire.modelID(id) + "/image-support", json: ["enabled": on])
    }

    func youVoiceSettings() async throws -> YouVoiceSettingsDTO {
        try await get("/api/settings")
    }

    func youVoiceSetAutoCompact(_ on: Bool) async throws -> YouVoiceSettingsDTO {
        try await post("/api/settings/auto-compact", json: ["enabled": on])
    }

    /// POST /api/settings/helpers: nil is automatic, "off" is off, else a local or API connection's id.
    func youVoiceSetHelpers(_ choice: String?) async throws -> YouVoiceSettingsDTO {
        var body: [String: Any] = [:]
        if let choice { body["endpoint_id"] = try YouVoiceWire.modelID(choice) } else { body["endpoint_id"] = NSNull() }
        return try await post("/api/settings/helpers", json: body)
    }

    func youVoiceEngines() async throws -> YouVoiceEngineStateDTO {
        try await get("/api/voice-engines")
    }

    func youVoiceSetChoice(_ choice: String) async throws -> YouVoiceEngineStateDTO {
        try await request("PUT", "/api/voice-engines/choice", json: ["choice": choice])
    }

    func youVoiceSetQuality(_ quality: String) async throws -> YouVoiceEngineStateDTO {
        try await request("PUT", "/api/voice-engines/quality", json: ["quality": quality])
    }

    func youVoiceSetHDVoice(_ voice: String) async throws -> YouVoiceEngineStateDTO {
        try await request("PUT", "/api/voice-engines/hd/voice", json: ["voice": try YouVoiceWire.hdVoiceID(voice)])
    }

    /// POST /api/voice-engines/hd/preview: a short WAV the phone plays itself. The first one loads the model.
    func youVoiceHDPreview(_ voice: String) async throws -> Data {
        try await youVoiceRaw("POST", "/api/voice-engines/hd/preview", json: ["voice": try YouVoiceWire.hdVoiceID(voice)], timeout: 60)
    }

    func youVoicePronunciations() async throws -> YouVoicePronListDTO {
        try await get("/api/voice-engines/pronunciations")
    }

    /// PUT /api/voice-engines/pronunciations: replaces the whole list. Each row: word, say, and phonemes ("" when the
    /// desktop should work them out from the respelling).
    func youVoiceSavePronunciations(_ rows: [(word: String, say: String, phonemes: String)]) async throws -> YouVoicePronListDTO {
        let items: [[String: Any]] = rows.map { ["word": $0.word, "say": $0.say, "phonemes": $0.phonemes] }
        return try await request("PUT", "/api/voice-engines/pronunciations", json: ["items": items])
    }

    func youVoiceSpeech() async throws -> YouVoiceSpeechDTO {
        try await get("/api/speech/status")
    }

    func youVoiceFreeVoice() async throws -> YouVoiceFreeVoiceDTO {
        try await get("/api/models/free-voice")
    }

    func youVoiceBotVoice() async throws -> YouVoiceBotVoiceDTO {
        try await get("/api/bot-voice/live-settings")
    }

    /// PUT /api/bot-voice/live-settings with all three values (a missing one would be reset to its default).
    func youVoiceSetBotVoice(voice: String, readTyped: Bool, idleMinutes: Int) async throws -> YouVoiceBotVoiceDTO {
        try await request("PUT", "/api/bot-voice/live-settings",
                          json: ["voice": voice, "read_typed": readTyped, "idle_minutes": idleMinutes])
    }

    func youVoiceReach() async throws -> YouVoiceReachView {
        try YouVoiceReach.parse(try await youVoiceRaw("GET", "/api/reach-me"))
    }

    /// PUT /api/reach-me with only the parts that changed. Quiet hours and the bots are replaced whole.
    func youVoiceSaveReach(_ patch: [String: Any]) async throws -> YouVoiceReachView {
        try YouVoiceReach.parse(try await youVoiceRaw("PUT", "/api/reach-me", json: patch))
    }

    func youVoiceSetPaused(_ paused: Bool) async throws -> YouVoiceReachView {
        try YouVoiceReach.parse(try await youVoiceRaw("POST", "/api/reach-me/pause", json: ["paused": paused]))
    }
}

// MARK: - Samples

/// A sample answer for every route above, shaped like the desktop's own (made-up content).
nonisolated enum YouVoiceSamples {

    static let models = #"""
    [
      {"id": "a1b2c3d4e5f6", "name": "Claude", "base_url": "", "model": "", "has_api_key": false, "kind": "claude_cli",
       "num_ctx": null, "supports_images": true, "realtime_provider": null, "realtime_model": null, "free_tier": false, "mark": "claude"},
      {"id": "0f1e2d3c4b5a", "name": "Qwen local", "base_url": "http://127.0.0.1:11434/v1", "model": "qwen3:8b", "has_api_key": false,
       "kind": "local", "num_ctx": 4096, "supports_images": false},
      {"id": "112233445566", "name": "OpenRouter", "base_url": "https://user:notreal@openrouter.example/api/v1?x=1", "model": "deepseek/chat",
       "has_api_key": true, "kind": "api", "num_ctx": null, "supports_images": true},
      {"id": "665544332211", "name": "Shop OpenAI", "base_url": "", "model": "gpt-4.1-mini", "has_api_key": false, "kind": "api",
       "num_ctx": null, "supports_images": false, "shared": true, "shared_by": "bike-shop"},
      {"name": "A connection with no id"}
    ]
    """#

    static let stats = #"""
    {"days": 7, "since": 1792400000, "min_samples": 5, "source": "runs",
     "endpoints": {
       "0f1e2d3c4b5a": {"endpoint_id": "0f1e2d3c4b5a", "runs": 24, "enough_data": true, "failed": 1, "stopped": 2,
                        "ttft_median_s": 0.9, "tokens_per_second_median": 41.6},
       "112233445566": {"runs": 3, "enough_data": false, "failed": 0, "stopped": 0, "ttft_median_s": null},
       "a1b2c3d4e5f6": {"runs": 9, "enough_data": true, "failed": 0, "stopped": 0, "ttft_median_s": 12.4, "tokens_per_second_median": null}
     },
     "models": []}
    """#

    static let settings = #"""
    {"onboarding_complete": true, "vault_dir": "/home/example/vault", "disabled_tools": [], "auto_compact": true,
     "computer_use": {"enabled": true}, "computer_steps_days": 7, "helper_endpoint_id": null,
     "helper_endpoint": {"id": "0f1e2d3c4b5a", "name": "Qwen local", "kind": "local"}, "ring_preference": "app"}
    """#

    static let helpersSaved = #"""
    {"ok": true, "helper_endpoint_id": "off", "helper_endpoint": null}
    """#

    static let test = #"""
    {"ok": false, "detail": "Could not reach http://100.64.0.12:11434/v1/chat/completions after 3 tries"}
    """#

    static let testOK = #"{"ok": true, "latency_ms": 412}"#

    static let engines = #"""
    {"choice": "kairos", "notice": "", "quality": "standard", "hd_voice": "iris",
     "hd": {"offered": true, "nvidia": true, "reason": "", "card": "Example GPU", "installed": true, "ready": true,
            "not_ready_reason": "", "state": "ready", "progress": {}, "partial_bytes": 0, "voices": [
              {"id": "iris", "name": "Iris", "description": "Warm female voice."}, {"id": "ryan", "name": "Ryan"}, {"name": "No id"}],
            "default_voice": "iris", "running": false, "sources": []},
     "kairos": {"kokoro_ready": true, "kokoro_reason": ""},
     "gpt_live": {"available": true, "endpoint_id": "112233445566", "price_per_minute": 0.05, "key_page": "https://example.com/keys", "verified": false},
     "elevenlabs": {"has_key": false, "key_page": "https://example.com/keys", "models": ["m1"], "price_per_1k": 0.2, "verified": false},
     "voicebox": {"url": "http://127.0.0.1:17493", "repo": "https://example.com/repo", "verified": false},
     "compatible": {"url": "", "voices": []}}
    """#

    static let pronunciations = #"""
    {"items": [{"word": "Siobhan", "say": "shi-VAWN", "phonemes": "ʃɪvˈɔːn"}, {"word": "Kairos", "say": "KY-ross", "phonemes": "kˈIɹɑs"},
               {"say": "no word"}]}
    """#

    static let speech = #"""
    {"vc_runtime": {}, "engine_available": true, "active_model": "base.en",
     "models": [{"name": "tiny.en", "label": "Tiny", "size_mb": 75, "downloaded": false},
                {"name": "base.en", "label": "Base", "size_mb": 142, "downloaded": true}, {"label": "no name"}],
     "optional": [{"name": "smart-turn", "label": "Smart Turn", "state": "ready", "status": "Ready", "ready": true},
                  {"name": "kokoro", "label": "Kokoro voice", "state": "not_downloaded", "status": "Not downloaded", "ready": false}],
     "turn_detect": {"ready": true}, "call_model": "small.en"}
    """#

    static let freeVoice = #"{"configured": true, "endpoint_id": "112233445566", "model": "gemini-live", "key_page": "https://example.com/key"}"#

    static let botVoice = #"{"voice": "cedar", "read_typed": false, "idle_minutes": 5}"#

    static let reach = #"""
    {"message": ["app", "telegram"], "call": ["app"], "quiet": {"enabled": true, "start": "22:00", "end": "07:30"},
     "bots": {"ledger_bot": {"message": [], "call": null}, "scout.1": {"message": ["telegram"]}, "empty": {}},
     "paused": null, "stops": [], "quiet_now": false,
     "message_channels": [
       {"id": "app", "label": "In the Kairos app", "ready": true, "detail": "Notifications on 1 device."},
       {"id": "telegram", "label": "Telegram", "ready": true, "detail": "Sends to 123456789 through \"Home\"."},
       {"id": "sms", "label": "SMS text", "ready": false, "detail": "Texts +15555550123."}],
     "call_channels": [
       {"id": "phone", "label": "Phone call", "ready": false, "detail": "Needs a Phone connection."},
       {"id": "app", "label": "Ring in the Kairos app", "ready": true, "detail": "Rings any open window."}],
     "log": [
       {"at": 1793000000, "kind": "message", "bot_id": "scout", "bot_name": "Scout", "ok": true, "channel": "telegram", "note": "",
        "tried": [{"channel": "app", "reason": "this iPhone was offline"}]},
       {"at": 1793000500, "kind": "call", "bot_id": "ledger", "bot_name": "Ledger", "ok": false, "channel": null,
        "note": "could not call +1 (555) 555-0123", "tried": [{"channel": "phone", "reason": "line busy at +15555550123"}]},
       "odd row"]}
    """#

    static let reachPaused = #"""
    {"message": [], "call": [], "quiet": {"enabled": false, "start": "22:00", "end": "07:00"}, "bots": {},
     "paused": {"at": 1793000000, "channel": "telegram", "by": "reply"}, "quiet_now": false,
     "message_channels": [], "call_channels": [], "log": []}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("youvoice.models") {
            let read = try KJSON.decode(YouVoiceModelListDTO.self, from: YouVoiceSamples.models)
            guard read.models.count == 4, read.skipped == 1 else { throw SampleMismatch("model rows") }
            let stats = try YouVoiceStats.parse(Data(YouVoiceSamples.stats.utf8))
            let rows = YouVoiceLive.modelRows(from: read, stats: stats)
            guard rows.count == 4, rows[0].kind == .claudeCLI, rows[0].acceptsImages,
                  rows[1].kind == .local, rows[1].host == "127.0.0.1", rows[1].contextWindow == 4096, rows[1].isSmallWindow,
                  !rows[1].hasKey, rows[2].hasKey, rows[2].host == "openrouter.example", rows[2].canToggleImages,
                  rows[3].sharedBy == "bike-shop", !rows[3].canToggleImages, rows[3].host.isEmpty,
                  rows[2].details == "deepseek/chat · openrouter.example · key saved",
                  rows[0].details == "Model: CLI default" else { throw SampleMismatch("model shaping") }
            return "4 connections, 1 skipped, host only, key yes or no"
        },
        DecodeCheck("youvoice.stats") {
            let stats = try YouVoiceStats.parse(Data(YouVoiceSamples.stats.utf8))
            guard stats.count == 3, let local = stats["0f1e2d3c4b5a"], local.runs == 24, local.enoughData,
                  YouVoiceStats.line(local) == "Last 7 days: first output 0.9 s · 42 tok/s · 1 failed of 24 · 2 stopped",
                  YouVoiceStats.line(stats["112233445566"]!) == "Not enough data yet: 3 runs in the last 7 days",
                  YouVoiceStats.line(stats["a1b2c3d4e5f6"]!) == "Last 7 days: first output 12 s · none failed of 9",
                  YouVoiceStats.line(YouVoiceStat(runs: 0, enoughData: false, failed: 0, stopped: 0, firstOutputSeconds: nil, tokensPerSecond: nil)) == nil
            else { throw SampleMismatch("stats") }
            return "3 stats, lines in words"
        },
        DecodeCheck("youvoice.settings") {
            let read = try KJSON.decode(YouVoiceSettingsDTO.self, from: YouVoiceSamples.settings)
            let off = try KJSON.decode(YouVoiceSettingsDTO.self, from: YouVoiceSamples.helpersSaved)
            guard read.autoCompact?.bool == true, read.helperEndpointId?.isNull ?? true,
                  YouVoiceLive.helperValue(read) == "auto", YouVoiceLive.helperValue(off) == "off" else { throw SampleMismatch("settings") }
            return "auto-compact, helper automatic and off"
        },
        DecodeCheck("youvoice.test") {
            let bad = try KJSON.decode(YouVoiceTestDTO.self, from: YouVoiceSamples.test)
            let good = try KJSON.decode(YouVoiceTestDTO.self, from: YouVoiceSamples.testOK)
            let words = YouVoiceLive.testFailure(bad)
            guard bad.ok?.bool == false, good.ok?.bool == true, good.latencyMs?.int == 412,
                  !words.contains("100.64.0.12:11434"), !words.contains("/v1/chat"), words.contains("100.64.0.12") else {
                throw SampleMismatch("test answer")
            }
            return "ok, failed with a host only"
        },
        DecodeCheck("youvoice.engines") {
            let read = try KJSON.decode(YouVoiceEngineStateDTO.self, from: YouVoiceSamples.engines)
            let state = YouVoiceLive.enginesState(from: read)
            guard state.choice == "kairos", state.quality == "standard", state.hdVoice == "iris",
                  state.kokoroReady == true, state.gptAvailable, state.gptPrice == 0.05, !state.elevenHasKey,
                  state.hdInstalled, state.hdReady, state.hdVoices.map(\.id) == ["iris", "ryan"],
                  state.serverHost == nil else { throw SampleMismatch("engines") }
            var server = read
            server.choice = .string("voicebox")
            guard YouVoiceLive.enginesState(from: server).serverHost == "127.0.0.1" else { throw SampleMismatch("server host") }
            guard (try? YouVoiceWire.hdVoiceID("iris")) != nil, (try? YouVoiceWire.hdVoiceID("../x")) == nil else {
                throw SampleMismatch("voice id guard")
            }
            return "choice, quality, HD ready, 2 voices, host only"
        },
        DecodeCheck("youvoice.pronunciations") {
            let read = try KJSON.decode(YouVoicePronListDTO.self, from: YouVoiceSamples.pronunciations)
            let items = YouVoiceLive.pronItems(from: read)
            guard items.count == 2, read.skipped == 1, items[0].word == "Siobhan", items[0].say == "shi-VAWN",
                  items[0].phonemes == "ʃɪvˈɔːn" else { throw SampleMismatch("pronunciations") }
            let rows = items.map(YouVoiceLive.pronRow)
            let same = YouVoiceLive.sameList(items, items)
            var edited = items
            edited[1].say = "KAI-ross"
            guard rows.map(\.id) == ["w:siobhan", "w:kairos"], same, !YouVoiceLive.sameList(items, edited) else {
                throw SampleMismatch("pronunciation rows")
            }
            return "2 words, 1 skipped, same list and changed list told apart"
        },
        DecodeCheck("youvoice.speech") {
            let read = try KJSON.decode(YouVoiceSpeechDTO.self, from: YouVoiceSamples.speech)
            let free = try KJSON.decode(YouVoiceFreeVoiceDTO.self, from: YouVoiceSamples.freeVoice)
            guard read.engineAvailable?.bool == true, read.activeModel?.string == "base.en", read.models.count == 2,
                  read.optionalModels.count == 2, read.optionalModels[0].ready?.bool == true,
                  read.optionalModels[1].status?.string == "Not downloaded", free.configured?.bool == true else {
                throw SampleMismatch("speech")
            }
            return "2 listening models, 2 optional, free voice on"
        },
        DecodeCheck("youvoice.botvoice") {
            let read = try KJSON.decode(YouVoiceBotVoiceDTO.self, from: YouVoiceSamples.botVoice)
            guard let setting = YouVoiceLive.botSetting(read), setting.voice == "cedar", !setting.readTyped, setting.idleMinutes == 5 else {
                throw SampleMismatch("bot voice")
            }
            let odd = try KJSON.decode(YouVoiceBotVoiceDTO.self, from: #"{"voice": "marin", "read_typed": "no"}"#)
            guard YouVoiceLive.botSetting(odd) == nil else { throw SampleMismatch("odd bot voice") }
            return "one setting, odd answer refused"
        },
        DecodeCheck("youvoice.reach") {
            let view = try YouVoiceReach.parse(Data(YouVoiceSamples.reach.utf8))
            guard view.message == ["app", "telegram"], view.call == ["app"], view.quietEnabled, view.quietStart == "22:00",
                  view.quietEnd == "07:30", !view.isPaused, view.messageChannels.count == 3, view.callChannels.count == 2,
                  !view.callChannels[0].ready, view.callChannels[1].ready else { throw SampleMismatch("reach basics") }
            // "your order" is no value, "never" is an empty list.
            guard view.bots.count == 2, view.bots["ledger_bot"]?.message == [], view.bots["ledger_bot"]?.call == nil,
                  view.bots["scout.1"]?.message == ["telegram"], view.bots["empty"] == nil else { throw SampleMismatch("reach bots") }
            guard view.log.count == 2, view.log[0].delivered, view.log[0].title == "Scout messaged you: Telegram",
                  view.log[0].detail.contains("skipped In the Kairos app: this iPhone was offline"),
                  !view.log[1].delivered, view.log[1].title == "Ledger tried to call you: not delivered",
                  !view.log[1].detail.contains("5555550123"), !view.log[1].detail.contains("555-0123"),
                  view.log[1].detail.contains("•••• 0123") else { throw SampleMismatch("reach log") }
            let paused = try YouVoiceReach.parse(Data(YouVoiceSamples.reachPaused.utf8))
            guard paused.isPaused, paused.pausedBy == "reply", paused.pausedAt != nil, paused.message.isEmpty else {
                throw SampleMismatch("reach paused")
            }
            let body = try YouVoiceWire.botsBody(view.bots)
            guard (body["ledger_bot"] as? [String: Any])?["message"] as? [String] == [],
                  (body["ledger_bot"] as? [String: Any])?["call"] == nil, (try? YouVoiceWire.botsBody(["a/b": YouVoiceBotWay(message: [], call: nil)])) == nil
            else { throw SampleMismatch("bots body") }
            return "orders, quiet hours, bots (never is empty), log with numbers cut, paused"
        },
        DecodeCheck("youvoice.guards") {
            guard YouVoiceWire.host("https://user:notreal@openrouter.example:8443/api?x=1") == "openrouter.example",
                  YouVoiceWire.host("") == nil, YouVoiceWire.host("not an address") == nil,
                  YouVoiceWire.hostsOnly("see https://a.example/x/y?k=v and http://10.0.0.5:80/z now") == "see a.example and 10.0.0.5 now",
                  YouVoiceWire.phoneMasked("call +1 (555) 555-0123 now") == "call •••• 0123 now",
                  YouVoiceWire.phoneMasked("until 07:00 on 3 tries") == "until 07:00 on 3 tries",
                  YouVoiceWire.clock("07:05")?.minute == 5, YouVoiceWire.clock("7:5") == nil, YouVoiceWire.clock("24:00") == nil,
                  YouVoiceWire.clockText(hour: 7, minute: 5) == "07:05" else { throw SampleMismatch("guards") }
            guard (try? YouVoiceWire.modelID("a/b")) == nil, (try? YouVoiceWire.modelID("0f1e2d3c4b5a")) != nil,
                  (try? YouVoiceWire.botID("scout.1")) != nil, (try? YouVoiceWire.botID("a b")) == nil else {
                throw SampleMismatch("id guards")
            }
            return "host only, numbers cut, clock, ids"
        },
    ]
}
