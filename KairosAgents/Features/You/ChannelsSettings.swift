import SwiftUI
import UIKit

// Channels: Discord bots and every other messaging connector in one list, each with its own page,
// a platform picker, the add forms, and the Discord bot page with its channel overrides.
// Everything runs on sample data in ChannelStore; the desktop connection replaces it later.

// MARK: - Platforms

nonisolated enum ChannelFieldKind: Hashable, Sendable { case text, number, secret, toggle, multiline }

nonisolated struct ChannelField: Hashable, Sendable {
    let key: String
    let label: String
    var kind: ChannelFieldKind = .text
    var required = true
    var placeholder = ""
    var help: String? = nil
    /// Filled in when a new channel is added.
    var preset = ""
}

nonisolated enum ChannelCategory: Hashable, Sendable, CaseIterable {
    case twoWay, webhook, sendOnly

    var title: String {
        switch self {
        case .twoWay: "Two-way"
        case .webhook: "Two-way through a webhook"
        case .sendOnly: "Send only"
        }
    }

    var detail: String {
        switch self {
        case .twoWay: "Talk to Kairos and your agents. No public address needed."
        case .webhook: "The platform calls Kairos, so Kairos must be reachable from the internet to receive. Sending works regardless."
        case .sendOnly: "For task results and agent notifications. No bot needed."
        }
    }
}

nonisolated struct ChannelPlatform: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let badge: String
    let tint: UInt32
    let about: String
    let category: ChannelCategory
    var fields: [ChannelField] = []
    /// Shows a webhook address on its page.
    var webhook = false
    var senderHelp = "One per line, or separated by commas."
    var steps: [String] = []

    var twoWay: Bool { category != .sendOnly }
}

