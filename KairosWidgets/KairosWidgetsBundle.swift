import ActivityKit
import SwiftUI
import WidgetKit

/// The widget extension: one Live Activity for every kind of live work, and nine widgets.
/// Built only from project-widgets.yml; the designs live in KairosAgents/Native/Shared so the app's gallery draws the same views.
#warning("Proof: the KairosWidgets extension target is compiled")
@main
struct KairosWidgetsBundle: WidgetBundle {
    var body: some Widget {
        KairosLiveActivity()
        NeedsYouWidget()
        RunningWidget()
        TeamWidget()
        PostsWidget()
        SpendWidget()
        NextEventWidget()
        UsageWidget()
        DesktopWidget()
        QuickActionsWidget()
    }
}

// MARK: - Live Activity and Dynamic Island

struct KairosLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KairosActivityAttributes.self) { context in
            ActivityLockView(attributes: context.attributes, state: shown(context))
                .activityBackgroundTint(IslandInk.card.opacity(0.92))
                .activitySystemActionForegroundColor(IslandInk.cream)
                .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            let state = shown(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(attributes: context.attributes, state: state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(attributes: context.attributes, state: state)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedCenter(attributes: context.attributes, state: state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(attributes: context.attributes, state: state)
                }
            } compactLeading: {
                IslandCompactLeading(attributes: context.attributes, state: state)
            } compactTrailing: {
                IslandCompactTrailing(attributes: context.attributes, state: state)
            } minimal: {
                IslandMinimal(attributes: context.attributes, state: state)
            }
            .widgetURL(context.attributes.url)
            .keylineTint(IslandInk.gold)
        }
    }

    /// A stale activity says so instead of showing an old step as if it were current.
    private func shown(_ context: ActivityViewContext<KairosActivityAttributes>) -> KairosActivityAttributes.ContentState {
        guard context.isStale, !context.state.phase.ended else { return context.state }
        var state = context.state
        state.step = "Open Kairos to refresh"
        return state
    }
}

// MARK: - Widgets

nonisolated struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Every widget reads the same snapshot the app writes to the App Group.
nonisolated struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: NativeSample.snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let stored = WidgetSnapshotStore.read()
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview && !stored.connected ? NativeSample.snapshot() : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct KairosWidgetContent: View {
    let kind: KairosWidgetKind
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        KairosWidgetView(kind: kind, snapshot: entry.snapshot, family: family)
            .containerBackground(for: .widget) {
                if family.isAccessory { Color.clear } else { WidgetGround() }
            }
            .widgetURL(kind.link(entry.snapshot))
    }
}

private func configuration(_ kind: KairosWidgetKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: "kairos." + kind.rawValue, provider: SnapshotProvider()) { entry in
        KairosWidgetContent(kind: kind, entry: entry)
    }
    .configurationDisplayName(kind.title)
    .description(kind.about)
    .supportedFamilies(kind.families)
}

struct NeedsYouWidget: Widget { var body: some WidgetConfiguration { configuration(.needsYou) } }
struct RunningWidget: Widget { var body: some WidgetConfiguration { configuration(.running) } }
struct TeamWidget: Widget { var body: some WidgetConfiguration { configuration(.team) } }
struct PostsWidget: Widget { var body: some WidgetConfiguration { configuration(.posts) } }
struct SpendWidget: Widget { var body: some WidgetConfiguration { configuration(.spend) } }
struct NextEventWidget: Widget { var body: some WidgetConfiguration { configuration(.nextEvent) } }
struct UsageWidget: Widget { var body: some WidgetConfiguration { configuration(.usage) } }
struct DesktopWidget: Widget { var body: some WidgetConfiguration { configuration(.desktop) } }
struct QuickActionsWidget: Widget { var body: some WidgetConfiguration { configuration(.quickActions) } }
