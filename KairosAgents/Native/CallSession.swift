import AVFoundation
import Foundation
import Observation
import UIKit

/// What a call needs when its audio may start. CallKit's didActivate sends it for a CallKit call; the call
/// center sends it itself where CallKit is not in use (the simulator, a ring answered from a link).
nonisolated struct CallAudioStart: Sendable, Equatable {
    let callID: UUID
    let ringID: String?
    /// No CallKit call holds the audio session, so the call activates and releases it itself.
    let ownsAudioSession: Bool
}

/// The voice of a call with a bot, in the desktop's local mode, as the web client does it (agentCall.js):
/// open the call record (with the ring id, so the bot opens with why it rang), then loop: listen, cut an
/// utterance at the end of speech, transcribe it on the desktop, send the words as the turn, speak each sentence of
/// the reply as it streams, keep the call alive, end it. Never the paid realtime socket.
///
/// One call at a time. Everything here runs on the main actor; the audio itself lives in `CallAudio` on its own
/// queue and talks back through its event stream. `epoch` changes whenever the call ends, so anything still on its
/// way from an older call is dropped.
@Observable
final class CallSession {
    static let shared = CallSession()

    enum Phase: Equatable {
        case idle
        case connecting
        /// The bot is about to say, or saying, why it rang.
        case opening
        case listening
        case thinking
        case speaking
        /// Another call or CallKit has the audio for now.
        case paused
        /// The call cannot go on; `line` says why, and it ends in a moment.
        case ending
    }

    private(set) var phase: Phase = .idle
    /// One plain sentence: what went wrong, or a notice about this call.
    private(set) var line: String?
    /// The microphone's level while listening, the bot's voice while it speaks. 0 to 1.
    private(set) var level: Double = 0
    /// When the call was really open (the microphone listening). The call screen's timer starts here.
    private(set) var openedAt: Date?
    /// The call this voice belongs to.
    private(set) var callID: UUID?

    /// This call has a real voice (paired). Not paired, the call stays the pretend call on sample data.
    func isLive(_ id: UUID?) -> Bool { id != nil && callID == id }

    /// The call screen's status line.
    func status(botName: String, muted: Bool) -> String? {
        switch phase {
        case .idle, .ending: return nil
        case .connecting: return "Connecting"
        case .opening: return "\(botName) is saying why it called"
        case .listening: return muted ? "Muted" : "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "\(botName) is speaking"
        case .paused: return "On hold"
        }
    }

    static let setUpSpeechLine = "Set up Speech in Kairos on your desktop to talk on a call."

    // MARK: State

    /// The web client's states (agentCall.js setState).
    private enum Mode { case preparing, listening, transcribing, thinking, speaking, paused }

    private struct Utterance {
        let wav: Data
        let revision: Int
        let during: Bool
        let asked: Bool
    }

    private struct Sentence {
        let index: Int
        let raw: String
        let text: String
        var started = false
        var done = false
        var began = false
        var held: [(Data, Double)] = []
    }

    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var info: CallAudioStart?
    @ObservationIgnored private var client: APIClient?
    @ObservationIgnored private var audio: CallAudio?
    @ObservationIgnored private var audioAllowed = false
    @ObservationIgnored private var audioRunning = false
    @ObservationIgnored private var recordID: String?
    @ObservationIgnored private var recordEnded = false
    @ObservationIgnored private var speechModel = ""
    @ObservationIgnored private var voice: CallVoiceChoice = .device
    @ObservationIgnored private var smartTurn = false
    @ObservationIgnored private var turnFailures = 0
    /// Transcriptions and turns that failed in a row; three and the call cannot go on.
    @ObservationIgnored private var failureStreak = 0
    /// The error line a failed transcription or turn put up, cleared by the next one that works.
    @ObservationIgnored private var errorLine: String?
    /// A reply was started and has not finished playing (or was cut): stopping it now means telling the desktop.
    @ObservationIgnored private var replyPending = false
    @ObservationIgnored private var idleMinutes = 5
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var lastContact = Date()

    @ObservationIgnored private var active = false
    @ObservationIgnored private var muted = false
    @ObservationIgnored private var mode: Mode = .preparing
    @ObservationIgnored private var openingRunning = false
    @ObservationIgnored private var speechActive = false
    @ObservationIgnored private var transcribing = false
    @ObservationIgnored private var dispatching = false
    @ObservationIgnored private var voiceBusy = false
    @ObservationIgnored private var flushQueued = false
    @ObservationIgnored private var endWhenQuiet = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var audioQueue: [Utterance] = []
    @ObservationIgnored private var texts: [String] = []
    @ObservationIgnored private var workUpdates: [String] = []
    @ObservationIgnored private var announced: Set<String> = []
    @ObservationIgnored private var deferredReply: String?
    @ObservationIgnored private var utterance: (during: Bool, asked: Bool) = (false, false)

