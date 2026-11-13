import Foundation

// The phone's own routes on the desktop, exactly as docs/PHONE-API.md describes them.
// Times on these routes are ISO 8601 text; `FlexibleDate` also accepts epoch seconds.

nonisolated struct PhoneAccountDTO: Decodable, Hashable, Sendable {
    var username: String?
    var isAdmin: Bool?
    var color: String?
}

nonisolated struct PhoneServerDTO: Decodable, Hashable, Sendable {
    var name: String?
    var version: String?
}

/// POST /api/phone/pair/claim. The token is shown once and goes straight to the Keychain.
nonisolated struct PhonePairClaimDTO: Decodable, Sendable {
    var token: String
    var deviceId: String?
    var account: PhoneAccountDTO?
    var server: PhoneServerDTO?
}

/// GET /api/phone/session.
nonisolated struct PhoneSessionDTO: Decodable, Hashable, Sendable {
    var account: PhoneAccountDTO?
    var deviceId: String?
    var server: PhoneServerDTO?
}

nonisolated struct PhoneDeviceDTO: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String?
    var model: String?
    var createdAt: FlexibleDate?
    var lastSeenAt: FlexibleDate?
    var current: Bool?
}

/// GET /api/phone/devices.
nonisolated struct PhoneDevicesDTO: Decodable, Hashable, Sendable {
    var devices: [PhoneDeviceDTO]?
}

nonisolated struct PhoneUsageDTO: Decodable, Hashable, Sendable {
    var provider: String?
    var percent: Double?
    var resetsAt: FlexibleDate?
}

nonisolated struct PhoneNextEventDTO: Decodable, Hashable, Sendable {
    var title: String?
    var startsAt: FlexibleDate?
    var allDay: Bool?
}

/// GET /api/phone/home: the small read for the top of Home and for widgets.
nonisolated struct PhoneHomeDTO: Decodable, Hashable, Sendable {
    var usage: [PhoneUsageDTO]?
    var nextEvent: PhoneNextEventDTO?
    var needsYou: Int?
    var running: Int?
}

/// GET /api/rings/{ring_id}.
nonisolated struct PhoneRingStateDTO: Decodable, Hashable, Sendable {
    var id: String?
    var agentId: String?
    var botName: String?
    /// "ringing", "answered", "declined" or "expired".
    var status: String?
    var secondsLeft: Double?
}

extension APIClient {
    /// POST /api/phone/pair/claim. No token yet: the code is the proof.
    func phonePairClaim(code: String) async throws -> PhonePairClaimDTO {
        try await post("/api/phone/pair/claim", json: [
            "code": code,
            "device_name": APIClient.deviceName,
            "device_model": APIClient.deviceModel,
            "app_version": APIClient.appVersion,
        ])
    }

    func phoneSession() async throws -> PhoneSessionDTO {
        try await get("/api/phone/session")
    }

    func phoneDevices() async throws -> PhoneDevicesDTO {
        try await get("/api/phone/devices")
    }

    /// DELETE /api/phone/devices/{id}: unpair a phone. Its token stops working at once.
    func phoneUnpair(deviceId: String) async throws {
        try await call("DELETE", "/api/phone/devices/\(deviceId)")
    }

    func phoneHome() async throws -> PhoneHomeDTO {
        try await get("/api/phone/home")
    }

    /// POST /api/phone/push/register. Sending again replaces the registration.
    /// `detail` is the notice level (`generic` or `hideTitles`); with `hideTitles` the desktop sends no chat titles.
    func phonePushRegister(apns: String, voip: String?, environment: String, locale: String, detail: String) async throws {
        var body: [String: Any] = ["apns_token": apns, "environment": environment, "locale": locale, "detail": detail]
        if let voip { body["voip_token"] = voip } else { body["voip_token"] = NSNull() }
        try await call("POST", "/api/phone/push/register", json: body)
    }

    func phonePushUnregister() async throws {
        try await call("DELETE", "/api/phone/push/register")
    }

    /// POST /api/phone/push/activity: a Live Activity's own push token.
    func phonePushActivity(activityId: String, kind: String, pushToken: String) async throws {
        try await call("POST", "/api/phone/push/activity", json: [
            "activity_id": activityId,
            "kind": kind,
            "push_token": pushToken,
        ])
    }

    func phoneRingState(_ ringId: String) async throws -> PhoneRingStateDTO {
        try await get("/api/rings/\(ringId)")
    }
}
