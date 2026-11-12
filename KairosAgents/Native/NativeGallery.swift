import SwiftUI
import WidgetKit

// The gallery: every Live Activity, Dynamic Island, widget and notification design, drawn with the very
// views the extension uses, so the build can photograph them. Buttons here say what they would do.

// MARK: - Page frame

private struct GalleryPage<Content: View>: View {
    let title: String
    var dark = false
    @ViewBuilder var content: Content
    @State private var tapped: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            Text(title)
                .font(KFont.ui(15, .semibold))
                .foregroundStyle(dark ? IslandInk.cream : Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
                .background { if !dark { HeaderFade() } }
        }
        .overlay(alignment: .bottom) {
            if let tapped {
                Text(tapped)
                    .font(KFont.ui(14, .medium))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .kGlass(Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.nativePreview, { name in
            withAnimation(Motion.snappy) { tapped = "\(name): tapped. On a phone this goes to your desktop." }
        })
        .background { if dark { LockWallpaper() } }
        .kScreen()
    }
}

private struct Caption: View {
    let text: String
    var dark = false

    var body: some View {
        Text(text.uppercased())
            .font(KFont.label)
            .tracking(1.4)
            .foregroundStyle(dark ? IslandInk.faint : Palette.inkFaint)
            .padding(.top, 6)
    }
}

/// A warm dark wallpaper, like the Lock Screen in the reference.
struct LockWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x4A3524), Color(hex: 0x241A13), Color(hex: 0x120E0B)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x8A6236, alpha: 0.45), .clear], center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Dynamic Island drawings

/// The island's compact pill: leading side, the camera, trailing side.
struct IslandCompactDrawing: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 0) {
            IslandCompactLeading(attributes: attributes, state: state).frame(width: 40, alignment: .leading)
            Color.black.frame(width: 126)
            IslandCompactTrailing(attributes: attributes, state: state).frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 37)
        .background(Color.black, in: Capsule())
        .environment(\.colorScheme, .dark)
    }
}

/// Two activities at once: one keeps the pill, the other becomes a small circle.
struct IslandMinimalDrawing: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState
    let other: KairosActivityAttributes
    let otherState: KairosActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                IslandCompactLeading(attributes: other, state: otherState).frame(width: 36, alignment: .leading)
                Color.black.frame(width: 110)
                IslandCompactTrailing(attributes: other, state: otherState).frame(minWidth: 36, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(height: 37)
            .background(Color.black, in: Capsule())
            IslandMinimal(attributes: attributes, state: state)
                .frame(width: 37, height: 37)
                .background(Color.black, in: Circle())
        }
        .environment(\.colorScheme, .dark)
    }
}

/// The expanded island: leading and trailing beside the camera, the centre under it, the bottom across.
struct IslandExpandedDrawing: View {
    let attributes: KairosActivityAttributes
    let state: KairosActivityAttributes.ContentState
    var hidingTitles = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                IslandExpandedLeading(attributes: attributes, state: state)
                IslandExpandedCenter(attributes: attributes, state: state, hidingTitles: hidingTitles)
                    .padding(.top, 4)
                IslandExpandedTrailing(attributes: attributes, state: state)
            }
            IslandExpandedBottom(attributes: attributes, state: state)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 42, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// The Lock Screen card as iOS frames it: rounded, over the wallpaper, with the activity's tint.