nonisolated enum ChannelCatalog {
    static let models = ["", "Claude Sonnet", "Claude Opus", "GPT-6.1 Sol", "Qwen local"]

    static let discordSteps = [
        "On a computer, open the Discord Developer Portal and create a New Application.",
        "Open Bot in the sidebar, tap Reset Token and copy it.",
        "Under Privileged Gateway Intents, turn on Message Content Intent.",
        "Under OAuth2, URL Generator, tick \"bot\" with Send Messages and Read Message History, then open the address it makes to invite the bot to your server.",
    ]

    private static func webhookSteps(_ app: String) -> [String] {
        [
            "In \(app), open the channel's settings and add an incoming webhook.",
            "Copy the webhook address it gives you.",
            "Paste it here, tap Add, then Send test on the channel's page.",
        ]
    }

    static let platforms: [ChannelPlatform] = [
        ChannelPlatform(id: "discord", label: "Discord", badge: "D", tint: Palette.botLilac, about: "A Discord bot in your server or DMs.", category: .twoWay, steps: discordSteps),
        ChannelPlatform(
            id: "telegram", label: "Telegram", badge: "T", tint: Palette.botPowder, about: "A Telegram bot you message directly.", category: .twoWay,
            fields: [
                ChannelField(key: "bot_token", label: "Bot token", kind: .secret),
                ChannelField(key: "default_chat_id", label: "Default chat ID", required: false, placeholder: "55501234", help: "Where results go when no chat is named."),
            ],
            senderHelp: "Telegram user IDs, one per line.",
            steps: [
                "In Telegram, message BotFather and send /newbot.",
                "Pick a name and a username, then copy the token it sends you.",
                "Paste the token here. Send your new bot a message so it can answer you.",
                "Add your Telegram user ID to the allowed senders.",
            ]
        ),
        ChannelPlatform(
            id: "whatsapp", label: "WhatsApp", badge: "W", tint: Palette.botSage, about: "WhatsApp Cloud API, on your own Meta app.", category: .twoWay,
            fields: [
                ChannelField(key: "phone_number_id", label: "Phone number ID"),
                ChannelField(key: "access_token", label: "Access token", kind: .secret),
                ChannelField(key: "app_secret", label: "App secret", kind: .secret),
                ChannelField(key: "verify_token", label: "Verify token", kind: .secret),
                ChannelField(key: "default_to", label: "Default recipient", required: false, placeholder: "+15550100142"),
                ChannelField(key: "template_name", label: "Template name", required: false, help: "Used to start a chat after 24 hours of silence."),
            ],
            webhook: true,
            senderHelp: "Phone numbers with the country code, one per line.",
            steps: [
                "Create an app in Meta for Developers and add the WhatsApp product.",
                "Copy the phone number ID and a permanent access token.",
                "Copy the app secret from the app's basic settings.",
                "Set the webhook address on this page in Meta, with a verify token you make up, and enter the same token here.",
            ]
        ),
        ChannelPlatform(
            id: "slack", label: "Slack", badge: "S", tint: Palette.botRose, about: "A Slack app in your workspace.", category: .twoWay,
            fields: [
                ChannelField(key: "app_token", label: "App token", kind: .secret, placeholder: "xapp-..."),
                ChannelField(key: "bot_token", label: "Bot token", kind: .secret, placeholder: "xoxb-..."),
                ChannelField(key: "default_channel", label: "Default channel", required: false, placeholder: "#general"),
            ],
            senderHelp: "Slack member IDs, one per line.",
            steps: [
                "Create a Slack app for your workspace and turn on Socket Mode.",
                "Make an app-level token with connections:write and copy it.",
                "Add the chat:write and message reading scopes, install the app and copy the bot token.",
                "Invite the app to the channels it should use.",
            ]
        ),
        ChannelPlatform(
            id: "signal", label: "Signal", badge: "Si", tint: Palette.botPowder, about: "Through a Signal REST server you run.", category: .twoWay,
            fields: [
                ChannelField(key: "api_url", label: "Server address", placeholder: "http://100.64.0.12:8080"),
                ChannelField(key: "number", label: "Bot number", placeholder: "+15550100111"),
            ],
            senderHelp: "Phone numbers with the country code, one per line.",
            steps: [
                "Run the signal-cli REST server on a computer that stays on.",
                "Register or link a number for the bot there.",
                "Enter the server's address and the bot's number here.",
            ]
        ),
        ChannelPlatform(
            id: "imessage", label: "iMessage", badge: "iM", tint: Palette.botSand, about: "Through BlueBubbles on a Mac.", category: .twoWay,
            fields: [
                ChannelField(key: "server_url", label: "Server address", placeholder: "http://100.64.0.12:1234"),
                ChannelField(key: "password", label: "Server password", kind: .secret),
            ],
            senderHelp: "Phone numbers or email addresses, one per line.",
            steps: [
                "Install the BlueBubbles server on a Mac signed in to iMessage.",
                "Keep that Mac on and awake.",
                "Copy the server address and password from BlueBubbles and enter them here.",
            ]
        ),
        ChannelPlatform(
            id: "matrix", label: "Matrix", badge: "Mx", tint: Palette.botSage, about: "A Matrix account on any homeserver.", category: .twoWay,
            fields: [
                ChannelField(key: "homeserver", label: "Homeserver", placeholder: "https://matrix.example.com"),
                ChannelField(key: "user_id", label: "Bot user ID", placeholder: "@kairos:example.com"),
                ChannelField(key: "access_token", label: "Access token", kind: .secret),
            ],
            senderHelp: "Matrix user IDs, one per line.",
            steps: [
                "Make an account for the bot on your homeserver.",
                "Sign in as the bot and copy its access token from the client settings.",
                "Enter the homeserver, the bot's user ID and the token here.",
            ]
        ),
        ChannelPlatform(
            id: "mattermost", label: "Mattermost", badge: "Mm", tint: Palette.botPowder, about: "A bot account on your Mattermost server.", category: .twoWay,
            fields: [
                ChannelField(key: "server_url", label: "Server address", placeholder: "https://chat.example.com"),
                ChannelField(key: "token", label: "Bot token", kind: .secret),
            ],
            senderHelp: "Mattermost usernames, one per line.",
            steps: [
                "In Mattermost, open Integrations, then Bot Accounts, and add a bot.",
                "Copy its token.",
                "Enter the server address and the token here.",
            ]
        ),
        ChannelPlatform(
            id: "irc", label: "IRC", badge: "#", tint: Palette.botGold, about: "A nickname on an IRC server.", category: .twoWay,
            fields: [
                ChannelField(key: "server", label: "Server", placeholder: "irc.example.net"),
                ChannelField(key: "port", label: "Port", kind: .number, preset: "6697"),
                ChannelField(key: "tls", label: "Use TLS", kind: .toggle, required: false, preset: "true"),
                ChannelField(key: "nick", label: "Nickname", placeholder: "kairos-bot"),
                ChannelField(key: "channels", label: "Channels", required: false, placeholder: "#shop", help: "Separated by commas."),
            ],
            senderHelp: "Nicknames, one per line.",
            steps: [
                "Pick a server and a nickname for the bot.",
                "Most servers use TLS on port 6697.",
                "List the channels it should join, then add yourself as an allowed sender.",
            ]
        ),
        ChannelPlatform(
            id: "email", label: "Email", badge: "@", tint: Palette.botSand, about: "An email address Kairos reads and answers.", category: .twoWay,
            fields: [
                ChannelField(key: "address", label: "Address", placeholder: "bot@example.com"),
                ChannelField(key: "password", label: "Password", kind: .secret, help: "Use an app password if your provider offers one."),
                ChannelField(key: "imap_host", label: "IMAP host", placeholder: "imap.example.com"),
                ChannelField(key: "imap_port", label: "IMAP port", kind: .number, preset: "993"),
                ChannelField(key: "smtp_host", label: "SMTP host", placeholder: "smtp.example.com"),
                ChannelField(key: "smtp_port", label: "SMTP port", kind: .number, preset: "465"),
            ],
            senderHelp: "Email addresses, one per line.",
            steps: [
                "Use a separate address for the bot if you can.",
                "Make an app password in your email provider's security settings.",
                "Copy the IMAP and SMTP hosts from your provider's help pages.",
            ]
        ),
        ChannelPlatform(
            id: "sms", label: "Text messages", badge: "Tx", tint: Palette.botRose, about: "Texts through your own Twilio number.", category: .twoWay,
            fields: [
                ChannelField(key: "account_sid", label: "Account SID", placeholder: "AC..."),
                ChannelField(key: "auth_token", label: "Auth token", kind: .secret),
                ChannelField(key: "from_number", label: "From number", placeholder: "+15550100199"),
                ChannelField(key: "public_url", label: "Public address", placeholder: "https://kairos-desk.tailnet-example.ts.net", help: "An https address Twilio can reach."),
            ],
            webhook: true,
            senderHelp: "Phone numbers with the country code, one per line.",
            steps: [
                "In your Twilio account, copy the account SID and auth token.",
                "Buy or pick a number that can send texts.",
                "Set the webhook address on this page as the number's incoming message webhook.",
            ]
        ),
        ChannelPlatform(
            id: "line", label: "LINE", badge: "L", tint: Palette.botSage, about: "A LINE Messaging API channel.", category: .twoWay,
            fields: [
                ChannelField(key: "channel_secret", label: "Channel secret", kind: .secret),
                ChannelField(key: "access_token", label: "Channel access token", kind: .secret),
            ],
            webhook: true,
            senderHelp: "LINE user IDs, one per line.",
            steps: [
                "In the LINE Developers console, make a Messaging API channel.",
                "Copy the channel secret and issue a channel access token.",
                "Set the webhook address on this page in the console and turn on Use webhook.",
            ]
        ),
        ChannelPlatform(
            id: "webhook", label: "Webhook", badge: "Wh", tint: Palette.botGold, about: "Any service that can call an address and receive replies.", category: .webhook,
            fields: [
                ChannelField(key: "secret", label: "Shared secret", kind: .secret),
                ChannelField(key: "reply_url", label: "Reply address", required: false, placeholder: "https://example.com/kairos-reply", help: "Where Kairos posts its replies."),
            ],
            webhook: true,
            senderHelp: "Sender names your service sends, one per line.",
            steps: [
                "Give your service the webhook address on this page.",
                "Make up a shared secret and enter it in both places.",
                "Add a reply address if your service should get answers back.",
            ]
        ),
        ChannelPlatform(
            id: "ntfy", label: "ntfy", badge: "n", tint: Palette.botPowder, about: "Push alerts through ntfy.", category: .sendOnly,
            fields: [
                ChannelField(key: "server", label: "Server", preset: "https://ntfy.sh"),
                ChannelField(key: "topic", label: "Topic", placeholder: "shop-alerts-7f3k", help: "Pick a name that is hard to guess."),
                ChannelField(key: "token", label: "Access token", kind: .secret, required: false),
            ],
            steps: [
                "Install the ntfy app on your phone.",
                "Make up a topic name that is hard to guess and subscribe to it in the app.",
                "Enter the same topic here.",
            ]
        ),
        ChannelPlatform(id: "teams", label: "Microsoft Teams", badge: "Ms", tint: Palette.botLilac, about: "Posts to a Teams channel.", category: .sendOnly,
                        fields: [ChannelField(key: "webhook_url", label: "Webhook address", placeholder: "https://example.webhook.office.com/...")], steps: webhookSteps("Teams")),
        ChannelPlatform(id: "googlechat", label: "Google Chat", badge: "G", tint: Palette.botSage, about: "Posts to a Google Chat space.", category: .sendOnly,
                        fields: [ChannelField(key: "webhook_url", label: "Webhook address", placeholder: "https://chat.googleapis.com/...")], steps: webhookSteps("Google Chat")),
        ChannelPlatform(id: "feishu", label: "Feishu / Lark", badge: "F", tint: Palette.botPowder, about: "Posts to a Feishu or Lark group.", category: .sendOnly,
                        fields: [ChannelField(key: "webhook_url", label: "Webhook address")], steps: webhookSteps("Feishu or Lark")),
        ChannelPlatform(id: "dingtalk", label: "DingTalk", badge: "Dt", tint: Palette.botSand, about: "Posts to a DingTalk group.", category: .sendOnly,
                        fields: [ChannelField(key: "webhook_url", label: "Webhook address")], steps: webhookSteps("DingTalk")),
        ChannelPlatform(id: "wecom", label: "WeCom", badge: "We", tint: Palette.botSage, about: "Posts to a WeCom group.", category: .sendOnly,
                        fields: [ChannelField(key: "webhook_url", label: "Webhook address")], steps: webhookSteps("WeCom")),
    ]

    static func platform(_ kind: String) -> ChannelPlatform? {
        platforms.first { $0.id == kind }
    }

    static func senders(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func modelLabel(_ model: String, empty: String) -> String {
        model.isEmpty ? empty : model
    }

    static let webhookBase = "https://kairos-desk.tailnet-example.ts.net/api/connectors/"
}

// MARK: - Sample records

nonisolated struct ChannelConnector: Identifiable, Hashable, Sendable {
    let id: String
    var kind: String
    var name: String
    var enabled: Bool
    /// listening, connected, starting, error, off, or the desktop's own word.
    var state: String
    var stateDetail = ""
    var values: [String: String] = [:]
    var savedSecrets: Set<String> = []
    var senders: [String] = []
    var anyone = false
    var model = ""
}

nonisolated enum ChannelOverrideMode: String, CaseIterable, Hashable, Sendable {
    case normal, open, silent

    var title: String {
        switch self {
        case .normal: "Normal"
        case .open: "Open"
        case .silent: "Silent"
        }
    }

    var detail: String {
        switch self {
        case .normal: "The allow list applies"
        case .open: "Anyone can talk"
        case .silent: "Never replies"
        }
    }
}

nonisolated struct ChannelOverride: Identifiable, Hashable, Sendable {
    let id: String
    var channelID: String
    var label: String
    var mode: ChannelOverrideMode
}

nonisolated struct ChannelDiscordBot: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var allowedUserID: String
    var live: Bool
    var model: String
    var voiceChannelID = ""
    var overrides: [ChannelOverride] = []
}

/// What a channel form holds while it is being edited.
nonisolated struct ChannelForm: Hashable, Sendable {
    var name = ""
    var values: [String: String] = [:]
    var senders = ""
    var anyone = false
    var model = ""
}

/// The channel list, shared by every Channels screen (and Reach me, for Discord voice).
@Observable
final class ChannelStore {
    static let shared = ChannelStore()

    var bots: [ChannelDiscordBot] = [
        ChannelDiscordBot(
            id: "d-kairos", name: "Kairos", allowedUserID: "123456789012345678", live: true, model: "Claude Sonnet",
            overrides: [
                ChannelOverride(id: "o-orders", channelID: "987654321098765432", label: "shop-orders", mode: .open),
                ChannelOverride(id: "o-news", channelID: "987654321098765433", label: "announcements", mode: .silent),
            ]
        ),
        ChannelDiscordBot(id: "d-helper", name: "Shop helper", allowedUserID: "", live: false, model: ""),
    ]

