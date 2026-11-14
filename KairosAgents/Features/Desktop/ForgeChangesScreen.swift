import SwiftUI

/// A small coloured letter for M, A, D or U.
struct ChangeBadge: View {
    let mark: ChangeMark

    var body: some View {
        Text(mark.rawValue)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityLabel(mark.word)
    }

    private var color: Color {
        switch mark {
        case .modified: Palette.working
        case .added, .untracked: Palette.success
        case .deleted: Palette.danger
        }
    }
}

/// Every file changed since the session started, with Revert.
struct ForgeChangesScreen: View {
    let sessionID: String
    @State private var store = ForgeStore.shared
    @State private var reverting: String?
    @State private var refreshing = false
    @State private var toast: String?

    private var session: ForgeSessionInfo? { store.session(sessionID) }
    private var blocked: Bool { session?.state == .working || session?.ended == true }

    var body: some View {
        // Paired with a desktop: that session's changes, never a sample.
        if DeskForgeLive.shared.on {
            DeskChangesListView(sessionID: sessionID)
        } else {
            sampleBody
        }
    }

    private var sampleBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let session {
                    if session.changes.isEmpty {
                        DeskEmptyNote(symbol: "checkmark.circle", title: "No changes", text: "No changes from the session baseline.")
                    } else {
                        HStack {
                            Text("\(session.changes.count) files").font(KFont.ui(15, .medium)).foregroundStyle(Palette.inkDim)
                            Spacer()
                            DiffCount(added: session.added, removed: session.removed, size: 14)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(session.changes.enumerated()), id: \.element.id) { index, change in
                                HStack(spacing: 0) {
                                    NavigationLink(value: DesktopRoute.diff(session: sessionID, path: change.path)) {
                                        HStack(spacing: 12) {
                                            ChangeBadge(mark: change.mark)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(change.name).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                                                Text(change.path).font(CodeFont.mono(11.5)).foregroundStyle(Palette.inkFaint).lineLimit(1).truncationMode(.head)
                                            }
                                            Spacer(minLength: 4)
                                            if change.binary {
                                                Text("Binary").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                                            } else {
                                                DiffCount(added: change.added, removed: change.removed, size: 12.5)
                                            }
                                        }
                                        .padding(.leading, 14)
                                        .frame(minHeight: 60)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressStyle(scale: 0.98))
                                    Button { reverting = change.path } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(blocked ? Palette.inkFaint : Palette.danger)
                                            .frame(width: 48, height: 60)
                                            .contentShape(Rectangle())
                                    }
                                    .disabled(blocked)
                                    .accessibilityLabel("Revert \(change.name)")
                                }
                                .overlay(alignment: .bottom) { if index < session.changes.count - 1 { Palette.line.frame(height: 1).padding(.leading, 50) } }
                                .arrives(index)
                            }
                        }
                        .kCard(radius: 22)
                        if blocked {
                            NoteLine(text: session.ended ? "This session has ended, so changes are read only." : "Revert is off while the agent is working.")
                        }
                    }
                } else {
                    DeskEmptyNote(symbol: "questionmark.folder", title: "No session", text: "Select a session to review its changes.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await refresh() }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Changes", subtitle: "Since the session started") {
                GlassIconButton(symbol: "arrow.clockwise", label: "Refresh changes") { Task { await refresh() } }
                    .rotationEffect(.degrees(refreshing ? 360 : 0))
                    .animation(refreshing ? .linear(duration: 0.6) : nil, value: refreshing)
            }
        }
        .kScreen()
        .confirmationDialog("Revert this file?", isPresented: Binding(get: { reverting != nil }, set: { if !$0 { reverting = nil } }), titleVisibility: .visible) {
            Button("Revert whole file", role: .destructive) {
                if let reverting { withAnimation(Motion.snappy) { store.revertFile(sessionID, path: reverting) } }
                reverting = nil
                toast = "File restored to the session start"
            }
        } message: {
            Text("\(reverting ?? "") goes back to how it was when the session started.")
        }
        .machineToast($toast)
    }

    private func refresh() async {
        refreshing = true
        try? await Task.sleep(for: .seconds(0.6))
        refreshing = false
        toast = "Changes are up to date"
    }
}

/// The full diff of one file, with Revert hunk and Revert file.
struct ForgeDiffScreen: View {
    let sessionID: String
    let path: String
    @State private var store = ForgeStore.shared
    @State private var revertHunk: UUID?
    @State private var revertAll = false
    @State private var toast: String?
    @Environment(\.dismiss) private var dismiss

    private var session: ForgeSessionInfo? { store.session(sessionID) }
    private var change: FileChange? { session?.changes.first { $0.path == path } }
    private var blocked: Bool { session?.state == .working || session?.ended == true }

