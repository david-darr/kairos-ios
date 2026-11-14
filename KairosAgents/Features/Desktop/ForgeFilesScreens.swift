import SwiftUI
import UIKit

/// The session's files as a tree. Changed files are marked.
struct ForgeExplorerScreen: View {
    let sessionID: String
    @State private var store = ForgeStore.shared
    @State private var open: Set<String> = ["src", "src/components"]
    @State private var loading = false

    private var session: ForgeSessionInfo? { store.session(sessionID) }

    var body: some View {
        // Paired with a desktop: that session's files, never a sample tree.
        if DeskForgeLive.shared.on {
            DeskChangesExplorerView(sessionID: sessionID)
        } else {
            sampleBody
        }
    }

    private var sampleBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().tint(Palette.gold)
                        Text("Loading files...").font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.node.id) { row in
                            nodeRow(row.node, depth: row.depth)
                        }
                    }
                    .kCard(radius: 20)
                }
                NoteLine(text: session?.branch == nil ? "Showing your project folder." : "Showing this session's worktree.", symbol: "folder")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Explorer", subtitle: store.project(session?.projectID ?? "")?.path) {
                GlassIconButton(symbol: "arrow.down.right.and.arrow.up.left", label: "Collapse all") {
                    withAnimation(Motion.snappy) { open = [] }
                }
                GlassIconButton(symbol: "arrow.clockwise", label: "Refresh Explorer") {
                    loading = true
                    Task {
                        try? await Task.sleep(for: .seconds(0.6))
                        withAnimation(Motion.snappy) { loading = false }
                    }
                }
            }
        }
        .kScreen()
    }

    private struct Row { let node: FileNode; let depth: Int }

    private var rows: [Row] {
        var result: [Row] = []
        func walk(_ nodes: [FileNode], _ depth: Int) {
            for node in nodes {
                result.append(Row(node: node, depth: depth))
                if let children = node.children, open.contains(node.path) { walk(children, depth + 1) }
            }
        }
        walk(ForgeSample.tree, 0)
        return result
    }

    @ViewBuilder
    private func nodeRow(_ node: FileNode, depth: Int) -> some View {
        let folder = node.children != nil
        let label = HStack(spacing: 10) {
            if folder {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
                    .rotationEffect(.degrees(open.contains(node.path) ? 90 : 0))
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }
            Image(systemName: folder ? "folder.fill" : "doc.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(folder ? Palette.goldText : Palette.inkDim)
            Text(node.name)
                .font(KFont.ui(15.5))
                .foregroundStyle(color(node.mark))
                .strikethrough(node.mark == .deleted)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let mark = node.mark { ChangeBadge(mark: mark) }
            if !folder { Text(node.size).font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint) }
        }
        .padding(.leading, 14 + CGFloat(depth) * 18)
        .padding(.trailing, 14)
        .frame(minHeight: 46)
        .contentShape(Rectangle())

        if folder {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) {
                    if open.contains(node.path) { open.remove(node.path) } else { open.insert(node.path) }
                }
            } label: { label }
            .buttonStyle(PressStyle(scale: 0.99))
            .accessibilityLabel("\(node.name) folder, \(open.contains(node.path) ? "open" : "closed")")
        } else {
            NavigationLink(value: DesktopRoute.file(session: sessionID, path: node.path)) { label }
                .buttonStyle(PressStyle(scale: 0.99))
                .accessibilityLabel("\(node.name)\(node.mark.map { ", \($0.word)" } ?? "")")
        }
    }

    private func color(_ mark: ChangeMark?) -> Color {
        switch mark {
        case .added, .untracked: Palette.success
        case .deleted: Palette.danger
        case .modified: Palette.working
        case nil: Palette.ink
        }
    }
}

/// Unsaved edits survive leaving the file and coming back.
@MainActor
enum ForgeDrafts {
    static var drafts: [String: String] = [:]
    static var saved: [String: String] = [:]
}

/// A file from the session: read it with line numbers, or edit and save it.
struct ForgeFileScreen: View {
    let sessionID: String
    let path: String
    @State private var store = ForgeStore.shared
    @State private var text = ""
    @State private var editing = false
    @State private var saving = false
    @State private var conflict = false
    @State private var toast: String?

    private var session: ForgeSessionInfo? { store.session(sessionID) }
    private var binary: Bool { [".png", ".jpg", ".svg", ".ico"].contains { path.lowercased().hasSuffix($0) } }
    private var readOnly: Bool { binary || session?.ended == true }
    private var original: String { ForgeDrafts.saved[key] ?? ForgeSample.fileText(path) }
    private var dirty: Bool { text != original }
    private var key: String { sessionID + ":" + path }

