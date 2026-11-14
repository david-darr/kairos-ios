import SwiftUI

nonisolated enum ForgeHomeStart: Hashable, Sendable { case customize, compose }

/// Forge Home on the phone: start a task, then the widgets (all touchable), with Customize one tap away.
struct ForgeHomeScreen: View {
    var start: ForgeHomeStart? = nil
    var inspectDay: Int? = nil

    @State private var store = ForgeStore.shared
    @State private var task = ""
    @State private var projectID = "p-shop"
    @State private var mode: ForgeMode = .build
    @State private var location: ForgeLocation = .worktree
    @State private var branch = "main"
    @State private var agent = "Claude Code"
    @State private var model = "Default model"
    @State private var effort = "High"
    @State private var showModel = false
    @State private var showContext = false
    @State private var showCustomize = false
    @State private var openSession: String?
    @State private var starting = false
    @State private var needsFirstCommit = false
    @State private var selectedDay: Int?
    @State private var toast: String?
    @State private var live = DeskForgeLive.shared
    /// Paired: the model connection picked for the next session.
    @State private var endpointID: String?
    /// Paired: the session about to start, waiting for its confirm.
    @State private var confirming: DeskForgeStart?
    /// Paired: why the last start did not happen, or what could not be confirmed.
    @State private var problem: String?
    @FocusState private var typing: Bool