    var body: some View {
        if DeskForgeLive.shared.on {
            DeskChangesDiffView(sessionID: sessionID, path: path)
        } else {
            sampleBody
        }
    }

    private var sampleBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let change {
                    HStack(spacing: 10) {
                        ChangeBadge(mark: change.mark)
                        Text(change.mark.word).font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
                        Spacer()
                        DiffCount(added: change.added, removed: change.removed, size: 14)
                    }
                    if change.binary {
                        DeskEmptyNote(symbol: "doc.richtext", title: "Binary file", text: "Text diff is unavailable.")
                            .kCard(radius: 20)
                    }
                    ForEach(change.hunks) { hunk in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text(hunk.header).font(CodeFont.mono(11.5)).foregroundStyle(Palette.working).lineLimit(1)
                                Spacer(minLength: 6)
                                Button { revertHunk = hunk.id } label: {
                                    Label("Revert hunk", systemImage: "arrow.uturn.backward")
                                        .font(KFont.ui(13.5, .medium))
                                        .foregroundStyle(blocked ? Palette.inkFaint : Palette.danger)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .disabled(blocked)
                            }
                            .padding(.leading, 12)
                            ScrollView(.horizontal) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(hunk.lines) { line in DiffLineView(line: line) }
                                }
                                .frame(minWidth: 330, alignment: .leading)
                            }
                            .scrollIndicators(.hidden)
                            .padding(.bottom, 8)
                        }
                        .kCard(radius: 18)
                    }
                    if blocked { NoteLine(text: "Revert is off while the agent is working or after the session ended.") }
                } else {
                    DeskEmptyNote(symbol: "checkmark.circle", title: "Nothing to show", text: "This file has no changes now. It may have been reverted.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: change?.name ?? (path.split(separator: "/").last.map(String.init) ?? path), subtitle: path) {
                if change != nil {
                    GlassIconButton(symbol: "arrow.uturn.backward.circle", label: "Revert whole file") { revertAll = true }
                        .disabled(blocked)
                        .opacity(blocked ? 0.4 : 1)
                }
            }
        }
        .kScreen()
        .confirmationDialog("Revert this hunk?", isPresented: Binding(get: { revertHunk != nil }, set: { if !$0 { revertHunk = nil } }), titleVisibility: .visible) {
            Button("Revert hunk", role: .destructive) {
                if let revertHunk { withAnimation(Motion.snappy) { store.revertHunk(sessionID, path: path, hunk: revertHunk) } }
                revertHunk = nil
                toast = "Hunk reverted"
            }
        } message: {
            Text("Only this block of lines goes back. The rest of the file stays.")
        }
        .confirmationDialog("Revert the whole file?", isPresented: $revertAll, titleVisibility: .visible) {
            Button("Revert whole file", role: .destructive) {
                withAnimation(Motion.snappy) { store.revertFile(sessionID, path: path) }
                dismiss()
            }
        } message: {
            Text("Every change in this file since the session started goes back.")
        }
        .machineToast($toast)
    }
}

/// Git for one session: branch status, stage, commit, push, pull, branches and merge back.
struct ForgeGitSheet: View {
    let sessionID: String
    var onOpenDiff: ((String) -> Void)? = nil
    @State private var store = ForgeStore.shared
    @State private var message = ""
    @State private var newBranch = ""
    @State private var merging = false
    @State private var working = false
    @State private var status: String?
    @Environment(\.dismiss) private var dismiss

    private var session: ForgeSessionInfo? { store.session(sessionID) }

    var body: some View {
        if DeskForgeLive.shared.on {
            DeskChangesGitView(sessionID: sessionID, onOpenDiff: onOpenDiff)
        } else {
            sampleBody
        }
    }

    private var sampleBody: some View {
        NavigationStack {
            ScrollView {
                if let session {
                    content(session)
                } else {
                    DeskEmptyNote(symbol: "arrow.triangle.branch", title: "No session", text: "Select an active session to use Git.")
                }
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
        }
        .kSheet()
    }

    private func content(_ session: ForgeSessionInfo) -> some View {
        let git = session.git
        let total = git.staged.count + git.unstaged.count
        let running = session.state == .working
        return VStack(alignment: .leading, spacing: 16) {
            DeskSheetTitle(text: "Git")
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 18, weight: .medium)).foregroundStyle(Palette.goldText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(git.branch).font(CodeFont.mono(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(git.upstream ?? "No upstream").font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label("\(git.ahead) ahead", systemImage: "arrow.up").foregroundStyle(git.ahead > 0 ? Palette.goldText : Palette.inkFaint)
                    Label("\(git.behind) behind", systemImage: "arrow.down").foregroundStyle(git.behind > 0 ? Palette.working : Palette.inkFaint)
                }
                .font(KFont.ui(13, .medium))
            }
            .padding(16)
            .kCard(radius: 20)

            fileGroup("Staged", git.staged, staged: true, session: session)
            fileGroup("Changes", git.unstaged, staged: false, session: session)
            if total == 0 { NoteLine(text: "Nothing to commit. The work is saved in Git.") }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Commit message")
                TextField("Describe what changed", text: $message, axis: .vertical)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2...5)
                    .padding(14)
                    .kCard(radius: 16)
                let canCommit = !message.trimmingCharacters(in: .whitespaces).isEmpty && total > 0 && !running && !working
                GoldButton(title: git.staged.isEmpty ? "Commit all \(total)" : "Commit \(git.staged.count)") {
                    run("Committed") {
                        store.commit(sessionID)
                        message = ""
                    }
                }
                .disabled(!canCommit)
                .opacity(canCommit ? 1 : 0.45)
            }

