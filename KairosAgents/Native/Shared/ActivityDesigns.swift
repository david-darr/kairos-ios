import AppIntents
import SwiftUI

// The Live Activity and Dynamic Island designs, one set of views for every kind.
// The widget extension draws them for real; the app's gallery draws the same views so they can be photographed.

// MARK: - Colours that never change with the look (the island is always black, the card always night)

nonisolated enum IslandInk {
    static let cream = Color(hex: 0xF2E8D8)
    static let dim = Color(hex: 0xF2E8D8, alpha: 0.62)
    static let faint = Color(hex: 0xF2E8D8, alpha: 0.38)
    static let gold = Color(hex: 0xE2B154)
    static let success = Color(hex: 0x8BCB8E)
    static let danger = Color(hex: 0xE8836E)
    static let working = Color(hex: 0x8CB8D9)
    static let card = Color(hex: 0x1F1813)
    static let chip = Color(hex: 0xF2E8D8, alpha: 0.1)
    static let hangUp = Color(hex: 0xC2412C)
}

// MARK: - Buttons that work in both places

/// In the app's gallery, buttons report what they would do instead of running an intent.
nonisolated struct NativePreviewKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (String) -> Void)? = nil
}

extension EnvironmentValues {
    var nativePreview: (@MainActor @Sendable (String) -> Void)? {
        get { self[NativePreviewKey.self] }
        set { self[NativePreviewKey.self] = newValue }
    }
}

enum NativeAction {
    case open(URL, String)
    case stop(String, ActivityKind)
    case retry(String, ActivityKind)
    case mute
    case endCall

    var name: String {
        switch self {
        case .open(_, let label): label
        case .stop: "Stop"
        case .retry: "Retry"
        case .mute: "Mute"
        case .endCall: "End"
        }
    }
}

struct NativeControl<Label: View>: View {
    let action: NativeAction
    @ViewBuilder var label: Label
    @Environment(\.nativePreview) private var preview

    var body: some View {
        if let preview {
            Button { preview(action.name) } label: { label }.buttonStyle(.plain)
        } else {
            switch action {
            case .open(let url, _): Link(destination: url) { label }
            case .stop(let id, let kind): Button(intent: StopWorkIntent(activityID: id, kind: kind)) { label }.buttonStyle(.plain)
            case .retry(let id, let kind): Button(intent: RetryWorkIntent(activityID: id, kind: kind)) { label }.buttonStyle(.plain)
            case .mute: Button(intent: MuteCallIntent()) { label }.buttonStyle(.plain)
            case .endCall: Button(intent: EndCallIntent()) { label }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Small pieces

/// The bot's own face, never redrawn: Kip or the bot's pastel and shape.
struct ActivityFace: View {
    let attributes: KairosActivityAttributes
    var phase: ActivityPhase = .running
    var size: CGFloat
    var stage: Color = .black

    var body: some View {
        Mascot(
            shape: MascotShape(rawValue: attributes.botShape) ?? .round,
            colorHex: attributes.botColor,
            pose: pose,
            size: size,
            stage: stage
        )
        .environment(\.colorScheme, .dark)
    }

    private var pose: MascotPose {
        switch phase {
        case .running: attributes.kind == .call ? .idle : .thinking
        case .waiting: .needs
        case .done: .idle
        case .failed, .stopped: .sleeping
        }
    }
}

/// Coloured dots for the bots helping: the compact pill's trailing side.
struct HelperDots: View {
    let helpers: [ActivityHelper]
    var size: CGFloat = 9
    var vertical = false

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 3))
        layout {
            ForEach(helpers.prefix(3)) { helper in
                Circle().fill(Color(hex: helper.colorHex)).frame(width: size, height: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(helpers.map(\.name).joined(separator: " and ") + " helping")
    }
}

/// A sub-agent chip: a dot, the bot's name and what it is doing.
struct HelperChip: View {
    let helper: ActivityHelper

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: helper.colorHex)).frame(width: 8, height: 8)
            Text("\(helper.name): \(helper.doing)")
                .font(KFont.ui(12.5, .medium, relativeTo: .caption))
                .lineLimit(1)
        }
        .foregroundStyle(IslandInk.cream)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(IslandInk.chip, in: Capsule())
    }
}

