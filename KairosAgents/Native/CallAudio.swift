import AVFoundation
import Foundation

// The audio of a call with a bot: the microphone, end-of-speech detection, the bot's voice and the levels.
//
// Threads. Nothing in this file is main-actor isolated: the project's default isolation is the main actor, and a
// closure that inherits it and then runs on an audio thread traps at run time. So every type here is `nonisolated`,
// every closure handed to AVFoundation (taps, buffer completions, converter input, notification observers, speech
// buffers) is formed inside a nonisolated method and marked `@Sendable`, and none of them touches main-actor state.
// All mutable state of `CallAudio` lives on its one serial queue; the taps copy their buffer and hand it to that queue.
// What the call screen needs goes out through `events`, an AsyncStream the main actor reads.

// MARK: - End of speech (speechSegments.js: SpeechSegments)

/// Cuts the microphone into utterances by signal level, with the web client's numbers: 16 kHz samples in
/// 128-sample blocks, 200 ms to learn the room, 60 ms of voice to start, 700 ms of quiet to end, 400 ms kept
/// before the start, 160 ms kept after the last voice, 30 seconds at most. Optional end-of-turn by meaning
/// (Smart Turn): a 200 ms pause asks once whether the sentence is finished.
nonisolated struct SpeechSegmenter {
    nonisolated enum Event {
        case started
        /// An utterance ended. `pcm` is empty when it was too short to be speech.
        case segment(pcm: [Float], endpointMs: Int)
        /// A short pause: is the sentence finished? Answer with `answer(_:complete:)`.
        case pause(id: Int, pcm: [Float])
    }

    static let rate = 16_000
    static let smartPauseMs = 200.0
    static let smartCapMs = 2500.0
    static let smartWindowMs = 8000.0
    static let trailingKeepMs = 160.0

    var silenceMs = 700.0
    private(set) var smart = false
    private(set) var active = false
    private(set) var noise: Float = 0.002
    private(set) var calibrated = 0

    private let preRoll = 6400
    private let maxLength = 480_000
    private var ring: [[Float]] = []
    private var ringSize = 0
    private var parts: [[Float]] = []
    private var length = 0
    private var attack = 0.0
    private var voiced = 0
    private var quiet = 0
    private var lastVoice = 0
    private var calibration: [Float] = []
    private var pauseID = 0
    private var asked = 0
    private var verdict: Bool?

    private var rate: Double { Double(Self.rate) }
    private var trailing: Int { Int((rate * Self.trailingKeepMs / 1000).rounded()) }

    mutating func reset(keepNoise: Bool = false) {
        let previousNoise = noise, wasCalibrated = calibrated
        ring = []; ringSize = 0; parts = []; length = 0
        active = false; attack = 0; voiced = 0; quiet = 0
        asked = 0; verdict = nil
        noise = 0.002; calibration = []; calibrated = 0; lastVoice = 0
        if keepNoise && wasCalibrated >= Int(rate * 0.2) {
            noise = previousNoise
            calibrated = wasCalibrated
        }
    }

    mutating func setSmartTurn(_ value: Bool) {
        smart = value
        verdict = nil
    }

    /// The verdict for a pause question (ignored when it is for an older pause).
    mutating func answer(_ id: Int, complete: Bool) -> [Event] {
        guard active, id == pauseID, asked != 0 else { return [] }
        verdict = complete
        var events: [Event] = []
        decide(&events)
        return events
    }

    static func rms(_ samples: [Float]) -> Float {
        var square: Float = 0
        for sample in samples { square += sample * sample }
        return (square / Float(max(1, samples.count))).squareRoot()
    }

    mutating func push(_ samples: [Float]) -> (rms: Float, events: [Event]) {
        let level = Self.rms(samples)
        var events: [Event] = []
        let count = samples.count
        if !active {
            ring.append(samples); ringSize += count
            while ringSize > preRoll, ring.count > 1 { ringSize -= ring.removeFirst().count }
            if calibrated < Int(rate * 0.2) {
                calibration.append(level); calibrated += count
                // A low percentile, so a quiet opening syllable is not learned as noise.
                let ordered = calibration.sorted()
                noise = max(0.0005, min(0.012, ordered[Int(Double(ordered.count) * 0.2)]))
                return (level, events)
            }
            let speech = level > max(0.004, noise * 2.5)
            attack = speech ? attack + Double(count) : max(0, attack - Double(count) * 0.5)
            if !speech { noise = noise * 0.96 + min(level, noise * 1.3) * 0.04 }
            if attack >= rate * 0.06 {
                active = true; parts = ring; length = ringSize
                ring = []; ringSize = 0; voiced = Int(attack); quiet = 0; lastVoice = length
                asked = 0; verdict = nil
                events.append(.started)
            }
        } else {
            parts.append(samples); length += count
            if level > max(0.0025, noise * 1.6) {
                voiced += count; lastVoice = length; quiet = 0
                asked = 0; verdict = nil
            } else {
                quiet += count
            }
            if length >= maxLength {
                finish(&events)
            } else {
                if smart, asked == 0, Double(quiet) >= rate * Self.smartPauseMs / 1000, Double(voiced) >= rate * 0.12 {
                    ask(&events)
                }
                if smart, verdict != nil {
                    decide(&events)
                } else if Double(quiet) >= rate * silenceMs / 1000 {
                    finish(&events)
                }
            }
        }
        return (level, events)
    }

    /// The utterance began in the barge-in detector, which already heard its first part.
    mutating func begin(parts: [[Float]], voiced: Int) -> [Event] {
        self.parts = parts
        length = parts.reduce(0) { $0 + $1.count }
        ring = []; ringSize = 0; active = true; attack = 0
        self.voiced = voiced; quiet = 0; lastVoice = length
        asked = 0; verdict = nil
        return [.started]
    }

    private mutating func decide(_ events: inout [Event]) {
        guard active else { return }
        let quietMs = Double(quiet) / rate * 1000
        let ends: Bool
        switch smart ? verdict : nil {
        case true?: ends = quietMs >= Self.smartPauseMs
        case false?: ends = quietMs >= max(Self.smartCapMs, silenceMs)
        case nil: ends = quietMs >= silenceMs
        }
        if ends { finish(&events) }
    }

    private mutating func ask(_ events: inout [Event]) {
        let keep = Int(rate * Self.smartWindowMs / 1000)
        let end = min(length, lastVoice + trailing)
        let skip = max(0, end - keep)
        var out: [Float] = []
        out.reserveCapacity(min(end, keep))
        var taken = 0
        for part in parts {
            if taken >= end { break }
            let from = max(0, skip - taken), to = min(part.count, end - taken)
            if to > from { out.append(contentsOf: part[from..<to]) }
            taken += part.count
        }
        pauseID += 1
        asked = pauseID
        verdict = nil
        events.append(.pause(id: pauseID, pcm: out))
    }

    private mutating func finish(_ events: inout [Event]) {
        let accepted = Double(voiced) >= rate * 0.12
        let keep = min(length, lastVoice + trailing, maxLength)
        let overflow = max(0, length - maxLength)
        let tail: [Float]? = overflow > 0 ? Array((parts.last ?? []).suffix(overflow)) : nil
        var pcm: [Float] = []
        if accepted {
            pcm.reserveCapacity(keep)
            for part in parts {
                let room = keep - pcm.count
                if room <= 0 { break }
                pcm.append(contentsOf: part.prefix(room))
            }
        }
        let endpointMs = Int((Double(quiet) / rate * 1000).rounded())
        active = false; attack = 0; voiced = 0; quiet = 0; parts = []; length = 0; lastVoice = 0
        asked = 0; verdict = nil
        ring = []; ringSize = 0
        if let tail { ring = [tail]; ringSize = tail.count }
        events.append(.segment(pcm: pcm, endpointMs: endpointMs))
    }
}

