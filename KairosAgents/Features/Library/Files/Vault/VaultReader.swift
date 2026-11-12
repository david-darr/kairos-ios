import SwiftUI
import UIKit

// MARK: - Note page

/// One note: breadcrumb, title, meta, properties, the rendered body, and the editor in place of it.
struct VaultNoteView: View {
    let noteID: String
    @Environment(VaultNav.self) private var nav
    @Environment(FilesToaster.self) private var toaster
    @Environment(\.dismiss) private var dismiss
    @State private var store = VaultStore.shared
    @State private var editing = false
    @State private var showLinks = false
    @State private var linksAtHistory = false
    @State private var titleGone = false
    @State private var confirmLeave = false
    @State private var editorDirty = false
    @State private var pendingLeave: (() -> Void)?

    var body: some View {
        Group {
            if let note = store.note(noteID) {
                content(note)
            } else {
                FilesEmpty(symbol: "doc.questionmark", title: "Couldn't open this note", detail: "It may have been moved or deleted on your desktop.", action: "Back to Vault") { nav.home() }
                    .frame(maxHeight: .infinity)
                    .kScreen()
            }
        }
        .onAppear {
            switch nav.debug {
            case .links: nav.debug = .none; showLinks = true
            case .history: nav.debug = .none; linksAtHistory = true; showLinks = true
            case .write, .preview, .conflict: editing = true
            default: break
            }
        }
    }

