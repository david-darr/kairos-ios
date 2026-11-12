import SwiftUI

/// Places inside Make. Studio, the editor and a design cover the tab bar, so they open in their own
/// full-screen stack (`MakeCover`) and push with these routes.
nonisolated enum MakeRoute: Hashable, Identifiable, Sendable {
    case studio
    case editor(String)
    case designs
    case design(String)
    case made(MadeKind)

    var id: String {
        switch self {
        case .studio: "studio"
        case .editor(let id): "editor-\(id)"
        case .designs: "designs"
        case .design(let id): "design-\(id)"
        case .made(let kind): "made-\(kind.rawValue)"
        }
    }
}

struct MakeRouteView: View {
    let route: MakeRoute

    var body: some View {
        switch route {
        case .studio: StudioScreen()
        case .editor(let id): VideoEditorScreen(projectID: id)
        case .designs: DesignListScreen()
        case .design(let id): DesignScreen(designID: id)
        case .made(let kind): MadeListScreen(kind: kind)
        }
    }
}

extension View {
    /// Every Make screen can push every other one.
    func makeDestinations() -> some View {
        navigationDestination(for: MakeRoute.self) { MakeRouteView(route: $0) }
    }
}

/// A full-screen stack for one Make place, over the tab bar.
struct MakeCover: View {
    let start: MakeRoute
    let store: MakeStore
    let toast: MakeToast
    @State private var path: [MakeRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            MakeRouteView(route: start)
                .makeDestinations()
        }
        .environment(store)
        .environment(toast)
        .makeToasts(toast)
    }
}

/// Debug builds: hosts one Make view with the store and toasts around it.
struct MakeDebugHost<Content: View>: View {
    @State private var store = MakeStore()
    @State private var toast = MakeToast()
    var setup: (MakeStore) -> Void = { _ in }
    @ViewBuilder var content: Content

    var body: some View {
        content
            .makeDestinations()
            .environment(store)
            .environment(toast)
            .makeToasts(toast)
            .onAppear { setup(store) }
    }
}
