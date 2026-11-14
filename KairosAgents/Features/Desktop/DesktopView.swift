import SwiftUI

/// Your PC from your pocket: its status, running apps, Forge sessions, and every desktop area.
struct DesktopView: View {
    var asleep = false
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var store = ForgeStore.shared
    @State private var nav = DesktopNav.shared
    @State private var live = DeskForgeLive.shared
    @Namespace private var zoom

    /// Paired with a desktop: every part below shows that desktop, never the sample one.
    private var paired: Bool { live.on }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        @Bindable var nav = nav
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if paired {
                    livePCCard.arrives(0)
                    liveForge
                } else {
                    pcCard.arrives(0)
                    if !store.apps.isEmpty { appsRow.arrives(1) }
                    sessionsCard.arrives(2)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("On this PC").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                    LazyVGrid(columns: columns, spacing: 10) {
                        areaTile("hammer", "Forge", forgeDetail, id: "forge") { open(.forgeHome) }
                        // Paired, a tile whose screen still shows made-up data stays closed (constants in DeskForgeLive).
                        if !paired || DeskForgeLive.computerLive {
                            areaTile("cursorarrow.rays", "Computer", "See and steer", id: "computer") { router.push(.area(.computer), on: .desktop) }
                        }
                        if !paired || DeskForgeLive.browseLive {
                            areaTile("globe", "Browse", "Your PC's browser", id: "browse") { router.push(.area(.browse), on: .desktop) }
                        }
                        if !paired || DeskForgeLive.localModelsLive {
                            areaTile("cpu", "Local models", "Run on this PC", id: "models") { open(.localModels) }
                        }
                        if !paired || DeskForgeLive.pcFilesLive {
                            areaTile("folder", "Files on this PC", "Projects and folders", id: "files") { open(.pcFiles("")) }
                        }
                        areaTile("folder.badge.plus", "Projects", projectsDetail, id: "projects") { open(.forgeProjects) }
                    }
                    if paired && DeskForgeLive.desktopTilesWaiting {
                        HintLine(text: "Computer, Browse, local models and PC files are not on this iPhone yet. Use them in Kairos on your desktop.")
                    }
                }
                .arrives(3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        .shrinksBar(chrome)
        .safeAreaInset(edge: .top, spacing: 0) {
            TabHeader(title: "Desktop") {
                GlassIconButton(symbol: "magnifyingglass", label: "Search") { router.sheet = .search }
            }
        }
        .kScreen(glowAt: UnitPoint(x: 0.9, y: 0.02))
        .fullScreenCover(item: $nav.open) { item in
            DesktopWorkspace(start: item.route)
                .environment(router)
                .environment(chrome)
                .navigationTransition(.zoom(sourceID: zoomID(item.route), in: zoom))
        }
        .onChange(of: chrome.addTick) {
            if router.tab == .desktop { open(.forgeHome) }
        }
        .onAppear {
            if asleep {
                store.pc.asleep = true
                store.pc.online = false
                store.pc.lastSeen = "40 min ago"
            }
        }
        .task(id: DeskForgeLive.connectionKey) {
            guard live.on else { return }
            await live.loadHome()
            // While this tab is in front: the counts, the running turns and the apps, a few times a minute.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                if Task.isCancelled { break }
                if router.tab == .desktop, nav.open == nil { await live.refreshHome() }
            }
        }
    }

    // MARK: Paired

    private var forgeDetail: String {
        guard paired else { return "\(store.liveSessions.count) sessions" }
        guard live.isAdmin else { return "Admin account only" }
        return live.load == .loaded ? "\(live.openSessions.count) sessions" : "Coding agents"
    }

    private var projectsDetail: String {
        guard paired else { return "\(store.projects.count) in Forge" }
        return live.isAdmin && live.load == .loaded ? "\(live.projects.count) in Forge" : "In Forge"
    }

    /// The desktop this phone is paired with. There is no Wake here: the desktop has no route for it,
    /// and a sleeping PC could not hear one.
    private var livePCCard: some View {
        let connection = Connection.shared
        let online = connection.isConnected
        let version = [connection.desktop?.serverName ?? "Kairos", connection.desktop?.serverVersion ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 54, height: 54)
                    .background(Palette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your desktop").font(KFont.ui(18, .semibold, relativeTo: .headline)).foregroundStyle(Palette.ink)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        if online {
                            PulsingDot(color: Palette.success, size: 7)
                        } else {
                            Circle().fill(Palette.inkFaint).frame(width: 7, height: 7)
                        }
                        Text(online ? "Online · \(version)" : connection.statusLine)
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if let counts = live.counts {
                HStack(spacing: 0) {
                    stat("\(counts.running ?? 0)", "working")
                    stat("\(counts.needsYou ?? 0)", "waiting for you", gold: (counts.needsYou ?? 0) > 0)
                    if live.isAdmin, live.load == .loaded {
                        stat("\(live.apps.count)", live.apps.count == 1 ? "app running" : "apps running")
                    }
                }
            }
        }
        .padding(16)
        .kGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder
    private var liveForge: some View {
        if !live.isAdmin || live.load != .loaded {
            DeskForgeGate(load: live.load) { Task { await live.loadHome() } }.arrives(1)
        } else {
            if !live.apps.isEmpty { liveAppsRow.arrives(1) }
            liveSessionsCard.arrives(2)
        }
    }

    /// Apps the desktop is running for Forge sessions. The page itself is on the desktop only, so these do not open.
    private var liveAppsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Running apps").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(live.apps) { app in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 7) {
                                PulsingDot(color: Palette.success, size: 6)
                                Text("localhost:\(String(app.port))").font(CodeFont.mono(13, .semibold)).foregroundStyle(Palette.ink)
                            }
                            Text(live.session(app.sessionID)?.title ?? "Forge app").font(KFont.ui(14)).foregroundStyle(Palette.inkDim).lineLimit(1)
                        }
                        .padding(14)
                        .frame(width: 210, alignment: .leading)
                        .kCard(radius: 20)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            HintLine(text: "Open a running app in Kairos on your desktop.")
        }
    }

    private var liveSessionsCard: some View {
        let sessions = live.openSessions
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Forge sessions").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                Spacer()
                Button {
                    live.composeProjectID = nil
                    store.composeRequested = true
                    open(.forgeHome)
                } label: {
                    Label("New", systemImage: "plus")
                        .font(KFont.ui(15, .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("New Forge session")
            }
            if sessions.isEmpty {
                DeskEmptyNote(symbol: "hammer", title: "Ready to build", text: "No Forge sessions on your desktop yet.", action: "New session") {
                    live.composeProjectID = nil
                    store.composeRequested = true
                    open(.forgeHome)
                }
                .kCard(radius: 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.prefix(4).enumerated()), id: \.element.id) { index, session in
                        Button { open(.session(session.id)) } label: {
                            ForgeSessionRow(session: live.info(session), project: live.project(session.projectID)?.name ?? "",
                                            last: index == min(4, sessions.count) - 1, counts: false)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                        .matchedTransitionSource(id: session.id, in: zoom)
                    }
                    if sessions.count > 4 {
                        Button { open(.forgeHome) } label: {
                            Text("All \(sessions.count) sessions").font(KFont.ui(15, .medium)).foregroundStyle(Palette.goldText).frame(maxWidth: .infinity, minHeight: 48)
                        }
                    }
                }
                .kCard(radius: 22)
            }
        }
    }

    private func open(_ route: DesktopRoute) {
        Haptics.tap()
        nav.open = DesktopOpen(route: route)
    }

    private func zoomID(_ route: DesktopRoute) -> String {
        switch route {
        case .forgeHome: "forge"
        case .localModels: "models"
        case .pcFiles: "files"
        case .forgeProjects: "projects"
        case .session(let id): id
        default: "forge"
        }
    }

    // MARK: PC

    private var pcCard: some View {
        let pc = store.pc
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 54, height: 54)
                    .background(Palette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(pc.name).font(KFont.ui(18, .semibold, relativeTo: .headline)).foregroundStyle(Palette.ink)
                    HStack(spacing: 7) {
                        if pc.online {
                            PulsingDot(color: Palette.success, size: 7)
                        } else {
                            Circle().fill(Palette.inkFaint).frame(width: 7, height: 7)
                        }
                        Text(pc.online ? "Online · \(pc.version)" : "Asleep · seen \(pc.lastSeen)")
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkDim)
                    }
                }
                Spacer(minLength: 0)
            }
            if pc.asleep {
                Button {
                    Haptics.tap()
                    store.wake()
                } label: {
                    HStack(spacing: 8) {
                        if store.waking { ProgressView().tint(Palette.onGold) } else { Image(systemName: "power") }
                        Text(store.waking ? "Waking your PC..." : "Wake your PC")
                    }
                    .font(KFont.ui(16, .semibold))
                    .foregroundStyle(Palette.onGold)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.gold, in: Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(store.waking)
                Text("Sends a wake signal over your network. Wake on LAN must be on for this PC.")
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
            } else {
                HStack(spacing: 0) {
                    stat("\(store.workingCount)", "working")
                    stat("\(store.waitingCount)", "waiting for you", gold: store.waitingCount > 0)
                    stat("\(store.apps.count)", store.apps.count == 1 ? "app running" : "apps running")
                }
            }
        }
        .padding(16)
        .kGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(Motion.snappy, value: pc.asleep)
    }

    private func stat(_ value: String, _ label: String, gold: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(KFont.ui(22, .semibold)).foregroundStyle(gold ? Palette.goldText : Palette.ink).contentTransition(.numericText())
            Text(label).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Running apps

    private var appsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Running apps").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(store.apps) { app in
                        Button { open(.preview(app.sessionID)) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 7) {
                                    PulsingDot(color: Palette.success, size: 6)
                                    Text("localhost:\(String(app.port))").font(CodeFont.mono(13, .semibold)).foregroundStyle(Palette.ink)
                                }
                                Text(app.title).font(KFont.ui(14)).foregroundStyle(Palette.inkDim).lineLimit(1)
                            }
                            .padding(14)
                            .frame(width: 210, alignment: .leading)
                            .kCard(radius: 20)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("App on port \(String(app.port)), \(app.title). Open preview")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    // MARK: Forge sessions

    private var sessionsCard: some View {
        let live = store.liveSessions
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Forge sessions").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                Spacer()
                Button {
                    store.composeRequested = true
                    open(.forgeHome)
                } label: {
                    Label("New", systemImage: "plus")
                        .font(KFont.ui(15, .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("New Forge session")
            }
            if live.isEmpty {
                DeskEmptyNote(symbol: "hammer", title: "Ready to build", text: "No Forge sessions yet.", action: "New session") {
                    store.composeRequested = true
                    open(.forgeHome)
                }
                .kCard(radius: 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(live.prefix(4).enumerated()), id: \.element.id) { index, session in
                        Button { open(.session(session.id)) } label: {
                            ForgeSessionRow(session: session, project: store.project(session.projectID)?.name ?? "", last: index == min(4, live.count) - 1)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                        .matchedTransitionSource(id: session.id, in: zoom)
                    }
                    if live.count > 4 {
                        Button { open(.forgeHome) } label: {
                            Text("All \(live.count) sessions").font(KFont.ui(15, .medium)).foregroundStyle(Palette.goldText).frame(maxWidth: .infinity, minHeight: 48)
                        }
                    }
                }
                .kCard(radius: 22)
            }
        }
    }

    private func areaTile(_ symbol: String, _ title: String, _ detail: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                IconTile(symbol: symbol, size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .kCard(radius: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .matchedTransitionSource(id: id, in: zoom)
        .accessibilityLabel("\(title), \(detail)")
    }
}