            HStack(spacing: 10) {
                DeskPillButton(title: git.upstream == nil ? "Publish" : "Push", symbol: "arrow.up.circle") {
                    run(git.upstream == nil ? "Published to origin" : "Pushed") { store.push(sessionID) }
                }
                .disabled(running || working || (git.ahead == 0 && git.upstream != nil))
                .opacity(running || working || (git.ahead == 0 && git.upstream != nil) ? 0.45 : 1)
                DeskPillButton(title: git.behind > 0 ? "Pull \(git.behind)" : "Pull", symbol: "arrow.down.circle") {
                    run("Pulled") { store.pull(sessionID) }
                }
                .disabled(running || working || git.upstream == nil)
                .opacity(running || working || git.upstream == nil ? 0.45 : 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Branch")
                Menu {
                    ForEach(git.branches, id: \.self) { branch in
                        Button(branch) { run("Switched to \(branch)") { store.switchBranch(sessionID, to: branch) } }
                    }
                } label: {
                    CardRow(symbol: "arrow.branch", title: "Switch branch", value: git.branch, last: true).kCard(radius: 18)
                }
                .disabled(running)
                HStack(spacing: 8) {
                    TextField("New branch name", text: $newBranch)
                        .font(CodeFont.mono(14))
                        .foregroundStyle(Palette.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .kCard(radius: 16)
                    DeskPillButton(title: "Create", symbol: "plus") {
                        let name = newBranch.trimmingCharacters(in: .whitespaces)
                        run("Created \(name)") { store.createBranch(sessionID, name) }
                        newBranch = ""
                    }
                    .disabled(newBranch.trimmingCharacters(in: .whitespaces).isEmpty || running)
                }
            }

            if session.branch != nil {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Merge back")
                    if merging {
                        SwipeUpConfirm(title: "Swipe up to merge into main") {
                            merging = false
                            run("Merged. You can end the session now.") { }
                        }
                        QuietButton(title: "Cancel") { withAnimation(Motion.snappy) { merging = false } }
                    } else {
                        Button { withAnimation(Motion.snappy) { merging = true } } label: {
                            CardRow(symbol: "arrow.triangle.merge", title: "Merge \(git.branch) into main", detail: "Asks your PC's permission rules first", last: true)
                                .kCard(radius: 18)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                        .disabled(running || working)
                    }
                }
            }

            if let status {
                Label(status, systemImage: "checkmark.circle")
                    .font(KFont.ui(14.5, .medium))
                    .foregroundStyle(Palette.success)
                    .transition(.opacity)
            }
            if running { NoteLine(text: "Git actions wait while the agent is working.") }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .animation(Motion.snappy, value: status)
    }

    private func fileGroup(_ title: String, _ files: [String], staged: Bool, session: ForgeSessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "\(title) \(files.count)")
                if !files.isEmpty {
                    Button(staged ? "Unstage all" : "Stage all") {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { store.stageAll(sessionID, !staged) }
                    }
                    .font(KFont.ui(14, .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 36)
                }
            }
            if !files.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element) { index, file in
                        HStack(spacing: 10) {
                            Button {
                                if let onOpenDiff { dismiss(); onOpenDiff(file) }
                            } label: {
                                HStack(spacing: 10) {
                                    if let mark = session.changes.first(where: { $0.path == file })?.mark { ChangeBadge(mark: mark) }
                                    Text(file).font(CodeFont.mono(12.5)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.head)
                                    Spacer(minLength: 4)
                                }
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle(scale: 0.98))
                            .disabled(onOpenDiff == nil)
                            Button {
                                Haptics.tap()
                                withAnimation(Motion.snappy) { store.stage(sessionID, file, !staged) }
                            } label: {
                                Image(systemName: staged ? "minus.circle" : "plus.circle")
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(staged ? Palette.inkDim : Palette.goldText)
                                    .frame(width: 44, height: 48)
                            }
                            .accessibilityLabel(staged ? "Unstage \(file)" : "Stage \(file)")
                        }
                        .padding(.leading, 14)
                        .overlay(alignment: .bottom) { if index < files.count - 1 { Palette.line.frame(height: 1).padding(.leading, 14) } }
                    }
                }
                .kCard(radius: 18)
            }
        }
    }

    private func run(_ done: String, _ action: @escaping () -> Void) {
        working = true
        status = nil
        Haptics.tap()
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(Motion.snappy) { action() }
            working = false
            status = done
            Haptics.success()
        }
    }
}

