import SwiftUI

/// Debug views for the Make area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView make.<name>` (see docs/DEV-GUIDE.md).
enum MakeDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
