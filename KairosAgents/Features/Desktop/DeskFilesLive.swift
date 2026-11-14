import SwiftUI

// The paired desktop behind Files on this PC and Browse (Net/DeskFilesAPI.swift). Not paired, nothing here runs and
// both screens are the sample screens, exactly as before.
//
// Paired:
// - Files on this PC lists FOLDERS, for an admin account, read only. The desktop has no route that lists files, reads
//   one, or opens one on the PC, so none of those is drawn: no preview, no Open on PC, no share or copy of contents.
//   Paths are the person's own: they are shown, held only while their screen is open, and never written anywhere.
// - Browse is one screen with one honest line. Tabs, history, downloads and site settings have no route on the
//   desktop, and saved passwords are never listed, typed or fetched by the phone.

// MARK: - The store

@Observable
final class DeskFilesLive {
    static let shared = DeskFilesLive()

    /// The desktop and account everything below was read for. Nothing else is ever shown.
    private var account = "sample"
    private var folderMap: [String: DeskFilesFolder] = [:]

    @ObservationIgnored private var reads: [String: Int] = [:]

    private init() {}

    var on: Bool { DeskForgeLive.shared.on }
    /// The folder list answers an admin account only.
    var isAdmin: Bool { DeskForgeLive.shared.isAdmin }

    static let adminLine = "Files on this PC need an admin account on your desktop."

    private var current: Bool { on && account == DeskForgeLive.accountKey }

    private func stillLive(_ account: String) -> Bool {
        on && self.account == account && DeskForgeLive.accountKey == account
    }

    /// Before anything is read: drop whatever was read for another desktop, another account or sample mode.
    private func follow() {
        let key = DeskForgeLive.accountKey
        guard account != key else { return }
        account = key
        folderMap = [:]
        reads = [:]
    }

    /// One folder, by the path that was asked for ("" is the home folder). Nil until it is read for this desktop.
    func folder(_ path: String) -> DeskFilesFolder? { current ? folderMap[path] : nil }

    /// The screen went away: its folder is not kept.
    func release(_ path: String) {
        folderMap[path] = nil
        reads[path] = nil
    }

    func load(_ path: String) async {
        guard on else { return }
        follow()
        let account = self.account
        guard isAdmin else { return }
        guard path.isEmpty || DeskFilesWire.pathOK(path) else {
            folderMap[path] = DeskFilesFolder(load: .failed("This folder's name cannot be opened from the phone."))
            return
        }
        let loaded = folderMap[path]?.load == .loaded
        if !loaded { folderMap[path] = DeskFilesFolder(load: .loading) }
        var waited = 0
        while Connection.shared.state == .connecting, waited < 80, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        guard stillLive(account) else { return }
        let serial = (reads[path] ?? 0) + 1
        reads[path] = serial
        do {
            guard let client = Connection.shared.client else { throw APIError.notPaired }
            let dto = try await client.deskFilesBrowse(path)
            guard stillLive(account), reads[path] == serial else { return }
            folderMap[path] = DeskFilesWire.folder(dto, asked: path)
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            Connection.shared.note(error)
            guard stillLive(account), reads[path] == serial else { return }
            // A folder already on screen stays; a first read that failed says so.
            if !loaded { folderMap[path] = DeskFilesFolder(load: .failed(DeskFilesWire.words(error))) }
        }
    }
}

// MARK: - Files on this PC

/// The folders of the PC, while paired. Read only: folders, not files.
struct DeskFilesFolderScreen: View {
    let path: String

    @State private var live = DeskFilesLive.shared
    @State private var search = ""

    private var folder: DeskFilesFolder? { live.folder(path) }

    private var title: String {
        if path.isEmpty { return "Files on this PC" }
        return DeskFilesWire.lastName(folder?.path ?? path)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
                HintLine(text: "Folders only, read only. Files and opening them are in Kairos on your desktop.", symbol: "desktopcomputer")
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await live.load(path) }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: title, subtitle: live.isAdmin ? folder?.path : nil)
        }
        .kScreen()
        .task(id: DeskForgeLive.connectionKey + "|" + path) {
            await live.load(path)
        }
        .onDisappear { live.release(path) }
    }

    @ViewBuilder
    private var content: some View {
        if !live.isAdmin {
            DeskForgeLine(text: DeskFilesLive.adminLine)
        } else if let folder {
            switch folder.load {
            case .idle, .loading:
                DeskForgeLine(text: "Reading this folder from your desktop.")
            case .failed(let why):
                DeskForgeLine(text: why, action: "Try again", perform: { Task { await live.load(path) } })
            case .loaded:
                loaded(folder)
            }
        } else {
            DeskForgeLine(text: "Reading this folder from your desktop.")
        }
    }

    private func shown(_ folder: DeskFilesFolder) -> [DeskFilesDir] {
        search.isEmpty ? folder.dirs : folder.dirs.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    @ViewBuilder
    private func loaded(_ folder: DeskFilesFolder) -> some View {
        if folder.differs {
            HintLine(text: "Your desktop listed a different folder than the one asked for. The path above is the one it listed.",
                     symbol: "exclamationmark.triangle", color: Palette.goldText)
        }
        if let parent = folder.parent, DeskFilesWire.pathOK(parent) {
            VStack(spacing: 0) {
                NavigationLink(value: DesktopRoute.pcFiles(parent)) {
                    CardRow(symbol: "arrow.up.left", title: "Up one folder", detail: DeskFilesWire.lastName(parent), last: true)
                }
                .buttonStyle(PressStyle(scale: 0.98))
            }
            .kCard(radius: 22)
        }
        if folder.dirs.isEmpty {
            DeskEmptyNote(symbol: "folder", title: "No folders here", text: "This folder has no folders in it, or your desktop cannot read it.")
                .kCard(radius: 22)
        } else {
            MachineSearchField(prompt: "Search this folder", text: $search)
            let items = shown(folder)
            if items.isEmpty {
                NoteLine(text: "No folder here matches that.", symbol: "magnifyingglass")
            } else {
                Text("\(items.count) folders")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        row(item, last: offset == items.count - 1)
                            .arrives(offset)
                    }
                }
                .kCard(radius: 22)
            }
        }
        if folder.truncated {
            HintLine(text: "Only the first \(DeskFilesWire.limit) folders are listed.")
        }
        if folder.skipped > 0 {
            HintLine(text: "\(folder.skipped) folders could not be read and are not shown.")
        }
    }

    @ViewBuilder
    private func row(_ item: DeskFilesDir, last: Bool) -> some View {
        if item.openable {
            NavigationLink(value: DesktopRoute.pcFiles(item.path)) {
                CardRow(symbol: "folder", title: item.name, last: last)
            }
            .buttonStyle(PressStyle(scale: 0.98))
        } else {
            CardRow(symbol: "folder", title: item.name, detail: "This folder's name cannot be opened from the phone.", last: last, chevron: false)
        }
    }
}

// MARK: - Browse

/// Browse while paired: one screen, one line. There is nothing of Browse on this iPhone to show.
struct DeskFilesBrowseScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeskEmptyNote(symbol: "globe", title: "Browse",
                          text: "Browse runs in Kairos on your desktop. Bots' browsing shows in each bot's Computer page.")
                .kCard(radius: 22)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Browse", subtitle: "On your desktop") }
        .kScreen()
    }
}
