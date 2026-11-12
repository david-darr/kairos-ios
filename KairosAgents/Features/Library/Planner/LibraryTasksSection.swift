import SwiftUI

/// The Tasks section of Library: search, Build with Kairos, run history, the work board (one column
/// at a time), routines, triggers with their approvals, and the automation library.
struct LibraryTasksSection: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var store = TasksStore.shared
    @State private var sheet: TasksSheet?
    @State private var lead: TasksPart = .activity

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(spacing: 12) {
                searchPill
                if !store.searching { buildRow }
            }
            .arrives(0)

            if store.searching {
                results
            } else {
                ForEach(Array(order.enumerated()), id: \.element) { index, part in
                    partView(part).arrives(index + 1)
                }
            }
        }
        .padding(.bottom, 20)
        .sheet(item: $sheet) { current in
            sheetContent(current)
                .environment(router)
                .environment(chrome)
        }
        .onAppear(perform: applyDebug)
    }

    // MARK: Parts

    private var order: [TasksPart] {
        let all: [TasksPart] = [.activity, .board, .routines, .triggers, .library]
        guard lead != .activity else { return all }
        return [lead] + all.filter { $0 != lead }
    }

    @ViewBuilder
    private func partView(_ part: TasksPart) -> some View {
        switch part {
        case .activity:
            TasksActivityCard(store: store)
        case .board:
            WorkBoardView(store: store, actions: cardActions, onAdd: { sheet = .addCard })
        case .routines:
            JobListView(store: store, onOpen: { sheet = .job($0.id, run: nil, steps: nil) }, onSchedule: { sheet = .schedule })
        case .triggers:
            TrigListView(store: store,
                         onOpen: { sheet = .trigger($0.id) },
                         onAdd: { sheet = .addTrigger },
                         onApprove: { sheet = .approve($0) },
                         say: say)
        case .library:
            JobLibraryView(store: store, routines: store.routines, say: say)
        }
    }

    private var cardActions: WorkCardActions {
        WorkCardActions(open: { sheet = .card($0.id) }, delete: { sheet = .deleteCard($0) }, say: say)
    }

    private func say(_ text: String) {
        guard !text.isEmpty else { return }
        chrome.say(text)
    }

    // MARK: Search

    private var searchPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
            TextField("Search tasks and cards", text: $store.search,
                      prompt: Text("Search tasks and cards").foregroundStyle(Palette.inkFaint))
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .submitLabel(.search)
            if store.searching {
                Button {
                    Haptics.tap()
                    withAnimation(Motion.snappy) { store.search = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, store.searching ? 0 : 16)
        .frame(minHeight: 48)
        .kCard(radius: 24)
        .animation(Motion.snappy, value: store.searching)
    }

    private var buildRow: some View {
        Button {
            Haptics.tap()
            sheet = .brief
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.onGold)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Build with Kairos").font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                    Text("Give recurring work a rhythm. Describe it once.")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
            }
            .padding(12)
            .kCard(radius: 22, raised: true)
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }

    @ViewBuilder
    private var results: some View {
        let cards = store.matchingCards
        let jobs = store.matchingJobs
        let routines = store.matchingRoutines
        if cards.isEmpty && jobs.isEmpty && routines.isEmpty {
            Text("No matches for \"\(store.search.trimmingCharacters(in: .whitespaces))\"")
                .font(KFont.ui(15.5))
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, minHeight: 120)
                .kCard(radius: 20)
        } else {
            VStack(alignment: .leading, spacing: 22) {
                if !cards.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Cards")
                        ForEach(cards) { card in
                            WorkCardView(store: store, card: card, actions: cardActions)
                        }
                    }
                }
                if !jobs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Routines")
                        VStack(spacing: 0) {
                            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                                Button { sheet = .job(job.id, run: nil, steps: nil) } label: {
                                    JobRow(job: job, last: index == jobs.count - 1)
                                }
                                .buttonStyle(PressStyle(scale: 0.99))
                            }
                        }
                        .kCard(radius: 20)
                    }
                }
                if !routines.isEmpty {
                    JobLibraryView(store: store, routines: routines, say: say)
                }
            }
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ current: TasksSheet) -> some View {
        switch current {
        case .card(let id):
            WorkCardSheet(store: store, cardID: id, onDelete: { sheet = .deleteCard($0) })
        case .addCard:
            WorkAddCardSheet(store: store, onAdded: { message in
                sheet = nil
                say(message)
            })
        case .job(let id, let run, let steps):
            JobSheet(store: store, jobID: id, openRun: run, openSteps: steps,
                     onDelete: { sheet = .deleteJob($0) }, say: say)
        case .schedule:
            JobScheduleSheet(store: store, onScheduled: { message in
                sheet = nil
                say(message)
            })
        case .trigger(let id):
            TrigDetailSheet(store: store, triggerID: id, onDeleted: { message in
                sheet = nil
                say(message)
            })
        case .addTrigger:
            TrigAddSheet(store: store, onAdded: { id in sheet = .trigger(id) })
        case .approve(let request):
            TrigApproveSheet(store: store, request: request, onDone: say)
        case .brief:
            TasksBriefSheet(onStart: say)
        case .deleteCard(let card):
            TasksConfirmSheet(title: "Delete this card?",
                              message: "\(card.name) and its results will be removed.",
                              button: "Delete card") {
                withAnimation(Motion.snappy) { store.deleteCard(card.id) }
                say("Card deleted")
            }
        case .deleteJob(let job):
            TasksConfirmSheet(title: "Delete this task?",
                              message: "\(job.name) and its run history will be permanently deleted.",
                              button: "Delete task") {
                withAnimation(Motion.snappy) { store.deleteJob(job.id) }
                say("Task deleted")
            }
        }
    }

    // MARK: Debug pictures

    private func applyDebug() {
        guard let name = router.debugScreen, name.hasPrefix("tasks-"), !store.debugApplied else { return }
        store.debugApplied = true
        switch name {
        case "tasks-board":
            lead = .board
            store.column = .ready
        case "tasks-review":
            lead = .board
            store.column = .review
        case "tasks-card":
            lead = .board
            store.column = .review
            sheet = .card("c-newsletter")
        case "tasks-addcard":
            lead = .board
            sheet = .addCard
        case "tasks-routines":
            lead = .routines
            store.showAllJobs = true
        case "tasks-task":
            lead = .routines
            sheet = .job("j-stock", run: nil, steps: nil)
        case "tasks-history":
            lead = .routines
            sheet = .job("j-morning", run: "r-morning-2", steps: "r-morning-2")
        case "tasks-schedule":
            lead = .routines
            store.draft.name = "Evening wrap-up"
            store.draftError = .prompt
            sheet = .schedule
        case "tasks-triggers":
            lead = .triggers
        case "tasks-trigger":
            lead = .triggers
            store.newSecret("tr-github")
            sheet = .trigger("tr-github")
        case "tasks-addtrigger":
            lead = .triggers
            sheet = .addTrigger
        case "tasks-approve":
            lead = .triggers
            if let request = store.requests.first { sheet = .approve(request) }
        case "tasks-library":
            lead = .library
        case "tasks-brief":
            sheet = .brief
        case "tasks-search":
            store.search = "stock"
        default:
            break
        }
    }
}

enum TasksPart: Hashable {
    case activity, board, routines, triggers, library
}

/// The sheets Tasks can show. One at a time; changing it swaps the sheet.
enum TasksSheet: Identifiable {
    case card(String)
    case addCard
    case job(String, run: String?, steps: String?)
    case schedule
    case trigger(String)
    case addTrigger
    case approve(TrigRequest)
    case brief
    case deleteCard(WorkCard)
    case deleteJob(ScheduledJob)

    var id: String {
        switch self {
        case .card(let id): "card-\(id)"
        case .addCard: "add-card"
        case .job(let id, _, _): "job-\(id)"
        case .schedule: "schedule"
        case .trigger(let id): "trigger-\(id)"
        case .addTrigger: "add-trigger"
        case .approve(let request): "approve-\(request.id)"
        case .brief: "brief"
        case .deleteCard(let card): "delete-card-\(card.id)"
        case .deleteJob(let job): "delete-job-\(job.id)"
        }
    }
}
