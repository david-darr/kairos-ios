import SwiftUI

/// "Google accounts": switch Drive, reconnect, add another, disconnect.
struct DriveAccountsSheet: View {
    @Environment(DriveUI.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var note: String?
    @State private var disconnecting: DriveAccount?

    private var store: DriveStore { ui.store }

    var body: some View {
        FittedSheet(estimate: 560) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Google accounts")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)

                VStack(spacing: 0) {
                    ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                        accountRow(account, last: index == store.accounts.count - 1)
                            .arrives(index)
                    }
                }
                .kCard(radius: 20)

                if ui.live {
                    HintLine(text: "Add, reconnect or disconnect Google accounts in Kairos on your desktop.", symbol: "desktopcomputer")
                        .padding(.horizontal, 4)
                }

                if let note {
                    Label(note, systemImage: "desktopcomputer")
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .kCard(radius: 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !ui.live {
                VStack(spacing: 0) {
                    Button {
                        Haptics.tap()
                        say("Add accounts on the computer running Kairos. Sign in there and the new Drive shows up here.")
                    } label: {
                        GroupRow(title: "Add another Google account", symbol: "person.badge.plus", last: store.currentAccount == nil)
                    }
                    .buttonStyle(PressStyle(scale: 0.99))

                    if let current = store.currentAccount {
                        Button {
                            Haptics.tap()
                            disconnecting = current
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 26)
                                Text("Disconnect \(current.email)")
                                    .font(KFont.ui(16))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Palette.danger)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                    }
                }
                .kCard(radius: 20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .animation(Motion.snappy, value: note)
        }
        .confirmationDialog(
            "Disconnect Google?",
            isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }),
            titleVisibility: .visible,
            presenting: disconnecting
        ) { account in
            Button("Disconnect", role: .destructive) {
                ui.disconnect(account)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text("Kairos forgets the sign-in for \(account.email). Your files stay in Google Drive, and other accounts stay connected.")
        }
    }

    private func say(_ text: String) {
        withAnimation(Motion.snappy) { note = text }
    }

    private func accountRow(_ account: DriveAccount, last: Bool) -> some View {
        let current = account.id == store.currentAccountID
        return HStack(spacing: 12) {
            DriveAvatar(letter: account.letter, size: 40, muted: account.broken)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                    .font(KFont.ui(16, .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(account.broken ? (ui.live ? (account.problem ?? "Sign-in expired or revoked") : "Sign-in expired or revoked") : (current ? "Browsing now" : "Switch to this Drive"))
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(account.broken ? Palette.danger : (current ? Palette.goldText : Palette.inkFaint))
                Text(account.canSend ? "Can send email" : "Cannot send email yet")
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 6)
            trailing(for: account, current: current)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 66) }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func trailing(for account: DriveAccount, current: Bool) -> some View {
        if ui.live {
            if current {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Browsing now")
            } else if !account.broken {
                smallButton("Switch") {
                    ui.switchAccount(account)
                    dismiss()
                }
            }
        } else if account.broken {
            smallButton("Reconnect") {
                say("Reconnecting \(account.email) needs the computer running Kairos. Open Library there and sign in again.")
            }
        } else if current {
            if account.canSend {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Browsing now")
            } else {
                smallButton("Allow sending") {
                    say("Allowing email from \(account.email) needs the computer running Kairos.")
                }
            }
        } else {
            smallButton("Switch") {
                ui.switchAccount(account)
                dismiss()
            }
        }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(KFont.ui(14, .semibold, relativeTo: .footnote))
                .foregroundStyle(Palette.goldText)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Palette.gold.opacity(0.14), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// "New in Drive": folder, upload, sheet, form. The sheet closes on any choice.
struct DriveNewSheet: View {
    @Environment(DriveUI.self) private var ui

    private struct Choice {
        let symbol: String
        let title: String
        let detail: String
        let next: DrivePending
    }

    private var choices: [Choice] {[
        Choice(symbol: "folder.badge.plus", title: "New folder", detail: "An empty folder here", next: .prompt(.newFolder)),
        Choice(symbol: "arrow.up.doc", title: "Upload files", detail: "From your phone, up to 25 MB each", next: .importFiles),
        Choice(symbol: "tablecells", title: "New sheet", detail: "A blank Google Sheet", next: .prompt(.newSheet)),
        Choice(symbol: "list.bullet.rectangle", title: "New form", detail: "A Google Form with no questions yet", next: .prompt(.newForm)),
    ]}

    private var place: String {
        if let id = ui.currentFolder, let folder = ui.store.file(id) { return "In \(folder.name)" }
        return "In My Drive"
    }

    var body: some View {
        FittedSheet(estimate: 420) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 2) {
                    Text("New in Drive")
                        .font(KFont.ui(20, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    Text(place)
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)

                if ui.live && ui.store.busy.contains("new") {
                    HintLine(text: "Wait for the last one to finish before you make or upload another.", symbol: "hourglass")
                        .padding(.horizontal, 4)
                }

                VStack(spacing: 0) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                        Button {
                            Haptics.tap()
                            ui.closeSheet(then: choice.next)
                        } label: {
                            row(choice, last: index == choices.count - 1)
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .disabled(ui.live && ui.store.busy.contains("new"))
                        .opacity(ui.live && ui.store.busy.contains("new") ? 0.45 : 1)
                        .arrives(index)
                    }
                }
                .kCard(radius: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private func row(_ choice: Choice, last: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: choice.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 40, height: 40)
                .background(Palette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(choice.title).font(KFont.ui(16.5)).foregroundStyle(Palette.ink)
                Text(choice.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 68) }
        }
    }
}

/// "Move to folder": find a destination, or put it at the top of My Drive.
struct DriveMoveSheet: View {
    let ids: [String]
    @Environment(DriveUI.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    // Paired: folders read from the desktop, and the move on its way.
    @State private var liveFolders: [DriveFile] = []
    @State private var liveLoad: DriveLiveLoad = .idle
    @State private var moving = false

    private var folders: [DriveFile] {
        if ui.live { return liveFolders.filter { !ids.contains($0.id) } }
        let all = ui.store.destinations(excluding: ids)
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        return words.isEmpty ? all : all.filter { $0.name.lowercased().contains(words) }
    }

    private var subject: String {
        if ids.count == 1, let file = ui.store.file(ids[0]) { return file.name }
        return "\(ids.count) files"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 2) {
                Text("Move to folder")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Text(subject)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)

            FilesSearchField(text: $query, prompt: "Find a destination folder")

            if ui.live {
                if moving {
                    DriveLiveLine(text: "Moving. This sheet closes when your desktop answers.")
                } else if case .failed(let why) = liveLoad {
                    DriveLiveLine(text: why, action: "Try again") { Task { await loadFolders() } }
                } else if liveLoad == .loading && liveFolders.isEmpty {
                    DriveLiveLine(text: "Reading your folders.")
                }
            }

            ScrollView {
                VStack(spacing: 0) {
                    destination(nil, title: "My Drive root", detail: "The top of My Drive", symbol: "externaldrive", last: folders.isEmpty)
                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                        destination(folder.id, title: folder.name, detail: location(of: folder), symbol: "folder.fill", last: index == folders.count - 1)
                    }
                }
                .kCard(radius: 20)
                if folders.isEmpty && !query.isEmpty {
                    Text("No folders match \"\(query)\".")
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .padding(.top, 12)
                }
            }
            .scrollIndicators(.hidden)

            QuietButton(title: "Cancel") { dismiss() }
                .disabled(moving)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .kSheet([.medium, .large])
        .interactiveDismissDisabled(moving)
        .task(id: query) {
            guard ui.live else { return }
            if !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await loadFolders()
        }
    }

    /// Paired: folders in the same Google account as the files being moved.
    private func loadFolders() async {
        guard let account = ids.first.flatMap({ ui.store.file($0)?.account }) else { return }
        liveLoad = .loading
        do {
            liveFolders = try await ui.store.foldersLive(account: account, query: query.trimmingCharacters(in: .whitespaces))
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            liveLoad = .loaded
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            liveLoad = .failed("Your folders could not be read. " + error.plainWords)
        }
    }

    private func location(of folder: DriveFile) -> String {
        if let parent = folder.parent, let above = ui.store.file(parent) { return "In \(above.name)" }
        if ui.live { return folder.sharedWithMe ? "Shared with me" : "Google Drive" }
        return folder.sharedWithMe ? "Shared with me" : "My Drive"
    }

    private func destination(_ id: String?, title: String, detail: String, symbol: String, last: Bool) -> some View {
        Button {
            guard ui.live else {
                ui.move(ids, to: id)
                dismiss()
                return
            }
            guard !moving else { return }
            moving = true
            Task {
                await ui.moveLive(ids, to: id)
                moving = false
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 36, height: 36)
                    .background(Palette.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Palette.line.frame(height: 1).padding(.leading, 62) }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .disabled(moving)
    }
}
