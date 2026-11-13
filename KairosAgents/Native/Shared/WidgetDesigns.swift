import SwiftUI
import WidgetKit

// The widget designs. The extension draws them on the Home Screen and the Lock Screen;
// the app's gallery draws the same views so they can be photographed. They follow the look:
// night brown with cream ink, or parchment with bistre.

// MARK: - State and motion

// One state language for every widget, Live Activity and island view: the bot's face changes expression,
// a soft wash behind it takes the state's colour, a small mark names the state, and step lines move on.
// WidgetKit animates these when a timeline entry or a Live Activity update changes them (two seconds at most);
// nothing here loops. With Reduce Motion on, every change is a cross-fade.

/// What a bot is doing, as every native surface shows it.
nonisolated enum BotMood: String, CaseIterable, Hashable, Sendable {
    case working, needsYou, done, failed, idle, offline

    init(_ phase: ActivityPhase, stale: Bool = false) {
        if stale, !phase.ended { self = .offline; return }
        switch phase {
        case .running: self = .working
        case .waiting: self = .needsYou
        case .done: self = .done
        case .failed: self = .failed
        case .stopped: self = .idle
        }
    }

    var symbol: String {
        switch self {
        case .working: "bolt.fill"
        case .needsYou: "hand.raised.fill"
        case .done: "checkmark"
        case .failed: "exclamationmark"
        case .idle: "moon.zzz.fill"
        case .offline: "link"
        }
    }

    var label: String {
        switch self {
        case .working: "Working"
        case .needsYou: "Needs you"
        case .done: "Done"
        case .failed: "Couldn't finish"
        case .idle: "Idle"
        case .offline: "Not connected"
        }
    }
}

enum MoodStyle {
    static func pose(_ mood: BotMood) -> MascotPose {
        switch mood {
        case .working: .thinking
        case .needsYou: .needs
        case .done, .idle: .idle
        case .failed, .offline: .sleeping
        }
    }

    /// The wash and mark colour. The island and the Lock Screen card are always night, so they use `IslandInk`.
    static func tint(_ mood: BotMood, island: Bool = false) -> Color {
        switch mood {
        case .working: island ? IslandInk.working : Palette.working
        case .needsYou: island ? IslandInk.gold : Palette.gold
        case .done: island ? IslandInk.success : Palette.success
        case .failed: island ? IslandInk.danger : Palette.danger
        case .idle, .offline: island ? IslandInk.faint : Palette.inkFaint
        }
    }

    /// Settles well inside the two seconds WidgetKit allows.
    static func animation(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.35) : .spring(response: 0.55, dampingFraction: 0.82)
    }

    /// A face changing expression.
    static func swap(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity)
    }

    /// A line arriving from below and leaving upward.
    static func tick(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity))
    }
}

/// The hero: the bot's own face (never redrawn) over a soft wash in the state's colour, with a small mark.
struct MoodFace: View {
    var color: UInt32?
    var shape: String = "round"
    var mood: BotMood
    var size: CGFloat
    var stage: Color = Palette.ground
    /// Night colours, for the Lock Screen card and the island.
    var island = false
    var showsMark = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Mascot(shape: MascotShape(rawValue: shape) ?? .round, colorHex: color, pose: MoodStyle.pose(mood), size: size, stage: stage)
                .id(mood)
                .transition(MoodStyle.swap(reduceMotion))
        }
        .frame(width: size, height: size)
        .background {
            Circle()
                .fill(MoodStyle.tint(mood, island: island).opacity(mood == .idle || mood == .offline ? 0.18 : (island ? 0.42 : 0.3)))
                .frame(width: size * 1.2, height: size * 1.2)
                .blur(radius: size * 0.2)
        }
        .overlay(alignment: .bottomTrailing) {
            if showsMark, mood != .idle {
                MoodMark(mood: mood, size: max(11, size * 0.34), island: island)
                    .offset(x: size * 0.06, y: size * 0.02)
                    .transition(.opacity)
            }
        }
        .animation(MoodStyle.animation(reduceMotion), value: mood)
        .accessibilityHidden(true)
    }
}

/// The state's small round mark. The symbol swaps with the system's replace effect.
struct MoodMark: View {
    let mood: BotMood
    var size: CGFloat = 16
    var island = false

