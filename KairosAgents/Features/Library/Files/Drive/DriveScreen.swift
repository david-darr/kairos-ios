import SwiftUI
import UniformTypeIdentifiers

/// Debug states, so the build can photograph each part of Drive.
enum DriveDebug {
    case none, folder, select, details, share, newMenu, accounts, sheetEditor, formEditor, preview
}

/// Places inside the Drive cover.
enum DriveRoute: Hashable {
    case folder(String)
    case details(String)
    case sharing(String)
    case preview(String)
    case sheetEditor(String)
    case formEditor(String)
}

/// Sheets shown over the Drive cover.
enum DriveSheet: Identifiable {
    case accounts
    case newMenu
    case move([String])

    var id: String {
        switch self {
        case .accounts: "accounts"
        case .newMenu: "new"
        case .move(let ids): "move-\(ids.joined(separator: ","))"
        }
    }
}

/// The names asked for in the naming prompt.
enum DrivePrompt: Equatable {
    case newFolder, newSheet, newForm
    case rename(String)

    var title: String {
        switch self {
        case .newFolder: "New folder"
        case .newSheet: "New sheet"
        case .newForm: "New form"
        case .rename: "Rename"
        }
    }

    var placeholder: String {
        switch self {
        case .newFolder: "Folder name"
        case .newSheet: "Sheet title"
        case .newForm: "Form title"
        case .rename: "Name"
        }
    }
}

/// Something to do once the open sheet has closed.
enum DrivePending {
    case prompt(DrivePrompt)
    case importFiles
}

/// The whole cover's state: where you are, what is picked, and the shared actions.
@Observable
final class DriveUI {
    let store: DriveStore
    let toaster: FilesToaster

    var path: [DriveRoute] = []
    var section: DriveSection = .myDrive
    var filter: DriveFilter = .all
    var grid = false
    var query = ""
    var selecting = false
    var selected: Set<String> = []
    var loading = false
    var sheet: DriveSheet?
    var pending: DrivePending?
    var prompt: DrivePrompt = .newFolder
    var promptShown = false
    var promptText = ""
    var importing = false

    init(store: DriveStore, toaster: FilesToaster, debug: DriveDebug) {
        self.store = store
        self.toaster = toaster
        switch debug {
        case .none: break
        case .folder: path = [.folder(DriveSample.shopFolder)]
        case .select:
            selecting = true
            selected = [DriveSample.opening, DriveSample.rota]
        case .details: path = [.details(DriveSample.report)]
        case .share: path = [.sharing(DriveSample.report)]
        case .newMenu: sheet = .newMenu
        case .accounts: sheet = .accounts
        case .sheetEditor: path = [.sheetEditor(DriveSample.inventory)]
        case .formEditor: path = [.formEditor(DriveSample.survey)]
        case .preview: path = [.preview(DriveSample.report)]
        }
    }

    /// The folder you are standing in, if any.
    var currentFolder: String? {
        for route in path.reversed() {
            if case .folder(let id) = route { return id }
        }
        return nil
    }

    func route(for file: DriveFile) -> DriveRoute {
        if file.trashed { return .details(file.id) }
        return file.isFolder ? .folder(file.id) : .preview(file.id)
    }

    func open(_ file: DriveFile) {
        path.append(route(for: file))
    }

    // MARK: Sheets and prompts

    func ask(_ prompt: DrivePrompt, text: String = "") {
        self.prompt = prompt
        promptText = text
        promptShown = true
    }

    /// Closes the sheet, then does the next thing (a prompt or the file picker).
    func closeSheet(then next: DrivePending?) {
        pending = next
        sheet = nil
    }

    func runPending() {
        guard let next = pending else { return }
        pending = nil
        switch next {
        case .prompt(let prompt): ask(prompt)
        case .importFiles: importing = true
        }
    }

