import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, make, library, desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .make: "Make"
        case .library: "Library"
        case .desktop: "Desktop"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .make: "wand.and.stars"
        case .library: "books.vertical"
        case .desktop: "laptopcomputer"
        }
    }
}

enum SheetRoute: String, Identifiable {
    case search, you
    var id: String { rawValue }
}

/// Where the person is: which tab, what is pushed on it, which sheet is up.
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var visited: Set<AppTab> = [.home]
    var paths: [AppTab: [Route]] = [:]
    var sheet: SheetRoute?
    var librarySection: LibrarySection = .files
    /// Shortcuts the person dragged onto the bar. A shortcut opens the area's one home; it is never a copy.
    var pinned: [JumpArea] = []
    /// Set by the debug screenshots so a screen can open in a given state.
    var debugScreen: String?

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "pinnedAreas") ?? []
        pinned = saved.compactMap(JumpArea.init(rawValue:))
    }

    var barHidden: Bool { !(paths[tab] ?? []).isEmpty }

    func path(_ tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { self.paths[tab] ?? [] },
            set: { self.paths[tab] = $0 }
        )
    }

    func select(_ tab: AppTab) {
        visited.insert(tab)
        self.tab = tab
    }

    func push(_ route: Route, on tab: AppTab? = nil) {
        let target = tab ?? self.tab
        select(target)
        paths[target, default: []].append(route)
    }

    func open(_ conversation: Conversation) {
        switch conversation.kind {
        case .bot(let id): push(.bot(id), on: .home)
        case .model: push(.chat(conversation.id), on: .home)
        }
    }

    /// Open an area in its one home.
    func open(_ area: JumpArea) {
        sheet = nil
        switch area {
        case .vault: showLibrary(.files)
        case .notes: showLibrary(.notes)
        case .calendar: showLibrary(.calendar)
        case .mail: showLibrary(.mail)
        case .tasks: showLibrary(.tasks)
        case .studio, .designs:
            paths[.make] = []
            select(.make)
        case .forge:
            paths[.desktop] = []
            select(.desktop)
        case .computer, .browse:
            paths[.desktop] = []
            push(.area(area), on: .desktop)
        case .toolStore, .addTab:
            push(.area(area))
        }
    }

    private func showLibrary(_ section: LibrarySection) {
        paths[.library] = []
        librarySection = section
        select(.library)
    }

    func pin(_ area: JumpArea) {
        pinned.removeAll { $0 == area }
        pinned.append(area)
        if pinned.count > 1 { pinned.removeFirst(pinned.count - 1) }
        savePins()
    }

    func unpin(_ area: JumpArea) {
        pinned.removeAll { $0 == area }
        savePins()
    }

    private func savePins() {
        UserDefaults.standard.set(pinned.map(\.rawValue), forKey: "pinnedAreas")
    }

    // The gold circle changes with the tab.
    var actionSymbol: String {
        switch tab {
        case .home: "plus"
        case .make: "sparkles"
        case .library: librarySection.addSymbol
        case .desktop: "plus"
        }
    }

    var actionLabel: String {
        switch tab {
        case .home: "New chat"
        case .make: "Make something new"
        case .library: librarySection.addLabel
        case .desktop: "New Forge session"
        }
    }
}

/// The floating chrome: is the bar small, is the Jump to panel open, what is running.
@Observable
final class ChromeState {
    var collapsed = false
    var jumpOpen = false
    /// Goes up each time the gold circle is tapped on Library or Desktop. The screen showing there
    /// watches it and opens its own "new" action (a new event, a new card, a new Forge session).
    var addTick = 0
    var liveWork: LiveWork? = SampleData.liveWork
    var toast: String?
    /// Debug screenshots hold the bar still.
    var held = false
    private var toastTask: Task<Void, Never>?

    func scrolled(from old: CGFloat, to new: CGFloat) {
        guard !jumpOpen, !held else { return }
        if new < 12 {
            if collapsed { collapsed = false }
        } else if new - old > 5 {
            if !collapsed { collapsed = true }
        } else if old - new > 5 {
            if collapsed { collapsed = false }
        }
    }

    func openJump() {
        collapsed = false
        jumpOpen = true
    }

    func closeJump() { jumpOpen = false }

    func say(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled { toast = nil }
        }
    }
}

extension View {
    /// Put this on a tab's scroll view so the bar shrinks as you read down and comes back as you scroll up.
    func shrinksBar(_ chrome: ChromeState) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { old, new in
            chrome.scrolled(from: old, to: new)
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
    }
}
