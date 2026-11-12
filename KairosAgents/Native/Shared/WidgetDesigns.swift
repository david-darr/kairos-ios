import SwiftUI
import WidgetKit

// The widget designs. The extension draws them on the Home Screen and the Lock Screen;
// the app's gallery draws the same views so they can be photographed. They follow the look:
// night brown with cream ink, or parchment with bistre.

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

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.12))
                Capsule().fill(color).frame(width: proxy.size.width * max(0.04, min(1, value)))
            }
        }
        .frame(height: 5)
    }
}

private struct InkRing: View {
    var value: Double
    var color: Color = Palette.gold
    var width: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(Palette.ink.opacity(0.12), lineWidth: width)
            Circle().trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
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
        case .team: NativeLink.bot("content-team").url
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
                WidgetEmpty(symbol: "link", title: kind.title, text: "Open Kairos and pair your desktop to see this.")
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
            case .quickActions: QuickActionsWidgetView(snapshot: snapshot, family: family)
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

    private var count: Int { snapshot.needsYou.count }
    private var names: String { snapshot.needsYou.map(\.botName).joined(separator: ", ") }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "hand.raised.fill").font(.system(size: 13, weight: .semibold))
                    Text("\(count)").font(.system(size: 22, weight: .semibold, design: .rounded)).widgetAccentable()
                }
            }
            .accessibilityLabel("\(count) need you")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(count == 1 ? "1 needs you" : "\(count) need you", systemImage: "hand.raised.fill")
                    .font(.system(size: 15, weight: .semibold)).widgetAccentable()
                Text(count == 0 ? "Nothing is waiting" : names).font(.system(size: 13)).lineLimit(1)
                Text("Tap to answer").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label(count == 0 ? "Nothing needs you" : "\(count) need you", systemImage: "hand.raised.fill")
        case .systemMedium:
            HStack(spacing: 16) {
                bigCount.frame(width: 104, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.needsYou.prefix(3)) { item in
                        WidgetLink(link: item.link, label: "Open \(item.botName)") {
                            HStack(spacing: 8) {
                                WidgetFace(color: item.botColor, shape: item.botShape, size: 28, pose: .needs)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.botName).font(KFont.ui(14.5, .semibold)).foregroundStyle(Palette.ink)
                                    Text(item.kind == "Approval" ? "Wants your approval" : "Asked you a question")
                                        .font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                                }
                                .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    if snapshot.needsYou.isEmpty {
                        Text("Your bots are fine on their own.").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
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
                        WidgetFace(color: item.botColor, shape: item.botShape, size: 34, pose: .needs)
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
                .contentTransition(.numericText())
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

    private func title(_ item: WidgetSnapshot.Running) -> String { hidingTitles ? "\(item.botName) is working" : item.title }

    var body: some View {
        switch family {
        case .accessoryCircular:
            if let first = snapshot.running.first, let progress = first.progress {
                Gauge(value: progress) { Image(systemName: "bolt.fill") } currentValueLabel: {
                    Text("\(Int(progress * 100))")
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "bolt.fill").font(.system(size: 12, weight: .semibold))
                        Text("\(snapshot.running.count)").font(.system(size: 22, weight: .semibold, design: .rounded))
                    }
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(snapshot.running.count) running", systemImage: "bolt.fill").font(.system(size: 15, weight: .semibold)).widgetAccentable()
                if let first = snapshot.running.first {
                    Text(title(first)).font(.system(size: 13)).lineLimit(1)
                    if let progress = first.progress { ProgressView(value: progress).tint(.primary) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium, .systemLarge:
            VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 9) {
                WidgetHeader(symbol: "bolt.fill", title: "\(snapshot.running.count) running")
                ForEach(snapshot.running.prefix(family == .systemLarge ? 5 : 3)) { item in
                    WidgetLink(link: item.link, label: "Open \(item.title)") { row(item) }
                }
                if snapshot.running.isEmpty {
                    Text("Nothing is running.").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
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
                WidgetHeader(symbol: "bolt.fill", title: "Running")
                if let first = snapshot.running.first {
                    ZStack {
                        InkRing(value: first.progress ?? 0.3, width: 4)
                        WidgetFace(color: first.botColor, shape: first.botShape, size: 34, pose: .thinking)
                    }
                    .frame(width: 46, height: 46)
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                    Text(title(first)).font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                    Text(snapshot.running.count > 1 ? "\(first.step) · +\(snapshot.running.count - 1) more" : first.step)
                        .font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                } else {
                    Spacer(minLength: 0)
                    Text("Nothing is running.").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func row(_ item: WidgetSnapshot.Running) -> some View {
        HStack(spacing: 10) {
            WidgetFace(color: item.botColor, shape: item.botShape, size: 30, pose: .thinking)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title(item)).font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.progress.map { "\(Int($0 * 100))%" } ?? item.step)
                        .font(KFont.ui(12.5).monospacedDigit()).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                if let progress = item.progress {
                    InkBar(value: progress)
                } else {
                    InkBar(value: 0.25, color: Palette.working.opacity(0.7))
                }
            }
        }
    }
}

// MARK: Team status

struct TeamWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    var body: some View {
        if let team = snapshot.team {
            content(team)
        } else {
            WidgetEmpty(symbol: "person.3", title: "Team", text: "No bot team yet.")
        }
    }

    @ViewBuilder
    private func content(_ team: WidgetSnapshot.Team) -> some View {
        let stageName = team.stages.indices.contains(team.stage) ? team.stages[team.stage] : ""
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(team.name, systemImage: "person.3.fill").font(.system(size: 15, weight: .semibold)).widgetAccentable()
                Text(team.paused ? "Paused" : "\(stageName) · \(team.stage + 1) of \(team.stages.count)").font(.system(size: 13))
                ProgressView(value: Double(team.stage + 1), total: Double(max(1, team.stages.count))).tint(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        WidgetHeader(symbol: "person.3.fill", title: "Team")
                        Text(team.name).font(KFont.display(26)).foregroundStyle(Palette.ink).lineLimit(1)
                        Text(team.paused ? "Paused" : team.note).font(KFont.ui(13)).foregroundStyle(Palette.inkDim).lineLimit(1)
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
                Text(team.paused ? "Paused" : "\(stageName) · \(team.stage + 1) of \(team.stages.count)")
                    .font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                track(team, labels: false).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func faces(_ team: WidgetSnapshot.Team, size: CGFloat) -> some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(team.memberColors.prefix(3).enumerated()), id: \.offset) { index, color in
                WidgetFace(color: color, shape: ["squircle", "round", "tall"][index % 3], size: size)
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
                Text(WidgetFormat.money(spend.spent, spend.currency)).minimumScaleFactor(0.5)
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

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Mascot(size: 44, stage: .clear)
            }
            .accessibilityLabel("Ask Kip")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Mascot(size: 38, stage: .clear)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask Kip").font(.system(size: 15, weight: .semibold)).widgetAccentable()
                    Text("Tap to start").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .systemMedium:
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Mascot(size: 74, stage: Palette.ground)
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
                Mascot(size: 70, stage: Palette.ground).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                Text("Ask Kip").font(KFont.display(28)).foregroundStyle(Palette.ink)
                Text("Anything, any time").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
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
