import AVFoundation
import CallKit
import CryptoKit
import Foundation
import PushKit
import SwiftUI
import UIKit

/// What the native call layer asks of the call connection (`/api/agent-calls`, the Home and chats team).
/// The audio stream must not start before CallKit hands over the audio session.
enum CallAudioBridge {
    /// The audio session is live: start streaming the call with this bot (ring id when it was a ring).
    static var start: (_ botID: String, _ ringID: String?) async -> Void = { _, _ in }
    /// The call ended: close the stream.
    static var stop: () async -> Void = {}
}

/// Calls with bots: PushKit rings on a locked phone, CallKit's native screens, the audio session, mute and speaker.
@Observable
final class CallCenter {
    static let shared = CallCenter()

    struct Ring: Hashable {
        let id: String
        let bot: Bot
        let expiresAt: Date
    }

    struct Session: Hashable {
        let uuid: UUID
        /// A ring's push does not say which bot; the desktop's answer reply fills it in.
        var bot: Bot
        var ringID: String?
        var connectedAt: Date?
        /// CallKit knows this call. A ring answered from a notification link is the app's alone.
        var viaCallKit = false
    }

    /// An answer on its way to the desktop. Hanging up before it is confirmed sends a decline instead.
    private struct PendingAnswer {
        let token: UUID
        let task: Task<Void, Never>
        let ringID: String
        let deadline: Date
    }

    /// The call in progress, if any.
    private(set) var session: Session?
    /// Rings reported to CallKit and not yet answered, by call id.
    private(set) var rings: [UUID: Ring] = [:]
    private(set) var muted = false
    private(set) var speaker = true
    /// Asks the shell to show the call screen (from a ring, a link or the minimize pill).
    var showingCall = false
    /// A call screen is on screen, wherever it was opened from.
    var screenVisible = false
    private(set) var voipToken: String?

    /// A call runs and no call screen shows: the minimize pill floats at the top.
    var minimized: Bool { session != nil && !screenVisible && !showingCall }

    @ObservationIgnored private var provider: CXProvider?
    @ObservationIgnored private let controller = CXCallController()
    @ObservationIgnored private let relay = CallKitRelay()
    @ObservationIgnored private var registry: PKPushRegistry?
    /// For each ring still ringing here: the loop asking the desktop whether it ended somewhere else.
    @ObservationIgnored private var watchers: [UUID: Task<Void, Never>] = [:]
    /// For each answered ring: the answer on its way to the desktop.
    @ObservationIgnored private var answering: [UUID: PendingAnswer] = [:]
    /// Rings already over on this phone, until they expire: a repeat push for one is ended at once.
    @ObservationIgnored private var finishedRings: [UUID: Date] = [:]

    /// CallKit is not on the simulator; there the call screen still works, drawn by the app alone.
    static var usesCallKit: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    // MARK: Start-up

