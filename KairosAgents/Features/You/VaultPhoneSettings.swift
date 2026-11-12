import SwiftUI
import UIKit

// Vault (the desktop's vault folder and the task-list sync) and Phone line (your own Twilio or Telnyx
// number, so a bot can call or text you and you can call a bot). Sample data only.

// MARK: - Vault

struct VaultSettingsScreen: View {
    /// Start a sync as soon as the page opens (for debug pictures).
    var autoSync = false
    /// The first sync fails, to show that state.
    var failSync = false

    @State private var syncing = false
    @State private var syncStatus: String?
    @State private var synced = false
    @State private var failedOnce = false

    private let folder = "C:\\Users\\Sam\\Documents\\Shop Vault"

    var body: some View {
        SettingsPage("Vault", subtitle: "The folder of notes your bots read and write, on your desktop.") {
            SettingsGroup("Vault folder", footer: "The folder can only be changed on the desktop, in Settings > Vault.") {
                VStack(alignment: .leading, spacing: 6) {
                    RowLabel(title: "Current folder", symbol: "folder")
                    Text(folder)
                        .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.goldText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 38)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                RowLabel(title: "Open chats", detail: "Chats that are open keep their old vault note until they reconnect.", symbol: "bubble.left.and.bubble.right")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .arrives(0)

            SettingsGroup("Task list sync", footer: "Runs every time Kairos starts on the desktop. Sync now picks up edits made since then.") {
                RowLabel(title: "Active Priorities and Notes", detail: "Checkbox items in your vault's Active Priorities note show up in Notes, and ticking one in Notes ticks it in the vault.", symbol: "list.bullet")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                ActionRow(title: "Sync now", detail: syncStatus, symbol: "arrow.clockwise", tone: .gold, trailing: syncing ? "Syncing..." : nil) {
                    sync()
                }
            }
            .arrives(1)
        }
        .onAppear {
            if autoSync && !syncing && syncStatus == nil { sync() }
        }
    }

    private func sync() {
        guard !syncing else { return }
        syncing = true
        withAnimation(Motion.snappy) { syncStatus = nil }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(Motion.snappy) {
                syncing = false
                if failSync && !failedOnce {
                    failedOnce = true
                    syncStatus = nil
                    YouStore.shared.say("Sync could not finish. Check that your desktop is on, then try again.")
                } else if !synced {
                    synced = true
                    syncStatus = "Synced: 3 added, 1 updated, 1 removed."
                    YouStore.shared.say("Vault synced: 3 added, 1 updated, 1 removed.")
                } else {
                    syncStatus = "Already up to date."
                    YouStore.shared.say("Notes already match your vault.")
                }
            }
        }
    }
}

// MARK: - Phone line sample data

nonisolated struct PhoneKeyField: Hashable, Sendable {
    let key: String
    let label: String
    var secret = false
    var help = ""
}

nonisolated struct PhoneLineSample: Hashable, Sendable {
    var configured: Bool
    var provider = "twilio"
    var values: [String: String] = [:]
    var savedSecrets: Set<String> = []
    var enabled = true
    var number = ""
    var mobile = ""
    var publicURL = ""
    var pinSet = false
    var requirePin = true
    var bot = "kip"
    var model = ""
    var othersEnabled = false
    var callerName = ""

    static let empty = PhoneLineSample(configured: false)

    static let sample = PhoneLineSample(
        configured: true,
        provider: "twilio",
        values: ["account_sid": "AC00000000000000000000000000example"],
        savedSecrets: ["auth_token"],
        enabled: true,
        number: "+15550100199",
        mobile: "+15550100142",
        publicURL: "https://kairos-desk.tailnet-example.ts.net",
        pinSet: true,
        requirePin: true,
        bot: "kip",
        model: "Fast cloud model",
        othersEnabled: true,
        callerName: "Sam"
    )

    static let providers = ["twilio", "telnyx"]
    static let models = ["", "Fast cloud model", "Qwen local"]

    static func fields(_ provider: String) -> [PhoneKeyField] {
        if provider == "telnyx" {
            return [
                PhoneKeyField(key: "api_key", label: "API key", secret: true),
                PhoneKeyField(key: "public_key", label: "Webhook public key", help: "From your Telnyx account, under Keys and Credentials."),
                PhoneKeyField(key: "connection_id", label: "Call control application ID", help: "The application your number is assigned to."),
            ]
        }
        return [
            PhoneKeyField(key: "account_sid", label: "Account SID", help: "Starts with AC."),
            PhoneKeyField(key: "auth_token", label: "Auth token", secret: true),
        ]
    }
}

