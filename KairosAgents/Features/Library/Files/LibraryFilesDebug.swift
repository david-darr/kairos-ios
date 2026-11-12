import SwiftUI

/// Debug views for the Library files area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView library.<name>` (see docs/DEV-GUIDE.md).
enum LibraryFilesDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: return nil
        }
    }
}
