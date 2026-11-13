import SwiftUI

/// A file's details: what it is, every action, revisions and sharing.
struct DriveDetailsView: View {
    let fileID: String
    let openSharing: Bool

    @Environment(DriveUI.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var showRevisions = false
    @State private var showSharing = false
    @State private var confirmDelete = false
    @State private var started = false

    private var file: DriveFile? { ui.store.file(fileID) }

    var body: some View {
        ScrollView {
            if let file {
                VStack(alignment: .leading, spacing: 18) {
                    if ui.live { liveLines(file) }
                    hero(file).arrives(0)
                    actions(file).arrives(1)
                    revisions(file).arrives(2)
                    sharing(file).arrives(3)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            } else {
                FilesEmpty(symbol: "doc", title: "This file is gone", detail: "It was deleted or moved out of this Drive.", action: "Go back") { dismiss() }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .kScreen()
        .onAppear {
            guard !started else { return }
            started = true
            showSharing = openSharing
        }
        .task(id: DriveStore.connectionKey) {
            guard ui.live else { return }
            await ui.store.refreshFileLive(fileID)
        }
        .task(id: "\(showRevisions)|\(DriveStore.connectionKey)") {
            guard ui.live, showRevisions else { return }
            await ui.store.loadRevisionsLive(fileID)
        }
        .task(id: "\(showSharing)|\(DriveStore.connectionKey)") {
            guard ui.live, showSharing else { return }
            await ui.store.loadPeopleLive(fileID)
        }
        .confirmationDialog("Delete forever?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete forever", role: .destructive) {
                ui.deleteForever(fileID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This file cannot be restored.")
        }
    }

    /// Paired: the last change's sentence, and a file the desktop no longer has.
    @ViewBuilder
    private func liveLines(_ file: DriveFile) -> some View {
        if let note = ui.store.liveNote {
            DriveLiveLine(text: note, action: "OK") { ui.store.liveNote = nil }
        }
        if case .failed(let why) = ui.store.reads["info|" + fileID] {
            DriveLiveLine(text: why, action: "Try again") { Task { await ui.store.refreshFileLive(fileID) } }
        }
    }

    private var header: some View {
        FilesHeader(title: file?.name ?? "Details", subtitle: file?.kind.label, back: { dismiss() }) {
            if let file {
                GlassIconButton(symbol: file.starred ? "star.fill" : "star", label: file.starred ? "Unstar" : "Star") {
                    ui.star([file.id], !file.starred)
                }
            }
        }
    }

    // MARK: Hero

    private func hero(_ file: DriveFile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                DriveFileIcon(kind: file.kind, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.kind.label)
                        .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                        .foregroundStyle(file.kind.tint)
                    Text(file.name)
                        .font(KFont.ui(20, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            if file.trashed {
                Label("In the trash", systemImage: "trash")
                    .font(KFont.ui(14, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.danger)
            }
            VStack(spacing: 0) {
                fact("Modified", FilesDates.short(file.modified))
                fact("Size", file.kind.isGoogle || file.isFolder ? "Stored in Google" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                fact("Location", location(of: file), last: true)
            }
            .kCard(radius: 16)
        }
    }

    private func location(of file: DriveFile) -> String {
        if let parent = file.parent, let folder = ui.store.file(parent) { return folder.name }
        if ui.live { return file.sharedWithMe ? "Shared with me" : "Google Drive" }
        return file.sharedWithMe ? "Shared with me" : "My Drive"
    }

    private func fact(_ title: String, _ value: String, last: Bool = false) -> some View {
        HStack {
            Text(title).font(KFont.ui(15, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            Spacer(minLength: 8)
            Text(value).font(KFont.ui(15, relativeTo: .subheadline)).foregroundStyle(Palette.ink).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 14) }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func actions(_ file: DriveFile) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return FilesGroup(label: "Actions") {
            LazyVGrid(columns: columns, spacing: 10) {
                ActionTile(symbol: "arrow.up.forward.square", title: "Open") {
                    let route: DriveRoute = file.isFolder ? .folder(file.id) : .preview(file.id)
                    ui.path.append(route)
                }
                if file.kind == .sheet && !file.trashed {
                    ActionTile(symbol: "tablecells", title: "Edit cells") { ui.path.append(.sheetEditor(file.id)) }
                }
                if file.kind == .form && !file.trashed {
                    ActionTile(symbol: "list.bullet.rectangle", title: "Edit form") { ui.path.append(.formEditor(file.id)) }
                }
                ActionTile(symbol: "pencil", title: "Rename") { ui.ask(.rename(file.id), text: file.name) }
                ActionTile(symbol: "folder", title: "Move") { ui.sheet = .move([file.id]) }
                if !(ui.live && file.isFolder) {
                    ActionTile(symbol: "doc.on.doc", title: "Copy") { ui.copy([file.id]) }
                }
                ActionTile(symbol: "star", title: file.starred ? "Unstar" : "Star", on: file.starred) { ui.star([file.id], !file.starred) }
                if !file.isFolder && !ui.live {
                    ActionTile(symbol: "arrow.down.circle", title: "Download") { ui.download(file) }
                }
                if file.trashed {
                    ActionTile(symbol: "arrow.uturn.backward", title: "Restore") { ui.restore([file.id]) }
                    if !ui.live {
                        ActionTile(symbol: "trash.slash", title: "Delete forever", danger: true) { confirmDelete = true }
                    }
                } else {
                    ActionTile(symbol: "trash", title: "Trash", danger: true) { ui.askTrash([file.id]) }
                }
            }
            .disabled(ui.live && (ui.batchRunning || ui.store.busy.contains(file.id)))
            if ui.live {
                DriveLiveOpenLink(file: file)
                if file.trashed {
                    HintLine(text: "Delete forever and Empty trash are not offered on your phone. Do them in Google Drive on your desktop.")
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: Revisions

    private func revisions(_ file: DriveFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosure("Revisions", symbol: "clock.arrow.circlepath", open: $showRevisions)
            if showRevisions {
                if ui.live, file.revisions.isEmpty, ui.store.reads["revisions|" + file.id] == .loading || ui.store.reads["revisions|" + file.id] == nil {
                    Text("Reading revisions.")
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                } else if file.revisions.isEmpty {
                    Text("Revisions unavailable for this file.")
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                } else {
                    ForEach(Array(file.revisions.enumerated()), id: \.offset) { index, date in
                        HStack {
                            Text(index == 0 ? "Current version" : "Earlier version")
                                .font(KFont.ui(15, relativeTo: .subheadline))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text(FilesDates.short(date))
                                .font(KFont.ui(14, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .overlay(alignment: .top) { Palette.line.frame(height: 1).padding(.leading, 14) }
                    }
                }
            }
        }
        .kCard(radius: 18)
        .animation(Motion.snappy, value: showRevisions)
    }

    private func disclosure(_ title: String, symbol: String, open: Binding<Bool>) -> some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { open.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 26)
                Text(title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                    .rotationEffect(.degrees(open.wrappedValue ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .accessibilityValue(open.wrappedValue ? "Open" : "Closed")
    }

    // MARK: Sharing

    private func sharing(_ file: DriveFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosure("Sharing", symbol: "person.2", open: $showSharing)
            if showSharing {
                DriveSharingPanel(file: file)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .kCard(radius: 18)
        .animation(Motion.snappy, value: showSharing)
    }
}

/// Who can open a file, and a form to add someone.
struct DriveSharingPanel: View {
    let file: DriveFile
    @Environment(DriveUI.self) private var ui

    private var sharingBusy: Bool { ui.live && ui.store.busy.contains("share|" + file.id) }
    @State private var audience: DriveAudience = .person
    @State private var address = ""
    @State private var access: DriveAccess = .viewer
    @State private var removing: DriveMember?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            addForm
                .disabled(sharingBusy)
                .opacity(sharingBusy ? 0.5 : 1)
            if ui.live {
                if sharingBusy {
                    HintLine(text: "Sending to your desktop.", symbol: "hourglass")
                } else if case .failed(let why) = ui.store.reads["people|" + file.id] {
                    DriveLiveLine(text: why, action: "Try again") { Task { await ui.store.loadPeopleLive(file.id) } }
                } else if file.members.isEmpty {
                    HintLine(text: "Reading who has access.")
                }
            }
            SectionLabel(text: "Who has access")
            VStack(spacing: 0) {
                ForEach(Array(file.members.enumerated()), id: \.element.id) { index, member in
                    memberRow(member, last: index == file.members.count - 1)
                }
            }
            .kCard(radius: 16)
        }
        .confirmationDialog(
            "Remove access?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { member in
            Button("Remove", role: .destructive) { remove(member) }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text("\(member.title) will no longer be able to open \(file.name).")
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(DriveAudience.allCases, id: \.self) { item in
                        FilterPill(title: item.title, on: audience == item) { audience = item }
                    }
                }
            }
            .scrollIndicators(.hidden)

            if audience != .anyone {
                TextField(audience == .domain ? "Domain, such as example.com" : "Email address", text: $address)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .keyboardType(audience == .domain ? .URL : .emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .kCard(radius: 14, raised: true)
            }

            HStack(spacing: 10) {
                Menu {
                    Picker("Access", selection: $access) {
                        ForEach(DriveAccess.grantable, id: \.self) { level in
                            Text(level.title).tag(level)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(access.title).font(KFont.ui(15, .medium, relativeTo: .subheadline))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Palette.ink.opacity(0.08), in: Capsule())
                }
                .accessibilityLabel("Access: \(access.title)")

                Spacer(minLength: 0)

                Button(action: share) {
                    Text("Share")
                        .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.onGold)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 44)
                        .background(Palette.gold, in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.top, 2)
    }

    private func memberRow(_ member: DriveMember, last: Bool) -> some View {
        HStack(spacing: 10) {
            DriveAvatar(letter: member.letter, size: 34, muted: member.access != .owner)
            Text(member.title)
                .font(KFont.ui(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if member.access == .owner {
                Text(member.roleLabel ?? "Owner")
                    .font(KFont.ui(14, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.trailing, 4)
            } else {
                Menu {
                    Picker("Access", selection: accessBinding(member)) {
                        ForEach(DriveAccess.grantable, id: \.self) { level in
                            Text(level.title).tag(level)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(member.access.title).font(KFont.ui(14, .medium, relativeTo: .footnote))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Access for \(member.title): \(member.access.title)")

                Button {
                    Haptics.tap()
                    if ui.live {
                        ui.sheet = .confirm(DriveLiveConfirm(
                            title: "Remove \(member.title)?",
                            detail: "\(member.title) will no longer be able to open \(file.name).",
                            confirm: "Remove"
                        ) { remove(member) })
                    } else {
                        removing = member
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Palette.danger)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Remove \(member.title)")
                .disabled(sharingBusy)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 56) }
        }
    }

    private func accessBinding(_ member: DriveMember) -> Binding<DriveAccess> {
        Binding(
            get: { member.access },
            set: { level in
                Haptics.select()
                if ui.live {
                    guard level != member.access, !sharingBusy else { return }
                    ui.sheet = .confirm(DriveLiveConfirm(
                        title: "Make \(member.title) \(level.title.lowercased())?",
                        detail: "\(member.title) becomes \(level.title.lowercased()) on \(file.name) in Google Drive.",
                        confirm: "Change access", danger: false
                    ) {
                        Task {
                            let outcome = await ui.store.setAccessLive(file.id, member: member, to: level)
                            ui.say(outcome, done: "\(member.title) is now \(level.title.lowercased())")
                        }
                    })
                    return
                }
                withAnimation(Motion.snappy) { ui.store.setAccess(file.id, member: member.id, to: level) }
                ui.toaster.say("\(member.title) is now \(level.title.lowercased())")
            }
        )
    }

    private func share() {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch audience {
        case .person, .group:
            guard value.contains("@"), value.contains(".") else {
                ui.toaster.say("Enter an email address")
                return
            }
        case .domain:
            guard value.contains("."), !value.contains("@") else {
                ui.toaster.say("Enter a domain such as example.com")
                return
            }
        case .anyone:
            break
        }
        let member = DriveMember(audience: audience, address: audience == .anyone ? "" : value, access: access)
        if ui.live {
            guard !sharingBusy else { return }
            let fileID = file.id
            let name = file.name
            let chosenAudience = audience
            let chosenAccess = access
            let who = audience == .anyone ? "Anyone with the link" : member.title
            let detail: String
            switch audience {
            case .person, .group:
                detail = "\(who) can open \(name) as \(access.title.lowercased()). Google emails them a link."
            case .domain:
                detail = "Anyone at \(value) can open \(name) as \(access.title.lowercased())."
            case .anyone:
                detail = "Anyone who has the link can open \(name) as \(access.title.lowercased()), without signing in."
            }
            ui.sheet = .confirm(DriveLiveConfirm(
                title: "Share with \(who)?", detail: detail, confirm: "Share", danger: audience == .anyone
            ) {
                Task {
                    let outcome = await ui.store.shareLive(fileID, audience: chosenAudience, address: member.address, access: chosenAccess)
                    if outcome == .done { address = "" }
                    ui.say(outcome, done: "Shared with \(who)")
                }
            })
            return
        }
        withAnimation(Motion.snappy) { ui.store.share(file.id, with: member) }
        Haptics.success()
        ui.toaster.say("Shared with \(member.title)")
        address = ""
    }

    private func remove(_ member: DriveMember) {
        if ui.live {
            guard !sharingBusy else { return }
            let fileID = file.id
            Task {
                let outcome = await ui.store.removeAccessLive(fileID, member: member)
                ui.say(outcome, done: "Removed \(member.title)")
            }
            return
        }
        withAnimation(Motion.snappy) { ui.store.removeMember(file.id, member: member.id) }
        Haptics.thud()
        ui.toaster.say("Removed \(member.title)")
    }
}