/// A ring that fills with progress; spins its gap when the work cannot say how far along it is.
struct ProgressRing: View {
    var progress: Double?
    var color: Color = IslandInk.gold
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress ?? 0.3)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// The stages of staged work: done stages are gold, the running one fills, later ones wait.
struct StageTrack: View {
    let stages: [String]
    let current: Int
    var progress: Double?
    var phase: ActivityPhase = .running
    var showLabels = true

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, name in
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(IslandInk.cream.opacity(0.14))
                            Capsule().fill(fill(index)).frame(width: proxy.size.width * amount(index))
                        }
                    }
                    .frame(height: 5)
                    if showLabels {
                        Text(name)
                            .font(KFont.ui(11, index == current ? .semibold : .regular, relativeTo: .caption2))
                            .foregroundStyle(index <= current ? IslandInk.cream : IslandInk.faint)
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Stage \(min(current + 1, stages.count)) of \(stages.count): \(stages.indices.contains(current) ? stages[current] : "")")
    }

    private func amount(_ index: Int) -> Double {
        if phase == .done || index < current { return 1 }
        if index > current { return 0 }
        return max(0.08, progress ?? 0.5)
    }

    private func fill(_ index: Int) -> Color {
        switch phase {
        case .failed: index == current ? IslandInk.danger : IslandInk.gold
        case .done: IslandInk.success
        default: IslandInk.gold
        }
    }
}

/// A straight progress bar for single-stage work.
struct WorkBar: View {
    var progress: Double
    var color: Color = IslandInk.gold

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(IslandInk.cream.opacity(0.14))
                Capsule().fill(color).frame(width: proxy.size.width * max(0.04, min(1, progress)))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("\(Int(progress * 100)) percent")
    }
}

struct ElapsedText: View {
    let since: Date
    var size: CGFloat = 14

    var body: some View {
        Text(since, style: .timer)
            .font(KFont.ui(size, .medium, relativeTo: .caption).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 56, alignment: .trailing)
    }
}

private struct OpenButton: View {
    let attributes: KairosActivityAttributes
    var height: CGFloat = 40

    var body: some View {
        NativeControl(action: .open(attributes.url, attributes.kind.openLabel)) {
            Text(attributes.kind.openLabel)
                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(Color(hex: 0x1B1612))
                .frame(maxWidth: .infinity, minHeight: height)
                .background(IslandInk.cream, in: Capsule())
        }
    }
}

private struct StopButton: View {
    let attributes: KairosActivityAttributes
    var height: CGFloat = 40

    var body: some View {
        NativeControl(action: .stop(attributes.id, attributes.kind)) {
            Text("Stop")
                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(IslandInk.cream)
                .padding(.horizontal, 20)
                .frame(minHeight: height)
                .overlay(Capsule().strokeBorder(IslandInk.cream.opacity(0.35), lineWidth: 1))
                .contentShape(Capsule())
        }
        .accessibilityLabel("Stop \(attributes.kind.label.lowercased())")
    }
}

private struct RoundCallKey: View {
    let action: NativeAction
    let symbol: String
    let label: String
    var on = false
    var red = false
    var size: CGFloat = 40

