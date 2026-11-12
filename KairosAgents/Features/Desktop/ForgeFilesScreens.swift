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
        Group {
            if binary {
                EmptyNote(symbol: "photo", title: "Binary file. Read only.", text: "Open it on your PC to see it.")
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
