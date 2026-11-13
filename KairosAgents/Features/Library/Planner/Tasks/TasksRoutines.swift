import SwiftUI
import UIKit

// MARK: - Routines list

/// Scheduled tasks as rows. Unlike the desktop's phone list, each row shows its last run and
/// the start of its output, so nothing needs a second tap just to read the result.
struct JobListView: View {
    @Bindable var store: TasksStore
    let onOpen: (ScheduledJob) -> Void
    let onSchedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Routines")
                    .font(KFont.ui(19, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Spacer()
                PlannerRoundButton(symbol: "plus", label: "Schedule a task", size: 40, action: onSchedule)
            }

            if store.isLive && store.jobRunsFailed {
                TasksLiveLine(text: "Some run history could not be read. Open a task to try again.")
            }

            if store.jobs.isEmpty && !store.jobsReady {
                // Paired and not read yet, or the read failed: the line above the list says which.
                EmptyView()
            } else if store.jobs.isEmpty {
                PlannerEmpty(title: "No scheduled tasks",
                             hint: "Turn on a routine from the library below, or schedule your own. Results can go to Discord too.",
                             actionTitle: "Schedule a task", action: onSchedule)
            } else {
                let ordered = store.orderedJobs
                let shown = store.showAllJobs ? ordered : Array(ordered.prefix(3))
                let on = shown.filter(\.enabled)
                let off = shown.filter { !$0.enabled }
                if !on.isEmpty {
                    rows(on)
                }
                if !off.isEmpty {
                    SectionLabel(text: "Turned off").padding(.top, 4)
                    rows(off)
                }
                if ordered.count > 3 {
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { store.showAllJobs.toggle() }
                    } label: {
                        Text(store.showAllJobs ? "Show less" : "See all \(ordered.count)")
                            .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.goldText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    private func rows(_ jobs: [ScheduledJob]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                Button { onOpen(job) } label: {
                    JobRow(job: job, last: index == jobs.count - 1)
                }
                .buttonStyle(PressStyle(scale: 0.99))
                .accessibilityLabel("\(job.name). Open task controls")
            }
        }
        .kCard(radius: 20)
    }
}

struct JobRow: View {
    let job: ScheduledJob
    var last = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: job.builtin ? "sparkles" : "calendar.badge.clock")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(job.enabled ? Palette.goldText : Palette.inkFaint)
                .frame(width: 40, height: 40)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(job.displayName)
                    .font(KFont.ui(16, .medium))
                    .foregroundStyle(job.enabled ? Palette.ink : Palette.inkDim)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if job.runningSince != nil { PulsingDot(color: Palette.working, size: 6) }
                    Text(job.nextLine)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(job.runningSince != nil ? Palette.working : Palette.inkFaint)
                        .lineLimit(1)
                }
                if let run = job.runs.first {
                    HStack(spacing: 6) {
                        Circle().fill(run.tone.color).frame(width: 6, height: 6)
                        Text("Last run: \(run.when.map(TasksDates.relative) ?? "unknown") · \(run.outcomeLabel)")
                            .font(KFont.ui(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkDim)
                            .lineLimit(1)
                    }
                    Text(run.error.map { "Error: \($0)" } ?? run.output ?? "(no output)")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(run.error != nil ? Palette.danger : Palette.inkFaint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
                .padding(.top, 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 66) }
        }
    }
}

// MARK: - One scheduled task

struct JobSheet: View {
    @Bindable var store: TasksStore
    let jobID: String
    var openRun: String? = nil
    var openSteps: String? = nil
    let onDelete: (ScheduledJob) -> Void
    let say: (String) -> Void
    @State private var notice: String?
    @State private var confirmRun = false

    var body: some View {
        ScrollView {
            if let job = store.job(jobID) {
                content(job)
            } else {
                PlannerEmpty(title: "This task is gone", hint: "It was deleted.", pose: .idle)
                    .padding(18)
                    .padding(.top, 30)
            }
        }
        .scrollIndicators(.hidden)
        .kSheet()
        .plannerNotice($notice)
        .task {
            if store.isLive { await store.loadJobRuns(jobID) }
        }
        .confirmationDialog("Run this task now?", isPresented: $confirmRun, titleVisibility: .visible) {
            Button("Run now") {
                Haptics.thud()
                store.runJobLive(jobID) { result in notice = result }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(store.job(jobID)?.name ?? "This task") runs on your desktop now and can use its model and tools.")
        }
    }

    private func content(_ job: ScheduledJob) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PlannerSheetTitle(title: job.displayName, subtitle: job.scheduleSummary)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Prompt to run")
                Text(job.prompt)
                    .font(KFont.ui(15.5))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kCard(radius: 18)
            }

