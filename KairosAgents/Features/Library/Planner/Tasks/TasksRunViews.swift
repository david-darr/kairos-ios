import SwiftUI

// MARK: - Run history

/// The shared run history: first ten runs, "Show all N", rows that open to show the output,
/// the delivery state with Send again, and a Steps timeline.
struct RunHistoryList: View {
    let runs: [RunRecord]
    let onSendAgain: (String) -> Void
    @State var expanded: Set<String> = []
    @State var stepsOpen: Set<String> = []
    @State private var showAll = false
    @State private var sending: Set<String> = []

    var body: some View {
        if runs.isEmpty {
            Text("No runs yet.")
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .kCard(radius: 18)
        } else {
            let shown = showAll ? runs : Array(runs.prefix(10))
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, run in
                    row(run, last: index == shown.count - 1 && runs.count <= 10)
                }
                if runs.count > 10 && !showAll {
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { showAll = true }
                    } label: {
                        Text("Show all \(runs.count)")
                            .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.goldText)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .kCard(radius: 18)
        }
    }

    @ViewBuilder
    private func row(_ run: RunRecord, last: Bool) -> some View {
        let open = expanded.contains(run.id)
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) {
                    if open { expanded.remove(run.id) } else { expanded.insert(run.id) }
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            TonePill(text: run.outcomeLabel, tone: run.tone)
                            Text(run.when.map(TasksDates.relative) ?? "Time unknown")
                                .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                        }
                        Text(metaLine(run))
                            .font(KFont.ui(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .lineLimit(2)
                        if let late = run.lateFrom {
                            Label("Late, it was due at \(TasksDates.time(late))", systemImage: "clock.badge.exclamationmark")
                                .font(KFont.ui(13, relativeTo: .footnote))
                                .foregroundStyle(Palette.goldText)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .padding(.top, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .accessibilityHint(open ? "Hides the output" : "Shows the output")

            if open {
                VStack(alignment: .leading, spacing: 10) {
                    outputText(run)
                    deliveryRow(run)
                    stepsBlock(run)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 14) }
        }
    }

    private func metaLine(_ run: RunRecord) -> String {
        var parts = [TasksDates.duration(run.seconds)]
        if let model = run.model { parts.append(model) }
        if let attempt = run.attempt { parts.append("attempt \(attempt)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func outputText(_ run: RunRecord) -> some View {
        if let error = run.error {
            Text("Error: \(error)")
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
        } else if let output = run.output, !output.isEmpty {
            Text(output)
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text("(no output)")
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkFaint)
        }
    }

    @ViewBuilder
    private func deliveryRow(_ run: RunRecord) -> some View {
        if let line = deliveryLine(run.delivery) {
            VStack(alignment: .leading, spacing: 8) {
                Label(line.text, systemImage: line.symbol)
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(line.tone.color)
                    .fixedSize(horizontal: false, vertical: true)
                if run.delivery.canSendAgain {
                    let pending = sending.contains(run.id)
                    PlannerPill(title: pending ? "Sending..." : "Send again", symbol: "paperplane", style: .outline) {
                        sending.insert(run.id)
                        onSendAgain(run.id)
                    }
                    .disabled(pending)
                    .opacity(pending ? 0.6 : 1)
                }
            }
        }
    }

    private func deliveryLine(_ delivery: RunDelivery) -> (text: String, symbol: String, tone: PlannerTone)? {
        func to(_ name: String?) -> String { name.map { " to \($0)" } ?? "" }
        switch delivery {
        case .none:
            return nil
        case .delivered(let name):
            return (name == nil ? "Delivered" : "Delivered\(to(name))", "checkmark.circle", .success)
        case .delivering(let name):
            return ("Delivering\(to(name))", "paperplane", .working)
        case .retrying(let next, let attempts, let name):
            return ("Not delivered\(to(name)) yet. Next try at \(TasksDates.time(next)), after \(attempts) attempts.", "arrow.clockwise", .gold)
        case .abandoned(let name):
            return ("Delivery\(to(name)) kept failing for a day and was given up.", "exclamationmark.triangle", .danger)
        case .interrupted(let name):
            return ("Kairos closed while sending\(to(name)). It may not have arrived.", "exclamationmark.triangle", .gold)
        case .legacyFailed(let reason):
            return ("Delivery failed: \(reason)", "xmark.circle", .danger)
        }
    }

    @ViewBuilder
    private func stepsBlock(_ run: RunRecord) -> some View {
        if let steps = run.steps {
            let open = stepsOpen.contains(run.id)
            VStack(alignment: .leading, spacing: 8) {
                PlannerPill(title: open ? "Hide steps" : "Steps", symbol: "list.bullet", style: .quiet) {
                    withAnimation(Motion.snappy) {
                        if open { stepsOpen.remove(run.id) } else { stepsOpen.insert(run.id) }
                    }
                }
                if open {
                    if steps.isEmpty {
                        Text("No steps recorded for this run (no tools used, or it ran before timelines existed).")
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        RunStepTimeline(steps: steps)
                    }
                }
            }
        }
    }
}

/// A run's steps as a small timeline.
struct RunStepTimeline: View {
    let steps: [RunStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(step.tool == nil ? Palette.gold : Palette.working)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        if index < steps.count - 1 {
                            Rectangle().fill(Palette.line).frame(width: 1.5).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(step.label).font(KFont.ui(14, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                            if let tool = step.tool {
                                Text(tool).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Palette.ink.opacity(0.08), in: Capsule())
                            }
                        }
                        Text(stepMeta(step))
                            .font(KFont.ui(12.5, relativeTo: .caption))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .padding(12)
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepMeta(_ step: RunStep) -> String {
        var parts = [TasksDates.time(step.time)]
        if let seconds = step.seconds { parts.append(TasksDates.duration(seconds)) }
        if let detail = step.detail { parts.append(detail) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Recorded runs

/// The recorded runs chart: Week, Month or Year, one dot per hour or per day.
struct TasksActivityCard: View {
    @Bindable var store: TasksStore
    @Namespace private var ns

    var body: some View {
        let counts = store.activityCounts()
        let cells = store.activityCells()
        let columns = 24
        let rows = max(1, Int(ceil(Double(cells.count) / Double(columns))))
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runs this \(store.range.rawValue.lowercased())")
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                    Text("\(counts.done + counts.other)")
                        .font(KFont.ui(30, .semibold, relativeTo: .title))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text("\(counts.done) done · \(counts.other) other outcomes")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                        .contentTransition(.numericText())
                }
                Spacer()
                rangeSwitch
            }

            Canvas { context, size in
                let cell = size.width / CGFloat(columns)
                let dot = cell * 0.62
                for (index, value) in cells.enumerated() {
                    let x = CGFloat(index % columns) * cell + (cell - dot) / 2
                    let y = CGFloat(index / columns) * cell + (cell - dot) / 2
                    let rect = CGRect(x: x, y: y, width: dot, height: dot)
                    let color: Color
                    switch value {
                    case .none: color = Palette.ink.opacity(0.09)
                    case .some(true): color = Palette.ink.opacity(0.85)
                    case .some(false): color = Palette.gold
                    }
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
            .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
            .accessibilityLabel("\(counts.done) runs done and \(counts.other) other outcomes this \(store.range.rawValue.lowercased())")

            HStack(spacing: 14) {
                legend(Palette.ink.opacity(0.85), "Done")
                legend(Palette.gold, "Other outcomes")
                Spacer()
                Text(store.range == .week ? "One dot an hour" : "One dot a day")
                    .font(KFont.ui(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkFaint)
            }
            Text("From retained scheduled-task history. Older runs may no longer be stored.")
                .font(KFont.ui(12.5, relativeTo: .caption))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .kCard(radius: 22)
        .animation(Motion.snappy, value: store.range)
    }

    private var rangeSwitch: some View {
        HStack(spacing: 0) {
            ForEach(TasksRange.allCases, id: \.self) { range in
                let on = range == store.range
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { store.range = range }
                } label: {
                    Text(range.rawValue)
                        .font(KFont.ui(13.5, on ? .semibold : .regular, relativeTo: .footnote))
                        .foregroundStyle(on ? Palette.ink : Palette.inkDim)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 36)
                        .background {
                            if on { Capsule().fill(Palette.ink.opacity(0.14)).matchedGeometryEffect(id: "range", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.ink.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run history range")
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkDim)
        }
    }
}
