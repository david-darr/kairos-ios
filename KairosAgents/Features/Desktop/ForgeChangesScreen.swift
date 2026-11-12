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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let session {
                    if session.changes.isEmpty {
                        EmptyNote(symbol: "checkmark.circle", title: "No changes", text: "No changes from the session baseline.")
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
                    EmptyNote(symbol: "questionmark.folder", title: "No session", text: "Select a session to review its changes.")
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
                        EmptyNote(symbol: "doc.richtext", title: "Binary file", text: "Text diff is unavailable.")
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
                    EmptyNote(symbol: "checkmark.circle", title: "Nothing to show", text: "This file has no changes now. It may have been reverted.")
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
        NavigationStack {
            ScrollView {
                if let session {
                    content(session)
                } else {
                    EmptyNote(symbol: "arrow.triangle.branch", title: "No session", text: "Select an active session to use Git.")
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
            SheetTitle(text: "Git")
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
                PillButton(title: git.upstream == nil ? "Publish" : "Push", symbol: "arrow.up.circle") {
                    run(git.upstream == nil ? "Published to origin" : "Pushed") { store.push(sessionID) }
                }
                .disabled(running || working || (git.ahead == 0 && git.upstream != nil))
                .opacity(running || working || (git.ahead == 0 && git.upstream != nil) ? 0.45 : 1)
                PillButton(title: git.behind > 0 ? "Pull \(git.behind)" : "Pull", symbol: "arrow.down.circle") {
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
                    PillButton(title: "Create", symbol: "plus") {
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
