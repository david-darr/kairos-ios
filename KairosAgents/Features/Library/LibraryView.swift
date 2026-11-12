import SwiftUI

/// Files (the Vault first), Notes, Calendar, Mail and Tasks behind one glass switch.
struct LibraryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome

    var body: some View {
        @Bindable var router = router
        ScrollView {
            Group {
                switch router.librarySection {
                case .files: LibraryFilesSection()
                case .notes: LibraryNotesSection()
                case .calendar: LibraryCalendarSection()
                case .mail: LibraryMailSection()
                case .tasks: LibraryTasksSection()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .id(router.librarySection)
            .transition(.opacity)
        }
        .scrollIndicators(.hidden)
        .shrinksBar(chrome)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                TabHeader(title: "Library") {
                    GlassIconButton(symbol: "magnifyingglass", label: "Search") { router.sheet = .search }
                }
                GlassSwitch(items: LibrarySection.allCases, selection: $router.librarySection) { $0.rawValue }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
        .kScreen(glowAt: UnitPoint(x: 0.5, y: -0.08))
        .animation(Motion.gentle, value: router.librarySection)
    }
}
