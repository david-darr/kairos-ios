import SwiftUI

// Reach me: where and when bots message and call you. Runs on sample data; the desktop
// connection replaces ReachMeStore later.
//
// Notifications on this phone are the native layer's NotificationSettingsScreen (on main).
// NotificationsRowDestination is the slot for it: at merge, the lead points it there.

/// Lead: at merge, make this body `NotificationSettingsScreen()`.
struct NotificationsRowDestination: View {
    var body: some View {
        SettingsPage("Notifications", subtitle: "Which alerts this phone shows and how private they are.") {
            NoteText(text: "Notification settings arrive with the native layer in the next build.")
        }
    }
}

// MARK: - Reach me sample store

nonisolated enum ReachMeKind: Hashable, Sendable { case message, call }

nonisolated struct ReachMeChannel: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let detail: String
    var ready: Bool
}

nonisolated struct ReachMeLogEntry: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String
    var delivered: Bool
}

/// Where bots reach you: the two orders, quiet hours, each bot's choice, the one STOP and the log.
/// The Discord bot page reads and sets the first way to call you from here.
@Observable
final class ReachMeStore {
    static let shared = ReachMeStore()

    let messageChannels: [ReachMeChannel] = [
        ReachMeChannel(id: "app", label: "Kairos app", detail: "A notification on this iPhone.", ready: true),
        ReachMeChannel(id: "telegram", label: "Telegram", detail: "From your Telegram channel.", ready: true),
        ReachMeChannel(id: "discord", label: "Discord", detail: "A direct message from your Discord bot.", ready: true),
        ReachMeChannel(id: "whatsapp", label: "WhatsApp", detail: "From your WhatsApp channel.", ready: true),
        ReachMeChannel(id: "imessage", label: "iMessage", detail: "Needs an iMessage channel.", ready: false),
        ReachMeChannel(id: "signal", label: "Signal", detail: "Needs a Signal channel.", ready: false),
        ReachMeChannel(id: "sms", label: "Text message", detail: "To your mobile, from your phone line.", ready: true),
    ]

    /// Ids match the Discord page's "When a bot calls you" choices.
    let callChannels: [ReachMeChannel] = [
        ReachMeChannel(id: "app", label: "In the Kairos app", detail: "A ring in this app. On a locked iPhone it is a notification.", ready: true),
        ReachMeChannel(id: "phone", label: "On my phone", detail: "A real phone call to your mobile, from your phone line.", ready: true),
        ReachMeChannel(id: "discord", label: "In my Discord voice channel", detail: "Your Discord bot joins its voice channel.", ready: false),
        ReachMeChannel(id: "telegram", label: "As a Telegram voice message", detail: "A voice note in Telegram.", ready: true),
    ]

    var messageOrder: [String] = ["app", "telegram", "discord"]
    var callOrder: [String] = ["app", "phone"]

    /// Nil while bots may reach you; otherwise who paused it and when.
    var pausedNote: String?

    var quietOn = true
    var quietFrom: Date = ReachMeStore.time(22, 0)
    var quietUntil: Date = ReachMeStore.time(7, 30)

    /// Per bot: "default" (your order), "never", or one channel id.
    var botMessage: [String: String] = ["ledger": "never", "scout": "telegram"]
    var botCall: [String: String] = ["wisp": "never"]

    var log: [ReachMeLogEntry] = [
        ReachMeLogEntry(id: "l1", title: "Scout messaged you: Telegram", detail: "Today 9:12 · skipped Kairos app: this iPhone was offline", delivered: true),
        ReachMeLogEntry(id: "l2", title: "Kip called you: In the Kairos app", detail: "Today 8:01 · Morning brief", delivered: true),
        ReachMeLogEntry(id: "l3", title: "Ledger called you: not delivered", detail: "Yesterday 22:40 · quiet hours", delivered: false),
        ReachMeLogEntry(id: "l4", title: "Producer messaged you: not delivered", detail: "Mon 18:05 · skipped Telegram: the channel was off · skipped Discord: not connected", delivered: false),
    ]

