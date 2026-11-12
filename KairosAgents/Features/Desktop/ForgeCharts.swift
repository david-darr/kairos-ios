import SwiftUI

/// Day labels for the last `count` days, oldest first.
enum ForgeDays {
    static func label(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Commits by day. Touch and slide along it to read each day.
struct ActivityBars: View {
    let commits: [Int]
    let added: [Int]
    let removed: [Int]
    @Binding var selected: Int?
    var height: CGFloat = 120

    var body: some View {
        let peak = max(1, commits.max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            callout
            GeometryReader { geometry in
                let step = geometry.size.width / CGFloat(max(1, commits.count))
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(commits.indices, id: \.self) { index in
                        let on = selected == index
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(on ? Palette.gold : (commits[index] == 0 ? Palette.ink.opacity(0.1) : Palette.gold.opacity(0.55)))
                            .frame(width: max(4, step - 6), height: max(4, geometry.size.height * CGFloat(commits[index]) / CGFloat(peak)))
                            .frame(width: step)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let index = min(commits.count - 1, max(0, Int(value.location.x / step)))
                            if index != selected {
                                Haptics.select()
                                selected = index
                            }
                        }
                )
            }
            .frame(height: height)
            HStack {
                Text(ForgeDays.label(daysAgo: commits.count - 1))
                Spacer()
                Text("Today")
            }
            .font(KFont.ui(12, relativeTo: .caption))
            .foregroundStyle(Palette.inkFaint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Commits by day, \(commits.reduce(0, +)) commits over \(commits.count) days")
        .accessibilityAdjustableAction { direction in
            let current = selected ?? commits.count - 1
            switch direction {
            case .increment: selected = min(commits.count - 1, current + 1)
            case .decrement: selected = max(0, current - 1)
            @unknown default: break
            }
        }
        .accessibilityValue(selectedText)
    }

    private var selectedText: String {
        guard let index = selected, commits.indices.contains(index) else { return "Touch a bar to read its day" }
        let ago = commits.count - 1 - index
        let day = ago == 0 ? "Today" : ForgeDays.label(daysAgo: ago)
        let count = commits[index]
        return "\(day): \(count) \(count == 1 ? "commit" : "commits")"
    }

    private var callout: some View {
        HStack(spacing: 8) {
            Text(selectedText)
                .font(KFont.ui(14, .medium, relativeTo: .footnote))
                .foregroundStyle(selected == nil ? Palette.inkFaint : Palette.ink)
                .contentTransition(.numericText())
            if let index = selected, added.indices.contains(index), removed.indices.contains(index) {
                DiffCount(added: added[index], removed: removed[index], size: 13)
            }
            Spacer(minLength: 0)
            if selected != nil {
                Button {
                    selected = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear the selected day")
            }
        }
        .frame(minHeight: 32)
    }
}

/// Simple bars for commits over time (repo lifespan).
struct HistoryBars: View {
    let values: [Int]
    @Binding var selected: Int?

    var body: some View {
        let peak = max(1, values.max() ?? 1)
        GeometryReader { geometry in
            let step = geometry.size.width / CGFloat(max(1, values.count))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(values.indices, id: \.self) { index in
                    Capsule()
                        .fill(selected == index ? Palette.gold : Palette.working.opacity(0.7))
                        .frame(width: max(4, step - 5), height: max(4, geometry.size.height * CGFloat(values[index]) / CGFloat(peak)))
                        .frame(width: step)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let index = min(values.count - 1, max(0, Int(value.location.x / step)))
                    if index != selected { Haptics.select(); selected = index }
                }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Commits over time, \(values.reduce(0, +)) in total")
    }
}

/// A donut of languages with a legend you can tap.
struct LanguageDonut: View {
    let languages: [LanguageShare]
    @State private var selected: String?

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ForEach(Array(languages.enumerated()), id: \.element.id) { index, language in
                    let start = languages.prefix(index).reduce(0) { $0 + $1.percent } / 100
                    let end = start + language.percent / 100
                    Circle()
                        .trim(from: start + 0.004, to: max(start + 0.005, end - 0.004))
                        .stroke(Color(hex: language.colorHex), style: StrokeStyle(lineWidth: selected == language.name ? 22 : 16, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .opacity(selected == nil || selected == language.name ? 1 : 0.35)
                }
                VStack(spacing: 0) {
                    Text(selectedShare.map { String(format: "%.1f%%", $0.percent) } ?? "\(languages.count)")
                        .font(KFont.ui(18, .semibold))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text(selectedShare?.name ?? "languages")
                        .font(KFont.ui(11.5, relativeTo: .caption2))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
                .frame(width: 70)
            }
            .frame(width: 118, height: 118)
            .animation(Motion.snappy, value: selected)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(languages) { language in
                    Button {
                        Haptics.select()
                        selected = selected == language.name ? nil : language.name
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: language.colorHex)).frame(width: 10, height: 10)
                            Text(language.name).font(KFont.ui(14.5, selected == language.name ? .semibold : .regular)).foregroundStyle(Palette.ink)
                            Spacer(minLength: 4)
                            Text(String(format: "%.1f%%", language.percent)).font(KFont.ui(13.5)).foregroundStyle(Palette.inkFaint).monospacedDigit()
                        }
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    private var selectedShare: LanguageShare? { languages.first { $0.name == selected } }
}

/// Weekday by hour heatmap. Tap a cell to read it.
struct RhythmHeatmap: View {
    let rhythm: [[Int]]
    @State private var selected: (day: Int, hour: Int)?
    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let peak = max(1, rhythm.flatMap { $0 }.max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            Text(readout)
                .font(KFont.ui(14, .medium, relativeTo: .footnote))
                .foregroundStyle(selected == nil ? Palette.inkFaint : Palette.ink)
                .frame(minHeight: 22)
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 2) {
                    ForEach(days, id: \.self) { day in
                        Text(day).font(KFont.ui(10.5, relativeTo: .caption2)).foregroundStyle(Palette.inkFaint).frame(height: 14)
                    }
                }
                GeometryReader { geometry in
                    let cell = (geometry.size.width - 23 * 2) / 24
                    VStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { day in
                            HStack(spacing: 2) {
                                ForEach(0..<24, id: \.self) { hour in
                                    let value = rhythm[day][hour]
                                    let on = selected?.day == day && selected?.hour == hour
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(Palette.gold.opacity(0.1 + 0.9 * Double(value) / Double(peak)))
                                        .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(on ? Palette.ink : .clear, lineWidth: 1.5))
                                        .frame(width: cell, height: 14)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { value in
                            let hour = min(23, max(0, Int(value.location.x / (cell + 2))))
                            let day = min(6, max(0, Int(value.location.y / 16)))
                            if selected?.day != day || selected?.hour != hour {
                                Haptics.select()
                                selected = (day, hour)
                            }
                        }
                    )
                }
                .frame(height: 7 * 16)
            }
            HStack(spacing: 6) {
                Text("Less")
                ForEach(0..<5, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2.5).fill(Palette.gold.opacity(0.1 + 0.225 * Double(step))).frame(width: 12, height: 12)
                }
                Text("More")
                Spacer()
                Text("Peak \(peak) an hour")
            }
            .font(KFont.ui(12, relativeTo: .caption))
            .foregroundStyle(Palette.inkFaint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Commit rhythm by weekday and hour, \(rhythm.flatMap { $0 }.reduce(0, +)) commits. Busiest hour has \(peak).")
    }

    private var readout: String {
        guard let selected else { return "Tap a square to read it" }
        let count = rhythm[selected.day][selected.hour]
        return "\(days[selected.day]), \(String(format: "%02d:00", selected.hour)): \(count) \(count == 1 ? "commit" : "commits")"
    }
}

/// A stat with its change against the previous 30 days.
struct StatTile: View {
    let title: String
    let value: String
    var delta: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            Text(value).font(KFont.ui(22, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink).monospacedDigit()
            if let delta {
                Text(delta >= 0 ? "+\(delta.formatted()) vs last 30 days" : "\(delta.formatted()) vs last 30 days")
                    .font(KFont.ui(12, relativeTo: .caption))
                    .foregroundStyle(delta >= 0 ? Palette.success : Palette.danger)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(radius: 18)
        .accessibilityElement(children: .combine)
    }
}

/// Name, commits, lines added and removed.
struct RankedTable: View {
    let rows: [RankedRow]
    var mono = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Commits").frame(width: 62, alignment: .trailing)
                Text("Lines").frame(width: 92, alignment: .trailing)
            }
            .font(KFont.label)
            .foregroundStyle(Palette.inkFaint)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            ForEach(rows) { row in
                HStack {
                    Text(row.name)
                        .font(mono ? CodeFont.mono(12.5) : KFont.ui(14.5))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(row.commits)").font(KFont.ui(14)).foregroundStyle(Palette.inkDim).frame(width: 62, alignment: .trailing)
                    DiffCount(added: row.added, removed: row.removed, size: 12).frame(width: 92, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .overlay(alignment: .top) { Palette.line.frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
        .kCard(radius: 18)
    }
}
