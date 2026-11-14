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
    /// Paired: a change that asks first.
    case confirm(DriveLiveConfirm)

    var id: String {
        switch self {
        case .accounts: "accounts"
        case .newMenu: "new"
        case .move(let ids): "move-\(ids.joined(separator: ","))"
        case .confirm(let ask): "confirm-\(ask.id)"
        }
    }
}

/// A change to the paired desktop's Drive that is confirmed first, naming what it touches.
struct DriveLiveConfirm: Identifiable {
    let id = UUID().uuidString
    let title: String
    let detail: String
    let confirm: String
    var danger = true
    let action: () -> Void
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
    /// The text the naming prompt was filled with, so an unchanged name is not sent.
    var promptFilled = ""
    var importing = false
    /// Paired: a change to several files is on its way.
    var batchRunning = false

    /// Showing the paired desktop's Drive.
    var live: Bool { !store.isSample }

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
        promptFilled = text
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
        if live {
            savePromptLive(name)
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
        if live {
            receiveLive(urls)
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

    func count(_ ids: [String]) -> String {
        if ids.count == 1, let file = store.file(ids[0]) { return file.name }
        return "\(ids.count) files"
    }

    func copy(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        if live {
            let files = ids.filter { store.file($0)?.isFolder == false }
            guard !files.isEmpty else {
                toaster.say("Folders cannot be copied in Google Drive")
                return
            }
            runLive(files, done: { "Copied \($0)" }) { await self.store.copyLive($0) }
            return
        }
        let label = count(ids)
        withAnimation(Motion.snappy) { store.copy(ids) }
        Haptics.success()
        toaster.say("Copied \(label)")
    }

    func star(_ ids: [String], _ on: Bool) {
        guard !ids.isEmpty else { return }
        if live {
            runLive(ids, done: { on ? "Starred \($0)" : "Removed the star" }) { await self.store.starLive($0, on) }
            return
        }
        withAnimation(Motion.snappy) { store.setStarred(ids, on) }
        Haptics.select()
        toaster.say(on ? "Starred \(count(ids))" : "Removed the star")
    }

    func trash(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let label = count(ids)
        if live {
            runLive(ids, done: { "Moved \($0) to trash" }) { await self.store.trashLive($0) }
            selected.subtract(ids)
            return
        }
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
        if live {
            runLive(ids, done: { "Restored \($0)" }) { await self.store.restoreLive($0) }
            selected.subtract(ids)
            return
        }
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
        if live {
            Haptics.tap()
            Task {
                await store.loadAccountsLive()
                if let key = store.shownKey { await store.loadList(key) }
            }
            return
        }
        guard !loading else { return }
        withAnimation(Motion.snappy) { loading = true }
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(Motion.snappy) { loading = false }
            toaster.say("Drive is up to date")
        }
    }

    func switchAccount(_ account: DriveAccount) {
        if live { store.switchAccountLive(account.id) } else { store.switchAccount(account.id) }
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

// MARK: - Paired desktop

extension DriveUI {

    /// Trash asks first while paired, naming the files when there are a few, and the count and the place when
    /// there are many. Exactly these ids are sent. Unpaired it works as it always did.
    func askTrash(_ ids: [String], place: String? = nil) {
        guard !ids.isEmpty else { return }
        guard live else {
            trash(ids)
            return
        }
        let names = ids.compactMap { store.file($0)?.name }
        let title: String
        if ids.count == 1 {
            title = "Move \(count(ids)) to trash?"
        } else if ids.count <= 3, names.count == ids.count {
            title = "Move \(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1]) to trash?"
        } else {
            title = "Move \(ids.count) files in \(place ?? "this list") to trash?"
        }
        let folders = ids.contains { store.file($0)?.isFolder == true }
        let detail = (folders ? "A folder goes to the trash with everything in it. " : "")
            + (ids.count == 1 ? "It goes" : "They go") + " to the trash in Google Drive. You can restore "
            + (ids.count == 1 ? "it" : "them") + " from Trash."
        sheet = .confirm(DriveLiveConfirm(title: title, detail: detail, confirm: "Move to trash") { [weak self] in self?.trash(ids) })
    }

    /// Paired: drop the selection when what is on screen changes, so nothing unseen is ever acted on.
    func dropSelectionLive() {
        guard live, !selected.isEmpty else { return }
        selected = []
    }

    /// Run one change per file, one after another, and say how it went. It stops at the first file whose
    /// change could not be confirmed, so nothing more is sent on top of an unknown state.
    func runLive(_ ids: [String], done: @escaping (String) -> String, _ op: @escaping (String) async -> DriveLiveOutcome) {
        guard !batchRunning else {
            toaster.say("Wait for the last change to finish")
            return
        }
        let label = count(ids)
        batchRunning = true
        Task {
            defer { batchRunning = false }
            var finished = 0
            for id in ids {
                let outcome = await op(id)
                switch outcome {
                case .done:
                    finished += 1
                case .busy:
                    Haptics.thud()
                    store.liveNote = "\(finished) of \(ids.count) done. The rest were not sent: a change to one of them is still on its way."
                    store.refreshShownLive()
                    return
                case .failed(let why), .unconfirmed(let why):
                    Haptics.thud()
                    let start = ids.count > 1 ? "\(finished) of \(ids.count) done, the rest not sent. " : ""
                    store.liveNote = start + why
                    store.refreshShownLive()
                    return
                }
            }
            Haptics.success()
            toaster.say(done(label))
        }
    }

    func say(_ outcome: DriveLiveOutcome, done: String) {
        switch outcome {
        case .done:
            Haptics.success()
            toaster.say(done)
        case .busy:
            toaster.say("Wait for the last change to finish")
        case .failed(let why), .unconfirmed(let why):
            Haptics.thud()
            store.liveNote = why
        }
    }

    /// Move files one after another; stops at the first that could not be confirmed.
    func moveLive(_ ids: [String], to folder: String?) async {
        let place = folder.flatMap { store.file($0)?.name } ?? "My Drive"
        let label = count(ids)
        var finished = 0
        defer { selected = [] }
        for id in ids {
            let outcome = await store.moveLive(id, to: folder)
            switch outcome {
            case .done:
                finished += 1
            case .busy:
                Haptics.thud()
                store.liveNote = "\(finished) of \(ids.count) moved. The rest were not sent: a change to one of them is still on its way."
                store.refreshShownLive()
                return
            case .failed(let why), .unconfirmed(let why):
                Haptics.thud()
                store.liveNote = (ids.count > 1 ? "\(finished) of \(ids.count) moved, the rest not sent. " : "") + why
                store.refreshShownLive()
                return
            }
        }
        Haptics.success()
        toaster.say("Moved \(label) to \(place)")
    }

    fileprivate func savePromptLive(_ name: String) {
        let folder = currentFolder
        switch prompt {
        case .rename(let id):
            guard name != promptFilled.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            Task { say(await store.renameLive(id, to: name), done: "Renamed to \(name)") }
        case .newFolder, .newSheet, .newForm:
            let kind: DriveKind = prompt == .newFolder ? .folder : (prompt == .newSheet ? .sheet : .form)
            if folder == nil && section != .myDrive {
                section = .myDrive
                query = ""
            }
            toaster.say("Making \(name)")
            Task { say(await store.createLive(kind, name: name, in: folder), done: "\(name) created") }
        }
    }

    /// Paired: each file's size is read from its attributes, and anything over 25 MB or of unknown size is refused
    /// here, before any file is read. The files are then read and sent one at a time, off the main actor.
    fileprivate func receiveLive(_ urls: [URL]) {
        var outgoing: [DriveUploadItem] = []
        var tooBig: [String] = []
        var unknown: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey, .isDirectoryKey])
            if scoped { url.stopAccessingSecurityScopedResource() }
            let name = url.lastPathComponent
            guard values?.isDirectory != true, let size = values?.fileSize ?? values?.totalFileSize else {
                unknown.append(name)
                continue
            }
            if size > DriveWire.maxUpload {
                tooBig.append(name)
                continue
            }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            outgoing.append(DriveUploadItem(url: url, name: name, size: size, mimeType: mime))
        }
        if let first = tooBig.first {
            Haptics.thud()
            store.liveNote = tooBig.count == 1 ? "\(first) is over 25 MB, so it was not sent." : "\(tooBig.count) files are over 25 MB, so they were not sent."
        } else if let first = unknown.first {
            Haptics.thud()
            store.liveNote = "The size of \(first) could not be read, so it was not sent."
        }
        guard !outgoing.isEmpty else { return }
        guard !store.busy.contains("new") else {
            toaster.say("Wait for the upload on its way to finish")
            return
        }
        let folder = currentFolder
        if folder == nil && section != .myDrive {
            section = .myDrive
            query = ""
        }
        Task {
            let result = await store.uploadLive(outgoing, in: folder)
            let label = outgoing.count == 1 ? outgoing[0].name : "\(outgoing.count) files"
            switch result.outcome {
            case .done:
                Haptics.success()
                toaster.say("\(label) uploaded")
            case .busy:
                toaster.say("Wait for the upload on its way to finish")
            case .failed(let why), .unconfirmed(let why):
                Haptics.thud()
                store.liveNote = (outgoing.count > 1 ? "\(result.sent) of \(outgoing.count) uploaded, the rest not sent. " : "") + why
            }
        }
    }
}

