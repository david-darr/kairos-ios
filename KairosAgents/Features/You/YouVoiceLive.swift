import SwiftUI
import AVFoundation

/// Where one desktop read stands, for one plain sentence on screen.
nonisolated enum YouVoiceLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// The parts of You > Models, Voice, Bot call voice and Reach me that are read from the paired desktop, each on its own.
nonisolated enum YouVoicePart: Hashable, Sendable {
    case models, stats, settings, engines, pronunciations, speech, freeVoice, botVoice, reach
}

/// One model connection as the screen shows it. The key is only a yes or no, the address only its host.
nonisolated struct YouVoiceModel: Identifiable, Hashable, Sendable {
    let id: String
    /// What the desktop calls the kind: "api", "local", "claude_cli", "codex_cli", "antigravity_cli" (or a newer one).
    var rawKind: String
    var kind: ModelConnectionKind
    var name: String
    var model: String
    var host: String
    var hasKey: Bool
    var contextWindow: Int?
    var acceptsImages: Bool
    /// Set when another account shares this connection with you.
    var sharedBy: String?
    var speed: String?

    /// The desktop changes the image switch only on a connection of your own that is local or an API.
    var canToggleImages: Bool { sharedBy == nil && (rawKind == "local" || rawKind == "api") }

    var details: String {
        if sharedBy != nil { return model.isEmpty ? "CLI default" : model }
        if kind.isCLI { return "Model: \(model.isEmpty ? "CLI default" : model)" }
        var parts = [model, host]
        if hasKey { parts.append("key saved") }
        if kind == .local, let contextWindow { parts.append("context \(contextWindow)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var isSmallWindow: Bool { kind == .local && (contextWindow ?? 16384) < 8192 }
}

nonisolated enum YouVoiceTest: Hashable, Sendable {
    case testing
    case ok(Int)
    case failed(String)
    case unconfirmed(String)
}

nonisolated struct YouVoiceHDVoice: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
}

/// The Voice choice and quality as the desktop has them. No key and no server address is held here.
nonisolated struct YouVoiceEngines: Hashable, Sendable {
    /// "kairos", "gpt_live", "elevenlabs", "voicebox" or "compatible".
    var choice: String
    /// "standard" or "hd".
    var quality: String
    var hdVoice: String
    var kokoroReady: Bool?
    var kokoroReason: String
    /// An OpenAI connection that offers GPT-Live is already set up on the desktop.
    var gptAvailable: Bool
    var gptPrice: Double?
    /// The connection GPT-Live runs on, to be named before it is chosen.
    var gptEndpointID: String?
    /// An ElevenLabs key is already saved on the desktop (a yes or no).
    var elevenHasKey: Bool
    var elevenPrice: Double?
    /// The host of a voice server on the desktop's computer, when one is the Voice.
    var serverHost: String?
    var hdOffered: Bool
    var hdInstalled: Bool
    var hdReady: Bool
    var hdReason: String
    var hdVoices: [YouVoiceHDVoice]
}

nonisolated struct YouVoiceListenModel: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var sizeMb: Int?
    var downloaded: Bool
}

nonisolated struct YouVoiceOptionalState: Hashable, Sendable {
    var ready: Bool
    var status: String
}

nonisolated struct YouVoiceSpeech: Hashable, Sendable {
    var engineAvailable: Bool?
    var active: String?
    var models: [YouVoiceListenModel]
    var smartTurn: YouVoiceOptionalState?
}

nonisolated struct YouVoicePronItem: Hashable, Sendable {
    var word: String
    var say: String
    var phonemes: String
    /// The desktop marks the phonemes as typed by the person (not worked out from the respelling).
    var typed = false
}

/// One line of the pronunciation form. A word the desktop gave keeps its id (`w:` and the word in lower case) even when
/// the person retypes it; a new line gets `n:` and a fresh id.
nonisolated struct YouVoicePronRow: Identifiable, Hashable, Sendable {
    let id: String
    var word: String
    var say: String
    var phonemes: String
}

nonisolated struct YouVoiceBotSetting: Hashable, Sendable {
    var voice: String
    var readTyped: Bool
    var idleMinutes: Int
}

/// What the person changed in the bot call voice form since it was filled. Nil is "not touched".
nonisolated struct YouVoiceBotEdits: Hashable, Sendable {
    var voice: String?
    var readTyped: Bool?
    var idleMinutes: Int?

    var isEmpty: Bool { voice == nil && readTyped == nil && idleMinutes == nil }
}

/// What a save sent, shared by the closures of one change so a lost answer is judged against it.
private final class YouVoiceSentBox {
    var pron: [YouVoicePronItem] = []
    var pronFresh: [YouVoicePronItem]?
    var bot: YouVoiceBotSetting?
    var quiet: (enabled: Bool, start: String, end: String)?
}

private struct YouVoiceWords {
    var done: String
    var failed: String
}

/// The paired desktop behind You > Models, Voice, Bot call voice and Reach me. Unpaired, nothing here runs and every
/// screen shows its sample data. Paired, only small reversible preferences are sent: the image switch, long chats, the
/// helper model, the Voice choice, quality and HD voice (already installed), pronunciations, the one bot call voice and
/// Reach me. Nothing that adds or widens (a model, a share, a key, an address, a download) is ever sent, and no key,
/// password or token is read or kept here.
@Observable
final class YouVoiceLive {
    static let shared = YouVoiceLive()

    private(set) var loads: [YouVoicePart: YouVoiceLoad] = [:]
    private(set) var models: [YouVoiceModel] = []
    private(set) var skippedModels = 0
    private(set) var tests: [String: YouVoiceTest] = [:]
    private(set) var testingID: String?
    /// Connections whose last test got no answer: no second test (a second paid turn) until the models are read again.
    private(set) var testBlocked: Set<String> = []
    private(set) var autoCompact: Bool?
    /// "auto", "off" or a connection id; nil until read.
    private(set) var helperChoice: String?
    private(set) var engines: YouVoiceEngines?
    private(set) var speech: YouVoiceSpeech?
    private(set) var freeVoiceConfigured: Bool?
    /// The pronunciation form as the person has it, and the list it was FILLED from.
    private(set) var pronRows: [YouVoicePronRow] = []
    private(set) var pronFilled: [YouVoicePronItem] = []
    /// The desktop's list is not the one the form was filled from.
    private(set) var pronChanged = false
    private(set) var botVoiceFilled: YouVoiceBotSetting?
    private(set) var botEdits = YouVoiceBotEdits()
    private(set) var reach: YouVoiceReachView?
    /// The HD voice whose sample is loading or playing.
    private(set) var previewing: String?
    /// Changes on their way: "image:<id>", "autoCompact", "helper", "choice", "quality", "hdVoice", "pron", "botVoice",
    /// "message", "call", "quiet", "bots", "pause".
    private(set) var busy: Set<String> = []
    /// Changes the desktop did not confirm and that could not be checked. No second tap until a read shows them.
    private(set) var unconfirmed: [YouVoicePart: Set<String>] = [:]
    /// One plain sentence per part after a change that did not go through.
    var notice: [YouVoicePart: String] = [:]
    /// Parts the desktop refused for this account (403): the screen shows one plain line.
    private(set) var memberOnly: Set<YouVoicePart> = []

    @ObservationIgnored private var liveAccount = "sample"
    @ObservationIgnored private var reads: [YouVoicePart: Int] = [:]
    @ObservationIgnored private var writes: [YouVoicePart: Int] = [:]
    @ObservationIgnored private var writing: [YouVoicePart: Int] = [:]
    @ObservationIgnored private var stats: [String: YouVoiceStat] = [:]
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var sampleAudioOn = false

    private init() {}

    // MARK: The connection

    static var connectionKey: String { YouAccessLive.connectionKey }
    static var accountKey: String { YouAccessLive.accountKey }
    /// Paired: the screens show only what the desktop sends.
    static var isPaired: Bool { YouAccessLive.isPaired }

    private var isLive: Bool { Self.isPaired }

    private func stillLive(_ account: String) -> Bool {
        isLive && liveAccount == account && Self.accountKey == account
    }

    /// Drop everything read from another desktop or account.
    func followConnection() {
        let key = Self.accountKey
        guard key != liveAccount else { return }
        endSampleAudio()
        loads = [:]
        models = []
        skippedModels = 0
        tests = [:]
        testingID = nil
        testBlocked = []
        autoCompact = nil
        helperChoice = nil
        engines = nil
        speech = nil
        freeVoiceConfigured = nil
        pronRows = []
        pronFilled = []
        pronChanged = false
        botVoiceFilled = nil
        botEdits = YouVoiceBotEdits()
        reach = nil
        previewing = nil
        busy = []
        unconfirmed = [:]
        notice = [:]
        memberOnly = []
        reads = [:]
        writes = [:]
        writing = [:]
        stats = [:]
        liveAccount = key
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    func load(_ part: YouVoicePart) -> YouVoiceLoad? { loads[part] }

    private func ensureLive(_ account: String) throws {
        guard stillLive(account) else { throw YouVoiceNotSent(plain: "Your paired desktop changed. Try again.") }
    }

    // MARK: Reading

    func read(_ part: YouVoicePart) async {
        followConnection()
        guard isLive else { return }
        switch part {
        case .models:
            await read(part, "Your models could not be read.", fetch: { try await $0.youVoiceModels() }) { dto in
                self.skippedModels = dto.skipped
                self.testBlocked = []
                self.models = Self.modelRows(from: dto, stats: self.stats)
            }
        case .stats:
            await read(part, "The measured speeds could not be read.", fetch: { try await $0.youVoiceModelStats() }) { found in
                self.stats = found
                for index in self.models.indices {
                    self.models[index].speed = found[self.models[index].id].flatMap(YouVoiceStats.line)
                }
            }
        case .settings:
            await read(part, "The long chat and helper settings could not be read.", fetch: { try await $0.youVoiceSettings() }) { dto in
                self.autoCompact = dto.autoCompact?.bool
                self.helperChoice = Self.helperValue(dto)
            }
        case .engines:
            await read(part, "Your voice could not be read.", fetch: { try await $0.youVoiceEngines() }) { dto in
                self.engines = Self.enginesState(from: dto)
            }
        case .pronunciations:
            await read(part, "Your pronunciations could not be read.", fetch: { try await $0.youVoicePronunciations() }) { dto in
                self.showPronunciations(Self.pronItems(from: dto))
            }
        case .speech:
            await read(part, "The listening models could not be read.", fetch: { try await $0.youVoiceSpeech() }) { dto in
                self.speech = Self.speechState(from: dto)
            }
        case .freeVoice:
            await read(part, "The free Gemini key status could not be read.", fetch: { try await $0.youVoiceFreeVoice() }) { dto in
                self.freeVoiceConfigured = dto.configured?.bool
            }
        case .botVoice:
            await read(part, "The bot call voice could not be read.", fetch: { try await $0.youVoiceBotVoice() }) { dto in
                self.showBotVoice(Self.botSetting(dto))
            }
        case .reach:
            await read(part, "Your Reach me settings could not be read.", fetch: { try await $0.youVoiceReach() }) { view in
                self.reach = view
            }
        }
    }

    func readModels() async {
        await read(.models)
        await read(.stats)
        await read(.settings)
    }

    func readVoice() async {
        await read(.engines)
        // The paid-voice question names the connection GPT-Live runs on, so the models are read too.
        await read(.models)
        await read(.pronunciations)
        await read(.speech)
        await read(.freeVoice)
    }

    @discardableResult
    private func read<T>(_ part: YouVoicePart, _ failure: String, fetch: (APIClient) async throws -> T,
                         apply: (T) -> Void) async -> Bool {
        let account = liveAccount
        let mine = (reads[part] ?? 0) + 1
        reads[part] = mine
        if loads[part] != .loaded { loads[part] = .loading }
        for _ in 0..<3 {
            let before = writes[part] ?? 0
            do {
                let value = try await fetch(try liveClient())
                guard stillLive(account), mine == reads[part] else { return false }
                // A read never overwrites a change on its way: that change reads again when it ends.
                guard (writing[part] ?? 0) == 0 else { return false }
                guard before == (writes[part] ?? 0) else { continue }
                memberOnly.remove(part)
                apply(value)
                if unconfirmed[part]?.isEmpty == false {
                    unconfirmed[part] = nil
                    notice[part] = "Your desktop was checked again. What it has now is shown."
                }
                loads[part] = .loaded
                return true
            } catch {
                if error is CancellationError || Task.isCancelled { return false }
                // An answer for a pairing that has ended never changes the connection.
                guard stillLive(account) else { return false }
                Connection.shared.note(error)
                guard mine == reads[part] else { return false }
                if case .server(status: 403, _)? = error as? APIError {
                    memberOnly.insert(part)
                    loads[part] = .loaded
                    return false
                }
                loads[part] = .failed(failure + " " + error.plainWords)
                return false
            }
        }
        guard stillLive(account), mine == reads[part] else { return false }
        if loads[part] != .loaded { loads[part] = .failed(failure + " It kept changing while it was read. Try again.") }
        return false
    }

    // MARK: Shaping (also run by the decode checks)

    nonisolated static func modelRows(from dto: YouVoiceModelListDTO, stats: [String: YouVoiceStat]) -> [YouVoiceModel] {
        dto.models.map { item in
            let raw = item.kind?.string ?? "api"
            let kind: ModelConnectionKind = switch raw {
            case "claude_cli": .claudeCLI
            case "codex_cli": .codexCLI
            case "antigravity_cli": .antigravity
            case "local": .local
            default: .api
            }
            let name = item.name?.string ?? ""
            var sharedBy: String?
            if item.shared?.bool == true {
                let by = item.sharedBy?.string ?? ""
                sharedBy = by.isEmpty ? "another account" : by
            }
            return YouVoiceModel(id: item.id, rawKind: raw, kind: kind, name: name.isEmpty ? "A model" : name,
                                 model: item.model?.string ?? "", host: YouVoiceWire.host(item.baseUrl?.string) ?? "",
                                 hasKey: item.hasApiKey?.bool ?? false, contextWindow: item.numCtx?.int,
                                 acceptsImages: item.supportsImages?.bool ?? false, sharedBy: sharedBy,
                                 speed: stats[item.id].flatMap(YouVoiceStats.line))
        }
    }

    /// "auto" (no choice saved: the first local model), "off", or a connection id.
    nonisolated static func helperValue(_ dto: YouVoiceSettingsDTO) -> String {
        guard let id = dto.helperEndpointId?.string, !id.isEmpty else { return "auto" }
        return id
    }

    nonisolated static func testFailure(_ dto: YouVoiceTestDTO) -> String {
        let text = YouVoiceWire.safe((dto.detail?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        return text.isEmpty ? "No answer. Check that it is running on your desktop." : String(text.prefix(300))
    }

    nonisolated static func enginesState(from dto: YouVoiceEngineStateDTO) -> YouVoiceEngines {
        let choice = dto.choice?.string ?? "kairos"
        var host: String?
        if choice == "voicebox" { host = YouVoiceWire.host(dto.voicebox?.url?.string) }
        if choice == "compatible" { host = YouVoiceWire.host(dto.compatible?.url?.string) }
        return YouVoiceEngines(
            choice: choice, quality: dto.quality?.string ?? "standard", hdVoice: dto.hdVoice?.string ?? "iris",
            kokoroReady: dto.kairos?.kokoroReady?.bool, kokoroReason: dto.kairos?.kokoroReason?.string ?? "",
            gptAvailable: dto.gptLive?.available?.bool ?? false, gptPrice: dto.gptLive?.pricePerMinute?.double,
            gptEndpointID: dto.gptLive?.endpointId?.string,
            elevenHasKey: dto.elevenlabs?.hasKey?.bool ?? false, elevenPrice: dto.elevenlabs?.pricePer1k?.double,
            serverHost: host,
            hdOffered: dto.hd?.offered?.bool ?? false, hdInstalled: dto.hd?.installed?.bool ?? false,
            hdReady: dto.hd?.ready?.bool ?? false, hdReason: dto.hd?.notReadyReason?.string ?? "",
            hdVoices: (dto.hd?.voices ?? []).map { YouVoiceHDVoice(id: $0.id, name: $0.name?.string ?? $0.id.capitalized) })
    }

    nonisolated static func speechState(from dto: YouVoiceSpeechDTO) -> YouVoiceSpeech {
        let smart = dto.optionalModels.first { $0.name == "smart-turn" }
        return YouVoiceSpeech(
            engineAvailable: dto.engineAvailable?.bool, active: dto.activeModel?.string,
            models: dto.models.map {
                YouVoiceListenModel(id: $0.name, label: $0.label?.string ?? $0.name, sizeMb: $0.sizeMb?.int,
                                    downloaded: $0.downloaded?.bool ?? false)
            },
            smartTurn: smart.map { YouVoiceOptionalState(ready: $0.ready?.bool ?? false, status: $0.status?.string ?? "") })
    }

    nonisolated static func pronItems(from dto: YouVoicePronListDTO) -> [YouVoicePronItem] {
        dto.items.map {
            YouVoicePronItem(word: $0.word, say: $0.say?.string ?? "", phonemes: $0.phonemes?.string ?? "",
                             typed: $0.typed?.bool ?? false)
        }
    }

    /// What a save sends, row by row, the way the desktop's own page does: phonemes only for a word whose phonemes the
    /// person typed (the desktop marks it typed and the person did not change its respelling), with the respelling box
    /// empty; an empty value for every other row, so the desktop works the sound out from the respelling again and an
    /// untouched word is never turned into a typed one. `rows` are the form's lines with the id of the word each came from.
    nonisolated static func pronSend(_ rows: [(id: String, item: YouVoicePronItem)], filled: [YouVoicePronItem]) -> [YouVoicePronItem] {
        var was: [String: YouVoicePronItem] = [:]
        for item in filled where was["w:" + item.word.lowercased()] == nil { was["w:" + item.word.lowercased()] = item }
        return rows.map { row in
            if let before = was[row.id], before.typed, !before.phonemes.isEmpty, row.item.say == before.say {
                return YouVoicePronItem(word: row.item.word, say: "", phonemes: before.phonemes, typed: true)
            }
            return YouVoicePronItem(word: row.item.word, say: row.item.say, phonemes: "")
        }
    }

    /// The connection GPT-Live runs on, by name, when the models are read (and the person it is shared by).
    func gptLiveConnection() -> (name: String, sharedBy: String?)? {
        // The desktop names it "live:" plus the connection's id.
        guard let raw = engines?.gptEndpointID else { return nil }
        let id = raw.hasPrefix("live:") ? String(raw.dropFirst(5)) : raw
        guard let found = models.first(where: { $0.id == id }) else { return nil }
        return (found.name, found.sharedBy)
    }

    nonisolated static func pronRow(_ item: YouVoicePronItem) -> YouVoicePronRow {
        YouVoicePronRow(id: "w:" + item.word.lowercased(), word: item.word, say: item.say, phonemes: item.phonemes)
    }

    nonisolated static func sameList(_ first: [YouVoicePronItem], _ second: [YouVoicePronItem]) -> Bool {
        first == second
    }

    /// The bot call voice, or nil when the answer is not the three values (nothing is then sent back).
    nonisolated static func botSetting(_ dto: YouVoiceBotVoiceDTO) -> YouVoiceBotSetting? {
        guard let voice = dto.voice?.string, let readTyped = dto.readTyped?.bool, let idle = dto.idleMinutes?.int else { return nil }
        return YouVoiceBotSetting(voice: voice, readTyped: readTyped, idleMinutes: idle)
    }

    nonisolated static func engineTitle(_ choice: String) -> String {
        switch choice {
        case "gpt_live": "GPT-Live"
        case "elevenlabs": "ElevenLabs"
        case "voicebox", "compatible": "A voice server on your desktop"
        default: "Kairos Voice"
        }
    }

    // MARK: Writing

    private static func wasRefused(_ error: Error) -> Bool {
        if error is YouVoiceNotSent { return true }
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
    }

    private static func words(_ error: Error) -> String {
        (error as? YouVoiceNotSent)?.plain ?? YouVoiceWire.safe(error.plainWords)
    }

    /// Send one small change, once. It shows at once (`optimistic`); `send` makes the call; `check` reads the desktop
    /// and answers whether the change is there, used only when the answer was lost (nil: it cannot tell). Nothing is
    /// put back by hand and no second tap is offered blind: whatever happened, the part is read again afterwards and
    /// what the desktop really has is shown.
    private func write(_ part: YouVoicePart, key: String, words: YouVoiceWords,
                       optimistic: () -> Void,
                       send: (APIClient, String) async throws -> Void,
                       check: (APIClient) async throws -> Bool?,
                       done: () -> Void = {}) async {
        // The connection is checked before anything shows or is sent: a tap on a screen of another account or desktop
        // sends nothing (the old account's state is dropped, and the screen reads the new one).
        guard isLive else { return }
        guard Self.accountKey == liveAccount else {
            followConnection()
            return
        }
        guard !busy.contains(key), unconfirmed[part]?.contains(key) != true else { return }
        let account = liveAccount
        busy.insert(key)
        writing[part, default: 0] += 1
        notice[part] = nil
        optimistic()
        defer {
            if liveAccount == account {
                busy.remove(key)
                writing[part, default: 1] -= 1
                writes[part, default: 0] += 1
                Task { if self.stillLive(account) { await self.read(part) } }
            }
        }
        do {
            try ensureLive(account)
            let client = try liveClient()
            try ensureLive(account)
            try await send(client, account)
            guard stillLive(account) else { return }
            done()
            Haptics.success()
            YouStore.shared.say(words.done)
        } catch {
            guard stillLive(account) else { return }
            if !(error is YouVoiceNotSent) { Connection.shared.note(error) }
            guard stillLive(account) else { return }
            if Self.wasRefused(error) {
                notice[part] = words.failed + " " + Self.words(error)
                return
            }
            // The change may have reached the desktop before the answer was lost: look.
            let landed: Bool?
            do {
                landed = try await check(try liveClient())
            } catch {
                landed = nil
            }
            guard stillLive(account) else { return }
            switch landed {
            case true?:
                done()
                YouStore.shared.say(words.done)
            case false?:
                if let api = error as? APIError, case .offline = api {
                    // No answer in time: the change may still be on its way. Never "has not happened".
                    unconfirmed[part, default: []].insert(key)
                    notice[part] = "Your desktop did not confirm this in time, and it may still be saving. What it has now is shown. Look again in a moment before trying again."
                } else {
                    notice[part] = "Your desktop did not confirm this, and it has not happened there. " + Self.words(error)
                }
            case nil:
                unconfirmed[part, default: []].insert(key)
                notice[part] = "Your desktop did not confirm this, and it could not be checked. Look again in a moment before trying again."
            }
        }
    }

    // MARK: Models

    /// Ask the desktop for one tiny model turn. One at a time; nothing on the desktop changes.
    func test(_ id: String) async {
        followConnection()
        guard isLive, testingID == nil, !testBlocked.contains(id), models.contains(where: { $0.id == id }) else { return }
        let account = liveAccount
        testingID = id
        tests[id] = .testing
        defer { if liveAccount == account && testingID == id { testingID = nil } }
        do {
            let answer = try await liveClient().youVoiceTest(id)
            guard stillLive(account) else { return }
            if answer.ok?.bool == true {
                tests[id] = .ok(answer.latencyMs?.int ?? 0)
                Haptics.success()
            } else {
                tests[id] = .failed(Self.testFailure(answer))
                Haptics.thud()
            }
        } catch {
            if error is CancellationError || Task.isCancelled {
                if stillLive(account) { tests[id] = nil }
                return
            }
            guard stillLive(account) else { return }
            if !(error is YouVoiceNotSent) { Connection.shared.note(error) }
            guard stillLive(account) else { return }
            if Self.wasRefused(error) {
                tests[id] = .failed(Self.words(error))
            } else {
                tests[id] = .unconfirmed("The desktop did not answer. The test may still be running there. Test stays off for this connection until your models are read again.")
                testBlocked.insert(id)
            }
            Haptics.thud()
        }
    }

    func setImages(_ id: String, _ on: Bool) async {
        guard let row = models.first(where: { $0.id == id }), row.canToggleImages, row.acceptsImages != on else { return }
        await write(.models, key: "image:" + id,
                    words: YouVoiceWords(done: on ? "\(row.name) accepts images." : "\(row.name) no longer gets images.",
                                         failed: "The image switch was not changed."),
                    optimistic: {
                        if let index = models.firstIndex(where: { $0.id == id }) { models[index].acceptsImages = on }
                    },
                    send: { client, _ in _ = try await client.youVoiceSetImages(id, on) },
                    check: { client in
                        let fresh = try await client.youVoiceModels()
                        guard let found = fresh.models.first(where: { $0.id == id }), let value = found.supportsImages?.bool else { return nil }
                        return value == on
                    })
    }

    func setAutoCompact(_ on: Bool) async {
        guard autoCompact != on else { return }
        await write(.settings, key: "autoCompact",
                    words: YouVoiceWords(done: on ? "Long chats compact on their own." : "Long chats no longer compact.",
                                         failed: "Long chats were not changed."),
                    optimistic: { autoCompact = on },
                    send: { client, _ in _ = try await client.youVoiceSetAutoCompact(on) },
                    check: { client in
                        guard let value = try await client.youVoiceSettings().autoCompact?.bool else { return nil }
                        return value == on
                    })
    }

    /// "auto" (the first local model), "off", or a local or API connection's id.
    func setHelper(_ choice: String) async {
        guard helperChoice != choice else { return }
        await write(.settings, key: "helper", words: YouVoiceWords(done: "Helpers updated.", failed: "The helper model was not changed."),
                    optimistic: { helperChoice = choice },
                    send: { client, _ in _ = try await client.youVoiceSetHelpers(choice == "auto" ? nil : choice) },
                    check: { client in Self.helperValue(try await client.youVoiceSettings()) == choice })
    }

    // MARK: Voice

    /// Make this the Voice. Only a choice the desktop says is already set up (GPT-Live with an OpenAI connection,
    /// ElevenLabs with its key saved) can be chosen. The screen asks first for a paid one.
    func setChoice(_ choice: String) async {
        guard let current = engines, current.choice != choice else { return }
        switch choice {
        case "kairos": break
        case "gpt_live": guard current.gptAvailable else { return }
        case "elevenlabs": guard current.elevenHasKey else { return }
        default: return
        }
        await write(.engines, key: "choice",
                    words: YouVoiceWords(done: "\(Self.engineTitle(choice)) is your voice now.", failed: "The voice was not changed."),
                    optimistic: { engines?.choice = choice },
                    send: { client, _ in _ = try await client.youVoiceSetChoice(choice) },
                    check: { client in Self.enginesState(from: try await client.youVoiceEngines()).choice == choice })
    }

    /// Standard, or HD when the desktop says it is installed and ready. A download is never started from the phone.
    func setQuality(_ quality: String) async {
        guard let current = engines, current.quality != quality else { return }
        guard quality == "standard" || (quality == "hd" && current.hdReady) else { return }
        await write(.engines, key: "quality",
                    words: YouVoiceWords(done: quality == "hd" ? "HD voice is on." : "Standard voice is on.", failed: "The voice quality was not changed."),
                    optimistic: { engines?.quality = quality },
                    send: { client, _ in _ = try await client.youVoiceSetQuality(quality) },
                    check: { client in Self.enginesState(from: try await client.youVoiceEngines()).quality == quality })
    }

    func setHDVoice(_ voice: String) async {
        guard let current = engines, current.hdVoice != voice, current.hdVoices.contains(where: { $0.id == voice }) else { return }
        let name = current.hdVoices.first(where: { $0.id == voice })?.name ?? voice
        await write(.engines, key: "hdVoice", words: YouVoiceWords(done: "\(name) speaks now.", failed: "The HD voice was not changed."),
                    optimistic: { engines?.hdVoice = voice },
                    send: { client, _ in _ = try await client.youVoiceSetHDVoice(voice) },
                    check: { client in Self.enginesState(from: try await client.youVoiceEngines()).hdVoice == voice })
    }

    /// Play a short sample of an HD voice on this phone (the desktop sends the sound as a file).
    func previewHD(_ voice: String) async {
        followConnection()
        guard isLive, previewing == nil, engines?.hdReady == true else { return }
        let account = liveAccount
        guard CallCenter.shared.session == nil else {
            notice[.engines] = "You are on a call"
            return
        }
        previewing = voice
        notice[.engines] = nil
        var mine: AVAudioPlayer?
        defer { if let mine, player === mine { endSampleAudio() } }
        do {
            let data = try await liveClient().youVoiceHDPreview(voice)
            guard stillLive(account) else { previewing = nil; return }
            // A call may have started while the sample loaded: leave its audio alone.
            guard CallCenter.shared.session == nil else {
                previewing = nil
                notice[.engines] = "You are on a call"
                return
            }
            let sample = try AVAudioPlayer(data: data)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
            sampleAudioOn = true
            player = sample
            mine = sample
            sample.prepareToPlay()
            sample.play()
            try? await Task.sleep(for: .seconds(sample.duration + 0.3))
            if liveAccount == account, previewing == voice { previewing = nil }
        } catch {
            if liveAccount == account, previewing == voice { previewing = nil }
            if error is CancellationError || Task.isCancelled { return }
            guard stillLive(account) else { return }
            if !(error is YouVoiceNotSent) { Connection.shared.note(error) }
            if error is YouVoiceNotSent || error is APIError {
                notice[.engines] = "The sample could not be loaded. " + Self.words(error)
            } else {
                notice[.engines] = "The sample could not be played."
            }
        }
    }

    /// Stop the sample and give the audio session back, so the person's music can carry on. A call's own audio is
    /// never touched.
    private func endSampleAudio() {
        player?.stop()
        player = nil
        if sampleAudioOn {
            sampleAudioOn = false
            if CallCenter.shared.session == nil {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    // MARK: Pronunciations

    /// The form is the person's while they have edits; otherwise it follows the desktop.
    var pronDirty: Bool { !Self.sameWords(cleanedPron(), pronFilled) }

    var pronUnconfirmed: Bool { unconfirmed[.pronunciations]?.contains("pron") == true }

    private func cleanedPronRows() -> [(id: String, item: YouVoicePronItem)] {
        pronRows.compactMap { row in
            let word = row.word.trimmingCharacters(in: .whitespaces)
            let say = row.say.trimmingCharacters(in: .whitespaces)
            // A row with no word and no respelling is a removed row, whatever sound was kept for it.
            if word.isEmpty && say.isEmpty { return nil }
            return (id: row.id, item: YouVoicePronItem(word: word, say: say, phonemes: row.phonemes))
        }
    }

    private func cleanedPron() -> [YouVoicePronItem] {
        cleanedPronRows().map { $0.item }
    }

    /// Words and respellings only: the desktop works the sound out itself.
    private static func sameWords(_ first: [YouVoicePronItem], _ second: [YouVoicePronItem]) -> Bool {
        first.count == second.count && zip(first, second).allSatisfy { $0.word == $1.word && $0.say == $1.say }
    }

    private func showPronunciations(_ fresh: [YouVoicePronItem]) {
        if pronDirty {
            // The person's edits stay. If the desktop has moved on from the list the form was filled from, say so.
            // A desktop list that equals the form is the person's own save landing late: it becomes the filled list.
            if Self.sameWords(fresh, cleanedPron()) {
                pronFilled = fresh
                pronChanged = false
            } else {
                pronChanged = fresh != pronFilled
            }
        } else {
            pronFilled = fresh
            pronRows = fresh.map(Self.pronRow)
            pronChanged = false
        }
    }

    func pronSet(_ id: String, word: String? = nil, say: String? = nil) {
        guard let index = pronRows.firstIndex(where: { $0.id == id }) else { return }
        if let word { pronRows[index].word = word }
        if let say { pronRows[index].say = say }
    }

    func pronAdd() {
        pronRows.append(YouVoicePronRow(id: "n:" + UUID().uuidString, word: "", say: "", phonemes: ""))
    }

    func pronRemove(_ id: String) {
        pronRows.removeAll { $0.id == id }
    }

    /// Drop the form's edits and show the desktop's list.
    func pronUseDesktop() async {
        pronRows = pronFilled.map(Self.pronRow)
        pronChanged = false
        notice[.pronunciations] = nil
        await read(.pronunciations)
    }

    /// Save the list. The desktop replaces its whole list on a save, so it is read again just before: if it is not the
    /// list the form was filled from, nothing is sent and the person's edits stay. Otherwise the filled list plus the
    /// person's edits is sent.
    func savePronunciations() async {
        let rows = cleanedPronRows()
        guard pronDirty, !pronUnconfirmed else { return }
        guard rows.count <= 200 else {
            notice[.pronunciations] = "Keep the list to 200 words."
            return
        }
        // Phonemes go only for a word whose phonemes the person typed and did not change; every other row sends none, so
        // the desktop works the sound out from the respelling again (the same as its own page).
        let sent = Self.pronSend(rows, filled: pronFilled)
        if sent.contains(where: { ($0.word.isEmpty != $0.say.isEmpty) && $0.phonemes.isEmpty }) {
            notice[.pronunciations] = "Fill in both sides of each word."
            Haptics.thud()
            return
        }
        let filled = pronFilled
        let box = YouVoiceSentBox()
        box.pron = sent
        await write(.pronunciations, key: "pron",
                    words: YouVoiceWords(done: "Saved. Kairos Voice says these words this way now.", failed: "The pronunciations were not saved."),
                    optimistic: {},
                    send: { client, account in
                        let fresh: [YouVoicePronItem]
                        do {
                            fresh = Self.pronItems(from: try await client.youVoicePronunciations())
                        } catch {
                            throw YouVoiceNotSent(plain: "Your desktop's list could not be read first, so nothing was sent. " + error.plainWords)
                        }
                        try ensureLive(account)
                        guard fresh == filled else {
                            pronChanged = true
                            throw YouVoiceNotSent(plain: "The list changed on your desktop, so nothing was sent. Your edits are kept here.")
                        }
                        let saved = try await client.youVoiceSavePronunciations(sent.map { (word: $0.word, say: $0.say, phonemes: $0.phonemes) })
                        box.pronFresh = Self.pronItems(from: saved)
                    },
                    check: { client in
                        let fresh = Self.pronItems(from: try await client.youVoicePronunciations())
                        box.pronFresh = fresh
                        return Self.sameWords(fresh, box.pron.map { YouVoicePronItem(word: $0.word, say: String($0.say.prefix(80)), phonemes: "") })
                    },
                    done: {
                        // Show what the desktop now has (its own respellings and sounds).
                        let fresh = box.pronFresh ?? box.pron
                        pronFilled = fresh
                        pronRows = fresh.map(Self.pronRow)
                        pronChanged = false
                    })
    }

    // MARK: Bot call voice

    /// What the form shows: the desktop's values with the person's edits on top.
    var botVoiceShown: YouVoiceBotSetting? {
        guard let base = botVoiceFilled else { return nil }
        return YouVoiceBotSetting(voice: botEdits.voice ?? base.voice, readTyped: botEdits.readTyped ?? base.readTyped,
                                  idleMinutes: botEdits.idleMinutes ?? base.idleMinutes)
    }

    private func showBotVoice(_ fresh: YouVoiceBotSetting?) {
        botVoiceFilled = fresh
        guard let fresh else { return }
        // An edit that now equals the desktop's value is no edit.
        if botEdits.voice == fresh.voice { botEdits.voice = nil }
        if botEdits.readTyped == fresh.readTyped { botEdits.readTyped = nil }
        if botEdits.idleMinutes == fresh.idleMinutes { botEdits.idleMinutes = nil }
    }

    func editBotVoice(voice: String? = nil, readTyped: Bool? = nil, idleMinutes: Int? = nil) {
        guard let base = botVoiceFilled else { return }
        if let voice { botEdits.voice = voice == base.voice ? nil : voice }
        if let readTyped { botEdits.readTyped = readTyped == base.readTyped ? nil : readTyped }
        if let idleMinutes { botEdits.idleMinutes = idleMinutes == base.idleMinutes ? nil : idleMinutes }
    }

    /// Save the bot call voice. The route resets a field it is not sent, so all three are always sent: the desktop's
    /// own values, read again just before, with only the person's edits on top.
    func saveBotVoice() async {
        guard !botEdits.isEmpty, botVoiceFilled != nil else { return }
        let edits = botEdits
        let box = YouVoiceSentBox()
        await write(.botVoice, key: "botVoice",
                    words: YouVoiceWords(done: "Saved. Voice changes apply to your next call.", failed: "The bot call voice was not saved."),
                    optimistic: {},
                    send: { client, account in
                        let fresh: YouVoiceBotSetting?
                        do {
                            fresh = Self.botSetting(try await client.youVoiceBotVoice())
                        } catch {
                            throw YouVoiceNotSent(plain: "The setting could not be read first, so nothing was sent. " + error.plainWords)
                        }
                        try ensureLive(account)
                        guard let base = fresh else {
                            throw YouVoiceNotSent(plain: "Your desktop's setting could not be read in full, so nothing was sent.")
                        }
                        let next = YouVoiceBotSetting(voice: edits.voice ?? base.voice, readTyped: edits.readTyped ?? base.readTyped,
                                                      idleMinutes: edits.idleMinutes ?? base.idleMinutes)
                        box.bot = next
                        _ = try await client.youVoiceSetBotVoice(voice: next.voice, readTyped: next.readTyped, idleMinutes: next.idleMinutes)
                    },
                    check: { client in
                        // What was sent, compared with the desktop (never with the form as it is now).
                        guard let sent = box.bot, let now = Self.botSetting(try await client.youVoiceBotVoice()) else { return nil }
                        return now == sent
                    },
                    done: { botEdits = YouVoiceBotEdits() })
    }

    // MARK: Reach me

    func setPaused(_ paused: Bool) async {
        guard let current = reach, current.isPaused != paused else { return }
        await write(.reach, key: "pause",
                    words: YouVoiceWords(done: paused ? "Paused everywhere." : "Bots can reach you again.",
                                         failed: paused ? "Bots were not paused." : "Bots were not turned back on."),
                    optimistic: { reach?.isPaused = paused },
                    send: { client, _ in _ = try await client.youVoiceSetPaused(paused) },
                    check: { client in try await client.youVoiceReach().isPaused == paused })
    }

    /// Move one way up or down, or turn it on or off, in the message or call order. Only a way the desktop says is set up
    /// can be turned on; nothing is added from the phone.
    func moveWay(_ kind: ReachMeKind, _ id: String, by step: Int) async {
        guard let view = reach else { return }
        var order = kind == .message ? view.message : view.call
        guard let at = order.firstIndex(of: id), at + step >= 0, at + step < order.count else { return }
        order.swapAt(at, at + step)
        await setOrder(kind, order)
    }

    func setWay(_ kind: ReachMeKind, _ id: String, used: Bool) async {
        guard let view = reach else { return }
        var order = (kind == .message ? view.message : view.call).filter { $0 != id }
        if used {
            let channels = kind == .message ? view.messageChannels : view.callChannels
            guard channels.first(where: { $0.id == id })?.ready == true else { return }
            order.append(id)
        }
        await setOrder(kind, order)
    }

    /// Make one way the first of the order in ONE write (`setOrder`: compare-before-send, lost-answer check). A way that
    /// is not in the order is added only when the desktop says its channel is ready.
    func makeFirst(_ kind: ReachMeKind, _ id: String) async {
        guard let view = reach else { return }
        let current = kind == .message ? view.message : view.call
        if !current.contains(id) {
            let channels = kind == .message ? view.messageChannels : view.callChannels
            guard channels.first(where: { $0.id == id })?.ready == true else { return }
        }
        await setOrder(kind, [id] + current.filter { $0 != id })
    }

    private func setOrder(_ kind: ReachMeKind, _ order: [String]) async {
        guard let view = reach else { return }
        let key = kind == .message ? "message" : "call"
        let prior = kind == .message ? view.message : view.call
        guard prior != order else { return }
        await write(.reach, key: key, words: YouVoiceWords(done: "Saved.", failed: "The order was not saved."),
                    optimistic: {
                        if kind == .message { reach?.message = order } else { reach?.call = order }
                    },
                    send: { client, account in
                        let fresh: YouVoiceReachView
                        do {
                            fresh = try await client.youVoiceReach()
                        } catch {
                            throw YouVoiceNotSent(plain: "Your desktop could not be read first, so nothing was sent. " + error.plainWords)
                        }
                        try ensureLive(account)
                        guard (kind == .message ? fresh.message : fresh.call) == prior else {
                            throw YouVoiceNotSent(plain: "The order changed on your desktop, so nothing was sent. What your desktop has is shown.")
                        }
                        _ = try await client.youVoiceSaveReach([key: order])
                    },
                    check: { client in
                        let fresh = try await client.youVoiceReach()
                        return (kind == .message ? fresh.message : fresh.call) == order
                    })
    }

    /// Change quiet hours. The route needs all three values, so the desktop's own are read again just before and only
    /// the one the person changed is replaced.
    func setQuiet(enabled: Bool? = nil, start: String? = nil, end: String? = nil) async {
        guard reach != nil else { return }
        let box = YouVoiceSentBox()
        await write(.reach, key: "quiet", words: YouVoiceWords(done: "Quiet hours saved.", failed: "Quiet hours were not saved."),
                    optimistic: {
                        if let enabled { reach?.quietEnabled = enabled }
                        if let start { reach?.quietStart = start }
                        if let end { reach?.quietEnd = end }
                    },
                    send: { client, account in
                        let fresh: YouVoiceReachView
                        do {
                            fresh = try await client.youVoiceReach()
                        } catch {
                            throw YouVoiceNotSent(plain: "Your desktop could not be read first, so nothing was sent. " + error.plainWords)
                        }
                        try ensureLive(account)
                        let next = (enabled: enabled ?? fresh.quietEnabled, start: start ?? fresh.quietStart, end: end ?? fresh.quietEnd)
                        guard YouVoiceWire.clock(next.start) != nil, YouVoiceWire.clock(next.end) != nil else {
                            throw YouVoiceNotSent(plain: "A time could not be read, so nothing was sent.")
                        }
                        guard !(next.enabled && next.start == next.end) else {
                            throw YouVoiceNotSent(plain: "Quiet hours need a different start and end.")
                        }
                        box.quiet = next
                        let quiet: [String: Any] = ["enabled": next.enabled, "start": next.start, "end": next.end]
                        _ = try await client.youVoiceSaveReach(["quiet": quiet])
                    },
                    check: { client in
                        guard let sent = box.quiet else { return nil }
                        let fresh = try await client.youVoiceReach()
                        return fresh.quietEnabled == sent.enabled && fresh.quietStart == sent.start && fresh.quietEnd == sent.end
                    })
    }

    /// One bot's choice for messages or calls: nil is "your order", an empty list is "never", one way is "only that way".
    /// The route replaces every bot's choice at once, so the desktop's are read again just before and sent back with
    /// only this one changed. Bot changes go one at a time.
    func setBot(_ id: String, _ kind: ReachMeKind, _ choice: [String]?) async {
        guard let view = reach else { return }
        let prior = view.bots[id]
        var way = prior ?? YouVoiceBotWay()
        if kind == .message { way.message = choice } else { way.call = choice }
        guard way != (prior ?? YouVoiceBotWay()) else { return }
        let next: YouVoiceBotWay? = way.isEmpty ? nil : way
        await write(.reach, key: "bots", words: YouVoiceWords(done: "Saved.", failed: "The bot's choice was not saved."),
                    optimistic: { reach?.bots[id] = next },
                    send: { client, account in
                        _ = try YouVoiceWire.botID(id)
                        let fresh: YouVoiceReachView
                        do {
                            fresh = try await client.youVoiceReach()
                        } catch {
                            throw YouVoiceNotSent(plain: "Your desktop could not be read first, so nothing was sent. " + error.plainWords)
                        }
                        try ensureLive(account)
                        guard fresh.bots[id] == prior else {
                            throw YouVoiceNotSent(plain: "This bot's choice changed on your desktop, so nothing was sent. What your desktop has is shown.")
                        }
                        var bots = fresh.bots
                        bots[id] = next
                        let body = try YouVoiceWire.botsBody(bots)
                        _ = try await client.youVoiceSaveReach(["bots": body])
                    },
                    check: { client in try await client.youVoiceReach().bots[id] == next })
    }
}

// MARK: - Small views shared by the paired screens

/// The loading note or the failure with Try again for one part; nothing once it is read. A part the desktop refused for
/// this account gets one plain line.
struct YouVoiceLoadLine: View {
    let part: YouVoicePart
    let loading: String
    private let live = YouVoiceLive.shared

    var body: some View {
        if live.memberOnly.contains(part) {
            YouAccessLine(text: "Your account on your desktop is not allowed to see this. Ask an admin.")
        } else {
            switch live.load(part) {
            case .failed(let text)?:
                YouAccessLine(text: text, action: "Try again") {
                    Task { await live.read(part) }
                }
            case .loaded?:
                EmptyView()
            default:
                YouAccessLine(text: loading)
            }
        }
    }
}

/// What a change that did not go through left behind, as one sentence.
struct YouVoiceNoticeLine: View {
    let part: YouVoicePart
    private let live = YouVoiceLive.shared

    var body: some View {
        if let text = live.notice[part] {
            NoteText(text: text, symbol: "exclamationmark.triangle")
        }
    }
}

/// A name that can drive `.sheet(item:)`.
nonisolated struct YouVoiceNamed: Identifiable, Hashable, Sendable {
    let id: String
}
