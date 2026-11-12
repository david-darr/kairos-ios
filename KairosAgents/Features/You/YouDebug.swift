import SwiftUI

/// Debug views for the You area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView you.<name>` (see docs/DEV-GUIDE.md).
enum YouDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
