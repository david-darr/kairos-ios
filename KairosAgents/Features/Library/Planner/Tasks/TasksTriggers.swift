import SwiftUI
import UIKit

// MARK: - Triggers list

/// Outside events that start work: the requests waiting for you, then each trigger with its switch.
struct TrigListView: View {
    @Bindable var store: TasksStore
    let onOpen: (TrigRule) -> Void
    let onAdd: () -> Void
    let onApprove: (TrigRequest) -> Void
    let say: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlannerHeading(title: "Triggers", link: "Add a trigger", action: onAdd)
            Text("Outside events, like a GitHub push or a form on your site, can start work. Each one asks you first unless Run straight away is on.")
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            if !store.requests.isEmpty {
                SectionLabel(text: "Waiting for you").padding(.top, 4)
                ForEach(store.requests) { request in
                    requestCard(request)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }

            if store.triggers.isEmpty {
                PlannerEmpty(title: "No triggers yet", hint: "Let GitHub or a form on your site start work for you.",
                             actionTitle: "Add a trigger", action: onAdd)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.triggers.enumerated()), id: \.element.id) { index, trigger in
                        row(trigger, last: index == store.triggers.count - 1)
                    }
                }
                .kCard(radius: 20)
            }
        }
        .animation(Motion.snappy, value: store.requests)
    }

    private func requestCard(_ request: TrigRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TonePill(text: "Waiting for you", tone: .gold)
                Text(request.triggerName)
                    .font(KFont.ui(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(1)
            }
            Text(request.summary)
                .font(KFont.ui(16.5, .medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(request.eventType) · \(TasksDates.relative(request.at))")
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
            HStack(spacing: 10) {
                PlannerPill(title: "Skip", style: .quiet, expand: true) {
                    withAnimation(Motion.snappy) { store.skip(request.id) }
                    say("Skipped")
                }
                PlannerPill(title: "Approve", style: .gold, expand: true) { onApprove(request) }
            }
        }
        .padding(14)
        .kCard(radius: 20, raised: true)
    }

    private func row(_ trigger: TrigRule, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { onOpen(trigger) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(trigger.name)
                            .font(KFont.ui(16, .medium))
                            .foregroundStyle(trigger.enabled ? Palette.ink : Palette.inkDim)
                            .lineLimit(1)
                        TonePill(text: trigger.source.badge, tone: .muted)
                    }
                    Text(store.describe(trigger))
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        TonePill(text: trigger.autoRun ? "Runs straight away" : "Asks first", tone: trigger.autoRun ? .gold : .muted)
                        Text("Last event \(trigger.lastEvent.map(TasksDates.relative) ?? "never")")
                            .font(KFont.ui(12.5, relativeTo: .caption))
                            .foregroundStyle(Palette.inkFaint)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .accessibilityHint("Opens the trigger")

            Toggle("\(trigger.name) on", isOn: Binding(get: { trigger.enabled }, set: { on in
                Haptics.select()
                withAnimation(Motion.snappy) { store.setTriggerEnabled(trigger.id, on) }
                say(on ? "\(trigger.name) is on" : "\(trigger.name) is off. Its address refuses events.")
            }))
            .labelsHidden()
            .tint(Palette.gold)
        }
        .padding(14)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 14) }
        }
    }
}

// MARK: - Approve an outside event