    /// Call from `application(_:didFinishLaunchingWithOptions:)`: a ring can wake a closed app,
    /// and iOS needs the call reported before the push handler returns.
    func start() {
        guard Self.usesCallKit, provider == nil else { return }
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = true
        configuration.iconTemplateImageData = Self.templateIcon()
        let provider = CXProvider(configuration: configuration)
        provider.setDelegate(relay, queue: nil)
        self.provider = provider

        let registry = PKPushRegistry(queue: .main)
        registry.delegate = relay
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    /// Kip's silhouette for the call screen's app button (CallKit tints it).
    private static func templateIcon() -> Data? {
        let renderer = ImageRenderer(content: Mascot(size: 40, stage: .clear).environment(\.colorScheme, .dark))
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }

    func updateVoIPToken(_ token: String?) {
        voipToken = token
        NativeTokens.shared.voip = token
    }

    // MARK: Rings (VoIP push)

    /// Every VoIP push reports a call, always, or iOS stops delivering them. A ring that is already over
    /// is reported and ended at once.
    ///
    /// The relay's payload is `{kind: "ring", ring_id, expires_at, caller}`; `agent_id` and `bot_name` are read
    /// too, for a sender that adds them. A push without a usable ring id (or one already over) is reported
    /// and ended at once: nothing could answer it. Nothing here waits or returns before the report.
    func reportRing(_ payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        let pushedID = (payload["ring_id"] as? String).flatMap { Self.isPlainID($0) ? $0 : nil }
        let ringID = pushedID ?? UUID().uuidString
        let pushedBotID = (payload["agent_id"] as? String).flatMap { Self.isPlainID($0) ? $0 : nil }
        let botName = Self.callerName(payload)
        let expires = (payload["expires_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date().addingTimeInterval(60)
        let uuid = Self.uuid(for: ringID)
        // A repeat push for a ring already declined, answered or ended on this phone must not ring again.
        let over = finishedRings[uuid].map { $0 > Date() } ?? false
        let ended = payload["kind"] as? String == "bot_call_end" || pushedID == nil || expires <= Date() || over

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "kairos-bot-" + (pushedBotID ?? "ring-" + ringID))
        update.localizedCallerName = botName
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        guard let provider else { completion(); return }
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            Task { @MainActor in
                let center = CallCenter.shared
                // A repeat push for the same ring reports the same id: iOS answers "already exists", which is fine.
                if ended {
                    center.dropRing(uuid)
                    // A late repeat of a ring answered here leaves that call alone.
                    if center.session?.uuid != uuid { provider.reportCall(with: uuid, endedAt: nil, reason: .unanswered) }
                } else if error != nil, (error as? CXErrorCodeIncomingCallError)?.code != .callUUIDAlreadyExists {
                    center.dropRing(uuid)
                } else if center.rings[uuid] != nil {
                    center.expireLater(uuid, at: expires)
                    center.watch(uuid, ringID: ringID, until: expires)
                }
                completion()
            }
        }
        // Reported; now who is calling. CallKit's answer and end actions arrive on the main queue after this.
        // A repeat push for a ring already answered here must not bring the ring back.
        if !ended, session?.uuid != uuid {
            let paired = PushBridge.isPaired() || PushBridge.awaitingUnlock()
            // The push does not carry the bot id. Paired, it comes from the desktop's answer reply; never guessed.
            let bot = Self.callerBot(id: pushedBotID ?? (paired ? "" : "kip"), name: botName, paired: paired)
            rings[uuid] = Ring(id: ringID, bot: bot, expiresAt: expires)
        }
    }

    /// The desktop says the ring ended elsewhere (answered on another device, declined, or missed).
    func ringEnded(_ ringID: String, outcome: String) {
        let uuid = Self.uuid(for: ringID)
        guard dropRing(uuid) != nil else { return }
        provider?.reportCall(with: uuid, endedAt: nil, reason: Self.endedReason(outcome))
    }

    private func expireLater(_ uuid: UUID, at date: Date) {
        Task {
            try? await Task.sleep(for: .seconds(max(1, date.timeIntervalSinceNow)))
            guard dropRing(uuid) != nil else { return }
            provider?.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
        }
    }

    /// While a ring rings here and nobody answered it on this phone, ask the desktop every 3 seconds whether it
    /// ended somewhere else. Answering or declining here removes the ring first (on the main actor) and cancels
    /// this, so a reply still on its way is dropped and never hangs up the phone's own call. Stops at expiry.
    private func watch(_ uuid: UUID, ringID: String, until expires: Date) {
        // Before the first unlock there is no client yet; the loop asks once the connection is up.
        guard watchers[uuid] == nil, PushBridge.isPaired() || PushBridge.awaitingUnlock() else { return }
        watchers[uuid] = Task {
            while !Task.isCancelled, Date() < expires {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, rings[uuid] != nil, Date() < expires else { return }
                let status = await PushBridge.ringState(ringID)
                // The person may have answered or declined here while the request was out.
                guard !Task.isCancelled, rings[uuid] != nil else { return }
                if let status, ["answered", "declined", "expired"].contains(status) {
                    ringEnded(ringID, outcome: status)
                    return
                }
            }
        }
    }

    /// Forget a ring (answered, declined, ended or expired) and stop asking about it.
    @discardableResult
    private func dropRing(_ uuid: UUID) -> Ring? {
        watchers.removeValue(forKey: uuid)?.cancel()
        let ring = rings.removeValue(forKey: uuid)
        let now = Date()
        finishedRings = finishedRings.filter { $0.value > now }
        if let ring, ring.expiresAt > now { finishedRings[uuid] = ring.expiresAt }
        return ring
    }

    private static func endedReason(_ outcome: String) -> CXCallEndedReason {
        switch outcome {
        case "answered": .answeredElsewhere
        case "declined": .declinedElsewhere
        default: .unanswered
        }
    }

    /// Ring and bot ids from a push: letters, digits, dashes and underscores, as the relay checks them.
    private static func isPlainID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.unicodeScalars.allSatisfy {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "_"
        }
    }