nonisolated struct PhoneTranscriptLine: Hashable, Sendable {
    let speaker: String
    let text: String
}

nonisolated struct PhoneOutboundCall: Identifiable, Hashable, Sendable {
    let id: String
    var bot: String
    var who: String
    var to: String
    var when: String
    var live: Bool
    var endReason: String
    var lines: [PhoneTranscriptLine]
    var summary: String
}

nonisolated enum PhoneSample {
    static let calls: [PhoneOutboundCall] = [
        PhoneOutboundCall(
            id: "call-1", bot: "Atlas", who: "the parts supplier", to: "+15550100177", when: "Today 10:14", live: true, endReason: "",
            lines: [
                PhoneTranscriptLine(speaker: "Atlas", text: "Hi, this is Atlas, an AI assistant calling on behalf of Sam. This call is transcribed."),
                PhoneTranscriptLine(speaker: "Them", text: "Sure, how can I help?"),
                PhoneTranscriptLine(speaker: "Atlas", text: "Do you have twenty inner tubes in the 700 by 28 size in stock this week?"),
            ],
            summary: ""
        ),
        PhoneOutboundCall(
            id: "call-2", bot: "Kip", who: "Corner Bistro", to: "+15550100188", when: "Mon 18:02", live: false, endReason: "finished",
            lines: [
                PhoneTranscriptLine(speaker: "Kip", text: "Hi, this is Kip, an AI assistant calling on behalf of Sam. This call is transcribed."),
                PhoneTranscriptLine(speaker: "Them", text: "Corner Bistro, hello."),
                PhoneTranscriptLine(speaker: "Kip", text: "Could I book a table for four on Friday at seven?"),
                PhoneTranscriptLine(speaker: "Them", text: "Seven is full. Seven thirty works."),
                PhoneTranscriptLine(speaker: "Kip", text: "Seven thirty is fine. The name is Sam. Thank you."),
            ],
            summary: "Table for four on Friday at 7:30 pm, under Sam. Seven was full."
        ),
    ]

    static let blocked = ["+15550100123"]
}

// MARK: - Phone line

struct PhoneLineScreen: View {
    var startUnset = false
    var startPinOff = false
    var startTranscript = false

    @State private var line = PhoneLineSample.sample
    @State private var form = PhoneLineSample.sample
    @State private var secrets: [String: String] = [:]
    @State private var pin = ""
    @State private var saveError: String?
    @State private var calls = PhoneSample.calls
    @State private var blocked = PhoneSample.blocked
    @State private var blockNumber = ""
    @State private var openCall: PhoneOutboundCall?
    @State private var confirmRemove = false
    @State private var prepared = false

    private var botOptions: [String] {
        SampleData.allBots.filter { $0.members.isEmpty }.map(\.id)
    }

