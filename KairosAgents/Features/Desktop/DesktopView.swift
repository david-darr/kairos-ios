import SwiftUI

/// Your PC from your pocket: its status, running apps, Forge sessions, and every desktop area.
struct DesktopView: View {
    var asleep = false
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var store = ForgeStore.shared
    @State private var nav = DesktopNav.shared
    @Namespace private var zoom

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        @Bindable var nav = nav
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pcCard.arrives(0)
                if !store.apps.isEmpty { appsRow.arrives(1) }
                sessionsCard.arrives(2)
                VStack(alignment: .leading, spacing: 10) {
                    Text("On this PC").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                    LazyVGrid(columns: columns, spacing: 10) {
                        areaTile("hammer", "Forge", "\(store.liveSessions.count) sessions", id: "forge") { open(.forgeHome) }
                        areaTile("cursorarrow.rays", "Computer", "See and steer", id: "computer") { router.push(.area(.computer), on: .desktop) }
                        areaTile("globe", "Browse", "Your PC's browser", id: "browse") { router.push(.area(.browse), on: .desktop) }
                        areaTile("cpu", "Local models", "Run on this PC", id: "models") { open(.localModels) }
                        areaTile("folder", "Files on this PC", "Projects and folders", id: "files") { open(.pcFiles("")) }
                        areaTile("folder.badge.plus", "Projects", "\(store.projects.count) in Forge", id: "projects") { open(.forgeProjects) }
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
        .onAppear {
            if asleep {
                store.pc.asleep = true
                store.pc.online = false
                store.pc.lastSeen = "40 min ago"
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
                EmptyNote(symbol: "hammer", title: "Ready to build", text: "No Forge sessions yet.", action: "New session") {
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
