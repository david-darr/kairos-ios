import SwiftUI

/// Debug views for the Native area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView native.<name>` (see docs/DEV-GUIDE.md).
enum NativeDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
