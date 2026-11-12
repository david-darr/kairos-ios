import SwiftUI

/// Debug views for Computer, Local models and Files on this PC.
enum MachineDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "computer": return AnyView(ComputerScreen())
        case "computer-control": return AnyView(ComputerScreen(start: .control))
        case "computer-steps": return AnyView(ComputerScreen(start: .steps))
        case "computer-closed": return AnyView(ComputerScreen(start: .closed))
        case "models": return AnyView(LocalModelsScreen())
        case "models-engine": return AnyView(LocalModelsScreen(engine: .builtIn))
        case "models-empty": return AnyView(LocalModelsScreen(empty: true))
        case "models-offline": return AnyView(LocalModelsScreen(offline: true))
        case "models-setup": return AnyView(LocalModelsScreen(setup: true))
        case "files": return AnyView(PCFilesScreen())
        case "files-folder": return AnyView(PCFilesScreen(path: "Projects/shop-site"))
        case "files-preview": return AnyView(PCFilesScreen(path: "Documents", preview: "Documents/Shop opening plan.md"))
        default: return nil
        }
    }
}