    var body: some View {
        Image(systemName: mood.symbol)
            .font(.system(size: size * 0.52, weight: .bold))
            .foregroundStyle(island ? IslandInk.card : Palette.ground)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .background(MoodStyle.tint(mood, island: island), in: Circle())
            .overlay(Circle().strokeBorder(island ? IslandInk.card : Palette.ground, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

/// A step line that moves on: the new step arrives from below, the one it replaces dims and moves up,
/// and the one before that leaves. With no earlier step it simply slides to the next.
struct TickerText: View {
    let text: String
    var previous: String? = nil
    var font: Font
    var color: Color
    var dimColor: Color
    var dimFont: Font? = nil
    var lines = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: [String] {
        guard let previous, !previous.isEmpty, previous != text else { return [text] }
        return [previous, text]
    }

    var body: some View {
        let all = shown
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(all.enumerated()), id: \.element) { index, line in
                let current = index == all.count - 1
                Text(line)
                    .font(current ? font : (dimFont ?? font))
                    .foregroundStyle(current ? color : dimColor)
                    .lineLimit(current ? lines : 1)
                    .transition(MoodStyle.tick(reduceMotion))
            }
        }
        .animation(MoodStyle.animation(reduceMotion), value: all)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// A row of small faces: who else is working.
struct FaceRow: View {
    let faces: [(color: UInt32?, shape: String)]
    var size: CGFloat = 18
    var more = 0

    var body: some View {
        HStack(spacing: -size * 0.25) {
            ForEach(Array(faces.prefix(3).enumerated()), id: \.offset) { _, face in
                WidgetFace(color: face.color, shape: face.shape, size: size, pose: .thinking)
            }
            if more > 0 {
                Text("+\(more)").font(KFont.ui(11.5, .medium)).foregroundStyle(Palette.inkFaint).padding(.leading, size * 0.4)
            }
        }
        .accessibilityHidden(true)
    }
}

extension WidgetSnapshot {
    /// The state a widget that stands for one bot shows. `kip` narrows it to the paired desktop's Kip.
    func mood(kip: Bool = false) -> BotMood {
        guard connected else { return .offline }
        let work = kip ? running.filter { $0.isKip == true } : running
        if work.contains(where: { $0.waiting == true }) { return .needsYou }
        if !work.isEmpty { return .working }
        if let ended, !kip || ended.isKip == true { return ended.failed ? .failed : .done }
        return .idle
    }
}

// MARK: - Shared pieces

/// The widget's ground: the app's own ground with one warm glow.
struct WidgetGround: View {
    var body: some View {
        ZStack {
            Palette.ground
            RadialGradient(colors: [Palette.glow, Palette.glow.opacity(0)], center: UnitPoint(x: 0.9, y: -0.1), startRadius: 0, endRadius: 220)
        }
    }
}

struct WidgetHeader: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
            Text(title.uppercased()).font(KFont.ui(10.5, .medium, relativeTo: .caption2)).tracking(1.2).lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.goldText)
        .accessibilityAddTraits(.isHeader)
    }
}

struct WidgetFace: View {
    var color: UInt32?
    var shape: String = "round"
    var size: CGFloat
    var pose: MascotPose = .idle

    var body: some View {
        Mascot(shape: MascotShape(rawValue: shape) ?? .round, colorHex: color, pose: pose, size: size, stage: Palette.ground)
    }
}

/// Not connected: Kip asleep over a quiet wash, and how to fix it.
struct WidgetOffline: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(symbol: "link", title: title)
            MoodFace(color: nil, mood: .offline, size: 38).padding(.top, 4).padding(.leading, 2)
            Spacer(minLength: 0)
            Text("Open Kairos and pair your desktop to see this.").font(KFont.ui(13.5, .medium)).foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A plain line for a widget that has nothing to show yet.
struct WidgetEmpty: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(symbol: symbol, title: title)
            Spacer(minLength: 0)
            Text(text).font(KFont.ui(14, .medium)).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct InkBar: View {
    var value: Double
    var color: Color = Palette.gold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.12))
                Capsule().fill(color).frame(width: proxy.size.width * max(0.04, min(1, value)))
            }
        }
        .frame(height: 5)
        .animation(MoodStyle.animation(reduceMotion), value: value)
    }
}

private struct InkRing: View {
    var value: Double
    var color: Color = Palette.gold
    var width: CGFloat = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Palette.ink.opacity(0.12), lineWidth: width)
            Circle().trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(MoodStyle.animation(reduceMotion), value: value)
    }
}

nonisolated enum WidgetFormat {
    static func count(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 10_000 { return "\(value / 1000)K" }
        if value >= 1000 { return String(format: "%.1fK", Double(value) / 1000) }
        return "\(value)"
    }

    static func money(_ value: Double, _ currency: String) -> String {
        currency + String(format: value >= 100 ? "%.0f" : "%.2f", value)
    }
}

/// A tappable part of a medium or large widget (Links do nothing in small and Lock Screen widgets).
struct WidgetLink<Label: View>: View {
    let link: String
    let label: String
    @ViewBuilder var content: Label

    var body: some View {
        NativeControl(action: .open(URL(string: link) ?? NativeLink.home.url, label)) { content }
    }
}

// MARK: - The kinds of widget