    var body: some View {
        if DeskForgeLive.shared.on {
            DeskChangesFileView(sessionID: sessionID, path: path)
        } else {
            sampleBody
        }
    }

    private var sampleBody: some View {
        Group {
            if binary {
                DeskEmptyNote(symbol: "photo", title: "Binary file. Read only.", text: "Open it on your PC to see it.")
                    .frame(maxHeight: .infinity)
            } else if editing {
                TextEditor(text: $text)
                    .font(CodeFont.mono(13.5))
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .onChange(of: text) { ForgeDrafts.drafts[key] = text }
            } else {
                ScrollView([.vertical, .horizontal]) {
                    let lines = text.components(separatedBy: "\n")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)").foregroundStyle(Palette.inkFaint).frame(width: 30, alignment: .trailing)
                                Text(line.isEmpty ? " " : line).foregroundStyle(Palette.ink)
                            }
                            .font(CodeFont.mono(13))
                            .padding(.vertical, 1.5)
                        }
                    }
                    .padding(16)
                    .textSelection(.enabled)
                }
                .defaultScrollAnchor(.topLeading)
                .scrollIndicators(.hidden)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 6) {
                ScreenHeader(title: path.split(separator: "/").last.map(String.init) ?? path, subtitle: path) {
                    if !readOnly {
                        if editing {
                            Button(action: save) {
                                Text(saving ? "Saving" : "Save")
                                    .font(KFont.ui(15.5, .semibold))
                                    .foregroundStyle(dirty ? Palette.onGold : Palette.inkFaint)
                                    .padding(.horizontal, 16)
                                    .frame(height: 44)
                                    .background(dirty ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
                            }
                            .buttonStyle(PressStyle())
                            .disabled(!dirty || saving)
                        } else {
                            GlassIconButton(symbol: "pencil", label: "Edit file") {
                                withAnimation(Motion.snappy) { editing = true }
                            }
                        }
                    }
                    GlassIconButton(symbol: "doc.on.doc", label: "Copy file") {
                        UIPasteboard.general.string = text
                        toast = "Copied"
                    }
                }
                HStack(spacing: 6) {
                    Circle().fill(readOnly ? Palette.inkFaint : (dirty ? Palette.gold : Palette.success)).frame(width: 7, height: 7)
                    Text(readOnly ? "Read only" : (dirty ? "Unsaved" : "Saved"))
                    if editing {
                        Spacer()
                        Button("Done") { withAnimation(Motion.snappy) { editing = false } }
                            .foregroundStyle(Palette.goldText)
                            .frame(minHeight: 32)
                    }
                }
                .font(KFont.ui(13, .medium))
                .foregroundStyle(Palette.inkDim)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
        }
        .kScreen()
        .alert("File changed on disk", isPresented: $conflict) {
            Button("Overwrite", role: .destructive) { commitSave() }
            Button("Reload") {
                text = original
                ForgeDrafts.drafts[key] = nil
                toast = "Reloaded from your PC"
            }
        } message: {
            Text("The agent changed this file while you were editing. Keep your version or load theirs?")
        }
        .machineToast($toast)
        .onAppear {
            if text.isEmpty { text = ForgeDrafts.drafts[key] ?? original }
        }
    }

    private func save() {
        if session?.state == .working {
            conflict = true
        } else {
            commitSave()
        }
    }

    private func commitSave() {
        saving = true
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            ForgeDrafts.saved[key] = text
            ForgeDrafts.drafts[key] = nil
            saving = false
            Haptics.success()
            toast = "Saved on your PC"
        }
    }
}

// MARK: - Paired with a desktop

/// The session's files as a tree, read from the paired desktop one folder at a time. A file that can hold
/// secrets is listed without a link and is never opened on the phone.
struct DeskChangesExplorerView: View {
    let sessionID: String
    @State private var live = DeskChangesLive.shared
    @State private var forge = DeskForgeLive.shared
    @State private var open: Set<String> = []

    private var root: DeskChangesFolder? { live.folder(sessionID, "") }

