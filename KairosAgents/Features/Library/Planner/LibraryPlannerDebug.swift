import SwiftUI

/// Debug views for the Library planner area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView library.<name>` (see docs/DEV-GUIDE.md).
/// Names start with `calendar-`, `mail-` or `tasks-`; the whole name is handed to that section
/// as `router.debugScreen`, and the section opens itself in that state (a view, a sheet).
enum LibraryPlannerDebug {
    static func view(_ name: String) -> AnyView? {
        if name.hasPrefix("calendar-") { return AnyView(PlannerDebugHost(section: .calendar, state: name)) }
        if name.hasPrefix("mail-") { return AnyView(PlannerDebugHost(section: .mail, state: name)) }
        if name.hasPrefix("tasks-") { return AnyView(PlannerDebugHost(section: .tasks, state: name)) }
        return nil
    }
}