// MARK: - Paired with a desktop

/// A revert the person is being asked to confirm: a whole file, or one block named by its hash.
struct DeskChangesRevert: Identifiable {
    let id = UUID()
    var path: String
    var name: String
    /// nil reverts the whole file.
    var hash: String? = nil
    /// The file is new in this session, so reverting it deletes it.
    var fresh = false

    var title: String {
        hash == nil ? (fresh ? "Delete \(name)?" : "Revert \(name)?") : "Revert this block in \(name)?"
    }

    var detail: String {
        if hash != nil {
            return "This block in \(path) goes back to how it was when the session started. The lines you see in it are thrown away. The rest of the file stays."
        }
        return fresh
            ? "\(path) is new in this session, so reverting it deletes it from your desktop. It cannot be brought back from here."
            : "\(path) goes back to how it was when the session started. Your changes to it are thrown away."
    }

    var confirm: String { hash == nil ? (fresh ? "Delete file" : "Revert file") : "Revert block" }
}

/// Every file changed since the session started, read from the paired desktop, with Revert.
struct DeskChangesListView: View {
    let sessionID: String
    @State private var live = DeskChangesLive.shared
    @State private var forge = DeskForgeLive.shared
    @State private var ask: DeskChangesRevert?
    @State private var notice: String?
    @State private var toast: String?

    private var reading: DeskChangesReading? { live.changes(sessionID) }
    private var blocked: Bool { forge.isRunning(sessionID) || live.isBusy("revert:" + sessionID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let line = notice ?? live.note(sessionID) {
                    DeskForgeLine(text: line, action: "OK") {
                        notice = nil
                        live.clearNote(sessionID)
                    }
                }
                if forge.isAdmin, live.gone(sessionID) == nil, let reading, reading.load == .loaded {
                    content(reading)
                } else {
                    DeskChangesGate(sessionID: sessionID, load: reading?.load ?? .loading) {
                        Task { await live.loadChanges(sessionID) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await live.loadChanges(sessionID) }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Changes", subtitle: "Since the session started") {
                GlassIconButton(symbol: "arrow.clockwise", label: "Refresh changes") {
                    Task { await live.loadChanges(sessionID) }
                }
            }
        }
        .kScreen()
        .sheet(item: $ask) { item in
            ConfirmSheet(title: item.title, detail: item.detail, confirm: item.confirm) { revert(item) }
        }
        .machineToast($toast)
        .task(id: DeskForgeLive.connectionKey + "|" + sessionID) {
            guard live.on else { return }
            await live.loadChanges(sessionID)
        }
    }

    @ViewBuilder
    private func content(_ reading: DeskChangesReading) -> some View {
        if let stale = live.stale(sessionID) {
            DeskForgeLine(text: stale, action: "Try again") { Task { await live.loadChanges(sessionID) } }
        }
        if reading.files.isEmpty {
            DeskEmptyNote(symbol: "checkmark.circle", title: "No changes", text: "No changes from the session baseline.")
        } else {
            HStack {
                Text("\(reading.files.count) \(reading.files.count == 1 ? "file" : "files")")
                    .font(KFont.ui(15, .medium)).foregroundStyle(Palette.inkDim)
                Spacer()
                DiffCount(added: reading.files.reduce(0) { $0 + ($1.added ?? 0) },
                          removed: reading.files.reduce(0) { $0 + ($1.removed ?? 0) }, size: 14)
            }
            VStack(spacing: 0) {
                ForEach(Array(reading.files.enumerated()), id: \.element.id) { index, change in
                    row(change)
                        .overlay(alignment: .bottom) {
                            if index < reading.files.count - 1 { Palette.line.frame(height: 1).padding(.leading, 50) }
                        }
                }
            }
            .kCard(radius: 22)
            if reading.skipped > 0 {
                NoteLine(text: "\(reading.skipped) \(reading.skipped == 1 ? "row" : "rows") from your desktop could not be read.")
            }
            if forge.isRunning(sessionID) { NoteLine(text: "Revert is off while the agent is working.") }
        }
    }

    private func row(_ change: DeskChangesFile) -> some View {
        HStack(spacing: 0) {
            if change.secret {
                // A file that can hold secrets: no link, and nothing about it is read onto the phone.
                HStack(spacing: 12) {
                    ChangeBadge(mark: change.mark)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.name).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                        Text(DeskChangesWire.secretLine).font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 60)
            } else {
                NavigationLink(value: DesktopRoute.diff(session: sessionID, path: change.path)) {
                    HStack(spacing: 12) {
                        ChangeBadge(mark: change.mark)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.name).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(change.path).font(CodeFont.mono(11.5)).foregroundStyle(Palette.inkFaint).lineLimit(1).truncationMode(.head)
                        }
                        Spacer(minLength: 4)
                        if change.binary {
                            Text("Binary").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                        } else if let added = change.added, let removed = change.removed {
                            DiffCount(added: added, removed: removed, size: 12.5)
                        }
                    }
                    .padding(.leading, 14)
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.98))
                Button {
                    ask = DeskChangesRevert(path: change.path, name: change.name,
                                            fresh: change.mark == .untracked || change.mark == .added)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(blocked || !change.canRevert ? Palette.inkFaint : Palette.danger)
                        .frame(width: 48, height: 60)
                        .contentShape(Rectangle())
                }
                .disabled(blocked || !change.canRevert)
                .accessibilityLabel("Revert \(change.name)")
            }
        }
    }

    private func revert(_ item: DeskChangesRevert) {
        Task {
            let outcome: DeskForgeOutcome
            if let hash = item.hash {
                outcome = await live.revertHunk(sessionID, path: item.path, hash: hash)
            } else {
                outcome = await live.revertFile(sessionID, path: item.path)
            }
            if let line = outcome.line {
                notice = line
            } else if outcome == .done {
                Haptics.success()
                toast = "Reverted on your desktop"
            }
        }
    }
}

