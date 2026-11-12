import Foundation
import Observation

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
    func start() {
        guard !isPreview, !started else { return }
        started = true
        guard let data = UserDefaults.standard.data(forKey: Connection.desktopKey),
              let saved = try? JSONDecoder().decode(PairedDesktop.self, from: data) else { return }
        desktop = saved
        guard let token = Keychain.read(account: Connection.tokenAccount),
              let base = APIClient.baseURL(from: saved.address) else {
            set(.signedOut)
            return
        }
        client = makeClient(base: base, token: token)
        set(.connecting)
        Task { await checkSession() }
    }

    /// Call when the app comes back to the front.
    func wake() {
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
        started = true
        set(.connected)
        becameReady()
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
        PushBridge.registerActivity = { activityID, kind, token in
            await Connection.shared.rememberActivity(id: activityID, kind: kind, token: token)
        }
        PushBridge.answer = { requestID, choice, text in
            await Connection.shared.answerFromNotification(requestID: requestID, choice: choice, text: text)
        }
        PushBridge.ring = { ringID, answer in
            await Connection.shared.answerRing(ringID, answer: answer)
        }
    }

    private func rememberPushTokens(apns: String, voip: String?) async {
        pushTokens = (apns, voip)
        await sendPushTokens(apns: apns, voip: voip)
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
            try await client.phonePushRegister(apns: apns, voip: voip, environment: environment, locale: locale)
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

    private func answerRing(_ ringID: String, answer: Bool) async {
        guard let client else { return }
        do {
            if answer {
                _ = try await client.ringAnswer(ringID, viaLink: true)
            } else {
                try await client.ringDecline(ringID)
            }
        } catch {
            note(error)
        }
    }
}
