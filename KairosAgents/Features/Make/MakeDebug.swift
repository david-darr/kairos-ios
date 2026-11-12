import SwiftUI

/// Debug views for the Make area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView make.<name>` (see docs/DEV-GUIDE.md).
enum MakeDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "root": return AnyView(MakeView())
        case "typed": return AnyView(MakeView(debugState: "typed"))
        case "making": return AnyView(MakeView(debugState: "making"))
        case "result": return AnyView(MakeView(debugState: "result"))
        case "videos": return host(MadeListScreen(kind: .video))
        case "documents": return host(MadeListScreen(kind: .document))
        case "confirm":
            return AnyView(Color.clear.kScreen().sheet(isPresented: .constant(true)) {
                MakeSwipeUpConfirm(title: "Approve this post?", detail: "Clean your chain in 60 seconds, for @trailtips.", points: ["It moves to Publishing, ready to prepare.", "Nothing is posted until you press Post."], confirmLabel: "Swipe up to approve") {}
            })
        default:
            break
        }
        if name.hasPrefix("studio") {
            return AnyView(MakeDebugHost(setup: { $0.studio.debugOpen(name) }) { StudioScreen() })
        }
        if let view = VideoEditorDebug.view(name) { return host(view) }
        if let view = DesignsDebug.view(name) { return host(view) }
        return nil
    }

    private static func host<V: View>(_ view: V) -> AnyView {
        AnyView(MakeDebugHost { view })
    }
}
