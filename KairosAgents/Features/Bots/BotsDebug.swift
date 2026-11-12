import SwiftUI

/// Debug views for the Bots area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView bots.<name>` (see docs/DEV-GUIDE.md).
enum BotsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
