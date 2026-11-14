import SwiftUI
import UIKit

nonisolated enum ForgeProjectsStart: Hashable, Sendable { case add }

nonisolated enum AddProjectKind: String, CaseIterable, Hashable, Sendable {
    case folder = "Open folder", clone = "Clone repo", new = "New repo"
}

/// Every project, with search, the project actions and Add project.
struct ForgeProjectsScreen: View {
    var start: ForgeProjectsStart? = nil
    @State private var store = ForgeStore.shared
    @State private var search = ""
    @State private var showAdd = false
    @State private var removing: ForgeProject?
    @State private var toast: String?
    @State private var desk = DeskForgeLive.shared
    /// Paired: the project waiting for its confirm before it leaves the desktop's list.
    @State private var deskRemoving: ForgeProject?
    @State private var problem: String?

    /// Paired with a desktop: its projects, never the sample ones.
    private var paired: Bool { desk.on }
    private var all: [ForgeProject] { paired ? desk.projects.map(\.row) : store.projects }

    private var shown: [ForgeProject] {
        search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if paired && (!desk.isAdmin || desk.load != .loaded) {
                    DeskForgeGate(load: desk.load) { Task { await desk.loadHome() } }
                } else {
                    list
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Projects", subtitle: paired ? "\(all.count) on your desktop" : "\(store.projects.count) on \(store.pc.name)") {
                // Adding, creating and cloning a project stay on the desktop while paired.
                if !paired {
                    GlassIconButton(symbol: "plus", label: "Add project") { showAdd = true }
                }
            }
        }
        .kScreen()
        .sheet(isPresented: $showAdd) { AddProjectSheet { name, path in
            store.projects.insert(ForgeProject(id: "p-\(UUID().uuidString.prefix(5))", name: name, path: path, branch: "main", lastOpened: "Now"), at: 0)
            toast = "\(name) added"
        } }
        .confirmationDialog("Remove \(removing?.name ?? "this project") from the list?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove from list", role: .destructive) {
                if let removing {
                    withAnimation(Motion.snappy) { store.projects.removeAll { $0.id == removing.id } }
                    toast = "Removed. Its files are kept."
                }
                removing = nil
            }
        } message: {
            Text("The folder and its files stay on your PC.")
        }
        .sheet(item: $deskRemoving) { item in
            ConfirmSheet(title: "Remove \(item.name) from the list?",
                         detail: "Only its entry in Forge on your desktop is removed. The folder and its files stay where they are.",
                         confirm: "Remove from list") {
                removeLive(item)
            }
        }
        .machineToast($toast)
        .onAppear { if start == .add && !paired { showAdd = true } }
        .task(id: DeskForgeLive.connectionKey) {
            if desk.on { await desk.loadHome() }
        }
    }

    private func removeLive(_ item: ForgeProject) {
        problem = nil
        Task {
            let outcome = await desk.removeProject(item.id)
            if outcome == .done { toast = "Removed. Its files are kept." }
            if let line = outcome.line { problem = line }
        }
    }

    private func askRemove(_ item: ForgeProject) {
        if paired { deskRemoving = item } else { removing = item }
    }

    @ViewBuilder
    private var list: some View {
                MachineSearchField(prompt: "Search projects", text: $search)
                if paired, let problem {
                    DeskForgeLine(text: problem, action: "OK") { self.problem = nil }
                }
                if all.isEmpty && paired {
                    DeskEmptyNote(symbol: "folder.badge.plus", title: "No projects yet", text: "Add projects in Kairos on your desktop.")
                } else if store.projects.isEmpty && !paired {
                    DeskEmptyNote(symbol: "folder.badge.plus", title: "No projects yet", text: "Open a folder to begin.", action: "Add project") { showAdd = true }
                } else if shown.isEmpty {
                    NoteLine(text: "No project matches that.").padding(.top, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 0) {
                                NavigationLink(value: DesktopRoute.project(item.id)) {
                                    projectRow(item)
                                }
                                .buttonStyle(PressStyle(scale: 0.98))
                                Menu {
                                    Button {
                                        if paired { desk.repoProjectID = item.id } else { store.repoProjectID = item.id }
                                        toast = "Shown on Forge Home"
                                    } label: { Label("Open on Home", systemImage: "house") }
                                    Button { UIPasteboard.general.string = item.path; toast = "Path copied" } label: { Label("Copy path", systemImage: "doc.on.doc") }
                                    Button(role: .destructive) { askRemove(item) } label: { Label("Remove from list", systemImage: "minus.circle") }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Palette.inkDim)
                                        .frame(width: 48, height: 52)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("\(item.name) options")
                            }
                            .overlay(alignment: .bottom) { if index < shown.count - 1 { Palette.line.frame(height: 1).padding(.leading, 66) } }
                            .contextMenu {
                                Button { UIPasteboard.general.string = item.path; toast = "Path copied" } label: { Label("Copy path", systemImage: "doc.on.doc") }
                                Button(role: .destructive) { askRemove(item) } label: { Label("Remove from list", systemImage: "minus.circle") }
                            }
                            .arrives(index)
                        }
                    }
                    .kCard(radius: 22)
                }
                if paired {
                    HintLine(text: "Add projects in Kairos on your desktop.")
                    if desk.skipped > 0 {
                        HintLine(text: "\(desk.skipped) could not be read and are not shown.")
                    }
                }
    }

    private func projectRow(_ item: ForgeProject) -> some View {
        let live = store.sessions(in: item.id)
        let added = live.reduce(0) { $0 + $1.added }
        let removed = live.reduce(0) { $0 + $1.removed }
        // Paired: the desktop's sessions and apps for this project (the sample store has none under its id).
        let busy = paired
            ? desk.sessions(in: item.id).contains { !$0.ended && desk.state(of: $0.id) == .working }
            : live.contains { $0.state == .working }
        let appRunning = paired
            ? desk.apps.contains { $0.projectID == item.id }
            : store.apps.contains { app in live.contains { $0.id == app.sessionID } }
        return HStack(spacing: 12) {
            Text(String(item.name.prefix(1)).uppercased())
                .font(KFont.ui(17, .semibold))
                .foregroundStyle(Palette.onGold)
                .frame(width: 38, height: 38)
                .background(Palette.gold.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if busy { PulsingDot(color: Palette.working, size: 8).offset(x: 3, y: -3) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                Text(item.path).font(CodeFont.mono(12)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                HStack(spacing: 8) {
                    if added + removed > 0 { DiffCount(added: added, removed: removed, size: 12.5) }
                    if appRunning {
                        Label("App running", systemImage: "play.circle.fill").font(KFont.ui(12.5)).foregroundStyle(Palette.success)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Open an existing folder, clone a repository or start a new one.
struct AddProjectSheet: View {
    let onAdd: (String, String) -> Void
    @State private var kind: AddProjectKind = .folder
    @State private var name = ""
    @State private var path = "C:/Projects/"
    @State private var url = ""
    @State private var browsing = "C:/Projects"
    @State private var saving = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    private let folders: [String: [String]] = [
        "C:/Projects": ["bike-rentals", "portfolio", "shop-site", "inventory-api"],
        "C:/Projects/bike-rentals": ["src", "docs"],
        "C:/Projects/portfolio": ["pages", "images"],
    ]
    private let recent = ["C:/Projects/bike-rentals", "C:/Projects/portfolio"]

    var body: some View {
        FittedSheet(estimate: 700) {
            VStack(alignment: .leading, spacing: 14) {
                DeskSheetTitle(text: "Add project")
                ChoiceRow(items: AddProjectKind.allCases, selection: $kind, title: { $0.rawValue })
                switch kind {
                case .folder: folderForm
                case .clone: cloneForm
                case .new: newForm
                }
                if let problem {
                    NoteLine(text: problem, symbol: "exclamationmark.triangle").foregroundStyle(Palette.danger)
                }
                GoldButton(title: saving ? (kind == .clone ? "Cloning repository..." : "Adding project...") : (kind == .folder ? "Add project" : (kind == .clone ? "Clone" : "Create"))) { save() }
                    .disabled(saving)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .onChange(of: kind) { problem = nil }
        }
    }

    private func field(_ title: String, _ text: Binding<String>, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            TextField(title, text: text)
                .font(mono ? CodeFont.mono(14.5) : KFont.ui(16.5))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .kCard(radius: 16)
        }
    }

    private var folderForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Name (optional)", $name)
            field("Folder on your PC", $path, mono: true)
            SectionLabel(text: "Browse \(browsing)")
            VStack(spacing: 0) {
                if browsing != "C:/Projects" {
                    Button {
                        browsing = "C:/Projects"
                    } label: {
                        CardRow(symbol: "arrow.up", title: "Parent folder", chevron: false)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
                let children = folders[browsing] ?? []
                ForEach(Array(children.enumerated()), id: \.element) { index, child in
                    Button {
                        let full = browsing + "/" + child
                        path = full
                        if folders[full] != nil { browsing = full }
                    } label: {
                        CardRow(symbol: "folder", title: child, last: index == children.count - 1)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
            .kCard(radius: 18)
            SectionLabel(text: "Recent chat workspaces")
            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element) { index, item in
                    Button { path = item } label: {
                        CardRow(symbol: "clock", title: item, last: index == recent.count - 1, chevron: false)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
            .kCard(radius: 18)
        }
    }

    private var cloneForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Name", $name)
            field("Repository address", $url, mono: true)
            NoteLine(text: "For example https://example.com/you/shop.git or git@example.com:you/shop.git")
            NoteLine(text: "New folder under C:/Projects", symbol: "folder")
        }
    }

    private var newForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Name", $name)
            NoteLine(text: "New folder under C:/Projects", symbol: "folder")
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .folder:
            let cleanPath = path.trimmingCharacters(in: .whitespaces)
            guard cleanPath.count > "C:/Projects/".count else { problem = "Fill in the required field."; return }
            finish(cleanName.isEmpty ? String(cleanPath.split(separator: "/").last ?? "project") : cleanName, cleanPath)
        case .clone:
            guard !cleanName.isEmpty, !url.trimmingCharacters(in: .whitespaces).isEmpty else { problem = "Fill in the required field."; return }
            finish(cleanName, "C:/Projects/" + cleanName)
        case .new:
            guard !cleanName.isEmpty else { problem = "Fill in the required field."; return }
            finish(cleanName, "C:/Projects/" + cleanName)
        }
    }

    private func finish(_ name: String, _ path: String) {
        problem = nil
        saving = true
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            saving = false
            Haptics.success()
            dismiss()
            onAdd(name, path)
        }
    }
}

/// A project's page: its sessions (search, Today and Earlier, filters, rename and delete), running apps and New session.
struct ForgeProjectScreen: View {
    let projectID: String
    @State private var store = ForgeStore.shared
    @State private var search = ""
    @State private var workingOnly = false
    @State private var renaming: ForgeSessionInfo?
    @State private var deleting: ForgeSessionInfo?
    @State private var toast: String?
    @State private var desk = DeskForgeLive.shared
    /// Paired: the session waiting for its confirm before its worktree is removed.
    @State private var deskEnding: ForgeSessionInfo?
    @State private var problem: String?

    /// Paired with a desktop: its sessions, never the sample ones.
    private var paired: Bool { desk.on }
    private var project: ForgeProject? { paired ? desk.project(projectID)?.row : store.project(projectID) }
    private var sessions: [ForgeSessionInfo] {
        paired ? desk.sessions(in: projectID).map { desk.info($0) } : store.sessions(in: projectID)
    }

    private var shown: [ForgeSessionInfo] {
        sessions.filter { session in
            (search.isEmpty || session.title.localizedCaseInsensitiveContains(search)) &&
            (!workingOnly || session.state == .working || session.state == .needsYou)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if paired && (!desk.isAdmin || desk.load != .loaded) {
                    DeskForgeGate(load: desk.load) { Task { await desk.loadHome() } }
                } else {
                    page
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: project?.name ?? "Project", subtitle: project.map { "\($0.branch) · \($0.path)" }) {
                NavigationLink(value: DesktopRoute.forgeHome) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .simultaneousGesture(TapGesture().onEnded {
                    if paired {
                        desk.composeProjectID = projectID
                    } else if let project {
                        store.repoProjectID = project.id
                    }
                    store.composeRequested = true
                })
                .buttonStyle(PressStyle(scale: 0.9))
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("New session")
            }
        }
        .kScreen()
        .sheet(item: $renaming) { session in
            if paired {
                DeskForgeRenameSheet(sessionID: session.id, title: session.title)
            } else {
                ForgeRenameSheet(title: session.title) { name in store.update(session.id) { $0.title = name } }
            }
        }
        .confirmationDialog("Delete \(deleting?.title ?? "this session")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                if let deleting { withAnimation(Motion.snappy) { store.sessions.removeAll { $0.id == deleting.id } } }
                deleting = nil
                toast = "Session deleted"
            }
        } message: {
            Text("The conversation is deleted. Files on your PC stay as they are.")
        }
        .sheet(item: $deskEnding) { session in
            ConfirmSheet(title: "End \(session.title)?",
                         detail: session.branch == nil
                            ? "It works in your project folder, which stays as it is. Its app stops and the conversation is kept."
                            : "Its worktree is removed from your desktop. The branch \(session.branch ?? "") and the conversation are kept. Your desktop refuses if the worktree has uncommitted changes.",
                         confirm: "End session") {
                endLive(session)
            }
        }
        .machineToast($toast)
        .task(id: DeskForgeLive.connectionKey) {
            if desk.on { await desk.loadHome() }
        }
    }

    /// Paired: the Forge route only. It removes the worktree and ends the session; the chat's own delete
    /// would leave the worktree behind, so it is never used here.
    private func endLive(_ session: ForgeSessionInfo) {
        problem = nil
        Task {
            let outcome = await desk.removeWorktree(session.id)
            if outcome == .done { toast = "Session ended" }
            if let line = outcome.line { problem = line }
        }
    }

    @ViewBuilder
    private var page: some View {
                MachineSearchField(prompt: "Search sessions", text: $search)
                if paired, let problem {
                    DeskForgeLine(text: problem, action: "OK") { self.problem = nil }
                }
                HStack(spacing: 8) {
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) { workingOnly.toggle() }
                    } label: {
                        Chip(text: "Working now", symbol: workingOnly ? "checkmark" : "circle", filled: workingOnly)
                    }
                    .buttonStyle(PressStyle())
                    NavigationLink(value: DesktopRoute.repo(projectID)) {
                        Chip(text: "Repo history", symbol: "chart.bar.xaxis", filled: false)
                    }
                    .buttonStyle(PressStyle())
                }
                if paired {
                    let running = desk.apps.filter { $0.projectID == projectID }
                    if !running.isEmpty {
                        // The app's page opens on the desktop only, so these do not open.
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(running) { app in
                                    HStack(spacing: 7) {
                                        PulsingDot(color: Palette.success, size: 6)
                                        Text(":\(String(app.port)) \(desk.session(app.sessionID)?.title ?? "App")")
                                            .font(KFont.ui(13.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                                    }
                                    .padding(.horizontal, 13)
                                    .frame(height: 38)
                                    .kGlass(Capsule())
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                    }
                }
                let apps = paired ? [] : store.apps.filter { app in store.sessions(in: projectID).contains { $0.id == app.sessionID } }
                if !apps.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(apps) { app in
                                NavigationLink(value: DesktopRoute.preview(app.sessionID)) {
                                    HStack(spacing: 7) {
                                        PulsingDot(color: Palette.success, size: 6)
                                        Text(":\(String(app.port)) \(app.title)").font(KFont.ui(13.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                                    }
                                    .padding(.horizontal, 13)
                                    .frame(height: 38)
                                    .kGlass(Capsule())
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
                group("Today", shown.filter { $0.today && !$0.ended })
                group("Earlier", shown.filter { !$0.today && !$0.ended })
                group("Ended", shown.filter(\.ended))
                if shown.isEmpty {
                    DeskEmptyNote(symbol: "bubble.left.and.text.bubble.right", title: search.isEmpty ? "No sessions" : "No matching sessions", text: search.isEmpty ? "Start a session with New session." : "Try another word.")
                }
    }

    /// The row's menu. Paired, a session is ended through Forge (its worktree goes, the conversation stays);
    /// the desktop has no way to delete a Forge conversation and keep things tidy, so none is offered.
    @ViewBuilder
    private func rowActions(_ session: ForgeSessionInfo) -> some View {
        Button { renaming = session } label: { Label("Rename", systemImage: "pencil") }
        if !paired {
            Button(role: .destructive) { deleting = session } label: { Label("Delete", systemImage: "trash") }
        } else if !session.ended {
            Button(role: .destructive) { deskEnding = session } label: { Label("End session", systemImage: "xmark.circle") }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ sessions: [ForgeSessionInfo]) -> some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: title)
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        HStack(spacing: 0) {
                            NavigationLink(value: DesktopRoute.session(session.id)) {
                                ForgeSessionRow(session: session, project: session.agent, last: true, counts: !paired)
                            }
                            .buttonStyle(PressStyle(scale: 0.98))
                            Menu {
                                rowActions(session)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Palette.inkDim)
                                    .frame(width: 44, height: 60)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("\(session.title) options")
                        }
                        .overlay(alignment: .bottom) { if index < sessions.count - 1 { Palette.line.frame(height: 1).padding(.leading, 16) } }
                        .contextMenu {
                            rowActions(session)
                        }
                    }
                }
                .kCard(radius: 22)
            }
        }
    }
}

/// The full repository history for one project.
struct ForgeRepoScreen: View {
    let projectID: String
    @State private var store = ForgeStore.shared
    @State private var selected: Int?
    @State private var desk = DeskForgeLive.shared

    var body: some View {
        if desk.on {
            livePage
        } else {
            page(ForgeSample.repo, name: store.project(projectID)?.name ?? "")
        }
    }

    /// Paired: this project's history as the desktop summarises it.
    @ViewBuilder
    private var livePage: some View {
        let chosen = desk.project(projectID)
        if desk.isAdmin, desk.load == .loaded, let chosen, let repo = DeskForgeLive.repo(chosen.git) {
            page(repo, name: chosen.name)
                .task(id: DeskForgeLive.connectionKey + "|" + projectID) { await desk.loadSummary(projectID) }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if desk.isAdmin, desk.load == .loaded {
                    DeskForgeLine(text: chosen == nil ? "This project is not on your desktop's list any more."
                                  : (chosen?.gitProblem ?? "No history was read for this project."))
                } else {
                    DeskForgeGate(load: desk.load) { Task { await desk.loadHome() } }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Repo lifespan", subtitle: chosen?.name) }
            .kScreen()
            .task(id: DeskForgeLive.connectionKey) { await desk.loadHome() }
        }
    }

    private func page(_ repo: RepoStats, name: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatTile(title: "Commits", value: repo.commits.formatted(), delta: repo.commitsDelta)
                    StatTile(title: "Contributors", value: "\(repo.contributors)", delta: repo.contributorsDelta)
                    StatTile(title: "Lines added", value: repo.added.formatted(), delta: repo.addedDelta)
                    StatTile(title: "Lines removed", value: repo.removed.formatted(), delta: repo.removedDelta)
                }
                HStack {
                    Label("First commit \(repo.first)", systemImage: "flag")
                    Spacer()
                    Label("Latest \(repo.latest)", systemImage: "clock")
                }
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Commits over time").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(selected.flatMap { repo.history.indices.contains($0) ? "\(repo.history[$0]) commits" : nil } ?? repo.historyLabel)
                            .font(KFont.ui(13.5)).foregroundStyle(selected == nil ? Palette.inkFaint : Palette.goldText)
                    }
                    HistoryBars(values: repo.history, selected: $selected).frame(height: 110)
                }
                .padding(16).kCard(radius: 22)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Languages").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                    LanguageDonut(languages: repo.languages)
                }
                .padding(16).kCard(radius: 22)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Commit rhythm").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                    RhythmHeatmap(rhythm: repo.rhythm)
                }
                .padding(16).kCard(radius: 22)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Most changed files").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                    RankedTable(rows: repo.files, mono: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contributors").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                    RankedTable(rows: repo.people)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Repo lifespan", subtitle: "\(name) · \(repo.ageDays) days old")
        }
        .kScreen()
    }
}
