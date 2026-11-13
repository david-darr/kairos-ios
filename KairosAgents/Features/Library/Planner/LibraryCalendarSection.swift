import SwiftUI

/// The Calendar section of Library: Agenda, Day, Week and Month made for a phone.
/// Week is a strip of seven days over the chosen day's timeline, so nothing is squeezed into seven columns.
struct LibraryCalendarSection: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var store = CalStore.shared
    @State private var sheet: CalSheet?

    /// The store has not yet followed the connection: paired but still holding the sample or another account's
    /// items, or unpaired but still holding a desktop's. Nothing of it is drawn; it follows on appear.
    private var following: Bool {
        let wantLive = !Connection.shared.usesSampleData
        return wantLive == store.isSample || (wantLive && store.liveAccount != CalStore.accountKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if following {
                if !Connection.shared.usesSampleData { CalLiveLine(text: "Reading your calendar.") }
            } else {
                content
            }
        }
        .padding(.bottom, 8)
        .animation(Motion.snappy, value: store.mode)
        .sheet(item: $sheet) { current in
            sheetContent(current)
                .environment(router)
                .environment(chrome)
        }
        .onAppear {
            store.followConnection()
            applyDebugState()
        }
        .onChange(of: chrome.addTick) {
            // A save or delete on its way keeps its sheet; nothing swaps it.
            if router.tab == .library && !store.liveSheetBusy { sheet = .new(store.selected) }
        }
        .task(id: store.liveRangeKey) {
            store.followConnection()
            await store.loadLive()
        }
    }

    @ViewBuilder private var content: some View {
        CalModeBar(store: store)
        CalNavRow(store: store, onSources: { sheet = .sources }, onNew: { sheet = .new(store.selected) })
        liveLine

        Group {
            switch store.mode {
            case .week:
                VStack(alignment: .leading, spacing: 12) {
                    CalWeekStrip(store: store)
                    CalLegend(store: store)
                    dayHeading
                    CalTimeline(store: store, day: store.selected, onOpen: open)
                }
            case .day:
                VStack(alignment: .leading, spacing: 12) {
                    dayHeading
                    CalTimeline(store: store, day: store.selected, onOpen: open)
                }
            case .month:
                VStack(alignment: .leading, spacing: 20) {
                    CalMonthGrid(store: store)
                    CalDayPanel(store: store, day: store.selected, actions: actions)
                    VStack(alignment: .leading, spacing: 10) {
                        PlannerHeading(title: "Upcoming")
                        CalGroupedList(store: store, from: store.today, days: 7, actions: actions)
                    }
                }
            case .agenda:
                CalGroupedList(store: store, from: store.selected, days: 14, actions: actions)
            }
        }
        .transition(.opacity)

        VStack(spacing: 0) {
            Button { sheet = .sources } label: {
                GroupRow(title: "Your calendars", symbol: "list.bullet", value: visibleSummary)
            }
            .buttonStyle(PressStyle(scale: 0.99))
            Button { sheet = .archive } label: {
                GroupRow(title: "Archive", symbol: "archivebox", value: "\(store.archived.count)", last: true)
            }
            .buttonStyle(PressStyle(scale: 0.99))
        }
        .kCard(radius: 20)
        .padding(.top, 8)
    }

    // Pieces

    /// Paired: reading, or what failed with Try again. Unpaired, nothing.
    @ViewBuilder private var liveLine: some View {
        if !store.isSample {
            switch store.liveLoad {
            // Idle is the moment between following the connection and the first read starting.
            case .idle where store.events.isEmpty, .loading where store.events.isEmpty:
                CalLiveLine(text: "Reading your calendar.")
            case .failed(let text):
                CalLiveLine(text: text) { Task { await store.loadLive() } }
            default:
                EmptyView()
            }
        }
    }

    private var dayHeading: some View {
        let count = store.items(on: store.selected).count
        return HStack(alignment: .firstTextBaseline) {
            Text(CalDates.longDay(store.selected))
                .font(KFont.ui(18, .semibold, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(store.showsEmpty || count > 0 ? CalDates.countHeading(count) : "")
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .contentTransition(.numericText())
        }
        .padding(.top, 4)
    }

    private var visibleSummary: String {
        let shown = 3 - store.hiddenSources.count + (store.googleConnected ? store.calendars.filter(\.visible).count : 0)
        return "\(shown) on"
    }

    private var actions: CalActions {
        CalActions(
            open: open,
            edit: { sheet = .edit($0, .this) },
            delete: { sheet = .delete($0) },
            complete: complete,
            new: { sheet = .new($0) }
        )
    }

    private func open(_ item: CalOccurrence) {
        Haptics.tap()
        sheet = .detail(item)
    }

    private func complete(_ item: CalOccurrence) {
        guard store.isSample else {
            store.completeLive(item) { chrome.say($0) }
            return
        }
        withAnimation(Motion.snappy) { store.complete(item.event.id) }
        chrome.say("Done. It is in the Archive now.")
    }

    @ViewBuilder
    private func sheetContent(_ current: CalSheet) -> some View {
        switch current {
        case .new(let day):
            CalEventEditor(store: store, newOn: day) { chrome.say($0) }
        case .edit(let item, let scope):
            CalEventEditor(store: store, editing: item, scope: scope,
                           onSaved: { chrome.say($0) },
                           onDelete: { sheet = .delete($0) })
        case .detail(let item):
            CalDetailSheet(
                store: store, item: item,
                onEdit: { sheet = .edit(item, .this) },
                onDelete: { sheet = .delete(item) },
                onComplete: {
                    sheet = nil
                    complete(item)
                },
                onOpenSource: {
                    sheet = nil
                    if item.event.source == .notes {
                        router.open(.notes)
                    } else {
                        router.push(.page(item.event.tabName ?? "Tab"), on: .library)
                    }
                }
            )
        case .delete(let item):
            CalDeleteSheet(store: store, item: item) { chrome.say($0) }
        case .sources:
            CalSourcesSheet(store: store, onArchive: { sheet = .archive }, onOpenGoogle: {
                sheet = nil
                router.librarySection = .files
            })
        case .archive:
            CalArchiveSheet(store: store)
        }
    }

    // Debug pictures

    private func applyDebugState() {
        guard let name = router.debugScreen, name.hasPrefix("calendar-"), !store.debugApplied else { return }
        store.debugApplied = true
        store.selected = store.today
        switch name {
        case "calendar-month": store.mode = .month
        case "calendar-day": store.mode = .day
        case "calendar-agenda": store.mode = .agenda
        case "calendar-early":
            store.mode = .day
            store.showEarly = true
        case "calendar-event":
            store.mode = .week
            sheet = .new(store.today)
        case "calendar-edit":
            store.mode = .week
            if let item = store.nextOccurrence(titled: "Gym") { sheet = .edit(item, .series) }
        case "calendar-detail":
            store.mode = .week
            if let item = store.nextOccurrence(titled: "Bike shop stock check") ?? store.nextOccurrence(titled: "Dentist") {
                sheet = .detail(item)
            }
        case "calendar-delete":
            store.mode = .week
            if let item = store.nextOccurrence(titled: "Gym") { sheet = .delete(item) }
        case "calendar-sources":
            store.mode = .week
            sheet = .sources
        case "calendar-archive":
            store.mode = .week
            sheet = .archive
        default: store.mode = .week
        }
    }
}

/// The sheets Calendar can show. One at a time; changing it swaps the sheet.
enum CalSheet: Identifiable {
    case new(Date)
    case edit(CalOccurrence, CalScope)
    case detail(CalOccurrence)
    case delete(CalOccurrence)
    case sources
    case archive

    var id: String {
        switch self {
        case .new(let day): "new-\(day.timeIntervalSince1970)"
        case .edit(let item, let scope): "edit-\(item.id)-\(scope.rawValue)"
        case .detail(let item): "detail-\(item.id)"
        case .delete(let item): "delete-\(item.id)"
        case .sources: "sources"
        case .archive: "archive"
        }
    }
}