    /// Paired with a desktop: its projects and sessions, never the sample ones.
    private var paired: Bool { live.on }
    private var projectRows: [ForgeProject] { paired ? live.projects.map(\.row) : store.projects }
    private var liveProject: DeskForgeProject? { live.project(projectID) ?? live.projects.first }
    private var project: ForgeProject? { paired ? liveProject?.row : store.project(projectID) }
    private var liveEndpoint: String? {
        if let endpointID, live.models.contains(where: { $0.id == endpointID }) { return endpointID }
        return live.models.first?.id
    }
    private var isStarting: Bool { starting || (paired && live.isBusy("start")) }
    private var canStart: Bool {
        let typed = !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard paired else { return typed && project != nil && !starting }
        // A start whose answer was lost stays off while the phone checks whether the desktop made it.
        return typed && !isStarting && liveStart != nil && !live.isChecking(liveStart)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if paired && (!live.isAdmin || live.load != .loaded) {
                    DeskForgeGate(load: live.load) { Task { await live.loadHome() } }
                } else {
                    composer.arrives(0)
                    if paired, let problem {
                        DeskForgeLine(text: problem, action: "OK") { self.problem = nil }
                    }
                    if paired, let notice = live.startNotice {
                        if notice.checking {
                            DeskForgeLine(text: notice.text)
                        } else if let found = notice.sessionID {
                            DeskForgeLine(text: notice.text, action: "Open") {
                                live.clearStartNotice()
                                task = ""
                                openSession = found
                            }
                        } else {
                            DeskForgeLine(text: notice.text, action: "OK") { live.clearStartNotice() }
                        }
                    }
                    if needsFirstCommit && !paired { firstCommit.transition(.scale(scale: 0.96).combined(with: .opacity)) }
                    ForEach(Array(ForgeWidget.allCases.filter { store.widgets.contains($0) }.enumerated()), id: \.element) { index, widget in
                        widgetView(widget).arrives(index + 1)
                    }
                    if store.widgets.isEmpty {
                        DeskEmptyNote(symbol: "square.grid.2x2", title: "No widgets shown", text: "Choose what Forge Home shows.", action: "Customize") { showCustomize = true }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Forge", subtitle: paired ? "Coding on your desktop" : "Coding on \(store.pc.name)") {
                NavigationLink(value: DesktopRoute.forgeProjects) {
                    Image(systemName: "folder")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("Projects")
                GlassIconButton(symbol: "slider.horizontal.3", label: "Customize Forge Home") { showCustomize = true }
            }
        }
        .kScreen(glowAt: UnitPoint(x: 0.15, y: -0.05))
        .navigationDestination(item: $openSession) { id in ForgeSessionScreen(sessionID: id) }
        .sheet(isPresented: $showModel) {
            if paired {
                DeskForgeModelSheet(current: liveEndpoint) { picked in
                    endpointID = picked
                    return nil
                }
            } else {
                ForgeModelSheet(agent: $agent, model: $model, effort: $effort)
            }
        }
        .sheet(item: $confirming) { start in
            ConfirmSheet(title: "Start this session?", detail: startDetail(start), confirm: "Start session", danger: false) {
                launchLive(start)
            }
        }
        .task(id: DeskForgeLive.connectionKey) {
            if live.on { await live.loadHome() }
        }
        .sheet(isPresented: $showContext) { contextSheet }
        .sheet(isPresented: $showCustomize) { customizeSheet }
        .machineToast($toast)
        .onAppear {
            if let inspectDay { selectedDay = inspectDay }
            switch start {
            case .customize: showCustomize = true
            case .compose: showContext = true
            case nil: break
            }
            if store.composeRequested {
                store.composeRequested = false
                if paired {
                    if let wanted = live.composeProjectID { projectID = wanted }
                } else {
                    projectID = store.repoProjectID
                }
                typing = true
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What should your agents work on?")
                .font(KFont.display(26))
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 10) {
                TextField("Describe the task...", text: $task, axis: .vertical)
                    .font(KFont.ui(16.5))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2...6)
                    .focused($typing)
                    .disabled(isStarting)
                    .onChange(of: task) { needsFirstCommit = false }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(projectRows) { item in
                                Button(item.name) {
                                    projectID = item.id
                                    needsFirstCommit = false
                                }
                            }
                        } label: {
                            Chip(text: project?.name ?? "Choose a project", symbol: "folder")
                        }
                        .accessibilityLabel("Project, \(project?.name ?? "none")")
                        Button { showModel = true } label: {
                            Chip(text: modelChip, symbol: "sparkle")
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Model, \(paired ? modelChip : model). Change")
                        Button {
                            Haptics.select()
                            withAnimation(Motion.snappy) { mode = mode == .build ? .plan : .build }
                        } label: {
                            Chip(text: mode.rawValue, symbol: mode == .build ? "hammer" : "list.bullet.clipboard")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Mode, \(mode.rawValue). Switch")
                        Button { showContext = true } label: {
                            Chip(text: location.rawValue, symbol: "arrow.branch", filled: false)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Where it works, \(location.rawValue). Change")
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                HStack {
                    Text(isStarting ? "Starting..." : (liveHint ?? mode.explain))
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button(action: startTask) {
                        Image(systemName: isStarting ? "hourglass" : "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(canStart ? Palette.onGold : Palette.inkFaint)
                            .frame(width: 44, height: 44)
                            .background(canStart ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Circle())
                    }
                    .buttonStyle(PressStyle(scale: 0.88))
                    .disabled(!canStart)
                    .accessibilityLabel("Start session")
                }
            }
            .padding(16)
            .kGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private var firstCommit: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("This repository has no commits yet", systemImage: "exclamationmark.triangle")
                .font(KFont.ui(16, .semibold))
                .foregroundStyle(Palette.goldText)
            Text("A session needs one commit to branch from. Kairos can make it, then start your task.")
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
            DeskPillButton(title: "Make the first commit", symbol: "checkmark.circle", filled: true) {
                needsFirstCommit = false
                toast = "First commit made"
                launch()
            }
        }
        .padding(16)
        .kCard(radius: 22, raised: true)
    }

    private func startTask() {
        guard canStart else { return }
        typing = false
        if paired {
            // Starting makes a worktree and a branch on the desktop and spends a model run: confirm first.
            problem = nil
            confirming = liveStart
            return
        }
        if projectID == "p-notes" && !needsFirstCommit {
            withAnimation(Motion.bouncy) { needsFirstCommit = true }
            Haptics.thud()
            return
        }
        launch()
    }

    private func launch() {
        starting = true
        Haptics.tap()
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            let id = store.startSession(project: projectID, task: task, mode: mode, location: location, branch: location == .branch ? branch : nil, model: model == "Default model" ? agent : model, effort: effort)
            task = ""
            starting = false
            openSession = id
        }
    }

    private var contextSheet: some View {
        FittedSheet(estimate: 620) {
            VStack(alignment: .leading, spacing: 16) {
                DeskSheetTitle(text: "Session context")
                SectionLabel(text: "Project")
                VStack(spacing: 0) {
                    ForEach(Array(projectRows.enumerated()), id: \.element.id) { index, item in
                        Button {
                            Haptics.select()
                            projectID = item.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                    Text(item.path).font(CodeFont.mono(12)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer()
                                if project?.id == item.id { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText) }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) { if index < projectRows.count - 1 { Palette.line.frame(height: 1).padding(.leading, 16) } }
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 20)
                if paired && projectRows.isEmpty {
                    HintLine(text: "Add projects in Kairos on your desktop.")
                }
                SectionLabel(text: "Where it works")
                ChoiceRow(items: ForgeLocation.allCases, selection: $location, title: { $0.rawValue })
                Text(location.explain)
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(location == .inPlace ? Palette.goldText : Palette.inkFaint)
                if location == .branch && paired {
                    liveBranchMenu
                } else if location == .branch {
                    Menu {
                        ForEach(["main", "kairos/image-cache", "kairos/mobile-layout"], id: \.self) { item in
                            Button(item == "kairos/mobile-layout" ? "\(item) (already checked out)" : item) { branch = item }
                                .disabled(item == "kairos/mobile-layout")
                        }
                    } label: {
                        CardRow(symbol: "arrow.branch", title: "Branch", value: branch, last: true).kCard(radius: 18)
                    }
                }
                SectionLabel(text: "Mode")
                ChoiceRow(items: ForgeMode.allCases, selection: $mode, title: { $0.rawValue })
                GoldButton(title: "Done") { showContext = false }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var customizeSheet: some View {
        FittedSheet(estimate: 480) {
            VStack(alignment: .leading, spacing: 14) {
                DeskSheetTitle(text: "Customize Forge Home", detail: "Saved on this phone.")
                VStack(spacing: 0) {
                    ForEach(Array(ForgeWidget.allCases.enumerated()), id: \.element) { index, widget in
                        Toggle(isOn: Binding(
                            get: { store.widgets.contains(widget) },
                            set: { on in
                                withAnimation(Motion.snappy) {
                                    if on { store.widgets.insert(widget) } else { store.widgets.remove(widget) }
                                }
                            }
                        )) {
                            Text(widget.rawValue).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        }
                        .tint(Palette.gold)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .overlay(alignment: .bottom) { if index < ForgeWidget.allCases.count - 1 { Palette.line.frame(height: 1).padding(.leading, 16) } }
                    }
                }
                .kCard(radius: 20)
                GoldButton(title: "Done") { showCustomize = false }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: Widgets

    @ViewBuilder
    private func widgetView(_ widget: ForgeWidget) -> some View {
        switch widget {
        case .working: if paired { liveWorkingNow } else { workingNow }
        case .services: if paired { liveServices } else { services }
        case .git: if paired { liveGitActivity } else { gitActivity }
        case .recent: recentProjects
        case .lifespan: if paired { liveLifespan } else { lifespan }
        }
    }

    private var workingNow: some View {
        let live = store.liveSessions.filter { $0.state == .working || $0.state == .needsYou }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Working now")
            if live.isEmpty {
                DeskEmptyNote(symbol: "hammer", title: "Ready to build", text: "No Forge sessions running.", action: "New session") { typing = true }
                    .kCard(radius: 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(live.enumerated()), id: \.element.id) { index, session in
                        NavigationLink(value: DesktopRoute.session(session.id)) {
                            ForgeSessionRow(session: session, project: store.project(session.projectID)?.name ?? "", last: index == live.count - 1)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 22)
            }
        }
    }

    private var services: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Running services")
            if store.apps.isEmpty {
                NoteLine(text: "No apps running.").padding(16).kCard(radius: 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.apps.enumerated()), id: \.element.id) { index, app in
                        NavigationLink(value: DesktopRoute.preview(app.sessionID)) {
                            HStack(spacing: 12) {
                                PulsingDot(color: Palette.success, size: 7)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(":\(String(app.port)) \(app.title)").font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                                    Text(app.command).font(CodeFont.mono(12)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text("Preview").font(KFont.ui(14, .medium)).foregroundStyle(Palette.goldText)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) { if index < store.apps.count - 1 { Palette.line.frame(height: 1).padding(.leading, 36) } }
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 22)
            }
        }
    }

    private var gitActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Git activity")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(ForgeSample.activity.reduce(0, +))")
                        .font(KFont.ui(28, .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("commits in 14 days").font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
                    Spacer()
                    DiffCount(added: ForgeSample.activityAdded.reduce(0, +), removed: ForgeSample.activityRemoved.reduce(0, +))
                }
                ActivityBars(commits: ForgeSample.activity, added: ForgeSample.activityAdded, removed: ForgeSample.activityRemoved, selected: $selectedDay)
                HStack(spacing: 6) {
                    PulsingDot(color: Palette.working, size: 6)
                    Text("\(store.workingCount) \(store.workingCount == 1 ? "session" : "sessions") working")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(16)
            .kCard(radius: 22)
        }
    }

    private var recentProjects: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent projects").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                Spacer()
                NavigationLink(value: DesktopRoute.forgeProjects) {
                    Text("All projects").font(KFont.ui(15, .medium)).foregroundStyle(Palette.goldText).frame(minHeight: 44)
                }
            }
            if paired && projectRows.isEmpty {
                HintLine(text: "No projects yet. Add projects in Kairos on your desktop.")
            }
            VStack(spacing: 0) {
                ForEach(Array(projectRows.prefix(5).enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: DesktopRoute.project(item.id)) {
                        HStack(spacing: 12) {
                            Text(String(item.name.prefix(1)).uppercased())
                                .font(KFont.ui(16, .semibold))
                                .foregroundStyle(Palette.onGold)
                                .frame(width: 36, height: 36)
                                .background(Palette.gold.opacity(0.85), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                Text(item.path).font(CodeFont.mono(12)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 58)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) { if index < min(5, projectRows.count) - 1 { Palette.line.frame(height: 1).padding(.leading, 64) } }
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
            .kCard(radius: 22)
        }
    }

    private var lifespan: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Repo lifespan").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                Spacer()
                Menu {
                    ForEach(store.projects) { item in
                        Button(item.name) { store.repoProjectID = item.id }
                    }
                } label: {
                    Chip(text: store.project(store.repoProjectID)?.name ?? "Repository", symbol: "chevron.down", filled: false)
                }
                .accessibilityLabel("Repository")
            }
            let repo = ForgeSample.repo
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(title: "Commits", value: repo.commits.formatted(), delta: repo.commitsDelta)
                StatTile(title: "Repo age", value: "\(repo.ageDays) days")
            }
            NavigationLink(value: DesktopRoute.repo(store.repoProjectID)) {
                CardRow(symbol: "chart.bar.xaxis", title: "History, languages and rhythm", detail: "Since \(repo.first)", last: true)
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .kCard(radius: 20)
        }
    }
}

// MARK: - Paired with a desktop

extension ForgeHomeScreen {

    private var modelChip: String {
        guard paired else { return model == "Default model" ? agent : model }
        return liveEndpoint.map { live.modelName($0) } ?? "No model"
    }

    /// The branch picked for "Existing branch", when the desktop has it and it is not checked out anywhere.
    private func liveBranch(_ projectID: String) -> String? {
        live.branches(projectID)?.first { $0.name == branch && $0.worktree == nil }?.name
    }

    /// What Start would send, or nil while something is missing.
    private var liveStart: DeskForgeStart? {
        guard let chosen = liveProject, chosen.gitProblem == nil, let endpoint = liveEndpoint else { return nil }
        let words = task.trimmingCharacters(in: .whitespacesAndNewlines)
        switch location {
        case .worktree:
            return DeskForgeStart(projectID: chosen.id, task: words, mode: mode == .plan ? "plan" : "build",
                                  isolation: "new_worktree", branch: nil, endpointID: endpoint)
        case .branch:
            guard let picked = liveBranch(chosen.id) else { return nil }
            return DeskForgeStart(projectID: chosen.id, task: words, mode: mode == .plan ? "plan" : "build",
                                  isolation: "existing_branch", branch: picked, endpointID: endpoint)
        case .inPlace:
            return DeskForgeStart(projectID: chosen.id, task: words, mode: mode == .plan ? "plan" : "build",
                                  isolation: "in_place", branch: nil, endpointID: endpoint)
        }
    }

    /// Paired: the one thing standing in the way of a start, in place of the mode's line.
    private var liveHint: String? {
        guard paired else { return nil }
        guard let chosen = liveProject else { return "Add projects in Kairos on your desktop." }
        if let wrong = chosen.gitProblem { return wrong }
        if live.models.isEmpty { return "No model was read from your desktop. Add one there first." }
        if location == .branch && liveBranch(chosen.id) == nil { return "Choose a branch that is not checked out." }
        return nil
    }

    /// The confirm's words: the project, the branch and what it will cost, named plainly.
    private func startDetail(_ start: DeskForgeStart) -> String {
        let chosen = live.project(start.projectID)
        let name = chosen?.name ?? "this project"
        let base = (chosen?.branch ?? "").isEmpty ? "its current branch" : (chosen?.branch ?? "")
        let place: String
        switch start.isolation {
        case "existing_branch": place = "It works on the branch \(start.branch ?? "") of \(name), in its own worktree."
        case "in_place": place = "It works directly in the folder of \(name), on \(base). Changes land in that folder."
        default: place = "It makes a new worktree and a new branch from \(base) in \(name)."
        }
        let what = start.mode == "plan"
            ? "\(live.modelName(start.endpointID)) reads and proposes a plan. It changes nothing."
            : "\(live.modelName(start.endpointID)) starts on your task and asks before edits and commands."
        return place + " " + what + " This runs on your desktop."
    }

    private func launchLive(_ start: DeskForgeStart) {
        guard !isStarting, !live.isChecking(start) else { return }
        starting = true
        Haptics.tap()
        Task {
            let result = await live.startSession(start)
            starting = false
            if let id = result.id {
                task = ""
                openSession = id
            } else if let line = result.outcome.line, !live.isChecking(start) {
                // The first commit is made on the desktop: the phone does not offer it while paired.
                problem = line.contains("has no commits yet") ? line + " Make it in Kairos on your desktop." : line
            }
        }
    }

    @ViewBuilder
    private var liveBranchMenu: some View {
        if let chosen = liveProject {
            let list = live.branches(chosen.id)
            Menu {
                ForEach(list ?? [], id: \.name) { item in
                    Button(item.worktree == nil ? item.name : "\(item.name) (already checked out)") { branch = item.name }
                        .disabled(item.worktree != nil)
                }
            } label: {
                CardRow(symbol: "arrow.branch", title: "Branch", value: list == nil ? "Reading" : (liveBranch(chosen.id) ?? "Choose"), last: true)
                    .kCard(radius: 18)
            }
            .disabled(list == nil)
            .task(id: chosen.id) { await live.loadBranches(chosen.id) }
        }
    }

    private var liveWorkingNow: some View {
        let working = live.openSessions.filter { session in
            let state = live.state(of: session.id)
            return state == .working || state == .needsYou
        }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Working now")
            if working.isEmpty {
                DeskEmptyNote(symbol: "hammer", title: "Ready to build", text: "No Forge sessions running.", action: "New session") { typing = true }
                    .kCard(radius: 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(working.enumerated()), id: \.element.id) { index, session in
                        NavigationLink(value: DesktopRoute.session(session.id)) {
                            ForgeSessionRow(session: live.info(session), project: live.project(session.projectID)?.name ?? "",
                                            last: index == working.count - 1, counts: false)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 22)
            }
        }
    }

    /// Apps the desktop runs for sessions. Their pages open on the desktop only, so these rows do not.
    private var liveServices: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Running services")
            if live.apps.isEmpty {
                NoteLine(text: "No apps running.").padding(16).kCard(radius: 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(live.apps.enumerated()), id: \.element.id) { index, app in
                        HStack(spacing: 12) {
                            PulsingDot(color: Palette.success, size: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(":\(String(app.port)) \(live.session(app.sessionID)?.title ?? "Forge app")")
                                    .font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                                Text(app.command).font(CodeFont.mono(12)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                        .overlay(alignment: .bottom) { if index < live.apps.count - 1 { Palette.line.frame(height: 1).padding(.leading, 36) } }
                        .accessibilityElement(children: .combine)
                    }
                }
                .kCard(radius: 22)
                HintLine(text: "Open a running app in Kairos on your desktop.")
            }
        }
    }

    private var liveGitActivity: some View {
        let days = live.days
        let commits = days.map { $0.commits ?? 0 }
        let added = days.map { $0.added ?? 0 }
        let removed = days.map { $0.removed ?? 0 }
        let working = live.openSessions.filter { live.state(of: $0.id) == .working }.count
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Git activity")
            if days.isEmpty {
                NoteLine(text: "No git activity was read from your desktop.").padding(16).kCard(radius: 20)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(commits.reduce(0, +))")
                            .font(KFont.ui(28, .semibold))
                            .foregroundStyle(Palette.ink)
                        Text("commits in \(days.count) days").font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
                        Spacer()
                        DiffCount(added: added.reduce(0, +), removed: removed.reduce(0, +))
                    }
                    ActivityBars(commits: commits, added: added, removed: removed, selected: $selectedDay)
                    HStack(spacing: 6) {
                        PulsingDot(color: Palette.working, size: 6)
                        Text("\(working) \(working == 1 ? "session" : "sessions") working")
                            .font(KFont.ui(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                .padding(16)
                .kCard(radius: 22)
            }
        }
    }

    private var liveLifespan: some View {
        let chosen = live.repoProjectID.flatMap { live.project($0) }
        let repo = DeskForgeLive.repo(chosen?.git)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Repo lifespan").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                Spacer()
                Menu {
                    ForEach(live.projects) { item in
                        Button(item.name) { live.repoProjectID = item.id }
                    }
                } label: {
                    Chip(text: chosen?.name ?? "Repository", symbol: "chevron.down", filled: false)
                }
                .accessibilityLabel("Repository")
            }
            if let chosen, let repo {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatTile(title: "Commits", value: repo.commits.formatted(), delta: repo.commitsDelta)
                    StatTile(title: "Repo age", value: "\(repo.ageDays) days")
                }
                NavigationLink(value: DesktopRoute.repo(chosen.id)) {
                    CardRow(symbol: "chart.bar.xaxis", title: "History, languages and rhythm", detail: "Since \(repo.first)", last: true)
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .kCard(radius: 20)
            } else {
                NoteLine(text: chosen == nil ? "No projects yet." : (chosen?.gitProblem ?? "No history was read for this project."))
                    .padding(16).kCard(radius: 20)
            }
        }
    }
}

/// One Forge session in a list: title, project, branch, mode, change counts and its state.
struct ForgeSessionRow: View {
    let session: ForgeSessionInfo
    let project: String
    var last = false
    /// false for a desktop's session in a list: its change counts are not read there, so none are shown.
    var counts = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                HStack(spacing: 6) {
                    Text(project).foregroundStyle(Palette.inkFaint)
                    Text("·").foregroundStyle(Palette.inkFaint)
                    Text(session.placeLabel).foregroundStyle(Palette.inkFaint).lineLimit(1)
                    Text("·").foregroundStyle(Palette.inkFaint)
                    Text(session.mode.rawValue).foregroundStyle(Palette.inkFaint)
                }
                .font(KFont.ui(13, relativeTo: .footnote))
                .lineLimit(1)
                HStack(spacing: 8) {
                    if counts { DiffCount(added: session.added, removed: session.removed, size: 13) }
                    stateLabel
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last { Palette.line.frame(height: 1).padding(.leading, 16) } }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stateLabel: some View {
        if session.ended {
            Text("Ended · \(session.updated)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
        } else {
            openStateLabel
        }
    }

    @ViewBuilder
    private var openStateLabel: some View {
        switch session.state {
        case .needsYou:
            HStack(spacing: 5) {
                Circle().fill(Palette.gold).frame(width: 8, height: 8)
                Text("Waiting for you").foregroundStyle(Palette.goldText)
            }
            .font(KFont.ui(13, .medium, relativeTo: .footnote))
        case .working:
            HStack(spacing: 6) {
                PulsingDot(color: Palette.working, size: 6)
                Text("Working").foregroundStyle(Palette.working)
            }
            .font(KFont.ui(13, .medium, relativeTo: .footnote))
        case .done:
            Text("Done · \(session.updated)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.success)
        case .idle:
            Text("Idle · \(session.updated)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
        }
    }
}