/// Google Drive, opened as a full-screen cover from Library > Files.
struct DriveScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var toaster: FilesToaster
    @State private var ui: DriveUI

    /// `startFile` opens Drive straight on one file the store holds (its preview, or the folder itself), with Back
    /// leading to the top of Drive; used by Search. A file the store does not hold, or one in another Google
    /// account than the one Drive is browsing, is not opened, and Drive opens at its top as usual. Without it,
    /// Drive opens exactly as before.
    init(debug: DriveDebug = .none, startFile: String? = nil) {
        let toaster = FilesToaster()
        let ui = DriveUI(store: DriveStore.shared, toaster: toaster, debug: debug)
        if let startFile, let file = ui.store.file(startFile), file.account == ui.store.currentAccountID {
            ui.path = [ui.route(for: file)]
        }
        _toaster = State(initialValue: toaster)
        _ui = State(initialValue: ui)
    }

    var body: some View {
        NavigationStack(path: $ui.path) {
            DriveBrowser(folderID: nil, close: { dismiss() })
                .navigationDestination(for: DriveRoute.self) { route in
                    destination(route)
                }
        }
        .environment(ui)
        .task(id: DriveStore.connectionKey) {
            let store = ui.store
            let wasSample = store.isSample
            let wasAccount = store.liveAccount
            store.followConnection()
            // A change of desktop or Kairos account leaves no folder or selection from the one before.
            if wasSample != store.isSample || (!store.isSample && wasAccount != store.liveAccount) {
                ui.path = []
                ui.selected = []
                ui.selecting = false
            }
            guard !store.isSample else { return }
            switch store.accountsLoad {
            case .idle, .failed: await store.loadAccountsLive()
            case .loading, .loaded: break
            }
        }
        .onChange(of: ui.query) { ui.dropSelectionLive() }
        .onChange(of: ui.filter) { ui.dropSelectionLive() }
        .onChange(of: ui.section) { ui.dropSelectionLive() }
        .onChange(of: ui.grid) { ui.dropSelectionLive() }
        .onChange(of: ui.path) { ui.dropSelectionLive() }
        .onChange(of: ui.store.currentAccountID) { ui.dropSelectionLive() }
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
        case .confirm(let ask): ConfirmSheet(title: ask.title, detail: ask.detail, confirm: ask.confirm, danger: ask.danger, action: ask.action)
        }
    }
}
