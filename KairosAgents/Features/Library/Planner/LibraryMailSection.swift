import SwiftUI

/// The Mail section of Library. Mail on the phone is triage, not an inbox:
/// what matters today, what needs a reply (Kip drafts it, you swipe up to send), and your accounts.
struct LibraryMailSection: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var store = MailStore.shared
    @State private var sheet: MailSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.readyToShow {
                summary.arrives(0)
                if !store.isSample, let note = store.liveNote {
                    MailLiveLine(text: note)
                        .transition(.opacity)
                }
                searchPill.arrives(1)

                if store.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    lists
                } else {
                    searchResults
                }

                Button { sheet = .accounts(connect: false, error: false) } label: {
                    GroupRow(title: "Email accounts", symbol: "at", value: "\(store.accounts.count + store.googleSenders.count)", last: true)
                }
                .buttonStyle(PressStyle(scale: 0.99))
                .kCard(radius: 20)
                .padding(.top, 4)
                .arrives(4)
            } else {
                // Paired, and the desktop's mail has not been read yet: never the sample mail.
                waiting.arrives(0)
            }
        }
        .padding(.bottom, 8)
        .animation(Motion.snappy, value: store.items)
        .animation(Motion.snappy, value: store.refreshing)
        .animation(Motion.snappy, value: store.error)
        .sheet(item: $sheet) { current in
            sheetContent(current)
                .environment(router)
                .environment(chrome)
        }
        .animation(Motion.snappy, value: store.liveNote)
        .animation(Motion.snappy, value: store.liveLoad)
        .task(id: MailStore.connectionKey) {
            store.followConnection()
            await store.loadLive()
        }
        .onAppear(perform: applyDebugState)
        .onChange(of: chrome.addTick) {
            if router.tab == .library { refresh() }
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Mascot(pose: store.needsReply.isEmpty ? .idle : .needs, size: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Important today")
                        .font(KFont.ui(19, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    Text(store.checkedLine)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 4)
                PlannerRoundButton(symbol: "person.crop.circle.badge.plus", label: "Email accounts", size: 44) {
                    sheet = .accounts(connect: false, error: false)
                }
            }

            if store.lastChecked != nil {
                HStack(spacing: 10) {
                    PlannerStat(value: "\(store.scanned)", label: "Unread scanned")
                    PlannerStat(value: "\(store.items.count)", label: "Important", tone: store.items.isEmpty ? nil : .gold)
                }
            }

            if let error = store.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.top, 2)
                    Text(error)
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.danger)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity)
            }

            if store.refreshing {
                HStack(spacing: 10) {
                    ProgressView().tint(Palette.gold)
                    Text("Reading your inbox...")
                        .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .transition(.opacity)
            } else {
                PlannerPill(title: "Refresh now", symbol: "arrow.clockwise", style: .quiet, expand: true, action: refresh)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .kCard(radius: 24, raised: true)
    }

    // MARK: Waiting for the desktop

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Mascot(pose: .thinking, size: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Important today")
                        .font(KFont.ui(19, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    Text("Your mail comes from your desktop.")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }
            if case .failed(let text) = store.liveLoad {
                MailLiveLine(text: text, symbol: "exclamationmark.triangle", retry: {
                    Task { await store.loadLive() }
                })
                .transition(.opacity)
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(Palette.gold)
                    Text("Reading your desktop...")
                        .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .transition(.opacity)
            }
        }
        .padding(16)
        .kCard(radius: 24, raised: true)
    }

    // MARK: Search

    private var searchPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.inkFaint)
            TextField("Search mail and accounts", text: $store.query,
                      prompt: Text("Search mail and accounts").foregroundStyle(Palette.inkFaint))
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !store.query.isEmpty {
                Button {
                    Haptics.tap()
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, store.query.isEmpty ? 16 : 0)
        .frame(minHeight: 48)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            let items = store.filtered
            let accounts = store.matchingAccounts
            if items.isEmpty && accounts.isEmpty {
                Text("No matches for \"\(store.query)\"")
                    .font(KFont.ui(15))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .transition(.opacity)
            }
            if !items.isEmpty {
                itemCard(items)
            }
            if !accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Accounts")
                    VStack(spacing: 0) {
                        ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                            Button { sheet = .accounts(connect: false, error: false) } label: {
                                GroupRow(title: account.email, symbol: "tray.full", last: index == accounts.count - 1)
                            }
                            .buttonStyle(PressStyle(scale: 0.99))
                        }
                    }
                    .kCard(radius: 20)
                }
            }
        }
    }

    // MARK: Lists

    @ViewBuilder
    private var lists: some View {
        if store.items.isEmpty && !store.refreshing {
            if store.lastChecked == nil {
                PlannerEmpty(title: "Your inbox, with room to think",
                             hint: "Run triage to see what needs you.",
                             pose: .idle,
                             actionTitle: "Refresh now", action: refresh)
                    .arrives(2)
            } else {
                PlannerEmpty(title: "Nothing needs your attention",
                             hint: "Nothing important in the last day.",
                             pose: .sleeping,
                             actionTitle: "Refresh now", action: refresh)
                    .arrives(2)
            }
        } else {
            if !store.needsReply.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    PlannerHeading(title: "Needs a reply")
                    itemCard(store.needsReply)
                }
                .arrives(2)
            }
            if !store.alsoImportant.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    PlannerHeading(title: store.needsReply.isEmpty ? "Important" : "Also important")
                    itemCard(store.alsoImportant)
                }
                .arrives(3)
            }
        }
    }

    private func itemCard(_ items: [MailItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button { open(item) } label: {
                    MailRow(item: item, hasDraft: store.drafts[item.id] != nil,
                            replied: store.sentIDs.contains(item.id),
                            unconfirmed: store.unconfirmedSends[item.id] != nil,
                            last: index == items.count - 1)
                }
                .buttonStyle(PressStyle(scale: 0.99))
                .contextMenu {
                    // Paired, replying is off when the address this came to cannot send from the phone.
                    if store.isSample || store.drafts[item.id] != nil || store.replyAccount(for: item) != nil {
                        Button { sheet = .draft(item, instant: false, sent: false) } label: {
                            Label(store.drafts[item.id] == nil ? (store.isSample ? "Draft a reply" : "Write a reply") : "Open the draft",
                                  systemImage: "square.and.pencil")
                        }
                    }
                    // Handled is kept on this iPhone only; paired, the next read would bring it back, so it is not offered.
                    if store.isSample {
                        Button { handled(item) } label: {
                            Label("Mark as handled", systemImage: "checkmark.circle")
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .kCard(radius: 20)
    }

    // MARK: Actions

    private func open(_ item: MailItem) {
        Haptics.tap()
        if store.drafts[item.id] != nil {
            sheet = .draft(item, instant: true, sent: false)
        } else {
            sheet = .message(item)
        }
    }

    private func handled(_ item: MailItem) {
        Haptics.success()
        withAnimation(Motion.snappy) { store.markHandled(item.id) }
        chrome.say("Marked as handled")
    }

    private func refresh() {
        guard !store.refreshing, store.readyToShow else { return }
        Haptics.tap()
        Task {
            let summary = await store.refresh()
            guard !summary.isEmpty else { return }
            Haptics.success()
            chrome.say(summary)
        }
    }

    @ViewBuilder
    private func sheetContent(_ current: MailSheet) -> some View {
        switch current {
        case .message(let item):
            MailMessageSheet(
                item: item, store: store,
                onDraft: { sheet = .draft(item, instant: false, sent: false) },
                onHandled: {
                    sheet = nil
                    handled(item)
                }
            )
        case .draft(let item, let instant, let sent):
            MailDraftSheet(item: item, store: store, instant: instant, startSent: sent,
                           onSent: { chrome.say($0) },
                           onSaved: { chrome.say("Draft saved. It waits for you here.") })
        case .accounts(let connect, let error):
            MailAccountsSheet(store: store, startConnecting: connect, showMissingError: error)
        }
    }

    // MARK: Debug pictures

    private func applyDebugState() {
        guard let name = router.debugScreen, name.hasPrefix("mail-"), !store.debugApplied else { return }
        store.debugApplied = true
        let first = store.needsReply.first ?? store.items.first
        switch name {
        case "mail-message":
            if let first { sheet = .message(first) }
        case "mail-draft":
            if let first { sheet = .draft(first, instant: true, sent: false) }
        case "mail-sent":
            if let first { sheet = .draft(first, instant: true, sent: true) }
        case "mail-accounts":
            sheet = .accounts(connect: false, error: false)
        case "mail-connect":
            sheet = .accounts(connect: true, error: true)
        case "mail-empty":
            store.showEmptyRun()
        case "mail-first":
            store.showFirstRun()
        case "mail-error":
            store.showError()
        case "mail-search":
            store.query = "invoice"
        default:
            break
        }
    }
}

/// One flagged message in the triage list.
struct MailRow: View {
    let item: MailItem
    var hasDraft = false
    /// Paired: the desktop confirmed a reply sent from this iPhone.
    var replied = false
    /// Paired: a reply was sent with no answer. Check Sent before sending again.
    var unconfirmed = false
    var last = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MailAvatar(item: item)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.subjectLine)
                        .font(KFont.ui(16, .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.time)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                }
                Text(item.sender)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(1)
                Text(item.reason)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if unconfirmed {
                    TonePill(text: "Send not confirmed", tone: .danger, symbol: "exclamationmark.triangle.fill")
                        .padding(.top, 3)
                } else if hasDraft {
                    TonePill(text: "Draft waiting", tone: .gold, symbol: "square.and.pencil")
                        .padding(.top, 3)
                } else if replied {
                    TonePill(text: "Replied from this iPhone", tone: .success, symbol: "checkmark")
                        .padding(.top, 3)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 68) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(hasDraft ? "Opens the draft" : "Opens the message")
    }
}

/// The sheets Mail can show. One at a time; changing it swaps the sheet.
enum MailSheet: Identifiable {
    case message(MailItem)
    case draft(MailItem, instant: Bool, sent: Bool)
    case accounts(connect: Bool, error: Bool)

    var id: String {
        switch self {
        case .message(let item): "message-\(item.id)"
        case .draft(let item, _, let sent): "draft-\(item.id)-\(sent)"
        case .accounts: "accounts"
        }
    }
}
