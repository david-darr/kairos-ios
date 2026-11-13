import Foundation

// A call with a bot, in the desktop's local mode: plain requests and streamed lines (NDJSON), never the paid
// realtime socket. Every shape here is copied from the desktop: routes/call_routes.py, services/agent_calls.py,
// routes/speech_routes.py, core/call_voices.py, and the web client's callDefaults.js, callVoice.js, voiceInput.js,
// voiceOutput.js and backchannel.js, which are the reference behaviour.

// MARK: - Replies

/// One row of GET /api/agent-calls/choices (agent_calls.py: choices): a connection a call can talk through.
nonisolated struct CallChoiceDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
    var model: String?
    /// "api", "local", "claude_cli", "codex_cli" or "antigravity_cli".
    var kind: String?
    var slower: Bool?
    /// Measured median time to first output, in seconds, when Kairos has one.
    var firstOutputS: Double?
}

nonisolated struct CallVoiceDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
}

/// GET /api/agent-calls/voices (core/call_voices.py: catalog): the account's Voice engine and what it offers.
/// `error` set, or no voices or no models, means the engine cannot speak and the device voice is used.
nonisolated struct CallVoiceCatalogDTO: Decodable, Hashable, Sendable {
    var choice: String?
    var url: String?
    var `protocol`: String?
    var voices: [CallVoiceDTO]?
    var models: [String]?
    var error: String?
}

nonisolated struct SpeechModelDTO: Decodable, Hashable, Sendable {
    var name: String
    var label: String?
    var sizeMb: Double?
    var downloaded: Bool?
}

nonisolated struct SpeechTurnDetectDTO: Decodable, Hashable, Sendable {
    var ready: Bool?
}

/// GET /api/speech/status (core/speech.py: status).
nonisolated struct SpeechStatusDTO: Decodable, Hashable, Sendable {
    var engineAvailable: Bool?
    var activeModel: String?
    var models: [SpeechModelDTO]?
    var callModel: String?
    var turnDetect: SpeechTurnDetectDTO?
}

/// POST /api/speech/prepare (speech_routes.py: prepare_speech).
nonisolated struct SpeechPrepareDTO: Decodable, Hashable, Sendable {
    var model: String?
    /// "cuda" or "cpu".
    var engine: String?
    var fallback: String?
    var prepareMs: Int?
}

/// POST /api/speech/transcribe with a model (speech_routes.py: transcribe).
nonisolated struct SpeechTranscriptDTO: Decodable, Hashable, Sendable {
    var text: String?
    var engine: String?
}

/// POST /api/speech/turn (speech_routes.py: end_of_turn): has the speaker finished the sentence?
nonisolated struct SpeechTurnDTO: Decodable, Hashable, Sendable {
    var available: Bool?
    var complete: Bool?
    var probability: Double?
}

nonisolated struct CallJobDTO: Decodable, Hashable, Sendable {
    var taskId: String
    var title: String?
    /// The task's status: "ready" and "running" are still going.
    var status: String?
}

/// The call record (agent_calls.py: view): POST /api/agent-calls, GET /api/agent-calls/{id}, POST .../end.
nonisolated struct CallRecordDTO: Decodable, Hashable, Sendable {
    var id: String
    var parentId: String?
    var agentId: String?
    var ended: Bool?
    var summaryState: String?
    var liveError: String?
    var jobs: [CallJobDTO]?
}

/// GET /api/bot-voice/live-settings (services/bot_voice.py: live_settings): a call with nothing said for this
/// many minutes is hung up.
nonisolated struct CallLiveSettingsDTO: Decodable, Hashable, Sendable {
    var idleMinutes: Int?
}

/// One streamed line of a call route, as one loose shape. Read `type` first:
/// - turn, opening and work update (agent_calls.py: turn, announce): "text" (`delta`, `firstOutputMs`), "speaker"
///   (`id`, `name`), "job" (`job`), "notice" (`message`), "done" (`text`, `replyMs`), "error" (`message`).
/// - watch (agent_calls.py: watch_events): "ready", "ping", "work" (`taskId`, `status`), "typed" (`text`),
///   "end" (`reason`).
/// - speak (call_routes.py: speak) has no type: `sampleRate`, `audio` (base64 PCM16 little-endian mono),
///   `done` true, or `error` text.
nonisolated struct CallLineDTO: Decodable, Hashable, Sendable {
    var type: String?
    var delta: String?
    var text: String?
    var message: String?
    var firstOutputMs: Int?
    var replyMs: Int?
    var id: String?
    var name: String?
    var taskId: String?
    var status: String?
    var reason: String?
    var job: JSONValue?
    var sampleRate: Double?
    var audio: String?
    var done: Bool?
    var error: String?
}

// MARK: - The routes

extension APIClient {
    /// GET /api/agent-calls/choices.
    func callChoices() async throws -> [CallChoiceDTO] {
        try await callJSON(try callRequest("GET", "/api/agent-calls/choices", timeout: 20))
    }

    /// GET /api/agent-calls/voices.
    func callVoices() async throws -> CallVoiceCatalogDTO {
        try await callJSON(try callRequest("GET", "/api/agent-calls/voices", timeout: 20))
    }

    /// GET /api/speech/status.
    func speechStatus() async throws -> SpeechStatusDTO {
        try await callJSON(try callRequest("GET", "/api/speech/status", timeout: 20))
    }

    /// GET /api/bot-voice/live-settings.
    func callLiveSettings() async throws -> CallLiveSettingsDTO {
        try await callJSON(try callRequest("GET", "/api/bot-voice/live-settings", timeout: 15))
    }