/// The full diff of one file from the paired desktop, with Revert block and Revert file.
struct DeskChangesDiffView: View {
    let sessionID: String
    let path: String
    @State private var live = DeskChangesLive.shared
    @State private var forge = DeskForgeLive.shared
    @State private var ask: DeskChangesRevert?
    @State private var notice: String?
    @State private var toast: String?
    @Environment(\.dismiss) private var dismiss

    private var secret: Bool { DeskChangesWire.isSecret(path) }
    private var reading: DeskChangesReading? { live.changes(sessionID) }
    private var change: DeskChangesFile? { reading?.files.first { $0.path == path } }
    private var blocked: Bool { forge.isRunning(sessionID) || live.isBusy("revert:" + sessionID) }
    private var title: String { path.split(separator: "/").last.map(String.init) ?? path }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let line = notice ?? live.note(sessionID) {
                    DeskForgeLine(text: line, action: "OK") {
                        notice = nil
                        live.clearNote(sessionID)
                    }
                }
                if secret {
                    DeskForgeLine(text: DeskChangesWire.secretLine)
                } else if forge.isAdmin, live.gone(sessionID) == nil, let reading, reading.load == .loaded {
                    if let stale = live.stale(sessionID) {
                        DeskForgeLine(text: stale, action: "Try again") { Task { await live.loadChanges(sessionID) } }
                    }
                    if let change {
                        fileContent(change)
                    } else {
                        DeskEmptyNote(symbol: "checkmark.circle", title: "Nothing to show", text: "This file has no changes now. It may have been reverted.")
                    }
                } else {
                    DeskChangesGate(sessionID: sessionID, load: reading?.load ?? .loading) {
                        Task { await live.loadChanges(sessionID) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: change?.name ?? title, subtitle: path) {
                if let change, change.canRevert, !secret {
                    GlassIconButton(symbol: "arrow.uturn.backward.circle", label: "Revert whole file") {
                        ask = DeskChangesRevert(path: change.path, name: change.name,
                                                fresh: change.mark == .untracked || change.mark == .added)
                    }
                    .disabled(blocked)
                    .opacity(blocked ? 0.4 : 1)
                }
            }
        }
        .kScreen()
        .sheet(item: $ask) { item in
            ConfirmSheet(title: item.title, detail: item.detail, confirm: item.confirm) { revert(item) }
        }
        .machineToast($toast)
        .task(id: DeskForgeLive.connectionKey + "|" + sessionID) {
            guard live.on, !secret else { return }
            await live.loadChanges(sessionID)
        }
    }

