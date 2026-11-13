import Foundation
import Observation
import UIKit

/// The desktop this phone is paired with. Nothing secret: the token is in the Keychain.
nonisolated struct PairedDesktop: Codable, Hashable, Sendable {
    var address: String
    var username: String
    var isAdmin: Bool
    var color: String
    var serverName: String
    var serverVersion: String
    var deviceId: String

    /// The address without its scheme, for showing.
    var host: String {
        address.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }

    static let sample = PairedDesktop(
        address: "https://desk.example.com", username: "alex", isAdmin: true, color: "teal",
        serverName: "Kairos", serverVersion: "2.3.0", deviceId: "d_sample"
    )
}

/// The connection to the person's desktop, for the whole app to read.
/// `Connection.shared.state` says which of five things is true right now.
@Observable
final class Connection {
    static let shared = Connection()

    nonisolated enum State: Equatable, Sendable {
        /// Never paired: the app shows made-up sample data.
        case sample
        /// Paired, asking the desktop whether the token is still good.
        case connecting
        /// Paired and the desktop is answering.
        case connected
        /// Paired, but the desktop is not answering. The text says why, in plain words.
        case offline(String)
        /// The desktop refused this phone's token. Pair again.
        case signedOut
    }

    private(set) var state: State = .sample
    private(set) var desktop: PairedDesktop?
    private(set) var client: APIClient?
    /// When the desktop last answered anything.
    private(set) var lastContact: Date?

    /// Called on every state change, for the data store.
    @ObservationIgnored var onChange: (() -> Void)?
    /// One live event's JSON, for the data store.
    @ObservationIgnored var onPacket: ((Data) -> Void)?
    /// The live stream opened again after a gap: anything shown may be stale.
    @ObservationIgnored var onStreamOpen: (() -> Void)?

    private let stream = LiveEventStream()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var pushTokens: (apns: String, voip: String?)?
    @ObservationIgnored private var activityTokens: [String: (kind: String, token: String)] = [:]
    private let isPreview: Bool

    private static let desktopKey = "pairedDesktop"
    private static let tokenAccount = "desktop-token"

    private init() {
        isPreview = false
        stream.onPacket = { [weak self] data in
            self?.lastContact = Date()
            self?.onPacket?(data)
        }
        stream.onState = { [weak self] open in self?.streamChanged(open) }
        stream.onUnauthorized = { [weak self] in self?.tokenRefused() }
        wirePushBridge()
    }

    /// A stand-in for pictures and debug views. It never touches the network or the Keychain.
    init(preview state: State, desktop: PairedDesktop? = .sample) {
        isPreview = true
        self.state = state
        self.desktop = state == .sample ? nil : desktop
    }

    // MARK: Reading

    /// A desktop is paired (whether or not it is answering right now).
    var isPaired: Bool { desktop != nil && state != .sample }

    /// The app should show sample data.
    var usesSampleData: Bool { state == .sample }

    var isConnected: Bool { state == .connected }

    /// One short line for a status row.
    var statusLine: String {
        switch state {
        case .sample: return "Not paired. Showing sample data."
        case .connecting: return "Connecting to your desktop"
        case .connected: return "Connected"
        case .offline(let reason): return reason
        case .signedOut: return "This iPhone is no longer paired."
        }
    }

    // MARK: Launch

    /// Call when the app opens. Reads the saved pairing and asks the desktop whether it still stands.
    ///
    /// A ring can launch the app before the first unlock after a restart, when neither the saved pairing nor
    /// the token can be read. Then nothing is decided: the state stays as it is, nothing is cleared, and this
    /// runs again once the phone is unlocked (or the app comes to the front, or a ring's answer asks).
    func start() {
        guard !isPreview, !started else { return }
        let token = Keychain.lookup(account: Connection.tokenAccount)
        let locked = !UIApplication.shared.isProtectedDataAvailable
        guard token != .unreadable else { waitForUnlock(); return }
        guard let data = UserDefaults.standard.data(forKey: Connection.desktopKey),
              let saved = try? JSONDecoder().decode(PairedDesktop.self, from: data) else {
            // Not paired, or the saved pairing cannot be read yet.
            if locked { waitForUnlock(); return }
            markStarted()
            return
        }
        guard case .found(let value) = token, let base = APIClient.baseURL(from: saved.address) else {
            if locked, token == .missing { waitForUnlock(); return }
            markStarted()
            desktop = saved
            set(.signedOut)
            return
        }
        markStarted()
        desktop = saved
        client = makeClient(base: base, token: value)
        set(.connecting)
        Task { await checkSession() }
    }