    /// POST /api/agent-calls: open the call record. `ringID` (32 hex) makes the ring's reason the bot's opening.
    /// `model` nil lets a sign-in use its own default.
    func callStart(parentID: String, agentID: String, endpointID: String, model: String?, ringID: String?) async throws -> CallRecordDTO {
        var body: [String: Any] = ["parent_id": parentID, "agent_id": agentID, "endpoint_id": endpointID]
        if let model, !model.isEmpty { body["model"] = model } else { body["model"] = NSNull() }
        if let ringID { body["ring_id"] = ringID }
        return try await callJSON(try callRequest("POST", "/api/agent-calls", json: body, timeout: 30))
    }

    /// POST /api/agent-calls/{id}/prepare: load the conversation model before the first turn.
    func callPrepare(_ callID: String) async throws {
        _ = try await send(try callRequest("POST", "/api/agent-calls/\(callID)/prepare", timeout: 90))
    }

    /// POST /api/speech/prepare: load the speech model. `backend` is "auto" (GPU when set up) or "cpu".
    func speechPrepare(model: String, backend: String) async throws -> SpeechPrepareDTO {
        try await callJSON(try callRequest("POST", "/api/speech/prepare", json: ["model": model, "backend": backend], timeout: 90))
    }

    /// GET /api/agent-calls/{id}: the record, and the keep-alive (a call unseen for 90 seconds is ended).
    func callStatus(_ callID: String) async throws -> CallRecordDTO {
        try await callJSON(try callRequest("GET", "/api/agent-calls/\(callID)", timeout: 10))
    }

    /// POST /api/agent-calls/{id}/end. Ending twice is harmless on the desktop.
    func callEnd(_ callID: String) async throws {
        _ = try await send(try callRequest("POST", "/api/agent-calls/\(callID)/end", timeout: 10))
    }

    /// POST /api/agent-calls/{id}/interrupt. `spoken`: the person talked over the reply. `heard`: the sentences
    /// that had begun to play, so the desktop keeps only those.
    func callInterrupt(_ callID: String, spoken: Bool, heard: [String]?) async throws {
        var body: [String: Any] = ["spoken": spoken]
        if let heard { body["heard"] = Array(heard.prefix(60)).map { String($0.prefix(1600)) } }
        _ = try await send(try callRequest("POST", "/api/agent-calls/\(callID)/interrupt", json: body, timeout: 10))
    }

    /// POST /api/speech/transcribe: one utterance as 16 kHz mono WAV, with the call's speech model.
    func speechTranscribe(wav: Data, model: String, backend: String) async throws -> SpeechTranscriptDTO {
        var request = try callRequest("POST", "/api/speech/transcribe", timeout: 60)
        let form = CallMultipart.body(file: wav, fileName: "speech.wav", fields: [("model", model), ("backend", backend)])
        request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.data
        return try await callJSON(request)
    }

    /// POST /api/speech/turn: is this pause the end of a sentence? Asked with a short timeout; late is no answer.
    func speechTurn(wav: Data, timeout: Double) async throws -> SpeechTurnDTO {
        var request = try callRequest("POST", "/api/speech/turn", timeout: timeout)
        let form = CallMultipart.body(file: wav, fileName: "turn.wav", fields: [])
        request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.data
        return try await callJSON(request)
    }

    /// A streamed call route, line by line: /turn, /opening, /work/{task}/update, /watch and /speak.
    /// `idle` is the longest wait for the next bytes; `limit` caps the whole stream.
    func callLines(_ path: String, json: [String: Any], idle: Double, limit: Double) throws -> AsyncThrowingStream<Data, Error> {
        var request = try callRequest("POST", path, json: json, timeout: idle)
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        return CallStreams.lines(request, limit: limit)
    }

    private func callRequest(_ method: String, _ path: String, json: [String: Any]? = nil, timeout: Double) throws -> URLRequest {
        var request = try urlRequest(method, path)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let json {
            guard JSONSerialization.isValidJSONObject(json) else { throw APIError.unreadable("request") }
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func callJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await send(request)
        do {
            return try KJSON.decode(T.self, from: data)
        } catch {
            throw APIError.unreadable(String(describing: error))
        }
    }
}

// MARK: - Streams

/// Streamed lines, read off the main actor. Each line is capped, and so is the whole stream.
nonisolated enum CallStreams {
    /// The longest one line may be (the web client's limit).
    static let lineLimit = 3_000_000

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// The lines of one streamed request. Ending the iteration (or cancelling its task) cancels the request.
    /// `limit` is the longest the whole stream may run, in seconds.
    static func lines(_ request: URLRequest, limit: Double) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let reader = Task {
                do {
                    try await read(request, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let clock = Task {
                try? await Task.sleep(for: .seconds(limit))
                guard !Task.isCancelled else { return }
                reader.cancel()
            }
            continuation.onTermination = { @Sendable _ in
                reader.cancel()
                clock.cancel()
            }
        }
    }

    private static func read(_ request: URLRequest, into continuation: AsyncThrowingStream<Data, Error>.Continuation) async throws {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.offline("Your desktop could not be reached. Try again in a moment.")
            }
            guard (200..<300).contains(http.statusCode) else {
                var body = Data()
                for try await byte in bytes {
                    body.append(byte)
                    if body.count >= 65_536 { break }
                }
                throw failure(status: http.statusCode, body: body)
            }
            var buffer = NDJSONLineBuffer()
            for try await byte in bytes {
                if let line = try buffer.append(byte) { continuation.yield(line) }
            }
            if let last = buffer.finish() { continuation.yield(last) }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError.from(error)
        }
    }