    var connectors: [ChannelConnector] = [
        ChannelConnector(id: "c-telegram", kind: "telegram", name: "Telegram", enabled: true, state: "listening",
                         values: ["default_chat_id": "55501234"], savedSecrets: ["bot_token"], senders: ["55501234"], model: "Claude Sonnet"),
        ChannelConnector(id: "c-whatsapp", kind: "whatsapp", name: "Shop WhatsApp", enabled: true, state: "error",
                         stateDetail: "The access token expired. Paste a new one and save.",
                         values: ["phone_number_id": "100200300400500", "default_to": "+15550100142"],
                         savedSecrets: ["access_token", "app_secret", "verify_token"], senders: ["+15550100142", "+15550100143"]),
        ChannelConnector(id: "c-ntfy", kind: "ntfy", name: "Phone alerts", enabled: true, state: "connected",
                         values: ["server": "https://ntfy.sh", "topic": "shop-alerts-7f3k"]),
        ChannelConnector(id: "c-email", kind: "email", name: "Shop inbox", enabled: false, state: "off",
                         values: ["address": "bot@example.com", "imap_host": "imap.example.com", "imap_port": "993", "smtp_host": "smtp.example.com", "smtp_port": "465"],
                         savedSecrets: ["password"], senders: ["sam@example.com"]),
        ChannelConnector(id: "c-webhook", kind: "webhook", name: "Order form", enabled: true, state: "starting",
                         values: ["reply_url": "https://example.com/kairos-reply"], savedSecrets: ["secret"]),
    ]

    var checkedAt = Date()

    func connector(_ id: String) -> ChannelConnector? { connectors.first { $0.id == id } }
    func bot(_ id: String) -> ChannelDiscordBot? { bots.first { $0.id == id } }

    func updateConnector(_ id: String, _ change: (inout ChannelConnector) -> Void) {
        guard let index = connectors.firstIndex(where: { $0.id == id }) else { return }
        change(&connectors[index])
    }

    func updateBot(_ id: String, _ change: (inout ChannelDiscordBot) -> Void) {
        guard let index = bots.firstIndex(where: { $0.id == id }) else { return }
        change(&bots[index])
    }

    func setEnabled(_ id: String, _ on: Bool) {
        withAnimation(Motion.snappy) {
            updateConnector(id) { record in
                record.enabled = on
                record.state = on ? "starting" : "off"
                record.stateDetail = ""
            }
        }
        if on {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                settle(id)
            }
        }
    }

    /// A channel that was starting is up now.
    private func settle(_ id: String) {
        withAnimation(Motion.snappy) {
            updateConnector(id) { record in
                guard record.enabled, record.state == "starting" else { return }
                record.state = (ChannelCatalog.platform(record.kind)?.twoWay ?? true) ? "listening" : "connected"
            }
        }
    }

    /// What the list does every 5 seconds: read the live state again.
    func refresh() {
        checkedAt = Date()
        for record in connectors where record.state == "starting" {
            settle(record.id)
        }
    }

    func removeConnector(_ id: String) {
        withAnimation(Motion.snappy) { connectors.removeAll { $0.id == id } }
    }

    func removeBot(_ id: String) {
        withAnimation(Motion.snappy) { bots.removeAll { $0.id == id } }
    }

    func addConnector(kind: String, form: ChannelForm) {
        guard let platform = ChannelCatalog.platform(kind) else { return }
        let name = form.name.trimmingCharacters(in: .whitespaces)
        var record = ChannelConnector(id: "c-\(UUID().uuidString.prefix(6))", kind: kind, name: name.isEmpty ? platform.label : name, enabled: true, state: "starting")
        for field in platform.fields {
            let value = (form.values[field.key] ?? "").trimmingCharacters(in: .whitespaces)
            if field.kind == .secret {
                if !value.isEmpty { record.savedSecrets.insert(field.key) }
            } else {
                record.values[field.key] = value
            }
        }
        if platform.twoWay {
            record.senders = ChannelCatalog.senders(from: form.senders)
            record.model = form.model
        }
        withAnimation(Motion.snappy) { connectors.append(record) }
        let id = record.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            settle(id)
        }
    }

    func addBot(name: String, allowedUserID: String, model: String) {
        let bot = ChannelDiscordBot(id: "d-\(UUID().uuidString.prefix(6))", name: name, allowedUserID: allowedUserID, live: true, model: model)
        withAnimation(Motion.snappy) { bots.append(bot) }
    }
}

// MARK: - Small shared pieces

private func channelPill(_ state: String) -> (text: String, tone: StatusPill.Tone) {
    switch state {
    case "listening": return ("Listening", .ok)
    case "connected": return ("Ready", .ok)
    case "starting": return ("Starting", .muted)
    case "error": return ("Problem", .bad)
    case "off": return ("Off", .muted)
    default: return (state.capitalized, .muted)
    }
}

private struct ChannelBadge: View {
    let text: String
    let tint: UInt32

