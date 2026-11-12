import SwiftUI

/// Debug views for the Home and chats area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView chat.<name>` (see docs/DEV-GUIDE.md).
enum ChatDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        // The decoders, as a pass or fail list.
        case "decoders": return AnyView(DecodeChecksView())

        // Pairing.
        case "connect":
            return AnyView(PairingForm(back: {}, skipTitle: "Look around first", onPaired: {}).kScreen())
        case "connect-filled":
            return AnyView(PairingForm(back: {}, skipTitle: "Look around first", onPaired: {},
                                       startAddress: "desk.example.com", startCode: "482913", startBusy: true).kScreen())
        case "connect-error":
            return AnyView(PairingForm(back: {}, skipTitle: "Look around first", onPaired: {},
                                       startAddress: "desk.example.com", startCode: "48291",
                                       startNote: "That code is not right or has expired.").kScreen())

        // The connection page in each state.
        case "connection":
            return AnyView(ConnectionScreen(connection: Connection(preview: .connected), sampleDevices: ChatDebug.devices))
        case "connection-offline":
            return AnyView(ConnectionScreen(connection: Connection(preview: .offline("Your desktop did not answer. Check that Kairos is open and remote access is on."))))
        case "connection-signedout":
            return AnyView(ConnectionScreen(connection: Connection(preview: .signedOut)))
        case "connection-none":
            return AnyView(ConnectionScreen(connection: Connection(preview: .sample)))

        default: return nil
        }
    }

    static let devices = [
        PhoneDeviceDTO(id: "d_1", name: "iPhone", model: "iPhone17,1",
                       createdAt: FlexibleDate(date: Date(timeIntervalSince1970: 1_794_300_000)),
                       lastSeenAt: FlexibleDate(date: Date(timeIntervalSince1970: 1_794_390_000)), current: true),
        PhoneDeviceDTO(id: "d_2", name: "Old phone", model: "iPhone15,2",
                       createdAt: FlexibleDate(date: Date(timeIntervalSince1970: 1_790_000_000)),
                       lastSeenAt: nil, current: false),
    ]
}
