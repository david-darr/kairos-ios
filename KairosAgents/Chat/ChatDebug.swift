import SwiftUI

/// Debug views for the Home and chats area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView chat.<name>` (see docs/DEV-GUIDE.md).
enum ChatDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