struct TrigApproveSheet: View {
    @Bindable var store: TasksStore
    let request: TrigRequest
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 460) {
            VStack(alignment: .leading, spacing: 16) {
                PlannerSheetTitle(title: "Approve this event?", subtitle: request.triggerName)
                VStack(alignment: .leading, spacing: 6) {
                    Text(request.summary)
                        .font(KFont.ui(17, .medium))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(request.eventType) · \(TasksDates.relative(request.at))")
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                    if let trigger = store.trigger(request.triggerID) {
                        Text(store.describe(trigger))
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .kCard(radius: 18)
                Label("This starts work from an outside event. The whole event goes to the agent as information.", systemImage: "exclamationmark.shield")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .fixedSize(horizontal: false, vertical: true)
                SwipeUpToConfirm(title: "Swipe up to approve", doneTitle: "Approved", symbol: "checkmark") {
                    let next = store.approve(request.id)
                    Task {
                        try? await Task.sleep(for: .seconds(0.7))
                        dismiss()
                        onDone(next)
                    }
                }
                QuietButton(title: "Skip this event") {
                    store.skip(request.id)
                    dismiss()
                    onDone("Skipped")
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - One trigger

struct TrigDetailSheet: View {
    @Bindable var store: TasksStore
    let triggerID: String
    let onDeleted: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var notice: String?
    @State private var events = ""
    @State private var path = ""
    @State private var value = ""
    @State private var cardTitle = ""
    @State private var instructions = ""
    @State private var loaded = false
    @State private var askAutoRun = false
    @State private var confirmSecret = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            if let trigger = store.trigger(triggerID) {
                content(trigger)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .tint(Palette.gold)
        .plannerNotice($notice)
        .onAppear(perform: load)
        .confirmationDialog("Make a new secret?", isPresented: $confirmSecret, titleVisibility: .visible) {
            Button("Make a new secret", role: .destructive) {
                withAnimation(Motion.snappy) { store.newSecret(triggerID) }
                notice = "New secret made"
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current secret stops working straight away. Anything sending events must be updated.")
        }
        .confirmationDialog("Delete this trigger?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete trigger", role: .destructive) {
                let name = store.trigger(triggerID)?.name ?? "Trigger"
                store.deleteTrigger(triggerID)
                dismiss()
                onDeleted("\(name) deleted")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its address stops working. Cards it already made stay on the board.")
        }
        .onChange(of: store.trigger(triggerID) == nil) { _, gone in
            if gone { dismiss() }
        }
    }

    private func load() {
        guard !loaded, let trigger = store.trigger(triggerID) else { return }
        loaded = true
        events = trigger.events
        path = trigger.conditionPath
        value = trigger.conditionValue
        cardTitle = trigger.cardTitle
        instructions = trigger.instructions
    }

    private func content(_ trigger: TrigRule) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PlannerSheetTitle(title: trigger.name, subtitle: store.describe(trigger))

            addressCard(trigger)
            if let secret = trigger.freshSecret {
                secretCard(trigger, secret: secret)
            }

            VStack(spacing: 0) {
                PlannerToggleRow(title: "On", detail: "When off, its address refuses events.",
                                 isOn: Binding(get: { trigger.enabled }, set: { store.setTriggerEnabled(trigger.id, $0) }))
                PlannerToggleRow(title: "Run straight away",
                                 detail: trigger.autoRun ? "Work starts without asking you." : "Each event waits for your OK.",
                                 isOn: Binding(get: { trigger.autoRun || askAutoRun }, set: { on in
                                     if on { askAutoRun = true } else {
                                         askAutoRun = false
                                         store.setAutoRun(trigger.id, false)
                                         notice = "It asks first again"
                                     }
                                 }),
                                 last: true)
            }
            .kCard(radius: 18)

            if askAutoRun && !trigger.autoRun {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Only do this for a source you trust. Anyone with the address and secret can start work, and agents can use their tools.", systemImage: "exclamationmark.triangle")
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    SwipeUpToConfirm(title: "Swipe up to allow", doneTitle: "Runs straight away", symbol: "bolt.fill") {
                        store.setAutoRun(trigger.id, true)
                        askAutoRun = false
                    }
                    QuietButton(title: "Keep asking first") { withAnimation(Motion.snappy) { askAutoRun = false } }
                }
                .padding(14)
                .kCard(radius: 18, raised: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Filters and wording")
                PlannerTextField(label: "Events", placeholder: "push, pull_request", text: $events)
                hint("Comma separated. Leave it empty to accept every event.")
                HStack(spacing: 10) {
                    PlannerTextField(label: "Field", placeholder: "order.type", text: $path)
                    PlannerTextField(label: "Equals", placeholder: "repair", text: $value)
                }
                hint("Only events where this field has this value. Leave the field empty for no condition.")
                if trigger.action == .card {
                    PlannerTextField(label: "Card title", placeholder: "New order from {customer.name}", text: $cardTitle)
                    PlannerTextField(label: "Instructions", placeholder: "What should happen with this event", text: $instructions, multiline: true)
                    hint("Use {field.path} to fill in parts of the event. The whole event is attached as information.")
                }
                PlannerPill(title: "Save", symbol: "checkmark", style: .gold, expand: true) {
                    store.saveTrigger(trigger.id, events: events, path: path, value: value, title: cardTitle, instructions: instructions)
                    Haptics.success()
                    notice = "Saved"
                }
            }

            recentEvents(trigger)

            VStack(spacing: 10) {
                PlannerPill(title: "New secret", symbol: "key", style: .outline, expand: true) { confirmSecret = true }
                PlannerPill(title: "Delete trigger", symbol: "trash", style: .danger, expand: true) { confirmDelete = true }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 30)
        .animation(Motion.snappy, value: askAutoRun)
        .animation(Motion.snappy, value: trigger)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(KFont.ui(13, relativeTo: .footnote))
            .foregroundStyle(Palette.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, -8)
    }

    private func addressCard(_ trigger: TrigRule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Address")
            HStack(spacing: 10) {
                Text(trigger.address)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                PlannerRoundButton(symbol: "doc.on.doc", label: "Copy address", size: 40) {
                    UIPasteboard.general.string = trigger.address
                    notice = "Copied."
                }
            }
            .padding(12)
            .kCard(radius: 16)
        }
    }

    private func secretCard(_ trigger: TrigRule, secret: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Secret, shown once", systemImage: "key.fill")
                .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Palette.goldText)
            HStack(spacing: 10) {
                Text(secret)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                PlannerRoundButton(symbol: "doc.on.doc", label: "Copy secret", size: 40) {
                    UIPasteboard.general.string = secret
                    notice = "Copied."
                }
            }
            Text("Copy it now. It will not be shown again; make a new secret if you lose it.")
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.danger)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: trigger.source == .github ? "Connect GitHub" : "Connect a service")
                ForEach(Array(guide(trigger).enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(KFont.ui(12.5, .semibold, relativeTo: .caption))
                            .foregroundStyle(Palette.onGold)
                            .frame(width: 20, height: 20)
                            .background(Palette.gold, in: Circle())
                        Text(line)
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("Events only reach Kairos while it is reachable from the internet. You can test it on your own network first.")
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            PlannerPill(title: "I copied it", style: .quiet) {
                withAnimation(Motion.snappy) { store.forgetSecret(trigger.id) }
            }
        }
        .padding(14)
        .kCard(radius: 18, raised: true)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.gold.opacity(0.6), lineWidth: 1))
    }

    private func guide(_ trigger: TrigRule) -> [String] {
        if trigger.source == .github {
            return [
                "In your repository, open Settings, then Webhooks, then Add webhook.",
                "Paste the address as the Payload URL and choose application/json as the content type.",
                "Paste the secret, pick the events you want, and save.",
            ]
        }
        return [
            "Send a POST to the address with a JSON body.",
            "Sign the body with the secret (HMAC SHA-256) and put it in the X-Kairos-Signature header.",
            "Add an X-Kairos-Delivery ID if you can, so a repeat is not run twice.",
        ]
    }

    private func recentEvents(_ trigger: TrigRule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Recent events")
            if trigger.recent.isEmpty {
                Text("Nothing received yet.")
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kCard(radius: 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(trigger.recent.enumerated()), id: \.element.id) { index, event in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.name).font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                                Text([TasksDates.relative(event.at), event.detail].compactMap { $0 }.joined(separator: " · "))
                                    .font(KFont.ui(13, relativeTo: .footnote))
                                    .foregroundStyle(Palette.inkFaint)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            TonePill(text: event.label, tone: event.tone)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) {
                            if index < trigger.recent.count - 1 { Palette.line.frame(height: 1).padding(.leading, 14) }
                        }
                    }
                }
                .kCard(radius: 18)
            }
        }
    }
}

