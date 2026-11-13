import SwiftUI

/// The Drive list: the home of the cover (folderID nil) or one folder pushed on top of it.
struct DriveBrowser: View {
    let folderID: String?
    let close: () -> Void

    @Environment(DriveUI.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var confirmTrash = false

    private var store: DriveStore { ui.store }
    private var isRoot: Bool { folderID == nil }
    private var folder: DriveFile? { folderID.flatMap { store.file($0) } }

    private var items: [DriveFile] {
        if ui.live { return store.liveItems(liveKey) }
        return store.listing(section: ui.section, folder: folderID, query: isRoot ? ui.query : "", filter: ui.filter)
    }

    private var quickHome: Bool {
        isRoot && ui.section == .myDrive && ui.query.isEmpty && ui.filter == .all
    }

    private var showQuick: Bool {
        if ui.live { return quickHome && !quickFiles.isEmpty }
        return quickHome && !ui.loading && !store.recent(limit: 1).isEmpty
    }

    private var quickFiles: [DriveFile] {
        guard ui.live else { return store.recent(limit: 10) }
        return Array(store.liveItems(quickKey).filter { !$0.isFolder }.prefix(10))
    }

    // MARK: Paired desktop

    private var liveKey: DriveLiveKey? {
        store.key(section: ui.section, folder: folderID, query: isRoot ? ui.query : "", filter: ui.filter)
    }

    private var quickKey: DriveLiveKey? {
        store.key(section: .recent, folder: nil, query: "", filter: .all)
    }

    private var liveList: DriveLiveList? { liveKey.flatMap { store.lists[$0] } }

    private var liveTaskID: String {
        "\(DriveStore.connectionKey)|\(String(describing: liveKey))|\(store.currentAccountID ?? "")"
    }

    /// Read this list (and Quick access on the home) from the desktop. A search waits for typing to pause.
    private func loadLive() async {
        guard ui.live, let key = liveKey else { return }
        store.shownKey = key
        if !key.query.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
        }
        await store.loadList(key)
        if quickHome, let quick = quickKey, !Task.isCancelled { await store.loadList(quick) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isRoot {
                    rootTop
                } else {
                    breadcrumb
                }
                if ui.live { liveLines }
                if store.currentAccount != nil {
                    toolsRow
                    if showQuick { quickAccess }
                    results
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, ui.selecting ? 140 : 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if ui.selecting { selectionBar }
        }
        .kScreen()
        .confirmationDialog("Move selected files to trash?", isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Move to trash", role: .destructive) { ui.trash(Array(ui.selected)) }
            Button("Cancel", role: .cancel) {}
        }
        .animation(Motion.snappy, value: ui.selecting)
        .animation(Motion.snappy, value: ui.loading)
        .task(id: liveTaskID) { await loadLive() }
        .onAppear { if ui.live, let key = liveKey { store.shownKey = key } }
    }

    /// Paired: the last change's longer sentence, an upload's progress, and what the account says.
    @ViewBuilder
    private var liveLines: some View {
        if let note = store.liveNote {
            DriveLiveLine(text: note, action: "OK") { store.liveNote = nil }
        }
        if let progress = store.uploadProgress {
            VStack(alignment: .leading, spacing: 8) {
                Text("Uploading, \(Int(progress * 100)) percent sent")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                DriveStorageBar(fraction: progress)
            }
            .padding(14)
            .kCard(radius: 16)
            .accessibilityElement(children: .combine)
        }
        if isRoot, let account = store.currentAccount, account.broken {
            HintLine(text: (account.problem ?? "Sign-in expired or revoked") + " Reconnect it in Kairos on your desktop.",
                     symbol: "exclamationmark.circle", color: Palette.danger)
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if isRoot {
            FilesHeader(title: "Google Drive", subtitle: rootSubtitle, backSymbol: "chevron.down", backLabel: "Close Drive", back: close) {
                headerButtons
            }
        } else {
            FilesHeader(title: folder?.name ?? "Folder", subtitle: liveList?.load == .loading && items.isEmpty ? "Loading" : "\(items.count) items", back: { dismiss() }) {
                headerButtons
            }
        }
    }

    private var rootSubtitle: String {
        if !ui.query.isEmpty { return "Search results" }
        return ui.section.title
    }

    @ViewBuilder
    private var headerButtons: some View {
        if store.currentAccount != nil {
            GlassIconButton(symbol: "arrow.clockwise", label: "Refresh") { ui.refresh() }
            GlassIconButton(symbol: "plus", label: "Create or upload in Drive") {
                Haptics.tap()
                ui.sheet = .newMenu
            }
        }
    }

    // MARK: Top of the home

    @ViewBuilder
    private var rootTop: some View {
        if let account = store.currentAccount {
            Button {
                Haptics.tap()
                ui.sheet = .accounts
            } label: {
                DriveAccountCard(account: account)
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .arrives(0)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(DriveSection.allCases, id: \.self) { section in
                        FilterPill(title: section.title, symbol: section.symbol, on: ui.section == section) {
                            ui.section = section
                            ui.selected = []
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Drive views")

            FilesSearchField(text: queryBinding, prompt: "Search Drive")
        } else if ui.live && (store.accountsLoad == .loading || store.accountsLoad == .idle) {
            DriveLiveLine(text: "Reading your Google accounts.")
        } else if ui.live, case .failed(let why) = store.accountsLoad {
            DriveLiveLine(text: why, action: "Try again") { Task { await store.loadAccountsLive() } }
        } else {
            FilesEmpty(
                symbol: "person.crop.circle",
                title: "No Google account",
                detail: "Connect a Google account on the computer running Kairos, then open Drive again.",
                action: "Close Drive",
                perform: close
            )
        }
    }

    private var queryBinding: Binding<String> {
        Binding(get: { ui.query }, set: { ui.query = $0 })
    }

    private var filterBinding: Binding<DriveFilter> {
        Binding(get: { ui.filter }, set: { value in withAnimation(Motion.snappy) { ui.filter = value } })
    }

    // MARK: Breadcrumb

    /// Unpaired: the folders above this one. Paired: the folders opened to get here.
    private var chain: [DriveFile] {
        guard ui.live else { return folderID.map { store.ancestors(of: $0) } ?? [] }
        var opened: [DriveFile] = []
        for route in ui.path {
            if case .folder(let id) = route, let item = store.file(id) { opened.append(item) }
            if case .folder(let id) = route, id == folderID { break }
        }
        return opened
    }

    private var breadcrumb: some View {
        let chain = self.chain
        let top = ui.live ? ui.section.title : (chain.first?.sharedWithMe == true ? DriveSection.shared.title : DriveSection.myDrive.title)
        return ScrollView(.horizontal) {
            HStack(spacing: 4) {
                crumb(top, current: false) { ui.path = [] }
                ForEach(Array(chain.enumerated()), id: \.element.id) { index, item in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .accessibilityHidden(true)
                    crumb(item.name, current: index == chain.count - 1) {
                        if ui.live {
                            if let at = ui.path.firstIndex(of: .folder(item.id)) { ui.path = Array(ui.path.prefix(at + 1)) }
                        } else {
                            ui.path = chain.prefix(index + 1).map { DriveRoute.folder($0.id) }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Folder path")
    }

    private func crumb(_ title: String, current: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Text(title)
                .font(KFont.ui(14.5, current ? .semibold : .regular, relativeTo: .subheadline))
                .foregroundStyle(current ? Palette.ink : Palette.goldText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(current)
    }

    // MARK: Tools

    private var toolsRow: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("File type", selection: filterBinding) {
                    ForEach(DriveFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 13, weight: .semibold))
                    Text(ui.filter.title)
                        .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(ui.filter == .all ? Palette.ink : Palette.goldText)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .kGlass(Capsule())
            }
            .accessibilityLabel("File type: \(ui.filter.title)")

            Spacer(minLength: 0)

            GlassIconButton(symbol: ui.grid ? "list.bullet" : "square.grid.2x2", label: ui.grid ? "Show as list" : "Show as grid") {
                Haptics.select()
                withAnimation(Motion.snappy) { ui.grid.toggle() }
            }
            GlassIconButton(symbol: ui.selecting ? "xmark" : "checkmark.circle", label: ui.selecting ? "Stop selecting" : "Select files") {
                Haptics.tap()
                ui.setSelecting(!ui.selecting)
            }
        }
    }

    // MARK: Quick access

    private var quickAccess: some View {
        FilesGroup(label: "Quick access") {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(quickFiles.enumerated()), id: \.element.id) { index, file in
                        NavigationLink(value: DriveRoute.preview(file.id)) {
                            DriveQuickTile(file: file)
                        }
                        .buttonStyle(PressStyle(scale: 0.97))
                        .arrives(index)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if ui.live, items.isEmpty, case .failed(let why) = liveList?.load {
            DriveLiveLine(text: why, action: "Try again") { Task { await loadLive() } }
        } else if ui.live && items.isEmpty && liveList?.load != .loaded {
            HStack(spacing: 10) {
                ProgressView().tint(Palette.goldText)
                Text("Loading Drive")
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .transition(.opacity)
        } else if ui.loading {
            HStack(spacing: 10) {
                ProgressView().tint(Palette.goldText)
                Text("Loading Drive")
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .transition(.opacity)
        } else {
            let all = items
            let folders = all.filter { $0.isFolder }
            let others = all.filter { !$0.isFolder }
            if all.isEmpty {
                FilesEmpty(symbol: ui.section == .trash ? "trash" : "magnifyingglass", title: "Nothing here", detail: "No matching Google files.")
            }
            if !folders.isEmpty {
                FilesGroup(label: "Folders") { collection(folders, offset: 0) }
            }
            if !others.isEmpty {
                FilesGroup(label: "Files") { collection(others, offset: folders.count) }
            }
            if ui.live { liveFooter }
        }
    }

    /// Paired: a failed refresh over a list already shown, a partial search, and Load more.
    @ViewBuilder
    private var liveFooter: some View {
        if let list = liveList {
            if !items.isEmpty, case .failed(let why) = list.load {
                DriveLiveLine(text: why, action: "Try again") { Task { await loadLive() } }
            }
            if list.partial {
                HintLine(text: "Google returned a partial result. Narrow the search.")
            }
            if list.next != nil, let key = liveKey {
                Button {
                    Haptics.tap()
                    Task { await store.loadList(key, more: true) }
                } label: {
                    HStack(spacing: 8) {
                        if list.loadingMore { ProgressView().tint(Palette.goldText) }
                        Text(list.loadingMore ? "Loading more" : "Load more")
                            .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Palette.goldText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .kCard(radius: 16)
                }
                .buttonStyle(PressStyle())
                .disabled(list.loadingMore)
            }
        }
    }

    @ViewBuilder
    private func collection(_ files: [DriveFile], offset: Int) -> some View {
        if ui.grid {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    cell(file, grid: true, last: false)
                        .arrives(offset + index)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    cell(file, grid: false, last: index == files.count - 1)
                        .arrives(offset + index)
                }
            }
            .kCard(radius: 20)
        }
    }

    @ViewBuilder
    private func cell(_ file: DriveFile, grid: Bool, last: Bool) -> some View {
        let picked = ui.selected.contains(file.id)
        if ui.selecting {
            Button {
                ui.toggle(file.id)
            } label: {
                face(file, grid: grid, picked: picked, last: last)
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .accessibilityAddTraits(picked ? .isSelected : [])
        } else {
            NavigationLink(value: ui.route(for: file)) {
                face(file, grid: grid, picked: false, last: last)
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .contextMenu { menu(for: file) }
        }
    }

    @ViewBuilder
    private func face(_ file: DriveFile, grid: Bool, picked: Bool, last: Bool) -> some View {
        if grid {
            DriveFileCard(file: file, selecting: ui.selecting, picked: picked)
        } else {
            DriveFileRow(file: file, selecting: ui.selecting, picked: picked, last: last)
        }
    }

    // MARK: Long-press menu (the desktop's right-click menu)

    @ViewBuilder
    private func menu(for file: DriveFile) -> some View {
        Button { ui.open(file) } label: { Label("Open", systemImage: "arrow.up.forward.square") }
        Button { ui.path.append(.details(file.id)) } label: { Label("Details", systemImage: "info.circle") }
        Button { ui.ask(.rename(file.id), text: file.name) } label: { Label("Rename", systemImage: "pencil") }
        Button { ui.sheet = .move([file.id]) } label: { Label("Move", systemImage: "folder") }
        if !(ui.live && file.isFolder) {
            Button { ui.copy([file.id]) } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
        Button { ui.star([file.id], !file.starred) } label: {
            Label(file.starred ? "Unstar" : "Star", systemImage: file.starred ? "star.slash" : "star")
        }
        Button { ui.path.append(.sharing(file.id)) } label: { Label("Share", systemImage: "person.badge.plus") }
        if !file.isFolder && !ui.live {
            Button { ui.download(file) } label: { Label("Download", systemImage: "arrow.down.circle") }
        }
        Divider()
        if file.trashed {
            Button { ui.restore([file.id]) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
        } else {
            Button(role: .destructive) { ui.askTrash([file.id]) } label: { Label("Move to trash", systemImage: "trash") }
        }
    }

    // MARK: Selection toolbar

    private var selectionBar: some View {
        let ids = Array(ui.selected)
        let none = ids.isEmpty
        return VStack(spacing: 6) {
            HStack {
                Text("\(ids.count) selected")
                    .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Spacer()
                Button("Clear") { ui.clearSelection() }
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(PressStyle())
                    .disabled(none)
                    .accessibilityLabel("Clear selection")
            }
            HStack(spacing: 4) {
                DriveToolButton(symbol: "folder", title: "Move") { ui.sheet = .move(ids) }
                DriveToolButton(symbol: "doc.on.doc", title: "Copy") { ui.copy(ids) }
                DriveToolButton(symbol: "star", title: "Star") { ui.star(ids, true) }
                if ui.section == .trash {
                    DriveToolButton(symbol: "arrow.uturn.backward", title: "Restore") { ui.restore(ids) }
                } else {
                    DriveToolButton(symbol: "trash", title: "Trash", danger: true) {
                        if ui.live { ui.askTrash(ids) } else { confirmTrash = true }
                    }
                }
            }
            .disabled(none || ui.batchRunning)
            .opacity(none || ui.batchRunning ? 0.45 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .kGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