    func savePrompt() {
        let name = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            toaster.say("Give it a name first")
            return
        }
        switch prompt {
        case .newFolder: make(.folder, name)
        case .newSheet: make(.sheet, name)
        case .newForm: make(.form, name)
        case .rename(let id):
            withAnimation(Motion.snappy) { store.rename(id, to: name) }
            Haptics.success()
            toaster.say("Renamed to \(name)")
        }
    }

    private func make(_ kind: DriveKind, _ name: String) {
        let folder = currentFolder
        if folder == nil && section != .myDrive {
            section = .myDrive
            query = ""
        }
        withAnimation(Motion.snappy) { _ = store.create(kind, name: name, in: folder) }
        Haptics.success()
        toaster.say("\(name) created")
    }

    func receive(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            toaster.say("Could not read those files")
            return
        }
        let limit = 25 * 1_024 * 1_024
        var added: [String] = []
        var tooBig: [String] = []
        let folder = currentFolder
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if scoped { url.stopAccessingSecurityScopedResource() }
            let name = url.lastPathComponent
            if size > limit {
                tooBig.append(name)
                continue
            }
            if folder == nil && section != .myDrive {
                section = .myDrive
                query = ""
            }
            withAnimation(Motion.snappy) { _ = store.upload(name: name, size: Int64(size), in: folder) }
            added.append(name)
        }
        if let first = tooBig.first {
            Haptics.thud()
            toaster.say(tooBig.count == 1 ? "\(first) is over 25 MB" : "\(tooBig.count) files are over 25 MB")
        } else if let first = added.first {
            Haptics.success()
            toaster.say(added.count == 1 ? "\(first) uploaded" : "\(added.count) files uploaded")
        }
    }

    // MARK: Selection

    func toggle(_ id: String) {
        Haptics.select()
        withAnimation(Motion.snappy) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        }
    }

    func setSelecting(_ on: Bool) {
        withAnimation(Motion.snappy) {
            selecting = on
            if !on { selected = [] }
        }
    }

    func clearSelection() {
        withAnimation(Motion.snappy) { selected = [] }
    }

    // MARK: Actions on files

    private func count(_ ids: [String]) -> String {
        if ids.count == 1, let file = store.file(ids[0]) { return file.name }
        return "\(ids.count) files"
    }

    func copy(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let label = count(ids)
        withAnimation(Motion.snappy) { store.copy(ids) }
        Haptics.success()
        toaster.say("Copied \(label)")
    }

    func star(_ ids: [String], _ on: Bool) {
        guard !ids.isEmpty else { return }
        withAnimation(Motion.snappy) { store.setStarred(ids, on) }
        Haptics.select()
        toaster.say(on ? "Starred \(count(ids))" : "Removed the star")
    }

    func trash(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let label = count(ids)
        withAnimation(Motion.snappy) {
            store.trash(ids)
            selected.subtract(ids)
        }
        Haptics.thud()
        toaster.say("Moved \(label) to trash")
    }

    func restore(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let label = count(ids)
        withAnimation(Motion.snappy) {
            store.restore(ids)
            selected.subtract(ids)
        }
        Haptics.success()
        toaster.say("Restored \(label)")
    }

    func move(_ ids: [String], to folder: String?) {
        guard !ids.isEmpty else { return }
        let label = count(ids)
        let place = folder.flatMap { store.file($0)?.name } ?? "My Drive"
        withAnimation(Motion.snappy) {
            store.move(ids, to: folder)
            selected = []
        }
        Haptics.success()
        toaster.say("Moved \(label) to \(place)")
    }

    func deleteForever(_ id: String) {
        let label = count([id])
        withAnimation(Motion.snappy) { store.deleteForever(id) }
        Haptics.thud()
        toaster.say("Deleted \(label) forever")
    }

    func download(_ file: DriveFile) {
        Haptics.success()
        toaster.say("Saved \(file.name) to your desktop's Downloads")
    }

    func refresh() {
        guard !loading else { return }
        withAnimation(Motion.snappy) { loading = true }
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(Motion.snappy) { loading = false }
            toaster.say("Drive is up to date")
        }
    }

    func switchAccount(_ account: DriveAccount) {
        store.switchAccount(account.id)
        path = []
        selected = []
        selecting = false
        toaster.say("Browsing \(account.email)")
    }

    func disconnect(_ account: DriveAccount) {
        withAnimation(Motion.snappy) {
            store.disconnect(account.id)
            path = []
            selected = []
            selecting = false
        }
        toaster.say("Disconnected \(account.email)")
    }
}

/// Google Drive, opened as a full-screen cover from Library > Files.
struct DriveScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var toaster: FilesToaster
    @State private var ui: DriveUI

    init(debug: DriveDebug = .none) {
        let toaster = FilesToaster()
        _toaster = State(initialValue: toaster)
        _ui = State(initialValue: DriveUI(store: DriveStore.shared, toaster: toaster, debug: debug))
    }

    var body: some View {
        NavigationStack(path: $ui.path) {
            DriveBrowser(folderID: nil, close: { dismiss() })
                .navigationDestination(for: DriveRoute.self) { route in
                    destination(route)
                }
        }
        .environment(ui)
        .filesToasts(toaster)
        .sheet(item: $ui.sheet, onDismiss: { ui.runPending() }) { sheet in
            sheetContent(sheet)
                .environment(ui)
                .environment(toaster)
        }
        .alert(ui.prompt.title, isPresented: $ui.promptShown) {
            TextField(ui.prompt.placeholder, text: $ui.promptText)
            Button("Save") { ui.savePrompt() }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $ui.importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            ui.receive(result)
        }
    }

    @ViewBuilder
    private func destination(_ route: DriveRoute) -> some View {
        switch route {
        case .folder(let id): DriveBrowser(folderID: id, close: {})
        case .details(let id): DriveDetailsView(fileID: id, openSharing: false)
        case .sharing(let id): DriveDetailsView(fileID: id, openSharing: true)
        case .preview(let id): DrivePreviewView(fileID: id)
        case .sheetEditor(let id): DriveSheetEditor(fileID: id)
        case .formEditor(let id): DriveFormEditor(fileID: id)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: DriveSheet) -> some View {
        switch sheet {
        case .accounts: DriveAccountsSheet()
        case .newMenu: DriveNewSheet()
        case .move(let ids): DriveMoveSheet(ids: ids)
        }
    }
}