    static func failure(status: Int, body: Data) -> APIError {
        if status == 401 { return .unauthorized }
        let detail = (try? KJSON.decode(APIErrorBody.self, from: body))?.text ?? ""
        if detail.isEmpty, [502, 503, 504].contains(status) {
            return .offline("Your desktop did not answer. Check that Kairos is open and remote access is on.")
        }
        return .server(status: status, detail: detail)
    }
}

/// Cuts a byte stream into lines (NDJSON). Blank lines are skipped; a line over the limit is an error.
nonisolated struct NDJSONLineBuffer {
    private var line = Data()
    let limit: Int

    init(limit: Int = CallStreams.lineLimit) {
        self.limit = limit
    }

    /// One more byte. Returns a whole line when this byte ended one.
    mutating func append(_ byte: UInt8) throws -> Data? {
        if byte == 0x0A {
            let done = line
            line = Data()
            return Self.blank(done) ? nil : done
        }
        line.append(byte)
        if line.count > limit { throw APIError.unreadable("A call stream line was too long.") }
        return nil
    }

    /// Several bytes at once (the checks use this). Returns every line they completed.
    mutating func append(contentsOf bytes: Data) throws -> [Data] {
        var out: [Data] = []
        for byte in bytes { if let done = try append(byte) { out.append(done) } }
        return out
    }

    /// The stream ended: a last line with no newline after it.
    mutating func finish() -> Data? {
        let done = line
        line = Data()
        return Self.blank(done) ? nil : done
    }

    private static func blank(_ data: Data) -> Bool {
        data.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
    }
}

// MARK: - Audio formats

/// A form upload with one file under `audio` and plain text fields, as the speech routes read it.
nonisolated enum CallMultipart {
    static func body(file: Data, fileName: String, fields: [(String, String)]) -> (data: Data, boundary: String) {
        let boundary = "kairos-" + UUID().uuidString
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return (body, boundary)
    }
}

