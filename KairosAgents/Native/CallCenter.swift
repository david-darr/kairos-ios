import AVFoundation
import CallKit
import CryptoKit
import Foundation
import PushKit
import SwiftUI

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
        let bot: Bot
        var ringID: String?
        var connectedAt: Date?
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
    func reportRing(_ payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        let ringID = payload["ring_id"] as? String ?? UUID().uuidString
        let botID = payload["agent_id"] as? String ?? "kip"
        let botName = String((payload["bot_name"] as? String ?? "A bot").prefix(60))
        let expires = (payload["expires_at"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date().addingTimeInterval(60)
        let ended = payload["kind"] as? String == "bot_call_end" || expires <= Date()
        let uuid = Self.uuid(for: ringID)

        var bot = SampleData.allBots.first { $0.id == botID } ?? Bot(id: botID, name: botName, role: "", colorHex: Palette.botGold, status: .online)
        bot.name = botName

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "kairos-bot-" + botID)
        update.localizedCallerName = botName
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        guard let provider else { completion(); return }
        if !ended { rings[uuid] = Ring(id: ringID, bot: bot, expiresAt: expires) }
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            Task { @MainActor in
                // A repeat push for the same ring reports the same id: iOS answers "already exists", which is fine.
                if ended {
                    CallCenter.shared.rings[uuid] = nil
                    provider.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
                } else if error != nil, CallCenter.shared.session?.uuid != uuid, (error as? CXErrorCodeIncomingCallError)?.code != .callUUIDAlreadyExists {
                    CallCenter.shared.rings[uuid] = nil
                } else {
                    CallCenter.shared.expireLater(uuid, at: expires)
                }
                completion()
            }
        }
    }

    /// The desktop says the ring ended elsewhere (answered on another device, declined, or missed).
    func ringEnded(_ ringID: String, outcome: String) {
        let uuid = Self.uuid(for: ringID)
        guard rings[uuid] != nil else { return }
        rings[uuid] = nil
        let reason: CXCallEndedReason = outcome == "answered" ? .answeredElsewhere : (outcome == "declined" ? .declinedElsewhere : .unanswered)
        provider?.reportCall(with: uuid, endedAt: nil, reason: reason)
    }

    private func expireLater(_ uuid: UUID, at date: Date) {
        Task {
            try? await Task.sleep(for: .seconds(max(1, date.timeIntervalSinceNow)))
            guard rings[uuid] != nil else { return }
            rings[uuid] = nil
            provider?.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
        }
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
        session = Session(uuid: uuid, bot: bot)
        muted = false
        if present { showingCall = true }
        Task { _ = await AVAudioApplication.requestRecordPermission() }
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
        if rings[uuid] != nil, Self.usesCallKit {
            controller.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { _ in }
            return
        }
        Task { await PushBridge.ring(ringID, true) }
        session = Session(uuid: uuid, bot: SampleData.bot(botID), ringID: ringID)
        showingCall = true
        connected(uuid)
    }

    func endCall() {
        guard let id = session?.uuid else { return }
        if Self.usesCallKit, provider != nil {
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
        if Self.usesCallKit, provider != nil {
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

    fileprivate func perform(_ action: CXAnswerCallAction) {
        guard let ring = rings.removeValue(forKey: action.callUUID) else { action.fail(); return }
        configureAudio()
        session = Session(uuid: action.callUUID, bot: ring.bot, ringID: ring.id, connectedAt: .now)
        muted = false
        showingCall = true
        Task { await PushBridge.ring(ring.id, true) }
        LiveActivities.shared.startCall(bot: ring.bot, ringID: ring.id)
        action.fulfill()
    }

    fileprivate func perform(_ action: CXStartCallAction) {
        configureAudio()
        provider?.reportOutgoingCall(with: action.callUUID, startedConnectingAt: .now)
        action.fulfill()
        connected(action.callUUID)
    }

    fileprivate func perform(_ action: CXEndCallAction) {
        if let ring = rings.removeValue(forKey: action.callUUID) {
            // Declined on the incoming-call screen.
            Task { await PushBridge.ring(ring.id, false) }
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
        rings = [:]
        if let session { finish(session.uuid) }
    }

    // MARK: Pieces

    private func connected(_ uuid: UUID) {
        guard session?.uuid == uuid else { return }
        session?.connectedAt = .now
        if Self.usesCallKit { provider?.reportOutgoingCall(with: uuid, connectedAt: .now) }
        if let session { LiveActivities.shared.startCall(bot: session.bot, ringID: session.ringID ?? uuid.uuidString) }
    }

    private func setMuted(_ value: Bool) {
        muted = value
        LiveActivities.shared.updateCall(muted: value)
    }

    private func finish(_ uuid: UUID) {
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
