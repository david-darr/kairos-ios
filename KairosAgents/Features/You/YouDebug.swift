import SwiftUI

/// Debug views for the You area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView you.<name>` (see docs/DEV-GUIDE.md).
/// Each screen file answers for its own names.
enum YouDebug {
    private static let sources: [(String) -> AnyView?] = [
        YouHomeDebug.view, AccountDebug.view, ModelsDebug.view, VoiceDebug.view,
        NotifyDebug.view, ChannelsDebug.view, VaultPhoneDebug.view, AccessDebug.view,
        IntegrationsDebug.view, LookDebug.view, BotsSettingsDebug.view, AdminDebug.view,
        StoreDebug.view,
    ]

    static func view(_ name: String) -> AnyView? {
        for source in sources {
            if let found = source(name) { return AnyView(found.youDestinations()) }
        }
        return nil
    }
}