    /// `bot_name` when the push has it, else the relay's `caller`.
    private static func callerName(_ payload: [AnyHashable: Any]) -> String {
        for key in ["bot_name", "caller"] {
            let name = (payload[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return String(name.prefix(60)) }
        }
        return "A bot"
    }

    /// Paired: the desktop's own bot when the phone has it. Not paired: the sample bot, as before.
    private static func callerBot(id: String, name: String, paired: Bool) -> Bot {
        let known = paired ? (id.isEmpty ? nil : PushBridge.liveBot(id)) : SampleData.allBots.first(where: { $0.id == id })
        var bot = known ?? Bot(id: id, name: name, role: "", colorHex: Palette.botGold, status: .online)
        bot.name = name
        return bot
    }

    /// The same ring always maps to the same call id, so the desktop's repeat pushes never ring twice.
    static func uuid(for ringID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(ringID.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: Calling a bot (from a chat, the widget or Search)

    /// `present` asks the shell to show the call screen; a call screen that is already up passes false.
    func startCall(with bot: Bot, present: Bool = true) {
        if let session, session.bot.id == bot.id {
            if present { showingCall = true }
            return
        }
        if session != nil { endCall() }
        let uuid = UUID()
        session = Session(uuid: uuid, bot: bot, viaCallKit: Self.usesCallKit)
        muted = false
        if present { showingCall = true }
        // Asking without the usage string in Info.plist ends the app, so the app-only build skips it.
        if Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil {
            Task { _ = await AVAudioApplication.requestRecordPermission() }
        }
        if Self.usesCallKit {
            let handle = CXHandle(type: .generic, value: "kairos-bot-" + bot.id)
            let action = CXStartCallAction(call: uuid, handle: handle)
            action.contactIdentifier = bot.name
            controller.request(CXTransaction(action: action)) { error in
                guard error != nil else { return }
                Task { @MainActor in CallCenter.shared.finish(uuid) }
            }
        } else {
            connected(uuid)
        }
    }

    /// Open the call for a ring the person answered from a notification instead of the call screen.
    func answerFromLink(ringID: String, botID: String) {
        let uuid = Self.uuid(for: ringID)
        // The same link opened again: show the call already answered, never answer it a second time.
        if session?.uuid == uuid {
            showingCall = true
            return
        }
        if rings[uuid] != nil, Self.usesCallKit {
            controller.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { _ in }
            return
        }
        if session != nil { endCall() }
        session = Session(uuid: uuid, bot: SampleData.bot(botID), ringID: ringID)
        showingCall = true
        sendAnswer(uuid, ringID: ringID, until: Date().addingTimeInterval(60)) { [weak self] in self?.connected(uuid) }
    }

    func endCall() {
        guard let session else { return }
        let id = session.uuid
        if session.viaCallKit, provider != nil {
            controller.request(CXTransaction(action: CXEndCallAction(call: id))) { error in
                guard error != nil else { return }
                Task { @MainActor in CallCenter.shared.finish(id) }
            }
        } else {
            finish(id)
        }
    }

    func toggleMute() {
        guard let session else { return }
        if session.viaCallKit, provider != nil {
            controller.request(CXTransaction(action: CXSetMutedCallAction(call: session.uuid, muted: !muted))) { _ in }
        } else {
            setMuted(!muted)
        }
    }

    func toggleSpeaker() {
        speaker.toggle()
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(speaker ? .speaker : .none)
    }

    // MARK: What CallKit tells us (on the main queue)

    /// Answered on this phone. The ring is dropped first, so the watch loop stops and ignores any reply in flight.
    /// The app's call screen reads "Calling…" until the desktop has the answer; if it cannot get it, the call
    /// ends as failed. The action is fulfilled at once, as CallKit requires (holding it past CallKit's action
    /// timeout would fail the call), so CallKit's own Lock Screen timer runs while the answer is retried.
    fileprivate func perform(_ action: CXAnswerCallAction) {
        let uuid = action.callUUID
        guard let ring = dropRing(uuid) else { action.fail(); return }
        configureAudio()
        session = Session(uuid: uuid, bot: ring.bot, ringID: ring.id, viaCallKit: true)
        muted = false
        showingCall = true
        action.fulfill()
        sendAnswer(uuid, ringID: ring.id, until: ring.expiresAt) { [weak self] in
            guard let self, let session = self.session, session.uuid == uuid else { return }
            self.session?.connectedAt = .now
            LiveActivities.shared.startCall(bot: session.bot, ringID: ring.id)
        }
    }

    /// Send an answer once (the connection retries it until `deadline`), then fill in the bot the desktop named.
    /// A call hung up meanwhile cancels the send and ignores its reply.
    /// It holds a little background time, like the decline, so a locked phone can finish sending it.
    private func sendAnswer(_ uuid: UUID, ringID: String, until deadline: Date, onSent: @escaping @MainActor () -> Void) {
        answering.removeValue(forKey: uuid)?.task.cancel()
        let token = UUID()
        let hold = BackgroundHold()
        hold.id = UIApplication.shared.beginBackgroundTask(withName: "Answer a call") { hold.end() }
        let task = Task {
            let reply = await PushBridge.ring(ringID, true, deadline)
            hold.end()
            // Only the newest answer for this call clears its entry, so a replaced one never leaves it behind.
            if answering[uuid]?.token == token { answering[uuid] = nil }
            guard !Task.isCancelled, session?.uuid == uuid else { return }
            let viaCallKit = session?.viaCallKit ?? false
            switch reply {
            case .sample:
                onSent()
            case .sent(let botID, let botName):
                if let botID, Self.isPlainID(botID), botID != session?.bot.id {
                    let name = botName.map { String($0.prefix(60)) }.flatMap { $0.isEmpty ? nil : $0 } ?? session?.bot.name ?? "A bot"
                    session?.bot = Self.callerBot(id: botID, name: name, paired: true)
                }
                onSent()
            case .ended(let status):
                // "expired" here means the person answered but it reached the desktop too late: a failure.
                let reason: CXCallEndedReason = status == "expired" ? .failed : Self.endedReason(status)
                if viaCallKit { provider?.reportCall(with: uuid, endedAt: nil, reason: reason) }
                finish(uuid)
            case .failed:
                if viaCallKit { provider?.reportCall(with: uuid, endedAt: nil, reason: .failed) }
                finish(uuid)
            }
        }
        answering[uuid] = PendingAnswer(token: token, task: task, ringID: ringID, deadline: deadline)
    }

    /// Declined (on the incoming-call screen, or hung up before the answer was confirmed). The call is already
    /// gone on the phone; the decline keeps trying until the ring runs out, with a little background time so
    /// a locked phone can finish sending it. If the answer got there first, the desktop refuses the decline.
    private func sendDecline(_ ringID: String, until deadline: Date) {
        let hold = BackgroundHold()
        hold.id = UIApplication.shared.beginBackgroundTask(withName: "Decline a call") { hold.end() }
        Task {
            _ = await PushBridge.ring(ringID, false, deadline)
            hold.end()
        }
    }

    fileprivate func perform(_ action: CXStartCallAction) {
        configureAudio()
        provider?.reportOutgoingCall(with: action.callUUID, startedConnectingAt: .now)
        action.fulfill()
        connected(action.callUUID)
    }

    fileprivate func perform(_ action: CXEndCallAction) {
        if let ring = dropRing(action.callUUID) {
            // Declined on the incoming-call screen.
            sendDecline(ring.id, until: ring.expiresAt)
        }
        finish(action.callUUID)
        action.fulfill()
    }

    fileprivate func perform(_ action: CXSetMutedCallAction) {
        setMuted(action.isMuted)
        action.fulfill()
    }

    fileprivate func audioActivated() {
        guard let session else { return }
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(speaker ? .speaker : .none)
        Task { await CallAudioBridge.start(session.bot.id, session.ringID) }
    }

    fileprivate func reset() {
        for uuid in Array(rings.keys) { dropRing(uuid) }
        if let session { finish(session.uuid) }
    }

    // MARK: Pieces

    private func connected(_ uuid: UUID) {
        guard session?.uuid == uuid else { return }
        session?.connectedAt = .now
        if session?.viaCallKit == true { provider?.reportOutgoingCall(with: uuid, connectedAt: .now) }
        if let session { LiveActivities.shared.startCall(bot: session.bot, ringID: session.ringID ?? uuid.uuidString) }
    }

    private func setMuted(_ value: Bool) {
        muted = value
        LiveActivities.shared.updateCall(muted: value)
    }

    private func finish(_ uuid: UUID) {
        // Hung up before the desktop confirmed the answer: tell it no, so it records a decline, not a miss.
        if let pending = answering.removeValue(forKey: uuid) {
            pending.task.cancel()
            sendDecline(pending.ringID, until: pending.deadline)
        }
        guard session?.uuid == uuid else { return }
        session = nil
        showingCall = false
        muted = false
        Task { await CallAudioBridge.stop() }
        LiveActivities.shared.endCall()
    }

    private func configureAudio() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
    }
}

/// CallKit and PushKit call in on the main queue; this hands each call to `CallCenter` on the main actor.
nonisolated final class CallKitRelay: NSObject, CXProviderDelegate, PKPushRegistryDelegate {
    func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated { CallCenter.shared.reset() }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated { CallCenter.shared.perform(action) }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        MainActor.assumeIsolated { CallCenter.shared.perform(action) }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        MainActor.assumeIsolated { CallCenter.shared.perform(action) }
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        MainActor.assumeIsolated { CallCenter.shared.perform(action) }
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { CallCenter.shared.audioActivated() }
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        MainActor.assumeIsolated { CallCenter.shared.updateVoIPToken(token) }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        MainActor.assumeIsolated { CallCenter.shared.updateVoIPToken(nil) }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let dictionary = payload.dictionaryPayload
        MainActor.assumeIsolated { CallCenter.shared.reportRing(dictionary, completion: completion) }
    }
}

/// A little background time from iOS, given back once.
final class BackgroundHold {
    var id: UIBackgroundTaskIdentifier = .invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// The phone's push tokens. Sent to the desktop through `PushBridge.registerTokens` whenever one changes.
final class NativeTokens {
    static let shared = NativeTokens()

    var apns: String? { didSet { send() } }
    var voip: String? { didSet { send() } }

    private func send() {
        guard let apns else { return }
        let voip = voip
        Task { await PushBridge.registerTokens(apns, voip) }
    }
}