    // The bot's voice: sentences of the reply now playing.
    @ObservationIgnored private var sentences: [Sentence] = []
    @ObservationIgnored private var head = 0
    @ObservationIgnored private var replyFinished = false
    @ObservationIgnored private var replyEndSent = false
    @ObservationIgnored private var heldBytes = 0
    @ObservationIgnored private var playGeneration = 0
    @ObservationIgnored private var chunker = SentenceChunker()
    @ObservationIgnored private var lastHeard: [String] = []
    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var fetches: [Int: Task<Void, Never>] = [:]

    // Every task of the call, cancelled when it ends.
    @ObservationIgnored private var setupTask: Task<Void, Never>?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var transcribeTask: Task<Void, Never>?
    @ObservationIgnored private var flushTimer: Task<Void, Never>?
    @ObservationIgnored private var endingTask: Task<Void, Never>?
    @ObservationIgnored private var chores: [UUID: Task<Void, Never>] = [:]

    /// The longest a sent turn may be (call_routes.py: Turn.text).
    private let turnLimit = 6000
    /// The most reply audio held back for later sentences while an earlier one still downloads.
    private let heldLimit = 24_000_000

    private init() {}

    // MARK: The call center's bridge

    /// The audio session is live for this call. A second start for the same call is CallKit giving the audio back.
    func start(_ start: CallAudioStart) async {
        if callID == start.callID {
            audioAllowed = true
            resumeAudio()
            return
        }
        if callID != nil { stop() }
        // Not paired: the pretend call on sample data, exactly as before. No network, no microphone.
        guard !Connection.isDebugViewLaunch, Connection.shared.isPaired else { return }
        epoch += 1
        let mine = epoch
        callID = start.callID
        info = start
        audioAllowed = true
        line = nil
        level = 0
        openedAt = nil
        mode = .preparing
        phase = .connecting
        setupTask = Task { await self.setUp(mine) }
    }

    /// The call ended (any way at all): stop the audio, every task and timer, and tell the desktop once.
    func stop() {
        guard callID != nil else { return }
        teardown()
        endingTask?.cancel()
        endingTask = nil
        callID = nil
        info = nil
        phase = .idle
        line = nil
        level = 0
        openedAt = nil
    }

    /// CallKit took the audio session away (didDeactivate): stop the engine and wait for it to come back. The engine is
    /// suspended even while a start is still on its way (the suspend runs after it on the engine's queue).
    func audioPaused() {
        guard callID != nil else { return }
        audioAllowed = false
        guard let audio else { return }
        audio.suspend()
        audioRunning = false
        hold()
    }

    /// Mute stops capture and stops sending. It comes from CallKit's mute action, which the call screen's key asks for.
    func setMuted(_ value: Bool) {
        muted = value
        guard active else { return }
        if value {
            // Capture stops and the segmenter forgets the half-said sentence, so no end of it will ever come.
            speechActive = false
            utterance = (false, false)
            level = 0
        }
        applyMicrophone()
        updatePhase()
        scheduleFlush()
    }

    // MARK: Setting up

    private func current(_ mine: Int) -> Bool { epoch == mine && callID != nil }

