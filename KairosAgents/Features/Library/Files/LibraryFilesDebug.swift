import SwiftUI

/// Debug views for the Library files area, so the build can take a picture of any screen in it.
/// Launch with `-kDebugView library.<name>` (see docs/DEV-GUIDE.md).
enum LibraryFilesDebug {
    static func view(_ name: String) -> AnyView? {
        let plan = "Projects/Bike shop/Launch plan"
        switch name {
        // The sections as they sit in the Library tab
        case "files-section": return AnyView(FilesDebugTab(section: .files))
        case "notes-section": return AnyView(FilesDebugTab(section: .notes))
        case "notes-empty": return AnyView(NotesDebugView(state: .empty))
        case "notes-details": return AnyView(NotesDebugView(state: .details))
        case "notes-composing": return AnyView(NotesDebugView(state: .composing))

        // Chat documents, uploads and the document editor
        case "files-chatdocs": return AnyView(FilesDebugCover { ChatDocumentsScreen() })
        case "files-chatdocs-search": return AnyView(FilesDebugCover { ChatDocumentsScreen(debug: .search) })
        case "files-chatdocs-empty": return AnyView(FilesDebugCover { ChatDocumentsScreen(debug: .empty) })
        case "files-uploads": return AnyView(FilesDebugCover { UploadsScreen() })
        case "files-editor": return AnyView(FilesDebugCover { LibraryDocumentEditor(documentID: LibraryDocumentsStore.shared.documents.first?.id) })

        // The Vault
        case "vault-home": return AnyView(FilesDebugCover { VaultScreen() })
        case "vault-search": return AnyView(FilesDebugCover { VaultScreen(debug: .search) })
        case "vault-folder": return AnyView(FilesDebugCover { VaultScreen(route: .folder("Daily notes")) })
        case "vault-list": return AnyView(FilesDebugCover { VaultScreen(route: .list(.missingProperties)) })
        case "vault-note": return AnyView(FilesDebugCover { VaultScreen(start: .note(plan)) })
        case "vault-links": return AnyView(FilesDebugCover { VaultScreen(start: .note(plan), debug: .links) })
        case "vault-history": return AnyView(FilesDebugCover { VaultScreen(start: .note(plan), debug: .history) })
        case "vault-write": return AnyView(FilesDebugCover { VaultScreen(start: .note(plan), debug: .write) })
        case "vault-preview": return AnyView(FilesDebugCover { VaultScreen(start: .note(plan), debug: .preview) })
        case "vault-conflict": return AnyView(FilesDebugCover { VaultScreen(start: .note(plan), debug: .conflict) })
        case "vault-map": return AnyView(FilesDebugCover { VaultScreen(start: .map) })
        case "vault-peek": return AnyView(FilesDebugCover { VaultScreen(debug: .peek, route: .map(plan)) })
        case "vault-focus": return AnyView(FilesDebugCover { VaultScreen(debug: .focus, route: .map(plan)) })

        // Google Drive
        case "drive-home": return AnyView(FilesDebugCover { DriveScreen() })
        case "drive-folder": return AnyView(FilesDebugCover { DriveScreen(debug: .folder) })
        case "drive-select": return AnyView(FilesDebugCover { DriveScreen(debug: .select) })
        case "drive-details": return AnyView(FilesDebugCover { DriveScreen(debug: .details) })
        case "drive-share": return AnyView(FilesDebugCover { DriveScreen(debug: .share) })
        case "drive-new": return AnyView(FilesDebugCover { DriveScreen(debug: .newMenu) })
        case "drive-accounts": return AnyView(FilesDebugCover { DriveScreen(debug: .accounts) })
        case "drive-sheet": return AnyView(FilesDebugCover { DriveScreen(debug: .sheetEditor) })
        case "drive-form": return AnyView(FilesDebugCover { DriveScreen(debug: .formEditor) })
        case "drive-preview": return AnyView(FilesDebugCover { DriveScreen(debug: .preview) })
        default: return nil
        }
    }
}

/// The Library tab opened on one section, for pictures.
private struct FilesDebugTab: View {
    let section: LibrarySection
    @Environment(AppRouter.self) private var router

    var body: some View {
        LibraryView()
            .onAppear { router.librarySection = section }
    }
}

/// Shows a full-screen place the way the app does: as a cover, so its own navigation works.
private struct FilesDebugCover<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var shown = false

    var body: some View {
        Ground()
            .fullScreenCover(isPresented: $shown) {
                content()
                    .environment(router)
                    .environment(chrome)
            }
            .onAppear {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { shown = true }
            }
    }
}