    private struct Row: Identifiable {
        enum Kind {
            case entry(DeskChangesEntry)
            case reading
            case failed(String)
        }
        let id: String
        let path: String
        let depth: Int
        let kind: Kind
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if forge.isAdmin, live.gone(sessionID) == nil, let root, root.load == .loaded {
                    if let stale = live.stale(sessionID) {
                        DeskForgeLine(text: stale, action: "Try again") { Task { await refresh() } }
                    }
                    if root.entries.isEmpty {
                        DeskEmptyNote(symbol: "folder", title: "No files", text: "This session's folder has no files.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(rows()) { row in
                                rowView(row)
                            }
                        }
                        .kCard(radius: 20)
                    }
                    NoteLine(text: forge.session(sessionID)?.branch == nil ? "Showing your project folder." : "Showing this session's worktree.", symbol: "folder")
                } else {
                    DeskChangesGate(sessionID: sessionID, load: root?.load ?? .loading, reading: "Reading this session's files from your desktop.") {
                        Task { await live.loadFolder(sessionID, path: "") }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await refresh() }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Explorer", subtitle: forge.project(forge.session(sessionID)?.projectID ?? "")?.path) {
                GlassIconButton(symbol: "arrow.down.right.and.arrow.up.left", label: "Collapse all") {
                    withAnimation(Motion.snappy) { open = [] }
                }
                GlassIconButton(symbol: "arrow.clockwise", label: "Refresh Explorer") {
                    Task { await refresh() }
                }
            }
        }
        .kScreen()
        .task(id: DeskForgeLive.connectionKey + "|" + sessionID) {
            guard live.on else { return }
            await live.loadFolder(sessionID, path: "")
        }
    }

    /// The tree as it is now: each open folder's entries under it, a reading line or a failure where a folder has none yet.
    private func rows() -> [Row] {
        var result: [Row] = []
        func walk(_ path: String, _ depth: Int) {
            guard let folder = live.folder(sessionID, path) else {
                if depth > 0 { result.append(Row(id: "reading:" + path, path: path, depth: depth, kind: .reading)) }
                return
            }
            switch folder.load {
            case .loaded:
                for entry in folder.entries {
                    result.append(Row(id: entry.path, path: entry.path, depth: depth, kind: .entry(entry)))
                    if entry.directory, !entry.secret, open.contains(entry.path) { walk(entry.path, depth + 1) }
                }
            case .failed(let why):
                if depth > 0 { result.append(Row(id: "failed:" + path, path: path, depth: depth, kind: .failed(why))) }
            case .idle, .loading:
                if depth > 0 { result.append(Row(id: "reading:" + path, path: path, depth: depth, kind: .reading)) }
            }
        }
        walk("", 0)
        return result
    }

    private func refresh() async {
        await live.loadFolder(sessionID, path: "")
        for path in open.sorted() { await live.loadFolder(sessionID, path: path) }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row.kind {
        case .reading:
            HStack(spacing: 8) {
                ProgressView().tint(Palette.gold)
                Text("Reading this folder").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                Spacer(minLength: 0)
            }
            .padding(.leading, 14 + CGFloat(row.depth) * 18)
            .frame(minHeight: 40)
        case .failed(let why):
            HStack(spacing: 8) {
                Text(why).font(KFont.ui(13.5)).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Try again") { Task { await live.loadFolder(sessionID, path: row.path) } }
                    .font(KFont.ui(14, .semibold))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
            }
            .padding(.leading, 14 + CGFloat(row.depth) * 18)
            .padding(.trailing, 14)
        case .entry(let entry):
            entryRow(entry, depth: row.depth)
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: DeskChangesEntry, depth: Int) -> some View {
        let isOpen = open.contains(entry.path)
        let label = HStack(spacing: 10) {
            if entry.directory && !entry.secret {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }
            Image(systemName: entry.secret ? "lock" : (entry.directory ? "folder.fill" : "doc.text"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(entry.directory && !entry.secret ? Palette.goldText : Palette.inkDim)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(KFont.ui(15.5)).foregroundStyle(Palette.ink).lineLimit(1)
                if entry.secret {
                    Text(DeskChangesWire.secretLine).font(KFont.ui(12)).foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if entry.changed && !entry.secret {
                Circle().fill(Palette.working).frame(width: 7, height: 7).accessibilityHidden(true)
            }
        }
        .padding(.leading, 14 + CGFloat(depth) * 18)
        .padding(.trailing, 14)
        .padding(.vertical, entry.secret ? 6 : 0)
        .frame(minHeight: 46)
        .contentShape(Rectangle())

        if entry.secret {
            label.accessibilityLabel("\(entry.name). \(DeskChangesWire.secretLine)")
        } else if entry.directory {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) {
                    if isOpen {
                        open.remove(entry.path)
                    } else {
                        open.insert(entry.path)
                    }
                }
                if !isOpen, live.folder(sessionID, entry.path)?.load != .loaded {
                    Task { await live.loadFolder(sessionID, path: entry.path) }
                }
            } label: { label }
            .buttonStyle(PressStyle(scale: 0.99))
            .accessibilityLabel("\(entry.name) folder, \(isOpen ? "open" : "closed")")
        } else {
            NavigationLink(value: DesktopRoute.file(session: sessionID, path: entry.path)) { label }
                .buttonStyle(PressStyle(scale: 0.99))
                .accessibilityLabel("\(entry.name)\(entry.changed ? ", changed" : "")")
        }
    }
}

/// What the file screen is asking the person to confirm.
enum DeskChangesFileAsk: String, Identifiable {
    case reload, keepMine
    var id: String { rawValue }
}

/// A file from the paired desktop: read it with line numbers, or edit and save it. Saving is explicit, sends the
/// hash and mtime the editor was filled from, and never replaces the desktop's newer version without a confirm.
struct DeskChangesFileView: View {
    let sessionID: String
    let path: String
    @State private var live = DeskChangesLive.shared
    @State private var forge = DeskForgeLive.shared
    @State private var editing = false
    @State private var ask: DeskChangesFileAsk?
    @State private var notice: String?
    @State private var toast: String?

    private var secret: Bool { DeskChangesWire.isSecret(path) }
    private var state: DeskChangesFileState? { live.file(sessionID, path) }
    private var saving: Bool { live.isBusy("file:" + DeskChangesLive.pathKey(sessionID, path)) }
    private var running: Bool { forge.isRunning(sessionID) }
    private var name: String { path.split(separator: "/").last.map(String.init) ?? path }

    var body: some View {
        Group {
            if secret {
                VStack(alignment: .leading, spacing: 14) {
                    DeskForgeLine(text: DeskChangesWire.secretLine)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            } else if forge.isAdmin, live.gone(sessionID) == nil, let state, state.load == .loaded {
                fileBody(state)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    DeskChangesGate(sessionID: sessionID, load: state?.load ?? .loading, reading: "Reading this file from your desktop.") {
                        Task { await live.loadFile(sessionID, path: path) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .kScreen()
        .sheet(item: $ask) { item in
            switch item {
            case .reload:
                ConfirmSheet(title: "Reload from your desktop?",
                             detail: "Your edits to \(name) are thrown away. What your desktop has replaces them.",
                             confirm: "Reload and drop my edits") {
                    Task { await live.reload(sessionID, path: path) }
                }
            case .keepMine:
                ConfirmSheet(title: "Keep your version?",
                             detail: "Your text replaces the newer version your desktop has of \(name). That newer version is lost.",
                             confirm: "Replace the desktop's version") {
                    save(overwrite: true)
                }
            }
        }
        .machineToast($toast)
        .task(id: DeskForgeLive.connectionKey + "|" + sessionID + "|" + path) {
            guard live.on, !secret else { return }
            await live.loadFile(sessionID, path: path)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            ScreenHeader(title: name, subtitle: path) {
                if let state, state.load == .loaded, !secret, !state.binary {
                    if editing, state.canSave {
                        let canSave = state.dirty && !saving && !state.unsettled && state.newer == nil && !running
                        Button { save(overwrite: false) } label: {
                            Text(saving ? "Saving" : "Save")
                                .font(KFont.ui(15.5, .semibold))
                                .foregroundStyle(canSave ? Palette.onGold : Palette.inkFaint)
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                                .background(canSave ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .disabled(!canSave)
                    } else if state.canSave {
                        GlassIconButton(symbol: "pencil", label: "Edit file") {
                            withAnimation(Motion.snappy) { editing = true }
                        }
                    }
                    GlassIconButton(symbol: "doc.on.doc", label: "Copy file") {
                        UIPasteboard.general.string = state.shown
                        toast = "Copied"
                    }
                }
            }
            if let state, state.load == .loaded, !secret, !state.binary {
                HStack(spacing: 6) {
                    Circle().fill(!state.canSave ? Palette.inkFaint : (state.dirty ? Palette.gold : Palette.success)).frame(width: 7, height: 7)
                    Text(!state.canSave ? "Read only" : (state.unsettled ? "Not confirmed" : (state.dirty ? "Unsaved" : "Saved")))
                    if editing {
                        Spacer()
                        Button("Done") { withAnimation(Motion.snappy) { editing = false } }
                            .foregroundStyle(Palette.goldText)
                            .frame(minHeight: 32)
                            .disabled(saving)
                    }
                }
                .font(KFont.ui(13, .medium))
                .foregroundStyle(Palette.inkDim)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
        }
    }

    private func fileBody(_ state: DeskChangesFileState) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if let line = notice ?? state.line {
                    DeskForgeLine(text: line, action: "OK") {
                        notice = nil
                        live.dismissLine(sessionID, path: path)
                    }
                }
                if let stale = live.stale(sessionID) {
                    DeskForgeLine(text: stale, action: "Try again") { Task { await live.loadFile(sessionID, path: path) } }
                }
                if state.unsettled {
                    DeskForgeLine(text: "Your desktop did not confirm the save. Saving stays off until it has been read again.",
                                  action: "Check again") {
                        Task { await live.loadFile(sessionID, path: path) }
                    }
                }
                if state.newer != nil, !state.dirty {
                    DeskForgeLine(text: "This file changed on your desktop. What you see is the older text.", action: "Reload") {
                        Task { await live.reload(sessionID, path: path) }
                    }
                }
                if state.newer != nil, state.dirty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This file changed on your desktop")
                            .font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                        Text("Your text is still here. Reload takes your desktop's version and drops your edits. Keep mine replaces your desktop's version with yours.")
                            .font(KFont.ui(13.5)).foregroundStyle(Palette.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            PillButton(title: "Reload", look: .plain, wide: true) { ask = .reload }
                            PillButton(title: "Keep mine", look: .danger, wide: true) { ask = .keepMine }
                        }
                        .disabled(saving)
                    }
                    .padding(14)
                    .kCard(radius: 18, raised: true)
                }
                if running && state.dirty { NoteLine(text: "Saving is off while the agent is working.") }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            if state.binary {
                DeskEmptyNote(symbol: "photo", title: "Binary file. Read only.", text: "Open it in Kairos on your desktop to see it.")
                    .frame(maxHeight: .infinity)
            } else if editing && state.canSave {
                TextEditor(text: Binding(get: { live.file(sessionID, path)?.shown ?? "" },
                                         set: { live.setDraft(sessionID, path: path, $0) }))
                    .font(CodeFont.mono(13.5))
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .disabled(saving || state.unsettled)
            } else {
                DeskChangesReaderView(text: state.shown)
            }
        }
    }

    private func save(overwrite: Bool) {
        Task {
            let outcome = await live.save(sessionID, path: path, overwrite: overwrite)
            if let line = outcome.line {
                notice = line
            } else if outcome == .done {
                Haptics.success()
                toast = "Saved on your desktop"
            }
        }
    }
}

/// What the reader shows of a file: at most `maxLines` lines, each cut at `maxWidth` characters.
nonisolated enum DeskChangesReaderText {
    static let maxLines = 5000
    static let maxWidth = 2000

    static func cut(_ text: String) -> (lines: [String], short: Bool) {
        // "\r\n" is one Character in Swift, so a file with Windows line ends needs it named here.
        let pieces = text.split(maxSplits: maxLines, omittingEmptySubsequences: false,
                                whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
        var short = pieces.count > maxLines
        var lines: [String] = []
        lines.reserveCapacity(min(pieces.count, maxLines))
        for piece in pieces.prefix(maxLines) {
            if piece.count > maxWidth {
                short = true
                lines.append(String(piece.prefix(maxWidth)))
            } else {
                lines.append(String(piece))
            }
        }
        return (lines, short)
    }
}

/// A file with line numbers. The lines are cut once per text, off the main actor, and drawn lazily.
struct DeskChangesReaderView: View {
    let text: String
    @State private var lines: [String] = []
    @State private var short = false
    @State private var ready = false

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !ready {
                    ProgressView().padding(.top, 8)
                }
                ForEach(lines.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").foregroundStyle(Palette.inkFaint).frame(width: 30, alignment: .trailing)
                        Text(lines[index].isEmpty ? " " : lines[index]).foregroundStyle(Palette.ink)
                    }
                    .font(CodeFont.mono(13))
                    .padding(.vertical, 1.5)
                }
                if short {
                    Text("This file is longer than the phone shows: the first 5,000 lines, with long lines cut. Edit shows all of it.")
                        .font(KFont.ui(13)).foregroundStyle(Palette.inkFaint).padding(.top, 8)
                }
            }
            .padding(16)
            .textSelection(.enabled)
        }
        .defaultScrollAnchor(.topLeading)
        .scrollIndicators(.hidden)
        .task(id: text) {
            // Another text: the old lines go before the new ones are ready.
            ready = false
            lines = []
            let source = text
            let result = await Task.detached(priority: .userInitiated) { DeskChangesReaderText.cut(source) }.value
            if Task.isCancelled { return }
            lines = result.lines
            short = result.short
            ready = true
        }
    }
}
