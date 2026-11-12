import SwiftUI

/// Debug views for the Desktop area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView desktop.<name>` (see docs/DEV-GUIDE.md).
enum DesktopDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
