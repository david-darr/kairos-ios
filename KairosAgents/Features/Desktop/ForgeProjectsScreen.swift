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

    private var shown: [ForgeProject] {
        search.isEmpty ? store.projects : store.projects.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MachineSearchField(prompt: "Search projects", text: $search)
                if store.projects.isEmpty {
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
                                    Button { store.repoProjectID = item.id; toast = "Shown on Forge Home" } label: { Label("Open on Home", systemImage: "house") }
                                    Button { UIPasteboard.general.string = item.path; toast = "Path copied" } label: { Label("Copy path", systemImage: "doc.on.doc") }
                                    Button(role: .destructive) { removing = item } label: { Label("Remove from list", systemImage: "minus.circle") }
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
                                Button(role: .destructive) { removing = item } label: { Label("Remove from list", systemImage: "minus.circle") }
                            }
                            .arrives(index)
                        }
                    }
                    .kCard(radius: 22)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Projects", subtitle: "\(store.projects.count) on \(store.pc.name)") {
                GlassIconButton(symbol: "plus", label: "Add project") { showAdd = true }
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
        .machineToast($toast)
        .onAppear { if start == .add { showAdd = true } }
    }

    private func projectRow(_ item: ForgeProject) -> some View {
        let live = store.sessions(in: item.id)
        let added = live.reduce(0) { $0 + $1.added }
        let removed = live.reduce(0) { $0 + $1.removed }
        let busy = live.contains { $0.state == .working }
        let appRunning = store.apps.contains { app in live.contains { $0.id == app.sessionID } }
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

    private var project: ForgeProject? { store.project(projectID) }

    private var shown: [ForgeSessionInfo] {
        store.sessions(in: projectID).filter { session in
            (search.isEmpty || session.title.localizedCaseInsensitiveContains(search)) &&
            (!workingOnly || session.state == .working || session.state == .needsYou)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MachineSearchField(prompt: "Search sessions", text: $search)
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
                let apps = store.apps.filter { app in store.sessions(in: projectID).contains { $0.id == app.sessionID } }
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
                group("Today", shown.filter(\.today))
                group("Earlier", shown.filter { !$0.today })
                if shown.isEmpty {
                    DeskEmptyNote(symbol: "bubble.left.and.text.bubble.right", title: search.isEmpty ? "No sessions" : "No matching sessions", text: search.isEmpty ? "Start a session with New session." : "Try another word.")
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
                    if let project { store.repoProjectID = project.id }
                    store.composeRequested = true
                })
                .buttonStyle(PressStyle(scale: 0.9))
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("New session")
            }
        }
        .kScreen()
        .sheet(item: $renaming) { session in
            ForgeRenameSheet(title: session.title) { name in store.update(session.id) { $0.title = name } }
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
        .machineToast($toast)
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
                                ForgeSessionRow(session: session, project: session.agent, last: true)
                            }
                            .buttonStyle(PressStyle(scale: 0.98))
                            Menu {
                                Button { renaming = session } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { deleting = session } label: { Label("Delete", systemImage: "trash") }
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
                            Button { renaming = session } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) { deleting = session } label: { Label("Delete", systemImage: "trash") }
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

    var body: some View {
        let repo = ForgeSample.repo
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
                        Text(selected.map { "\(repo.history[$0]) commits" } ?? repo.historyLabel)
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
            ScreenHeader(title: "Repo lifespan", subtitle: "\(store.project(projectID)?.name ?? "") · \(repo.ageDays) days old")
        }
        .kScreen()
    }
}
