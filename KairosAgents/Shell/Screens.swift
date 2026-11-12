import SwiftUI

/// Where each area's screens plug into the shell. Area teams fill in their own files; this file only routes.
enum AreaScreens {
    @ViewBuilder
    static func view(for area: JumpArea) -> some View {
        switch area {
        case .computer: ComputerScreen()
        case .browse: BrowseScreen()
        case .toolStore: ToolStoreScreen()
        case .addTab: AddTabScreen()
        default: AreaView(title: area.title, symbol: area.symbol, about: area.about)
        }
    }
}

/// Debug builds can open any one screen by name: `-kDebugView <area>.<name>`.
/// Each area answers for its own names in its own Debug file.
enum DebugGallery {
    static func view(named name: String) -> AnyView? {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "library": return LibraryFilesDebug.view(parts[1]) ?? LibraryPlannerDebug.view(parts[1])
        case "make": return MakeDebug.view(parts[1])
        case "desktop": return DesktopDebug.view(parts[1])
        case "you": return YouDebug.view(parts[1])
        case "bots": return BotsDebug.view(parts[1])
        case "chat": return ChatDebug.view(parts[1])
        case "native": return NativeDebug.view(parts[1])
        default: return nil
        }
    }
}

/// Hosts one debug view with everything a screen expects around it.
struct DebugHost: View {
    let name: String
    @State private var router = AppRouter()
    @State private var chrome = ChromeState()

    var body: some View {
        NavigationStack {
            Group {
                if let view = DebugGallery.view(named: name) {
                    view
                } else {
                    Text("No debug view named \(name)")
                        .font(KFont.ui(16))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .kScreen()
                }
            }
        }
        .environment(router)
        .environment(chrome)
    }
}