    var body: some View {
        SettingsPage("Phone line", subtitle: "Call a bot from your own mobile, and let your bots call or text you.") {
            SettingsGroup("Your phone number", footer: "It runs through your own Twilio or Telnyx account and number, so you pay them directly. Kairos never buys a number or signs up for anything.") {
                PickRow(title: "Provider", symbol: "antenna.radiowaves.left.and.right", selection: Binding(get: { form.provider }, set: { value in
                    form.provider = value
                    secrets = [:]
                }), options: PhoneLineSample.providers) { $0 == "telnyx" ? "Telnyx" : "Twilio" }
                StatusRow(title: "Phone", detail: status.detail, symbol: "phone", status: status.word, tone: status.tone)
                YouToggleRow(title: "Phone on", isOn: Binding(get: { form.enabled }, set: { on in
                    form.enabled = on
                    if line.configured {
                        line.enabled = on
                        YouStore.shared.say(on ? "Phone on." : "Phone off. Bots will not call or text you.")
                    }
                }))
            }
            .arrives(0)

            SettingsGroup("Provider keys", footer: "Secrets are sealed with your account key and never shown again.") {
                ForEach(PhoneLineSample.fields(form.provider), id: \.key) { field in
                    keyRow(field)
                }
            }
            .arrives(1)

            SettingsGroup("Numbers", footer: "Only your mobile can call in, and it is the only number a bot will ever call or text.") {
                FieldRow(title: "Your Kairos number", text: $form.number, prompt: "+15550100199", keyboard: .phonePad)
                FieldRow(title: "Your own mobile", text: $form.mobile, prompt: "+15550100142", keyboard: .phonePad)
            }
            .arrives(2)

            SettingsGroup("Reaching Kairos", footer: "An https address your provider can reach, such as your Remote Access address or your own tunnel. Kairos does not open one for you. Leave it empty for texts only.") {
                FieldRow(title: "Public address", text: $form.publicURL, prompt: "https://kairos-desk.tailnet-example.ts.net", keyboard: .URL)
                if line.configured && !line.publicURL.isEmpty {
                    addressRow(title: "Paste into your provider", detail: "The voice webhook for your Kairos number.", address: webhook("voice"))
                    addressRow(title: "For texts you send back", detail: "Set it as the number's incoming message webhook, so a STOP you text pauses every bot.", address: webhook("sms"))
                }
            }
            .arrives(3)

            SettingsGroup("Incoming call PIN", footer: "Caller ID can be faked, so when you call in, Kairos asks for this PIN on the keypad (then #) before it connects you. Three tries a call, and five wrong tries in an hour lock incoming calls for an hour. Calls Kairos places to you never ask.") {
                FieldRow(title: "PIN (4 to 8 digits)", text: $pin, prompt: line.pinSet ? "Saved. Leave empty to keep it." : "4 to 8 digits", secure: true, keyboard: .numberPad)
                YouToggleRow(title: "Ask for the PIN", detail: "Turn this off only if you accept the risk below.", symbol: "lock", isOn: Binding(get: { form.requirePin }, set: { on in
                    form.requirePin = on
                    if line.configured {
                        line.requirePin = on
                        YouStore.shared.say(on ? "The PIN is asked again." : "The PIN is no longer asked.")
                    }
                }))
                if !form.requirePin {
                    PhoneWarningText(text: "Warning: with the PIN off, anyone who can fake your caller ID can talk to your bots as you. Caller ID is easy to fake. Keep this on.")
                }
            }
            .arrives(4)

            SettingsGroup("Who answers") {
                PickRow(title: "Bot", detail: "Which bot picks up when you call.", symbol: "person.crop.circle", selection: $form.bot, options: botOptions) { id in
                    id == "kip" ? "Kip (default)" : SampleData.bot(id).name
                }
                PickRow(title: "Conversation model", detail: "A fast API or local model, like the one used in app calls.", symbol: "cpu", selection: $form.model, options: PhoneLineSample.models) { model in
                    model.isEmpty ? "Choose a fast model" : model
                }
            }
            .arrives(5)

            NoteText(text: "Calls from a bot to you always start with \"This is Kip, an AI assistant from Kairos\" and go only to your mobile.", symbol: "info.circle")

            SettingsGroup("Calls to other people", footer: "A bot can phone someone for you, such as a restaurant or a client. You approve every call before it is placed. The call opens by saying it is an AI assistant calling for you and that it is transcribed. You see a live transcript, can answer the bot's questions and can hang up. A summary lands in the bot's chat afterwards.") {
                YouToggleRow(title: "Calls to other people", detail: "Off by default.", symbol: "phone", isOn: Binding(get: { form.othersEnabled }, set: { on in
                    if on && form.callerName.trimmingCharacters(in: .whitespaces).isEmpty {
                        YouStore.shared.say("Enter your name for calls first.")
                        return
                    }
                    form.othersEnabled = on
                    if line.configured {
                        line.othersEnabled = on
                        line.callerName = form.callerName
                        YouStore.shared.say(on ? "Bots may call other people, with your approval." : "Calls to other people are off.")
                    }
                }))
                FieldRow(title: "Your name for calls", text: $form.callerName, prompt: "Sam")
                RowLabel(title: "Limits", detail: "One call at a time, a minute apart, between 8 am and 9 pm by your desktop's clock. Each day: 3 per bot, 5 per account and 2 to any one number. Ten minutes at most. Never to your own numbers or premium-rate numbers. When someone asks not to be called again, their number is blocked.", symbol: "clock")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Text("Rules for AI calls differ by place, and this is not legal advice. In the US, the FCC treats AI voices as artificial voices under the TCPA. Use it for your own errands, never for marketing.")
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .arrives(6)

            SettingsGroup("Recent calls to other people") {
                if calls.isEmpty {
                    EmptyRow(text: "No calls yet.")
                } else {
                    ForEach(calls) { call in
                        HStack(spacing: 8) {
                            RowLabel(title: "\(call.bot) called \(call.who)", detail: callDetail(call))
                            if call.live { StatusPill(text: "On the call", tone: .working) }
                            YouPillButton(title: call.live ? "Watch" : "Transcript") { openCall = call }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(minHeight: 52)
                    }
                }
            }
            .arrives(7)

            SettingsGroup("Do-not-call list", footer: "Bots never call a number on this list.") {
                ForEach(blocked, id: \.self) { number in
                    HStack(spacing: 8) {
                        RowLabel(title: number, detail: "Bots will not call this number.", symbol: "hand.raised")
                        YouPillButton(title: "Unblock") {
                            withAnimation(Motion.snappy) { blocked.removeAll { $0 == number } }
                            YouStore.shared.say("Unblocked.")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 52)
                }
                FieldRow(title: "Block a number", text: $blockNumber, prompt: "+15551234567", keyboard: .phonePad)
                RowButtons {
                    YouPillButton(title: "Block", symbol: "hand.raised") { block() }
                }
            }
            .arrives(8)

            NoteText(text: "Texting US numbers: carriers block texts from numbers that are not registered. Before bots text you, register your Kairos number for A2P 10DLC in your Twilio or Telnyx account (Sole Proprietor if you have no business tax ID), or use a verified toll-free number. Approval can take days to weeks, and the provider charges its own fees.", symbol: "info.circle")

            if let saveError { PhoneWarningText(text: saveError) }

            GoldButton(title: line.configured ? "Save changes" : "Save") { save() }

            if line.configured {
                SettingsGroup {
                    ActionRow(title: "Remove phone line", symbol: "trash", tone: .danger) { confirmRemove = true }
                }
            }
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            if startUnset {
                line = .empty
                form = .empty
            }
            if startPinOff {
                line.requirePin = false
                form.requirePin = false
            }
            if startTranscript { openCall = calls.first { !$0.live } }
        }
        .sheet(item: $openCall) { call in
            PhoneTranscriptSheet(call: call) {
                if let index = calls.firstIndex(where: { $0.id == call.id }) {
                    calls[index].live = false
                    calls[index].endReason = "you hung up"
                    calls[index].summary = "You ended the call before the supplier answered."
                }
                openCall = nil
                YouStore.shared.say("Call ended.")
            }
        }
        .confirmationDialog("Remove your phone line?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                withAnimation(Motion.snappy) {
                    line = .empty
                    form = .empty
                    secrets = [:]
                    pin = ""
                    saveError = nil
                }
                YouStore.shared.say("Phone line removed.")
            }
        } message: {
            Text("Its keys, numbers and PIN are deleted here. Bots stop calling and texting you. Your number stays yours at the provider.")
        }
    }

    // MARK: Pieces

    private var status: (word: String, tone: StatusPill.Tone, detail: String) {
        if !line.configured { return ("Not set up", .muted, "Not set up.") }
        if !line.enabled { return ("Off", .muted, "Switched off. Bots will not call or text you.") }
        if line.publicURL.isEmpty { return ("Texts only", .warn, "Texts only: add your public address to take calls.") }
        return ("Ready", .ok, "Ready for calls and texts.")
    }

    private func webhook(_ kind: String) -> String {
        var base = line.publicURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        return "\(base)/api/phone/\(kind)"
    }

    private func callDetail(_ call: PhoneOutboundCall) -> String {
        var text = "\(call.when) · \(call.to) · \(call.live ? "On the call" : "Ended")"
        if !call.live && !call.endReason.isEmpty { text += " · \(call.endReason)" }
        return text
    }

    @ViewBuilder
    private func keyRow(_ field: PhoneKeyField) -> some View {
        if field.secret {
            FieldRow(
                title: field.label,
                text: Binding(get: { secrets[field.key] ?? "" }, set: { secrets[field.key] = $0 }),
                prompt: form.savedSecrets.contains(field.key) && form.provider == line.provider ? "Saved. Leave empty to keep it." : "Paste it here",
                secure: true
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                FieldRow(
                    title: field.label,
                    text: Binding(get: { form.values[field.key] ?? "" }, set: { form.values[field.key] = $0 }),
                    prompt: field.key == "account_sid" ? "AC..." : ""
                )
                if !field.help.isEmpty {
                    Text(field.help)
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

    private func addressRow(title: String, detail: String, address: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RowLabel(title: title, detail: detail)
            Text(address)
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.goldText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            YouPillButton(title: "Copy", symbol: "square.and.arrow.up") {
                UIPasteboard.general.string = address
                Haptics.success()
                YouStore.shared.say("Copied.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func block() {
        let number = blockNumber.filter { !$0.isWhitespace }
        let digits = number.filter(\.isNumber)
        guard digits.count >= 7, number.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" || $0 == "(" || $0 == ")" }) else {
            YouStore.shared.say("Enter a phone number with its country code.")
            return
        }
        guard !blocked.contains(number) else {
            YouStore.shared.say("That number is already blocked.")
            return
        }
        withAnimation(Motion.snappy) { blocked.append(number) }
        blockNumber = ""
        YouStore.shared.say("Blocked. Bots will not call \(number).")
    }

    private func fail(_ text: String) {
        withAnimation(Motion.snappy) { saveError = text }
        Haptics.thud()
    }

    private func save() {
        let fields = PhoneLineSample.fields(form.provider)
        let sameProvider = form.provider == line.provider && line.configured
        for field in fields {
            let entered = (field.secret ? secrets[field.key] : form.values[field.key]) ?? ""
            let saved = field.secret && sameProvider && line.savedSecrets.contains(field.key)
            if entered.trimmingCharacters(in: .whitespaces).isEmpty && !saved && field.key != "public_key" {
                fail("Enter the \(field.label.lowercased()).")
                return
            }
        }
        if form.number.trimmingCharacters(in: .whitespaces).isEmpty || form.mobile.trimmingCharacters(in: .whitespaces).isEmpty {
            fail("Enter your Kairos number and your own mobile.")
            return
        }
        if !pin.isEmpty && (pin.count < 4 || pin.count > 8 || !pin.allSatisfy(\.isNumber)) {
            fail("The PIN must be 4 to 8 digits.")
            return
        }
        if form.requirePin && pin.isEmpty && !line.pinSet {
            fail("Set a PIN, or turn off Ask for the PIN.")
            return
        }
        if !form.publicURL.isEmpty && !form.publicURL.lowercased().hasPrefix("https://") {
            fail("The public address must start with https://.")
            return
        }

        let wasConfigured = line.configured
        var next = form
        next.configured = true
        if !sameProvider { next.savedSecrets = [] }
        for field in fields where field.secret {
            if !(secrets[field.key] ?? "").isEmpty { next.savedSecrets.insert(field.key) }
        }
        if !pin.isEmpty { next.pinSet = true } else { next.pinSet = line.pinSet }
        withAnimation(Motion.snappy) {
            line = next
            form = next
            secrets = [:]
            pin = ""
            saveError = nil
        }
        Haptics.success()
        YouStore.shared.say(wasConfigured ? "Phone saved." : "Phone saved. Paste the two addresses into your provider.")
    }
}

private struct PhoneWarningText: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 13, weight: .semibold))
            Text(text).font(KFont.ui(14, relativeTo: .footnote)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// A call to someone else: the transcript, or the live call with Hang up.
private struct PhoneTranscriptSheet: View {
    let call: PhoneOutboundCall
    let hangUp: () -> Void

    var body: some View {
        FittedSheet(estimate: 560) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 6) {
                    Text("\(call.bot) called \(call.who)")
                        .font(KFont.ui(20, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Text("\(call.when) · \(call.to)")
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                        if call.live { StatusPill(text: "Live", tone: .working) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(call.lines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.speaker)
                                .font(KFont.label)
                                .tracking(1.2)
                                .foregroundStyle(line.speaker == "Them" ? Palette.inkFaint : Palette.goldText)
                            Text(line.text)
                                .font(KFont.ui(15.5, relativeTo: .subheadline))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if call.live {
                        HStack(spacing: 8) {
                            PulsingDot(color: Palette.working)
                            Text("Listening...")
                                .font(KFont.ui(14, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkDim)
                        }
                    }
                }
                .padding(16)
                .kCard(radius: 22)

                if !call.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(text: "Summary")
                        Text(call.summary)
                            .font(KFont.ui(15, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 6)
                }

                if call.live {
                    GoldButton(title: "Hang up") { hangUp() }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Debug pictures

enum VaultPhoneDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "vault": return AnyView(VaultSettingsScreen())
        case "vault-synced": return AnyView(VaultSettingsScreen(autoSync: true))
        case "vault-failed": return AnyView(VaultSettingsScreen(autoSync: true, failSync: true))
        case "phone": return AnyView(PhoneLineScreen())
        case "phone-unset": return AnyView(PhoneLineScreen(startUnset: true))
        case "phone-pin-off": return AnyView(PhoneLineScreen(startPinOff: true))
        case "phone-transcript": return AnyView(PhoneLineScreen(startTranscript: true))
        default: return nil
        }
    }
}