    @ViewBuilder
    private func fileContent(_ change: DeskChangesFile) -> some View {
        HStack(spacing: 10) {
            ChangeBadge(mark: change.mark)
            Text(change.mark.word).font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
            Spacer()
            if let added = change.added, let removed = change.removed {
                DiffCount(added: added, removed: removed, size: 14)
            }
        }
        if change.binary {
            DeskEmptyNote(symbol: "doc.richtext", title: "Binary file", text: "Text diff is unavailable.")
                .kCard(radius: 20)
        } else if let why = change.unavailable {
            DeskForgeLine(text: why)
        }
        ForEach(change.hunks) { hunk in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(hunk.header).font(CodeFont.mono(11.5)).foregroundStyle(Palette.working).lineLimit(1)
                    Spacer(minLength: 6)
                    Button {
                        ask = DeskChangesRevert(path: change.path, name: change.name, hash: hunk.hash)
                    } label: {
                        Label("Revert block", systemImage: "arrow.uturn.backward")
                            .font(KFont.ui(13.5, .medium))
                            .foregroundStyle(blocked || !change.canRevert ? Palette.inkFaint : Palette.danger)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(blocked || !change.canRevert)
                }
                .padding(.leading, 12)
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(hunk.lines) { line in
                            DiffLineView(line: DiffLine(kind: line.kind, old: line.old, new: line.new, text: line.text))
                        }
                    }
                    .frame(minWidth: 330, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 8)
            }
            .kCard(radius: 18)
        }
        if change.truncated {
            NoteLine(text: "This diff is long, so only its first blocks are shown. Review the rest in Kairos on your desktop.")
        }
        if forge.isRunning(sessionID) { NoteLine(text: "Revert is off while the agent is working.") }
    }

    private func revert(_ item: DeskChangesRevert) {
        Task {
            let outcome: DeskForgeOutcome
            if let hash = item.hash {
                outcome = await live.revertHunk(sessionID, path: item.path, hash: hash)
            } else {
                outcome = await live.revertFile(sessionID, path: item.path)
            }
            if let line = outcome.line {
                notice = line
            } else if outcome == .done {
                Haptics.success()
                if item.hash == nil {
                    dismiss()
                } else {
                    toast = "Block reverted on your desktop"
                }
            }
        }
    }
}

/// What the Git sheet is asking the person to confirm.
enum DeskChangesGitAsk: Identifiable {
    case commit(message: String)
    case pull
    case push

    var id: String {
        switch self {
        case .commit: "commit"
        case .pull: "pull"
        case .push: "push"
        }
    }
}

/// Git for one session, from the paired desktop: status, stage, commit, pull, push and merge back.
/// Creating or switching a branch stays on the desktop.
struct DeskChangesGitView: View {
    let sessionID: String
    var onOpenDiff: ((String) -> Void)? = nil
    @State private var live = DeskChangesLive.shared
    @State private var forge = DeskForgeLive.shared
    @State private var message = ""
    @State private var ask: DeskChangesGitAsk?
    @State private var merging = false
    @State private var status: String?
    @State private var notice: String?
    @Environment(\.dismiss) private var dismiss