nonisolated enum KairosWidgetKind: String, CaseIterable, Sendable {
    case needsYou, running, team, posts, spend, nextEvent, usage, desktop, quickActions

    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .running: "Running work"
        case .team: "Team status"
        case .posts: "Latest post"
        case .spend: "Spend this month"
        case .nextEvent: "Next event"
        case .usage: "Usage per provider"
        case .desktop: "Desktop and sessions"
        case .quickActions: "Ask Kip"
        }
    }

    var about: String {
        switch self {
        case .needsYou: "How many bots are waiting on an answer or an approval."
        case .running: "Chats, tasks and routines working right now."
        case .team: "Where your bot team is in its cycle."
        case .posts: "Views, likes and comments on your newest post."
        case .spend: "What your models cost this month, against your cap."
        case .nextEvent: "Your next event or due date."
        case .usage: "How much of each provider's limit is used this week."
        case .desktop: "Whether your desktop is on, and its Forge sessions."
        case .quickActions: "Ask Kip, call Kip or open a pinned tab."
        }
    }

    var families: [WidgetFamily] {
        switch self {
        case .needsYou: [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        case .running: [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular]
        case .team: [.systemSmall, .systemMedium, .accessoryRectangular]
        case .posts: [.systemSmall, .systemMedium, .accessoryRectangular]
        case .spend: [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        case .nextEvent: [.systemSmall, .accessoryRectangular, .accessoryInline]
        case .usage: [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular]
        case .desktop: [.systemSmall, .systemMedium, .accessoryRectangular]
        case .quickActions: [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular]
        }
    }

    /// Where a tap on the whole widget goes.
    func link(_ snapshot: WidgetSnapshot) -> URL {
        switch self {
        case .needsYou: URL(string: snapshot.needsYou.first?.link ?? "") ?? NativeLink.home.url
        case .running: URL(string: snapshot.running.first?.link ?? "") ?? NativeLink.home.url
        case .team: snapshot.team?.id.map { NativeLink.bot($0).url } ?? NativeLink.allBots.url
        case .posts: NativeLink.area("studio").url
        case .spend, .usage: NativeLink.home.url
        case .nextEvent: NativeLink.area("calendar").url
        case .desktop: NativeLink.desktop.url
        case .quickActions: NativeLink.ask("kip").url
        }
    }
}

/// One entry point: the right design for a kind and a size.
struct KairosWidgetView: View {
    let kind: KairosWidgetKind
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    var hidingTitles: Bool = NativeSettings.hidesTitles

    var body: some View {
        if !snapshot.connected, kind != .quickActions {
            if family.isAccessory {
                Label("Open Kairos", systemImage: "link").font(.system(size: 13, weight: .medium))
            } else {
                WidgetOffline(title: kind.title)
            }
        } else {
            switch kind {
            case .needsYou: NeedsYouWidgetView(snapshot: snapshot, family: family)
            case .running: RunningWidgetView(snapshot: snapshot, family: family, hidingTitles: hidingTitles)
            case .team: TeamWidgetView(snapshot: snapshot, family: family)
            case .posts: PostsWidgetView(snapshot: snapshot, family: family, hidingTitles: hidingTitles)
            case .spend: SpendWidgetView(snapshot: snapshot, family: family)
            case .nextEvent: EventWidgetView(snapshot: snapshot, family: family, hidingTitles: hidingTitles)
            case .usage: UsageWidgetView(snapshot: snapshot, family: family)
            case .desktop: DesktopWidgetView(snapshot: snapshot, family: family, hidingTitles: hidingTitles)
            case .quickActions: QuickActionsWidgetView(snapshot: snapshot, family: family, hidingTitles: hidingTitles)
            }
        }
    }
}

extension WidgetFamily {
    var isAccessory: Bool { self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline }
}

// MARK: Needs you

struct NeedsYouWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { snapshot.needsYou.count }
    private var names: String { snapshot.needsYou.map(\.botName).joined(separator: ", ") }

    var body: some View {
        content
            .animation(MoodStyle.animation(reduceMotion), value: snapshot.needsYou.map(\.id))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "hand.raised.fill").font(.system(size: 13, weight: .semibold))
                    Text("\(count)").font(.system(size: 22, weight: .semibold, design: .rounded)).widgetAccentable()
                        .contentTransition(.numericText(value: Double(count)))
                }
            }
            .accessibilityLabel("\(count) need you")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(count == 1 ? "1 needs you" : "\(count) need you", systemImage: "hand.raised.fill")
                    .font(.system(size: 15, weight: .semibold)).widgetAccentable()
                    .contentTransition(.numericText(value: Double(count)))
                TickerText(text: count == 0 ? "Nothing is waiting" : names, font: .system(size: 13), color: .primary, dimColor: .secondary)
                Text("Tap to answer").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label(count == 0 ? "Nothing needs you" : "\(count) need you", systemImage: "hand.raised.fill")
                .contentTransition(.numericText(value: Double(count)))
        case .systemMedium:
            HStack(spacing: 16) {
                bigCount.frame(width: 104, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.needsYou.prefix(3)) { item in
                        WidgetLink(link: item.link, label: "Open \(item.botName)") {
                            HStack(spacing: 8) {
                                MoodFace(color: item.botColor, shape: item.botShape, mood: .needsYou, size: 28, showsMark: false)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.botName).font(KFont.ui(14.5, .semibold)).foregroundStyle(Palette.ink)
                                    Text(item.kind == "Approval" ? "Wants your approval" : "Asked you a question")
                                        .font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                                }
                                .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .transition(MoodStyle.tick(reduceMotion))
                    }
                    if snapshot.needsYou.isEmpty {
                        HStack(spacing: 10) {
                            MoodFace(color: nil, mood: .idle, size: 30)
                            Text("Your bots are fine on their own.").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                bigCount
                Spacer(minLength: 0)
                HStack(spacing: -8) {
                    ForEach(snapshot.needsYou.prefix(3)) { item in
                        MoodFace(color: item.botColor, shape: item.botShape, mood: .needsYou, size: 34, showsMark: false)
                            .transition(MoodStyle.swap(reduceMotion))
                    }
                    if snapshot.needsYou.isEmpty {
                        MoodFace(color: nil, mood: .idle, size: 34).transition(MoodStyle.swap(reduceMotion))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var bigCount: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "hand.raised.fill", title: "Needs you")
            Text("\(count)")
                .font(KFont.display(54))
                .foregroundStyle(count == 0 ? Palette.inkFaint : Palette.goldText)
                .contentTransition(.numericText(value: Double(count)))
                .padding(.top, 2)
            Text(count == 0 ? "Nothing waiting" : (count == 1 ? "bot is waiting" : "bots are waiting"))
                .font(KFont.ui(13)).foregroundStyle(Palette.inkDim).lineLimit(1)
        }
    }
}

// MARK: Running work

struct RunningWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    var hidingTitles: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func title(_ item: WidgetSnapshot.Running) -> String { hidingTitles ? "\(item.botName) is working" : item.title }
    private func mood(_ item: WidgetSnapshot.Running) -> BotMood { item.waiting == true ? .needsYou : .working }
    private func step(_ item: WidgetSnapshot.Running) -> String { item.waiting == true ? "Waiting for you" : item.step }

    private func endedLine(_ ended: WidgetSnapshot.Ended) -> String {
        let what = hidingTitles ? "\(ended.botName)'s work" : ended.title
        return ended.failed ? "Couldn't finish: \(what)" : "Done: \(what)"
    }

    var body: some View {
        content
            .animation(MoodStyle.animation(reduceMotion), value: snapshot.running.map(\.id))
            .animation(MoodStyle.animation(reduceMotion), value: snapshot.ended)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            if let first = snapshot.running.first, let progress = first.progress {
                Gauge(value: progress) { Image(systemName: "bolt.fill") } currentValueLabel: {
                    Text("\(Int(progress * 100))").contentTransition(.numericText(value: progress))
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: snapshot.mood().symbol).font(.system(size: 12, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                        Text("\(snapshot.running.count)").font(.system(size: 22, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText(value: Double(snapshot.running.count)))
                    }
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(snapshot.running.count) running", systemImage: "bolt.fill").font(.system(size: 15, weight: .semibold)).widgetAccentable()
                    .contentTransition(.numericText(value: Double(snapshot.running.count)))
                if let first = snapshot.running.first {
                    TickerText(text: title(first), font: .system(size: 13), color: .primary, dimColor: .secondary)
                    if let progress = first.progress { ProgressView(value: progress).tint(.primary) }
                } else if let ended = snapshot.ended {
                    Text(endedLine(ended)).font(.system(size: 13)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium, .systemLarge:
            VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 9) {
                WidgetHeader(symbol: "bolt.fill", title: "\(snapshot.running.count) running")
                    .contentTransition(.numericText(value: Double(snapshot.running.count)))
                ForEach(snapshot.running.prefix(family == .systemLarge ? 5 : 3)) { item in
                    WidgetLink(link: item.link, label: "Open \(item.title)") { row(item) }
                        .transition(MoodStyle.tick(reduceMotion))
                }
                if snapshot.running.isEmpty {
                    if let ended = snapshot.ended {
                        WidgetLink(link: ended.link, label: "Open \(ended.botName)") { endedRow(ended) }
                            .transition(MoodStyle.tick(reduceMotion))
                    } else {
                        HStack(spacing: 10) {
                            MoodFace(color: nil, mood: .idle, size: 30)
                            Text("Nothing is running.").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                        }
                        .transition(.opacity)
                    }
                }
                if family == .systemLarge, !snapshot.needsYou.isEmpty {
                    Palette.line.frame(height: 1).padding(.vertical, 4)
                    WidgetHeader(symbol: "hand.raised.fill", title: "Waiting on you")
                    ForEach(snapshot.needsYou.prefix(3)) { item in
                        WidgetLink(link: item.link, label: "Open \(item.botName)") {
                            HStack(spacing: 10) {
                                MoodFace(color: item.botColor, shape: item.botShape, mood: .needsYou, size: 30, showsMark: false)
                                Text(item.botName).font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.ink)
                                Text(item.kind == "Approval" ? "wants your approval" : "asked you a question")
                                    .font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
                                Spacer(minLength: 0)
                            }
                            .lineLimit(1)
                        }
                        .transition(MoodStyle.tick(reduceMotion))
                    }
                }
                Spacer(minLength: 0)
                if family == .systemLarge {
                    HStack(spacing: 4) {
                        Text("Updated")
                        Text(snapshot.updatedAt, style: .time)
                    }
                    .font(KFont.ui(11.5)).foregroundStyle(Palette.inkFaint)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    WidgetHeader(symbol: "bolt.fill", title: "Running")
                    if let started = snapshot.running.first?.startedAt { timer(started) }
                }
                if let first = snapshot.running.first {
                    HStack(alignment: .center, spacing: 8) {
                        ZStack {
                            InkRing(value: first.progress ?? 0.3, color: MoodStyle.tint(mood(first)), width: 4)
                            MoodFace(color: first.botColor, shape: first.botShape, mood: mood(first), size: 34)
                        }
                        .frame(width: 46, height: 46)
                        Spacer(minLength: 0)
                        if snapshot.running.count > 1 {
                            FaceRow(faces: snapshot.running.dropFirst().map { (color: $0.botColor, shape: $0.botShape) }, size: 18,
                                    more: max(0, snapshot.running.count - 4))
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                    TickerText(text: title(first), font: KFont.ui(15, .semibold), color: Palette.ink, dimColor: Palette.inkFaint, lines: 2)
                    TickerText(text: step(first), font: KFont.ui(12.5), color: mood(first) == .needsYou ? Palette.goldText : Palette.inkFaint,
                               dimColor: Palette.inkFaint)
                } else if let ended = snapshot.ended {
                    MoodFace(color: ended.botColor, shape: ended.botShape, mood: ended.failed ? .failed : .done, size: 38)
                        .padding(.top, 4).padding(.leading, 2)
                        .transition(MoodStyle.swap(reduceMotion))
                    Spacer(minLength: 0)
                    Text(endedLine(ended)).font(KFont.ui(14.5, .semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                    Text("\(Text(ended.at, style: .relative)) ago").font(KFont.ui(12)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                } else {
                    MoodFace(color: nil, mood: .idle, size: 38).padding(.top, 4).padding(.leading, 2)
                        .transition(MoodStyle.swap(reduceMotion))
                    Spacer(minLength: 0)
                    Text("Nothing is running.").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Time since the desktop started the turn; WidgetKit keeps it ticking with the app closed.
    private func timer(_ since: Date) -> some View {
        Text(since, style: .timer)
            .font(KFont.ui(11.5, .medium).monospacedDigit())
            .foregroundStyle(Palette.inkFaint)
            .multilineTextAlignment(.trailing)
            .frame(width: 46, alignment: .trailing)
            .lineLimit(1)
    }

    private func row(_ item: WidgetSnapshot.Running) -> some View {
        HStack(spacing: 10) {
            MoodFace(color: item.botColor, shape: item.botShape, mood: mood(item), size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title(item)).font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    if let progress = item.progress {
                        Text("\(Int(progress * 100))%")
                            .font(KFont.ui(12.5).monospacedDigit()).foregroundStyle(Palette.inkFaint).lineLimit(1)
                            .contentTransition(.numericText(value: progress))
                    } else if let started = item.startedAt {
                        timer(started)
                    } else {
                        Text(step(item)).font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                    }
                }
                if family == .systemLarge {
                    TickerText(text: step(item), previous: item.waiting == true ? nil : item.previousStep, font: KFont.ui(12.5),
                               color: mood(item) == .needsYou ? Palette.goldText : Palette.inkDim, dimColor: Palette.inkFaint, dimFont: KFont.ui(11))
                }
                if let progress = item.progress {
                    InkBar(value: progress, color: MoodStyle.tint(mood(item)))
                } else {
                    InkBar(value: 0.25, color: MoodStyle.tint(mood(item)).opacity(0.7))
                }
            }
        }
    }

    private func endedRow(_ ended: WidgetSnapshot.Ended) -> some View {
        HStack(spacing: 10) {
            MoodFace(color: ended.botColor, shape: ended.botShape, mood: ended.failed ? .failed : .done, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(endedLine(ended)).font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                Text("\(Text(ended.at, style: .relative)) ago").font(KFont.ui(12)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Team status

struct TeamWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let team = snapshot.team {
            content(team)
                .animation(MoodStyle.animation(reduceMotion), value: team)
        } else {
            WidgetEmpty(symbol: "person.3", title: "Team", text: "Tap to see your bots and teams.")
        }
    }

    private func stageLine(_ team: WidgetSnapshot.Team) -> String {
        let stageName = team.stages.indices.contains(team.stage) ? team.stages[team.stage] : ""
        return team.paused ? "Paused" : "\(stageName) · \(team.stage + 1) of \(team.stages.count)"
    }

    @ViewBuilder
    private func content(_ team: WidgetSnapshot.Team) -> some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(team.name, systemImage: "person.3.fill").font(.system(size: 15, weight: .semibold)).widgetAccentable()
                TickerText(text: stageLine(team), font: .system(size: 13), color: .primary, dimColor: .secondary)
                ProgressView(value: Double(team.stage + 1), total: Double(max(1, team.stages.count))).tint(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        WidgetHeader(symbol: "person.3.fill", title: "Team")
                        Text(team.name).font(KFont.display(26)).foregroundStyle(Palette.ink).lineLimit(1)
                        TickerText(text: team.paused ? "Paused" : team.note, font: KFont.ui(13), color: Palette.inkDim, dimColor: Palette.inkFaint)
                    }
                    Spacer(minLength: 6)
                    faces(team, size: 34)
                }
                Spacer(minLength: 0)
                track(team)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(symbol: "person.3.fill", title: "Team")
                faces(team, size: 30).padding(.top, 4)
                Spacer(minLength: 0)
                Text(team.name).font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                TickerText(text: stageLine(team), font: KFont.ui(12.5), color: Palette.inkFaint, dimColor: Palette.inkFaint)
                track(team, labels: false).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func faces(_ team: WidgetSnapshot.Team, size: CGFloat) -> some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(team.memberColors.prefix(3).enumerated()), id: \.offset) { index, color in
                MoodFace(color: color, shape: ["squircle", "round", "tall"][index % 3], mood: team.paused ? .idle : .working,
                         size: size, showsMark: index == 0)
            }
        }
    }

    private func track(_ team: WidgetSnapshot.Team, labels: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(team.stages.enumerated()), id: \.offset) { index, name in
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(index < team.stage ? Palette.gold : (index == team.stage ? Palette.gold.opacity(0.55) : Palette.ink.opacity(0.12)))
                        .frame(height: 5)
                    if labels {
                        Text(name).font(KFont.ui(11, index == team.stage ? .semibold : .regular))
                            .foregroundStyle(index <= team.stage ? Palette.ink : Palette.inkFaint).lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: Latest post numbers

struct PostsWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    var hidingTitles: Bool

    var body: some View {
        if let post = snapshot.post {
            content(post)
        } else {
            WidgetEmpty(symbol: "play.rectangle", title: "Latest post", text: "Nothing posted yet.")
        }
    }

    @ViewBuilder
    private func content(_ post: WidgetSnapshot.Post) -> some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("\(WidgetFormat.count(post.views)) views", systemImage: "play.rectangle.fill").font(.system(size: 15, weight: .semibold)).widgetAccentable()
                Text("\(WidgetFormat.count(post.likes)) likes · \(WidgetFormat.count(post.comments)) comments").font(.system(size: 13))
                Text(post.platform).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(symbol: "play.rectangle.fill", title: "Latest post · \(post.platform)")
                Text(hidingTitles ? "Your newest post" : post.title).font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                HStack(spacing: 0) {
                    stat(post.views, "views")
                    stat(post.likes, "likes")
                    stat(post.comments, "comments")
                }
                Spacer(minLength: 0)
                tapNote(post)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(symbol: "play.rectangle.fill", title: "Latest post")
                Text(WidgetFormat.count(post.views)).font(KFont.display(44)).foregroundStyle(Palette.ink).padding(.top, 4)
                    .contentTransition(.numericText(value: Double(post.views)))
                Text("views on \(post.platform)").font(KFont.ui(12.5)).foregroundStyle(Palette.inkDim).lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Label(WidgetFormat.count(post.likes), systemImage: "heart.fill")
                    Label(WidgetFormat.count(post.comments), systemImage: "bubble.left.fill")
                }
                .font(KFont.ui(12.5, .medium)).foregroundStyle(Palette.inkFaint).labelStyle(.titleAndIcon)
                tapNote(post).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(WidgetFormat.count(value)).font(KFont.display(30)).foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(value)))
            Text(label).font(KFont.ui(12)).foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tapNote(_ post: WidgetSnapshot.Post) -> some View {
        if post.needsTap > 0 {
            Text(post.needsTap == 1 ? "1 TikTok post needs your tap" : "\(post.needsTap) TikTok posts need your tap")
                .font(KFont.ui(12, .medium)).foregroundStyle(Palette.goldText).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

// MARK: Spend this month

struct SpendWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    var body: some View {
        if let spend = snapshot.spend {
            content(spend)
        } else {
            WidgetEmpty(symbol: "creditcard", title: "Spend", text: "No spend recorded this month.")
        }
    }

    @ViewBuilder
    private func content(_ spend: WidgetSnapshot.Spend) -> some View {
        let share = spend.cap > 0 ? spend.spent / spend.cap : 0
        let tint = share >= 1 ? Palette.danger : (share >= 0.8 ? Palette.goldText : Palette.gold)
        switch family {
        case .accessoryCircular:
            Gauge(value: min(1, share)) { Image(systemName: "creditcard") } currentValueLabel: {
                Text(spend.currency + "\(Int(spend.spent.rounded()))").minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Spend this month", systemImage: "creditcard.fill").font(.system(size: 14, weight: .semibold)).widgetAccentable()
                Text("\(WidgetFormat.money(spend.spent, spend.currency)) of \(WidgetFormat.money(spend.cap, spend.currency))").font(.system(size: 13))
                ProgressView(value: min(1, share)).tint(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label("\(WidgetFormat.money(spend.spent, spend.currency)) of \(WidgetFormat.money(spend.cap, spend.currency)) this month", systemImage: "creditcard")
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(symbol: "creditcard.fill", title: "This month")
                Text(WidgetFormat.money(spend.spent, spend.currency)).font(KFont.display(40)).foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: spend.spent))
                    .minimumScaleFactor(0.7).lineLimit(1).padding(.top, 6)
                Text("of \(WidgetFormat.money(spend.cap, spend.currency)) cap").font(KFont.ui(13)).foregroundStyle(Palette.inkDim)
                Spacer(minLength: 0)
                InkBar(value: share, color: tint)
                Text(spend.unknown ? "Some spend is unknown" : (share >= 1 ? "At your cap" : "\(Int(share * 100))% used"))
                    .font(KFont.ui(12, .medium)).foregroundStyle(share >= 0.8 || spend.unknown ? Palette.goldText : Palette.inkFaint)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: Next event

struct EventWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    var hidingTitles: Bool

    var body: some View {
        if let event = snapshot.nextEvent {
            content(event)
        } else {
            WidgetEmpty(symbol: "calendar", title: "Next", text: "Nothing on your calendar.")
        }
    }

    @ViewBuilder
    private func content(_ event: WidgetSnapshot.Event) -> some View {
        let title = hidingTitles ? "Event" : event.title
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(event.startsAt.formatted(.dateTime.weekday(.wide))).font(.system(size: 13, weight: .semibold)).widgetAccentable()
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(event.allDay ? "All day" : event.startsAt.formatted(date: .omitted, time: .shortened)).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label("\(event.startsAt.formatted(.dateTime.weekday(.abbreviated))) \(event.allDay ? "" : event.startsAt.formatted(date: .omitted, time: .shortened)) · \(title)", systemImage: "calendar")
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(symbol: "calendar", title: "Next")
                Text(event.startsAt.formatted(.dateTime.weekday(.wide)))
                    .font(KFont.ui(15, .semibold)).foregroundStyle(Palette.goldText).padding(.top, 8)
                Text(title).font(KFont.display(26)).foregroundStyle(Palette.ink).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(event.allDay ? "All day" : event.startsAt.formatted(date: .omitted, time: .shortened))
                    .font(KFont.ui(14, .medium)).foregroundStyle(Palette.inkDim)
                Text(event.startsAt, style: .relative).font(KFont.ui(12)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: Usage per provider

struct UsageWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    private func tint(_ percent: Int) -> Color { percent >= 90 ? Palette.danger : (percent >= 75 ? Palette.goldText : Palette.gold) }

    var body: some View {
        if snapshot.usage.isEmpty {
            WidgetEmpty(symbol: "gauge.with.dots.needle.33percent", title: "Usage", text: "No limits reported by your providers.")
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let top = snapshot.usage.max { $0.percent < $1.percent } ?? snapshot.usage[0]
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(top.percent), in: 0...100) { Text(String(top.provider.prefix(1))) } currentValueLabel: {
                Text("\(top.percent)")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(snapshot.usage.prefix(2)) { item in
                    HStack(spacing: 6) {
                        Text(item.provider).font(.system(size: 13, weight: .semibold)).frame(width: 52, alignment: .leading)
                        ProgressView(value: Double(item.percent), total: 100).tint(.primary)
                        Text("\(item.percent)%").font(.system(size: 12).monospacedDigit())
                    }
                }
            }
        case .systemMedium:
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(symbol: "gauge.with.dots.needle.33percent", title: "Usage this week")
                ForEach(snapshot.usage.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.provider).font(KFont.ui(14, .medium)).foregroundStyle(Palette.ink)
                            Spacer()
                            if let reset = item.resetsAt {
                                Text("resets \(reset.formatted(.dateTime.weekday(.abbreviated)))").font(KFont.ui(11.5)).foregroundStyle(Palette.inkFaint)
                            }
                            Text("\(item.percent)%").font(KFont.ui(14, .semibold).monospacedDigit()).foregroundStyle(tint(item.percent))
                                .contentTransition(.numericText(value: Double(item.percent)))
                        }
                        InkBar(value: Double(item.percent) / 100, color: tint(item.percent))
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(symbol: "gauge.with.dots.needle.33percent", title: "Usage")
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    ForEach(snapshot.usage.prefix(2)) { item in
                        VStack(spacing: 6) {
                            ZStack {
                                InkRing(value: Double(item.percent) / 100, color: tint(item.percent), width: 6)
                                Text("\(item.percent)").font(KFont.ui(17, .semibold).monospacedDigit()).foregroundStyle(Palette.ink)
                                    .contentTransition(.numericText(value: Double(item.percent)))
                            }
                            .frame(width: 56, height: 56)
                            Text(item.provider).font(KFont.ui(12.5, .medium)).foregroundStyle(Palette.inkDim).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: Desktop and sessions

struct DesktopWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    var hidingTitles: Bool

    var body: some View {
        if let desktop = snapshot.desktop {
            content(desktop)
        } else {
            WidgetEmpty(symbol: "desktopcomputer", title: "Desktop", text: "No desktop paired.")
        }
    }

    @ViewBuilder
    private func content(_ desktop: WidgetSnapshot.Desktop) -> some View {
        let waiting = desktop.sessions.filter(\.waiting).count
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(desktop.online ? "\(desktop.name) is on" : "\(desktop.name) is off", systemImage: "desktopcomputer")
                    .font(.system(size: 15, weight: .semibold)).widgetAccentable()
                Text("\(desktop.sessions.count) Forge sessions").font(.system(size: 13))
                if waiting > 0 { Text("\(waiting) waiting for you").font(.system(size: 13, weight: .semibold)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    WidgetHeader(symbol: "desktopcomputer", title: desktop.name)
                    onlineTag(desktop.online)
                }
                ForEach(desktop.sessions.prefix(3)) { session in
                    WidgetLink(link: NativeLink.area("forge").url.absoluteString, label: "Open Forge") {
                        HStack(spacing: 8) {
                            Image(systemName: "hammer.fill").font(.system(size: 12)).foregroundStyle(Palette.goldText).frame(width: 26, height: 26)
                                .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(hidingTitles ? "Forge session" : session.title).font(KFont.ui(14, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text("+\(session.added)").foregroundStyle(Palette.success)
                                    Text("−\(session.removed)").foregroundStyle(Palette.danger)
                                    if session.waiting { Text("waiting for you").foregroundStyle(Palette.goldText) }
                                }
                                .font(KFont.ui(12, .medium).monospacedDigit())
                            }
                            Spacer(minLength: 0)
                            if session.waiting { Circle().fill(Palette.gold).frame(width: 8, height: 8) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(symbol: "desktopcomputer", title: "Desktop")
                Image(systemName: "desktopcomputer").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.ink).padding(.top, 6)
                Spacer(minLength: 0)
                Text(desktop.name).font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                onlineTag(desktop.online)
                Text(waiting > 0 ? "\(waiting) session waiting" : "\(desktop.sessions.count) Forge sessions")
                    .font(KFont.ui(12.5, .medium)).foregroundStyle(waiting > 0 ? Palette.goldText : Palette.inkFaint).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func onlineTag(_ online: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(online ? Palette.success : Palette.inkFaint).frame(width: 7, height: 7)
            Text(online ? "On" : "Off").font(KFont.ui(12, .medium)).foregroundStyle(Palette.inkDim)
        }
    }
}

// MARK: Quick actions

struct QuickActionsWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    var hidingTitles: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Kip's own state on the paired desktop (or on the sample data before pairing).
    private var mood: BotMood { snapshot.mood(kip: true) }

    private var line: String {
        let work = snapshot.running.first { $0.isKip == true }
        switch mood {
        case .working:
            guard let work else { return "Working" }
            return hidingTitles ? "Working on it" : work.title
        case .needsYou: return "Waiting for you"
        case .done: return "Finished. Tap to see"
        case .failed: return "Couldn't finish"
        case .offline: return "Not connected"
        case .idle: return "Anything, any time"
        }
    }

    var body: some View {
        content
            .animation(MoodStyle.animation(reduceMotion), value: mood)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Mascot(pose: MoodStyle.pose(mood), size: 44, stage: .clear)
                    .id(mood)
                    .transition(MoodStyle.swap(reduceMotion))
            }
            .accessibilityLabel("Ask Kip")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Mascot(pose: MoodStyle.pose(mood), size: 38, stage: .clear)
                    .id(mood)
                    .transition(MoodStyle.swap(reduceMotion))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask Kip").font(.system(size: 15, weight: .semibold)).widgetAccentable()
                    TickerText(text: mood == .idle ? "Tap to start" : line, font: .system(size: 13), color: .secondary, dimColor: .secondary)
                }
                Spacer(minLength: 0)
            }
        case .systemMedium:
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    MoodFace(color: nil, mood: mood, size: 70)
                    Text("Kip").font(KFont.display(24)).foregroundStyle(Palette.ink)
                }
                .frame(width: 96)
                VStack(spacing: 8) {
                    action("Ask Kip", "bubble.left.fill", NativeLink.ask("kip"))
                    action("Call Kip", "phone.fill", NativeLink.call("kip"))
                    if let pinned = snapshot.pinned {
                        action("Open \(pinned.title)", pinned.symbol, .addedTab(pinned.title))
                    } else {
                        action("New chat", "plus", .newChat)
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                MoodFace(color: nil, mood: mood, size: 66).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                Text("Ask Kip").font(KFont.display(28)).foregroundStyle(Palette.ink)
                TickerText(text: line, font: KFont.ui(12.5), color: mood == .needsYou ? Palette.goldText : Palette.inkFaint, dimColor: Palette.inkFaint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func action(_ title: String, _ symbol: String, _ link: NativeLink) -> some View {
        WidgetLink(link: link.url.absoluteString, label: title) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.goldText).frame(width: 20)
                Text(title).font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(Palette.ink.opacity(0.08), in: Capsule())
        }
    }
}