    var body: some View {
        Text(text)
            .font(KFont.ui(13, .semibold, relativeTo: .footnote))
            .foregroundStyle(Palette.onGold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 36, height: 36)
            .background(Color(hex: tint), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct ChannelErrorText: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 13, weight: .semibold))
            Text(text).font(KFont.ui(14.5, relativeTo: .subheadline)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Numbered steps, for setup guides.
private struct ChannelSteps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(KFont.ui(13.5, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: 26, height: 26)
                        .background(Palette.gold, in: Circle())
                    Text(step)
                        .font(KFont.ui(15.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
        }
        .padding(16)
    }
}

/// A platform's setup steps, in a sheet.
private struct ChannelGuideSheet: View {
    let title: String
    let steps: [String]

    var body: some View {
        FittedSheet(estimate: 480) {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                ChannelSteps(steps: steps)
                    .kCard(radius: 22)
                Text("Then come back, fill in the fields and save. Send test checks that it works.")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }
}

/// The allowed senders list: one per line, or separated by commas.
private struct ChannelSendersRow: View {
    @Binding var text: String
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Allowed senders")
                .font(KFont.ui(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
            TextField("Nobody yet", text: $text, axis: .vertical)
                .lineLimit(2...6)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text(help)
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Every field a platform declares. A blank secret keeps the saved one.
private struct ChannelFieldRows: View {
    let platform: ChannelPlatform
    @Binding var form: ChannelForm
    var savedSecrets: Set<String> = []

    var body: some View {
        ForEach(platform.fields, id: \.key) { field in
            fieldRow(field)
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: ChannelField) -> some View {
        let title = field.required || field.kind == .toggle ? field.label : "\(field.label) (optional)"
        let text = Binding(get: { form.values[field.key] ?? "" }, set: { form.values[field.key] = $0 })
        switch field.kind {
        case .toggle:
            YouToggleRow(title: title, detail: field.help, isOn: Binding(get: { (form.values[field.key] ?? "") == "true" }, set: { form.values[field.key] = $0 ? "true" : "false" }))
        default:
            VStack(alignment: .leading, spacing: 0) {
                FieldRow(
                    title: title,
                    text: text,
                    prompt: field.kind == .secret && savedSecrets.contains(field.key) ? "Saved. Leave blank to keep it." : field.placeholder,
                    secure: field.kind == .secret,
                    keyboard: field.kind == .number ? .numberPad : (field.placeholder.hasPrefix("http") ? .URL : .default)
                )
                if let help = field.help {
                    Text(help)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .padding(.top, -4)
                }
            }
        }
    }
}

// MARK: - The list

struct ChannelsScreen: View {
    var startPicker = false
    var startEmpty = false

    @State private var loaded = false
    @State private var showPicker = false
    @State private var picked: String?
    @State private var addKind: String?

    private let store = ChannelStore.shared

    var body: some View {
        if YouBotsLive.isPaired {
            YouBotsChannelsScreen()
        } else {
            sampleBody
        }
    }

    private var sampleBody: some View {
        SettingsPage("Channels", subtitle: "Reach Kairos from the apps you already use, and choose where results go.") {
            SettingsGroup("Your channels") {
                if !loaded {
                    EmptyRow(text: "Loading...")
                } else if store.bots.isEmpty && store.connectors.isEmpty {
                    EmptyRow(text: "No channels yet. Add one to reach Kairos from your phone.")
                } else {
                    ForEach(store.bots) { bot in
                        ChannelBotListRow(bot: bot)
                    }
                    ForEach(store.connectors) { connector in
                        ChannelConnectorListRow(connector: connector)
                    }
                }
            }
            .arrives(0)

            NoteText(text: "Status updates every 5 seconds while this page is open. Checked at \(store.checkedAt.formatted(date: .omitted, time: .standard)).", symbol: "arrow.clockwise")

            SettingsGroup {
                ActionRow(title: "Add a channel", detail: "Discord, Telegram, WhatsApp, Slack, email and more.", symbol: "plus", tone: .gold) {
                    showPicker = true
                }
            }
            .arrives(1)

            NoteText(text: "Two-way channels answer only the senders you allow, and those senders can reach your agents by name. Send-only channels carry task results and agent notifications.")

            SettingsGroup {
                YouNavRow(title: "Reach me", detail: "The order bots use to message and call you.", symbol: "bell", to: .reachMe)
            }
            .arrives(2)
        }
        .task {
            if !loaded {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(Motion.snappy) { loaded = true }
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                store.refresh()
            }
        }
        .onAppear {
            if startEmpty {
                store.bots = []
                store.connectors = []
            }
            if startPicker { showPicker = true }
        }
        .sheet(isPresented: $showPicker, onDismiss: {
            if let kind = picked {
                picked = nil
                addKind = kind
            }
        }) {
            ChannelPickerSheet { kind in
                picked = kind
                showPicker = false
            }
        }
        .navigationDestination(item: $addKind) { kind in
            AddChannelScreen(kind: kind)
        }
    }
}

private struct ChannelBotListRow: View {
    let bot: ChannelDiscordBot

    var body: some View {
        NavigationLink(value: YouRoute.discord(bot.id)) {
            HStack(spacing: 12) {
                ChannelBadge(text: "D", tint: Palette.botLilac)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bot.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusPill(text: bot.live ? "Listening" : "Not connected", tone: bot.live ? .ok : .muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
    }

    private var detail: String {
        var text = "Discord · " + (bot.allowedUserID.isEmpty ? "answers anyone in its channels" : "answers one allowed user")
        let count = bot.overrides.count
        if count > 0 { text += " · \(count) channel override\(count == 1 ? "" : "s")" }
        return text
    }
}

private struct ChannelConnectorListRow: View {
    let connector: ChannelConnector

    var body: some View {
        let platform = ChannelCatalog.platform(connector.kind)
        let pill = channelPill(connector.state)
        HStack(spacing: 10) {
            NavigationLink(value: YouRoute.channel(connector.id)) {
                HStack(spacing: 12) {
                    ChannelBadge(text: platform?.badge ?? "?", tint: platform?.tint ?? Palette.botGold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connector.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        Text(detail(platform))
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                        if connector.state == "error" && !connector.stateDetail.isEmpty {
                            Text(connector.stateDetail)
                                .font(KFont.ui(13.5, relativeTo: .footnote))
                                .foregroundStyle(Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    StatusPill(text: pill.text, tone: pill.tone)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.985))
            Toggle("\(connector.name) on", isOn: Binding(get: { connector.enabled }, set: { on in
                Haptics.select()
                ChannelStore.shared.setEnabled(connector.id, on)
            }))
            .labelsHidden()
            .tint(Palette.gold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
    }

    private func detail(_ platform: ChannelPlatform?) -> String {
        let label = platform?.label ?? connector.kind
        guard platform?.twoWay ?? true else { return "\(label) · send only" }
        let count = connector.senders.count
        return "\(label) · \(count) allowed sender\(count == 1 ? "" : "s")"
    }
}

/// Add a channel: platform tiles in three groups. Empty groups are left out.
private struct ChannelPickerSheet: View {
    let pick: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 4) {
                    Text("Add a channel")
                        .font(KFont.ui(20, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    Text("Pick where you want to reach Kairos, or where results should go.")
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)

                ForEach(ChannelCategory.allCases, id: \.self) { category in
                    let list = ChannelCatalog.platforms.filter { $0.category == category }
                    if !list.isEmpty {
                        SettingsGroup(category.title, footer: category.detail) {
                            ForEach(list) { platform in
                                tile(platform)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }

    private func tile(_ platform: ChannelPlatform) -> some View {
        Button {
            Haptics.tap()
            pick(platform.id)
        } label: {
            HStack(spacing: 12) {
                ChannelBadge(text: platform.badge, tint: platform.tint)
                RowLabel(title: platform.label, detail: platform.about)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
    }
}

// MARK: - One channel

struct ChannelDetailScreen: View {
    let channelID: String
    var startGuide = false

    @State private var form = ChannelForm()
    @State private var loaded = false
    @State private var testing = false
    @State private var testResult: String?
    @State private var showGuide = false
    @State private var confirmRemove = false
    @Environment(\.dismiss) private var dismiss

    private let store = ChannelStore.shared

    var body: some View {
        if YouBotsLive.isPaired {
            YouBotsChannelScreen(channelID: channelID)
        } else if let connector = store.connector(channelID) {
            page(connector)
        } else {
            SettingsPage("Channel", subtitle: "This channel was removed.") {
                SettingsGroup {
                    YouNavRow(title: "All channels", symbol: "list.bullet", to: .channels)
                }
            }
        }
    }

    private func page(_ connector: ChannelConnector) -> some View {
        let platform = ChannelCatalog.platform(connector.kind)
        let pill = channelPill(connector.state)
        let webhookURL = ChannelCatalog.webhookBase + connector.id + "/webhook"
        return SettingsPage(connector.name, subtitle: platform?.about ?? connector.kind) {
            SettingsGroup("Status") {
                YouToggleRow(
                    title: "On",
                    detail: connector.enabled ? "Running now." : "Switched off. Nothing is received or sent.",
                    symbol: "power",
                    isOn: Binding(get: { connector.enabled }, set: { store.setEnabled(connector.id, $0) })
                )
                StatusRow(title: "Status", detail: connector.stateDetail.isEmpty ? nil : connector.stateDetail, symbol: "antenna.radiowaves.left.and.right", status: pill.text, tone: pill.tone)
                if platform?.webhook ?? false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Webhook address").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        Text(webhookURL)
                            .font(KFont.ui(14.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.goldText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Give this to the platform. It must reach Kairos from the internet; nothing arrives until then.")
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                        YouPillButton(title: "Copy", symbol: "square.and.arrow.up") {
                            UIPasteboard.general.string = webhookURL
                            Haptics.success()
                            YouStore.shared.say("Copied.")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                RowButtons {
                    YouPillButton(title: testing ? "Sending..." : "Send test", symbol: "bell") { sendTest(connector) }
                    if let testResult {
                        Text(testResult)
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(testResult == "Sent" ? Palette.success : Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .arrives(0)

            if let platform {
                SettingsGroup("Settings") {
                    ChannelFieldRows(platform: platform, form: $form, savedSecrets: connector.savedSecrets)
                    if platform.twoWay {
                        ChannelSendersRow(text: $form.senders, help: platform.senderHelp)
                        YouToggleRow(title: "Anyone can message", detail: "Answers strangers too. They never reach your agents.", isOn: $form.anyone)
                        PickRow(title: "Model for chats", detail: "Which model answers messages here.", selection: $form.model, options: ChannelCatalog.models) {
                            ChannelCatalog.modelLabel($0, empty: "No model chosen")
                        }
                    }
                }
                .arrives(1)

                GoldButton(title: "Save") { save(connector, platform) }

                SettingsGroup {
                    ActionRow(title: "How to set up \(platform.label)", detail: "The steps, one by one.", symbol: "questionmark.circle") {
                        showGuide = true
                    }
                }
                .arrives(2)
            } else {
                NoteText(text: "This kind of channel is not offered on this desktop, so its settings are left out. Status, test and removal still work.", symbol: "info.circle")
            }

            SettingsGroup {
                ActionRow(title: "Remove \(connector.name)", symbol: "trash", tone: .danger) { confirmRemove = true }
            }
            .arrives(3)
        }
        .onAppear { load(connector) }
        .sheet(isPresented: $showGuide) {
            ChannelGuideSheet(title: "Set up \(platform?.label ?? "this channel")", steps: platform?.steps ?? [])
        }
        .confirmationDialog("Remove \(connector.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                store.removeConnector(connector.id)
                YouStore.shared.say("\(connector.name) removed.")
                dismiss()
            }
        } message: {
            Text("Its saved settings and tokens are deleted. Chats it started stay in Chats.")
        }
    }

    private func load(_ connector: ChannelConnector) {
        guard !loaded else { return }
        loaded = true
        form = ChannelForm(
            name: connector.name,
            values: connector.values,
            senders: connector.senders.joined(separator: "\n"),
            anyone: connector.anyone,
            model: connector.model
        )
        if startGuide { showGuide = true }
    }

    private func save(_ connector: ChannelConnector, _ platform: ChannelPlatform) {
        let draft = form
        store.updateConnector(connector.id) { record in
            for field in platform.fields {
                let value = (draft.values[field.key] ?? "").trimmingCharacters(in: .whitespaces)
                if field.kind == .secret {
                    if !value.isEmpty { record.savedSecrets.insert(field.key) }
                } else {
                    record.values[field.key] = value
                }
            }
            if platform.twoWay {
                record.senders = ChannelCatalog.senders(from: draft.senders)
                record.anyone = draft.anyone
                record.model = draft.model
            }
            if record.state == "error" && record.enabled {
                record.state = "starting"
                record.stateDetail = ""
            }
        }
        for field in platform.fields where field.kind == .secret {
            form.values[field.key] = ""
        }
        Haptics.success()
        YouStore.shared.say("Saved.")
        store.refresh()
    }

    private func sendTest(_ connector: ChannelConnector) {
        guard !testing else { return }
        testing = true
        testResult = nil
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            let current = store.connector(connector.id) ?? connector
            withAnimation(Motion.snappy) {
                testing = false
                if !current.enabled {
                    testResult = "Not sent. Turn it on first."
                } else if current.state == "error" {
                    testResult = current.stateDetail.isEmpty ? "Not sent. The channel has a problem." : "Not sent. \(current.stateDetail)"
                } else {
                    testResult = "Sent"
                }
            }
        }
    }
}

// MARK: - Add a channel

struct AddChannelScreen: View {
    let kind: String
    var startFailed = false

    @State private var form = ChannelForm()
    @State private var token = ""
    @State private var allowedUser = ""
    @State private var error: String?
    @State private var adding = false
    @State private var prepared = false
    @State private var showGuide = false
    @Environment(\.dismiss) private var dismiss

    private let store = ChannelStore.shared

    var body: some View {
        if YouBotsLive.isPaired {
            SettingsPage("Add a channel", subtitle: "A channel carries a token or an address, so it is added in Kairos on your desktop.") {
                HintLine(text: "Add, edit and remove a channel in Kairos on your desktop, in Settings, Channels. A token, a topic or a server address never goes through this phone.",
                         symbol: "desktopcomputer")
                    .padding(.horizontal, 8)
                SettingsGroup {
                    YouNavRow(title: "All channels", symbol: "list.bullet", to: .channels)
                }
            }
        } else if kind == "discord" {
            discordPage
        } else if let platform = ChannelCatalog.platform(kind) {
            platformPage(platform)
        } else {
            SettingsPage("Add a channel", subtitle: "This platform is not offered.") {
                SettingsGroup {
                    YouNavRow(title: "All channels", symbol: "list.bullet", to: .channels)
                }
            }
        }
    }

    // MARK: Discord

    private var discordPage: some View {
        SettingsPage("Add Discord", subtitle: "A Discord bot that answers you in your server or DMs.") {
            SettingsGroup("Before you start") {
                ChannelSteps(steps: ChannelCatalog.discordSteps)
            }
            .arrives(0)

            SettingsGroup("Settings", footer: "Allowed user is optional. Only this user is answered, and only they can reach your agents. Leave it empty to answer anyone in its channels.") {
                FieldRow(title: "Name", text: $form.name, prompt: "Kairos")
                FieldRow(title: "Bot token", text: $token, prompt: "Paste the bot token", secure: true)
                FieldRow(title: "Allowed user (optional)", text: $allowedUser, prompt: "Your Discord user ID", keyboard: .numberPad)
                PickRow(title: "Default model", selection: $form.model, options: ChannelCatalog.models) {
                    ChannelCatalog.modelLabel($0, empty: "No default model")
                }
                if let error { ChannelErrorText(text: error) }
            }
            .arrives(1)

            GoldButton(title: adding ? "Adding..." : "Add Discord bot") { addDiscord() }

            NoteText(text: "The plain Discord delivery target messages the allowed user directly. Each channel override is its own target on the Tasks tab.", symbol: "info.circle")
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            if startFailed { error = "Name and token are required." }
        }
    }

    private func addDiscord() {
        guard !adding else { return }
        let name = form.name.trimmingCharacters(in: .whitespaces)
        let secret = token.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !secret.isEmpty else {
            withAnimation(Motion.snappy) { error = "Name and token are required." }
            Haptics.thud()
            return
        }
        error = nil
        adding = true
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            store.addBot(name: name, allowedUserID: allowedUser.trimmingCharacters(in: .whitespaces), model: form.model)
            adding = false
            Haptics.success()
            YouStore.shared.say("Discord bot added.")
            dismiss()
        }
    }

    // MARK: Other platforms

    private func platformPage(_ platform: ChannelPlatform) -> some View {
        SettingsPage("Add \(platform.label)", subtitle: platform.about) {
            SettingsGroup("Settings") {
                FieldRow(title: "Name", text: $form.name, prompt: platform.label)
                ChannelFieldRows(platform: platform, form: $form)
                if platform.twoWay {
                    ChannelSendersRow(text: $form.senders, help: platform.senderHelp)
                    PickRow(title: "Model for chats", detail: "Which model answers messages here.", selection: $form.model, options: ChannelCatalog.models) {
                        ChannelCatalog.modelLabel($0, empty: "No model chosen")
                    }
                }
                if let error { ChannelErrorText(text: error) }
            }
            .arrives(0)

            GoldButton(title: adding ? "Adding..." : "Add \(platform.label)") { add(platform) }

            SettingsGroup {
                ActionRow(title: "How to set up \(platform.label)", detail: "The steps, one by one.", symbol: "questionmark.circle") {
                    showGuide = true
                }
            }
            .arrives(1)

            if platform.category == .webhook || platform.webhook {
                NoteText(text: "After you add it, its page shows the webhook address to give the platform.", symbol: "info.circle")
            }
        }
        .onAppear { prepare(platform) }
        .sheet(isPresented: $showGuide) {
            ChannelGuideSheet(title: "Set up \(platform.label)", steps: platform.steps)
        }
    }

    private func prepare(_ platform: ChannelPlatform) {
        guard !prepared else { return }
        prepared = true
        form.name = platform.label
        for field in platform.fields where !field.preset.isEmpty {
            form.values[field.key] = field.preset
        }
        if startFailed { error = missingText(platform) }
    }

    private func missingText(_ platform: ChannelPlatform) -> String? {
        var missing: [String] = []
        if form.name.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("Name") }
        for field in platform.fields where field.required && field.kind != .toggle {
            if (form.values[field.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                missing.append(field.label)
            }
        }
        return missing.isEmpty ? nil : "Not added. Fill in: \(missing.joined(separator: ", "))."
    }

    private func add(_ platform: ChannelPlatform) {
        guard !adding else { return }
        if let problem = missingText(platform) {
            withAnimation(Motion.snappy) { error = problem }
            Haptics.thud()
            return
        }
        error = nil
        adding = true
        let draft = form
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            store.addConnector(kind: platform.id, form: draft)
            adding = false
            Haptics.success()
            YouStore.shared.say("\(platform.label) added.")
            dismiss()
        }
    }
}

// MARK: - Discord bot

struct DiscordBotScreen: View {
    let botID: String
    var startGuide = false

    @State private var model = ""
    @State private var voiceID = ""
    @State private var voiceError: String?
    @State private var newID = ""
    @State private var newLabel = ""
    @State private var newMode: ChannelOverrideMode = .normal
    @State private var overrideError: String?
    @State private var loaded = false
    @State private var showGuide = false
    @State private var confirmRemove = false
    @State private var removingOverride: ChannelOverride?
    @Environment(\.dismiss) private var dismiss

    private let store = ChannelStore.shared
    private let reach = ReachMeStore.shared

    private static let callWays = ["", "app", "phone", "discord", "telegram"]

    var body: some View {
        if YouBotsLive.isPaired {
            YouBotsDiscordScreen(botID: botID)
        } else if let bot = store.bot(botID) {
            page(bot)
        } else {
            SettingsPage("Discord bot", subtitle: "This bot was removed.") {
                SettingsGroup {
                    YouNavRow(title: "All channels", symbol: "list.bullet", to: .channels)
                }
            }
        }
    }

    private func callLabel(_ way: String) -> String {
        switch way {
        case "app": "In the Kairos app"
        case "phone": "On my phone"
        case "discord": "In my Discord voice channel"
        case "telegram": "As a Telegram voice message"
        default: "Calls are off"
        }
    }

    private func page(_ bot: ChannelDiscordBot) -> some View {
        SettingsPage(bot.name, subtitle: "A Discord bot. Changes here restart its connection at once.") {
            SettingsGroup("Bot") {
                StatusRow(
                    title: "Connection",
                    detail: bot.live ? "Connected to Discord." : "Not connected. Check the token, and that your desktop is on.",
                    symbol: "antenna.radiowaves.left.and.right",
                    status: bot.live ? "Listening" : "Not connected",
                    tone: bot.live ? .ok : .muted
                )
                RowLabel(
                    title: "Allowed user",
                    detail: bot.allowedUserID.isEmpty
                        ? "Answers anyone in its channels. Agents are never reachable through it."
                        : "Only Discord user \(bot.allowedUserID) is answered outside open channels, and only they can reach your agents.",
                    symbol: "person.crop.circle"
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                PickRow(title: "Default model", detail: "Which model answers messages to this bot.", selection: $model, options: ChannelCatalog.models) {
                    ChannelCatalog.modelLabel($0, empty: "No default model")
                }
                RowButtons {
                    YouPillButton(title: "Save model", prominent: true) {
                        store.updateBot(bot.id) { $0.model = model }
                        Haptics.success()
                        YouStore.shared.say("Saved. Its connection restarted.")
                    }
                }
            }
            .arrives(0)

            SettingsGroup("Voice", footer: "Talk with this bot by voice in a server channel. It joins when you say \"call me\", speaks only to you, and leaves when you do. It needs the voice add-ons on your desktop.") {
                FieldRow(title: "Voice channel ID", text: $voiceID, prompt: "Empty means off", keyboard: .numberPad)
                Text(bot.voiceChannelID.isEmpty
                     ? "Off. Paste a voice channel's ID from a server this bot is in."
                     : "Joins channel \(bot.voiceChannelID) only.")
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                if let voiceError { ChannelErrorText(text: voiceError) }
                RowButtons {
                    YouPillButton(title: "Save voice channel") { saveVoice(bot) }
                }
                PickRow(
                    title: "When a bot calls you",
                    detail: "The first way in Reach me's call order. Changing one changes the other.",
                    selection: Binding(get: { reach.firstCall }, set: { way in
                        reach.firstCall = way
                        YouStore.shared.say(way.isEmpty ? "Calls are off." : "Saved. It is first in Reach me now.")
                    }),
                    options: Self.callWays
                ) { callLabel($0) }
                YouNavRow(title: "Reach me", detail: "The rest of the order, quiet hours and STOP.", symbol: "bell", to: .reachMe)
            }
            .arrives(1)

            SettingsGroup("Channel overrides", footer: "Per-channel behaviour, and extra delivery targets for tasks.") {
                if bot.overrides.isEmpty {
                    EmptyRow(text: "No overrides. The bot follows its allow list everywhere.")
                } else {
                    ForEach(bot.overrides) { entry in
                        HStack(spacing: 0) {
                            PickRow(
                                title: "#\(entry.label)",
                                detail: "Channel ID \(entry.channelID) · \(entry.mode.detail)",
                                selection: Binding(get: { entry.mode }, set: { mode in
                                    store.updateBot(bot.id) { record in
                                        if let index = record.overrides.firstIndex(where: { $0.id == entry.id }) {
                                            record.overrides[index].mode = mode
                                        }
                                    }
                                    YouStore.shared.say("Channel updated.")
                                }),
                                options: ChannelOverrideMode.allCases
                            ) { $0.title }
                            Button {
                                Haptics.tap()
                                removingOverride = entry
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Palette.danger)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .padding(.trailing, 6)
                            .accessibilityLabel("Remove #\(entry.label)")
                        }
                    }
                }
            }
            .arrives(2)

            SettingsGroup("Add an override", footer: "To find a channel ID: in Discord, turn on Developer Mode (Settings, Advanced), then press and hold a channel, or right-click it on a computer, and choose Copy Channel ID.") {
                FieldRow(title: "Channel ID", text: $newID, prompt: "Discord channel ID", keyboard: .numberPad)
                FieldRow(title: "Label", text: $newLabel, prompt: "announcements")
                PickRow(title: "Behaviour", detail: newMode.detail, selection: $newMode, options: ChannelOverrideMode.allCases) { $0.title }
                if let overrideError { ChannelErrorText(text: overrideError) }
                RowButtons {
                    YouPillButton(title: "Add override", symbol: "plus") { addOverride(bot) }
                }
            }
            .arrives(3)

            NoteText(text: "The plain Discord delivery target messages the allowed user directly. Each channel override is its own target on the Tasks tab.", symbol: "info.circle")

            SettingsGroup {
                ActionRow(title: "Setup steps", detail: "The token, the intent and the invite.", symbol: "questionmark.circle") { showGuide = true }
                ActionRow(title: "Remove bot", symbol: "trash", tone: .danger) { confirmRemove = true }
            }
            .arrives(4)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            model = bot.model
            voiceID = bot.voiceChannelID
            if startGuide { showGuide = true }
        }
        .sheet(isPresented: $showGuide) {
            ChannelGuideSheet(title: "Before you start", steps: ChannelCatalog.discordSteps)
        }
        .confirmationDialog("Remove this bot?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove bot", role: .destructive) {
                store.removeBot(bot.id)
                YouStore.shared.say("Bot removed.")
                dismiss()
            }
        } message: {
            Text("\"\(bot.name)\" will be disconnected from Discord and its token deleted. Any task delivering to Discord will stop reaching you.")
        }
        .confirmationDialog("Remove this channel override?", isPresented: Binding(get: { removingOverride != nil }, set: { if !$0 { removingOverride = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let entry = removingOverride {
                    withAnimation(Motion.snappy) {
                        store.updateBot(bot.id) { record in record.overrides.removeAll { $0.id == entry.id } }
                    }
                    YouStore.shared.say("Channel removed.")
                }
                removingOverride = nil
            }
        } message: {
            Text("#\(removingOverride?.label ?? "") goes back to the allow list and stops being a task delivery target.")
        }
    }

    private func saveVoice(_ bot: ChannelDiscordBot) {
        let id = voiceID.trimmingCharacters(in: .whitespaces)
        if !id.isEmpty && bot.allowedUserID.isEmpty {
            withAnimation(Motion.snappy) { voiceError = "Voice needs an allowed user, because it talks only to that person." }
            return
        }
        voiceError = nil
        store.updateBot(bot.id) { $0.voiceChannelID = id }
        Haptics.success()
        YouStore.shared.say(id.isEmpty ? "Voice turned off." : "Voice channel saved.")
    }

    private func addOverride(_ bot: ChannelDiscordBot) {
        let id = newID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else {
            withAnimation(Motion.snappy) { overrideError = "A channel ID is required." }
            Haptics.thud()
            return
        }
        overrideError = nil
        let label = newLabel.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        let entry = ChannelOverride(id: "o-\(UUID().uuidString.prefix(6))", channelID: id, label: label.isEmpty ? "channel-\(id.suffix(4))" : label, mode: newMode)
        withAnimation(Motion.snappy) {
            store.updateBot(bot.id) { $0.overrides.append(entry) }
        }
        newID = ""
        newLabel = ""
        newMode = .normal
        Haptics.success()
        YouStore.shared.say("Channel added.")
    }
}

// MARK: - Paired: what the desktop has

/// Where to do something: one quiet line.
private struct YouBotsChannelHint: View {
    let text: String

    var body: some View {
        HintLine(text: text, symbol: "desktopcomputer")
            .padding(.horizontal, 8)
    }
}

/// Channels while paired: the desktop's Discord bots and connectors, read only, with their status. A token, an address,
/// a topic, a setting or a sender never reaches this phone, and no channel is added, edited or removed from it.
struct YouBotsChannelsScreen: View {
    private let live = YouBotsLive.shared

    var body: some View {
        let ready = live.load(.connectors) == .loaded || live.load(.discord) == .loaded
        SettingsPage("Channels", subtitle: "Reach Kairos from the apps you already use, and choose where results go.") {
            YouBotsLoadLine(part: .connectors, loading: "Reading your channels from your desktop.")
            YouBotsLoadLine(part: .discord, loading: "Reading your Discord bots from your desktop.")
            YouBotsNoticeLine(part: .connectors)
            YouBotsNoticeLine(part: .discord)

            if ready {
                SettingsGroup("Your channels") {
                    if live.discordBots.isEmpty && live.channels.isEmpty
                        && live.load(.connectors) == .loaded && live.load(.discord) == .loaded {
                        EmptyRow(text: "No channels yet. Add one in Kairos on your desktop to reach Kairos from your phone.")
                    }
                    ForEach(live.discordBots) { bot in
                        discordRow(bot)
                    }
                    ForEach(live.channels) { channel in
                        channelRow(channel)
                    }
                    if live.skippedChannels + live.skippedDiscord > 0 {
                        EmptyRow(text: "Some channels could not be read here. See them in Kairos on your desktop.")
                    }
                }
                .arrives(0)

                if let checked = live.checkedAt {
                    NoteText(text: "Status updates while this page is open. Checked at \(checked.formatted(date: .omitted, time: .standard)).", symbol: "arrow.clockwise")
                }

                YouBotsChannelHint(text: "Add, edit and remove a channel, its allowed senders, its token and the model it answers with in Kairos on your desktop. A token or an address never goes through this phone.")

                NoteText(text: "Two-way channels answer only the senders you allow, and those senders can reach your agents by name. Send-only channels carry task results and agent notifications.")
            }

            SettingsGroup {
                YouNavRow(title: "Reach me", detail: "The order bots use to message and call you.", symbol: "bell", to: .reachMe)
            }
            .arrives(1)
        }
        .task(id: YouBotsLive.connectionKey) {
            while !Task.isCancelled {
                await live.read(.connectors)
                await live.read(.discord)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func discordRow(_ bot: YouBotsDiscord) -> some View {
        let connected = live.discordLive.map { $0.contains(bot.name) }
        let pill: (text: String, tone: StatusPill.Tone) = {
            guard bot.hasToken else { return ("No token", .muted) }
            switch connected {
            case true?: return ("Listening", .ok)
            case false?: return ("Not connected", .muted)
            case nil: return ("Not checked", .muted)
            }
        }()
        var detail = "Discord · " + (bot.hasAllowedUser ? "answers one allowed user" : "answers anyone in its channels")
        if !bot.overrides.isEmpty { detail += " · \(bot.overrides.count) channel override\(bot.overrides.count == 1 ? "" : "s")" }
        return NavigationLink(value: YouRoute.discord(bot.id)) {
            HStack(spacing: 12) {
                ChannelBadge(text: "D", tint: Palette.botLilac)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bot.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusPill(text: pill.text, tone: pill.tone)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
    }

    private func channelRow(_ channel: YouBotsChannel) -> some View {
        let platform = ChannelCatalog.platform(channel.kind)
        let pill = channelPill(channel.state)
        return NavigationLink(value: YouRoute.channel(channel.id)) {
            HStack(spacing: 12) {
                ChannelBadge(text: platform?.badge ?? "?", tint: platform?.tint ?? Palette.botGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    Text(detail(channel))
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                    if channel.state == "error" {
                        Text("This channel has a problem. Check it in Kairos on your desktop.")
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusPill(text: pill.text, tone: pill.tone)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
    }

    private func detail(_ channel: YouBotsChannel) -> String {
        guard channel.twoWay else { return "\(channel.label) · send only" }
        var text = "\(channel.label) · \(channel.senders) allowed sender\(channel.senders == 1 ? "" : "s")"
        if channel.anyone { text += " · anyone may message" }
        return text
    }
}

/// One channel while paired: its status, off behind a confirm, and a test message behind a confirm. The test sends a
/// real message once; if its answer is lost it is never sent again from this phone.
struct YouBotsChannelScreen: View {
    let channelID: String
    private let live = YouBotsLive.shared
    @State private var turningOff = false
    @State private var testing = false

    var body: some View {
        Group {
            if let channel = live.channels.first(where: { $0.id == channelID }) {
                page(channel)
            } else if live.load(.connectors) == .loaded {
                SettingsPage("Channel", subtitle: "This channel is not on your desktop any more.") {
                    SettingsGroup {
                        YouNavRow(title: "All channels", symbol: "list.bullet", to: .channels)
                    }
                }
            } else {
                SettingsPage("Channel", subtitle: "Reading it from your desktop.") {
                    YouBotsLoadLine(part: .connectors, loading: "Reading this channel from your desktop.")
                }
            }
        }
        .task(id: YouBotsLive.connectionKey) {
            while !Task.isCancelled {
                await live.read(.connectors)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func page(_ channel: YouBotsChannel) -> some View {
        let platform = ChannelCatalog.platform(channel.kind)
        let pill = channelPill(channel.state)
        return SettingsPage(channel.name, subtitle: platform?.about ?? channel.label) {
            YouBotsNoticeLine(part: .connectors)
            SettingsGroup("Status") {
                StatusRow(title: "On", detail: channel.enabled ? "Running now." : "Switched off. Nothing is received or sent.", symbol: "power",
                          status: channel.enabled ? "On" : "Off", tone: channel.enabled ? .ok : .muted)
                if channel.enabled {
                    RowButtons {
                        YouBotsChangeButton(part: .connectors, key: "connector:" + channel.id, title: "Turn off", working: "Turning off...") {
                            turningOff = true
                        }
                    }
                } else {
                    YouBotsChannelHint(text: "It is turned back on in Kairos on your desktop.")
                        .padding(.vertical, 10)
                }
                StatusRow(title: "Status", detail: channel.state == "error" ? "This channel has a problem. Check it in Kairos on your desktop." : nil,
                          symbol: "antenna.radiowaves.left.and.right", status: pill.text, tone: pill.tone)
                if channel.webhook {
                    YouBotsChannelHint(text: "This channel's webhook address is shown in Kairos on your desktop. It never goes through this phone.")
                        .padding(.vertical, 10)
                }
                testRow(channel)
            }
            .arrives(0)

            if channel.twoWay {
                SettingsGroup("Who can message it") {
                    ValueRow(title: "Allowed senders", value: channel.senders == 0 ? "Nobody yet" : "\(channel.senders)")
                    ValueRow(title: "Anyone can message", detail: "Answers strangers too. They never reach your agents.", value: channel.anyone ? "Yes" : "No")
                }
                .arrives(1)
            }

            YouBotsChannelHint(text: "Its settings, senders, token and model, and removing it, are done in Kairos on your desktop. A token or an address never goes through this phone.")
        }
        .sheet(isPresented: $turningOff) {
            ConfirmSheet(title: "Turn off \(channel.name)?",
                         detail: "Nothing is received or sent through it until it is turned on again in Kairos on your desktop. This phone cannot turn it back on.",
                         confirm: "Turn off") {
                Task { await live.connectorOff(channel.id) }
            }
        }
        .sheet(isPresented: $testing) {
            ConfirmSheet(title: "Send a test message?",
                         detail: "A real message goes through \(channel.name) to where it sends notifications. It is sent once. If your desktop does not answer, this phone will not send another.",
                         confirm: "Send test", danger: false) {
                Task { await live.sendTest(channel.id) }
            }
        }
    }

    private func testRow(_ channel: YouBotsChannel) -> some View {
        let state = live.testState(channel.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                switch state {
                case .sending?:
                    StatusPill(text: "Sending...", tone: .working)
                case .unconfirmed?:
                    StatusPill(text: "Not confirmed", tone: .warn)
                    YouPillButton(title: "I checked, allow another", danger: false) {
                        live.allowAnotherTest(channel.id)
                    }
                default:
                    if channel.enabled && channel.state != "error" {
                        YouPillButton(title: "Send test", symbol: "bell") { testing = true }
                    }
                }
            }
            if let words = testWords(state, channel) {
                Text(words)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(failed(state) ? Palette.danger : Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func failed(_ state: YouBotsTestState?) -> Bool {
        if case .refused? = state { return true }
        return false
    }

    private func testWords(_ state: YouBotsTestState?, _ channel: YouBotsChannel) -> String? {
        switch state {
        case .sent?:
            return "Sent. Check that it arrived."
        case .refused(let words)?:
            return words
        case .unconfirmed?:
            return "Your desktop did not answer, so this phone cannot tell whether the test was sent. While this phone stays paired as it is now, it will not send another one until you say you checked. Look in the channel itself, and in Kairos on your desktop."
        case .sending?:
            return nil
        case nil:
            if !channel.enabled { return "Turn it on in Kairos on your desktop to send a test." }
            if channel.state == "error" { return "A test is not sent while the channel has a problem." }
            return nil
        }
    }
}

/// One override's change the person asked for, waiting for their confirm.
private struct YouBotsModeChange: Identifiable {
    let id: String
    let bot: String
    let label: String
    let from: ChannelOverrideMode
    let to: ChannelOverrideMode
    let hasAllowedUser: Bool
}

/// A Discord bot while paired: its connection, its voice (off behind a confirm), the first way bots call you (through
/// Reach me), and its channel overrides (silent or normal, and remove, each behind a confirm). The token, the allowed
/// user, the model and every channel id stay on the desktop.
struct YouBotsDiscordScreen: View {
    let botID: String
    private let live = YouBotsLive.shared
    private let voice = YouVoiceLive.shared
    @State private var changing: YouBotsModeChange?
    @State private var removing: YouBotsOverride?
    @State private var clearingVoice = false

    var body: some View {
        Group {
            if let bot = live.discordBots.first(where: { $0.id == botID }) {
                page(bot)
            } else if live.load(.discord) == .loaded {
                SettingsPage("Discord bot", subtitle: "This bot is not on your desktop any more.") {
                    SettingsGroup {
                        YouNavRow(title: "All channels", symbol: "list.bullet", to: .channels)
                    }
                }
            } else {
                SettingsPage("Discord bot", subtitle: "Reading it from your desktop.") {
                    YouBotsLoadLine(part: .discord, loading: "Reading this bot from your desktop.")
                }
            }
        }
        .task(id: YouBotsLive.connectionKey) {
            await live.read(.discord)
            await voice.read(.reach)
        }
    }

    private func connection(_ bot: YouBotsDiscord) -> (detail: String, status: String, tone: StatusPill.Tone) {
        guard bot.hasToken else { return ("No token is saved on your desktop.", "No token", .muted) }
        switch live.discordLive.map({ $0.contains(bot.name) }) {
        case true?: return ("Connected to Discord.", "Listening", .ok)
        case false?: return ("Not connected. Check the token, and that your desktop is on.", "Not connected", .muted)
        case nil: return ("Whether it is connected could not be read.", "Not checked", .muted)
        }
    }

    private func page(_ bot: YouBotsDiscord) -> some View {
        let state = connection(bot)
        return SettingsPage(bot.name, subtitle: "A Discord bot.") {
            YouBotsNoticeLine(part: .discord)
            SettingsGroup("Bot") {
                StatusRow(title: "Connection", detail: state.detail, symbol: "antenna.radiowaves.left.and.right", status: state.status, tone: state.tone)
                RowLabel(
                    title: "Allowed user",
                    detail: bot.hasAllowedUser
                        ? "Only one allowed Discord user is answered outside open channels, and only they can reach your agents."
                        : "Answers anyone in its channels. Agents are never reachable through it.",
                    symbol: "person.crop.circle"
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                YouBotsChannelHint(text: "The token, the allowed user and the default model are changed in Kairos on your desktop.")
                    .padding(.vertical, 10)
            }
            .arrives(0)

            SettingsGroup("Voice", footer: "Talk with this bot by voice in a server channel. It joins when you say \"call me\", speaks only to you, and leaves when you do. It needs the voice add-ons on your desktop.") {
                RowLabel(title: "Voice channel", detail: bot.hasVoice ? "A voice channel is set. The bot joins only that one." : "Off. Choose a voice channel in Kairos on your desktop.",
                         symbol: "waveform")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                if bot.hasVoice {
                    RowButtons {
                        YouBotsChangeButton(part: .discord, key: "voice:" + bot.id, title: "Turn voice off", working: "Turning off...") {
                            clearingVoice = true
                        }
                    }
                }
                callOrder
                YouNavRow(title: "Reach me", detail: "The rest of the order, quiet hours and STOP.", symbol: "bell", to: .reachMe)
            }
            .arrives(1)

            SettingsGroup("Channel overrides", footer: "Per-channel behaviour, and extra delivery targets for tasks.") {
                if bot.overrides.isEmpty {
                    EmptyRow(text: "No overrides. The bot follows its allow list everywhere.")
                } else {
                    ForEach(bot.overrides) { entry in
                        overrideRow(bot, entry)
                    }
                }
            }
            .arrives(2)

            YouBotsChannelHint(text: "Adding an override, opening a channel to anyone, and removing the bot are done in Kairos on your desktop.")
        }
        .sheet(item: $changing) { change in
            ConfirmSheet(title: "Set #\(change.label) to \(change.to.title.lowercased())?",
                         detail: Self.changeWords(change),
                         confirm: "Set to \(change.to.title)", danger: false) {
                Task { await live.setOverrideMode(bot: change.bot, entry: change.id, mode: change.to.rawValue) }
            }
        }
        .sheet(item: $removing) { entry in
            ConfirmSheet(title: "Remove #\(entry.label)?",
                         detail: Self.removeWords(bot),
                         confirm: "Remove") {
                Task { await live.removeOverride(bot: bot.id, entry: entry.id) }
            }
        }
        .sheet(isPresented: $clearingVoice) {
            ConfirmSheet(title: "Turn voice off?",
                         detail: "\(bot.name) stops joining its voice channel. This phone cannot set one again: do that in Kairos on your desktop.",
                         confirm: "Turn voice off") {
                Task { await live.clearVoice(bot: bot.id) }
            }
        }
    }

    private static func changeWords(_ change: YouBotsModeChange) -> String {
        if change.to == .silent {
            return "It will never reply there, whoever writes. It stays a delivery target for tasks. This phone cannot change it back."
        }
        if change.hasAllowedUser { return "Only your allowed user is answered there now." }
        return "This bot has no allowed user, so it still answers anyone there. Set an allowed user in Kairos on your desktop to narrow it."
    }

    private static func removeWords(_ bot: YouBotsDiscord) -> String {
        let base = "It goes back to the allow list and stops being a task delivery target. This phone cannot add it back: add one in Kairos on your desktop."
        if bot.hasAllowedUser { return base }
        return "This bot has no allowed user, so it answers anyone there after this. " + base
    }

    /// The first way bots call you: Reach me's own call order, changed through Reach me's own store.
    @ViewBuilder private var callOrder: some View {
        YouVoiceLoadLine(part: .reach, loading: "Reading Reach me from your desktop.")
        if let view = voice.reach {
            let first = view.call.first ?? ""
            let options: [String] = (first.isEmpty ? [""] : []) + view.callChannels.filter { $0.ready || $0.id == first }.map { $0.id }
            PickRow(
                title: "When a bot calls you",
                detail: "The first way in Reach me's call order. Changing one changes the other.",
                selection: Binding(get: { first }, set: { way in
                    if !way.isEmpty, way != first { Task { await live.setFirstCall(way) } }
                }),
                options: options
            ) { id in
                id.isEmpty ? "Calls are off" : (view.callChannels.first { $0.id == id }?.label ?? id)
            }
            .disabled(live.callChanging || voice.busy.contains("call") || voice.busy.contains("message"))
        }
        YouVoiceNoticeLine(part: .reach)
    }

    private func overrideRow(_ bot: YouBotsDiscord, _ entry: YouBotsOverride) -> some View {
        let mode = ChannelOverrideMode(rawValue: entry.mode) ?? .normal
        let key = "override:" + entry.id
        let working = live.busy.contains(key)
        // A silent channel stays silent from this phone: letting it answer again can open it to everyone.
        let options: [ChannelOverrideMode]
        switch mode {
        case .open: options = [.open, .normal, .silent]
        case .normal: options = [.normal, .silent]
        case .silent: options = [.silent]
        }
        return HStack(spacing: 0) {
            PickRow(
                title: "#\(entry.label)",
                detail: mode.detail,
                selection: Binding(get: { mode }, set: { new in
                    if new != mode, new != .open, mode == .open || new == .silent {
                        changing = YouBotsModeChange(id: entry.id, bot: bot.id, label: entry.label, from: mode, to: new,
                                                     hasAllowedUser: bot.hasAllowedUser)
                    }
                }),
                options: options
            ) { $0.title }
            .disabled(working || mode == .silent)
            if working {
                StatusPill(text: "Working...", tone: .muted)
                    .padding(.trailing, 12)
            } else if live.unconfirmed[.discord]?.contains(key) == true {
                StatusPill(text: "Not confirmed", tone: .warn)
                    .padding(.trailing, 12)
            } else if mode != .silent {
                Button {
                    Haptics.tap()
                    removing = entry
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.danger)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .padding(.trailing, 6)
                .accessibilityLabel("Remove #\(entry.label)")
            }
        }
    }
}

// MARK: - Debug pictures

enum ChannelsDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "channels": return AnyView(ChannelsScreen())
        case "channels-empty": return AnyView(ChannelsScreen(startEmpty: true))
        case "channels-picker": return AnyView(ChannelsScreen(startPicker: true))
        case "channel-telegram": return AnyView(ChannelDetailScreen(channelID: "c-telegram"))
        case "channel-problem": return AnyView(ChannelDetailScreen(channelID: "c-whatsapp"))
        case "channel-off": return AnyView(ChannelDetailScreen(channelID: "c-email"))
        case "channel-sendonly": return AnyView(ChannelDetailScreen(channelID: "c-ntfy"))
        case "channel-guide": return AnyView(ChannelDetailScreen(channelID: "c-telegram", startGuide: true))
        case "channel-add": return AnyView(AddChannelScreen(kind: "telegram"))
        case "channel-add-failed": return AnyView(AddChannelScreen(kind: "whatsapp", startFailed: true))
        case "channel-add-discord": return AnyView(AddChannelScreen(kind: "discord"))
        case "channel-add-discord-failed": return AnyView(AddChannelScreen(kind: "discord", startFailed: true))
        case "channel-discord": return AnyView(DiscordBotScreen(botID: "d-kairos"))
        case "channel-discord-new": return AnyView(DiscordBotScreen(botID: "d-helper"))
        case "channel-discord-guide": return AnyView(DiscordBotScreen(botID: "d-kairos", startGuide: true))
        default: return nil
        }
    }
}