// MARK: - Talking over the bot (speechSegments.js: BargeIn)

/// While the bot speaks, the microphone stays open (echo-cancelled) and this watches for the person's voice over
/// whatever of the bot's voice still leaks in. 120 ms of voice pauses the bot (duck), 320 ms interrupts it (barge);
/// voice that stops between the two and stays quiet 350 ms was a nod, and the bot carries on (clear).
nonisolated struct BargeInDetector {
    nonisolated enum Event {
        case duck
        case clear
        case barge(parts: [[Float]], voiced: Int)
    }

    private let voice = 5120
    private let gap = 1600
    private let warmup = 2400
    private let minLevel: Float = 0.012
    private let ratio: Float = 3
    private let preRoll = 4800
    private let duckAfter = 1920
    private let clearGap = 5600

    private var floor: Float = 0.002
    private var warmed = 0
    private var voiced = 0
    private var quiet = 0
    private var run = false
    private var ducked = false
    private var buffer: [[Float]] = []
    private var size = 0

    var threshold: Float { max(minLevel, floor * ratio) }

    mutating func reset(ambient: Float) {
        floor = max(0.0005, ambient)
        warmed = 0; voiced = 0; quiet = 0; run = false; ducked = false
        buffer = []; size = 0
    }

    mutating func push(_ samples: [Float]) -> (rms: Float, event: Event?) {
        let level = SpeechSegmenter.rms(samples)
        buffer.append(samples); size += samples.count
        if warmed < warmup {
            warmed += samples.count
            floor += (level - floor) * 0.25
            trim(all: false)
            return (level, nil)
        }
        var event: Event?
        if level > threshold {
            run = true; voiced += samples.count; quiet = 0
            floor += (level - floor) * 0.002
            if !ducked, voiced >= duckAfter, voiced < voice {
                ducked = true
                event = .duck
            }
            if voiced >= voice {
                let parts = buffer, heard = voiced
                reset(ambient: floor)
                warmed = warmup
                return (level, .barge(parts: parts, voiced: heard))
            }
        } else {
            floor += (level - floor) * 0.05
            if run {
                quiet += samples.count
                if quiet > (ducked ? clearGap : gap) {
                    run = false; voiced = 0; quiet = 0
                    if ducked { ducked = false; event = .clear }
                }
            }
            if !run { trim(all: false) }
        }
        if size > 16_000 * 3 { trim(all: true) }
        return (level, event)
    }

    private mutating func trim(all: Bool) {
        let keep = all ? 16_000 * 3 : preRoll
        while buffer.count > 1, size - buffer[0].count >= keep { size -= buffer.removeFirst().count }
    }
}

