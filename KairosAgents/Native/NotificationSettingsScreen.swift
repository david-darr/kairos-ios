import SwiftUI
import UIKit
import UserNotifications

/// Notifications, Live Activities and widgets: what may reach the phone and how much it says.
/// Opened from iOS Settings ("Kairos notification settings"), and linkable from You.
struct NotificationSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    private var notifications = NativeNotifications.shared
    @State private var groups: [NoticeGroup: Bool] = Dictionary(uniqueKeysWithValues: NoticeGroup.allCases.map { ($0, $0.isOn) })
    @State private var detail = NativeSettings.detail
    @State private var liveActivities = NativeSettings.liveActivitiesOn
    @State private var widgets = NativeSettings.widgetsShareData
    @State private var sent = false

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if notifications.status != .authorized && notifications.status != .provisional {
                    NotificationAskCard()
                        .arrives(0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "What a notification says")
                    VStack(spacing: 0) {
                        ForEach(Array(NoticeDetail.offered.enumerated()), id: \.element) { index, level in
                            Button {
                                Haptics.select()
                                withAnimation(Motion.snappy) { detail = level }
                                NativeSettings.detail = level
                                // The desktop leaves chat titles out of pushes when this is Private.
                                Task { await PushBridge.detailChanged() }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: detail == level ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(detail == level ? Palette.gold : Palette.inkFaint)
                                        .contentTransition(.symbolEffect(.replace))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(level.title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                                        Text(level.about).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle(scale: 0.98))
                            .accessibilityAddTraits(detail == level ? .isSelected : [])
                            .overlay(alignment: .bottom) {
                                if index < NoticeDetail.offered.count - 1 { Palette.line.frame(height: 1).padding(.leading, 48) }
                            }
                        }
                    }
                    .kCard()
                }
                .arrives(1)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Tell me when")
                    VStack(spacing: 0) {
                        ForEach(Array(NoticeGroup.allCases.enumerated()), id: \.element) { index, group in
                            toggleRow(group.title, symbol: group.symbol, last: index == NoticeGroup.allCases.count - 1,
                                      isOn: Binding(get: { groups[group] ?? true }, set: { value in
                                          groups[group] = value
                                          group.isOn = value
                                      }))
                        }
                    }
                    .kCard()
                }
                .arrives(2)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Lock Screen and Home Screen")
                    VStack(spacing: 0) {
                        toggleRow("Live Activities", symbol: "iphone", last: false, isOn: Binding(get: { liveActivities }, set: { value in
                            liveActivities = value
                            NativeSettings.liveActivitiesOn = value
                        }))
                        toggleRow("Widgets show my numbers", symbol: "square.grid.2x2", last: true, isOn: Binding(get: { widgets }, set: { value in
                            widgets = value
                            NativeSettings.widgetsShareData = value
                            WidgetSync.publish()
                        }))
                    }
                    .kCard()
                    Text("Live Activities follow replies, tasks, team cycles, uploads, Forge builds and calls. Widgets keep counts and titles, never messages.")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.horizontal, 4)
                }
                .arrives(3)

                Button {
                    Haptics.tap()
                    sent = true
                    Task {
                        await NativeNotifications.shared.post(Notice(kind: .question, botID: "scout", botName: "Scout", title: "Bike shop launch",
                                                                     preview: "Which topic should I start with?", link: .bot("scout")), after: 3)
                    }
                } label: {
                    Label(sent ? "Sent. It arrives in a few seconds." : "Send a test notification", systemImage: sent ? "checkmark" : "bell.badge")
                        .font(KFont.ui(15, .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .kCard(radius: 24)
                }
                .buttonStyle(PressStyle())
                .disabled(sent)
                .arrives(4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .kScreen()
        .task { await notifications.refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            GlassIconButton(symbol: "chevron.left", label: "Back") { dismiss() }
            Text("Notifications").font(KFont.ui(20, .semibold)).foregroundStyle(Palette.ink)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background { HeaderFade() }
    }

    private func toggleRow(_ title: String, symbol: String, last: Bool, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.goldText).frame(width: 26)
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
            }
        }
        .tint(Palette.gold)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 54) }
        }
    }
}

/// Asks for notification permission in context: says why first, then shows the iOS prompt.
/// Other screens can show it where a person has just done something worth being told about.
struct NotificationAskCard: View {
    private var notifications = NativeNotifications.shared

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Mascot(pose: .needs, size: 54, live: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(notifications.status == .denied ? "Notifications are off" : "Know when a bot needs you")
                        .font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                    Text(notifications.status == .denied
                         ? "Turn them on in iOS Settings to hear about approvals, finished work and calls."
                         : "Approve, deny or reply from the Lock Screen. Kairos says who and what kind, never the message.")
                        .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            GoldButton(title: notifications.status == .denied ? "Open iOS Settings" : "Turn on notifications") {
                Haptics.tap()
                if notifications.status == .denied {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                } else {
                    Task { await notifications.requestPermission() }
                }
            }
        }
        .padding(18)
        .kCard(radius: 24, raised: true)
    }
}