    private var state: DeskChangesGitState? { live.git(sessionID) }
    private var running: Bool { forge.isRunning(sessionID) }
    private var locked: Bool { live.gitLocked(sessionID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DeskSheetTitle(text: "Git")
                    if forge.isAdmin, live.gone(sessionID) == nil, let state, state.load == .loaded, let git = state.git {
                        content(git)
                    } else {
                        DeskChangesGate(sessionID: sessionID, load: state?.load ?? .loading,
                                        reading: "Reading this branch from your desktop.") {
                            Task { await live.loadGit(sessionID) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
        }
        .kSheet()
        // A change on its way, or an approval being answered, cannot be swiped away.
        .interactiveDismissDisabled(locked)
        .sheet(item: $ask) { item in confirmSheet(item) }
        .task(id: DeskForgeLive.connectionKey + "|" + sessionID) {
            guard live.on else { return }
            await live.loadGit(sessionID)
        }
    }

    private func content(_ git: DeskChangesGit) -> some View {
        let total = git.staged.count + git.unstaged.count
        let hiddenSecrets = git.unstaged.filter { DeskChangesWire.isSecret($0.path) }
        let stagedSecrets = git.staged.contains { DeskChangesWire.isSecret($0.path) }
        // Commit with nothing staged adds every file, so it waits while a file that can hold secrets is among them.
        let commitAddsSecrets = git.staged.isEmpty && !hiddenSecrets.isEmpty
        let secretWords = hiddenSecrets.count == 1 ? "A file that can hold secrets is" : "\(hiddenSecrets.count) files that can hold secrets are"
        return VStack(alignment: .leading, spacing: 16) {
            if let stale = live.stale(sessionID) {
                DeskForgeLine(text: stale, action: "Try again") { Task { await live.loadGit(sessionID) } }
            }
            if let line = notice ?? live.note(sessionID) {
                DeskForgeLine(text: line, action: "OK") {
                    notice = nil
                    live.clearNote(sessionID)
                }
            }
            if let line = live.holdLine(sessionID) {
                DeskForgeLine(text: line, action: live.hold(sessionID)?.phase == .checking ? nil : "OK") {
                    live.clearHold(sessionID)
                }
            }
            if let approval = live.approval(sessionID), approval.kind != .restart {
                DeskChangesApprovalCard(sessionID: sessionID, approval: approval)
            }
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 18, weight: .medium)).foregroundStyle(Palette.goldText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(git.branch).font(CodeFont.mono(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(git.upstream.map { DeskForgeRequestText.hideSignIn($0) } ?? "No upstream")
                        .font(KFont.ui(13)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label("\(git.ahead) ahead", systemImage: "arrow.up").foregroundStyle(git.ahead > 0 ? Palette.goldText : Palette.inkFaint)
                    Label("\(git.behind) behind", systemImage: "arrow.down").foregroundStyle(git.behind > 0 ? Palette.working : Palette.inkFaint)
                }
                .font(KFont.ui(13, .medium))
            }
            .padding(16)
            .kCard(radius: 20)

            fileGroup("Staged", git.staged, staged: true)
            fileGroup("Changes", git.unstaged, staged: false)
            if total == 0 { NoteLine(text: "Nothing to commit. The work is saved in Git.") }
            if !hiddenSecrets.isEmpty {
                NoteLine(text: secretWords + " not staged here. Stage \(hiddenSecrets.count == 1 ? "it" : "them") in Kairos on your desktop if you mean to.",
                         symbol: "lock")
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Commit message")
                TextField("Describe what changed", text: $message, axis: .vertical)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2...5)
                    .padding(14)
                    .kCard(radius: 16)
                    .disabled(locked)
                let canCommit = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && total > 0
                    && !running && !locked && live.hold(sessionID) == nil && !commitAddsSecrets
                GoldButton(title: git.staged.isEmpty ? "Commit all \(total)" : "Commit \(git.staged.count)") {
                    ask = .commit(message: message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .disabled(!canCommit)
                .opacity(canCommit ? 1 : 0.45)
                if commitAddsSecrets {
                    NoteLine(text: "Stage the files you want first. Committing all would include a file that can hold secrets.")
                }
            }

            HStack(spacing: 10) {
                let pushOff = running || locked || (git.ahead == 0 && git.upstream != nil)
                DeskPillButton(title: git.upstream == nil ? "Publish" : "Push", symbol: "arrow.up.circle") { ask = .push }
                    .disabled(pushOff)
                    .opacity(pushOff ? 0.45 : 1)
                let pullOff = running || locked || git.upstream == nil
                DeskPillButton(title: git.behind > 0 ? "Pull \(git.behind)" : "Pull", symbol: "arrow.down.circle") { ask = .pull }
                    .disabled(pullOff)
                    .opacity(pullOff ? 0.45 : 1)
            }

            branches(git)

            if let session = forge.session(sessionID), session.branch != nil {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Merge back")
                    if !git.unmerged {
                        NoteLine(text: "Nothing to merge: \(session.baseBranch.isEmpty ? "the base branch" : session.baseBranch) already has this work.")
                    } else if merging {
                        SwipeUpConfirm(title: "Swipe up to merge into \(session.baseBranch.isEmpty ? "the base branch" : session.baseBranch)") {
                            merging = false
                            status = nil
                            live.startApproval(sessionID, .merge)
                        }
                        QuietButton(title: "Cancel") { withAnimation(Motion.snappy) { merging = false } }
                    } else {
                        Button { withAnimation(Motion.snappy) { merging = true } } label: {
                            CardRow(symbol: "arrow.triangle.merge", title: "Merge \(git.branch) into \(session.baseBranch.isEmpty ? "the base branch" : session.baseBranch)",
                                    detail: "Your desktop asks you to approve it first", last: true)
                                .kCard(radius: 18)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                        .disabled(running || locked)
                        .opacity(running || locked ? 0.45 : 1)
                    }
                }
            }

            if let status {
                Label(status, systemImage: "checkmark.circle")
                    .font(KFont.ui(14.5, .medium))
                    .foregroundStyle(Palette.success)
                    .transition(.opacity)
            }
            if running { NoteLine(text: "Git actions wait while the agent is working.") }
            if stagedSecrets {
                NoteLine(text: "A staged file can hold secrets. Check it in Kairos on your desktop before you commit.", symbol: "lock")
            }
        }
        .animation(Motion.snappy, value: status)
    }

    /// The branches the repository has, read only. Creating or switching one is done on the desktop.
    private func branches(_ git: DeskChangesGit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Branches")
            if git.branches.isEmpty {
                NoteLine(text: "No branches were listed.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(git.branches.prefix(30).enumerated()), id: \.element) { index, name in
                        HStack(spacing: 10) {
                            Image(systemName: name == git.branch ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(name == git.branch ? Palette.goldText : Palette.inkFaint)
                            Text(name).font(CodeFont.mono(13)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .overlay(alignment: .bottom) {
                            if index < min(git.branches.count, 30) - 1 { Palette.line.frame(height: 1).padding(.leading, 14) }
                        }
                    }
                }
                .kCard(radius: 18)
                if git.branches.count > 30 { NoteLine(text: "And \(git.branches.count - 30) more.") }
            }
            HintLine(text: "Create or switch a branch: do this in Kairos on your desktop.")
        }
    }

    private func fileGroup(_ title: String, _ files: [DeskChangesGitFile], staged: Bool) -> some View {
        let secretsIn = !staged && files.contains { DeskChangesWire.isSecret($0.path) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "\(title) \(files.count)")
                // Stage all would add a file that can hold secrets, so it is off then: stage the others one by one.
                if !files.isEmpty, !secretsIn {
                    Button(staged ? "Unstage all" : "Stage all") {
                        Haptics.tap()
                        write { await live.stage(sessionID, path: nil, unstage: staged) }
                    }
                    .font(KFont.ui(14, .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 36)
                    .disabled(locked || running)
                }
            }
            if !files.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        let secret = DeskChangesWire.isSecret(file.path)
                        HStack(spacing: 10) {
                            if secret && !staged {
                                HStack(spacing: 10) {
                                    ChangeBadge(mark: file.mark)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(file.path).font(CodeFont.mono(12.5)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.head)
                                        Text(DeskChangesWire.secretLine).font(KFont.ui(12)).foregroundStyle(Palette.inkFaint)
                                    }
                                    Spacer(minLength: 4)
                                }
                                .frame(minHeight: 48)
                            } else {
                                Button {
                                    if let onOpenDiff { dismiss(); onOpenDiff(file.path) }
                                } label: {
                                    HStack(spacing: 10) {
                                        ChangeBadge(mark: file.mark)
                                        Text(file.path).font(CodeFont.mono(12.5)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.head)
                                        Spacer(minLength: 4)
                                    }
                                    .frame(minHeight: 48)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle(scale: 0.98))
                                .disabled(onOpenDiff == nil || secret)
                                Button {
                                    Haptics.tap()
                                    write { await live.stage(sessionID, path: file.path, unstage: staged) }
                                } label: {
                                    Image(systemName: staged ? "minus.circle" : "plus.circle")
                                        .font(.system(size: 19, weight: .medium))
                                        .foregroundStyle(staged ? Palette.inkDim : Palette.goldText)
                                        .frame(width: 44, height: 48)
                                }
                                .disabled(locked || running)
                                .accessibilityLabel(staged ? "Unstage \(file.path)" : "Stage \(file.path)")
                            }
                        }
                        .padding(.leading, 14)
                        .overlay(alignment: .bottom) { if index < files.count - 1 { Palette.line.frame(height: 1).padding(.leading, 14) } }
                    }
                }
                .kCard(radius: 18)
            }
        }
    }