    /// The saved pairing could not be read yet (before the first unlock after a restart).
    @ObservationIgnored private(set) var waitingForUnlock = false
    @ObservationIgnored private var unlockWatch: NSObjectProtocol?

    private func waitForUnlock() {
        waitingForUnlock = true
        guard unlockWatch == nil else { return }
        unlockWatch = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in Connection.shared.start() }
        }
    }

    private func markStarted() {
        started = true
        waitingForUnlock = false
        if let unlockWatch {
            NotificationCenter.default.removeObserver(unlockWatch)
            self.unlockWatch = nil
        }
    }

    /// A debug launch that opens one view on its own (`-kDebugView`) stays off the network.
    static var isDebugViewLaunch: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "kDebugView") != nil
        #else
        return false
        #endif
    }

    /// Call when the app comes back to the front.
    func wake() {
        if waitingForUnlock { start() }
        guard !isPreview, let client, state != .signedOut, state != .sample else { return }
        if !stream.isRunning { stream.start(client: client) }
        Task { await checkSession() }
    }

    // MARK: Pairing

    /// Pair with the address and the six digit code the desktop shows. Throws an `APIError` in plain words.
    func pair(address: String, code: String) async throws {
        guard let base = APIClient.baseURL(from: address) else { throw APIError.badAddress }
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else {
            throw APIError.server(status: 400, detail: "The code has 6 digits. Check it on your desktop.")
        }
        let open = APIClient(base: base, token: nil)
        let claim: PhonePairClaimDTO
        do {
            claim = try await open.phonePairClaim(code: digits)
        } catch APIError.server(let status, let detail) where status == 404 {
            _ = detail
            throw APIError.server(status: 404, detail: "That address answered, but it has no phone pairing. Update Kairos on your desktop, then try again.")
        } catch APIError.unauthorized {
            throw APIError.server(status: 401, detail: "That code is not right or has expired.")
        }
        guard !claim.token.isEmpty else { throw APIError.unreadable("token") }
        guard Keychain.save(claim.token, account: Connection.tokenAccount) else {
            throw APIError.server(status: 0, detail: "The pairing could not be saved on this iPhone. Try again.")
        }
        let paired = PairedDesktop(
            address: base.absoluteString,
            username: claim.account?.username ?? "you",
            isAdmin: claim.account?.isAdmin ?? false,
            color: claim.account?.color ?? "",
            serverName: claim.server?.name ?? "Kairos",
            serverVersion: claim.server?.version ?? "",
            deviceId: claim.deviceId ?? ""
        )
        save(paired)
        client = makeClient(base: base, token: claim.token)
        lastContact = Date()
        markStarted()
        set(.connected)
        becameReady()
        ConnectionSeam.paired()
    }

    /// Unpair this phone: tell the desktop, forget the token, go back to sample data.
    func unpair() async {
        guard !isPreview else {
            desktop = nil
            set(.sample)
            return
        }
        if let client, let id = desktop?.deviceId, !id.isEmpty {
            try? await client.phonePushUnregister()
            try? await client.phoneUnpair(deviceId: id)
        }
        forget()
        set(.sample)
    }

    /// Forget a pairing the desktop already refused, and go back to sample data.
    func forgetPairing() {
        forget()
        set(.sample)
    }

    func devices() async throws -> [PhoneDeviceDTO] {
        guard let client else { throw APIError.notPaired }
        return try await client.phoneDevices().devices ?? []
    }

    // MARK: Health

    /// `GET /api/phone/session`: is the token still good, and who is this.
    func checkSession() async {
        guard !isPreview, let client, !checking else { return }
        checking = true
        defer { checking = false }
        do {
            let session = try await client.phoneSession()
            lastContact = Date()
            if var current = desktop {
                current.username = session.account?.username ?? current.username
                current.isAdmin = session.account?.isAdmin ?? current.isAdmin
                current.color = session.account?.color ?? current.color
                current.serverName = session.server?.name ?? current.serverName
                current.serverVersion = session.server?.version ?? current.serverVersion
                if let id = session.deviceId, !id.isEmpty { current.deviceId = id }
                if current != desktop { save(current) }
            }
            let wasConnected = state == .connected
            set(.connected)
            if !wasConnected || !stream.isRunning { becameReady() }
        } catch APIError.unauthorized {
            tokenRefused()
        } catch let error as APIError {
            set(.offline(error.isOffline ? error.plain : "Your desktop answered, but not as expected. " + error.plain))
            // Keep knocking: the stream retries with a growing wait and flips the state when it opens.
            if !stream.isRunning { stream.start(client: client) }
        } catch {
            set(.offline("Your desktop could not be reached. Trying again."))
            if !stream.isRunning { stream.start(client: client) }
        }
    }

    /// A request elsewhere in the app failed; let the state follow.
    func note(_ error: Error) {
        guard !isPreview, let error = error as? APIError else { return }
        switch error {
        case .unauthorized:
            tokenRefused()
        case .offline(let reason):
            if state == .connected { set(.offline(reason)) }
        default:
            break
        }
    }

    // MARK: Private

    private func makeClient(base: URL, token: String) -> APIClient {
        APIClient(base: base, token: token)
    }

    private func set(_ new: State) {
        guard state != new else { return }
        state = new
        onChange?()
    }

    private func save(_ paired: PairedDesktop) {
        desktop = paired
        if let data = try? JSONEncoder().encode(paired) {
            UserDefaults.standard.set(data, forKey: Connection.desktopKey)
        }
    }

    private func forget() {
        stream.stop()
        client = nil
        desktop = nil
        Keychain.delete(account: Connection.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Connection.desktopKey)
    }

    private func tokenRefused() {
        stream.stop()
        client = nil
        Keychain.delete(account: Connection.tokenAccount)
        set(.signedOut)
    }

    private func streamChanged(_ open: Bool) {
        if open {
            lastContact = Date()
            if state != .connected, state != .signedOut, state != .sample {
                set(.connected)
                Task { await checkSession() }
            }
            onStreamOpen?()
        } else if state == .connected {
            set(.offline("Your desktop stopped answering. Trying again."))
        }
    }

    /// The desktop is answering with a good token: open the live stream and hand over what was waiting.
    private func becameReady() {
        guard let client else { return }
        if !stream.isRunning { stream.start(client: client) }
        if let tokens = pushTokens {
            Task { await self.sendPushTokens(apns: tokens.apns, voip: tokens.voip) }
        }
        for (id, entry) in activityTokens {
            Task { try? await client.phonePushActivity(activityId: id, kind: entry.kind, pushToken: entry.token) }
        }
    }

    // MARK: The push seam

    /// Fill in `Native/PushBridge.swift`. Tokens that arrive before a desktop is paired are kept
    /// and sent the moment one is.
    private func wirePushBridge() {
        PushBridge.registerTokens = { apns, voip in
            await Connection.shared.rememberPushTokens(apns: apns, voip: voip)
        }
        PushBridge.detailChanged = {
            await Connection.shared.resendPushTokens()
        }
        PushBridge.registerActivity = { activityID, kind, token in
            await Connection.shared.rememberActivity(id: activityID, kind: kind, token: token)
        }
        PushBridge.answer = { requestID, choice, text in
            await Connection.shared.answerFromNotification(requestID: requestID, choice: choice, text: text)
        }
        PushBridge.ring = { ringID, answer, deadline in
            await Connection.shared.answerRing(ringID, answer: answer, until: deadline)
        }
        PushBridge.ringState = { ringID in
            await Connection.shared.ringStatus(ringID)
        }
        PushBridge.isPaired = {
            Connection.shared.isPaired && Connection.shared.client != nil
        }
        PushBridge.awaitingUnlock = {
            Connection.shared.waitingForUnlock
        }
        PushBridge.liveBot = { botID in
            let store = ChatStore.shared
            return store.isSample ? nil : store.bots.first(where: { $0.id == botID })
        }
    }

    private func rememberPushTokens(apns: String, voip: String?) async {
        pushTokens = (apns, voip)
        await sendPushTokens(apns: apns, voip: voip)
    }

    private func resendPushTokens() async {
        guard let tokens = pushTokens else { return }
        await sendPushTokens(apns: tokens.apns, voip: tokens.voip)
    }

    private func sendPushTokens(apns: String, voip: String?) async {
        guard let client, state == .connected else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let locale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        do {
            try await client.phonePushRegister(apns: apns, voip: voip, environment: environment, locale: locale,
                                               detail: NativeSettings.detail.rawValue)
        } catch {
            note(error)
        }
    }

    private func rememberActivity(id: String, kind: String, token: String) async {
        activityTokens[id] = (kind, token)
        guard let client, state == .connected else { return }
        do {
            try await client.phonePushActivity(activityId: id, kind: kind, pushToken: token)
        } catch {
            note(error)
        }
    }

    /// An approval or a question answered from a notification. With no text it is a choice on a live
    /// request; with text it is a reply to a bot's inbox row.
    private func answerFromNotification(requestID: String, choice: String, text: String?) async {
        guard let client else { return }
        do {
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let rows = try await client.botNeedsYou().rows ?? []
                if let row = rows.first(where: { $0.id == requestID || $0.sourceId == requestID || $0.id.hasSuffix(":" + requestID) }) {
                    let action = (row.actions ?? []).contains("reply") ? "reply" : choice
                    if let question = row.questions?.first?.question, (row.actions ?? []).contains("respond") {
                        _ = try await client.botInboxRespond(row.id, action: "respond", expectedRevision: row.revision ?? "", answers: [question: text])
                    } else {
                        _ = try await client.botInboxRespond(row.id, action: action, expectedRevision: row.revision ?? "", text: text)
                    }
                    return
                }
            }
            _ = try await client.permissionAnswer(requestID, choice: choice)
        } catch {
            note(error)
        }
    }

    /// Answer or decline a ring. A ring can wake a closed app before the connection is up, so this starts it
    /// when needed and keeps trying every two seconds until `deadline`. A later try that finds the ring already
    /// answered (or declined) checks whether an earlier try got there first, so one answer never counts twice
    /// and is never mistaken for an answer somewhere else.
    private func answerRing(_ ringID: String, answer: Bool, until deadline: Date) async -> RingReply {
        guard !isPreview, !Connection.isDebugViewLaunch else { return .sample }
        if client == nil { start() }
        // Before the first unlock the pairing cannot be read: wait for it, within the ring's life. Never
        // take that for "not paired" (that would show a pretend call the desktop never hears of).
        while waitingForUnlock {
            guard !Task.isCancelled, Date().addingTimeInterval(1) < deadline else { return .failed }
            try? await Task.sleep(for: .seconds(1))
            start()
        }
        guard state != .sample else { return .sample }
        var tried = false
        while !Task.isCancelled {
            guard let client else { return .failed }
            do {
                if answer {
                    let reply = try await client.ringAnswer(ringID, viaLink: true)
                    return .sent(botID: reply.agentId, botName: reply.botName)
                }
                try await client.ringDecline(ringID)
                return .sent(botID: nil, botName: nil)
            } catch APIError.unreadable {
                // The desktop said yes (a 2xx) in a shape this phone cannot read: it counted.
                return .sent(botID: nil, botName: nil)
            } catch APIError.server(let code, _) where code == 404 || code == 409 {
                // The ring is over on the desktop.
                let now = try? await client.phoneRingState(ringID)
                let outcome = now?.status ?? "expired"
                if tried, outcome == (answer ? "answered" : "declined") {
                    return .sent(botID: now?.agentId, botName: now?.botName)
                }
                return .ended(outcome)
            } catch APIError.unauthorized {
                tokenRefused()
                return .failed
            } catch APIError.server(let code, _) where code < 500 {
                // The desktop refused this try outright: it did not count. Try again until the deadline.
            } catch {
                // Not reached, the reply was lost, or the desktop failed partway: an earlier try may have counted.
                tried = true
                note(error)
            }
            guard !Task.isCancelled, Date().addingTimeInterval(2) < deadline else { return .failed }
            try? await Task.sleep(for: .seconds(2))
        }
        return .failed
    }

    /// `GET /api/rings/{id}`: where a ring stands. nil when there is no client or it could not be read.
    private func ringStatus(_ ringID: String) async -> String? {
        guard let client else { return nil }
        do {
            return try await client.phoneRingState(ringID).status
        } catch {
            note(error)
            return nil
        }
    }
}
