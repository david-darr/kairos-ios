import SwiftUI

/// Debug views for the You area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView you.<name>` (see docs/DEV-GUIDE.md).
/// Each screen file answers for its own names; `route.<x>` names open a screen by its route.
enum YouDebug {
    static func view(_ name: String) -> AnyView? {
        let found = YouHomeDebug.view(name)
            ?? AccountDebug.view(name)
            ?? ModelsDebug.view(name)
            ?? VoiceDebug.view(name)
            ?? NotifyDebug.view(name)
            ?? ChannelsDebug.view(name)
            ?? VaultPhoneDebug.view(name)
            ?? AccessDebug.view(name)
            ?? IntegrationsDebug.view(name)
            ?? LookDebug.view(name)
            ?? BotsSettingsDebug.view(name)
            ?? AdminDebug.view(name)
            ?? StoreDebug.view(name)
        return found.map { AnyView($0.youDestinations()) }
    }
}