    @ViewBuilder
    private func confirmSheet(_ item: DeskChangesGitAsk) -> some View {
        let git = state?.git
        switch item {
        case .commit(let text):
            let count = git.map { $0.staged.isEmpty ? $0.unstaged.count : $0.staged.count } ?? 0
            let scope = (git?.staged.isEmpty ?? true) ? "every changed file (\(count))" : "the \(count) staged \(count == 1 ? "file" : "files")"
            ConfirmSheet(title: "Commit to \(git?.branch ?? "this branch")?",
                         detail: "\"\(text)\" commits \(scope). The repository's own hooks run on your desktop, and a commit cannot be undone from here.",
                         confirm: "Commit", danger: false) {
                commit(text)
            }
        case .pull:
            ConfirmSheet(title: "Pull \(git?.upstream.map { DeskForgeRequestText.hideSignIn($0) } ?? "the upstream")?",
                         detail: "Fast-forwards \(git?.branch ?? "this branch") to its upstream. The repository's own hooks run on your desktop.",
                         confirm: "Pull", danger: false) {
                write(done: "Pulled") { await live.pull(sessionID) }
            }
        case .push:
            ConfirmSheet(title: "Push \(git?.branch ?? "this branch")?",
                         detail: "Sends it to \(git?.upstream.map { DeskForgeRequestText.hideSignIn($0) } ?? "its remote"). Your desktop then shows the exact remote, with any sign-in part hidden, for you to approve. Nothing is pushed until you do.",
                         confirm: "Continue to approval", danger: false) {
                status = nil
                live.startApproval(sessionID, .push)
            }
        }
    }

    private func commit(_ text: String) {
        write(done: "Committed") {
            let outcome = await live.commit(sessionID, message: text)
            if outcome == .done, message.trimmingCharacters(in: .whitespacesAndNewlines) == text { message = "" }
            return outcome
        }
    }

    /// Run one change and say how it ended: a sentence when it did not, the short word when it did.
    private func write(done: String? = nil, _ action: @escaping () async -> DeskForgeOutcome) {
        Haptics.tap()
        status = nil
        notice = nil
        Task {
            let outcome = await action()
            if let line = outcome.line {
                notice = line
            } else if outcome == .done {
                Haptics.success()
                status = done
            }
        }
    }
}