    var body: some View {
        NativeControl(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(on ? Color(hex: 0x2B2119) : .white)
                .frame(width: size, height: size)
                .background(red ? IslandInk.hangUp : (on ? IslandInk.cream : Color.white.opacity(0.16)), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - The text block every kind shares

private struct ActivityTexts: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState
    var hidingTitles: Bool
    var titleSize: CGFloat = 17

    private var topLine: String {
        switch state.phase {
        case .waiting: "Waiting for you"
        case .done: "\(attributes.botName) finished"
        case .failed: hidingTitles ? attributes.kind.label : attributes.title
        case .stopped: "\(attributes.botName) stopped"
        case .running: state.step
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(topLine)
                .font(KFont.ui(13, relativeTo: .caption))
                .foregroundStyle(state.phase == .waiting ? IslandInk.gold : IslandInk.dim)
                .lineLimit(1)
            Text(state.headline(for: attributes, hidingTitles: hidingTitles))
                .font(KFont.ui(titleSize, .semibold, relativeTo: .headline))
                .foregroundStyle(IslandInk.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if !state.detail.isEmpty, state.phase != .failed, !hidingTitles || attributes.kind == .reply {
                Text(state.detail)
                    .font(KFont.ui(13, relativeTo: .caption))
                    .foregroundStyle(IslandInk.faint)
                    .lineLimit(1)
            }
        }
    }
}

/// The trailing figure for each kind: dots, a percent, a stage count or a timer.
private struct ActivityFigure: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState
    var compact = false

    var body: some View {
        switch attributes.kind {
        case .reply:
            if state.helpers.isEmpty {
                ElapsedText(since: state.startedAt, size: compact ? 13 : 14).foregroundStyle(IslandInk.gold)
            } else {
                HelperDots(helpers: state.helpers, size: compact ? 8 : 10, vertical: !compact)
            }
        case .call:
            ElapsedText(since: state.startedAt, size: compact ? 13 : 15).foregroundStyle(IslandInk.success)
        case .team:
            Text("\(min(state.stage + 1, attributes.stages.count))/\(attributes.stages.count)")
                .font(KFont.ui(compact ? 13 : 15, .semibold, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(IslandInk.gold)
        case .task, .render, .forge:
            if let progress = state.progress {
                ZStack {
                    ProgressRing(progress: progress, lineWidth: compact ? 2.5 : 3)
                    if !compact {
                        Text("\(Int(progress * 100))")
                            .font(KFont.ui(10.5, .semibold, relativeTo: .caption2).monospacedDigit())
                            .foregroundStyle(IslandInk.cream)
                    }
                }
                .frame(width: compact ? 18 : 30, height: compact ? 18 : 30)
            } else {
                ElapsedText(since: state.startedAt, size: 13).foregroundStyle(IslandInk.gold)
            }
        }
    }
}

// MARK: - Lock Screen

/// The Lock Screen card for every kind and every state.
struct ActivityLockView: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState
    var hidingTitles: Bool = NativeSettings.hidesTitles

    var body: some View {
        Group {
            if state.phase.ended {
                ended
            } else if attributes.kind == .call {
                call
            } else {
                running
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ActivityFace(attributes: attributes, phase: state.phase, size: 52, stage: IslandInk.card)
                ActivityTexts(attributes: attributes, state: state, hidingTitles: hidingTitles)
                Spacer(minLength: 4)
                ActivityFigure(attributes: attributes, state: state)
            }
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if !attributes.stages.isEmpty {
                        StageTrack(stages: attributes.stages, current: state.stage, progress: state.progress, phase: state.phase)
                    } else if let first = state.helpers.first {
                        HStack(spacing: 6) {
                            HelperChip(helper: first)
                            if state.helpers.count > 1 {
                                Text("+\(state.helpers.count - 1)").font(KFont.ui(12.5, .medium)).foregroundStyle(IslandInk.dim)
                            }
                        }
                    } else if let progress = state.progress {
                        WorkBar(progress: progress)
                    } else {
                        Text(attributes.kind.label).font(KFont.ui(12.5)).foregroundStyle(IslandInk.faint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StopButton(attributes: attributes, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(alignment: .bottom) {
            LinearGradient(colors: [IslandInk.gold.opacity(0), IslandInk.gold.opacity(0.16)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var call: some View {
        HStack(spacing: 14) {
            ActivityFace(attributes: attributes, size: 52, stage: IslandInk.card)
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.botName).font(KFont.display(28)).foregroundStyle(IslandInk.cream).lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: state.muted ? "mic.slash.fill" : "waveform")
                        .font(.system(size: 11, weight: .semibold))
                    Text(state.muted ? "Muted" : "Kairos call")
                    Text("·")
                    Text(state.startedAt, style: .timer).monospacedDigit()
                }
                .font(KFont.ui(13, relativeTo: .caption))
                .foregroundStyle(IslandInk.dim)
            }
            Spacer(minLength: 4)
            RoundCallKey(action: .mute, symbol: state.muted ? "mic.slash.fill" : "mic.fill", label: state.muted ? "Unmute" : "Mute", on: state.muted, size: 44)
            RoundCallKey(action: .endCall, symbol: "phone.down.fill", label: "End call", red: true, size: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var ended: some View {
        HStack(spacing: 12) {
            ActivityFace(attributes: attributes, phase: state.phase, size: 38, stage: IslandInk.card)
            Text(state.headline(for: attributes, hidingTitles: hidingTitles))
                .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                .foregroundStyle(IslandInk.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            if state.phase == .failed {
                NativeControl(action: .retry(attributes.id, attributes.kind)) {
                    Text("Retry")
                        .font(KFont.ui(14, .medium, relativeTo: .subheadline))
                        .foregroundStyle(IslandInk.cream)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 34)
                        .background(IslandInk.chip, in: Capsule())
                }
            } else if attributes.kind != .call {
                NativeControl(action: .open(attributes.url, "Open")) {
                    Text("Open")
                        .font(KFont.ui(14, .medium, relativeTo: .subheadline))
                        .foregroundStyle(IslandInk.dim)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 34)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(alignment: .bottom) {
            LinearGradient(colors: [endTint.opacity(0), endTint.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var endTint: Color {
        switch state.phase {
        case .done: Color(hex: 0x3E6B3C)
        case .failed: Color(hex: 0x7A2E22)
        default: Color(hex: 0x4A3524)
        }
    }
}

// MARK: - Dynamic Island

struct IslandCompactLeading: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState

    var body: some View {
        ActivityFace(attributes: attributes, phase: state.phase, size: 24)
            .padding(.leading, 2)
    }
}

struct IslandCompactTrailing: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState

    var body: some View {
        Group {
            switch state.phase {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(IslandInk.success)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(IslandInk.danger)
            case .stopped:
                Image(systemName: "stop.circle.fill").foregroundStyle(IslandInk.dim)
            case .waiting:
                Image(systemName: "hand.raised.fill").foregroundStyle(IslandInk.gold)
            case .running:
                ActivityFigure(attributes: attributes, state: state, compact: true)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .padding(.trailing, 2)
    }
}

/// When two activities share the island, each gets one small circle.
struct IslandMinimal: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState

    var body: some View {
        ZStack {
            if attributes.kind != .call, !state.phase.ended {
                ProgressRing(progress: state.progress ?? stageProgress, color: IslandInk.gold, lineWidth: 2)
            }
            ActivityFace(attributes: attributes, phase: state.phase, size: 17)
        }
        .frame(width: 24, height: 24)
        .accessibilityElement()
        .accessibilityLabel("\(attributes.botName): \(state.step)")
    }

    private var stageProgress: Double? {
        attributes.stages.isEmpty ? nil : Double(state.stage + 1) / Double(attributes.stages.count)
    }
}

/// The expanded island, in its four regions. The extension places each part in its region;
/// the gallery stacks them inside a drawn island.
struct IslandExpandedLeading: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState

    var body: some View {
        ActivityFace(attributes: attributes, phase: state.phase, size: 46)
            .padding(.leading, 4)
            .padding(.top, 2)
    }
}

struct IslandExpandedTrailing: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.phase.ended {
                IslandCompactTrailing(attributes: attributes, state: state)
            } else {
                ActivityFigure(attributes: attributes, state: state)
            }
        }
        .padding(.trailing, 4)
        .padding(.top, 6)
    }
}

struct IslandExpandedCenter: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState
    var hidingTitles: Bool = NativeSettings.hidesTitles

    var body: some View {
        Group {
            if attributes.kind == .call {
                VStack(alignment: .leading, spacing: 0) {
                    Text(attributes.botName).font(KFont.display(24)).foregroundStyle(IslandInk.cream)
                    Text(state.muted ? "Muted" : "Kairos call").font(KFont.ui(12.5)).foregroundStyle(IslandInk.dim)
                }
            } else {
                ActivityTexts(attributes: attributes, state: state, hidingTitles: hidingTitles, titleSize: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct IslandExpandedBottom: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            if attributes.kind == .call {
                HStack(spacing: 14) {
                    Spacer()
                    RoundCallKey(action: .mute, symbol: state.muted ? "mic.slash.fill" : "mic.fill", label: state.muted ? "Unmute" : "Mute", on: state.muted, size: 46)
                    RoundCallKey(action: .endCall, symbol: "phone.down.fill", label: "End call", red: true, size: 46)
                }
            } else if state.phase.ended {
                HStack(spacing: 10) {
                    if state.phase == .failed {
                        NativeControl(action: .retry(attributes.id, attributes.kind)) {
                            Text("Retry")
                                .font(KFont.ui(15, .medium))
                                .foregroundStyle(IslandInk.cream)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(IslandInk.chip, in: Capsule())
                        }
                    }
                    OpenButton(attributes: attributes, height: 38)
                }
            } else {
                if !attributes.stages.isEmpty {
                    StageTrack(stages: attributes.stages, current: state.stage, progress: state.progress, phase: state.phase)
                } else if !state.helpers.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(state.helpers.prefix(2)) { HelperChip(helper: $0) }
                        Spacer(minLength: 0)
                    }
                } else if let progress = state.progress {
                    WorkBar(progress: progress)
                }
                HStack(spacing: 10) {
                    OpenButton(attributes: attributes, height: 38)
                    StopButton(attributes: attributes, height: 38)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}