/// 16-bit PCM WAV, exactly as the web client writes it (voiceInput.js: encodeWav).
nonisolated enum CallWAV {
    static func encode(_ samples: [Float], rate: Int) -> Data {
        var data = Data(capacity: 44 + samples.count * 2)
        func text(_ value: String) { data.append(Data(value.utf8)) }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        text("RIFF")
        u32(UInt32(36 + samples.count * 2))
        text("WAVE")
        text("fmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(rate))
        u32(UInt32(rate * 2))
        u16(2)
        u16(16)
        text("data")
        u32(UInt32(samples.count * 2))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let value = Int16(clamped < 0 ? clamped * 32768 : clamped * 32767)
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}

/// Base64 PCM16 little-endian mono as the speak route sends it, chunk by chunk. A chunk can end halfway through a
/// sample; that byte is carried into the next chunk, as callVoice.js does.
nonisolated struct PCM16Decoder {
    private var carry: UInt8?

    /// The chunk's whole samples as little-endian Int16 bytes (with any carried byte in front), or nil when the
    /// text is not base64.
    mutating func decode(_ base64: String) -> Data? {
        guard let raw = Data(base64Encoded: base64) else { return nil }
        var bytes = Data(capacity: raw.count + 1)
        if let carry { bytes.append(carry) }
        bytes.append(raw)
        if bytes.count % 2 == 1 {
            carry = bytes.last
            bytes.removeLast()
        } else {
            carry = nil
        }
        return bytes
    }

    /// A byte is left over at the end of the stream: the audio was cut short.
    var incomplete: Bool { carry != nil }

    static func floats(_ bytes: Data) -> [Float] {
        var out = [Float](repeating: 0, count: bytes.count / 2)
        bytes.withUnsafeBytes { raw in
            for index in 0..<out.count {
                let low = UInt16(raw[index * 2])
                let high = UInt16(raw[index * 2 + 1])
                out[index] = Float(Int16(bitPattern: low | (high << 8))) / 32768
            }
        }
        return out
    }
}

// MARK: - The choices a call starts with (callDefaults.js)

/// How the call speaks: the account's Voice engine, or this iPhone's own voice when that engine is not ready.
nonisolated enum CallVoiceChoice: Equatable, Sendable {
    case neural(model: String, voice: String)
    case device
}

nonisolated enum CallDefaults {
    private static let cliKinds: Set<String> = ["claude_cli", "codex_cli", "antigravity_cli"]
    private static let kindOrder: [String: Int] = ["api": 0, "claude_cli": 1, "local": 2, "codex_cli": 3, "antigravity_cli": 4]

    /// The model version a call can send for this connection, or nil when it cannot be used. A sign-in may send ""
    /// (Claude Code then talks on Haiku); an API or local connection needs one.
    static func usableModel(_ choice: CallChoiceDTO, wanted: String) -> String? {
        let model = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        let own = (choice.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = choice.kind ?? ""
        if kind == "claude_cli" { return model }
        if cliKinds.contains(kind) { return model.isEmpty ? own : model }
        let picked = model.isEmpty ? own : model
        return picked.isEmpty ? nil : picked
    }

    /// The conversation model (pickConversation, with nothing saved on this phone): the bot's own connection, else
    /// the quickest one Kairos measured, then by kind. A connection marked slower is skipped while another can be used.
    static func conversation(_ choices: [CallChoiceDTO], botEndpoint: String?, botModel: String?) -> (endpoint: String, model: String)? {
        let fast = choices.filter { $0.slower != true && usableModel($0, wanted: "") != nil }
        if let botEndpoint, let own = choices.first(where: { $0.id == botEndpoint }), own.slower != true || fast.isEmpty {
            if let model = usableModel(own, wanted: own.kind == "claude_cli" ? "" : (botModel ?? "")) {
                return (own.id, model)
            }
        }
        let pool = fast.isEmpty ? choices.filter { usableModel($0, wanted: "") != nil } : fast
        let ranked = pool.enumerated().sorted { a, b in
            let left = a.element.firstOutputS ?? .infinity, right = b.element.firstOutputS ?? .infinity
            if left != right { return left < right }
            let leftKind = kindOrder[a.element.kind ?? ""] ?? 9, rightKind = kindOrder[b.element.kind ?? ""] ?? 9
            if leftKind != rightKind { return leftKind < rightKind }
            return a.offset < b.offset
        }
        guard let best = ranked.first?.element, let model = usableModel(best, wanted: "") else { return nil }
        return (best.id, model)
    }

    /// The speech model (pickSpeechModel): an already downloaded one, the call default first. The phone never starts
    /// a download; nil means speech is not set up.
    static func speechModel(_ status: SpeechStatusDTO) -> String? {
        guard status.engineAvailable == true else { return nil }
        let ready = (status.models ?? []).filter { $0.downloaded == true }
        let preferred = status.callModel ?? "small.en"
        return (ready.first(where: { $0.name == preferred }) ?? ready.first)?.name
    }

    /// The voice (pickVoice, with nothing saved on this phone): the bot's own voice, else the engine's default voice,
    /// else this iPhone's voice when the engine is not ready.
    static func voice(_ catalog: CallVoiceCatalogDTO?, botVoice: String?) -> CallVoiceChoice {
        let voices = catalog?.voices ?? []
        let models = catalog?.models ?? []
        guard let catalog, catalog.error == nil, let model = models.first, let first = voices.first else { return .device }
        if let botVoice, voices.contains(where: { $0.id == botVoice }) { return .neural(model: model, voice: botVoice) }
        return .neural(model: model, voice: (voices.first(where: { $0.id == "default" }) ?? first).id)
    }
}

// MARK: - Listener noises (backchannel.js)

nonisolated enum Backchannel {
    private static let noises: Set<String> = ["mm", "mmm", "mhm", "mmhm", "mm-hm", "mm-hmm", "mmhmm", "hm", "hmm", "uh-huh", "uhhuh",
                                              "uh", "um", "ah", "aha", "oh", "ooh", "huh"]
    private static let acks: Set<String> = ["yeah", "yep", "yup", "yes", "right", "okay", "ok", "sure", "alright", "gotcha", "cool",
                                            "nice", "interesting", "wow", "exactly", "true", "absolutely", "really", "indeed",
                                            "totally", "definitely", "correct", "great", "good", "fine", "kay"]
    private static let phrases = ["uh huh", "mm hm", "mm hmm", "got it", "i see", "go on", "makes sense", "fair enough", "i get it", "sounds good"]
    private static let takesTheFloor: Set<String> = ["no", "nope", "wait", "stop", "hold", "actually", "but", "however", "sorry", "pause",
                                                     "what", "why", "how", "when", "where", "who", "can", "could", "would", "please",
                                                     "don't", "dont", "not", "never"]
    private static let nodUnits = Set(phrases.map { $0.replacingOccurrences(of: " ", with: "-") })
    private static let noiseUnits = Set(phrases.prefix(3).map { $0.replacingOccurrences(of: " ", with: "-") })

    private static func words(_ text: String) -> [String] {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789'- ")
        var cleaned = String(text.lowercased().map { allowed.contains($0) ? $0 : " " })
        cleaned = " " + cleaned.split(whereSeparator: { $0 == " " }).joined(separator: " ") + " "
        for phrase in phrases {
            cleaned = cleaned.replacingOccurrences(of: " " + phrase + " ", with: " " + phrase.replacingOccurrences(of: " ", with: "-") + " ")
        }
        return cleaned.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-'")) }.filter { !$0.isEmpty }
    }

    /// True when `text` is only listener noises. `asked`: the bot's last spoken sentence was a question.
    static func isBackchannel(_ text: String, asked: Bool) -> Bool {
        let list = words(text)
        guard !list.isEmpty, list.count <= 5 else { return false }
        if list.contains(where: { takesTheFloor.contains($0) }) { return false }
        let fits: (String) -> Bool = { word in
            asked ? noises.contains(word) || noiseUnits.contains(word)
                : noises.contains(word) || acks.contains(word) || nodUnits.contains(word)
        }
        guard list.allSatisfy(fits) else { return false }
        return Set(list).count <= 3
    }

    /// Did the last sentence the person heard end in a question?
    static func endsInQuestion(_ sentences: [String]) -> Bool {
        let last = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.last ?? ""
        return last.range(of: #"\?["')\]]*$"#, options: .regularExpression) != nil
    }
}

// MARK: - Sentences to speak (voiceOutput.js)

/// Cuts a streamed reply into sentences as it arrives: every finished sentence goes at once, and the first may go at
/// a clause break after about six words, so the bot starts speaking sooner.
nonisolated struct SentenceChunker {
    private var buffer = ""
    private var flushedFirst = false

    private static let sentenceEnd = try! NSRegularExpression(pattern: #"(?<=[.!?])\s+(?=[A-Z0-9"'])"#)
    private static let abbreviation = try! NSRegularExpression(pattern:
        #"(?:\b(?:Mr|Mrs|Ms|Mx|Dr|Prof|Sr|Jr|St|Mt|Ave|Blvd|Dept|Gen|Col|Lt|Sgt|Capt|Rep|Sen|Gov|Hon|Rev|vs|Inc|Ltd|Co|Corp|Fig|approx|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)|\b(?!I\.)[A-Z]|\b[A-Za-z]\.[A-Za-z]|\be\.g|\bi\.e)\.$"#)
    private static let clauseBreak = try! NSRegularExpression(pattern: #"[,;](?=\s)|\s+-{1,2}\s+|\s*[—–]\s*"#)
    private static let endsSentence = try! NSRegularExpression(pattern: #"[.!?]["')\]]?\s*$"#)
    private static let endsInNumber = try! NSRegularExpression(pattern: #"\d\.\s*$"#)

    var started: Bool { flushedFirst }

    mutating func feed(_ text: String) -> [String] {
        buffer += text
        var out: [String] = []
        while true {
            let ns = buffer as NSString
            let match = Self.nextSentenceEnd(buffer)
            let clause = flushedFirst ? nil : Self.firstClauseEnd(buffer)
            if let clause, match == nil || clause.length <= match!.location + 1 {
                buffer = ns.substring(from: clause.length)
                if !clause.head.isEmpty { out.append(clause.head); flushedFirst = true }
                continue
            }
            guard let match else { break }
            let sentence = ns.substring(to: match.location + 1).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = ns.substring(from: match.location + match.length)
            if !sentence.isEmpty { out.append(sentence); flushedFirst = true }
        }
        return out
    }

    mutating func finish() -> [String] {
        let leftover = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard !leftover.isEmpty else { return [] }
        flushedFirst = true
        return [leftover]
    }

    /// A buffer that already ends like a sentence goes now, without waiting for the next word.
    mutating func flushSentence() -> [String] {
        let trimmedEnd = buffer.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        guard Self.matches(Self.endsSentence, buffer), !Self.matches(Self.abbreviation, trimmedEnd),
              !Self.matches(Self.endsInNumber, buffer) else { return [] }
        let sentence = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard !sentence.isEmpty else { return [] }
        flushedFirst = true
        return [sentence]
    }

    mutating func reset() {
        buffer = ""
        flushedFirst = false
    }

    private static func matches(_ pattern: NSRegularExpression, _ text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func nextSentenceEnd(_ text: String) -> NSRange? {
        let ns = text as NSString
        for match in sentenceEnd.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if !matches(abbreviation, ns.substring(to: match.range.location)) { return match.range }
        }
        return nil
    }

    private static func firstClauseEnd(_ text: String) -> (head: String, length: Int)? {
        let ns = text as NSString
        for match in clauseBreak.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let found = ns.substring(with: match.range)
            let keep = (found.hasPrefix(",") || found.hasPrefix(";")) ? 1 : 0
            let head = ns.substring(to: match.range.location + keep).trimmingCharacters(in: .whitespacesAndNewlines)
            if head.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count >= 6 {
                return (head, match.range.location + match.range.length)
            }
        }
        return nil
    }
}

/// Markdown is written to be read, not heard (voiceOutput.js: forSpeech). The desktop strips it again for its own
/// voices; this keeps the phone's own voice from reading symbols aloud.
nonisolated enum SpokenText {
    static let codeLine = "I've put the code in the chat."

    private static let patterns: [(String, String, NSRegularExpression.Options)] = [
        (#"```[\s\S]*?(?:```|$)"#, "\n" + codeLine + "\n", []),
        (#"!\[[^\]]*\]\([^)]*\)"#, " ", []),
        (#"\[([^\]]+)\]\([^)]*\)"#, "$1", []),
        (#"https?://\S+|www\.\S+"#, "a link", []),
        (#"</?[A-Za-z][^>]*>"#, " ", []),
        (#"^\s*(?:[-*_=]{3,}|\|?[\s:|-]{3,}\|?)\s*$"#, "", [.anchorsMatchLines]),
        (#"^\s{0,3}#{1,6}\s+"#, "", [.anchorsMatchLines]),
        (#"^\s*>\s?"#, "", [.anchorsMatchLines]),
        (#"^\s*(?:[-*+•]|\d{1,3}[.)])\s+"#, "", [.anchorsMatchLines]),
        (#"`([^`\n]+)`"#, "$1", []),
        (#"(\*\*|__|~~|\*|(?<!\w)_|_(?!\w))"#, "", []),
        (#"\|"#, " ", []),
    ]
    private static let rules: [(NSRegularExpression, String)] = patterns.map { rule in
        (try! NSRegularExpression(pattern: rule.0, options: rule.2), rule.1)
    }
    private static let lineEnd = try! NSRegularExpression(pattern: #"[.!?:;,…]['")\]]*$"#)
    private static let repeats = try! NSRegularExpression(pattern: #"(?:\s*I've put the code in the chat\.){2,}"#)

    static func clean(_ text: String) -> String {
        var out = text
        for (pattern, template) in rules {
            out = pattern.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: template)
        }
        var lines = out.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count > 1 {
            lines = lines.map { line in
                lineEnd.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil ? line : line + "."
            }
        }
        out = lines.joined(separator: " ")
        out = repeats.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: " " + codeLine)
        return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

// MARK: - Checks (no test target: the debug view runs these)

nonisolated enum CallSamples {
    static let checks: [DecodeCheck] = [
        DecodeCheck("calls.record") { try checkRecord() },
        DecodeCheck("calls.choices") { try checkChoices() },
        DecodeCheck("calls.voices") { try checkVoices() },
        DecodeCheck("calls.speech") { try checkSpeech() },
        DecodeCheck("calls.lines") { try checkLines() },
        DecodeCheck("calls.speak") { try checkSpeak() },
        DecodeCheck("calls.wav") { try checkWAV() },
        DecodeCheck("calls.segments") { try checkSegments() },
        DecodeCheck("calls.smartTurn") { try checkSmartTurn() },
        DecodeCheck("calls.bargeIn") { try checkBargeIn() },
        DecodeCheck("calls.backchannel") { try checkBackchannel() },
        DecodeCheck("calls.sentences") { try checkSentences() },
    ]

    static func checkRecord() throws -> String {
        let json = """
        {"id": "0123456789abcdef0123456789abcdef", "parent_id": "s_bikeshop", "agent_id": "scout", "room_id": null,
         "members": null, "ended": false, "summary_state": "open", "summary_error": null, "summary": "",
         "started_at": 1767225600.5, "mode": "local", "live_error": null, "live_finalized": null, "live_usage": null,
         "realtime": null, "jobs": [{"task_id": "t1", "title": "Order brake pads", "key": "r1", "status": "running",
         "result": ""}], "latency": null}
        """
        let record = try KJSON.decode(CallRecordDTO.self, from: json)
        guard record.ended == false, record.jobs?.first?.taskId == "t1", record.jobs?.first?.status == "running",
              record.parentId == "s_bikeshop" else { throw SampleMismatch("record fields") }
        let live = try KJSON.decode(CallLiveSettingsDTO.self, from: #"{"voice": "marin", "read_typed": false, "idle_minutes": 7}"#)
        guard live.idleMinutes == 7 else { throw SampleMismatch("idle minutes") }
        return "record, jobs and idle minutes"
    }

    static func checkChoices() throws -> String {
        let json = """
        [{"id": "e_cli", "name": "Claude Code", "model": "", "kind": "claude_cli", "slower": false, "first_output_s": null},
         {"id": "e_api", "name": "Hosted", "model": "fast-1", "kind": "api", "slower": false, "first_output_s": 0.9},
         {"id": "e_local", "name": "On this PC", "model": "small-7b", "kind": "local", "slower": false, "first_output_s": 0.4},
         {"id": "e_codex", "name": "Codex", "model": "", "kind": "codex_cli", "slower": true, "first_output_s": null}]
        """
        let choices = try KJSON.decode([CallChoiceDTO].self, from: json)
        guard choices.count == 4, choices[2].firstOutputS == 0.4 else { throw SampleMismatch("choices decode") }
        guard let quickest = CallDefaults.conversation(choices, botEndpoint: nil, botModel: nil),
              quickest.endpoint == "e_local", quickest.model == "small-7b" else { throw SampleMismatch("quickest connection") }
        guard let own = CallDefaults.conversation(choices, botEndpoint: "e_api", botModel: "fast-2"),
              own.endpoint == "e_api", own.model == "fast-2" else { throw SampleMismatch("the bot's own connection") }
        guard let cli = CallDefaults.conversation(choices, botEndpoint: "e_cli", botModel: "ignored"),
              cli.endpoint == "e_cli", cli.model == "" else { throw SampleMismatch("a sign-in sends no version") }
        guard let slowOwn = CallDefaults.conversation(choices, botEndpoint: "e_codex", botModel: nil),
              slowOwn.endpoint == "e_local" else { throw SampleMismatch("a slower connection is skipped") }
        guard CallDefaults.conversation([], botEndpoint: nil, botModel: nil) == nil else { throw SampleMismatch("no connection") }
        return "4 connections, 5 picks"
    }

    static func checkVoices() throws -> String {
        let ready = try KJSON.decode(CallVoiceCatalogDTO.self, from: """
        {"choice": "kairos", "url": "kokoro://local", "protocol": "kokoro",
         "voices": [{"id": "af_one", "name": "One"}, {"id": "default", "name": "Default"}], "models": ["kokoro"]}
        """)
        let missing = try KJSON.decode(CallVoiceCatalogDTO.self, from: """
        {"choice": "kairos", "url": "", "protocol": "kokoro", "voices": [], "models": [],
         "error": "Kokoro is not downloaded. The device voice is used instead."}
        """)
        guard CallDefaults.voice(ready, botVoice: nil) == .neural(model: "kokoro", voice: "default"),
              CallDefaults.voice(ready, botVoice: "af_one") == .neural(model: "kokoro", voice: "af_one"),
              CallDefaults.voice(ready, botVoice: "gone") == .neural(model: "kokoro", voice: "default"),
              CallDefaults.voice(missing, botVoice: "af_one") == .device,
              CallDefaults.voice(nil, botVoice: nil) == .device else { throw SampleMismatch("voice picks") }
        return "ready engine, missing engine"
    }

    static func checkSpeech() throws -> String {
        let status = try KJSON.decode(SpeechStatusDTO.self, from: """
        {"vc_runtime": {"ok": true}, "optional": {}, "turn_detect": {"ready": true, "reason": "", "threshold": 0.5},
         "engine_available": true, "active_model": "base.en",
         "models": [{"name": "tiny.en", "label": "Tiny", "size_mb": 75, "downloaded": false},
                    {"name": "base.en", "label": "Base", "size_mb": 142, "downloaded": true},
                    {"name": "small.en", "label": "Small", "size_mb": 466, "downloaded": false}],
         "call_model": "small.en", "acceleration": {"supported": false, "configured": false}}
        """)
        guard status.turnDetect?.ready == true, CallDefaults.speechModel(status) == "base.en" else {
            throw SampleMismatch("speech model pick")
        }
        var none = status
        none.models = status.models?.map { var model = $0; model.downloaded = false; return model }
        guard CallDefaults.speechModel(none) == nil else { throw SampleMismatch("no downloaded model") }
        var off = status
        off.engineAvailable = false
        guard CallDefaults.speechModel(off) == nil else { throw SampleMismatch("no engine") }
        let prepared = try KJSON.decode(SpeechPrepareDTO.self, from: #"{"model": "base.en", "engine": "cpu", "fallback": null, "prepare_ms": 812}"#)
        let heard = try KJSON.decode(SpeechTranscriptDTO.self, from: #"{"text": "Is the shop open Friday?", "model": "base.en", "engine": "cpu", "timings": {"queue_ms": 0}}"#)
        let turn = try KJSON.decode(SpeechTurnDTO.self, from: #"{"available": true, "complete": false, "probability": 0.21}"#)
        guard prepared.prepareMs == 812, heard.text == "Is the shop open Friday?", turn.complete == false else {
            throw SampleMismatch("prepare, transcript or turn")
        }
        return "status, prepare, transcript, turn"
    }

    static func checkLines() throws -> String {
        var buffer = NDJSONLineBuffer(limit: 200)
        var lines: [Data] = []
        lines += try buffer.append(contentsOf: Data(#"{"type":"text","delta":"Hi, ","first_output_ms":420}"#.utf8))
        lines += try buffer.append(contentsOf: Data("\n\n{\"type\":\"te".utf8))
        lines += try buffer.append(contentsOf: Data("xt\",\"delta\":\"the shop opens at nine.\"}\r\n".utf8))
        lines += try buffer.append(contentsOf: Data(#"{"type":"done","text":"Hi, the shop opens at nine.","reply_ms":1300}"#.utf8))
        if let last = buffer.finish() { lines.append(last) }
        let events = try lines.map { try KJSON.decode(CallLineDTO.self, from: $0) }
        guard events.count == 3, events[0].firstOutputMs == 420, events[1].delta == "the shop opens at nine.",
              events[2].type == "done", events[2].replyMs == 1300 else { throw SampleMismatch("turn lines") }
        let watch = try [#"{"type": "work", "task_id": "t1", "status": "done"}"#, #"{"type": "typed", "text": "(typed) and Saturday?"}"#,
                         #"{"type": "end", "reason": "answered"}"#, #"{"type": "job", "job": {"task_id": "t2", "title": "Check stock", "key": "r2"}}"#]
            .map { try KJSON.decode(CallLineDTO.self, from: $0) }
        guard watch[0].taskId == "t1", watch[1].text == "(typed) and Saturday?", watch[2].reason == "answered",
              (watch[3].job?["task_id"] ?? watch[3].job?["taskId"])?.string == "t2" else { throw SampleMismatch("watch lines") }
        var tight = NDJSONLineBuffer(limit: 8)
        do {
            _ = try tight.append(contentsOf: Data("0123456789".utf8))
            throw SampleMismatch("an over-long line was not refused")
        } catch is APIError {}
        return "split lines, blank lines, watch events, line cap"
    }

    static func checkSpeak() throws -> String {
        // Three samples (0, 16384, -32768) split across two chunks in the middle of a sample.
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x40, 0x00, 0x80]
        let first = Data(bytes[0..<3]).base64EncodedString(), second = Data(bytes[3...]).base64EncodedString()
        let lines = [#"{"sample_rate": 24000}"#, "{\"audio\": \"\(first)\"}", "{\"audio\": \"\(second)\"}", #"{"done": true}"#]
        let events = try lines.map { try KJSON.decode(CallLineDTO.self, from: $0) }
        guard events[0].sampleRate == 24000, events[3].done == true else { throw SampleMismatch("speak events") }
        var decoder = PCM16Decoder()
        var samples: [Float] = []
        for event in events {
            guard let audio = event.audio else { continue }
            guard let chunk = decoder.decode(audio) else { throw SampleMismatch("base64") }
            samples += PCM16Decoder.floats(chunk)
        }
        guard samples == [0, 0.5, -1], !decoder.incomplete else { throw SampleMismatch("PCM16 was \(samples)") }
        let failed = try KJSON.decode(CallLineDTO.self, from: #"{"error": "Voice playback failed. Check the local voice engine and selected profile."}"#)
        guard failed.error?.isEmpty == false else { throw SampleMismatch("speak error") }
        return "rate, carried byte, 3 samples, error"
    }

    static func checkWAV() throws -> String {
        let wav = CallWAV.encode([0, 1, -1, 2], rate: 16000)
        let expected: [UInt8] = Array("RIFF".utf8) + [44, 0, 0, 0] + Array("WAVEfmt ".utf8) + [16, 0, 0, 0, 1, 0, 1, 0,
            0x80, 0x3E, 0, 0, 0x00, 0x7D, 0, 0, 2, 0, 16, 0] + Array("data".utf8) + [8, 0, 0, 0,
            0x00, 0x00, 0xFF, 0x7F, 0x00, 0x80, 0xFF, 0x7F]
        guard Array(wav) == expected else { throw SampleMismatch("WAV bytes were \(Array(wav))") }
        return "44-byte header, 4 clamped samples"
    }

    /// Alternating samples of one level, in 128-sample blocks as the recorder feeds them.
    static func blocks(level: Float, seconds: Double) -> [[Float]] {
        let count = Int(seconds * 16000) / 128
        return (0..<count).map { _ in (0..<128).map { $0.isMultiple(of: 2) ? level : -level } }
    }

    static func checkSegments() throws -> String {
        var segmenter = SpeechSegmenter()
        var events: [SpeechSegmenter.Event] = []
        for block in blocks(level: 0.001, seconds: 0.4) + blocks(level: 0.05, seconds: 0.8) + blocks(level: 0.001, seconds: 1.2) {
            events += segmenter.push(block).events
        }
        let starts = events.filter { if case .started = $0 { return true } else { return false } }.count
        let segments = events.compactMap { event -> (Int, Int)? in
            if case .segment(let pcm, let endpoint) = event { return (pcm.count, endpoint) }
            return nil
        }
        guard starts == 1, segments.count == 1, segments[0].1 == 704, segments[0].0 > 12_800, segments[0].0 < 22_000 else {
            throw SampleMismatch("starts \(starts), segments \(segments)")
        }
        // Speech that never stops is cut at 30 seconds.
        var long = SpeechSegmenter()
        var cut = 0
        for block in blocks(level: 0.001, seconds: 0.3) + blocks(level: 0.05, seconds: 31) {
            for event in long.push(block).events { if case .segment(let pcm, _) = event { cut = pcm.count } }
        }
        guard cut == 480_000 else { throw SampleMismatch("long speech cut at \(cut)") }
        // A click is not speech.
        var quiet = SpeechSegmenter()
        var clicked = 0
        for block in blocks(level: 0.001, seconds: 0.3) + blocks(level: 0.05, seconds: 0.03) + blocks(level: 0.001, seconds: 1) {
            clicked += quiet.push(block).events.count
        }
        guard clicked == 0 else { throw SampleMismatch("a click started speech") }
        return "one utterance ends 704 ms after speech, 30 s cap, a click ignored"
    }

    static func checkSmartTurn() throws -> String {
        var segmenter = SpeechSegmenter()
        segmenter.setSmartTurn(true)
        var asked: Int?
        var ended = false
        for block in blocks(level: 0.001, seconds: 0.3) + blocks(level: 0.05, seconds: 0.6) + blocks(level: 0.001, seconds: 0.3) {
            for event in segmenter.push(block).events {
                if case .pause(let id, let pcm) = event, !pcm.isEmpty { asked = id }
                if case .segment = event { ended = true }
            }
        }
        guard let asked, !ended else { throw SampleMismatch("no question at the pause, or ended too soon") }
        let answered = segmenter.answer(asked, complete: true)
        guard answered.contains(where: { if case .segment = $0 { return true } else { return false } }) else {
            throw SampleMismatch("a complete verdict did not end the turn")
        }
        return "asked at 200 ms, ended on a complete verdict"
    }

    static func checkBargeIn() throws -> String {
        var detector = BargeInDetector()
        detector.reset(ambient: 0.002)
        var duck = false, barge = false
        for block in blocks(level: 0.004, seconds: 0.2) + blocks(level: 0.1, seconds: 0.4) {
            switch detector.push(block).event {
            case .duck?: duck = true
            case .barge?: barge = true
            default: break
            }
        }
        guard duck, barge else { throw SampleMismatch("duck \(duck), barge \(barge)") }
        var nod = BargeInDetector()
        nod.reset(ambient: 0.002)
        var seen: [String] = []
        for block in blocks(level: 0.004, seconds: 0.2) + blocks(level: 0.1, seconds: 0.2) + blocks(level: 0.004, seconds: 0.5) {
            switch nod.push(block).event {
            case .duck?: seen.append("duck")
            case .clear?: seen.append("clear")
            case .barge?: seen.append("barge")
            case nil: break
            }
        }
        guard seen == ["duck", "clear"] else { throw SampleMismatch("a nod gave \(seen)") }
        return "talking over interrupts, a nod does not"
    }

    static func checkBackchannel() throws -> String {
        let cases: [(String, Bool, Bool)] = [
            ("Mm-hm.", false, true), ("yeah, got it", false, true), ("Yeah", true, false), ("mm", true, true),
            ("wait, no", false, false), ("yeah but what about Friday", false, false), ("okay okay okay okay okay okay", false, false),
        ]
        for (text, asked, wanted) in cases where Backchannel.isBackchannel(text, asked: asked) != wanted {
            throw SampleMismatch("\"\(text)\" asked \(asked) should be \(wanted)")
        }
        guard Backchannel.endsInQuestion(["Hello.", "Is Friday good?"]), !Backchannel.endsInQuestion(["Is it? Yes."]) else {
            throw SampleMismatch("question ending")
        }
        return "\(cases.count) cases, question ending"
    }

    static func checkSentences() throws -> String {
        var chunker = SentenceChunker()
        var out = chunker.feed("Hi there. Dr. Lee fixed the bike on Nov. 12 and it rides well. ")
        out += chunker.feed("It costs 3.5 dollars")
        out += chunker.finish()
        guard out == ["Hi there.", "Dr. Lee fixed the bike on Nov. 12 and it rides well.", "It costs 3.5 dollars"] else {
            throw SampleMismatch("sentences were \(out)")
        }
        var clause = SentenceChunker()
        let first = clause.feed("The shop opens at nine on most days, but on Friday it opens at ten. ")
        let rest = clause.finish()
        guard first == ["The shop opens at nine on most days,"], rest == ["but on Friday it opens at ten."] else {
            throw SampleMismatch("clause was \(first) then \(rest)")
        }
        var flush = SentenceChunker()
        _ = flush.feed("All done.")
        guard flush.flushSentence() == ["All done."] else { throw SampleMismatch("flush") }
        let spoken = SpokenText.clean("## Plan\n- **Order** pads\n- See [the list](https://example.com/x)\n```\ncode\n```")
        guard spoken == "Plan. Order pads. See the list. I've put the code in the chat." else {
            throw SampleMismatch("spoken text was \(spoken)")
        }
        return "abbreviations, clause, flush, markdown"
    }
}