// MARK: - The engine

/// What the audio tells the call.
nonisolated enum CallAudioEvent: Sendable {
    /// The microphone's level, 0 to 1, about 20 times a second while listening.
    case micLevel(Double)
    /// The bot's voice level, 0 to 1, as it plays.
    case playLevel(Double)
    case speechStarted
    /// An utterance ended: its 16 kHz WAV, or nil when it was too short to be speech.
    case utterance(wav: Data?, endpointMs: Int)
    /// A short pause: ask the desktop whether the sentence is finished.
    case askTurn(id: Int, wav: Data)
    case bargeDuck
    case bargeClear
    case bargeIn
    /// The first audio of this sentence of this reply was played.
    case sentenceBegan(generation: Int, sentence: Int)
    /// Everything of this reply has played.
    case replyPlayed(generation: Int)
    /// The phone's own voice finished making a sentence (`ok` false: it failed).
    case deviceSentenceDone(generation: Int, sentence: Int, ok: Bool)
    /// The audio route or the engine changed under a reply; what was queued is gone.
    case playbackLost(generation: Int)
    /// Another app or a phone call took the audio.
    case interrupted
    case resumed
    /// Something about this call's audio the person should know; the call goes on. One plain sentence.
    case notice(String)
    /// The audio could not run, and the call cannot go on. One plain sentence.
    case failed(String)
}

nonisolated enum CallAudioError: Error {
    case closed
    case noMicrophone
}

/// Copies an audio buffer, so a tap can hand it to another queue.
nonisolated func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: max(1, buffer.frameLength)) else { return nil }
    copy.frameLength = buffer.frameLength
    let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    for index in 0..<min(source.count, target.count) {
        guard let from = source[index].mData, let to = target[index].mData else { continue }
        memcpy(to, from, Int(min(source[index].mDataByteSize, target[index].mDataByteSize)))
    }
    return copy
}

/// Set once by a converter's input block: the one buffer it may hand over has been handed over.
nonisolated final class OneShot: @unchecked Sendable {
    var used = false
}