            if let since = job.runningSince {
                HStack(spacing: 10) {
                    PulsingDot(color: Palette.working)
                    Text("Running now, started \(TasksDates.time(since))")
                        .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.working)
                    Spacer()
                    PlannerPill(title: "Stop", symbol: "stop.fill", style: .danger) {
                        if store.isLive {
                            store.stopLive(job.id) { notice = $0 }
                            return
                        }
                        if let text = store.stopJob(job.id) { notice = text }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .kCard(radius: 18)
                .transition(.opacity)
            }

            HStack(spacing: 10) {
                let starting = store.starting.contains(job.id)
                PlannerPill(title: starting && job.runningSince == nil ? "Starting..." : (job.runningSince == nil ? "Run now" : "Running..."),
                            symbol: "play.fill", style: .gold, expand: true) {
                    if store.isLive {
                        // Real work on the desktop: ask first.
                        confirmRun = true
                        return
                    }
                    Haptics.thud()
                    store.runJob(job.id) { result in notice = result }
                }
                // Paired, it also waits while another change for this task is on its way.
                .disabled(job.runningSince != nil || starting || (store.isLive && store.busy.contains(job.id)))
                .opacity(job.runningSince != nil || starting || (store.isLive && store.busy.contains(job.id)) ? 0.6 : 1)
                PlannerPill(title: job.enabled ? "Turn off" : "Turn on", symbol: job.enabled ? "pause" : "power", style: .quiet, expand: true) {
                    if store.isLive {
                        store.toggleJobLive(job.id) { notice = $0 }
                        return
                    }
                    if let text = store.toggleJob(job.id) {
                        notice = text
                    } else {
                        notice = "This one-time schedule has ended. Use Run now or schedule a new task."
                    }
                }
                .opacity(!job.enabled && job.ended ? 0.55 : 1)
                .disabled(store.busy.contains(job.id))
            }
            if !job.enabled && job.ended {
                Text("This one-time schedule has ended. Use Run now or schedule a new task.")
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
            }

            if store.isLive {
                VStack(spacing: 0) {
                    let model = job.endpointID ?? ""
                    let channel = job.channelID ?? ""
                    if job.agentID != nil {
                        // A bot's task runs on its bot's model (core/task_scheduler.py), so there is nothing to choose here.
                        HStack(spacing: 12) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Palette.goldText)
                                .frame(width: 26)
                            Text("Model").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                            Spacer(minLength: 8)
                            Text("Its bot's model")
                                .font(KFont.ui(15))
                                .foregroundStyle(Palette.inkDim)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 54) }
                        .accessibilityElement(children: .combine)
                    } else {
                        PlannerMenuRow(title: "Model", symbol: "sparkle",
                                       options: store.modelIDs.contains(model) ? store.modelIDs : store.modelIDs + [model],
                                       selection: Binding(get: { model }, set: { id in store.setJobModelLive(job.id, id) { notice = $0 } }),
                                       label: { store.modelLabel($0) })
                    }
                    PlannerMenuRow(title: "Deliver to", symbol: "paperplane", options: store.channelIDs(keeping: channel),
                                   selection: Binding(get: { channel }, set: { id in store.setJobDeliveryLive(job.id, id) { notice = $0 } }),
                                   label: { store.channelLabel($0) }, last: true)
                }
                .kCard(radius: 18)
                .disabled(store.busy.contains(job.id))
            } else {
                VStack(spacing: 0) {
                    PlannerMenuRow(title: "Model", symbol: "sparkle", options: TasksOptions.models,
                                   selection: Binding(get: { job.model }, set: { store.setJobModel(job.id, $0) }), label: { $0 })
                    PlannerMenuRow(title: "Deliver to", symbol: "paperplane",
                                   options: TasksOptions.channelOptions(keeping: job.deliver),
                                   selection: Binding(get: { job.deliver }, set: { store.setJobDelivery(job.id, $0) }),
                                   label: TasksOptions.channelLabel, last: true)
                }
                .kCard(radius: 18)
            }

            lastRun(job)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Run history (\(job.runs.count))")
                if store.isLive {
                    RunHistoryList(runs: job.runs, onSendAgain: { store.sendAgainLive(run: $0) },
                                   loadSteps: { try await store.loadSteps($0) })
                } else {
                    RunHistoryList(runs: job.runs, onSendAgain: { store.sendAgain(run: $0) },
                                   expanded: Set([openRun].compactMap { $0 }),
                                   stepsOpen: Set([openSteps].compactMap { $0 }))
                }
            }

            VStack(spacing: 10) {
                if store.isLive {
                    TasksNotLiveNote(text: "Sharing is not connected to your desktop yet. Share it from Kairos on your desktop.")
                }
                if job.plain && !store.isLive {
                    PlannerPill(title: "Share with this Kairos", symbol: "person.2", style: .outline, expand: true) {
                        notice = "Shared with everyone on this Kairos."
                    }
                    Text("Everyone signed in here can see this automation and add a copy. Nothing private goes with it.")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !job.builtin && !store.isLive {
                    PlannerPill(title: "Share to the Tool Store", symbol: "bag", style: .outline, expand: true) {
                        notice = "\(job.name) is ready to share in the Tool Store."
                    }
                }
                PlannerPill(title: "Delete task", symbol: "trash", style: .danger, expand: true) { onDelete(job) }
                    .disabled(store.busy.contains(job.id))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 30)
        .animation(Motion.snappy, value: job)
    }

    @ViewBuilder
    private func lastRun(_ job: ScheduledJob) -> some View {
        if let run = job.runs.first {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Last run")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last run: \(run.when.map(TasksDates.relative) ?? "unknown") · \(run.outcomeLabel) · \(TasksDates.duration(run.seconds))")
                        .font(KFont.ui(14, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                    if let error = run.error {
                        Text("Error: \(error)")
                            .font(KFont.ui(15, relativeTo: .subheadline))
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(run.output ?? "(no output)")
                            .font(KFont.ui(15, relativeTo: .subheadline))
                            .foregroundStyle(run.output == nil ? Palette.inkFaint : Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if let line = deliveryNotice(run.delivery) {
                        Text(line)
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.goldText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .kCard(radius: 18)
            }
        }
    }

    private func deliveryNotice(_ delivery: RunDelivery) -> String? {
        switch delivery {
        case .retrying(_, let attempts, let to):
            return "Delivery to \(to ?? "the channel") has not gone through after \(attempts) attempts. Check Settings > Channels."
        case .abandoned(let to), .interrupted(let to):
            return "Delivery to \(to ?? "the channel") did not finish. Check Settings > Channels."
        case .legacyFailed(let reason):
            return "Delivery failed (\(reason)). Check Settings > Channels."
        default:
            return nil
        }
    }
}

// MARK: - Schedule a task

struct JobScheduleSheet: View {
    @Bindable var store: TasksStore
    let onScheduled: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sending = false
    @State private var refusal: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlannerSheetTitle(title: "Schedule a task")
                PlannerTextField(label: "Name", placeholder: "Morning summary", text: $store.draft.name,
                                 error: store.draftError == .name ? "Give the task a name." : nil)
                PlannerTextField(label: "Prompt to run", placeholder: "Say what the task should do each time",
                                 text: $store.draft.prompt, multiline: true,
                                 error: store.draftError == .prompt ? "Say what the task should do." : nil)

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Schedule")
                    VStack(spacing: 0) {
                        PlannerMenuRow(title: "Repeats", symbol: "repeat", options: JobScheduleKind.allCases,
                                       selection: $store.draft.kind, label: \.title)
                        whenRow
                    }
                    .kCard(radius: 18)
                    .overlay {
                        if let field = store.draftError, field == .runAt || field == .time || field == .minutes {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.danger, lineWidth: 1.5)
                        }
                    }
                }

                VStack(spacing: 0) {
                    if store.isLive {
                        PlannerMenuRow(title: "Model", symbol: "sparkle", options: store.modelIDs,
                                       selection: $store.draft.endpointID, label: { store.modelLabel($0) })
                        PlannerMenuRow(title: "Deliver to", symbol: "paperplane", options: store.channelIDs(),
                                       selection: $store.draft.channelID, label: { store.channelLabel($0) }, last: true)
                    } else {
                        PlannerMenuRow(title: "Model", symbol: "sparkle", options: TasksOptions.models,
                                       selection: $store.draft.model, label: { $0 })
                        PlannerMenuRow(title: "Deliver to", symbol: "paperplane", options: TasksOptions.channels,
                                       selection: $store.draft.deliver, label: TasksOptions.channelLabel, last: true)
                    }
                }
                .kCard(radius: 18)

                if let error = store.draftError {
                    Label(error.message, systemImage: "exclamationmark.circle")
                        .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                        .accessibilityAddTraits(.isStaticText)
                }

                if let refusal {
                    Label(refusal, systemImage: "exclamationmark.circle")
                        .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if sending {
                    TasksLiveLine(text: store.scheduleCheck == nil ? "Scheduling it on your desktop." : "Looking for it on your desktop.")
                } else if store.isLive, let check = store.scheduleCheck, !check.text.isEmpty {
                    // Its answer was lost: Schedule waits until a read shows whether it landed.
                    TasksLiveLine(text: check.text, retry: scheduleLive)
                }

                GoldButton(title: "Schedule") {
                    if store.isLive {
                        scheduleLive()
                        return
                    }
                    if let field = store.schedule() {
                        Haptics.thud()
                        withAnimation(Motion.snappy) { store.draftError = field }
                    } else {
                        Haptics.success()
                        onScheduled("Scheduled")
                        dismiss()
                    }
                }
                .padding(.top, 4)
                .disabled(sending || (store.isLive && store.scheduleCheck != nil))
                Text("Your form is kept if you close this before scheduling.")
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .tint(Palette.gold)
        .animation(Motion.snappy, value: store.draft.kind)
        .animation(Motion.snappy, value: store.draftError)
        .onChange(of: store.draft) { old, new in
            guard let error = store.draftError else { return }
            let cleared: Bool
            switch error {
            case .name: cleared = old.name != new.name
            case .prompt: cleared = old.prompt != new.prompt
            case .runAt: cleared = old.runAt != new.runAt || old.kind != new.kind
            case .time: cleared = old.dailyTime != new.dailyTime || old.kind != new.kind
            case .minutes: cleared = old.minutes != new.minutes || old.kind != new.kind
            }
            if cleared { withAnimation(Motion.snappy) { store.draftError = nil } }
        }
        .onDisappear { store.leaveDraft() }
    }

    private func scheduleLive() {
        guard !sending else { return }
        refusal = nil
        sending = true
        Task {
            let result = await store.scheduleLive()
            sending = false
            if let field = result.field {
                Haptics.thud()
                withAnimation(Motion.snappy) { store.draftError = field }
                return
            }
            switch result.outcome {
            case .done?:
                Haptics.success()
                onScheduled("Scheduled")
                dismiss()
            case .refused(let problem)?:
                Haptics.thud()
                withAnimation(Motion.snappy) { refusal = problem }
            case .unsure(_)?:
                // The line above the button says it and offers Try again, which looks for it.
                Haptics.thud()
            case nil:
                break
            }
        }
    }

    @ViewBuilder
    private var whenRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 26)
            switch store.draft.kind {
            case .once:
                Text("Run at").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                DatePicker("Run at", selection: $store.draft.runAt, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            case .daily:
                Text("At (time)").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                DatePicker("At (time)", selection: $store.draft.dailyTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            case .interval:
                Text("Every (min)").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                TextField("Every (min)", text: $store.draft.minutes, prompt: Text("30").foregroundStyle(Palette.inkFaint))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(KFont.ui(16, .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 90)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .transition(.opacity)
    }
}

// MARK: - Automation library

struct JobLibraryView: View {
    @Bindable var store: TasksStore
    let routines: [JobRoutine]
    let say: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Automation library")
                    .font(KFont.ui(19, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                Text("Useful routines, ready to make your own.")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
            }
            let ordered = routines.filter(\.enabled) + routines.filter { !$0.enabled }
            ForEach(ordered) { routine in
                card(routine)
            }
        }
    }

    private func card(_ routine: JobRoutine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.label).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                    Text(routine.about)
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if routine.enabled { TonePill(text: "On", tone: .success, symbol: "checkmark") }
            }
            HStack(spacing: 6) {
                TonePill(text: routine.usesModel ? "Uses model" : "No model call", tone: routine.usesModel ? .gold : .muted)
                TonePill(text: routine.cadence, tone: .muted, symbol: "clock")
            }
            Group {
                if store.isLive {
                    PlannerMenuRow(title: "Deliver to", symbol: "paperplane", options: store.channelIDs(keeping: routine.channelID),
                                   selection: Binding(get: { routine.channelID }, set: { store.setRoutineChannel(routine.id, $0) }),
                                   label: { store.channelLabel($0) }, last: true)
                } else {
                    PlannerMenuRow(title: "Deliver to", symbol: "paperplane", options: TasksOptions.channels,
                                   selection: Binding(get: { routine.deliver }, set: { store.setRoutineDelivery(routine.id, $0) }),
                                   label: TasksOptions.channelLabel, last: true)
                }
            }
                .disabled(routine.enabled)
                .opacity(routine.enabled ? 0.55 : 1)
                .background(Palette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack {
                Spacer()
                if routine.enabled {
                    PlannerPill(title: "Disable", style: .danger) {
                        if store.isLive {
                            store.disableRoutineLive(routine.id, say: say)
                            return
                        }
                        withAnimation(Motion.snappy) { say(store.disableRoutine(routine.id)) }
                    }
                } else {
                    PlannerPill(title: "Enable", style: .gold) {
                        Haptics.success()
                        if store.isLive {
                            store.enableRoutineLive(routine.id, say: say)
                            return
                        }
                        withAnimation(Motion.snappy) { say(store.enableRoutine(routine.id)) }
                    }
                }
            }
            .disabled(store.busy.contains(routine.id))
        }
        .padding(14)
        .kCard(radius: 20)
    }
}
