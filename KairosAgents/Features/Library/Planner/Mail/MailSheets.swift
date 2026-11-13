import SwiftUI

// MARK: - Sender avatar

/// The sender's first letter on a warm tile.
struct MailAvatar: View {
    let item: MailItem
    var size: CGFloat = 42

    var body: some View {
        Text(item.initial)
            .font(KFont.ui(size * 0.42, .semibold))
            .foregroundStyle(Palette.goldText)
            .frame(width: size, height: size)
            .background(Palette.surfaceRaised, in: Circle())
            .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Message

/// One flagged message: who, when, why it matters, a short preview, and what to do about it.
struct MailMessageSheet: View {
    let item: MailItem
    let store: MailStore
    let onDraft: () -> Void
    let onHandled: () -> Void

    var body: some View {
        FittedSheet(estimate: 560) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    MailAvatar(item: item, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.sender).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                        Text(item.address).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(item.time).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                .padding(.top, 30)

                Text(item.subjectLine)
                    .font(KFont.ui(22, .semibold, relativeTo: .title2))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.goldText)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.needsReply ? "Needs a reply" : "Why it matters")
                            .font(KFont.label)
                            .tracking(1.2)
                            .foregroundStyle(Palette.goldText)
                        Text(item.reason)
                            .font(KFont.ui(15.5))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Palette.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.gold.opacity(0.3), lineWidth: 1))

                if store.isSample {
                    Text(item.preview)
                        .font(KFont.ui(15.5))
                        .foregroundStyle(Palette.inkDim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .kCard(radius: 18)
                } else {
                    // Triage keeps headers only; nothing from the message body is fetched or shown.
                    MailLiveLine(text: liveLine)
                }

                VStack(spacing: 6) {
                    if !store.isSample && store.replyAccount(for: item) == nil && store.drafts[item.id] == nil {
                        // Paired, a reply goes only from the address this came to; that one cannot send from here.
                        MailLiveLine(text: store.replyOffLine(for: item), symbol: "desktopcomputer")
                    } else {
                        GoldButton(title: store.drafts[item.id] == nil ? (store.isSample ? "Draft a reply" : "Write a reply") : "Open the draft",
                                   action: onDraft)
                    }
                    if store.isSample {
                        QuietButton(title: "Mark as handled", action: onHandled)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private var liveLine: String {
        let to = item.account.map { "It came to \($0). " } ?? ""
        return to + "Kairos keeps only the sender, subject and date for triage. Read the whole message in your mail app."
    }
}

// MARK: - Draft a reply

/// Kip drafts a reply. Nothing is sent until the person swipes up to send.
struct MailDraftSheet: View {
    let item: MailItem
    let store: MailStore
    /// Debug pictures skip Kip's short writing pause, or open already sent.
    var instant = false
    var startSent = false
    let onSent: (String) -> Void
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MailDraft(itemID: "", from: "", to: "", subject: "", body: "")
    @State private var writing = true
    @State private var sentFrom: String?
    @State private var notice: String?
    /// Paired: the plain confirm that names the recipients and the sending address is showing.
    @State private var confirming = false
    /// Paired: a new value puts the swipe back, after a confirm was cancelled or a send did not go.
    @State private var swipeKey = 0
    /// Paired: why the last send did not go, or that it could not be confirmed.
    @State private var problem: String?
    /// Paired: set the moment Send is tapped, cleared when the answer is known.
    @State private var inFlight = false
    /// Paired: a send of this reply could not be confirmed. Send comes back only after the person says they
    /// have read that and checked Sent, so nothing is sent again blind.
    @State private var heldForCheck = false

    /// Paired: this reply is on its way. The sheet holds still and every control is off until it is known.
    private var sending: Bool { inFlight || store.sendingIDs.contains(item.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlannerSheetTitle(title: sentFrom == nil ? "Reply" : "Sent", subtitle: item.subjectLine) {
                    if sentFrom == nil && !sending {
                        PlannerRoundButton(symbol: "xmark", label: "Close", size: 40) { dismiss() }
                    }
                }

                if let sentFrom {
                    sentCard(sentFrom)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                } else if writing {
                    HStack(spacing: 12) {
                        Mascot(pose: .thinking, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kip is writing...").font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                            Text("From the message and how you usually reply.")
                                .font(KFont.ui(13.5, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: 0)
                        ProgressView().tint(Palette.gold)
                    }
                    .padding(16)
                    .kCard(radius: 20)
                    .transition(.opacity)
                } else {
                    form
                        .disabled(sending)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if sentFrom == nil && !writing {
                VStack(spacing: 2) {
                    if sending {
                        HStack(spacing: 10) {
                            ProgressView().tint(Palette.gold)
                            Text("Sending from \(draft.from)...")
                                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                                .foregroundStyle(Palette.inkDim)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.top, 14)
                    } else if !store.isSample && store.replyAccount(for: item) == nil {
                        // A reply goes only from the address this came to, and that one cannot send from here.
                        Text(store.replyOffLine(for: item))
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .padding(.top, 14)
                    } else if !store.isSample && heldForCheck {
                        // The warning above says the last send could not be confirmed. Send comes back only after this.
                        GoldButton(title: "I have checked Sent") {
                            Haptics.tap()
                            problem = nil
                            heldForCheck = false
                            swipeKey += 1
                        }
                        .padding(.top, 14)
                    } else if canSend {
                        SwipeUpToConfirm(title: "Swipe up to send", doneTitle: store.isSample ? "Sent" : "Check and send",
                                         symbol: "paperplane.fill") {
                            if store.isSample { send() } else { askToSend() }
                        }
                        .id(swipeKey)
                    } else {
                        Text("Add an address and a reply to send it.")
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .padding(.top, 14)
                    }
                    if !sending {
                        QuietButton(title: "Save as draft") {
                            store.saveDraft(draft)
                            Haptics.success()
                            onSaved()
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
                .background {
                    LinearGradient(colors: [Palette.ground.opacity(0), Palette.ground.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(Motion.sheet, value: writing)
        .animation(Motion.bouncy, value: sentFrom)
        .animation(Motion.snappy, value: problem)
        .animation(Motion.snappy, value: sending)
        .plannerNotice($notice)
        .interactiveDismissDisabled(sending)
        .onChange(of: confirming) {
            // Closed without Send (a tap outside): the swipe comes back.
            if !confirming && !sending && sentFrom == nil { swipeKey += 1 }
        }
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button("Send") { sendLive() }
            Button("Cancel", role: .cancel) { swipeKey += 1 }
        } message: {
            Text(confirmMessage)
        }
        .kSheet()
        .task { await start() }
    }

    // MARK: Paired sending

    private var recipients: [String] { MailWire.recipients(draft.to) ?? [] }

    private var confirmTitle: String {
        let count = recipients.count
        let who = count == 1 ? "1 person" : "\(count) people"
        return "Send to \(who) from \(draft.from)?"
    }

    private var confirmMessage: String {
        var text = recipients.joined(separator: ", ")
        if store.unconfirmedSends[item.id] != nil {
            text += "\n\nAn earlier send of this reply could not be confirmed. Check Sent in your mail app first, or it may arrive twice."
        }
        return text
    }

    /// The swipe only asks; the confirm that names who and from where sends.
    private func askToSend() {
        problem = nil
        if let why = store.sendProblem(draft, for: item) {
            Haptics.thud()
            problem = why
            swipeKey += 1
            return
        }
        confirming = true
    }

    /// Exactly one send per confirm. The answer always shows; nothing is sent again by itself.
    private func sendLive() {
        guard !sending, !heldForCheck else { return }
        let approved = draft
        inFlight = true
        Task {
            let outcome = await store.sendLive(approved, for: item)
            inFlight = false
            switch outcome {
            case .sent(let from):
                Haptics.success()
                problem = nil
                sentFrom = from
                onSent("Sent from \(from)")
            case .notSent(let why):
                Haptics.thud()
                problem = "Not sent. " + why
                swipeKey += 1
            case .unknown(let text):
                // Never shown as sent. The draft stays; Send waits until the person has read this.
                Haptics.thud()
                problem = text
                heldForCheck = true
            }
        }
    }

    private var unconfirmedLine: String? {
        guard problem == nil, let when = store.unconfirmedSends[item.id] else { return nil }
        let time = when.formatted(date: .omitted, time: .shortened)
        return "A send of this reply at \(time) could not be confirmed. Check Sent in your mail app before sending it again."
    }

    private var canSend: Bool {
        !draft.to.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.from.isEmpty
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.goldText)
                Text("Waits for your approval. Nothing is sent until you swipe up.")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let warning = problem ?? unconfirmedLine {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.top, 2)
                    Text(warning)
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.danger)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity)
            }

            if !store.isSample {
                Text("Kip does not draft replies on the phone yet. Write yours here.")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "From")
                if store.isSample {
                    fromMenu
                } else {
                    fromFixed
                }
            }
            PlannerTextField(label: "To", placeholder: "name@example.com", text: $draft.to)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
            PlannerTextField(label: "Subject", text: $draft.subject)
            PlannerTextField(label: "Reply", placeholder: "Write your reply", text: $draft.body, multiline: true)
        }
    }

    private var fromMenu: some View {
        Menu {
            ForEach(store.senders) { sender in
                let usable = store.isSample ? sender.canSend : sender.sendsFromPhone
                Button {
                    Haptics.select()
                    draft.from = sender.email
                } label: {
                    if sender.email == draft.from {
                        Label(sender.email, systemImage: "checkmark")
                    } else if usable {
                        Text(sender.email)
                    } else if !store.isSample && sender.via == .google {
                        Text("\(sender.email), sends only from your desktop")
                    } else {
                        Text("\(sender.email), needs permission to send")
                    }
                }
                .disabled(!usable)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "at")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                Text(draft.from.isEmpty ? "Choose an address" : draft.from)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .kCard(radius: 16)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("From: \(draft.from)")
    }

    /// Paired: a reply goes only from the address the message came to, so From is shown, not chosen.
    private var fromFixed: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "at")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                Text(draft.from.isEmpty ? "No address can send this reply" : draft.from)
                    .font(KFont.ui(16))
                    .foregroundStyle(draft.from.isEmpty ? Palette.inkFaint : Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .kCard(radius: 16)
            Text("A reply goes from the address this message came to.")
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func sentCard(_ from: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Palette.onGold)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom), in: Circle())
            Text("Sent from \(from)")
                .font(KFont.ui(18, .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(store.isSample ? "To \(item.address). It is off the Needs a reply list." : "To \(draft.to).")
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center)
            PlannerPill(title: "Done", style: .quiet) { dismiss() }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .kCard(radius: 24)
    }

    private func start() async {
        guard draft.itemID.isEmpty else { return }
        if startSent {
            draft = store.newDraft(for: item)
            sentFrom = draft.from
            writing = false
            return
        }
        if !store.isSample {
            // A send of this reply that could not be confirmed: Send waits until the person has checked Sent.
            heldForCheck = store.unconfirmedSends[item.id] != nil
        }
        if var saved = store.drafts[item.id] {
            if !store.isSample {
                // Paired, the reply goes only from the address this came to, whatever the saved draft says.
                saved.from = store.replySender(for: item)?.email ?? ""
            }
            draft = saved
            writing = false
            return
        }
        draft = store.newDraft(for: item)
        // Paired, nothing is drafted by Kip, so there is no writing pause.
        if !instant && store.isSample { try? await Task.sleep(for: .seconds(1.3)) }
        writing = false
    }

    private func send() {
        let approved = draft
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(Motion.snappy) { store.send(approved) }
            sentFrom = approved.from
            onSent("Sent from \(approved.from)")
        }
    }
}

// MARK: - Email accounts

/// Sending accounts, connected accounts and the connect form, in one sheet.
struct MailAccountsSheet: View {
    let store: MailStore
    var startConnecting = false
    var showMissingError = false

    @Environment(\.dismiss) private var dismiss
    @State private var connecting = false
    @State private var email = ""
    @State private var password = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var smtpHost = ""
    @State private var smtpPort = "465"
    @State private var formError: String?
    @State private var removing: MailAccount?
    @State private var notice: String?
    @State private var phoneNote: String?
    /// Paired: a removal that was refused or could not be confirmed.
    @State private var accountProblem: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PlannerSheetTitle(title: "Email accounts") {
                        if !store.accountBusy {
                            PlannerRoundButton(symbol: "xmark", label: "Close", size: 40) { dismiss() }
                        }
                    }

                    sendingCard(proxy)
                    accountsList
                    connectForm.id("connect")
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if startConnecting {
                    connecting = true
                    if showMissingError { formError = "Fill in email, password, and both host fields first" }
                    Task {
                        try? await Task.sleep(for: .seconds(0.3))
                        withAnimation(Motion.sheet) { proxy.scrollTo("connect", anchor: .top) }
                    }
                }
            }
        }
        .animation(Motion.snappy, value: connecting)
        .animation(Motion.snappy, value: store.accounts)
        .animation(Motion.snappy, value: phoneNote)
        .animation(Motion.snappy, value: accountProblem)
        .animation(Motion.snappy, value: store.accountBusy)
        .plannerNotice($notice)
        .interactiveDismissDisabled(store.accountBusy)
        .confirmationDialog("Remove this account?", isPresented: Binding(
            get: { removing != nil },
            set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible, presenting: removing) { account in
            Button("Remove account", role: .destructive) {
                if store.isSample {
                    withAnimation(Motion.snappy) { store.remove(account) }
                    Haptics.thud()
                    notice = "Account removed"
                } else {
                    removeLive(account)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text(store.isSample
                 ? "Kairos stops reading \(account.email). Your mail stays where it is."
                 : "Kairos on your desktop stops reading \(account.email) and deletes the password it saved. Your mail stays where it is.")
        }
        .kSheet()
    }

    // Sending accounts

    private func sendingCard(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Sending accounts")
            Text("Addresses your agents can send email from. Gmail and Google Workspace sign in with Google; other providers use the form below.")
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                if store.senders.isEmpty {
                    Text("No sending accounts yet.")
                        .font(KFont.ui(15))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                ForEach(Array(store.senders.enumerated()), id: \.element.id) { index, sender in
                    HStack(spacing: 12) {
                        Image(systemName: sender.via == .google ? "g.circle" : "envelope")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Palette.goldText)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sender.email).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(sender.detail)
                                .font(KFont.ui(13.5, relativeTo: .footnote))
                                .foregroundStyle(sender.canSend ? Palette.inkFaint : Palette.goldText)
                        }
                        Spacer(minLength: 8)
                        if !sender.canSend {
                            PlannerPill(title: "Allow sending", style: .outline) {
                                phoneNote = "Sign in to Google on the computer running Kairos to allow sending from \(sender.email)."
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 62)
                    .overlay(alignment: .bottom) {
                        if index < store.senders.count - 1 { Palette.line.frame(height: 1).padding(.leading, 54) }
                    }
                }
            }
            .kCard(radius: 20)

            if let phoneNote {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.goldText)
                        .padding(.top, 2)
                    Text(phoneNote)
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity)
            }

            HStack(spacing: 8) {
                PlannerPill(title: "Add Google account", symbol: "plus", style: .quiet) {
                    phoneNote = !store.isSample && !store.googleConfigured
                        ? "Google needs a one-time setup in Library on the computer running Kairos. Then add the account there and it shows up here."
                        : "Google sign-in happens on the computer running Kairos. Add the account there and it shows up here."
                }
                PlannerPill(title: "Other provider", style: .quiet) {
                    connecting = true
                    Task {
                        try? await Task.sleep(for: .seconds(0.2))
                        withAnimation(Motion.sheet) { proxy.scrollTo("connect", anchor: .top) }
                    }
                }
            }
        }
    }

    // Connected accounts

    private var accountsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Connected accounts")
            if let accountProblem {
                Text(accountProblem)
                    .font(KFont.ui(14, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if store.accounts.isEmpty {
                PlannerEmpty(title: "No accounts connected",
                             hint: "Connect an account so Kairos can read your mail and flag what matters.",
                             pose: .idle,
                             actionTitle: "Connect an account") { connecting = true }
            } else {
                ForEach(store.accounts) { account in
                    accountCard(account)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
    }

    private func accountCard(_ account: MailAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "tray.full")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 40, height: 40)
                    .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(account.hosts).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                Spacer(minLength: 0)
                PlannerRoundButton(symbol: "trash", label: "Remove account", size: 40, tint: Palette.danger) {
                    removing = account
                }
                .disabled(store.accountBusy)
            }
            HStack(spacing: 10) {
                if store.testing.contains(account.id) {
                    HStack(spacing: 8) {
                        ProgressView().tint(Palette.gold)
                        Text("Testing...").font(KFont.ui(15, .medium)).foregroundStyle(Palette.inkDim)
                    }
                    .frame(minHeight: 44)
                } else {
                    PlannerPill(title: "Test connection", style: .quiet) {
                        Task {
                            let ok = await store.test(account)
                            if ok { Haptics.success() } else { Haptics.thud() }
                            notice = ok ? "Connection works" : "Test failed"
                        }
                    }
                }
                if let result = store.testResults[account.id] {
                    TonePill(text: result.text, tone: result.ok ? .success : .danger,
                             symbol: result.ok ? "checkmark" : "exclamationmark.triangle.fill")
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .kCard(radius: 20)
        .animation(Motion.snappy, value: store.testing)
        .animation(Motion.snappy, value: store.testResults)
    }

    // Connect form

    private var connectForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Haptics.tap()
                connecting.toggle()
            } label: {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.goldText)
                        .rotationEffect(.degrees(connecting ? 45 : 0))
                    Text("Connect an account")
                        .font(KFont.ui(17, .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(connecting ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .accessibilityAddTraits(connecting ? .isSelected : [])

            if connecting {
                VStack(alignment: .leading, spacing: 12) {
                    PlannerTextField(label: "Email address", placeholder: "name@example.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    secureField
                    HStack(alignment: .top, spacing: 10) {
                        PlannerTextField(label: "IMAP host", placeholder: "imap.example.com", text: $imapHost)
                        PlannerTextField(label: "Port", text: $imapPort)
                            .keyboardType(.numberPad)
                            .frame(width: 92)
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    HStack(alignment: .top, spacing: 10) {
                        PlannerTextField(label: "SMTP host", placeholder: "smtp.example.com", text: $smtpHost)
                        PlannerTextField(label: "Port", text: $smtpPort)
                            .keyboardType(.numberPad)
                            .frame(width: 92)
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    if let formError {
                        Text(formError)
                            .font(KFont.ui(14, .medium, relativeTo: .footnote))
                            .foregroundStyle(Palette.danger)
                            .transition(.opacity)
                    }
                    if store.accountBusy {
                        HStack(spacing: 10) {
                            ProgressView().tint(Palette.gold)
                            Text("Waiting for your desktop...")
                                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                                .foregroundStyle(Palette.inkDim)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .padding(.top, 4)
                    } else {
                        GoldButton(title: "Add Account", action: add)
                            .padding(.top, 4)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .kCard(radius: 22)
        .onChange(of: email) { formError = nil }
        .onChange(of: password) { formError = nil }
        .onChange(of: imapHost) { formError = nil }
        .onChange(of: smtpHost) { formError = nil }
    }

    private var secureField: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Password")
            SecureField("Password", text: $password, prompt: Text("App password").foregroundStyle(Palette.inkFaint))
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .textContentType(.password)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .kCard(radius: 16)
        }
    }

    private func add() {
        let address = email.trimmingCharacters(in: .whitespaces)
        let imap = imapHost.trimmingCharacters(in: .whitespaces)
        let smtp = smtpHost.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty, !password.isEmpty, !imap.isEmpty, !smtp.isEmpty else {
            Haptics.thud()
            withAnimation(Motion.snappy) { formError = "Fill in email, password, and both host fields first" }
            return
        }
        guard store.isSample else {
            addLive(address: address, imap: imap, smtp: smtp)
            return
        }
        let account = MailAccount(email: address, imapHost: imap, imapPort: Int(imapPort) ?? 993,
                                  smtpHost: smtp, smtpPort: Int(smtpPort) ?? 465)
        withAnimation(Motion.snappy) { store.addAccount(account) }
        // Clear the address, password and hosts; keep the ports.
        email = ""
        password = ""
        imapHost = ""
        smtpHost = ""
        formError = nil
        Haptics.success()
        notice = "Account added"
    }

    // Paired

    /// Add the account on the desktop. What was typed stays until the desktop confirms it.
    private func addLive(address: String, imap: String, smtp: String) {
        guard !store.accountBusy else { return }
        let typedPassword = password
        let imapNumber = Int(imapPort) ?? 993
        let smtpNumber = Int(smtpPort) ?? 465
        formError = nil
        Task {
            let outcome = await store.addAccountLive(email: address, password: typedPassword, imapHost: imap, imapPort: imapNumber,
                                                     smtpHost: smtp, smtpPort: smtpNumber)
            switch outcome {
            case .done(let text):
                if email.trimmingCharacters(in: .whitespaces) == address {
                    // Clear the address, password and hosts; keep the ports.
                    email = ""
                    password = ""
                    imapHost = ""
                    smtpHost = ""
                }
                formError = nil
                Haptics.success()
                notice = text
            case .failed(let why):
                Haptics.thud()
                withAnimation(Motion.snappy) { formError = "Not added. " + why }
            case .unknown(let text):
                Haptics.thud()
                withAnimation(Motion.snappy) { formError = text }
            }
        }
    }

    /// Remove the account on the desktop, after the confirm above.
    private func removeLive(_ account: MailAccount) {
        guard !store.accountBusy else { return }
        accountProblem = nil
        Task {
            let outcome = await store.removeAccountLive(account)
            switch outcome {
            case .done(let text):
                Haptics.thud()
                notice = text
            case .failed(let why):
                Haptics.thud()
                accountProblem = "Not removed. " + why
            case .unknown(let text):
                Haptics.thud()
                accountProblem = text
            }
        }
    }
}