    static func time(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    func channels(_ kind: ReachMeKind) -> [ReachMeChannel] {
        kind == .message ? messageChannels : callChannels
    }

    func order(_ kind: ReachMeKind) -> [String] {
        kind == .message ? messageOrder : callOrder
    }

    private func setOrder(_ kind: ReachMeKind, _ order: [String]) {
        withAnimation(Motion.snappy) {
            if kind == .message { messageOrder = order } else { callOrder = order }
        }
    }

    func move(_ kind: ReachMeKind, _ id: String, by step: Int) {
        var list = order(kind)
        guard let at = list.firstIndex(of: id), at + step >= 0, at + step < list.count else { return }
        list.swapAt(at, at + step)
        setOrder(kind, list)
    }

    func setUsed(_ kind: ReachMeKind, _ id: String, _ used: Bool) {
        var list = order(kind).filter { $0 != id }
        if used { list.append(id) }
        setOrder(kind, list)
    }

    /// The first way bots call you. The Discord bot page shows and changes this.
    var firstCall: String {
        get { callOrder.first ?? "" }
        set {
            if newValue.isEmpty {
                setOrder(.call, [])
            } else {
                setOrder(.call, [newValue] + callOrder.filter { $0 != newValue })
            }
        }
    }

    var quietNow: Bool {
        guard quietOn else { return false }
        let calendar = Calendar.current
        func minutes(_ date: Date) -> Int { calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date) }
        let now = minutes(Date()), from = minutes(quietFrom), until = minutes(quietUntil)
        if from == until { return false }
        return from < until ? (now >= from && now < until) : (now >= from || now < until)
    }

    func label(for id: String, kind: ReachMeKind) -> String {
        channels(kind).first { $0.id == id }?.label ?? id
    }
}

// MARK: - Reach me

struct ReachMeScreen: View {
    var startPaused = false

    @Bindable private var store = ReachMeStore.shared

    private let bots = SampleData.allBots.filter { $0.members.isEmpty }