    private func content(_ note: VaultNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VaultBreadcrumb(folder: note.folder)
                Text(note.title)
                    .font(KFont.display(36))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay(alignment: .topTrailing) {
                        if editing && editorDirty {
                            Circle().fill(Palette.gold).frame(width: 9, height: 9).offset(x: 12, y: 8)
                                .accessibilityLabel("Unsaved changes")
                        }
                    }
                Text(meta(note))
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .contentTransition(.numericText())
                if !note.properties.isEmpty {
                    VaultPropertyPills(note: note, compact: true)
                }
                if editing {
                    VaultEditor(noteID: note.id, dirty: $editorDirty) {
                        withAnimation(Motion.snappy) { editing = false }
                    }
                    .transition(.opacity)
                } else {
                    actions(note)
                    Palette.line.frame(height: 1).padding(.vertical, 2)
                    VaultMarkdownView(
                        blocks: VaultMarkdown.blocks(VaultMarkdown.frontmatterSplit(note.body).content, lineOffset: VaultMarkdown.frontmatterSplit(note.body).offset, hideTitle: note.title),
                        onOpen: { nav.open($0) },
                        onToggle: { line in
                            withAnimation(Motion.snappy) { store.save(note.id, body: VaultMarkdown.toggleTask(in: note.body, line: line)) }
                        }
                    )
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 90 } action: { _, gone in
            withAnimation(Motion.gentle) { titleGone = gone }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header(note) }
        .kScreen(glowAt: UnitPoint(x: 0.2, y: -0.06))
        .animation(Motion.snappy, value: editing)
        .sheet(isPresented: $showLinks) {
            VaultLinksSheet(noteID: note.id, startAtHistory: linksAtHistory)
                .environment(nav)
                .environment(toaster)
        }
        .confirmationDialog("Discard note edits?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) {
                editing = false
                editorDirty = false
                pendingLeave?()
                pendingLeave = nil
            }
        } message: {
            Text("Your unsaved changes to this Vault note will be lost.")
        }
    }

    private func header(_ note: VaultNote) -> some View {
        HStack(spacing: 10) {
            GlassIconButton(symbol: "chevron.left", label: "Back to Vault") { leave { dismiss() } }
            Text(note.title)
                .font(KFont.ui(17, .semibold, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .opacity(titleGone ? 1 : 0)
                .frame(maxWidth: .infinity)
            Menu {
                Button(store.pins.contains(note.id) ? "Unpin" : "Pin", systemImage: store.pins.contains(note.id) ? "pin.slash" : "pin") { togglePin(note) }
                Button("Copy path", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = note.id + ".md"
                    toaster.say("Path copied")
                }
                Button("Copy wikilink", systemImage: "link") {
                    UIPasteboard.general.string = note.wikilink
                    toaster.say("Wikilink copied")
                }
                Button("History", systemImage: "clock.arrow.circlepath") {
                    linksAtHistory = true
                    showLinks = true
                }
                Button("Show on map", systemImage: "point.3.connected.trianglepath.dotted") { leave { nav.showMap(note.id) } }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .kGlass(Circle(), interactive: true)
            .accessibilityLabel("Note options")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background { HeaderFade() }
    }

    private func actions(_ note: VaultNote) -> some View {
        let links = store.outlinks(note.id).resolved.count + store.backlinks(note.id).count
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                actionPill("Edit", symbol: "pencil", filled: true) {
                    withAnimation(Motion.snappy) { editing = true }
                }
                actionPill("Ask Kairos", symbol: "sparkle") {
                    nav.askAbout = note.title
                    nav.close()
                }
                actionPill(store.pins.contains(note.id) ? "Pinned" : "Pin", symbol: store.pins.contains(note.id) ? "pin.fill" : "pin") { togglePin(note) }
                    .accessibilityAddTraits(store.pins.contains(note.id) ? .isSelected : [])
                actionPill("Links · \(links)", symbol: "link") {
                    linksAtHistory = false
                    showLinks = true
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func actionPill(_ title: String, symbol: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                .foregroundStyle(filled ? Palette.onGold : Palette.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(filled ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.09)), in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : Palette.line, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private func togglePin(_ note: VaultNote) {
        let pinned = store.pins.contains(note.id)
        withAnimation(Motion.snappy) { store.togglePin(note.id) }
        toaster.say(pinned ? "Unpinned" : "Pinned to Vault Home")
    }

    private func leave(_ action: @escaping () -> Void) {
        if editing && editorDirty {
            pendingLeave = action
            confirmLeave = true
        } else {
            action()
        }
    }

    private func meta(_ note: VaultNote) -> String {
        let by: String
        switch note.editedBy {
        case "you": by = "by you"
        case "you (restored)": by = "by you (restored)"
        case "outside Kairos": by = "outside Kairos"
        default: by = "by \(note.editedBy)"
        }
        let ago = FilesDates.ago(note.edited)
        let edited = ago == "Just now" ? "Edited just now" : "Edited \(ago)"
        return "\(edited) \(by) · \(note.words) words"
    }
}

/// "Vault / Projects / Bike shop": each crumb opens that folder.
struct VaultBreadcrumb: View {
    let folder: String
    @Environment(VaultNav.self) private var nav

    var body: some View {
        let parts = folder.split(separator: "/").map(String.init)
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                crumb("Vault") { nav.home() }
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.inkFaint)
                    crumb(part) { nav.openFolder(parts[0...index].joined(separator: "/")) }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func crumb(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(KFont.ui(14, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.goldText)
                .padding(.horizontal, 4)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// status, project and type as pills; a missing one reads "No status".
struct VaultPropertyPills: View {
    let note: VaultNote
    var compact = false
    var showMissing = false

    var body: some View {
        VaultFlow(spacing: 6) {
            ForEach(Array(note.properties.enumerated()), id: \.offset) { _, pair in
                pill(compact ? pair.value : "\(pair.key): \(pair.value)", strong: VaultStore.requiredProperties.contains(pair.key))
            }
            if showMissing {
                ForEach(VaultStore.requiredProperties.filter { note.property($0) == nil }, id: \.self) { key in
                    Text("No \(key)")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .overlay(Capsule().strokeBorder(Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
            }
        }
    }

    private func pill(_ text: String, strong: Bool) -> some View {
        Text(text)
            .font(KFont.ui(13, .medium, relativeTo: .footnote))
            .foregroundStyle(strong ? Palette.goldText : Palette.inkDim)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background((strong ? Palette.gold : Palette.ink).opacity(0.1), in: Capsule())
    }
}

// MARK: - Editor

/// Write and Preview, Save and Done, `[[` suggestions, and the conflict and properties guards.
struct VaultEditor: View {
    enum Mode: String, CaseIterable { case write = "Write", preview = "Preview" }

    let noteID: String
    @Binding var dirty: Bool
    let done: () -> Void
    @Environment(VaultNav.self) private var nav
    @Environment(FilesToaster.self) private var toaster
    @State private var store = VaultStore.shared
    @State private var draft = ""
    @State private var original = ""
    @State private var openedAt = Date.distantPast
    @State private var mode: Mode = .write
    @State private var status = ""
    @State private var confirmDiscard = false
    @State private var confirmProperties = false
    @State private var conflict = false
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GlassSwitch(items: Mode.allCases, selection: $mode) { $0.rawValue }
                Spacer(minLength: 0)
                Text(status)
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(dirty ? Palette.goldText : Palette.inkFaint)
                    .lineLimit(1)
            }
            if mode == .write {
                writeView
            } else {
                VaultMarkdownView(
                    blocks: VaultMarkdown.blocks(VaultMarkdown.stripFrontmatter(draft)),
                    onOpen: { _ in toaster.say("Save or leave the editor to follow links") }
                )
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                .kCard(radius: 20)
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    if dirty { confirmDiscard = true } else { done() }
                } label: {
                    Text("Done")
                        .font(KFont.ui(16, .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Palette.ink.opacity(0.09), in: Capsule())
                }
                .buttonStyle(PressStyle())
                Button {
                    Haptics.tap()
                    trySave()
                } label: {
                    Text("Save")
                        .font(KFont.ui(16, .semibold))
                        .foregroundStyle(dirty ? Palette.onGold : Palette.inkFaint)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(dirty ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.06)), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(!dirty)
            }
        }
        .onAppear(perform: load)
        .onChange(of: draft) {
            dirty = draft != original
            status = dirty ? "Unsaved changes" : (status == "Saved" ? "Saved" : "")
        }
        .confirmationDialog("Discard note edits?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) {
                dirty = false
                done()
            }
        } message: {
            Text("Your unsaved changes to this Vault note will be lost.")
        }
        .confirmationDialog("Remove the properties block?", isPresented: $confirmProperties, titleVisibility: .visible) {
            Button("Remove and save", role: .destructive) { commit() }
        } message: {
            Text("This note will lose its status, project and type.")
        }
        .alert("This note changed since you opened it", isPresented: $conflict) {
            Button("Copy my version") {
                UIPasteboard.general.string = draft
                toaster.say("Your version is copied")
            }
            Button("Reload their version") {
                let latest = store.note(noteID)?.body ?? draft
                original = latest
                draft = latest
                openedAt = store.note(noteID)?.edited ?? .now
                toaster.say("Loaded the latest version")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Someone saved it from another place. Keep a copy of yours, or load theirs.")
        }
    }

    private var writeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft)
                .font(.system(size: 15.5, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .autocorrectionDisabled()
                .padding(10)
                .frame(minHeight: 340)
                .kCard(radius: 20)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Button("Link", systemImage: "link") { draft += "[[" }
                        Button("Checkbox", systemImage: "checkmark.square") { draft += draft.hasSuffix("\n") || draft.isEmpty ? "- [ ] " : "\n- [ ] " }
                        Spacer()
                        Button("Done") { focused = false }
                    }
                }
            if let partial = pendingLink {
                suggestions(partial)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.snappy, value: pendingLink)
    }

    /// The text after an unclosed `[[` at the end of the draft.
    private var pendingLink: String? {
        guard let open = draft.range(of: "[[", options: .backwards) else { return nil }
        let tail = draft[open.upperBound...]
        if tail.contains("]") || tail.contains("\n") || tail.count > 40 { return nil }
        return String(tail)
    }

    private func suggestions(_ partial: String) -> some View {
        let q = partial.lowercased()
        let matches = store.sortedNotes.filter { q.isEmpty || $0.title.lowercased().contains(q) }.prefix(60)
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: matches.isEmpty ? "No notes match" : "Link to a note")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(matches)) { note in
                        Button {
                            Haptics.select()
                            if let open = draft.range(of: "[[", options: .backwards) {
                                draft = String(draft[..<open.upperBound]) + note.title + "]]"
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(note.title).font(KFont.ui(14.5, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                                Text(note.folder.isEmpty ? "Vault" : note.folder).font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 48)
                            .kCard(radius: 14, raised: true)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func load() {
        guard !loaded, let note = store.note(noteID) else { return }
        loaded = true
        draft = note.body
        original = note.body
        openedAt = note.edited
        switch nav.debug {
        case .preview:
            nav.debug = .none
            mode = .preview
        case .conflict:
            nav.debug = .none
            draft = note.body + "\nA new line written on the phone."
            openedAt = note.edited.addingTimeInterval(-60)
            conflict = true
        case .write:
            nav.debug = .none
            draft = note.body + "\nSee [["
        default: break
        }
    }

    private func trySave() {
        if let current = store.note(noteID), current.edited > openedAt {
            conflict = true
            return
        }
        if VaultMarkdown.hasFrontmatter(original) && !VaultMarkdown.hasFrontmatter(draft) {
            confirmProperties = true
            return
        }
        commit()
    }

    private func commit() {
        status = "Saving..."
        store.save(noteID, body: draft)
        original = draft
        openedAt = store.note(noteID)?.edited ?? .now
        dirty = false
        status = "Saved"
        Haptics.success()
        toaster.say("Vault note saved")
        done()
    }
}

// MARK: - Links, properties and history sheet

/// About this note: properties, links both ways, related notes, the local graph and history.
struct VaultLinksSheet: View {
    let noteID: String
    var startAtHistory = false
    @Environment(VaultNav.self) private var nav
    @Environment(FilesToaster.self) private var toaster
    @Environment(\.dismiss) private var dismiss
    @State private var store = VaultStore.shared
    @State private var showRelated = false
    @State private var depth = 1
    @State private var change: VaultChange?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let note = store.note(noteID) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("About this note")
                            .font(KFont.ui(20, .semibold, relativeTo: .title3))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                        FilesGroup(label: "Properties") {
                            VaultPropertyPills(note: note, showMissing: true)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .kCard(radius: 18)
                        }
                        linkedFrom(note)
                        linksOut(note)
                        related(note)
                        FilesGroup(label: "Local graph", trailing: "Open in Map") {
                            go { nav.showMap(note.id) }
                        } content: {
                            VaultLocalGraph(noteID: note.id, depth: $depth) { id in go { nav.open(id) } }
                        }
                        history(note).id("history")
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if startAtHistory {
                    Task {
                        try? await Task.sleep(for: .seconds(0.35))
                        withAnimation(Motion.gentle) { proxy.scrollTo("history", anchor: .top) }
                    }
                }
            }
        }
        .kSheet([.medium, .large])
        .sheet(item: $change) { change in
            VaultChangeSheet(noteID: noteID, change: change)
                .environment(toaster)
        }
    }

    private func go(_ action: @escaping () -> Void) {
        dismiss()
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            action()
        }
    }

    private func linkedFrom(_ note: VaultNote) -> some View {
        let backlinks = store.backlinks(note.id)
        return FilesGroup(label: "Linked from · \(backlinks.count)") {
            if backlinks.isEmpty {
                emptyLine("No notes link here yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(backlinks.enumerated()), id: \.offset) { index, link in
                        Button { go { nav.open(link.note.id) } } label: {
                            VaultNoteRow(note: link.note, detail: link.snippet.isEmpty ? link.note.folder : link.snippet, last: index == backlinks.count - 1)
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                    }
                }
                .kCard(radius: 18)
            }
        }
    }

    private func linksOut(_ note: VaultNote) -> some View {
        let out = store.outlinks(note.id)
        let total = out.resolved.count + out.unresolved.count
        return FilesGroup(label: "Links out · \(total)") {
            if total == 0 {
                emptyLine("This note links to nothing.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(out.resolved.enumerated()), id: \.offset) { index, target in
                        Button { go { nav.open(target.id) } } label: {
                            VaultNoteRow(note: target, detail: target.folder.isEmpty ? "Vault" : target.folder, last: index == total - 1)
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                    }
                    ForEach(Array(out.unresolved.enumerated()), id: \.offset) { index, name in
                        HStack(spacing: 12) {
                            Image(systemName: "questionmark.square.dashed").foregroundStyle(Palette.inkFaint).frame(width: 26)
                            Text(name).font(KFont.ui(16)).foregroundStyle(Palette.inkDim)
                            Spacer()
                            Text("Not in vault").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .overlay(alignment: .bottom) {
                            if out.resolved.count + index < total - 1 { Palette.line.frame(height: 1).padding(.leading, 52) }
                        }
                    }
                }
                .kCard(radius: 18)
            }
        }
    }

    private func related(_ note: VaultNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.select()
                withAnimation(Motion.snappy) { showRelated.toggle() }
            } label: {
                HStack {
                    SectionLabel(text: "Related by keywords")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(showRelated ? 90 : 0))
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityValue(showRelated ? "Open" : "Closed")
            if showRelated {
                let notes = store.related(note.id)
                if notes.isEmpty {
                    emptyLine("No notes share enough words with this one.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(notes.enumerated()), id: \.offset) { index, other in
                            Button { go { nav.open(other.id) } } label: {
                                VaultNoteRow(note: other, detail: other.folder, last: index == notes.count - 1)
                            }
                            .buttonStyle(PressStyle(scale: 0.99))
                        }
                    }
                    .kCard(radius: 18)
                }
            }
        }
    }

    private func history(_ note: VaultNote) -> some View {
        let changes = store.history[note.id] ?? []
        return FilesGroup(label: "History") {
            if changes.isEmpty {
                emptyLine("No recorded changes. Edits made outside Kairos before today are not tracked.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(changes.enumerated()), id: \.element.id) { index, item in
                        Button {
                            Haptics.tap()
                            change = item
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.label == "Created" ? "plus.circle" : item.label == "Restored" ? "arrow.uturn.backward.circle" : "pencil.circle")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Palette.goldText)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.label).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                    Text("\(FilesDates.short(item.date)) · \(item.by)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if index < changes.count - 1 { Palette.line.frame(height: 1).padding(.leading, 52) }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                    }
                }
                .kCard(radius: 18)
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(KFont.ui(15, relativeTo: .subheadline))
            .foregroundStyle(Palette.inkDim)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18)
    }
}

/// One recorded change: what it did, line by line, and a way back to before it.
struct VaultChangeSheet: View {
    let noteID: String
    let change: VaultChange
    @Environment(FilesToaster.self) private var toaster
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    var body: some View {
        let before = Set(change.before.components(separatedBy: "\n"))
        let after = Set(change.after.components(separatedBy: "\n"))
        let removed = change.before.components(separatedBy: "\n").filter { !after.contains($0) && !$0.isEmpty }
        let added = change.after.components(separatedBy: "\n").filter { !before.contains($0) && !$0.isEmpty }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(change.label)
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                Text(sentence(added: added.count, removed: removed.count))
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(removed.prefix(40).enumerated()), id: \.offset) { _, line in diffLine("− " + line, color: Palette.danger) }
                    ForEach(Array(added.prefix(40).enumerated()), id: \.offset) { _, line in diffLine("+ " + line, color: Palette.success) }
                    if removed.isEmpty && added.isEmpty {
                        Text("No line changed.").font(KFont.ui(15)).foregroundStyle(Palette.inkFaint)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: 16)
                if !change.before.isEmpty {
                    GoldButton(title: "Restore before this change") { confirm = true }
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .confirmationDialog("Restore this note?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Restore") {
                VaultStore.shared.restore(noteID, to: change)
                Haptics.success()
                toaster.say("Note restored")
                dismiss()
            }
        } message: {
            Text("The note goes back to how it was before this change. This is recorded in its history.")
        }
    }

    private func sentence(added: Int, removed: Int) -> String {
        let when = "\(FilesDates.full(change.date)), \(change.by)."
        if change.before.isEmpty { return "The note was created. \(when)" }
        return "\(added) added and \(removed) removed lines. \(when)"
    }

    private func diffLine(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13.5, design: .monospaced))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Local graph

/// The note and its neighbours on rings. Tap a neighbour to open it.
struct VaultLocalGraph: View {
    let noteID: String
    @Binding var depth: Int
    let open: (String) -> Void
    @State private var store = VaultStore.shared

    var body: some View {
        let around = store.neighbourhood(noteID, depth: depth)
        let ring1 = around.filter { $0.value == 1 }.map(\.key).sorted()
        let ring2 = around.filter { $0.value == 2 }.map(\.key).sorted()
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                FilterPill(title: "Direct", on: depth == 1) { depth = 1 }
                FilterPill(title: "2 steps", on: depth == 2) { depth = 2 }
                Spacer()
                Text("\(around.count - 1) linked").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let r1 = min(geometry.size.width, geometry.size.height) * (ring2.isEmpty ? 0.36 : 0.24)
                let r2 = min(geometry.size.width, geometry.size.height) * 0.43
                let points = positions(center: center, ring1: ring1, r1: r1, ring2: ring2, r2: r2)
                ZStack {
                    Canvas { context, _ in
                        for id in ring1 + ring2 {
                            guard let point = points[id] else { continue }
                            let from = (around[id] ?? 1) == 1 ? center : nearestInner(id, points: points, ring1: ring1) ?? center
                            var path = Path()
                            path.move(to: from)
                            path.addLine(to: point)
                            context.stroke(path, with: .color(Palette.gold.opacity(0.35)), lineWidth: 1)
                        }
                    }
                    ForEach(ring1 + ring2, id: \.self) { id in
                        if let point = points[id], let note = store.note(id) {
                            Button { open(id) } label: {
                                VStack(spacing: 3) {
                                    Circle().fill((around[id] ?? 1) == 1 ? Palette.gold : Palette.inkFaint).frame(width: 12, height: 12)
                                    Text(note.title).font(KFont.ui(11.5, relativeTo: .caption2)).foregroundStyle(Palette.inkDim).lineLimit(1).frame(maxWidth: 90)
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .position(point)
                            .accessibilityLabel("Open \(note.title)")
                        }
                    }
                    VStack(spacing: 3) {
                        Circle().fill(Palette.ink).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Palette.gold, lineWidth: 2))
                        Text(store.note(noteID)?.title ?? "").font(KFont.ui(12.5, .semibold, relativeTo: .caption)).foregroundStyle(Palette.ink).lineLimit(1)
                    }
                    .position(center)
                    .accessibilityHidden(true)
                }
            }
            .frame(height: 260)
            .padding(8)
            .kCard(radius: 18)
            .animation(Motion.snappy, value: depth)
        }
    }

    private func positions(center: CGPoint, ring1: [String], r1: CGFloat, ring2: [String], r2: CGFloat) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        for (index, id) in ring1.enumerated() {
            let angle = Double(index) / Double(max(1, ring1.count)) * 2 * .pi - .pi / 2
            result[id] = CGPoint(x: center.x + r1 * CGFloat(cos(angle)), y: center.y + r1 * CGFloat(sin(angle)))
        }
        for (index, id) in ring2.enumerated() {
            let angle = Double(index) / Double(max(1, ring2.count)) * 2 * .pi - .pi / 3
            result[id] = CGPoint(x: center.x + r2 * CGFloat(cos(angle)), y: center.y + r2 * 0.92 * CGFloat(sin(angle)))
        }
        return result
    }

    private func nearestInner(_ id: String, points: [String: CGPoint], ring1: [String]) -> CGPoint? {
        let around = Set(store.outlinks(id).resolved.map(\.id) + store.backlinks(id).map(\.note.id))
        guard let link = ring1.first(where: { around.contains($0) }) else { return nil }
        return points[link]
    }
}

// MARK: - Folder page and filtered lists

struct VaultFolderView: View {
    let folder: String
    @Environment(VaultNav.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @State private var store = VaultStore.shared

    var body: some View {
        let children = store.children(of: folder)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VaultBreadcrumb(folder: folder.split(separator: "/").dropLast().joined(separator: "/"))
                if children.folders.isEmpty && children.notes.isEmpty {
                    FilesEmpty(symbol: "folder", title: "Empty folder.", detail: "Notes you add on your desktop show up here.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(children.folders, id: \.self) { sub in
                            Button { nav.openFolder(sub) } label: {
                                VaultFolderRow(name: store.folderName(sub), count: store.noteCount(in: sub))
                            }
                            .buttonStyle(PressStyle(scale: 0.99))
                        }
                        ForEach(Array(VaultMonths.group(children.notes).enumerated()), id: \.offset) { _, group in
                            if let heading = group.heading {
                                Text(heading.uppercased())
                                    .font(KFont.label).tracking(1.2).foregroundStyle(Palette.inkFaint)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 52).padding(.top, 10).padding(.bottom, 4)
                            }
                            ForEach(group.notes) { note in
                                Button { nav.open(note.id) } label: {
                                    VaultNoteRow(note: note, detail: FilesDates.ago(note.edited), last: note.id == children.notes.last?.id)
                                }
                                .buttonStyle(PressStyle(scale: 0.99))
                                .contextMenu { VaultNoteMenu(note: note) }
                            }
                        }
                    }
                    .kCard(radius: 20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            FilesHeader(title: store.folderName(folder), subtitle: "\(store.noteCount(in: folder)) notes", back: { dismiss() }) {
                GlassIconButton(symbol: "house", label: "Vault Home") { nav.home() }
            }
        }
        .kScreen()
    }
}

struct VaultListView: View {
    let filter: VaultFilter
    @Environment(VaultNav.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @State private var store = VaultStore.shared

    var body: some View {
        let notes = store.notes(for: filter)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if notes.isEmpty {
                    FilesEmpty(symbol: "checkmark.circle", title: "All clear", detail: "No notes are in this list right now.", action: "Home") { nav.home() }
                } else {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        Button { nav.open(note.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(note.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                                }
                                Text(note.folder.isEmpty ? "Vault" : note.folder).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                if filter == .missingProperties {
                                    VaultPropertyPills(note: note, compact: true, showMissing: true)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .kCard(radius: 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                        .contextMenu { VaultNoteMenu(note: note) }
                        .arrives(index)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            FilesHeader(title: filter.title, subtitle: notes.count == 1 ? "1 note" : "\(notes.count) notes", backLabel: "Home", back: { dismiss() })
        }
        .kScreen()
    }
}