// MARK: - Add a trigger

struct TrigAddSheet: View {
    @Bindable var store: TasksStore
    let onAdded: (String) -> Void
    @State private var name = ""
    @State private var source: TrigSource = .github
    @State private var action: TrigAction = .card
    @State private var agent = "kairos"
    @State private var jobID = ""
    @State private var events = ""
    @State private var cardTitle = ""
    @State private var instructions = ""
    @State private var askOn = TasksOptions.askOptions[0]
    @State private var error: String?

    private var runnable: [ScheduledJob] { store.jobs.filter { !$0.builtin } }
    private var actions: [TrigAction] { runnable.isEmpty ? [.card] : TrigAction.allCases }
    private let agents = ["kairos", "scout", "quill", "mason", "atlas", "ledger"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlannerSheetTitle(title: "Add a trigger")
                PlannerTextField(label: "Name", placeholder: "Website order form", text: $name,
                                 error: error == "Give the trigger a name." ? error : nil)
                VStack(spacing: 0) {
                    PlannerMenuRow(title: "Source", symbol: "antenna.radiowaves.left.and.right", options: TrigSource.allCases,
                                   selection: $source, label: \.title)
                    PlannerMenuRow(title: "Action", symbol: "bolt", options: actions, selection: $action, label: \.title)
                    if action == .card {
                        PlannerMenuRow(title: "Agent", symbol: "person.crop.circle", options: agents, selection: $agent,
                                       label: { $0 == "kairos" ? "Kairos, no agent" : SampleData.bot($0).name })
                    } else {
                        PlannerMenuRow(title: "Task", symbol: "calendar.badge.clock", options: runnable.map(\.id), selection: $jobID,
                                       label: { id in
                                           guard let job = store.job(id) else { return "Pick a task" }
                                           return job.agentID.map { "\(job.name) (\(SampleData.bot($0).name))" } ?? job.name
                                       })
                    }
                    PlannerMenuRow(title: "Ask me on", symbol: "bell", options: TasksOptions.askOptions, selection: $askOn,
                                   label: { $0 }, last: true)
                }
                .kCard(radius: 18)

                PlannerTextField(label: "Events", placeholder: "push, pull_request", text: $events)
                Text("Comma separated. Leave it empty to accept every event.")
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.top, -8)
                if action == .card {
                    PlannerTextField(label: "Card title", placeholder: "Check {repository.name}", text: $cardTitle)
                    PlannerTextField(label: "Instructions", placeholder: "What should happen with each event", text: $instructions, multiline: true)
                    Text("Use {field.path} to fill in parts of the event. The whole event is attached as information.")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, -8)
                }

                Label("New triggers ask you before any work starts. You can change that later.", systemImage: "checkmark.shield")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .fixedSize(horizontal: false, vertical: true)

                if let error, error != "Give the trigger a name." {
                    Text(error)
                        .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.danger)
                }

                GoldButton(title: "Add trigger", action: add)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .animation(Motion.snappy, value: action)
        .animation(Motion.snappy, value: error)
        .onAppear { if jobID.isEmpty { jobID = runnable.first?.id ?? "" } }
    }

    private func add() {
        error = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Haptics.thud()
            error = "Give the trigger a name."
            return
        }
        if action == .task && store.job(jobID) == nil {
            Haptics.thud()
            error = "Pick the task this trigger runs."
            return
        }
        Haptics.success()
        let id = store.addTrigger(name: trimmed, source: source, action: action,
                                  agentID: agent == "kairos" ? nil : agent, jobID: jobID,
                                  events: events, title: cardTitle, instructions: instructions, askOn: askOn)
        onAdded(id)
    }
}