    var body: some View {
        SettingsPage("Reach me", subtitle: "Where your bots reach you, in the order you choose. A bot tries the first way that is set up, then the next.") {
            SettingsGroup("Messages and calls from bots") {
                YouToggleRow(title: store.pausedNote == nil ? "Bots may reach me" : "Paused: bots will not message or call you", detail: pauseDetail, symbol: "hand.raised", isOn: Binding(get: { store.pausedNote == nil }, set: { on in
                    store.pausedNote = on ? nil : "Paused \(Date().formatted(date: .abbreviated, time: .shortened)) here."
                    YouStore.shared.say(on ? "Bots can reach you again." : "Paused everywhere.")
                }))
            }
            .arrives(0)

            SettingsGroup("Message me", footer: "For results and things to look at soon. The first way here that is set up and takes it wins.") {
                ReachMeOrderList(kind: .message)
            }
            .arrives(1)

            SettingsGroup("Call me", footer: "For something urgent, or when you asked a bot to call. The first way here is also \"When a bot calls you\" on a Discord bot page. When you name a way yourself, the bot tries that one first. A daily limit or a busy line is reported to the bot, not worked around.") {
                ReachMeOrderList(kind: .call)
            }
            .arrives(2)

            SettingsGroup("Quiet hours", footer: "In your own time zone. Messages wait until quiet hours end; calls are not made.") {
                YouToggleRow(title: "Quiet hours", detail: store.quietNow ? "It is quiet hours now." : nil, symbol: "moon", isOn: $store.quietOn)
                ReachMeTimeRow(title: "From", time: $store.quietFrom)
                ReachMeTimeRow(title: "Until", time: $store.quietUntil)
            }
            .arrives(3)

            SettingsGroup("Each bot", footer: "A bot can use your order, only one way, or never reach out.") {
                ForEach(bots) { bot in
                    ReachMeBotRow(bot: bot)
                }
            }
            .arrives(4)

            SettingsGroup("What reaches you, honestly") {
                Text("Only a real phone call (Phone line) rings like a call on a locked iPhone. A Kairos ring on a phone is a notification, a plain banner, not a call screen. Telegram, WhatsApp, Discord, iMessage, Signal and texts arrive as those apps' own notifications. Nothing works when your desktop is off or asleep: every message and call starts there.")
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                YouNavRow(title: "Phone line", symbol: "phone", to: .phone)
            }
            .arrives(5)

            SettingsGroup("Recent") {
                if store.log.isEmpty {
                    EmptyRow(text: "Nothing sent yet.")
                } else {
                    ForEach(store.log) { entry in
                        HStack(spacing: 8) {
                            RowLabel(title: entry.title, detail: entry.detail, symbol: entry.delivered ? "checkmark" : "xmark", tint: entry.delivered ? Palette.success : Palette.danger)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(minHeight: 52)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .arrives(6)
        }
        .onAppear {
            if startPaused && store.pausedNote == nil {
                store.pausedNote = "Paused Nov 11, 21:04 by a STOP reply on Telegram."
            }
        }
    }

    private var pauseDetail: String {
        if let note = store.pausedNote {
            return "\(note) Reply START anywhere, or turn this on."
        }
        return "Reply STOP on any channel (Telegram, WhatsApp, Discord, iMessage, Signal or a text) to pause every bot on every channel at once. START turns it back on."
    }
}

/// The order editor: chosen ways first, numbered, with Up, Down and a switch; then the unused ones.
private struct ReachMeOrderList: View {
    let kind: ReachMeKind
    private let store = ReachMeStore.shared

    var body: some View {
        let order = store.order(kind)
        let channels = store.channels(kind)
        let rest = channels.map(\.id).filter { !order.contains($0) }
        ForEach(order + rest, id: \.self) { id in
            if let channel = channels.first(where: { $0.id == id }) {
                row(channel, at: order.firstIndex(of: id), count: order.count)
            }
        }
    }

    private func isReady(_ channel: ReachMeChannel) -> Bool {
        if kind == .call && channel.id == "discord" {
            return ChannelStore.shared.bots.contains { !$0.voiceChannelID.isEmpty }
        }
        return channel.ready
    }

    private func row(_ channel: ReachMeChannel, at: Int?, count: Int) -> some View {
        let ready = isReady(channel)
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(at.map { "\($0 + 1). \(channel.label)" } ?? channel.label)
                        .font(KFont.ui(16))
                        .foregroundStyle(at == nil ? Palette.inkDim : Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    StatusPill(text: ready ? "Ready" : "Not set up", tone: ready ? .ok : .muted)
                }
                Text(channel.detail)
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let at {
                moveButton(channel, symbol: "arrow.up", step: -1, enabled: at > 0)
                moveButton(channel, symbol: "arrow.down", step: 1, enabled: at < count - 1)
            }
            Toggle("Use \(channel.label)", isOn: Binding(get: { at != nil }, set: { used in
                Haptics.select()
                store.setUsed(kind, channel.id, used)
            }))
            .labelsHidden()
            .tint(Palette.gold)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
    }

    private func moveButton(_ channel: ReachMeChannel, symbol: String, step: Int, enabled: Bool) -> some View {
        Button {
            Haptics.tap()
            store.move(kind, channel.id, by: step)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .accessibilityLabel("Move \(channel.label) \(step < 0 ? "up" : "down")")
    }
}

/// A time of day, hour and minute.
private struct ReachMeTimeRow: View {
    let title: String
    @Binding var time: Date

    var body: some View {
        HStack {
            Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
            Spacer()
            DatePicker(title, selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(Palette.gold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
    }
}

/// One bot: how it may message you and how it may call you.
private struct ReachMeBotRow: View {
    let bot: Bot
    private let store = ReachMeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                BotFace(bot: bot, size: 30)
                Text(bot.name).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                Spacer()
            }
            HStack(spacing: 8) {
                choice(.message)
                choice(.call)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func value(_ kind: ReachMeKind) -> String {
        (kind == .message ? store.botMessage[bot.id] : store.botCall[bot.id]) ?? "default"
    }

    private func setValue(_ kind: ReachMeKind, _ value: String) {
        Haptics.select()
        withAnimation(Motion.snappy) {
            if kind == .message {
                store.botMessage[bot.id] = value == "default" ? nil : value
            } else {
                store.botCall[bot.id] = value == "default" ? nil : value
            }
        }
    }

    private func title(_ kind: ReachMeKind, _ value: String) -> String {
        switch value {
        case "default": "Your order"
        case "never": "Never"
        default: "Only \(store.label(for: value, kind: kind))"
        }
    }

    private func choice(_ kind: ReachMeKind) -> some View {
        let options = ["default", "never"] + store.channels(kind).map(\.id)
        let current = value(kind)
        let name = kind == .message ? "Messages" : "Calls"
        return Menu {
            Picker(name, selection: Binding(get: { current }, set: { setValue(kind, $0) })) {
                ForEach(options, id: \.self) { option in
                    Text(title(kind, option)).tag(option)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(KFont.ui(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Palette.inkFaint)
                HStack(spacing: 4) {
                    Text(title(kind, current))
                        .font(KFont.ui(14, .medium, relativeTo: .footnote))
                        .foregroundStyle(current == "never" ? Palette.danger : Palette.goldText)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(Palette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(bot.name): \(name.lowercased()), \(title(kind, current))")
    }
}

// MARK: - Debug pictures

enum NotifyDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "notify": return AnyView(NotificationsRowDestination())
        case "reachme": return AnyView(ReachMeScreen())
        case "reachme-paused": return AnyView(ReachMeScreen(startPaused: true))
        default: return nil
        }
    }
}