struct LockCardDrawing<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(IslandInk.card.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Live Activity pages

struct ActivityKindPage: View {
    let kind: ActivityKind

    var body: some View {
        let attributes = NativeSample.attributes(kind)
        let running = NativeSample.running(kind)
        let other: ActivityKind = kind == .reply ? .render : .reply
        GalleryPage(title: "\(kind.label): Live Activity", dark: true) {
            Caption(text: "Dynamic Island, compact", dark: true)
            IslandCompactDrawing(attributes: attributes, state: running).frame(maxWidth: .infinity)
            Caption(text: "Minimal, beside another activity", dark: true)
            IslandMinimalDrawing(attributes: attributes, state: running,
                                 other: NativeSample.attributes(other), otherState: NativeSample.running(other))
                .frame(maxWidth: .infinity)
            Caption(text: "Expanded", dark: true)
            IslandExpandedDrawing(attributes: attributes, state: running)
            Caption(text: "Lock Screen", dark: true)
            LockCardDrawing { ActivityLockView(attributes: attributes, state: running, hidingTitles: false) }
            Caption(text: kind == .call ? "Ended" : "Done and couldn't finish", dark: true)
            LockCardDrawing { ActivityLockView(attributes: attributes, state: NativeSample.done(kind), hidingTitles: false) }
            if kind != .call {
                LockCardDrawing { ActivityLockView(attributes: attributes, state: NativeSample.failed(kind), hidingTitles: false) }
            }
        }
    }
}

/// End states in the island, a waiting state, and the call muted.
struct ActivityEndsPage: View {
    var body: some View {
        var waiting = NativeSample.running(.reply)
        waiting.phase = .waiting
        var muted = NativeSample.running(.call)
        muted.muted = true
        return GalleryPage(title: "Ends and waiting", dark: true) {
            Caption(text: "Compact: done, couldn't finish, waiting", dark: true)
            HStack(spacing: 8) {
                IslandCompactDrawing(attributes: NativeSample.attributes(.task), state: NativeSample.done(.task))
            }
            .frame(maxWidth: .infinity)
            IslandCompactDrawing(attributes: NativeSample.attributes(.forge), state: NativeSample.failed(.forge)).frame(maxWidth: .infinity)
            IslandCompactDrawing(attributes: NativeSample.attributes(.reply), state: waiting).frame(maxWidth: .infinity)
            Caption(text: "Expanded: done", dark: true)
            IslandExpandedDrawing(attributes: NativeSample.attributes(.reply), state: NativeSample.done(.reply))
            Caption(text: "Expanded: couldn't finish", dark: true)
            IslandExpandedDrawing(attributes: NativeSample.attributes(.task), state: NativeSample.failed(.task))
            Caption(text: "Lock Screen: a bot needs you mid-reply", dark: true)
            LockCardDrawing { ActivityLockView(attributes: NativeSample.attributes(.reply), state: waiting, hidingTitles: false) }
            Caption(text: "Call, muted", dark: true)
            IslandCompactDrawing(attributes: NativeSample.attributes(.call), state: muted).frame(maxWidth: .infinity)
        }
    }
}

/// Private mode: chat titles hidden on the Lock Screen and in the island.
struct ActivityPrivatePage: View {
    var body: some View {
        GalleryPage(title: "Private mode", dark: true) {
            Caption(text: "Lock Screen, titles hidden", dark: true)
            LockCardDrawing { ActivityLockView(attributes: NativeSample.attributes(.reply), state: NativeSample.running(.reply), hidingTitles: true) }
            LockCardDrawing { ActivityLockView(attributes: NativeSample.attributes(.render), state: NativeSample.running(.render), hidingTitles: true) }
            LockCardDrawing { ActivityLockView(attributes: NativeSample.attributes(.reply), state: NativeSample.done(.reply), hidingTitles: true) }
            Caption(text: "Expanded island, titles hidden", dark: true)
            IslandExpandedDrawing(attributes: NativeSample.attributes(.forge), state: NativeSample.running(.forge), hidingTitles: true)
            Caption(text: "Notifications below the activity", dark: true)
            NoticeBanner(notice: Notice(kind: .question, botID: "scout", botName: "Scout", title: "Bike shop launch", link: .bot("scout"), detailOverride: .hideTitles), time: "now")
            NoticeBanner(notice: Notice(kind: .replyReady, title: "Bike shop launch", link: .chat("c-bike"), detailOverride: .hideTitles), time: "12m")
        }
    }
}

// MARK: - Widget pages

/// A widget at its real size, on its own background, as the Home Screen shows it.
struct WidgetDrawing: View {
    let kind: KairosWidgetKind
    let family: WidgetFamily
    var snapshot = NativeSample.snapshot()

    private var size: CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        case .accessoryCircular: CGSize(width: 72, height: 72)
        case .accessoryRectangular: CGSize(width: 172, height: 76)
        default: CGSize(width: 300, height: 24)
        }
    }

    var body: some View {
        if family.isAccessory {
            KairosWidgetView(kind: kind, snapshot: snapshot, family: family, hidingTitles: false)
                .foregroundStyle(.white)
                .background {
                    // AccessoryWidgetBackground only draws on the Lock Screen; stand in for it here.
                    if family == .accessoryCircular, kind == .needsYou || kind == .quickActions {
                        Circle().fill(Color.white.opacity(0.16))
                    }
                }
                .frame(width: size.width, height: size.height, alignment: family == .accessoryInline ? .leading : .center)
                .environment(\.colorScheme, .dark)
        } else {
            KairosWidgetView(kind: kind, snapshot: snapshot, family: family, hidingTitles: false)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background { WidgetGround() }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
    }
}

