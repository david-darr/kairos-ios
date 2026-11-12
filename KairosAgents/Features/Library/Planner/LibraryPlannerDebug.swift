import SwiftUI

/// Debug views for the Library planner area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView library.<name>` (see docs/DEV-GUIDE.md).
enum LibraryPlannerDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