/// The call's audio engine: voice processing (echo cancellation) on, a tap on the microphone that feeds the
/// segmenter at 16 kHz, and one player node for the bot's voice. It is started only once the audio session is
/// live (CallKit's didActivate, or the app's own activation when CallKit is not in use).
nonisolated final class CallAudio: @unchecked Sendable {
    let events: AsyncStream<CallAudioEvent>
    private let continuation: AsyncStream<CallAudioEvent>.Continuation
    private let queue = DispatchQueue(label: "app.kairos-agents.call-audio", qos: .userInitiated)
    /// True when no CallKit call holds the audio session (the simulator, a ring answered from a link): this
    /// class then sets the category and activates and releases the session itself.
    private let ownsSession: Bool

    // Everything below is touched only on `queue`.
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private let captureFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var built = false
    private var running = false
    private var closed = false
    /// CallKit took the audio session (didDeactivate); only `start()` (its didActivate) brings the engine back.
    private var suspended = false
    /// An interruption stopped the engine; its end may bring it back.
    private var interrupted = false
    /// The engine stopped itself (a configuration change) and is being started again.
    private var restarting = false
    /// Changes whenever the engine is stopped on purpose, so a restart still waiting is dropped.
    private var restartToken = 0
    /// When the engine stopped itself lately: more than three in ten seconds and the call audio gives up.
    private var restarts: [Date] = []
    /// The bot's voice is paused because the person may be about to talk over it (barge-in's duck).
    private var ducked = false
    private var observers: [NSObjectProtocol] = []
    private var inputConverter: AVAudioConverter?
    private var capturing = false
    private var barge = false
    private var segmenter = SpeechSegmenter()
    private var bargeIn = BargeInDetector()
    private var pending: [Float] = []
    private var levelSamples = 0
    private var generation = 0
    private var outstanding = 0
    private var replyEnding = false
    private var converters: [Int: AVAudioConverter] = [:]
    private var began: Set<Int> = []
    /// The most audio the player may hold, in seconds; more is dropped (a runaway stream cannot fill memory).
    private let playbackCap = 120.0
    private var queuedSeconds = 0.0

    init(ownsSession: Bool) {
        self.ownsSession = ownsSession
        let (stream, continuation) = AsyncStream<CallAudioEvent>.makeStream(bufferingPolicy: .bufferingNewest(512))
        events = stream
        self.continuation = continuation
    }

    // MARK: Start and stop

    /// Start, or start again after a pause (a held call, an interruption).
    func start() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            queue.async {
                self.suspended = false
                self.interrupted = false
                self.restarting = false
                do {
                    try self.startOnQueue()
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }

    /// The audio session was taken away (CallKit's didDeactivate): stop the engine, keep everything else.
    func suspend() {
        queue.async {
            self.suspended = true
            self.halt()
        }
    }

    /// The call is over: stop everything, remove the taps and observers, release the session if this owns it.
    /// Nothing of this outlives the call.
    func close() {
        queue.async {
            guard !self.closed else { return }
            self.closed = true
            self.halt()
            for observer in self.observers { NotificationCenter.default.removeObserver(observer) }
            self.observers = []
            if self.built {
                self.engine.detach(self.player)
                self.built = false
            }
            self.converters = [:]
            self.pending = []
            self.segmenter.reset()
            if self.ownsSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            self.continuation.finish()
        }
    }

    private func startOnQueue() throws {
        guard !closed else { throw CallAudioError.closed }
        guard !running else { return }
        if ownsSession {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true)
        }
        if !built {
            // Voice processing (echo cancellation) can only change while the engine is stopped, and turning it on
            // for the input turns it on for the output too. It comes first, before any connection or tap.
            if !engine.inputNode.isVoiceProcessingEnabled {
                do {
                    try engine.inputNode.setVoiceProcessingEnabled(true)
                } catch {
                    continuation.yield(.notice("Echo cancellation could not start, so the bot may hear itself. Headphones help."))
                }
            }
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playFormat)
            built = true
            watch()
        }
        try installTaps()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeTaps()
            throw error
        }
        running = true
        player.play()
    }

    /// Stop the engine and remove the taps. Whatever was queued to play is dropped.
    private func halt() {
        restartToken += 1
        restarting = false
        guard running || built else { return }
        if running {
            player.stop()
            engine.stop()
        }
        removeTaps()
        running = false
        outstanding = 0
        queuedSeconds = 0
        converters = [:]
        replyEnding = false
        ducked = false
    }

    private func installTaps() throws {
        removeTaps()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CallAudioError.noMicrophone }
        inputConverter = AVAudioConverter(from: format, to: captureFormat)
        // The tap runs on an audio thread, not the main one: it copies the buffer and hands it over, nothing more.
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable [weak self] buffer, _ in
            guard let self, let copy = copyBuffer(buffer) else { return }
            self.queue.async { self.process(copy) }
        }
        // The bot's voice level, measured from what the player renders.
        player.installTap(onBus: 0, bufferSize: 2048, format: player.outputFormat(forBus: 0)) { @Sendable [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let samples = data[0]
            var square: Float = 0
            for index in 0..<Int(buffer.frameLength) { square += samples[index] * samples[index] }
            let level = (square / Float(buffer.frameLength)).squareRoot()
            self.continuation.yield(.playLevel(Double(min(1, level * 7))))
        }
    }

    private func removeTaps() {
        engine.inputNode.removeTap(onBus: 0)
        if built { player.removeTap(onBus: 0) }
    }

    /// Route changes, engine changes and interruptions. Each observer's block only hops onto the queue.
    private func watch() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { @Sendable [weak self] _ in
            guard let self else { return }
            self.queue.async { self.rebuild() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { @Sendable [weak self] _ in
            guard let self else { return }
            self.queue.async { self.rebuildIfInputChanged() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { @Sendable [weak self] note in
            guard let self else { return }
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            self.queue.async { self.interruption(type, resume: options.contains(.shouldResume)) }
        })
    }

    /// The engine stopped itself (a new route, a new sample rate): drop what was queued, take the new formats, start
    /// again. The engine posts this only after it has stopped; one still running needs nothing. A few tries a little
    /// apart, and more than three restarts in ten seconds, and the call is told its audio failed.
    private func rebuild() {
        guard running, !closed, !engine.isRunning else { return }
        if outstanding > 0 { continuation.yield(.playbackLost(generation: generation)) }
        player.stop()
        engine.stop()
        removeTaps()
        running = false
        outstanding = 0
        queuedSeconds = 0
        converters = [:]
        replyEnding = false
        ducked = false
        let now = Date()
        restarts = restarts.filter { now.timeIntervalSince($0) < 10 }
        restarts.append(now)
        guard restarts.count <= 3 else {
            continuation.yield(.failed("The call audio kept stopping. End the call and try again."))
            return
        }
        restarting = true
        restart(attempt: 1, token: restartToken)
    }

    private func restart(attempt: Int, token: Int) {
        guard token == restartToken, restarting, !running, !closed else { return }
        do {
            try startOnQueue()
            restarting = false
            if interrupted {
                interrupted = false
                continuation.yield(.resumed)
            }
        } catch {
            guard attempt < 3 else {
                restarting = false
                continuation.yield(.failed("The call audio stopped. End the call and try again."))
                return
            }
            queue.asyncAfter(deadline: .now() + 0.3) { self.restart(attempt: attempt + 1, token: token) }
        }
    }

    /// Headphones or Bluetooth came or went: a new microphone format needs a new tap. A format of no rate or no
    /// channels can be passing; it is tried again a little later, and only then is the call told there is no microphone.
    private func rebuildIfInputChanged(attempt: Int = 1, token: Int? = nil) {
        guard running, !closed else { return }
        if let token, token != restartToken { return }
        if attempt == 1 {
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard let current = inputConverter?.inputFormat, current != format else { return }
        }
        do {
            try installTaps()
        } catch {
            guard attempt < 3 else {
                continuation.yield(.failed("No microphone is available for the call."))
                return
            }
            let mine = restartToken
            queue.asyncAfter(deadline: .now() + 0.3) { self.rebuildIfInputChanged(attempt: attempt + 1, token: mine) }
        }
    }

    /// Another app or a phone call took the audio. When it gives it back, the engine starts
    /// again, for a CallKit call too (CallKit did not take the session, so no didActivate follows; the engine never
    /// activates a CallKit session itself). A session CallKit deactivated waits for its didActivate instead.
    private func interruption(_ type: AVAudioSession.InterruptionType?, resume: Bool) {
        guard !closed else { return }
        switch type {
        case .began?:
            guard running || restarting else { return }
            if outstanding > 0 { continuation.yield(.playbackLost(generation: generation)) }
            halt()
            interrupted = true
            continuation.yield(.interrupted)
        case .ended?:
            // For a call the audio comes back whenever the other sound is done, with or without "should resume".
            // A few tries a little apart: right at the end of an interruption a start can fail for a moment.
            guard interrupted, !suspended, !running, !restarting else { return }
            restarting = true
            restart(attempt: 1, token: restartToken)
        default:
            break
        }
    }

    // MARK: The microphone

    /// Listen (segment), or watch for barge-in while the bot speaks, or neither (muted, thinking aloud).
    func setCapture(enabled: Bool, barge: Bool) {
        queue.async {
            if enabled != self.capturing {
                self.capturing = enabled
                self.segmenter.reset(keepNoise: true)
                self.pending = []
            }
            let watching = enabled && barge
            if watching != self.barge {
                self.barge = watching
                if watching { self.bargeIn.reset(ambient: self.segmenter.noise) }
            }
            // No longer watching for barge-in (muted, held, the reply over): a voice paused by the duck carries on,
            // since no "clear" can come for it any more.
            if !watching, self.ducked { self.undock() }
        }
    }

    private func undock() {
        ducked = false
        if running, engine.isRunning { player.play() }
    }

    func setSmartTurn(_ value: Bool) {
        queue.async { self.segmenter.setSmartTurn(value) }
    }

    func verdict(_ id: Int, complete: Bool) {
        queue.async {
            guard self.capturing else { return }
            self.send(self.segmenter.answer(id, complete: complete))
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard running, capturing, !closed else { return }
        if inputConverter?.inputFormat != buffer.format {
            inputConverter = AVAudioConverter(from: buffer.format, to: captureFormat)
        }
        guard let converter = inputConverter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * captureFormat.sampleRate / buffer.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: capacity) else { return }
        let given = OneShot()
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { @Sendable _, state in
            if given.used {
                state.pointee = .noDataNow
                return nil
            }
            given.used = true
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, let data = out.floatChannelData, out.frameLength > 0 else { return }
        pending.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
        var at = 0
        while pending.count - at >= 128 {
            block(Array(pending[at..<(at + 128)]))
            at += 128
        }
        pending.removeFirst(at)
    }

    private func block(_ samples: [Float]) {
        let level: Float
        if barge, !segmenter.active {
            let result = bargeIn.push(samples)
            level = result.rms
            switch result.event {
            case .duck?:
                // Hold the bot's voice: the person may be about to talk. Paused here, on the queue, so a mute or a
                // reply ending in between can never leave it paused (setCapture lets it go).
                if running {
                    player.pause()
                    ducked = true
                }
                continuation.yield(.bargeDuck)
            case .clear?:
                if ducked { undock() }
                continuation.yield(.bargeClear)
            case .barge(let parts, let voiced)?:
                barge = false
                continuation.yield(.bargeIn)
                send(segmenter.begin(parts: parts, voiced: voiced))
            case nil: break
            }
        } else {
            let result = segmenter.push(samples)
            level = result.rms
            send(result.events)
            levelSamples += samples.count
            if levelSamples >= 800 {
                levelSamples = 0
                continuation.yield(.micLevel(Double(min(1, level * 12))))
            }
        }
    }

    private func send(_ found: [SpeechSegmenter.Event]) {
        for event in found {
            switch event {
            case .started:
                continuation.yield(.speechStarted)
            case .segment(let pcm, let endpointMs):
                continuation.yield(.utterance(wav: pcm.isEmpty ? nil : CallWAV.encode(pcm, rate: SpeechSegmenter.rate), endpointMs: endpointMs))
            case .pause(let id, let pcm):
                guard !pcm.isEmpty else { continue }
                continuation.yield(.askTurn(id: id, wav: CallWAV.encode(pcm, rate: SpeechSegmenter.rate)))
            }
        }
    }

    // MARK: The bot's voice

    /// A piece of one sentence from the desktop's voice: PCM16 little-endian mono at `rate`.
    func play(pcm16 bytes: Data, rate: Double, sentence: Int, generation: Int) {
        queue.async {
            guard rate >= 8000, rate <= 96_000, bytes.count >= 2,
                  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else { return }
            let samples = PCM16Decoder.floats(bytes)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { channel[0].update(from: $0.baseAddress!, count: samples.count) }
            self.schedule(buffer, sentence: sentence, generation: generation)
        }
    }

    /// A buffer from the phone's own voice (AVSpeechSynthesizer). An empty buffer means the sentence is made.
    func deviceBuffer(_ buffer: AVAudioBuffer, sentence: Int, generation: Int) {
        guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
            queue.async {
                self.finishSentence(sentence, generation: generation, now: true)
                self.continuation.yield(.deviceSentenceDone(generation: generation, sentence: sentence, ok: true))
            }
            return
        }
        guard let copy = copyBuffer(pcm) else { return }
        queue.async { self.schedule(copy, sentence: sentence, generation: generation) }
    }

    /// No more audio for this sentence: let the converter hand over what it still holds.
    func finishSentence(_ sentence: Int, generation: Int) {
        queue.async { self.finishSentence(sentence, generation: generation, now: true) }
    }

    /// Every sentence of this reply was handed over: say so once the last of it has played.
    func endReply(generation: Int) {
        queue.async {
            guard generation == self.generation else { return }
            self.replyEnding = true
            self.settle()
        }
    }

    /// Stop the bot's voice now and drop everything queued. Later audio carries `generation`.
    func cancelPlayback(generation: Int) {
        queue.async {
            self.generation = generation
            self.outstanding = 0
            self.queuedSeconds = 0
            self.converters = [:]
            self.began = []
            self.replyEnding = false
            self.ducked = false
            guard self.built else { return }
            self.player.stop()
            if self.running, self.engine.isRunning { self.player.play() }
        }
    }

    private func finishSentence(_ sentence: Int, generation: Int, now: Bool) {
        guard generation == self.generation, let converter = converters.removeValue(forKey: sentence) else { return }
        guard let out = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: 8192) else { return }
        var error: NSError?
        _ = converter.convert(to: out, error: &error) { @Sendable _, state in
            state.pointee = .endOfStream
            return nil
        }
        if out.frameLength > 0 { enqueue(out, sentence: sentence) }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, sentence: Int, generation: Int) {
        guard generation == self.generation, running, !closed, buffer.frameLength > 0 else { return }
        let converter: AVAudioConverter
        if let existing = converters[sentence], existing.inputFormat == buffer.format {
            converter = existing
        } else {
            guard let made = AVAudioConverter(from: buffer.format, to: playFormat) else { return }
            converters[sentence] = made
            converter = made
        }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * playFormat.sampleRate / buffer.format.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: capacity) else { return }
        let given = OneShot()
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { @Sendable _, state in
            if given.used {
                state.pointee = .noDataNow
                return nil
            }
            given.used = true
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else { return }
        enqueue(out, sentence: sentence)
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer, sentence: Int) {
        let seconds = Double(buffer.frameLength) / playFormat.sampleRate
        guard queuedSeconds + seconds <= playbackCap else { return }
        queuedSeconds += seconds
        outstanding += 1
        let mine = generation
        let first = !began.contains(sentence)
        if first { began.insert(sentence) }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            guard let self else { return }
            self.queue.async { self.played(mine, sentence: sentence, first: first, seconds: seconds) }
        }
        if engine.isRunning, !player.isPlaying, !ducked { player.play() }
    }

    private func played(_ mine: Int, sentence: Int, first: Bool, seconds: Double) {
        guard mine == generation, outstanding > 0 else { return }
        outstanding -= 1
        queuedSeconds = max(0, queuedSeconds - seconds)
        if first { continuation.yield(.sentenceBegan(generation: mine, sentence: sentence)) }
        settle()
    }

    private func settle() {
        guard replyEnding, outstanding == 0 else { return }
        replyEnding = false
        continuation.yield(.replyPlayed(generation: generation))
    }
}

/// The phone's own voice, for when the desktop's Voice engine is not ready (the web client uses the device voice
/// then too). Its buffers go into the call's player, so echo cancellation knows them. The callback is formed here,
/// outside any actor, and only hands the buffer to the engine's queue.
nonisolated enum DeviceVoice {
    static func speak(_ text: String, with synthesizer: AVSpeechSynthesizer, into audio: CallAudio, sentence: Int, generation: Int) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        synthesizer.write(utterance) { @Sendable buffer in
            audio.deviceBuffer(buffer, sentence: sentence, generation: generation)
        }
    }
}