struct WidgetGridPage: View {
    let title: String
    let kinds: [KairosWidgetKind]
    let family: WidgetFamily

    var body: some View {
        GalleryPage(title: title) {
            if family == .systemSmall {
                LazyVGrid(columns: [GridItem(.fixed(170), spacing: 22), GridItem(.fixed(170))], spacing: 22) {
                    ForEach(kinds, id: \.self) { kind in
                        VStack(spacing: 6) {
                            WidgetDrawing(kind: kind, family: family)
                            Text(kind.title).font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            } else {
                ForEach(kinds, id: \.self) { kind in
                    VStack(spacing: 6) {
                        WidgetDrawing(kind: kind, family: family)
                        Text(kind.title).font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Lock Screen widgets: circular, rectangular and inline, white on the wallpaper.
struct LockWidgetsPage: View {
    var body: some View {
        GalleryPage(title: "Lock Screen widgets", dark: true) {
            Caption(text: "Inline, above the clock", dark: true)
            VStack(alignment: .leading, spacing: 8) {
                WidgetDrawing(kind: .needsYou, family: .accessoryInline)
                WidgetDrawing(kind: .nextEvent, family: .accessoryInline)
                WidgetDrawing(kind: .spend, family: .accessoryInline)
            }
            Caption(text: "Circular", dark: true)
            HStack(spacing: 14) {
                ForEach([KairosWidgetKind.needsYou, .running, .spend, .usage], id: \.self) { kind in
                    WidgetDrawing(kind: kind, family: .accessoryCircular)
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                WidgetDrawing(kind: .quickActions, family: .accessoryCircular)
            }
            .frame(maxWidth: .infinity)
            Caption(text: "Rectangular", dark: true)
            LazyVGrid(columns: [GridItem(.fixed(172), spacing: 18), GridItem(.fixed(172))], alignment: .leading, spacing: 12) {
                ForEach([KairosWidgetKind.needsYou, .running, .team, .posts, .spend, .nextEvent, .usage, .desktop, .quickActions], id: \.self) { kind in
                    WidgetDrawing(kind: kind, family: .accessoryRectangular)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Notifications

/// A notification as iOS draws it. Bot notifications read as a message from the bot (its face, the app badge).
struct NoticeBanner: View {
    let notice: Notice
    var time = "now"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(notice.kind.fromBot ? notice.botName : "Kairos").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if notice.kind.level == .timeSensitive {
                        Label("Time Sensitive", systemImage: "clock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x8A5A12))
                    }
                    Text(time).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Text(notice.headline).font(.system(size: 15, weight: notice.kind.fromBot ? .regular : .semibold)).lineLimit(1)
                if !notice.subtitle.isEmpty {
                    Text(notice.subtitle).font(.system(size: 15, weight: .medium)).lineLimit(1)
                }
                Text(notice.body).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .foregroundStyle(Color(hex: 0x1B1612))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: 0xF3EADB, alpha: 0.86), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        if notice.kind.fromBot {
            ZStack(alignment: .bottomTrailing) {
                BotFace(bot: SampleData.bot(notice.botID), size: 34, stage: Color(hex: 0x1B1612))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: 0x1B1612), in: Circle())
                    .environment(\.colorScheme, .dark)
                AppIconMark(size: 17).offset(x: 4, y: 4)
            }
        } else {
            AppIconMark(size: 40)
        }
    }
}

/// The app icon as a notification shows it: Kip on night brown.
struct AppIconMark: View {
    var size: CGFloat

    var body: some View {
        Mascot(size: size * 0.8, stage: Palette.night)
            .frame(width: size, height: size)
            .background(Palette.night, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

nonisolated enum NoticeSamples {
    static let all: [Notice] = [
        Notice(kind: .approval, botID: "kip", botName: "Kip", title: "Weekly report", preview: "Send the report draft to your professor?", link: .approval(requestID: "a1", botID: "kip"), requestID: "a1"),
        Notice(kind: .question, botID: "scout", botName: "Scout", title: "Bike shop launch", preview: "Which topic should I start with?", link: .bot("scout"), requestID: "q1"),
        Notice(kind: .replyReady, title: "Bike shop launch", preview: "Three files ready: prices, page and plan.", link: .chat("c-bike")),
        Notice(kind: .workDone, botID: "ledger", botName: "Ledger", title: "File this week's receipts", link: .bot("ledger")),
        Notice(kind: .workFailed, botID: "ledger", botName: "Ledger", title: "File this week's receipts", link: .bot("ledger"), activityID: "run_task", activityKind: "task"),
        Notice(kind: .teamUpdate, botID: "producer", botName: "Producer", title: "Content team", preview: "Today's video is up, two drafts are ready.", link: .bot("content-team")),
        Notice(kind: .posted, title: "Five tools for small shops", fact: "YouTube (Private)", link: .area("studio")),
        Notice(kind: .needsTap, title: "Five tools for small shops", fact: "1 TikTok post needs your tap", link: .area("studio")),
        Notice(kind: .channelWarning, title: "Shop channel", link: .area("studio")),
        Notice(kind: .spendNear, fact: "82%", link: .home),
        Notice(kind: .spendCap, link: .home),
        Notice(kind: .spendUnknown, link: .home),
        Notice(kind: .event, title: "Report due", fact: "at 9:00", link: .area("calendar")),
        Notice(kind: .morningBrief, botID: "kip", botName: "Kip", link: .bot("kip")),
        Notice(kind: .forgeWaiting, title: "Mobile layout prototype", link: .area("forge")),
        Notice(kind: .usage, fact: "Claude", link: .home),
        Notice(kind: .missedCall, botID: "kip", botName: "Kip", link: .call("kip")),
    ]
}

struct NoticesPage: View {
    let title: String
    let notices: [Notice]

    var body: some View {
        GalleryPage(title: title, dark: true) {
            ForEach(Array(notices.enumerated()), id: \.offset) { index, notice in
                NoticeBanner(notice: notice, time: ["now", "2m", "12m", "1h"][index % 4])
            }
        }
    }
}

/// A held notification: Approve, Deny and an inline reply that sends from the Lock Screen.
struct NoticeActionsPage: View {
    @State private var reply = ""
    @State private var outcome: String?
    @FocusState private var typing: Bool

    var body: some View {
        let approval = NoticeSamples.all[0]
        let question = NoticeSamples.all[1]
        GalleryPage(title: "Notification actions", dark: true) {
            Caption(text: "Held: approval", dark: true)
            NoticeBanner(notice: approval)
            VStack(spacing: 0) {
                actionRow("Approve", "checkmark") { outcome = "Approved. Kip sends the draft." }
                actionRow("Deny", "xmark", destructive: true) { outcome = "Denied. Kip will not send it." }
                actionRow("Reply", "arrowshape.turn.up.left", last: true) { typing = true }
            }
            .background(Color(hex: 0xF3EADB, alpha: 0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .environment(\.colorScheme, .light)
            Caption(text: "Inline reply: question", dark: true)
            NoticeBanner(notice: question)
            HStack(spacing: 8) {
                TextField("Your answer", text: $reply)
                    .focused($typing)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0x1B1612))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.white.opacity(0.9), in: Capsule())
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: 44, height: 44)
                        .background(Palette.gold, in: Circle())
                }
                .accessibilityLabel("Send")
                .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let outcome {
                Text(outcome)
                    .font(KFont.ui(14, .medium))
                    .foregroundStyle(IslandInk.cream)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .animation(Motion.snappy, value: outcome)
    }

    private func send() {
        let words = reply.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return }
        outcome = "Sent to Scout: \(words)"
        reply = ""
        typing = false
    }

    private func actionRow(_ title: String, _ symbol: String, destructive: Bool = false, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack {
                Text(title).font(.system(size: 17))
                Spacer()
                Image(systemName: symbol).font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(destructive ? Color(hex: 0xC2412C) : Color(hex: 0x1B1612))
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .overlay(alignment: .bottom) {
            if !last { Color.black.opacity(0.12).frame(height: 0.5) }
        }
    }
}

/// The call minimized over Home: the pill at the top keeps the call one tap away.
struct CallPillPage: View {
    var body: some View {
        HomeView()
            .nativeLinks()
            .onAppear {
                CallCenter.shared.startCall(with: SampleData.kip, present: false)
            }
    }
}