    private func setUp(_ mine: Int) async {
        guard let info else { return }
        guard let client = Connection.shared.client else {
            fail("Your desktop is not connected. Try again once it is.")
            return
        }
        self.client = client
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            fail("Allow the microphone for Kairos in Settings to talk on a call.")
            return
        case .undetermined:
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard current(mine) else { return }
            if !allowed {
                fail("Allow the microphone for Kairos in Settings to talk on a call.")
                return
            }
        default:
            break
        }
        // An answered ring is open once the desktop has the answer; its reply names the bot and its conversation.
        let deadline = Date().addingTimeInterval(70)
        while true {
            guard current(mine), let session = CallCenter.shared.session, session.uuid == info.callID else { return }
            if session.connectedAt != nil { break }
            if Date() > deadline {
                fail("Your desktop did not take the call. Try again.")
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let session = CallCenter.shared.session, session.uuid == info.callID else { return }
        let botID = session.bot.id
        guard !botID.isEmpty else {
            fail("The call could not start. Try again.")
            return
        }
        do {
            async let status = client.speechStatus()
            async let choices = client.callChoices()
            async let catalog = try? client.callVoices()
            async let roster = client.agentRoster()
            async let settings = try? client.callLiveSettings()
            let speech = try await status, connections = try await choices, bots = try await roster
            let voices = await catalog, live = await settings
            guard current(mine) else { return }
            guard let agent = bots.first(where: { $0.id == botID }) else {
                fail("This bot is not on your desktop any more.")
                return
            }
            guard let model = CallDefaults.speechModel(speech) else {
                fail(Self.setUpSpeechLine)
                return
            }
            guard let conversation = CallDefaults.conversation(connections, botEndpoint: agent.endpointId, botModel: agent.modelOverride) else {
                fail("Add a model in Kairos on your desktop to talk on a call.")
                return
            }
            speechModel = model
            voice = CallDefaults.voice(voices, botVoice: agent.voiceId)
            idleMinutes = max(1, min(60, live?.idleMinutes ?? 5))
            smartTurn = speech.turnDetect?.ready == true
            if agent.callMode == "realtime" || agent.callMode == "live" {
                line = "Realtime voice is not on the phone, so this call uses Kairos Voice."
            }
            let parent = try await conversationID(client, botID: botID, known: session.chatID)
            guard current(mine) else { return }
            // The ring's reason becomes the bot's first words. A ring the desktop no longer offers still gets a call.
            let ring = info.ringID.flatMap { Self.isRingID($0) ? $0 : nil }
            let talkEndpoint = conversation.endpoint, talkModel = conversation.model
            // Its own task, not cancelled with the setup: a record the desktop opened always comes back here, so a
            // call hung up meanwhile still ends it below.
            let opened = Task { () async throws -> (CallRecordDTO, Bool) in
                do {
                    let made = try await client.callStart(parentID: parent, agentID: botID, endpointID: talkEndpoint,
                                                          model: talkModel, ringID: ring)
                    return (made, ring != nil)
                } catch APIError.server(let code, _) where code == 409 && ring != nil {
                    let made = try await client.callStart(parentID: parent, agentID: botID, endpointID: talkEndpoint,
                                                          model: talkModel, ringID: nil)
                    return (made, false)
                }
            }
            let (record, opening) = try await opened.value
            guard current(mine) else {
                Self.endRecord(record.id, client: client)
                return
            }
            recordID = record.id
            recordEnded = false
            // The desktop ends a call it has not seen for 90 seconds, and loading a cold model can take that long:
            // the keep-alive runs from here, through the preparing, as the web client's does.
            lastContact = Date()
            pollTask = Task { await self.keepAlive(mine) }
            try await client.callPrepare(record.id)
            guard current(mine) else { return }
            _ = try await client.speechPrepare(model: model, backend: "auto")
            guard current(mine) else { return }

            let audio = CallAudio(ownsSession: info.ownsAudioSession)
            self.audio = audio
            eventsTask = Task {
                for await event in audio.events {
                    guard self.current(mine) else { return }
                    self.handle(event)
                }
            }
            muted = CallCenter.shared.muted
            if audioAllowed {
                try await audio.start()
                // CallKit may have taken the audio while it started (didDeactivate suspends it right after).
                audioRunning = audioAllowed
            }
            guard current(mine) else { return }
            audio.setSmartTurn(smartTurn)
            active = true
            openedAt = Date()
            lastActivity = Date()
            watchTask = Task { await self.watch(mine) }
            listen()
            if opening {
                workUpdates.append("ring-opening")
                scheduleFlush()
            }
        } catch is CancellationError {
            return
        } catch CallAudioError.noMicrophone {
            if current(mine) { fail("No microphone is available for the call.") }
        } catch let error as APIError {
            if current(mine) { fail(error.plain) }
        } catch {
            if current(mine) { fail("The call audio could not start. End the call and try again.") }
        }
    }

    /// The bot's conversation the call belongs to: the one the ring named, else its main one, else its oldest,
    /// else a new one (bot_attention.py: target_for picks the same way).
    private func conversationID(_ client: APIClient, botID: String, known: String?) async throws -> String {
        if let known, !known.isEmpty { return known }
        let list = try await client.agentThreads(botID)
        if let main = list.mainId, !main.isEmpty { return main }
        if let oldest = (list.threads ?? []).min(by: { ($0.createdAt ?? 0, $0.id) < ($1.createdAt ?? 0, $1.id) }) {
            return oldest.id
        }
        return try await client.agentCreateThread(botID).id
    }

    /// Ring ids are 32 lowercase hex characters (call_routes.py: Start.ring_id).
    static func isRingID(_ value: String) -> Bool {
        value.count == 32 && value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// CallKit gave the audio back. Also while the set-up's own start is still on its way (a deactivate and an
    /// activate in between): this start then runs after that suspend, so the engine ends up running.
    private func resumeAudio() {
        guard let audio, !audioRunning, audioAllowed else { return }
        let mine = epoch
        Task {
            do {
                try await audio.start()
                // CallKit took the audio again while it started: its didDeactivate already suspended the engine.
                guard self.current(mine), self.audioAllowed else { return }
                self.audioRunning = true
                if self.line == "Paused. Another call has the audio." { self.line = nil }
                self.listen()
                self.scheduleFlush()
            } catch {
                if self.current(mine) { self.fail("The call audio could not come back. End the call and try again.") }
            }
        }
    }

    // MARK: Ending

    /// The call cannot go on: say why in one line, stop everything, then end the call after a moment.
    private func fail(_ message: String) {
        guard let id = callID, phase != .ending else { return }
        teardown()
        line = message
        level = 0
        phase = .ending
        endingTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self.callID == id else { return }
            CallCenter.shared.endFromCall(failed: true)
        }
    }

    /// A transcription or a turn failed: say so in the error line. Three in a row and the call cannot go on.
    private func stepFailed(_ message: String) {
        failureStreak += 1
        if failureStreak >= 3 {
            fail(message)
            return
        }
        line = message
        errorLine = message
    }

    /// A transcription or a turn worked: the streak is over, and its error line goes.
    private func stepWorked() {
        failureStreak = 0
        if let errorLine, line == errorLine { line = nil }
        errorLine = nil
    }

    /// At most `limit` Unicode code points: the desktop counts a text's length that way (pydantic's max_length),
    /// not in Swift's characters, so an emoji or an accent can never push a text past its limit.
    static func clip(_ text: String, _ limit: Int) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.prefix(limit))
        return String(scalars)
    }

    /// The desktop ended the call (or no longer has it).
    private func endedByDesktop() {
        recordEnded = true
        CallCenter.shared.endFromCall(failed: false)
    }

    /// The call hangs up from this side (idle too long, or the bot asked to end it).
    private func hangUp() {
        CallCenter.shared.endCall()
    }

    /// Stops the audio and every task, and posts the end once. Leaves `callID` and the line for the caller.
    private func teardown() {
        epoch += 1
        active = false
        for task in [setupTask, eventsTask, pollTask, watchTask, turnTask, transcribeTask, flushTimer] { task?.cancel() }
        setupTask = nil; eventsTask = nil; pollTask = nil; watchTask = nil; turnTask = nil; transcribeTask = nil; flushTimer = nil
        for task in chores.values { task.cancel() }
        chores = [:]
        cancelSpeech()
        synthesizer = nil
        audio?.close()
        audio = nil
        audioRunning = false
        if let id = recordID, !recordEnded, let client {
            Self.endRecord(id, client: client)
        }
        recordEnded = true
        recordID = nil
        client = nil
        audioQueue = []; texts = []; workUpdates = []; announced = []; deferredReply = nil
        speechActive = false; transcribing = false; dispatching = false; voiceBusy = false; flushQueued = false
        endWhenQuiet = false; openingRunning = false; turnFailures = 0; revision += 1
        failureStreak = 0; errorLine = nil; replyPending = false
        utterance = (false, false)
        mode = .preparing
    }

    /// POST /end once, with a little background time so a locked phone can finish sending it (10 second timeout).
    private static func endRecord(_ id: String, client: APIClient) {
        let hold = BackgroundHold()
        hold.id = UIApplication.shared.beginBackgroundTask(withName: "End a call") { hold.end() }
        Task {
            try? await client.callEnd(id)
            hold.end()
        }
    }

    /// A short request that must not outlive the call.
    private func chore(_ work: @escaping @MainActor () async -> Void) {
        let key = UUID()
        chores[key] = Task {
            await work()
            self.chores[key] = nil
        }
    }

    // MARK: Keeping the call alive

    /// The web client's poll: at once, then every 2 seconds, from the moment the record exists (through the preparing),
    /// which is also the desktop's keep-alive (a call unseen for 90 seconds is ended there). Finished work is
    /// announced, and a call the desktop ended ends here. One slow or failed poll is not a lost desktop: the call ends
    /// only after two or more misses in a row and 20 seconds without an answer.
    private func keepAlive(_ mine: Int) async {
        var misses = 0
        while current(mine) {
            guard let client, let id = recordID else { return }
            do {
                let record = try await client.callStatus(id)
                guard current(mine) else { return }
                lastContact = Date()
                misses = 0
                if record.ended == true {
                    endedByDesktop()
                    return
                }
                for job in record.jobs ?? [] where !["ready", "running"].contains(job.status ?? "") {
                    announceWork(job.taskId)
                }
            } catch is CancellationError {
                return
            } catch APIError.unauthorized {
                guard current(mine) else { return }
                Connection.shared.note(APIError.unauthorized)
                fail("This iPhone is no longer paired with your desktop.")
                return
            } catch APIError.server(let code, _) where code == 404 {
                guard current(mine) else { return }
                endedByDesktop()
                return
            } catch {
                guard current(mine) else { return }
                misses += 1
                if misses >= 2, Date().timeIntervalSince(lastContact) >= 20 {
                    fail("Lost the connection to your desktop.")
                    return
                }
            }
            if active, Date().timeIntervalSince(lastActivity) > Double(idleMinutes) * 60, !voiceBusy, !speechActive {
                hangUp()
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// The call's push channel: finished work, text typed in the bot's chat, and the bot asking to end.
    private func watch(_ mine: Int) async {
        var quick = 0
        while current(mine) {
            guard let client, let id = recordID else { return }
            let opened = Date()
            do {
                for try await data in try client.callLines("/api/agent-calls/\(id)/watch", json: [:], idle: 60, limit: 3600) {
                    guard current(mine) else { return }
                    guard let event = try? KJSON.decode(CallLineDTO.self, from: data) else { continue }
                    switch event.type {
                    case "work":
                        if let task = event.taskId { announceWork(task) }
                    case "typed":
                        if active, let text = event.text, !text.isEmpty {
                            texts.append(Self.clip(text, 2000))
                            scheduleFlush()
                        }
                    case "end":
                        endWhenQuiet = true
                        if mode != .speaking, !voiceBusy { endSoon(after: 1.2) }
                    default:
                        break
                    }
                }
            } catch {
                // Reconnect below; the poll is the fallback.
            }
            guard current(mine) else { return }
            quick = Date().timeIntervalSince(opened) < 1 ? quick + 1 : 0
            if quick >= 5 { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func announceWork(_ taskID: String) {
        guard active, !announced.contains(taskID), announced.count < 50 else { return }
        announced.insert(taskID)
        workUpdates.append(taskID)
        scheduleFlush()
    }

    private func endSoon(after seconds: Double) {
        let mine = epoch
        chore {
            try? await Task.sleep(for: .seconds(seconds))
            guard self.current(mine), self.endWhenQuiet, self.active, self.mode != .speaking, !self.voiceBusy else { return }
            self.hangUp()
        }
    }

    // MARK: Audio events

    private func handle(_ event: CallAudioEvent) {
        switch event {
        case .micLevel(let value):
            if mode != .speaking, mode != .paused, !muted { level = value }
        case .playLevel(let value):
            if mode == .speaking { level = value }
        case .speechStarted:
            guard active, !muted else { return }
            if !utterance.during { utterance = (mode == .speaking || mode == .thinking || voiceBusy, false) }
            speechActive = true
        case .utterance(let wav, _):
            segmentEnded(wav)
        case .askTurn(let id, let wav):
            askTurn(id, wav: wav)
        case .bargeDuck, .bargeClear:
            // The engine pauses and resumes the bot's voice itself, on its own queue.
            break
        case .bargeIn:
            bargeIn()
        case .sentenceBegan(let generation, let index):
            guard generation == playGeneration, sentences.indices.contains(index) else { return }
            sentences[index].began = true
            if active, mode != .speaking {
                setMode(.speaking)
            }
        case .replyPlayed(let generation):
            guard generation == playGeneration else { return }
            replyEnded()
        case .deviceSentenceDone(let generation, let index, let ok):
            guard generation == playGeneration, sentences.indices.contains(index), !sentences[index].done else { return }
            sentences[index].done = true
            if !ok { line = "This iPhone's voice could not speak. Set up Kairos Voice on your desktop." }
            pump()
        case .playbackLost(let generation):
            guard generation == playGeneration, active, mode == .speaking || voiceBusy else { return }
            interruptReply(spoken: false)
        case .interrupted:
            audioRunning = false
            line = "Paused. Another call has the audio."
            hold()
        case .resumed:
            guard audioAllowed else { return }
            audioRunning = true
            if line == "Paused. Another call has the audio." { line = nil }
            listen()
            scheduleFlush()
        case .notice(let message):
            line = message
        case .failed(let message):
            // The engine is stopped or has no microphone: the call cannot go on, so it ends, honestly.
            fail(message)
        }
    }

    /// The call is on hold (CallKit took the audio, or another app interrupted it): nothing is captured, no turn
    /// runs, and the screen says "On hold". A reply on its way is stopped and the desktop is told how much of it was
    /// heard. What was said and not yet sent waits for the audio to come back.
    private func hold() {
        // Capture stops and the segmenter forgets the half-said sentence, so no end of it will ever come.
        speechActive = false
        utterance = (false, false)
        guard active else { return }
        if voiceBusy || replyPending {
            sendInterrupt(spoken: false, heard: heardNow())
            voiceBusy = false
            openingRunning = false
            revision += 1
            // Utterances already cut still count; only the reply is dropped.
            let next = revision
            audioQueue = audioQueue.map { Utterance(wav: $0.wav, revision: next, during: false, asked: false) }
            turnTask?.cancel()
        }
        stopPlayback()
        setMode(.paused)
    }

    private func setMode(_ next: Mode) {
        mode = next
        if [.speaking, .thinking, .transcribing].contains(next) { lastActivity = Date() }
        level = 0
        applyMicrophone()
        updatePhase()
    }

    /// The microphone listens in every state but speaking, paused and preparing. While the bot speaks it stays open
    /// to notice the person talking over it (barge-in). Muted, it is off.
    private func applyMicrophone() {
        let duplex = active && !muted && audioRunning && mode == .speaking
        let enabled = active && !muted && audioRunning && (duplex || ![.speaking, .paused, .preparing].contains(mode))
        audio?.setCapture(enabled: enabled, barge: duplex)
    }

    private func updatePhase() {
        guard phase != .ending, callID != nil else { return }
        switch mode {
        case .preparing: phase = .connecting
        case .listening: phase = .listening
        case .transcribing, .thinking: phase = openingRunning ? .opening : .thinking
        case .speaking: phase = openingRunning ? .opening : .speaking
        case .paused: phase = .paused
        }
    }

    /// Back to listening, unless the call is on hold (no audio): then it stays paused and says so.
    private func listen() {
        guard active else { return }
        setMode(audioRunning ? .listening : .paused)
    }

    // MARK: Your turn

    private func segmentEnded(_ wav: Data?) {
        speechActive = false
        let spoke = utterance
        utterance = (false, false)
        guard active, !muted else { return }
        if let wav {
            if audioQueue.count >= 6 {
                line = "Speech is arriving faster than your desktop can follow. The microphone is muted while it catches up."
                if !CallCenter.shared.muted { CallCenter.shared.toggleMute() }
                return
            }
            audioQueue.append(Utterance(wav: wav, revision: revision, during: spoke.during, asked: spoke.asked))
            transcribeQueued()
        }
        scheduleFlush()
    }

    private func transcribeQueued() {
        guard !transcribing, active else { return }
        transcribing = true
        let mine = epoch
        transcribeTask = Task { await self.transcribeLoop(mine) }
    }

    private func transcribeLoop(_ mine: Int) async {
        while active, current(mine), !audioQueue.isEmpty, let client {
            let item = audioQueue.removeFirst()
            if item.revision != revision { continue }
            if !voiceBusy, audioRunning { setMode(.transcribing) }
            do {
                let heard = try await client.speechTranscribe(wav: item.wav, model: speechModel, backend: "auto")
                guard active, current(mine), revision == item.revision else { continue }
                stepWorked()
                let text = (heard.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                // A nod over the bot's voice ("mm-hm") is not a turn: nothing is sent, nothing interrupts.
                if !text.isEmpty, item.during, Backchannel.isBackchannel(text, asked: item.asked) { continue }
                if !text.isEmpty {
                    texts.append(text)
                    if mode == .speaking {
                        // A reply already fully sent is being cut off in the person's ears: the desktop keeps only
                        // what was heard. One still streaming is held back instead (runTurn defers it).
                        if !voiceBusy { sendInterrupt(spoken: true, heard: heardNow()) }
                        stopPlayback()
                        listen()
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                if active, current(mine), item.revision == revision { stepFailed(APIError.plain(error)) }
            }
        }
        guard current(mine) else { return }
        transcribing = false
        if active {
            if !voiceBusy, !speechActive { listen() }
            scheduleFlush()
        }
    }

    /// Smart Turn: ask the desktop whether a pause ends the sentence. No answer within 700 ms is no opinion, and
    /// the ordinary silence wait ends the turn (turnEndpoint.js). Off for good when it is not set up or keeps failing.
    private func askTurn(_ id: Int, wav: Data) {
        guard smartTurn, active, let client, let audio else { return }
        let mine = epoch
        chore {
            do {
                let answer = try await client.speechTurn(wav: wav, timeout: 0.7)
                guard self.current(mine) else { return }
                self.turnFailures = 0
                if answer.available == false {
                    self.smartTurn = false
                    audio.setSmartTurn(false)
                    return
                }
                audio.verdict(id, complete: answer.complete ?? true)
            } catch {
                guard self.current(mine) else { return }
                self.turnFailures += 1
                if self.turnFailures >= 3 {
                    self.smartTurn = false
                    audio.setSmartTurn(false)
                }
            }
        }
    }

    /// The person talked over the bot for about a third of a second: stop the voice now, tell the desktop what was
    /// heard, and keep recording what they are saying as the next utterance.
    private func bargeIn() {
        guard active, mode == .speaking else { return }
        let heard = heardNow()
        utterance = (true, Backchannel.endsInQuestion(heard))
        sendInterrupt(spoken: true, heard: heard)
        voiceBusy = false
        revision += 1
        audioQueue = []; texts = []; deferredReply = nil
        turnTask?.cancel()
        stopPlayback()
        speechActive = true
        listen()
    }

    /// Stop the reply for good (the audio route changed under it), as the web's Interrupt does.
    private func interruptReply(spoken: Bool) {
        let heard = (mode == .speaking || voiceBusy) ? heardNow() : nil
        sendInterrupt(spoken: spoken, heard: heard)
        voiceBusy = false
        revision += 1
        audioQueue = []; texts = []; deferredReply = nil
        turnTask?.cancel()
        stopPlayback()
        listen()
        scheduleFlush()
    }

    private func sendInterrupt(spoken: Bool, heard: [String]?) {
        guard let client, let id = recordID else { return }
        chore { try? await client.callInterrupt(id, spoken: spoken, heard: heard) }
    }

    // MARK: The bot's turn

    private func scheduleFlush() {
        guard active, !flushQueued else { return }
        flushQueued = true
        let mine = epoch
        Task {
            guard self.current(mine) else { return }
            self.flushQueued = false
            self.flushText()
        }
    }

    /// Send what was said (or a finished piece of work, or the ring's opening) once nothing else is going on.
    private func flushText() {
        // On hold nothing is sent: it waits until the audio is back.
        guard active, audioRunning else { return }
        if texts.isEmpty, workUpdates.isEmpty, deferredReply == nil, !transcribing, audioQueue.isEmpty { return }
        if speechActive || transcribing || !audioQueue.isEmpty || dispatching || voiceBusy || mode == .speaking { return }
        if texts.isEmpty, workUpdates.isEmpty {
            if let reply = deferredReply {
                deferredReply = nil
                say(reply)
            }
            return
        }
        let text = Self.clip(texts.joined(separator: " "), turnLimit)
        let work = text.isEmpty && !workUpdates.isEmpty ? workUpdates.removeFirst() : nil
        texts = []
        guard !text.isEmpty || work != nil else { return }
        deferredReply = nil
        let mine = epoch, turn = revision
        dispatching = true
        if work == "ring-opening" { openingRunning = true }
        setMode(.thinking)
        voiceBusy = true
        resetSpeech()
        turnTask = Task { await self.runTurn(text: text, work: work, mine: mine, turn: turn) }
    }

    private func runTurn(text: String, work: String?, mine: Int, turn: Int) async {
        guard let client, let id = recordID else { return }
        let path: String
        var body: [String: Any] = [:]
        switch work {
        case "ring-opening"?: path = "/api/agent-calls/\(id)/opening"
        case let task?: path = "/api/agent-calls/\(id)/work/\(task)/update"
        case nil:
            path = "/api/agent-calls/\(id)/turn"
            body = ["text": text, "request_id": UUID().uuidString]
        }
        var output = ""
        var deferred = false
        do {
            for try await data in try client.callLines(path, json: body, idle: 90, limit: 300) {
                guard active, current(mine), revision == turn else { break }
                guard let event = try? KJSON.decode(CallLineDTO.self, from: data) else { continue }
                switch event.type {
                case "error":
                    throw APIError.server(status: 0, detail: event.message ?? "The conversation model failed. Check its connection on your desktop.")
                case "text":
                    let delta = event.delta ?? ""
                    if output.count < 120_000 { output += delta }
                    // The person is already talking again: keep the reply until they finish instead of talking over them.
                    if speechActive || transcribing || !audioQueue.isEmpty || !texts.isEmpty {
                        deferred = true
                        stopPlayback()
                    }
                    if !deferred { feedSpeech(delta) }
                case "notice":
                    if let message = event.message, !message.isEmpty { line = message }
                default:
                    break
                }
            }
            if active, current(mine), revision == turn {
                voiceBusy = false
                stepWorked()
                if deferred {
                    deferredReply = output
                    openingRunning = false
                    listen()
                } else {
                    finishSpeech()
                }
            }
        } catch {
            if active, current(mine), revision == turn {
                voiceBusy = false
                openingRunning = false
                stopPlayback()
                listen()
                if !(error is CancellationError) { stepFailed(APIError.plain(error)) }
            }
        }
        guard current(mine) else { return }
        dispatching = false
        if revision == turn { voiceBusy = false }
        scheduleFlush()
    }

    private func say(_ text: String) {
        guard active, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            listen()
            return
        }
        setMode(.speaking)
        resetSpeech()
        feedSpeech(text)
        finishSpeech()
    }

    /// The reply finished playing.
    private func replyEnded() {
        guard active else { return }
        openingRunning = false
        replyPending = false
        if mode == .speaking || (mode == .thinking && !voiceBusy) {
            if voiceBusy { setMode(.thinking) } else { listen() }
            scheduleFlush()
        } else {
            updatePhase()
        }
        if endWhenQuiet, !voiceBusy { endSoon(after: 0.4) }
    }

    // MARK: The bot's voice

    private func resetSpeech() {
        cancelSpeech()
        lastHeard = []
        replyPending = true
    }

    /// Stop the voice: the playing sentence, the queued ones and their downloads.
    private func stopPlayback() {
        if mode == .speaking { mode = .paused }
        cancelSpeech()
    }

    private func cancelSpeech() {
        if !sentences.isEmpty { lastHeard = heardNow() }
        replyPending = false
        playGeneration += 1
        audio?.cancelPlayback(generation: playGeneration)
        for task in fetches.values { task.cancel() }
        fetches = [:]
        synthesizer?.stopSpeaking(at: .immediate)
        sentences = []
        head = 0
        heldBytes = 0
        replyFinished = false
        replyEndSent = false
        chunker.reset()
        flushTimer?.cancel()
        flushTimer = nil
        if mode != .listening { level = 0 }
    }

    /// The sentences that began to play, as said: what the desktop keeps of a reply the person talked over.
    private func heardNow() -> [String] {
        sentences.isEmpty ? lastHeard : sentences.filter(\.began).map(\.raw)
    }

    private func feedSpeech(_ delta: String) {
        for sentence in chunker.feed(delta) { enqueueSentence(sentence) }
        flushTimer?.cancel()
        let mine = epoch, generation = playGeneration
        // A sentence that already ends in punctuation goes after 100 ms without waiting for the next word.
        flushTimer = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, self.current(mine), self.playGeneration == generation else { return }
            for sentence in self.chunker.flushSentence() { self.enqueueSentence(sentence) }
        }
    }

    private func finishSpeech() {
        flushTimer?.cancel()
        flushTimer = nil
        for sentence in chunker.finish() { enqueueSentence(sentence) }
        replyFinished = true
        pump()
    }

    private func enqueueSentence(_ raw: String) {
        let text = SpokenText.clean(raw)
        guard !text.isEmpty, sentences.count < 200 else { return }
        sentences.append(Sentence(index: sentences.count, raw: raw, text: Self.clip(text, 1600)))
        launch()
    }

    /// Start downloading the next sentences: up to three ahead for the desktop's voice, one at a time for the
    /// phone's own voice (its buffers go straight to the player).
    private func launch() {
        let ahead: Int
        if case .device = voice { ahead = 1 } else { ahead = 3 }
        guard head < sentences.count else { return }
        for index in head..<min(sentences.count, head + ahead) where !sentences[index].started {
            sentences[index].started = true
            switch voice {
            case .neural(let model, let name): fetchSentence(index, model: model, voice: name)
            case .device: speakOnPhone(index)
            }
        }
    }

    private func fetchSentence(_ index: Int, model: String, voice name: String) {
        guard let client else { return }
        let mine = epoch, generation = playGeneration, text = sentences[index].text
        fetches[index] = Task {
            var rate: Double?
            var decoder = PCM16Decoder()
            var failed = false
            do {
                for try await data in try client.callLines("/api/agent-calls/speak", json: ["text": text, "model": model, "voice": name],
                                                          idle: 30, limit: 120) {
                    guard self.current(mine), self.playGeneration == generation else { return }
                    guard let event = try? KJSON.decode(CallLineDTO.self, from: data) else { continue }
                    if event.error != nil { failed = true; break }
                    if let value = event.sampleRate { rate = value }
                    guard let audioText = event.audio else { continue }
                    guard let rate, let bytes = decoder.decode(audioText) else { failed = true; break }
                    self.deliver(index, bytes: bytes, rate: rate)
                }
                if decoder.incomplete { failed = true }
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
            guard self.current(mine), self.playGeneration == generation, self.sentences.indices.contains(index) else { return }
            if failed { self.line = "Voice playback failed. Check the voice in Kairos on your desktop." }
            self.fetches[index] = nil
            self.sentences[index].done = true
            self.pump()
        }
    }

    private func speakOnPhone(_ index: Int) {
        guard let audio else { return }
        let synthesizer = self.synthesizer ?? AVSpeechSynthesizer()
        self.synthesizer = synthesizer
        let generation = playGeneration, mine = epoch
        DeviceVoice.speak(sentences[index].text, with: synthesizer, into: audio, sentence: index, generation: generation)
        // A voice that never answers must not hold the call silent.
        chore {
            try? await Task.sleep(for: .seconds(15))
            guard self.current(mine), self.playGeneration == generation, self.sentences.indices.contains(index),
                  !self.sentences[index].done else { return }
            self.synthesizer?.stopSpeaking(at: .immediate)
            self.handle(.deviceSentenceDone(generation: generation, sentence: index, ok: false))
        }
    }

    /// Audio of one sentence: the sentence playing now goes to the player at once; a later one waits its turn.
    private func deliver(_ index: Int, bytes: Data, rate: Double) {
        guard sentences.indices.contains(index), let audio else { return }
        if index == head {
            audio.play(pcm16: bytes, rate: rate, sentence: index, generation: playGeneration)
        } else if heldBytes + bytes.count <= heldLimit {
            sentences[index].held.append((bytes, rate))
            heldBytes += bytes.count
        }
    }

    /// Play the sentences strictly in order: the head sentence's waiting audio goes out, and once it is all
    /// downloaded the next sentence becomes the head.
    private func pump() {
        guard let audio else { return }
        while head < sentences.count {
            for (bytes, rate) in sentences[head].held {
                audio.play(pcm16: bytes, rate: rate, sentence: head, generation: playGeneration)
                heldBytes -= bytes.count
            }
            sentences[head].held = []
            guard sentences[head].done else { break }
            audio.finishSentence(head, generation: playGeneration)
            head += 1
        }
        launch()
        if head >= sentences.count, replyFinished, !replyEndSent {
            replyEndSent = true
            audio.endReply(generation: playGeneration)
        }
    }
}
